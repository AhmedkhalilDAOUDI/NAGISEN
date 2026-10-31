import { html, useState, number, dayKey, fmt, parseDay } from "./lib.js";
import { useStore, update, getState, replaceAll, resetAll } from "./store.js";
import { Sheet, Toggle, Picker, confirmDialog } from "./ui.js";
import { COUNTRIES, currencyFor } from "./region.js";

export function Profile({ onClose }) {
  const s = useStore();
  const [goals, setGoals] = useState({ ...s.goals, water: s.waterGoal });
  const [weight, setWeight] = useState("");
  const changed = ["calories", "protein", "carbs", "fat"].some((k) => Number(goals[k]) !== s.goals[k]) || Number(goals.water) !== s.waterGoal;
  const valid = ["calories", "protein", "carbs", "fat", "water"].every((k) => number(goals[k]) >= 0) && number(goals.calories) >= 800;

  const saveGoals = () => update((x) => {
    x.goals = { calories: Math.round(number(goals.calories)), protein: Math.round(number(goals.protein)),
      carbs: Math.round(number(goals.carbs)), fat: Math.round(number(goals.fat)) };
    x.waterGoal = Math.round(number(goals.water));
  });

  const exportData = () => {
    const blob = new Blob([JSON.stringify(getState(), null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `NAGISEN-web-backup-${dayKey()}.json`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  const importData = (file) => {
    if (!file) return;
    file.text().then((text) => {
      try {
        const data = JSON.parse(text);
        if (!data || !Array.isArray(data.entries) || !data.goals) throw new Error();
        confirmDialog({ title: "Replace your current history?", message: "This replaces everything in NAGISEN on this browser with the backup.",
          actions: [{ title: "Replace with backup", destructive: true, run: () => replaceAll(data) }] });
      } catch {
        confirmDialog({ title: "Could not read that file", message: "Choose a NAGISEN web backup created by Export my data.", cancel: "OK" });
      }
    });
  };

  const goalRow = (k, label, unit, color) => html`
    <label class="spread" style="min-height:52px"><span style=${color ? `color:${color}` : ""}>${label}</span>
      <span class="row" style="gap:8px"><input class="plain-input" inputmode="numeric" style="text-align:right;width:90px"
        value=${goals[k]} onInput=${(e) => setGoals({ ...goals, [k]: e.target.value })} aria-label=${label} />
        <span class="muted" style="width:34px">${unit}</span></span></label>`;
  const weights = [...s.weights].sort((a, b) => b.day.localeCompare(a.day));

  return html`
    <${Sheet} title="You" onClose=${onClose} action=${changed ? saveGoals : null} actionLabel="Save" actionEnabled=${valid}>
      <h2 class="section">Daily goals</h2>
      <div class="panel tight list">
        ${goalRow("calories", "Calories", "kcal")}${goalRow("protein", "Protein", "g", "var(--protein)")}
        ${goalRow("carbs", "Carbs", "g", "var(--carbs)")}${goalRow("fat", "Fat", "g", "var(--fat)")}${goalRow("water", "Water", "mL")}
      </div>

      <h2 class="section">Weight</h2>
      <div class="panel stack" style="gap:10px">
        <div class="row">
          <input class="field grow" inputmode="decimal" placeholder="Today's weight in kg" value=${weight}
            onInput=${(e) => setWeight(e.target.value)} aria-label="Weight in kilograms" />
          <button class="link" disabled=${!(number(weight) >= 30 && number(weight) <= 300)}
            onClick=${() => { update((x) => { x.weights = x.weights.filter((w) => w.day !== dayKey()); x.weights.push({ day: dayKey(), kg: number(weight) }); }); setWeight(""); }}>Log</button>
        </div>
        ${weights.length > 0 && html`<div class="list">${weights.slice(0, 8).map((w) => html`
          <div class="list-row small"><span class="grow muted">${parseDay(w.day).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" })}</span>
            <span>${fmt(w.kg, 1)} kg</span></div>`)}</div>`}
      </div>

      <h2 class="section">Preferences</h2>
      <div class="panel tight list">
        <${Picker} title="Appearance" value=${s.appearance} onChange=${(v) => update((x) => { x.appearance = v; })}
          options=${[{ value: "system", label: "Match device" }, { value: "dark", label: "Dark" }, { value: "light", label: "Light" }]} />
        <${Picker} title="Country" value=${s.profile.country || "MA"} onChange=${(v) => update((x) => { x.profile.country = v; })}
          options=${COUNTRIES.map((c) => ({ value: c.code, label: c.name }))} />
        <div class="spread" style="min-height:52px"><span>Currency</span><span class="muted">${currencyFor(s.profile.country || "MA")}</span></div>
        <div class="spread" style="min-height:52px"><span>Creatine switch</span>
          <${Toggle} on=${!!s.profile.tracksCreatine} label="Show the creatine switch" onChange=${(v) => update((x) => { x.profile.tracksCreatine = v; })} /></div>
        <${Picker} title="Bedtime" value=${s.bedtime} onChange=${(v) => update((x) => { x.bedtime = v; })}
          options=${[20, 21, 22, 23, 0, 1, 2].map((h) => ({ value: h, label: `${String(h).padStart(2, "0")}:00` }))} />
        <${Picker} title="Caffeine half-life" value=${s.halfLife} onChange=${(v) => update((x) => { x.halfLife = v; })}
          options=${[3, 4, 5, 6, 7, 8].map((h) => ({ value: h, label: `${h} h` }))} />
      </div>

      <h2 class="section">Your data</h2>
      <div class="panel tight list">
        <button class="list-row" onClick=${exportData}>Export my data</button>
        <label class="list-row" style="cursor:pointer">Import a backup
          <input type="file" accept="application/json,.json" class="hidden" onChange=${(e) => importData(e.target.files[0])} /></label>
        <button class="list-row danger" onClick=${() => confirmDialog({ title: "Erase everything?",
          message: "Every food, goal, weight and workout in NAGISEN on this browser is removed, and setup starts again.",
          actions: [{ title: "Erase and start over", destructive: true, run: resetAll }] })}>Erase all data</button>
      </div>
      <p class="caption">Your history is stored in this browser on this device only. Export it to keep a copy or move it.</p>
      <p class="caption"><a href="about.html">About NAGISEN</a> · <a href="privacy.html">Privacy</a> · <a href="support.html">Support</a></p>
    <//>`;
}
