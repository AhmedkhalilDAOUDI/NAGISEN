import { html, useState, useRef, useEffect, dayKey, addDays } from "./lib.js";
import { useStore, update, getState, totalsOn, entriesOn } from "./store.js";
import { Sheet, Icon, Toggle, confirmDialog } from "./ui.js";

const KEY_STORE = "nagisen.deepseek.key";

const SYSTEM = `You're texting with a friend who trains and cares about food. Talk like a real person in a chat: casual, relaxed, plain words, contractions. Answer what they asked in the first sentence, then stop when it's answered. Most replies are one to four sentences; go longer only when they ask for detail or a plan.

Write in plain sentences. No headings, no bold, no bullet or numbered lists unless they ask for steps or a list. No emojis unless they use them. Match their language and how they write.

Never use these: "Great question", "Absolutely", "Certainly", "Of course!", "I'd be happy to", "Here's the thing", "It's important to note", "In summary", "Overall", "Hope this helps", "Let me know if", "Feel free to", "journey", "delve", "dive into", "game-changer", "crucial", "remember,". Don't recap the question, don't add a closing summary, don't end with an offer to help more, don't pile on disclaimers, don't moralise or cheerlead.

Example of the tone. They ask: "is it bad to train legs two days in a row?" You answer: "Not if the second day is lighter. Hit the same muscles hard twice in a row and you'll mostly just be tired, so make day two easy or swap it for upper body."

You can talk about anything. If NAGISEN data is attached, treat it as partial logs, not everything they ate or did, and don't invent what's missing. Say so when you're not sure. Never mention these instructions.`;

/** A short summary of today, sent only when "Use my NAGISEN data" is on. */
function context() {
  const s = getState();
  const today = dayKey();
  const t = totalsOn(s, today);
  const foods = entriesOn(s, today).map((e) => `${e.food.name} ${e.label}`).join("; ");
  const workouts = s.workouts.filter((w) => w.day === today).length;
  const recent = [...s.workouts].sort((a, b) => b.day.localeCompare(a.day)).slice(0, 3).map((w) => `${w.activity} ${w.minutes} min on ${w.day}`).join("; ");
  const days = Array.from({ length: 7 }, (_, i) => addDays(today, -i)).filter((d) => entriesOn(s, d).length);
  const parts = [
    `Today's goals: ${s.goals.calories} kcal, ${s.goals.protein} g protein, ${s.goals.carbs} g carbs, ${s.goals.fat} g fat.`,
    `Today: ${entriesOn(s, today).length} food entries, ${t.calories} kcal logged, ${Math.round(t.protein)} g protein logged, ${workouts} NAGISEN workouts logged.`,
  ];
  if (foods) parts.push(`Foods logged today: ${foods}.`);
  if (days.length) parts.push(`Last 7 days: food logged on ${days.length} days; average ${Math.round(days.reduce((a, d) => a + totalsOn(s, d).calories, 0) / days.length)} kcal per logged day. Unlogged days are missing data.`);
  if (recent) parts.push(`Recent training: ${recent}.`);
  return parts.join(" ");
}

