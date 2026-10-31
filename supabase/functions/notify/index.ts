// Sends a push notification when someone likes, comments on or follows a member's posts.
// Called by the database triggers in supabase/push.sql; see supabase/PUSH.md for setup.
import { createClient } from "jsr:@supabase/supabase-js@2";

const env = (name: string) => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};

const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));
const apnsHost = Deno.env.get("APNS_PRODUCTION") === "true" ? "api.push.apple.com" : "api.sandbox.push.apple.com";

const base64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

let cachedToken: { jwt: string; at: number } | null = null;

/** Apple's provider token: an ES256 JWT, reused for up to 50 minutes as Apple asks. */
async function providerToken(): Promise<string> {
  if (cachedToken && Date.now() - cachedToken.at < 50 * 60 * 1000) return cachedToken.jwt;
  const pem = env("APNS_PRIVATE_KEY").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const encode = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));
  const unsigned = `${encode({ alg: "ES256", kid: env("APNS_KEY_ID") })}.${encode({ iss: env("APNS_TEAM_ID"), iat: Math.floor(Date.now() / 1000) })}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned));
  cachedToken = { jwt: `${unsigned}.${base64url(new Uint8Array(signature))}`, at: Date.now() };
  return cachedToken.jwt;
}

/** Who acted, who is told, and what they read. Null when nobody should be notified. */
async function describe(table: string, record: Record<string, string>) {
  let actor: string, recipient: string | undefined, text: (name: string) => string;
  if (table === "appreciations") {
    actor = record.member_id;
    recipient = (await supabase.from("posts").select("author_id").eq("id", record.post_id).maybeSingle()).data?.author_id;
    text = (name) => `@${name} liked your post`;
  } else if (table === "comments") {
    actor = record.author_id;
    recipient = (await supabase.from("posts").select("author_id").eq("id", record.post_id).maybeSingle()).data?.author_id;
    const body = (record.body || "").slice(0, 120);
    text = (name) => `@${name} commented: ${body}`;
  } else if (table === "follows") {
    actor = record.follower_id;
    recipient = record.followee_id;
    text = (name) => `@${name} started following you`;
  } else return null;
  if (!recipient || recipient === actor) return null;
  // Someone the recipient blocked never reaches them.
  const { count } = await supabase.from("blocks").select("blocker_id", { count: "exact", head: true })
    .eq("blocker_id", recipient).eq("blocked_id", actor);
  if (count) return null;
  const name = (await supabase.from("profiles").select("username").eq("id", actor).maybeSingle()).data?.username || "Someone";
  return { recipient, body: text(name), kind: table };
}

Deno.serve(async (request) => {
  if (request.headers.get("x-push-secret") !== env("PUSH_WEBHOOK_SECRET")) return new Response("Forbidden", { status: 403 });
  const { table, record } = await request.json();
  const message = await describe(table, record);
  if (!message) return new Response("skipped");

  const { data: tokens } = await supabase.from("device_tokens").select("token").eq("member_id", message.recipient);
  const jwt = await providerToken();
  const results = await Promise.all((tokens || []).map(async ({ token }) => {
    const response = await fetch(`https://${apnsHost}/3/device/${token}`, {
      method: "POST",
      headers: { authorization: `bearer ${jwt}`, "apns-topic": env("APNS_BUNDLE_ID"), "apns-push-type": "alert", "apns-priority": "10" },
      body: JSON.stringify({ aps: { alert: { title: "NAGISEN", body: message.body }, sound: "default", "thread-id": message.kind }, kind: message.kind }),
    });
    // A token Apple no longer knows (app deleted, notifications reset) is removed.
    if (response.status === 410 || response.status === 400) await supabase.from("device_tokens").delete().eq("token", token);
    return response.status;
  }));
  return Response.json({ sent: results });
});
