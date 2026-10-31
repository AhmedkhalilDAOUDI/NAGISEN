import { html, useState, useEffect, useRef, fmt, gramsIn, number, uid } from "./lib.js";
import { useStore, update, usualFoods, logFood } from "./store.js";
import { Sheet, Icon, Picker } from "./ui.js";

const MEALS = ["Breakfast", "Lunch", "Dinner", "Snacks"];

/** Searches Open Food Facts; values are per serving when the serving has a weight, else per 100 g.
 *  The web uses the classic search endpoint because it's the one that allows browser requests (CORS). */
export async function searchFoods(query, signal) {
  const fields = "code,product_name,brands,serving_size,quantity,nutriments";
  const url = `https://world.openfoodfacts.org/cgi/search.pl?search_terms=${encodeURIComponent(query)}&search_simple=1&action=process&json=1&page_size=24&fields=${fields}`;
  let response;
  try { response = await fetch(url, { signal }); } catch (e) {
    if (e.name === "AbortError") throw e;
    throw new Error("Food search is unavailable right now. Check your connection and try again.");
  }
  if (response.status === 429) throw new Error("Too many searches in a row. Wait a few seconds and try again.");
  if (!response.ok) throw new Error("Food search is unavailable right now. Try again in a moment.");
  const { products = [] } = await response.json();
  return products.map(asFood).filter(Boolean);
}

function asFood(p) {
  const name = (p.product_name || "").trim();
  const n = p.nutriments || {};
  const kcal = n["energy-kcal_100g"];
  if (!name || !Number.isFinite(kcal) || kcal < 0 || kcal >= 10000) return null;
  const grams = gramsIn(p.serving_size);
  const factor = (grams || 100) / 100;
  if (factor <= 0 || factor > 100) return null;
  return {
    name, brand: Array.isArray(p.brands) ? p.brands.join(", ") : p.brands || "",
    serving: grams ? p.serving_size.trim() : "100 g", gramsPerServing: grams || 100,
    calories: Math.round(kcal * factor),
    protein: Math.max(0, (n.proteins_100g || 0) * factor), carbs: Math.max(0, (n.carbohydrates_100g || 0) * factor),
    fat: Math.max(0, (n.fat_100g || 0) * factor), barcode: p.code, source: "Open Food Facts",
  };
}

export function AddFood({ day, meal, onClose }) {
  const s = useStore();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState([]);
  const [state, setState] = useState("idle");
  const [picked, setPicked] = useState(null);
  const [manual, setManual] = useState(false);
  const usual = usualFoods(s);
  const timer = useRef();

  useEffect(() => {
    clearTimeout(timer.current);
    const q = query.trim();
    if (q.length < 3) { setResults([]); setState("idle"); return; }
    const controller = new AbortController();
    timer.current = setTimeout(async () => {
      setState("loading");
      try { setResults(await searchFoods(q, controller.signal)); setState("done"); }
      catch (e) { if (e.name !== "AbortError") setState(e.message); }
    }, 700);
    return () => controller.abort();
  }, [query]);

  const mine = s.customFoods.filter((f) => query.trim().length > 1 && f.name.toLowerCase().includes(query.trim().toLowerCase()));
  const row = (f) => html`
    <button class="list-row" onClick=${() => setPicked(f)}>
      <div class="grow"><div>${f.name}</div><div class="caption">${[f.brand, f.serving].filter(Boolean).join(" · ")}</div></div>
      <div class="small muted">${fmt(f.calories)} kcal</div>
    </button>`;

  if (picked) return html`<${Amount} food=${picked} day=${day} meal=${meal} onBack=${() => setPicked(null)} onDone=${onClose} />`;
  if (manual) return html`<${ManualFood} onBack=${() => setManual(false)} onSaved=${(f) => { setManual(false); setPicked(f); }} />`;

  return html`
    <${Sheet} title=${`Add to ${meal}`} onClose=${onClose}>
      <label class="field row" style="gap:10px">
        <${Icon} name="search" size="sm" />
        <input class="plain-input" style="padding:0" placeholder="Food or brand" value=${query} autofocus
          onInput=${(e) => setQuery(e.target.value)} aria-label="Search foods" />
      </label>
      <button class="link" style="text-align:left" onClick=${() => setManual(true)}>Add a food by hand</button>
      ${query.trim().length < 3 ? html`
        ${usual.length > 0 && html`<h2 class="section">Your usual foods</h2><div class="panel tight list">${usual.map(row)}</div>`}
        ${usual.length === 0 && html`<p class="muted">Search for a food, or add one by hand. The foods you log most will wait here.</p>`}`
      : html`
        ${mine.length > 0 && html`<h2 class="section">Your foods</h2><div class="panel tight list">${mine.map(row)}</div>`}
        <h2 class="section">Open Food Facts</h2>
        ${state === "loading" && html`<p class="muted">Searching…</p>`}
        ${state === "done" && results.length === 0 && html`<p class="muted">Nothing found. Try another word, or add it by hand.</p>`}
        ${state !== "loading" && state !== "done" && state !== "idle" && html`<p class="accent">${state}</p>`}
        ${results.length > 0 && html`<div class="panel tight list">${results.map(row)}</div>`}`}
    <//>`;
}

