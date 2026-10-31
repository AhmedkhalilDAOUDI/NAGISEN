import { html, useState, number, dayKey, fmt } from "./lib.js";
import { update } from "./store.js";
import { targetsFor, activityFor } from "./math.js";
import { Choice, Icon } from "./ui.js";
import { COUNTRIES, currencyFor } from "./region.js";

const QUESTIONS = 6;

/** First launch: a few quiet questions, one per page, then the targets they lead to. */
export function Onboarding() {
  const [step, setStep] = useState(0);
  const [a, setA] = useState({ country: (navigator.language.split("-")[1] || "MA").toUpperCase() });
  const set = (k, v) => setA({ ...a, [k]: v });
  const body = { age: number(a.age), height: number(a.height), weight: number(a.weight) };
  const plan = targetsFor({ ...a, ...body });

  const can = [true, !!a.equation,
    body.age >= 13 && body.age <= 100 && body.height >= 120 && body.height <= 230 && body.weight >= 30 && body.weight <= 300,
    !!a.direction, a.trainingDays != null, true, a.creatine != null, !!plan][step];

  function finish() {
    update((s) => {
      s.onboarded = true;
      s.profile = { equation: a.equation, age: body.age, height: body.height, direction: a.direction,
        trainingDays: a.trainingDays, activity: activityFor(a.trainingDays), country: a.country, tracksCreatine: a.creatine };
      s.goals = plan.goals;
      s.waterGoal = plan.water;
      s.weights.push({ day: dayKey(), kg: body.weight });
    });
  }

  const q = (kicker, title, detail) => html`
    <div class="stack" style="gap:10px">
      <div class="kicker">${kicker}</div>
      <h1 class="serif" style="font-size:32px;margin:0;line-height:1.15">${title}</h1>
      ${detail && html`<div class="muted">${detail}</div>`}
    </div>`;

  const num = (key, label, unit) => html`
    <label class="spread" style="min-height:60px">
      <span class="muted">${label}</span>
      <span class="row" style="gap:10px">
        <input class="plain-input serif" inputmode="decimal" placeholder="0" value=${a[key] || ""}
          onInput=${(e) => set(key, e.target.value)} style="font-size:24px;text-align:right;width:110px" aria-label=${label} />
        <span class="muted" style="width:44px">${unit}</span>
      </span>
    </label>`;

  const pages = [
    html`
      <div class="stack" style="gap:22px;margin-top:auto">
        <div class="mark"><div class="sun" /><div class="l1" /><div class="l2" /></div>
        <div class="kicker" style="letter-spacing:0.5em">NAGISEN</div>
        <h1 class="serif" style="font-size:38px;margin:0">Let's make it yours.</h1>
        <p class="muted" style="margin:0">Six short questions, so your daily targets fit your body and your goal. You start with a clean slate: nothing logged, nothing borrowed.</p>
      </div>`,
    html`${q("Your body", "Which calorie equation fits you?", "Used only to estimate how much energy you burn.")}
      <div class="stack" style="gap:10px">
        <${Choice} title="Female" on=${a.equation === "female"} onClick=${() => set("equation", "female")} />
        <${Choice} title="Male" on=${a.equation === "male"} onClick=${() => set("equation", "male")} />
      </div>`,
    html`${q("About you", "Age, height and weight", "Your starting point. Weight goes into your progress as today's entry.")}
      <div class="panel tight list">${num("age", "Age", "years")}${num("height", "Height", "cm")}${num("weight", "Weight", "kg")}</div>`,
    html`${q("Your goal", "What are you working toward?")}
      <div class="stack" style="gap:10px">
        ${[["lose", "Cut", "Lose fat, about 300 kcal under maintenance"], ["maintain", "Maintain", "Hold your weight where it is"],
           ["gain", "Bulk", "Build, about 250 kcal over maintenance"]].map(([v, t, d]) =>
          html`<${Choice} title=${t} detail=${d} on=${a.direction === v} onClick=${() => set("direction", v)} />`)}
      </div>`,
    html`${q("Training", "How often do you train?", "Sets the activity level in your calorie estimate.")}
      <div class="stack" style="gap:10px">
        ${[[1, "Rarely", "0 to 1 day a week"], [3, "Sometimes", "2 to 3 days a week"], [5, "Often", "4 to 5 days a week"],
           [7, "Almost daily", "6 to 7 days a week"]].map(([v, t, d]) =>
          html`<${Choice} title=${t} detail=${d} on=${a.trainingDays === v} onClick=${() => set("trainingDays", v)} />`)}
      </div>`,
    html`${q("Where you live", "Your country", "Prices you enter are shown in its currency.")}
      <div class="panel tight">
        <label class="spread" style="min-height:56px;position:relative">
          <span>Country</span>
          <span class="row accent" style="gap:6px">${COUNTRIES.find((c) => c.code === a.country)?.name || a.country}<${Icon} name="down" size="sm" /></span>
          <select aria-label="Country" onChange=${(e) => set("country", e.target.value)} style="position:absolute;inset:0;opacity:0">
            ${COUNTRIES.map((c) => html`<option value=${c.code} selected=${c.code === a.country}>${c.name}</option>`)}
          </select>
        </label>
      </div>
      <div class="caption">Currency: ${currencyFor(a.country)}</div>`,
    html`${q("Supplements", "Do you take creatine daily?", "Adds a daily switch on your Dashboard to mark it taken.")}
      <div class="stack" style="gap:10px">
        <${Choice} title="Yes" on=${a.creatine === true} onClick=${() => set("creatine", true)} />
        <${Choice} title="No" on=${a.creatine === false} onClick=${() => set("creatine", false)} />
      </div>`,
    html`${q("Your targets", "Here's where you start", "You can change any of this later in Goals.")}
      ${plan && html`
        <div class="panel stack" style="gap:20px;padding:22px">
          <div><div class="big-number accent">${fmt(plan.goals.calories)}</div><div class="muted">kcal a day</div></div>
          <div class="macro-grid">
            ${[["Protein", plan.goals.protein, "var(--protein)"], ["Carbs", plan.goals.carbs, "var(--carbs)"], ["Fat", plan.goals.fat, "var(--fat)"]]
              .map(([n, g, c]) => html`<div><div class="kicker" style=${`color:${c}`}>${n}</div><div class="value">${g} g</div></div>`)}
          </div>
          <hr class="divider" />
          <div class="spread small"><span class="muted">Water</span><span>${fmt(plan.water / 1000, 2)} L a day</span></div>
        </div>`}`,
  ];

  return html`
    <div class="screen" style="min-height:100vh;padding-bottom:calc(env(safe-area-inset-bottom) + 24px)">
      ${step > 0 && html`
        <div class="row">
          <button class="icon-btn" style="border:0;background:none" aria-label="Back" onClick=${() => setStep(step - 1)}><${Icon} name="left" /></button>
          <div class="progress" aria-label=${`Step ${step} of ${QUESTIONS + 1}`}>
            ${Array.from({ length: QUESTIONS + 1 }, (_, i) => html`<span class=${i < step ? "on" : ""} />`)}
          </div>
        </div>`}
      <div class="stack" style="gap:26px;flex:1;padding-top:${step ? 14 : 0}px" key=${step}>${pages[step]}</div>
      <button class="primary" disabled=${!can}
        onClick=${() => (step === QUESTIONS + 1 ? finish() : setStep(step + 1))}>
        ${step === 0 ? "Begin" : step === QUESTIONS + 1 ? "Start NAGISEN" : "Continue"}
      </button>
    </div>`;
}
