import { html, useState, useEffect } from "./lib.js";
import { BORDERS, ENJI } from "./math.js";

// Line icons drawn on a 24-point grid, stroked in the current text color.
const PATHS = {
  grid: "M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z",
  basket: "M3 10h18l-2 10H5zM8 10l4-6 4 6M9 14v3M12 14v3M15 14v3",
  run: "M14 4.5a1.5 1.5 0 1 0 0 .01M9 21l3-6 3 2v4M7 11l3-3 4 1 2 3 3 1M10 8l-2 6",
  people: "M9 11a3.5 3.5 0 1 0 0-.01M3 20c0-3.3 2.7-5 6-5s6 1.7 6 5M16.5 11a3 3 0 1 0 0-.01M17 15c2.5.3 4 1.9 4 5",
  sparkle: "M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8zM19 16l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7zM5 3l.5 1.5L7 5l-1.5.5L5 7l-.5-1.5L3 5l1.5-.5z",
  x: "M6 6l12 12M18 6L6 18",
  left: "M15 5l-7 7 7 7",
  right: "M9 5l7 7-7 7",
  down: "M6 9l6 6 6-6",
  plus: "M12 5v14M5 12h14",
  flame: "M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-2.5 1.5-4 2.5-5 .5 2 1.5 3 2.5 3-1-3 0-6 0-8z",
  check: "M5 12.5l4.5 4.5L19 7",
  checkCircle: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18M8 12.5l3 3 5-6",
  drop: "M12 3c3 4.5 6 7.5 6 11a6 6 0 0 1-12 0c0-3.5 3-6.5 6-11z",
  bolt: "M13 2L4 14h7l-1 8 9-12h-7z",
  heart: "M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.5-7 10-7 10z",
  chat: "M4 5h16v11H9l-5 4z",
  send: "M4 12l16-8-6 16-2.5-6.5z",
  dots: "M5 12h.01M12 12h.01M19 12h.01",
  search: "M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14M20 20l-4-4",
  trash: "M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13",
  pencil: "M4 20l4-1L19 8l-3-3L5 16zM14 6l3 3",
  flag: "M5 21V4M5 4h11l-2 4 2 4H5",
  hand: "M8 13V6a1.5 1.5 0 0 1 3 0v5M11 11V4.5a1.5 1.5 0 0 1 3 0V11M14 11V6a1.5 1.5 0 0 1 3 0v8c0 4-2.5 7-6 7-3 0-4.5-2-6-5l-1.5-3a1.5 1.5 0 0 1 2.5-1.5L8 13",
  pin: "M9 3h6l-1 6 3 3v2H7v-2l3-3zM12 14v7",
  camera: "M4 8h4l2-3h4l2 3h4v11H4zM12 10a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7",
  user: "M12 4a4 4 0 1 0 0 8 4 4 0 0 0 0-8M4 21c0-4 3.6-6.5 8-6.5s8 2.5 8 6.5",
  moon: "M20 14A8 8 0 1 1 10 4a6.5 6.5 0 0 0 10 10z",
  sun: "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8M12 2v2M12 20v2M4 12H2M22 12h-2M5 5l1.5 1.5M17.5 17.5L19 19M5 19l1.5-1.5M17.5 6.5L19 5",
  trophy: "M8 4h8v5a4 4 0 0 1-8 0zM8 6H5a3 3 0 0 0 3 4M16 6h3a3 3 0 0 1-3 4M12 13v4M8 20h8M9 17h6",
  dumbbell: "M3 10v4M6 8v8M18 8v8M21 10v4M6 12h12",
  calendar: "M4 6h16v14H4zM4 10h16M8 3v4M16 3v4",
  tag: "M3 12V4h8l10 10-8 8zM7.5 7.5h.01",
  scale: "M5 20h14M12 4v16M6 8l-3 6h6zM18 8l-3 6h6zM6 8h12",
  photo: "M4 5h16v14H4zM4 16l5-5 4 4 2-2 5 5M15 9h.01",
  book: "M5 4h10a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3zM5 17a3 3 0 0 1 3-3h10",
  gear: "M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6M19 12l2-1-1-3-2 .2-1.3-1.4.3-2-3-1-1 1.8h-2L9 3.8l-3 1 .3 2L5 8.2 3 8l-1 3 2 1-.1 1.8-1.7 1.2 1.5 2.8 2-.6 1.4 1.3-.2 2 3 .9 1-1.8h2l1 1.8 3-.9-.2-2 1.4-1.3 2 .6 1.5-2.8-1.7-1.2z",
  coffee: "M5 9h11v6a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4zM16 11h1.5a2.5 2.5 0 0 1 0 5H16M8 3c0 1.5 1 1.5 1 3M12 3c0 1.5 1 1.5 1 3",
};

export const Icon = ({ name, size, cls = "" }) => html`
  <svg class=${`i ${size === "sm" ? "sm" : ""} ${cls}`} viewBox="0 0 24 24" aria-hidden="true">
    <path d=${PATHS[name] || ""} />
  </svg>`;

export const Heading = ({ kicker, title, sub, children }) => html`
  <header class="spread" style="align-items:flex-start">
    <div class="heading grow">
      <div class="kicker">${kicker}</div>
      <h1>${title}</h1>
      ${sub && html`<div class="muted">${sub}</div>`}
    </div>
    ${children}
  </header>`;

