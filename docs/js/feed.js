import { html, useState, useEffect, useCallback, ago } from "./lib.js";
import { Heading, Icon, Menu, Avatar, MemberName, confirmDialog } from "./ui.js";
import { useSession, POST_FIELDS, PAGE, asPost, mediaURL, describe, REPORT_REASONS } from "./feedClient.js";
import { SignIn, ChooseUsername, Composer, EditPost, Comments, MemberPage, Account } from "./feedSheets.js";

export function Feed() {
  const session = useSession();
  const [mode, setMode] = useState("explore");
  const [posts, setPosts] = useState([]);
  const [more, setMore] = useState(false);
  const [message, setMessage] = useState(null);
  const [sheet, setSheet] = useState(null);
  const { supabase, user, profile } = session;
  const dev = profile?.special_border === "enji";

  const query = useCallback((from) => {
    let q = supabase.from("posts").select(POST_FIELDS).eq("mine.member_id", user.id);
    if (mode === "following") q = q.in("author_id", [...session.following, user.id]);
    return q.order("pinned_at", { ascending: false, nullsFirst: false }).order("created_at", { ascending: false }).range(from, from + PAGE - 1);
  }, [supabase, user, mode, session.following]);

  const load = useCallback(async (from = 0) => {
    const { data, error } = await query(from);
    if (error) return setMessage(describe(error, "load the feed"));
    setMessage(null);
    const page = data.map(asPost);
    setPosts((old) => (from === 0 ? page : [...old, ...page]));
    setMore(page.length === PAGE);
  }, [query]);

  useEffect(() => { if (session.state === "ready") load(0); }, [session.state, mode, load]);

  const patch = (id, change) => setPosts((list) => list.map((p) => (p.id === id ? { ...p, ...change(p) } : p)));
  const remove = (id) => setPosts((list) => list.filter((p) => p.id !== id));

  async function like(post) {
    patch(post.id, (p) => ({ liked: !p.liked, likes: p.likes + (p.liked ? -1 : 1) }));
    const { error } = post.liked
      ? await supabase.from("appreciations").delete().eq("post_id", post.id).eq("member_id", user.id)
      : await supabase.from("appreciations").upsert({ post_id: post.id }, { onConflict: "post_id,member_id" });
    if (error) { patch(post.id, () => ({ liked: post.liked, likes: post.likes })); setMessage(describe(error, "like the post")); }
  }

  const actions = {
    like, open: (post) => setSheet({ kind: "comments", post }), member: (author) => setSheet({ kind: "member", author }),
    edit: (post) => setSheet({ kind: "edit", post }),
    delete: (post) => confirmDialog({ title: "Delete this post?", message: "This can't be undone.", actions: [{ title: "Delete post", destructive: true, run: async () => {
      const { error } = await supabase.from("posts").delete().eq("id", post.id);
      if (error) return setMessage(describe(error, "delete the post"));
      const files = [post.mediaPath, post.posterPath].filter(Boolean);
      if (files.length) await supabase.storage.from("post-media").remove(files);
      remove(post.id);
    } }] }),
    pin: async (post) => {
      const { error } = await supabase.rpc("set_post_pinned", { target: post.id, pin: !post.pinnedAt });
      error ? setMessage(describe(error, "pin the post")) : load(0);
    },
    report: (post) => confirmDialog({ title: "Why are you reporting this post?", message: "The post will be hidden from your feed and sent for review.",
      actions: REPORT_REASONS.map((reason) => ({ title: reason, run: async () => {
        remove(post.id);
        await supabase.from("reports").insert({ post_id: post.id, reason });
        setMessage("Thanks. The post is hidden and has been sent for review.");
      } })) }),
    block: (post) => confirmDialog({ title: `Block @${post.author.username}?`, message: "You won’t see their posts, comments or stories anymore. They aren’t told.",
      actions: [{ title: "Block", destructive: true, run: async () => {
        const { error } = await supabase.from("blocks").upsert({ blocked_id: post.authorID }, { onConflict: "blocker_id,blocked_id" });
        error ? setMessage(describe(error, "block")) : setPosts((l) => l.filter((p) => p.authorID !== post.authorID));
      } }] }),
  };

  if (session.state === "loading") return html`<div class="screen"><${Heading} kicker="NAGISEN" title="Feed" /><p class="muted">Loading…</p></div>`;
  if (session.state === "error") return html`<div class="screen"><${Heading} kicker="NAGISEN" title="Feed" /><p class="accent">${session.message}</p></div>`;
  if (session.state === "signedOut") return html`
    <div class="screen">
      <${Heading} kicker="NAGISEN" title="Feed" />
      <section class="panel stack">
        <div>Create an account to share workouts, meals and small wins with NAGISEN members.</div>
        <button class="primary" onClick=${() => setSheet({ kind: "signin" })}>Sign in or create an account</button>
        <div class="caption">Posts are visible to signed-in NAGISEN members. Your food and workout history stays in this browser.</div>
      </section>
    </div>
    ${sheet?.kind === "signin" && html`<${SignIn} supabase=${supabase} onClose=${() => setSheet(null)} />`}`;
  if (session.state === "needsUsername") return html`<${ChooseUsername} session=${session} />`;

  return html`
    <div class="screen">
      <${Heading} kicker="NAGISEN" title="Feed">
        <div class="row" style="gap:8px">
          <button class="icon-btn" aria-label="New post" onClick=${() => setSheet({ kind: "compose" })}><${Icon} name="plus" size="sm" /></button>
          <button aria-label="Your account" onClick=${() => setSheet({ kind: "member", author: { id: user.id, username: profile.username, avatarPath: profile.avatar_path, tier: profile.border_tier, special: profile.special_border } })}>
            <${Avatar} url=${mediaURL(profile.avatar_path)} name=${profile.username} tier=${profile.border_tier} special=${profile.special_border} size=${40} /></button>
        </div>
      <//>
      <div class="tabs" role="tablist">
        <button role="tab" class=${mode === "following" ? "on" : ""} aria-selected=${mode === "following"} onClick=${() => setMode("following")}>Following</button>
        <button role="tab" class=${mode === "explore" ? "on" : ""} aria-selected=${mode === "explore"} onClick=${() => setMode("explore")}>Explore</button>
      </div>
      ${message && html`<p class="accent small" style="margin:0">${message}</p>`}
      ${posts.length === 0 && !message && html`
        <section class="panel stack">
          <div class="serif" style="font-size:24px">${mode === "following" ? "Nothing from the people you follow yet" : "The first page is yours to write"}</div>
          <div class="muted">Share a workout, a meal you made, or a small win.</div>
          <button class="primary" onClick=${() => setSheet({ kind: "compose" })}>Share a moment</button>
        </section>`}
      ${posts.map((p) => html`<${PostCard} key=${p.id} post=${p} me=${user.id} dev=${dev} actions=${actions} />`)}
      ${more && html`<button class="chip" style="align-self:center" onClick=${() => load(posts.length)}>Load more</button>`}
    </div>
    ${sheet?.kind === "compose" && html`<${Composer} session=${session} onClose=${() => setSheet(null)} onPosted=${() => { setSheet(null); load(0); }} />`}
    ${sheet?.kind === "edit" && html`<${EditPost} session=${session} post=${sheet.post} onClose=${() => setSheet(null)}
      onSaved=${(body) => { patch(sheet.post.id, () => ({ body })); setSheet(null); }} />`}
    ${sheet?.kind === "comments" && html`<${Comments} session=${session} post=${sheet.post} onClose=${() => setSheet(null)}
      onCount=${(n) => patch(sheet.post.id, () => ({ comments: n }))} />`}
    ${sheet?.kind === "member" && html`<${MemberPage} session=${session} author=${sheet.author} onClose=${() => setSheet(null)}
      onAccount=${() => setSheet({ kind: "account" })} actions=${actions} />`}
    ${sheet?.kind === "account" && html`<${Account} session=${session} onClose=${() => setSheet(null)} />`}`;
}

