import { html, useState, useEffect, relativeTime } from "./lib.js";
import { Sheet, Icon, Avatar, MemberName, Menu, confirmDialog } from "./ui.js";
import { POST_FIELDS, COMMENT_FIELDS, asPost, asComment, mediaURL, describe, uploadMedia, folder, REPORT_REASONS } from "./feedClient.js";

const validUsername = (n) => /^[\p{L}\p{N}_.]{1,30}$/u.test(n);

export function SignIn({ supabase, onClose }) {
  const [mode, setMode] = useState("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState(null);
  const [busy, setBusy] = useState(false);
  const submit = async (e) => {
    e.preventDefault();
    setBusy(true); setMessage(null);
    const { data, error } = mode === "signin"
      ? await supabase.auth.signInWithPassword({ email: email.trim(), password })
      : await supabase.auth.signUp({ email: email.trim(), password, options: { emailRedirectTo: location.origin + location.pathname } });
    setBusy(false);
    if (error) return setMessage(describe(error, mode === "signin" ? "sign in" : "create the account"));
    if (mode === "signup" && !data.session) return setMessage("Check your inbox and confirm your email, then sign in here.");
    onClose();
  };
  return html`
    <${Sheet} title=${mode === "signin" ? "Sign in" : "Create account"} onClose=${onClose}>
      <form class="stack" onSubmit=${submit}>
        <div class="panel tight list">
          <input class="plain-input" type="email" autocomplete="email" placeholder="Email" value=${email} onInput=${(e) => setEmail(e.target.value)} aria-label="Email" />
          <input class="plain-input" type="password" autocomplete=${mode === "signin" ? "current-password" : "new-password"}
            placeholder=${mode === "signin" ? "Password" : "Password (8+ characters)"} value=${password} onInput=${(e) => setPassword(e.target.value)} aria-label="Password" />
        </div>
        <button class="primary" disabled=${busy || !email.includes("@") || password.length < (mode === "signup" ? 8 : 1)}>
          ${busy ? "One moment…" : mode === "signin" ? "Sign in" : "Create account"}</button>
        ${message && html`<p class="accent small" style="margin:0">${message}</p>`}
        <button type="button" class="link" onClick=${() => { setMode(mode === "signin" ? "signup" : "signin"); setMessage(null); }}>
          ${mode === "signin" ? "New here? Create an account" : "Already have an account? Sign in"}</button>
      </form>
    <//>`;
}

export function ChooseUsername({ session }) {
  const [name, setName] = useState("");
  const [message, setMessage] = useState(null);
  const save = async () => {
    const { error } = await session.supabase.from("profiles").insert({ id: session.user.id, username: name.trim() });
    error ? setMessage(describe(error, "save the username")) : session.reload();
  };
  return html`
    <div class="screen">
      <div class="heading"><div class="kicker">NAGISEN</div><h1>Choose a username</h1>
        <div class="muted">Up to 30 letters, numbers, periods or underscores. It is shown with every post.</div></div>
      <div class="panel tight"><input class="plain-input" placeholder="Username" value=${name} autocapitalize="none" autocorrect="off"
        onInput=${(e) => setName(e.target.value)} aria-label="Username" /></div>
      <button class="primary" disabled=${!validUsername(name.trim())} onClick=${save}>Continue</button>
      ${message && html`<p class="accent small">${message}</p>`}
      <button class="link" onClick=${() => session.supabase.auth.signOut()}>Sign out</button>
    </div>`;
}

export function Composer({ session, onClose, onPosted }) {
  const [text, setText] = useState("");
  const [file, setFile] = useState(null);
  const [preview, setPreview] = useState(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);
  useEffect(() => () => preview && URL.revokeObjectURL(preview), [preview]);
  const pick = (f) => { if (!f) return; setFile(f); setPreview(URL.createObjectURL(f)); };
  const can = (text.trim() || file) && text.length <= 1000 && !busy;
  const share = async () => {
    setBusy(true); setMessage(null);
    let uploaded = null;
    try {
      if (file) uploaded = await uploadMedia(session.supabase, session.user.id, file);
      const { error } = await session.supabase.from("posts").insert({ author_id: session.user.id, body: text.trim(),
        media_path: uploaded?.path ?? null, media_kind: uploaded?.kind ?? null, poster_path: null });
      if (error) throw error;
      onPosted();
    } catch (e) {
      if (uploaded) await session.supabase.storage.from("post-media").remove([uploaded.path]);
      setMessage(describe(e, "share the post")); setBusy(false);
    }
  };
  const p = session.profile;
  return html`
    <${Sheet} title="New post" onClose=${onClose} action=${share} actionLabel="Share" actionEnabled=${!!can} busy=${busy}>
      <div class="row"><${Avatar} url=${mediaURL(p.avatar_path)} name=${p.username} tier=${p.border_tier} special=${p.special_border} size=${36} />
        <div><${MemberName} name=${p.username} special=${p.special_border} /><div class="caption">Shared with NAGISEN members</div></div></div>
      <textarea class="plain-input serif" rows="6" placeholder="What did you do today?" style="font-size:19px;line-height:1.45"
        value=${text} onInput=${(e) => setText(e.target.value)} aria-label="Post text" />
      <div class="row"><hr class="divider grow" /><span class="caption">${text.length} / 1,000</span></div>
      ${preview ? html`
        <div class="stack" style="gap:8px">
          ${file.type.startsWith("video/") ? html`<video src=${preview} controls playsinline style="width:100%;border-radius:18px" />`
            : html`<img src=${preview} alt="" style="width:100%;border-radius:18px" />`}
          <button class="small muted row" style="gap:6px" onClick=${() => { setFile(null); setPreview(null); }}><${Icon} name="x" size="sm" />Remove</button>
        </div>` : html`
        <label class="panel row" style="cursor:pointer">
          <span class="icon-btn accent"><${Icon} name="photo" size="sm" /></span>
          <span class="grow"><span style="display:block">Add a photo or video</span><span class="caption">One photo, or a video up to 50 MB</span></span>
          <input type="file" accept="image/*,video/mp4,video/quicktime" class="hidden" onChange=${(e) => pick(e.target.files[0])} />
        </label>`}
      ${message && html`<p class="accent small">${message}</p>`}
    <//>`;
}

export function EditPost({ session, post, onClose, onSaved }) {
  const [text, setText] = useState(post.body);
  const [message, setMessage] = useState(null);
  const trimmed = text.trim();
  const can = trimmed !== post.body && trimmed.length <= 1000 && (trimmed || post.mediaPath);
  const save = async () => {
    const { error } = await session.supabase.from("posts").update({ body: trimmed }).eq("id", post.id);
    error ? setMessage(describe(error, "save the post")) : onSaved(trimmed);
  };
  return html`
    <${Sheet} title="Edit post" onClose=${onClose} action=${save} actionLabel="Save" actionEnabled=${!!can}>
      <textarea class="plain-input serif" rows="8" style="font-size:19px;line-height:1.45" value=${text} onInput=${(e) => setText(e.target.value)} aria-label="Post text" />
      ${post.mediaPath && html`<div class="caption">The ${post.mediaKind === "video" ? "video" : "photo"} stays as posted.</div>`}
      ${message && html`<p class="accent small">${message}</p>`}
    <//>`;
}

export function Comments({ session, post, onClose, onCount }) {
  const { supabase, user, profile } = session;
  const [comments, setComments] = useState(null);
  const [text, setText] = useState("");
  const [message, setMessage] = useState(null);
  useEffect(() => {
    supabase.from("comments").select(COMMENT_FIELDS).eq("post_id", post.id).order("created_at").limit(200)
      .then(({ data, error }) => (error ? setMessage(describe(error, "load the comments")) : setComments(data.map(asComment))));
  }, []);
  const set = (list) => { setComments(list); onCount(list.length); };
  const send = async (e) => {
    e.preventDefault();
    const { data, error } = await supabase.from("comments").insert({ post_id: post.id, author_id: user.id, body: text.trim() }).select(COMMENT_FIELDS).single();
    if (error) return setMessage(describe(error, "add the comment"));
    set([...comments, asComment(data)]); setText("");
  };
  const del = (c) => confirmDialog({ title: "Delete this comment?", actions: [{ title: "Delete comment", destructive: true, run: async () => {
    const { error } = await supabase.from("comments").delete().eq("id", c.id);
    error ? setMessage(describe(error, "delete the comment")) : set(comments.filter((x) => x.id !== c.id));
  } }] });
  const report = (c) => confirmDialog({ title: "Why are you reporting this comment?", message: "The comment will be hidden for you and sent for review.",
    actions: REPORT_REASONS.map((reason) => ({ title: reason, run: async () => { set(comments.filter((x) => x.id !== c.id)); await supabase.from("reports").insert({ comment_id: c.id, reason }); } })) });
  return html`
    <${Sheet} title="Comments" onClose=${onClose}>
      <div class="stack" style="gap:14px">
        <div class="row"><${Avatar} url=${mediaURL(post.author.avatarPath)} name=${post.author.username} tier=${post.author.tier} special=${post.author.special} size=${30} />
          <${MemberName} name=${post.author.username} special=${post.author.special} /><span class="caption">${relativeTime(post.createdAt)}</span></div>
        ${post.body ? html`<div class="serif" style="font-size:19px;white-space:pre-wrap">${post.body}</div>` : html`<div class="muted">A ${post.mediaKind === "video" ? "video" : "photo"}</div>`}
        <div class="row"><span class="kicker">${comments?.length ? `${comments.length} ${comments.length === 1 ? "comment" : "comments"}` : "The thread"}</span><hr class="divider grow" /></div>
      </div>
      ${comments === null && !message && html`<p class="muted">Loading…</p>`}
      ${comments?.length === 0 && html`<div><div class="serif" style="font-size:21px">No comments yet</div><div class="muted">Say something kind to start the conversation.</div></div>`}
      ${comments?.map((c) => {
        const mine = c.authorID === user.id;
        const acts = [...(mine || post.authorID === user.id ? [{ title: "Delete comment", icon: "trash", destructive: true, run: () => del(c) }] : []),
          ...(!mine ? [{ title: "Report comment", icon: "flag", run: () => report(c) }] : [])];
        return html`
          <div class="row" style="align-items:flex-start">
            <${Avatar} url=${mediaURL(c.author.avatarPath)} name=${c.author.username} tier=${c.author.tier} special=${c.author.special} size=${34} />
            <div class="grow"><div class="row" style="gap:8px"><${MemberName} name=${c.author.username} special=${c.author.special} cls="small" />
              <span class="caption">${relativeTime(c.createdAt)}</span></div><div style="white-space:pre-wrap">${c.body}</div></div>
            <${Menu} title="Comment" actions=${acts} />
          </div>`;
      })}
      ${message && html`<p class="accent small">${message}</p>`}
      <form class="row" style="position:sticky;bottom:calc(env(safe-area-inset-bottom) + 10px)" onSubmit=${send}>
        <${Avatar} url=${mediaURL(profile.avatar_path)} name=${profile.username} tier=${profile.border_tier} special=${profile.special_border} size=${32} />
        <input class="field grow" style="background:var(--surface)" placeholder="Add a comment…" maxlength="500" value=${text}
          onInput=${(e) => setText(e.target.value)} aria-label="Comment" />
        <button class="icon-btn" style="background:var(--accent);color:#fff;border:0" disabled=${!text.trim()} aria-label="Send comment"><${Icon} name="send" size="sm" /></button>
      </form>
    <//>`;
}

export function MemberPage({ session, author, onClose, onAccount, actions }) {
  const { supabase, user } = session;
  const me = author.id === user.id;
  const [posts, setPosts] = useState(null);
  const [counts, setCounts] = useState({ posts: 0, followers: 0, following: 0 });
  const [follows, setFollows] = useState(session.following.has(author.id));
  const [bio, setBio] = useState(author.bio || "");
  useEffect(() => {
    supabase.from("posts").select(POST_FIELDS).eq("mine.member_id", user.id).eq("author_id", author.id)
      .order("pinned_at", { ascending: false, nullsFirst: false }).order("created_at", { ascending: false }).limit(60)
      .then(({ data }) => setPosts((data || []).map(asPost)));
    const count = (q) => q.then(({ count }) => count || 0);
    Promise.all([
      count(supabase.from("posts").select("id", { count: "exact", head: true }).eq("author_id", author.id)),
      count(supabase.from("follows").select("follower_id", { count: "exact", head: true }).eq("followee_id", author.id)),
      count(supabase.from("follows").select("followee_id", { count: "exact", head: true }).eq("follower_id", author.id)),
    ]).then(([p, f, g]) => setCounts({ posts: p, followers: f, following: g }));
    supabase.from("profiles").select("bio").eq("id", author.id).maybeSingle().then(({ data }) => data && setBio(data.bio || ""));
  }, []);
  const toggleFollow = async () => {
    const next = !follows;
    setFollows(next); setCounts((c) => ({ ...c, followers: c.followers + (next ? 1 : -1) }));
    next ? session.following.add(author.id) : session.following.delete(author.id);
    const { error } = next
      ? await supabase.from("follows").upsert({ followee_id: author.id }, { onConflict: "follower_id,followee_id" })
      : await supabase.from("follows").delete().eq("follower_id", user.id).eq("followee_id", author.id);
    if (error) { setFollows(!next); next ? session.following.delete(author.id) : session.following.add(author.id); }
  };
  const stat = (n, label) => html`<div class="center"><div class="serif" style="font-size:22px">${n}</div><div class="caption">${label}</div></div>`;
  return html`
    <${Sheet} title=${author.username} onClose=${onClose} extra=${!me && html`<${Menu} title=${`@${author.username}`}
      actions=${[{ title: `Block @${author.username}`, icon: "hand", destructive: true, run: () => { actions.block({ authorID: author.id, author }); onClose(); } }]} />`}>
      <div class="row" style="gap:18px">
        <${Avatar} url=${mediaURL(author.avatarPath)} name=${author.username} tier=${author.tier} special=${author.special} size=${86} />
        <div class="grow" style="display:grid;grid-template-columns:repeat(3,1fr)">
          ${stat(counts.posts, "posts")}${stat(counts.followers, counts.followers === 1 ? "follower" : "followers")}${stat(counts.following, "following")}</div>
      </div>
      <div><${MemberName} name=${author.username} special=${author.special} />
        ${author.special === "enji" && html`<div class="kicker accent" style="margin-top:4px">Enji · Developer</div>`}
        ${bio && html`<div style="margin-top:4px">${bio}</div>`}</div>
      ${me ? html`<button class="chip" style="justify-content:center" onClick=${onAccount}>Edit profile</button>`
        : html`<button class=${follows ? "chip" : "primary"} style=${follows ? "justify-content:center" : "height:40px"} onClick=${toggleFollow}>${follows ? "Following" : "Follow"}</button>`}
      ${posts === null ? html`<p class="muted">Loading…</p>` : posts.length === 0 ? html`<p class="muted">No posts yet.</p>` : html`
        <div class="grid3">${posts.map((p) => html`
          <button onClick=${() => actions.open(p)} aria-label="Open post">
            ${p.mediaKind === "photo" ? html`<img src=${mediaURL(p.mediaPath)} alt="" loading="lazy" />`
              : p.mediaKind === "video" ? html`<${Icon} name="photo" />` : html`<span style="overflow:hidden;max-height:100%">${p.body}</span>`}
          </button>`)}</div>`}
    <//>`;
}

export function Account({ session, onClose }) {
  const { supabase, user, profile } = session;
  const [username, setUsername] = useState(profile.username);
  const [bio, setBio] = useState(profile.bio || "");
  const [message, setMessage] = useState(null);
  const changed = username.trim() !== profile.username || bio.trim() !== (profile.bio || "");
  const save = async () => {
    const { error } = await supabase.from("profiles").update({ username: username.trim(), bio: bio.trim() }).eq("id", user.id);
    error ? setMessage(describe(error, "save your profile")) : (setMessage("Saved."), session.reload());
  };
  const avatar = async (file) => {
    if (!file) return;
    try {
      const { path } = await uploadMedia(supabase, user.id, file, "avatar-");
      const { error } = await supabase.from("profiles").update({ avatar_path: path }).eq("id", user.id);
      if (error) throw error;
      if (profile.avatar_path) await supabase.storage.from("post-media").remove([profile.avatar_path]);
      session.reload();
    } catch (e) { setMessage(describe(e, "update your picture")); }
  };
  const deleteAccount = () => confirmDialog({ title: "Delete your NAGISEN account?",
    message: "Your username, picture, every post, comment and photo or video you shared are removed for good. Your history in this browser is not affected.",
    actions: [{ title: "Delete account and posts", destructive: true, run: async () => {
      const { data: files } = await supabase.storage.from("post-media").list(folder(user.id), { limit: 1000 });
      if (files?.length) await supabase.storage.from("post-media").remove(files.map((f) => `${folder(user.id)}/${f.name}`));
      const { error } = await supabase.rpc("delete_my_account");
      if (error) return setMessage(describe(error, "delete the account"));
      await supabase.auth.signOut(); onClose();
    } }] });
  return html`
    <${Sheet} title="Account" onClose=${onClose} action=${changed ? save : null} actionLabel="Save" actionEnabled=${validUsername(username.trim()) && bio.length <= 150}>
      <div class="panel row" style="gap:18px">
        <${Avatar} url=${mediaURL(profile.avatar_path)} name=${profile.username} tier=${profile.border_tier} special=${profile.special_border} size=${84} />
        <label class="link" style="cursor:pointer">${profile.avatar_path ? "Change photo" : "Add a photo"}
          <input type="file" accept="image/*" class="hidden" onChange=${(e) => avatar(e.target.files[0])} /></label>
      </div>
      <div class="panel tight list">
        <input class="plain-input" placeholder="Username" autocapitalize="none" value=${username} onInput=${(e) => setUsername(e.target.value)} aria-label="Username" />
        <textarea class="plain-input" rows="3" placeholder="A line about you" maxlength="150" value=${bio} onInput=${(e) => setBio(e.target.value)} aria-label="Bio" />
      </div>
      <div class="caption">${bio.length}/150</div>
      ${message && html`<p class="accent small">${message}</p>`}
      <div class="panel tight list">
        <div class="list-row small muted">${user.email}</div>
        <button class="list-row" onClick=${() => { supabase.auth.signOut(); onClose(); }}>Sign out</button>
        <button class="list-row danger" onClick=${deleteAccount}>Delete account</button>
      </div>
    <//>`;
}
