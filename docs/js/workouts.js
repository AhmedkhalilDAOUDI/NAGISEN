import { html, useState, useEffect, dayKey, longDate, number, fmt, uid, parseDay } from "./lib.js";
import { useStore, update, streak } from "./store.js";
import { Heading, Sheet, Icon, Picker, Menu, confirmDialog } from "./ui.js";

const EXERCISES = ["Bench press", "Incline dumbbell press", "Cable fly", "Overhead press", "Lateral raise", "Pull-up",
  "Lat pulldown", "Barbell row", "Seated cable row", "Biceps curl", "Triceps pushdown", "Squat", "Romanian deadlift",
  "Leg press", "Split squat", "Leg curl", "Calf raise", "Plank"];
const ACTIVITIES = ["Strength training", "Running", "Walking", "Cycling", "Boxing", "Swimming", "HIIT", "Yoga", "Mobility", "Other"];
const SPLITS = {
  "Push / Pull / Legs": ["Push", "Pull", "Legs", "Push", "Pull", "Legs", "Rest"],
  "Upper / Lower": ["Upper", "Lower", "Rest", "Upper", "Lower", "Cardio", "Rest"],
  "Full Body": ["Full Body", "Rest", "Full Body", "Rest", "Full Body", "Cardio", "Rest"],
  "Boxing + Strength": ["Boxing", "Upper", "Conditioning", "Lower", "Boxing", "Full Body", "Rest"],
};
const WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

let questCatalog = null;
const loadQuests = () => (questCatalog ??= fetch("data/quests.json").then((r) => r.json()));

/** The same quest all day, a different one tomorrow; "another" moves to the next one in the list. */
function questFor(day, quests, offset = 0) {
  let hash = 0;
  for (const c of day) hash = (hash * 31 + c.charCodeAt(0)) >>> 0;
  return quests[(hash + offset) % quests.length];
}

const TROPHIES = [
  ["First session", (s) => s.workouts.length >= 1], ["Ten sessions", (s) => s.workouts.length >= 10],
  ["Fifty sessions", (s) => s.workouts.length >= 50], ["First record", (s) => s.records.length >= 1],
  ["Ten records", (s) => s.records.length >= 10], ["Week streak", (s) => streak(s) >= 7],
  ["Month streak", (s) => streak(s) >= 30], ["Quest taker", (s) => Object.keys(s.questsDone).length >= 5],
];