export function PostCard({ post, me, dev, actions }) {
  const mine = post.authorID === me;
  const menu = [
    ...(dev ? [{ title: post.pinnedAt ? "Unpin" : "Pin to top", icon: "pin", run: () => actions.pin(post) }] : []),
    ...(mine ? [{ title: "Edit post", icon: "pencil", run: () => actions.edit(post) }, { title: "Delete post", icon: "trash", destructive: true, run: () => actions.delete(post) }]
      : [{ title: "Report post", icon: "flag", run: () => actions.report(post) }, { title: "Block", icon: "hand", destructive: true, run: () => actions.block(post) }]),
  ];
  const share = () => {
    const text = post.mediaPath ? mediaURL(post.mediaPath) : post.body;
    navigator.share ? navigator.share({ text }).catch(() => {}) : navigator.clipboard?.writeText(text);
  };
  return html`
    <article class="post">
      <div class="spread">
        <button class="row" style="gap:10px" onClick=${() => actions.member(post.author)}>
          <${Avatar} url=${mediaURL(post.author.avatarPath)} name=${post.author.username} tier=${post.author.tier} special=${post.author.special} size=${34} />
          <${MemberName} name=${post.author.username} special=${post.author.special} />
        </button>
        <div class="row" style="gap:6px">
          ${post.pinnedAt && html`<span class="caption row" style="gap:4px;letter-spacing:0.12em;text-transform:uppercase;font-weight:600"><${Icon} name="pin" size="sm" />Pinned</span>`}
          <${Menu} title=${mine ? "Your post" : `@${post.author.username}`} actions=${menu} />
        </div>
      </div>
      ${post.mediaKind === "video" ? html`<video class="media" src=${mediaURL(post.mediaPath)} poster=${mediaURL(post.posterPath)} controls playsinline muted loop preload="metadata" />`
        : post.mediaPath ? html`<img class="media" src=${mediaURL(post.mediaPath)} alt=${`Photo by @${post.author.username}`} loading="lazy" onDblClick=${() => !post.liked && actions.like(post)} />`
        : html`<div class="text">${post.body}</div>`}
      <div class="row" style="gap:18px">
        <button aria-label=${post.liked ? "Unlike" : "Like"} onClick=${() => actions.like(post)} style=${post.liked ? "color:var(--red)" : ""}>
          <svg class="i" viewBox="0 0 24 24" style=${post.liked ? "fill:currentColor" : ""}><path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.5-7 10-7 10z" /></svg></button>
        <button aria-label="Comments" onClick=${() => actions.open(post)}><${Icon} name="chat" /></button>
        <button aria-label="Share" onClick=${share}><${Icon} name="send" /></button>
      </div>
      ${post.likes > 0 && html`<div style="font-weight:600;font-size:15px">${post.likes === 1 ? "1 like" : `${post.likes} likes`}</div>`}
      ${post.mediaPath && post.body && html`<div class="small"><${MemberName} name=${post.author.username} special=${post.author.special} /> ${post.body}</div>`}
      ${post.comments > 0 && html`<button class="small muted" style="text-align:left" onClick=${() => actions.open(post)}>${post.comments === 1 ? "View 1 comment" : `View all ${post.comments} comments`}</button>`}
      <div class="caption" style="text-transform:uppercase;letter-spacing:0.04em">${ago(post.createdAt)}</div>
    </article>`;
}
