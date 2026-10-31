import { html, useState, dayKey, addDays, number } from "./lib.js";
import { useStore, update, entriesOn, foodKey } from "./store.js";
import { Heading, Sheet, Icon, Picker } from "./ui.js";
import { money, currency } from "./region.js";

/** What one logged entry cost, from the price you saved for that food; null when there is none. */
export function entryCost(s, e) {
  const price = s.prices[foodKey(e.food)];
  if (!price) return null;
  const per = e.food.gramsPerServing;
  if (price.per100g != null) {
    const grams = e.unit === "grams" ? e.amount : per ? e.amount * per : null;
    return grams == null ? null : (price.per100g * grams) / 100;
  }
  const servings = e.unit === "servings" ? e.amount : per ? e.amount / per : null;
  return servings == null ? null : price.perServing * servings;
}

export function Lab() {
  const s = useStore();
  const [pricing, setPricing] = useState(null);
  const today = dayKey();
  const costOf = (day) => entriesOn(s, day).reduce((t, e) => t + (entryCost(s, e) || 0), 0);
  const week = Array.from({ length: 7 }, (_, i) => costOf(addDays(today, -i))).reduce((a, b) => a + b, 0);
  const unpriced = entriesOn(s, today).filter((e) => entryCost(s, e) == null).length;

  const recent = [];
  const seen = new Set();
  for (const e of [...s.entries].reverse()) {
    const k = foodKey(e.food);
    if (!seen.has(k)) { seen.add(k); recent.push(e.food); }
    if (recent.length >= 30) break;
  }

  return html`
    <div class="screen">
      <${Heading} kicker="NAGISEN Lab" title="Kitchen" sub="What you eat, and what it costs." />
      <section class="panel stack" style="gap:16px">
        <div class="kicker">Cost</div>
        <div class="row" style="gap:28px">
          <div><div class="serif" style="font-size:34px">${money(costOf(today))}</div><div class="caption">today</div></div>
          <div><div class="serif" style="font-size:34px">${money(week)}</div><div class="caption">last 7 days</div></div>
        </div>
        ${unpriced > 0 && html`<div class="caption">${unpriced} of today's foods ${unpriced === 1 ? "has" : "have"} no price yet.</div>`}
      </section>

      <h2 class="section">Prices for your foods</h2>
      ${recent.length === 0 ? html`<p class="muted">Foods you log show up here, ready for a price.</p>` : html`
        <div class="panel tight list">
          ${recent.map((f) => {
            const p = s.prices[foodKey(f)];
            return html`
              <button class="list-row" onClick=${() => setPricing(f)}>
                <div class="grow"><div>${f.name}</div><div class="caption">${f.brand || f.serving}</div></div>
                <div class="small ${p ? "" : "muted"}">${p ? (p.per100g != null ? `${money(p.per100g)} / 100 g` : `${money(p.perServing)} / serving`) : "Add price"}</div>
                <${Icon} name="right" size="sm" />
              </button>`;
          })}
        </div>`}
    </div>
    ${pricing && html`<${PriceEditor} food=${pricing} onClose=${() => setPricing(null)} />`}`;
}

function PriceEditor({ food, onClose }) {
  const s = useStore();
  const key = foodKey(food);
  const saved = s.prices[key];
  const [unit, setUnit] = useState(saved?.perServing != null || !food.gramsPerServing ? "servings" : "grams");
  const [amount, setAmount] = useState(String(saved?.bought ?? (unit === "grams" ? 100 : 1)));
  const [paid, setPaid] = useState(saved?.paid != null ? String(saved.paid) : "");
  const a = number(amount), p = number(paid);
  const valid = a > 0 && p >= 0 && paid !== "";
  const save = () => {
    update((x) => {
      x.prices[key] = unit === "grams" ? { per100g: (p / a) * 100, bought: a, paid: p } : { perServing: p / a, bought: a, paid: p };
    });
    onClose();
  };
  return html`
    <${Sheet} title=${food.name} onClose=${onClose} action=${save} actionLabel="Save" actionEnabled=${valid}>
      <p class="muted" style="margin:0">Enter what you bought and what you paid in ${currency()}.</p>
      <div class="panel tight list">
        ${food.gramsPerServing && html`<${Picker} title="Bought by" value=${unit} onChange=${setUnit}
          options=${[{ value: "grams", label: "Weight" }, { value: "servings", label: "Servings" }]} />`}
        <label class="spread" style="min-height:52px"><span>${unit === "grams" ? "Amount in grams" : "Number of servings"}</span>
          <input class="plain-input" inputmode="decimal" style="text-align:right;width:110px" value=${amount}
            onInput=${(e) => setAmount(e.target.value)} aria-label="Amount bought" /></label>
        <label class="spread" style="min-height:52px"><span>Paid in ${currency()}</span>
          <input class="plain-input" inputmode="decimal" style="text-align:right;width:110px" value=${paid} placeholder="0"
            onInput=${(e) => setPaid(e.target.value)} aria-label="Price paid" /></label>
      </div>
      ${valid && html`<div class="caption">${unit === "grams" ? `${money((p / a) * 100)} per 100 g` : `${money(p / a)} per serving`}</div>`}
      ${saved && html`<button class="link danger" style="text-align:left" onClick=${() => { update((x) => { delete x.prices[key]; }); onClose(); }}>Remove price</button>`}
    <//>`;
}