function Amount({ food, day, meal: startMeal, onBack, onDone }) {
  const [meal, setMeal] = useState(startMeal);
  const [unit, setUnit] = useState(food.gramsPerServing ? "grams" : "servings");
  const [amount, setAmount] = useState(food.gramsPerServing ? String(food.gramsPerServing) : "1");
  const value = number(amount);
  const factor = value ? (unit === "grams" ? value / food.gramsPerServing : value) : 0;
  const line = (name, v, color) => html`<div class="spread"><span style=${`color:${color}`}>${name}</span><span>${fmt(v * factor, 1)} g</span></div>`;
  return html`
    <${Sheet} title=${food.name} onClose=${onBack} action=${() => { logFood(food, { day, meal, unit, amount: value }); onDone(); }}
      actionLabel="Log" actionEnabled=${value > 0}>
      <div><div class="big-number accent">${fmt(food.calories * factor)}</div><div class="muted">kcal${food.brand ? ` · ${food.brand}` : ""}</div></div>
      <div class="panel stack" style="gap:10px">
        ${line("Protein", food.protein, "var(--protein)")}${line("Carbs", food.carbs, "var(--carbs)")}${line("Fat", food.fat, "var(--fat)")}
      </div>
      <div class="panel tight list">
        <${Picker} title="Meal" value=${meal} options=${MEALS.map((m) => ({ value: m, label: m }))} onChange=${setMeal} />
        ${food.gramsPerServing && html`<${Picker} title="Unit" value=${unit} onChange=${(u) => { setUnit(u); setAmount(u === "grams" ? String(food.gramsPerServing) : "1"); }}
          options=${[{ value: "grams", label: "Grams" }, { value: "servings", label: `Servings (${food.serving})` }]} />`}
        <label class="spread" style="min-height:52px"><span>${unit === "grams" ? "Grams" : "Servings"}</span>
          <input class="plain-input" inputmode="decimal" style="text-align:right;width:120px" value=${amount}
            onInput=${(e) => setAmount(e.target.value)} aria-label="Amount" /></label>
      </div>
      ${food.source && html`<div class="caption">Nutrition from ${food.source}. Check the package when it matters.</div>`}
    <//>`;
}

function ManualFood({ onBack, onSaved }) {
  const [f, setF] = useState({ name: "", serving: "100 g", calories: "", protein: "", carbs: "", fat: "" });
  const set = (k) => (e) => setF({ ...f, [k]: e.target.value });
  const valid = f.name.trim() && number(f.calories) >= 0 && f.calories !== "";
  const save = () => {
    const food = { id: uid(), name: f.name.trim(), brand: "", serving: f.serving.trim() || "1 serving",
      gramsPerServing: gramsIn(f.serving), calories: Math.round(number(f.calories)),
      protein: number(f.protein) || 0, carbs: number(f.carbs) || 0, fat: number(f.fat) || 0, source: "" };
    update((s) => { s.customFoods.push(food); });
    onSaved(food);
  };
  const field = (k, label, unit, color) => html`
    <label class="spread" style="min-height:52px"><span style=${color ? `color:${color}` : ""}>${label}</span>
      <span class="row" style="gap:8px"><input class="plain-input" inputmode="decimal" style="text-align:right;width:100px" value=${f[k]}
        onInput=${set(k)} placeholder="0" aria-label=${label} /><span class="muted" style="width:32px">${unit}</span></span></label>`;
  return html`
    <${Sheet} title="New food" onClose=${onBack} action=${save} actionLabel="Save" actionEnabled=${!!valid}>
      <div class="panel tight list">
        <input class="plain-input" placeholder="Name" value=${f.name} onInput=${set("name")} aria-label="Name" />
        <input class="plain-input" placeholder="Serving, such as 100 g or 1 bowl" value=${f.serving} onInput=${set("serving")} aria-label="Serving" />
      </div>
      <h2 class="section">Per serving</h2>
      <div class="panel tight list">
        ${field("calories", "Calories", "kcal")}${field("protein", "Protein", "g", "var(--protein)")}
        ${field("carbs", "Carbs", "g", "var(--carbs)")}${field("fat", "Fat", "g", "var(--fat)")}
      </div>
    <//>`;
}
