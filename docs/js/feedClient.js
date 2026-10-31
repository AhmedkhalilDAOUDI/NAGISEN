import { useState, useEffect, uid } from "./lib.js";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "../config.js";

// The same Supabase project, tables and storage paths as the iPhone app, so both share one Feed.
const BUCKET = "post-media";
const PROFILE = "username, avatar_path, border_tier, bio, special_border";
export const POST_FIELDS = `id, author_id, body, media_path, media_kind, poster_path, created_at, pinned_at,
  profiles!posts_author_id_fkey(${PROFILE}), comments(count), likes:appreciations(count), mine:appreciations(member_id)`;
export const COMMENT_FIELDS = `id, post_id, author_id, body, created_at, profiles!comments_author_id_fkey(${PROFILE})`;
export const PAGE = 20;
export const REPORT_REASONS = ["Spam", "Harassment or hate", "Sexual or violent content", "Something else"];

let clientPromise = null;
/** Set when a password-reset link signed the member in, so Feed asks for a new password. */
export let recovering = false;
export const doneRecovering = () => { recovering = false; };
/** Loads supabase-js only when Feed is opened, so the rest of the app stays light. */
export function client() {
  clientPromise ??= new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = "vendor/supabase.js";
    script.onload = async () => {
      const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { detectSessionInUrl: false } });
      // Finish a sign-in or password-reset link that opened the site (kept aside by main.js).
      const pending = new URLSearchParams(sessionStorage.getItem("nagisen.authHash") || "");
      sessionStorage.removeItem("nagisen.authHash");
      if (pending.get("access_token") && pending.get("refresh_token")) {
        await supabase.auth.setSession({ access_token: pending.get("access_token"), refresh_token: pending.get("refresh_token") });
        if (pending.get("type") === "recovery") recovering = true;
      }
      resolve(supabase);
    };
    script.onerror = () => { clientPromise = null; reject(new Error("Feed couldn't load. Check your connection.")); };
    document.head.appendChild(script);
  });
  return clientPromise;
}

export const mediaURL = (path) => (path ? `${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/${path}` : null);
export const folder = (userID) => userID.toLowerCase();

/** A post row, shaped the way the views read it. */
export function asPost(row) {
  const p = row.profiles || {};
  return {
    id: row.id, authorID: row.author_id, body: row.body || "", mediaPath: row.media_path, mediaKind: row.media_kind,
    posterPath: row.poster_path, createdAt: row.created_at, pinnedAt: row.pinned_at,
    author: { id: row.author_id, username: p.username || "member", avatarPath: p.avatar_path, tier: p.border_tier || 0, bio: p.bio || "", special: p.special_border },
    comments: row.comments?.[0]?.count || 0, likes: row.likes?.[0]?.count || 0, liked: (row.mine || []).length > 0,
  };
}

export const asComment = (row) => ({
  id: row.id, postID: row.post_id, authorID: row.author_id, body: row.body, createdAt: row.created_at,
  author: { id: row.author_id, username: row.profiles?.username || "member", avatarPath: row.profiles?.avatar_path,
    tier: row.profiles?.border_tier || 0, special: row.profiles?.special_border },
});

/** Plain words for what went wrong; nothing for a load that was simply cancelled. */
export function describe(error, doing) {
  if (!error || error.name === "AbortError") return null;
  const m = error.message || String(error);
  if (/Invalid login credentials/i.test(m)) return "That email and password don't match.";
  if (/Email not confirmed/i.test(m)) return "Confirm your email first, using the link we sent.";
  if (/already registered|already exists/i.test(m)) return "An account with that email already exists. Sign in instead.";
  if (/Failed to fetch|NetworkError/i.test(m)) return `You're offline. Couldn't ${doing}.`;
  if (error.code === "23505") return "That username is taken. Try another.";
  if (error.code === "23514") return "Use 1 to 30 letters, numbers, periods or underscores.";
  return `Couldn't ${doing}. ${m}`;
}

/** Shrinks a photo to at most 1600 px on its long side, as a JPEG, before upload. */
export async function compress(file, max = 1600) {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, max / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  return new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85));
}

export async function uploadMedia(supabase, userID, file, prefix = "") {
  const video = file.type.startsWith("video/");
  if (video && file.size > 50 * 1024 * 1024) throw new Error("Videos can be up to 50 MB.");
  const body = video ? file : await compress(file);
  const path = `${folder(userID)}/${prefix}${uid().toLowerCase()}.${video ? "mp4" : "jpg"}`;
  const { error } = await supabase.storage.from(BUCKET).upload(path, body, { contentType: video ? file.type || "video/mp4" : "image/jpeg" });
  if (error) throw error;
  return { path, kind: video ? "video" : "photo" };
}

/** The signed-in member and their profile; `state` is loading, signedOut, needsUsername or ready. */
export function useSession() {
  const [session, setSession] = useState({ state: "loading" });
  useEffect(() => {
    let alive = true, sub;
    client().then(async (supabase) => {
      const refresh = async (user) => {
        if (!user) return alive && setSession({ state: "signedOut", supabase });
        const { data: profile } = await supabase.from("profiles").select(`id, ${PROFILE}`).eq("id", user.id).maybeSingle();
        const { data: follows } = await supabase.from("follows").select("followee_id").eq("follower_id", user.id);
        alive && setSession({ state: profile ? "ready" : "needsUsername", supabase, user, profile,
          following: new Set((follows || []).map((f) => f.followee_id)), reload: () => refresh(user) });
      };
      const { data } = await supabase.auth.getSession();
      await refresh(data.session?.user);
      sub = supabase.auth.onAuthStateChange((event, s) => { if (event !== "INITIAL_SESSION" && event !== "TOKEN_REFRESHED") refresh(s?.user); }).data.subscription;
    }).catch((e) => alive && setSession({ state: "error", message: e.message }));
    return () => { alive = false; sub?.unsubscribe(); };
  }, []);
  return session;
}