export function Workouts() {
  const s = useStore();
  const today = dayKey();
  const [quests, setQuests] = useState([]);
  const [offset, setOffset] = useState(0);
  const [sheet, setSheet] = useState(null);
  useEffect(() => { loadQuests().then(setQuests).catch(() => {}); }, []);
  const quest = quests.length ? questFor(today, quests, offset) : null;
  const questDone = s.questsDone[today] === quest?.id;
  const focus = s.split ? s.split.days[(parseDay(today).getDay() + 6) % 7] : null;
  const best = {};
  for (const r of s.records) if (!best[r.exercise] || r.kg > best[r.exercise].kg) best[r.exercise] = r;
  const recent = [...s.workouts].sort((a, b) => b.day.localeCompare(a.day)).slice(0, 6);

  return html`
    <div class="screen">
      <${Heading} kicker="NAGISEN Move" title="Keep moving" sub=${longDate(today)} />

      ${quest && html`
        <section class="panel stack" style="gap:10px">
          <div class="spread"><div class="kicker">Today's side quest</div>
            <button class="link small" onClick=${() => setOffset(offset + 1)}>Another</button></div>
          <div class="caption" style="text-transform:uppercase;letter-spacing:0.18em">${quest.category} · ${quest.minutes} min</div>
          <div class="serif" style="font-size:22px">${quest.title}</div>
          <div class="muted">${quest.detail}</div>
          <button class=${questDone ? "chip on" : "chip"} style="align-self:flex-start"
            onClick=${() => update((x) => { questDone ? delete x.questsDone[today] : (x.questsDone[today] = quest.id); })}>
            <${Icon} name="check" size="sm" />${questDone ? "Done" : "Mark done"}</button>
        </section>`}

      <section class="panel stack" style="gap:12px">
        <div class="spread"><div class="kicker">Workouts</div>
          <button class="icon-btn" aria-label="Log a workout" onClick=${() => setSheet("workout")}><${Icon} name="plus" size="sm" /></button></div>
        ${recent.length === 0 ? html`<div class="muted">Log a session to start your history.</div>` : html`
          <div class="list">${recent.map((w) => html`
            <div class="list-row"><div class="grow"><div>${w.activity}</div>
              <div class="caption">${parseDay(w.day).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" })}</div></div>
              <div class="small">${w.minutes} min</div>
              <${Menu} title=${w.activity} actions=${[{ title: "Delete workout", icon: "trash", destructive: true,
                run: () => update((x) => { x.workouts = x.workouts.filter((y) => y.id !== w.id); }) }]} />
            </div>`)}</div>`}
      </section>

      <section class="panel stack" style="gap:12px">
        <div class="spread"><div class="row" style="gap:8px"><${Icon} name="dumbbell" /><div>
          <div class="kicker">Personal records</div><div class="serif" style="font-size:20px">Track your best lifts</div></div></div>
          <button class="icon-btn" aria-label="Add a record" onClick=${() => setSheet("record")}><${Icon} name="plus" size="sm" /></button></div>
        ${Object.keys(best).length === 0 ? html`<div class="caption">Add your first PR.</div>` : html`
          <div class="list">${Object.values(best).map((r) => html`
            <div class="list-row"><span class="grow">${r.exercise}</span><span class="serif" style="font-size:18px">${fmt(r.kg, 1)} kg × ${r.reps}</span></div>`)}</div>`}
      </section>

      <section class="panel stack" style="gap:12px">
        <div class="spread"><div class="kicker row" style="gap:6px"><${Icon} name="calendar" size="sm" />Workout split</div>
          <button class="link small" onClick=${() => setSheet("split")}>${s.split ? "Change" : "Choose"}</button></div>
        ${s.split ? html`
          <div class="serif" style="font-size:22px">Today: ${focus}</div>
          <div class="caption">${s.split.name}</div>
          <div class="week">${s.split.days.map((d, i) => html`<div><div class="caption" style="font-weight:600">${WEEKDAYS[i].slice(0, 3)}</div><div class="small">${d}</div></div>`)}</div>`
        : html`<div class="serif" style="font-size:22px">Plan your training week</div><div class="caption">Choose a split for each day of the week.</div>`}
      </section>

      <h2 class="section">Trophies</h2>
      <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:14px">
        ${TROPHIES.map(([name, earned]) => {
          const on = earned(s);
          return html`<div class="stack center" style="gap:6px;align-items:center;opacity:${on ? 1 : 0.55}">
            <div class="mark" style="width:54px;height:54px;gap:4px">
              <div class="sun" style=${`width:34px;height:34px;display:grid;place-items:center;${on ? "" : "background:none;border:0.75px solid var(--line)"}`}>
                <${Icon} name="trophy" size="sm" cls=${on ? "" : "muted"} /></div>
              <div class="l1" style=${`width:48px;height:2px;${on ? "" : "background:var(--line)"}`} />
              <div class="l2" style=${`width:30px;height:1.2px;${on ? "" : "background:var(--line)"}`} /></div>
            <div class="caption" style="line-height:1.2">${name}</div></div>`;
        })}
      </div>
    </div>
    ${sheet === "workout" && html`<${LogWorkout} onClose=${() => setSheet(null)} />`}
    ${sheet === "record" && html`<${LogRecord} onClose=${() => setSheet(null)} />`}
    ${sheet === "split" && html`<${ChooseSplit} onClose=${() => setSheet(null)} />`}`;
}

