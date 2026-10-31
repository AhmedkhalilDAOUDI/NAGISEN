import { html, useState, dayKey, addDays, dayTitle, longDate, fmt, uid, parseDay } from "./lib.js";
import { useStore, update, entriesOn, totalsOn, streak, deleteEntry, toggleDay } from "./store.js";
import { caffeineLevel } from "./math.js";
import { Icon, Heading, Toggle, Menu, confirmDialog } from "./ui.js";
import { AddFood } from "./food.js";
import { Profile } from "./profile.js";

const MEALS = ["Breakfast", "Lunch", "Dinner", "Snacks"];
const DRINKS = [["Atay", 32], ["Espresso", 63], ["Monster Ultra", 150]];

export function Dashboard() {
  const s = useStore();
  const [day, setDay] = useState(dayKey());
  const [adding, setAdding] = useState(null);
  const [profile, setProfile] = useState(false);
  const goals = s.goals;
  const totals = totalsOn(s, day);
  const left = goals.calories - totals.calories;
  const over = left < 0;
  const done = s.completedDays.includes(day);
  const fraction = Math.min(1, totals.calories / Math.max(goals.calories, 1));

  const cycleTheme = () => update((x) => {
    x.appearance = { system: "dark", dark: "light", light: "system" }[x.appearance] || "system";
  });

  return html`
    <div class="screen">
      <${Heading} kicker="NAGISEN" title=${html`
        <span class="row" style="gap:10px">
          <button aria-label="Previous day" onClick=${() => setDay(addDays(day, -1))}><${Icon} name="left" /></button>
          <span>${dayTitle(day)}</span>
          <button aria-label="Next day" onClick=${() => setDay(addDays(day, 1))}><${Icon} name="right" /></button>
        </span>`} sub=${longDate(day)}>
        <div class="row" style="gap:8px">
          <button class="icon-btn" aria-label=${`Appearance: ${s.appearance}`} onClick=${cycleTheme}>
            <${Icon} name=${s.appearance === "light" ? "sun" : s.appearance === "dark" ? "moon" : "gear"} size="sm" />
          </button>
          <button class="icon-btn" aria-label="Profile and goals" onClick=${() => setProfile(true)}><${Icon} name="user" size="sm" /></button>
        </div>
      <//>

      <section class="panel stack" style="gap:18px;padding:20px">
        <div class="kicker">Daily balance</div>
        <div class="spread">
          <div>
            <div class="big-number">${fmt(Math.abs(left))}</div>
            <div class="muted">${over ? "kcal over" : "kcal remaining"}</div>
          </div>
          <div class="ring-wrap" aria-label=${`${fmt(totals.calories)} of ${fmt(goals.calories)} kcal`}>
            <svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="44" fill="none" stroke="var(--hair)" stroke-width="6" />
              ${fraction > 0 && html`<circle cx="50" cy="50" r="44" fill="none" stroke=${over ? "var(--red)" : "var(--accent-text)"} stroke-width="6"
                stroke-linecap="round" stroke-dasharray=${`${fraction * 276.5} 276.5`} />`}</svg>
            <div class="mid"><${Icon} name="flame" /></div>
          </div>
        </div>
        <hr class="divider" />
        <div class="spread">
          <div class="row" style="gap:8px"><${Icon} name="flame" size="sm" /><span style="font-weight:600;font-size:19px">${streak(s)}-day streak</span></div>
        </div>
        <div class="spread">
          <div class="row" style="gap:8px"><${Icon} name="checkCircle" size="sm" /><span>Done logging</span></div>
          <${Toggle} on=${done} label="Done logging" onChange=${() => toggleDay("completedDays", day)} />
        </div>
        ${done && day === dayKey() && html`<${Week} s=${s} day=${day} />`}
        <hr class="divider" />
        <div class="kicker">Nutrition</div>
        <div class="macro-grid">
          ${[["Protein", totals.protein, goals.protein, "var(--protein)"], ["Carbs", totals.carbs, goals.carbs, "var(--carbs)"],
             ["Fat", totals.fat, goals.fat, "var(--fat)"]].map(([n, v, g, c]) => html`
            <div class="stack" style="gap:4px">
              <div class="kicker" style=${`color:${c}`}>● ${n}</div>
              <div class="value" style=${`color:${c}`}>${fmt(v)}g</div>
              <div class="caption">${fmt((v / Math.max(g, 1)) * 100)}% of ${g}g</div>
              <div class="bar"><div style=${`width:${Math.min(100, (v / Math.max(g, 1)) * 100)}%;background:${c}`} /></div>
            </div>`)}
        </div>
        <hr class="divider" />
        <${Water} s=${s} day=${day} />
      </section>

      ${s.profile.tracksCreatine && html`
        <section class="panel spread">
          <div class="row"><${Icon} name=${s.creatineDays.includes(day) ? "checkCircle" : "dots"} />
            <div><div class="serif" style="font-size:19px">5 g creatine</div>
              <div class="caption">${s.creatineDays.includes(day) ? "Taken today" : "Not taken yet"}</div></div></div>
          <${Toggle} on=${s.creatineDays.includes(day)} label="Creatine taken" onChange=${() => toggleDay("creatineDays", day)} />
        </section>`}

      <${Caffeine} s=${s} day=${day} />

      ${MEALS.map((meal) => {
        const items = entriesOn(s, day).filter((e) => e.meal === meal);
        const kcal = items.reduce((t, e) => t + e.calories, 0);
        return html`
          <section class="panel stack" style="gap:10px">
            <div class="spread">
              <div><div class="serif" style="font-size:21px">${meal}</div>
                <div class="caption">${items.length ? `${fmt(kcal)} kcal` : "Nothing logged"}</div></div>
              <div class="row" style="gap:4px">
                ${items.length > 0 && html`<${Menu} title=${meal} actions=${[{ title: `Clear ${meal}`, icon: "trash", destructive: true,
                  run: () => confirmDialog({ title: `Clear ${meal}?`, message: `This removes every food logged for ${meal} on this day.`,
                    actions: [{ title: "Delete whole meal", destructive: true, run: () => update((x) => { x.entries = x.entries.filter((e) => !(e.day === day && e.meal === meal)); }) }] }) }]} />`}
                <button class="icon-btn" aria-label=${`Add to ${meal}`} onClick=${() => setAdding(meal)}><${Icon} name="plus" size="sm" /></button>
              </div>
            </div>
            ${items.length > 0 && html`<div class="list">
              ${items.map((e) => html`
                <div class="list-row">
                  <div class="grow"><div>${e.food.name}</div><div class="caption">${e.label}${e.food.brand ? ` · ${e.food.brand}` : ""}</div></div>
                  <div class="small">${fmt(e.calories)} kcal</div>
                  <button aria-label=${`Remove ${e.food.name}`} class="muted" onClick=${() => deleteEntry(e.id)}><${Icon} name="x" size="sm" /></button>
                </div>`)}
            </div>`}
          </section>`;
      })}

      ${entriesOn(s, day).length === 0 && entriesOn(s, addDays(day, -1)).length > 0 && html`
        <button class="link" onClick=${() => confirmDialog({ title: "Copy yesterday's food?",
          message: "This adds yesterday's foods to this day. You can edit or remove entries afterwards.",
          actions: [{ title: `Add ${entriesOn(s, addDays(day, -1)).length} foods`, run: () => update((x) => {
            x.entries.push(...x.entries.filter((e) => e.day === addDays(day, -1)).map((e) => ({ ...e, id: uid(), day, createdAt: new Date().toISOString() })));
          }) }] })}>Copy yesterday's food</button>`}
    </div>
    ${adding && html`<${AddFood} day=${day} meal=${adding} onClose=${() => setAdding(null)} />`}
    ${profile && html`<${Profile} onClose=${() => setProfile(false)} />`}`;
}

function Week({ s, day }) {
  const d = parseDay(day);
  const monday = new Date(d);
  monday.setDate(d.getDate() - ((d.getDay() + 6) % 7));
  const days = Array.from({ length: 7 }, (_, i) => { const x = new Date(monday); x.setDate(monday.getDate() + i); return dayKey(x); });
  return html`
    <div class="week" aria-label="This week">
      ${days.map((k) => html`<div>
        <div class=${`dot ${s.completedDays.includes(k) ? "done" : ""}`}>${s.completedDays.includes(k) && html`<${Icon} name="check" size="sm" />`}</div>
        <div class="caption" style=${k === day ? "color:var(--ink);font-weight:700" : ""}>${parseDay(k).toLocaleDateString(undefined, { weekday: "short" })}</div>
      </div>`)}
    </div>`;
}

function Water({ s, day }) {
  const ml = s.water[day] || 0;
  const add = (v) => update((x) => { x.water[day] = Math.max(0, (x.water[day] || 0) + v); });
  return html`
    <div class="stack" style="gap:10px">
      <div class="spread"><div class="kicker row" style="gap:6px"><${Icon} name="drop" size="sm" />Water</div>
        <div class="small accent">${fmt((ml / Math.max(s.waterGoal, 1)) * 100)}%</div></div>
      <div><span class="serif" style="font-size:40px">${fmt(ml)}</span><span class="muted"> / ${fmt(s.waterGoal)} mL</span></div>
      <div class="bar"><div style=${`width:${Math.min(100, (ml / s.waterGoal) * 100)}%;background:var(--accent-text)`} /></div>
      <div class="row" style="gap:8px;flex-wrap:wrap">
        <button class="chip" onClick=${() => add(250)}>+ 250 mL</button>
        <button class="chip" onClick=${() => add(500)}>+ 500 mL</button>
        ${ml > 0 && html`<button class="chip" onClick=${() => add(-250)}>− 250</button>`}
      </div>
    </div>`;
}

function Caffeine({ s, day }) {
  const [custom, setCustom] = useState("");
  const todays = s.caffeine.filter((e) => dayKey(new Date(e.at)) === day);
  const total = todays.reduce((t, e) => t + e.mg, 0);
  const now = day === dayKey() ? caffeineLevel(s.caffeine, new Date(), s.halfLife) : null;
  const bed = new Date(parseDay(day)); bed.setHours(s.bedtime, 0, 0, 0);
  const atBed = caffeineLevel(s.caffeine, bed, s.halfLife);
  const add = (name, mg) => {
    const at = day === dayKey() ? new Date() : (() => { const d = parseDay(day); d.setHours(12); return d; })();
    update((x) => { x.caffeine.push({ id: uid(), at: at.toISOString(), mg, name }); });
  };
  return html`
    <section class="panel stack" style="gap:12px">
      <div class="spread"><div class="kicker row" style="gap:6px"><${Icon} name="bolt" size="sm" />Caffeine</div>
        <div class="caption">${fmt(total)} mg today</div></div>
      <div class="row" style="gap:24px">
        ${now != null && html`<div><div class="serif" style="font-size:28px">${fmt(now)} mg</div><div class="caption">in you now</div></div>`}
        <div><div class="serif" style="font-size:28px">${fmt(atBed)} mg</div><div class="caption">at ${s.bedtime}:00 bedtime</div></div>
      </div>
      <div class="row" style="gap:8px;flex-wrap:wrap">
        ${DRINKS.map(([n, mg]) => html`<button class="chip" onClick=${() => add(n, mg)}>${n} · ${mg} mg</button>`)}
        <input class="field" style="width:110px;min-height:34px;padding:4px 12px" inputmode="numeric" placeholder="Custom mg"
          value=${custom} onInput=${(e) => setCustom(e.target.value)} aria-label="Custom caffeine in milligrams" />
        ${Number(custom) > 0 && html`<button class="link" onClick=${() => { add("Caffeine", Math.round(Number(custom))); setCustom(""); }}>Add</button>`}
      </div>
      ${todays.length > 0 && html`<div class="list">${todays.map((e) => html`
        <div class="list-row small"><span class="grow">${e.name} · ${new Date(e.at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</span>
          <span>${e.mg} mg</span>
          <button class="muted" aria-label="Remove drink" onClick=${() => update((x) => { x.caffeine = x.caffeine.filter((c) => c.id !== e.id); })}><${Icon} name="x" size="sm" /></button>
        </div>`)}</div>`}
    </section>`;
}