/** A page that opens over the current screen, with NAGISEN's own bar: close mark, serif title, one action. */
export function Sheet({ title, onClose, action, actionLabel, actionEnabled = true, busy, extra, children }) {
  useEffect(() => {
    const key = (e) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", key);
    document.body.style.overflow = "hidden";
    return () => { window.removeEventListener("keydown", key); document.body.style.overflow = ""; };
  }, []);
  return html`
    <div class="sheet" role="dialog" aria-label=${title}>
      <div class="sheet-bar">
        <div><button class="close" onClick=${onClose} aria-label="Close"><${Icon} name="x" size="sm" /></button></div>
        <h2>${title}</h2>
        <div class="end">
          ${extra}
          ${action && (busy
            ? html`<span class="caption">Saving…</span>`
            : html`<button class="pill" disabled=${!actionEnabled} onClick=${action}>${actionLabel}</button>`)}
        </div>
      </div>
      <div class="sheet-body">${children}</div>
    </div>`;
}

/** The "…" menu: drops down from its button with a tracked title, ringed icons and hairlines. */
export function Menu({ title, actions, label = "More", icon = "dots" }) {
  const [open, setOpen] = useState(false);
  if (!actions.length) return null;
  return html`
    <div class="menu-wrap">
      <button class="icon-btn" style="border:0;background:none" aria-label=${label} aria-expanded=${open}
        onClick=${() => setOpen(!open)}><${Icon} name=${icon} /></button>
      ${open && html`
        <div class="menu-scrim" onClick=${() => setOpen(false)} />
        <div class="menu" role="menu">
          <div class="kicker">${title}</div>
          ${actions.map((a) => html`
            <button role="menuitem" class=${a.destructive ? "danger" : ""}
              onClick=${() => { setOpen(false); a.run(); }}>
              ${a.icon && html`<span class="ring"><${Icon} name=${a.icon} size="sm" /></span>`}
              <span>${a.title}</span>
            </button>`)}
        </div>`}
    </div>`;
}

// One centered dialog at a time, shown by DialogHost at the top of the app.
let showDialog = () => {};
export function confirmDialog({ title, message, actions = [], cancel = "Cancel" }) {
  showDialog({ title, message, actions, cancel });
}

export function DialogHost() {
  const [dialog, setDialog] = useState(null);
  showDialog = setDialog;
  if (!dialog) return null;
  const close = () => setDialog(null);
  return html`
    <div class="dialog-scrim" onClick=${(e) => e.target === e.currentTarget && close()}>
      <div class="dialog" role="alertdialog" aria-label=${dialog.title}>
        <div class="body">
          <h3>${dialog.title}</h3>
          ${dialog.message && html`<p>${dialog.message}</p>`}
        </div>
        ${dialog.actions.map((a) => html`
          <button class=${a.destructive ? "destructive" : ""} onClick=${() => { close(); a.run(); }}>${a.title}</button>`)}
        <button class="cancel" onClick=${close}>${dialog.cancel}</button>
      </div>
    </div>`;
}

export const Toggle = ({ on, onChange, label }) => html`
  <button class=${`toggle ${on ? "on" : ""}`} role="switch" aria-checked=${on} aria-label=${label}
    onClick=${() => onChange(!on)} />`;

export const Choice = ({ title, detail, on, onClick }) => html`
  <button class=${`choice ${on ? "on" : ""}`} onClick=${onClick} aria-pressed=${on}>
    <span class="stack" style="gap:2px">
      <span class="serif" style="font-size:19px">${title}</span>
      ${detail && html`<span class="caption">${detail}</span>`}
    </span>
    <span class="radio" />
  </button>`;

/** A styled select: the NAGISEN row look over the browser's own picker. */
export const Picker = ({ title, value, options, onChange }) => html`
  <label class="spread" style="min-height:52px;position:relative">
    <span>${title}</span>
    <span class="row accent" style="gap:6px">
      ${options.find((o) => o.value === value)?.label ?? ""}
      <${Icon} name="down" size="sm" />
    </span>
    <select aria-label=${title} value=${value} onChange=${(e) => onChange(options[e.target.selectedIndex].value)}
      style="position:absolute;inset:0;opacity:0;width:100%">
      ${options.map((o) => html`<option selected=${o.value === value}>${o.label}</option>`)}
    </select>
  </label>`;

export function Avatar({ url, name = "", tier = 0, special, size = 38 }) {
  const colors = special === "enji" ? ENJI : BORDERS[tier]?.colors || BORDERS[0].colors;
  const ring = colors.length > 1 ? `conic-gradient(${colors.join(",")})` : colors[0];
  const width = tier > 0 || special ? Math.max(2, size * 0.07) : 0.5;
  return html`
    <span class="avatar" style=${`width:${size}px;height:${size}px;padding:${width}px;background:${ring}`}>
      <span class="avatar" style=${`width:100%;height:100%;background:var(--surface);font-size:${size * 0.42}px;overflow:hidden`}>
        ${url ? html`<img src=${url} alt="" style="width:100%;height:100%;object-fit:cover" />` : (name[0] || "").toUpperCase()}
      </span>
    </span>`;
}

export const MemberName = ({ name, special, cls = "" }) => html`
  <span class=${`${cls} ${special === "enji" ? "enji-name" : ""}`} style="font-weight:600">${name}</span>`;