function LogWorkout({ onClose }) {
  const [activity, setActivity] = useState(ACTIVITIES[0]);
  const [minutes, setMinutes] = useState("45");
  const m = number(minutes);
  return html`
    <${Sheet} title="Log a workout" onClose=${onClose} actionLabel="Save" actionEnabled=${m > 0 && m <= 600}
      action=${() => { update((x) => { x.workouts.push({ id: uid(), day: dayKey(), activity, minutes: Math.round(m) }); }); onClose(); }}>
      <div class="panel tight list">
        <${Picker} title="Activity" value=${activity} onChange=${setActivity} options=${ACTIVITIES.map((a) => ({ value: a, label: a }))} />
        <label class="spread" style="min-height:52px"><span>Minutes</span>
          <input class="plain-input" inputmode="numeric" style="text-align:right;width:90px" value=${minutes}
            onInput=${(e) => setMinutes(e.target.value)} aria-label="Minutes" /></label>
      </div>
    <//>`;
}

function LogRecord({ onClose }) {
  const s = useStore();
  const [exercise, setExercise] = useState(EXERCISES[0]);
  const [kg, setKg] = useState("");
  const [reps, setReps] = useState("5");
  const w = number(kg), r = number(reps);
  const previous = s.records.filter((x) => x.exercise === exercise).reduce((b, x) => Math.max(b, x.kg), 0);
  const save = () => {
    update((x) => { x.records.push({ id: uid(), day: dayKey(), exercise, kg: w, reps: Math.round(r) }); });
    if (w > previous && previous > 0) confirmDialog({ title: "New personal record", message: `${exercise}: ${fmt(w, 1)} kg, up from ${fmt(previous, 1)} kg.`, cancel: "Nice" });
    onClose();
  };
  return html`
    <${Sheet} title="Personal record" onClose=${onClose} action=${save} actionLabel="Save" actionEnabled=${w > 0 && r > 0}>
      <div class="panel tight list">
        <${Picker} title="Exercise" value=${exercise} onChange=${setExercise} options=${EXERCISES.map((e) => ({ value: e, label: e }))} />
        <label class="spread" style="min-height:52px"><span>Weight</span><span class="row" style="gap:8px">
          <input class="plain-input" inputmode="decimal" style="text-align:right;width:90px" value=${kg} placeholder="0"
            onInput=${(e) => setKg(e.target.value)} aria-label="Weight in kilograms" /><span class="muted">kg</span></span></label>
        <label class="spread" style="min-height:52px"><span>Reps</span>
          <input class="plain-input" inputmode="numeric" style="text-align:right;width:90px" value=${reps}
            onInput=${(e) => setReps(e.target.value)} aria-label="Reps" /></label>
      </div>
      ${previous > 0 && html`<div class="caption">Your best ${exercise.toLowerCase()} so far: ${fmt(previous, 1)} kg.</div>`}
    <//>`;
}

function ChooseSplit({ onClose }) {
  const s = useStore();
  const [name, setName] = useState(s.split?.name || Object.keys(SPLITS)[0]);
  const [days, setDays] = useState(s.split?.days || SPLITS[Object.keys(SPLITS)[0]]);
  return html`
    <${Sheet} title="Workout split" onClose=${onClose} actionLabel="Save"
      action=${() => { update((x) => { x.split = { name, days }; }); onClose(); }}>
      <div class="row" style="gap:8px;flex-wrap:wrap">
        ${Object.keys(SPLITS).map((n) => html`<button class=${n === name ? "chip on" : "chip"} onClick=${() => { setName(n); setDays(SPLITS[n]); }}>${n}</button>`)}
      </div>
      <div class="panel tight list">
        ${days.map((d, i) => html`
          <label class="spread" style="min-height:52px"><span class="muted">${WEEKDAYS[i]}</span>
            <input class="plain-input" style="text-align:right;width:160px" value=${d} maxlength="40" aria-label=${WEEKDAYS[i]}
              onInput=${(e) => { const next = [...days]; next[i] = e.target.value; setDays(next); setName("Custom"); }} /></label>`)}
      </div>
      ${s.split && html`<button class="link danger" style="text-align:left" onClick=${() => { update((x) => { x.split = null; }); onClose(); }}>Remove split</button>`}
    <//>`;
}