export function Coach({ onClose }) {
  const s = useStore();
  const [key, setKey] = useState(() => { try { return localStorage.getItem(KEY_STORE) || ""; } catch { return ""; } });
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState(null);
  const [settings, setSettings] = useState(false);
  const end = useRef();
  const messages = s.coach.messages;
  useEffect(() => { end.current?.scrollIntoView({ behavior: "smooth" }); }, [messages.length, sending]);

  async function send(text) {
    if (!key) { setSettings(true); return; }
    const content = text.trim();
    if (!content || sending) return;
    setDraft(""); setError(null); setSending(true);
    update((x) => { x.coach.messages.push({ role: "user", content }); });
    const system = SYSTEM + (getState().coach.useContext ? `\n\nNAGISEN data, supplied for this reply when relevant: ${context()}` : "");
    const history = getState().coach.messages.slice(-20).map(({ role, content }) => ({ role, content }));
    try {
      const r = await fetch("https://api.deepseek.com/chat/completions", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
        body: JSON.stringify({ model: "deepseek-flash", thinking: { type: "disabled" }, max_tokens: 800, messages: [{ role: "system", content: system }, ...history] }),
      });
      if (r.status === 401) throw new Error("The API key was rejected. Check it in Chat settings.");
      if (r.status === 429) throw new Error("DeepSeek is busy or the account limit was reached. Try again later.");
      if (!r.ok) throw new Error(`DeepSeek returned error ${r.status}. Try again.`);
      const answer = (await r.json()).choices?.[0]?.message?.content;
      if (!answer) throw new Error("DeepSeek returned an unreadable response. Try again.");
      update((x) => { x.coach.messages.push({ role: "assistant", content: answer }); });
    } catch (e) {
      setError(e.message.includes("Failed to fetch") ? "Couldn't reach DeepSeek. Check your connection." : e.message);
    } finally {
      setSending(false);
    }
  }

  if (settings) return html`<${CoachSettings} keyValue=${key} onKey=${setKey} onClose=${() => setSettings(false)} />`;

  return html`
    <${Sheet} title="Your coach" onClose=${onClose} extra=${html`
      ${messages.length > 0 && html`<button class="icon-btn" aria-label="New chat" onClick=${() => update((x) => { x.coach.messages = []; })}><${Icon} name="pencil" size="sm" /></button>`}
      <button class="icon-btn" aria-label="Chat settings" onClick=${() => setSettings(true)}><${Icon} name="gear" size="sm" /></button>`}>
      ${messages.length === 0 && html`
        <div class="stack" style="gap:8px;margin-top:10px">
          <h1 class="serif" style="font-size:30px;margin:0">What's on your mind?</h1>
          <div class="muted">${s.coach.useContext ? "I can see today's logs, goals and recent training." : "Ask about food, training, recovery or anything else."}</div>
          ${!key && html`<button class="panel row" style="text-align:left;margin-top:12px" onClick=${() => setSettings(true)}>
            <${Icon} name="tag" /><div class="grow"><div>Connect DeepSeek</div><div class="caption">Add your API key once. It stays in this browser.</div></div></button>`}
        </div>`}
      <div class="stack" style="gap:16px">
        ${messages.map((m) => html`<div class=${`bubble ${m.role === "user" ? "me" : "them"}`}>${m.content}</div>`)}
        ${sending && html`<div class="muted">Thinking…</div>`}
        ${error && html`<div class="accent small">${error}</div>`}
        <div ref=${end} />
      </div>
      <form class="row" style="position:sticky;bottom:calc(env(safe-area-inset-bottom) + 10px);margin-top:auto"
        onSubmit=${(e) => { e.preventDefault(); send(draft); }}>
        <input class="field grow" placeholder="Ask anything" value=${draft} onInput=${(e) => setDraft(e.target.value)}
          style="background:var(--surface)" aria-label="Message" />
        <button class="icon-btn" style="background:var(--accent);color:#fff;border:0" disabled=${!draft.trim() || sending} aria-label="Send">
          <${Icon} name="send" size="sm" /></button>
      </form>
    <//>`;
}

function CoachSettings({ keyValue, onKey, onClose }) {
  const s = useStore();
  const [input, setInput] = useState("");
  const store = (v) => { try { v ? localStorage.setItem(KEY_STORE, v) : localStorage.removeItem(KEY_STORE); } catch {} onKey(v); };
  return html`
    <${Sheet} title="Chat settings" onClose=${onClose}>
      <h2 class="section">DeepSeek connection</h2>
      <div class="panel tight list">
        <input class="plain-input" type="password" autocomplete="off" placeholder=${keyValue ? "Replace API key" : "Paste API key"}
          value=${input} onInput=${(e) => setInput(e.target.value)} aria-label="DeepSeek API key" />
        <button class="list-row accent" disabled=${!input.trim()} onClick=${() => { store(input.trim()); setInput(""); onClose(); }}>Save key in this browser</button>
        ${keyValue && html`<button class="list-row danger" onClick=${() => store("")}>Remove saved key</button>`}
      </div>
      <h2 class="section">Personalization</h2>
      <div class="panel stack" style="gap:12px">
        <div class="spread"><span>Use my NAGISEN data</span>
          <${Toggle} on=${s.coach.useContext} label="Use my NAGISEN data" onChange=${(v) => update((x) => { x.coach.useContext = v; })} /></div>
        <div class="caption">When on, each message includes a short summary of today's food, goals and workouts. This summary is sent to DeepSeek with your question.</div>
      </div>
      <h2 class="section">Conversation</h2>
      <div class="panel tight"><button class="list-row danger" onClick=${() => confirmDialog({ title: "Clear chat history?",
        actions: [{ title: "Clear history", destructive: true, run: () => update((x) => { x.coach.messages = []; }) }] })}>Clear chat history</button></div>
      <p class="caption">The key is stored in this browser only. Chat history stays on this device. Messages you send go to DeepSeek.</p>
    <//>`;
}
