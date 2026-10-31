import { useEffect, useState, dayKey, addDays, uid } from "./lib.js";

const KEY = "nagisen.web.v1";

/** A brand-new person: nothing logged, nothing borrowed. Setup fills in the rest. */
const fresh = () => ({
  onboarded: false,
  profile: {},
  goals: { calories: 2000, protein: 120, carbs: 250, fat: 65 },
  waterGoal: 2500,
  entries: [],
  water: {},
  caffeine: [],
  halfLife: 5,
  bedtime: 23,
  completedDays: [],
  creatineDays: [],
  weights: [],
  workouts: [],
  records: [],
  split: null,
  questsDone: {},
  prices: {},
  customFoods: [],
  appearance: "system",
  coach: { useContext: false, messages: [] },
});

function load() {
  try {
    const saved = JSON.parse(localStorage.getItem(KEY));
    return saved ? { ...fresh(), ...saved } : fresh();
  } catch {
    return fresh();
  }
}

let state = load();
const listeners = new Set();

function save() {
  try {
    localStorage.setItem(KEY, JSON.stringify(state));
  } catch {
    // Storage full or blocked (private browsing): keep working in memory.
  }
}

/** Applies a change to a copy of the state, saves it, and redraws every screen that reads it. */
export function update(change) {
  const next = structuredClone(state);
  change(next);
  state = next;
  save();
  listeners.forEach((l) => l(state));
}

export const getState = () => state;

export function useStore() {
  const [, setTick] = useState(0);
  useEffect(() => {
    const l = () => setTick((t) => t + 1);
    listeners.add(l);
    return () => listeners.delete(l);
  }, []);
  return state;
}

export function replaceAll(data) {
  state = { ...fresh(), ...data };
  save();
  listeners.forEach((l) => l(state));
}

export const resetAll = () => replaceAll(fresh());

// MARK: - Reading

export const entriesOn = (s, day) => s.entries.filter((e) => e.day === day);

export function totalsOn(s, day) {
  return entriesOn(s, day).reduce(
    (t, e) => ({ calories: t.calories + e.calories, protein: t.protein + e.protein, carbs: t.carbs + e.carbs, fat: t.fat + e.fat }),
    { calories: 0, protein: 0, carbs: 0, fat: 0 }
  );
}

/** Consecutive checked-off days up to today; today counts once it's checked, and doesn't break it before. */
export function streak(s, today = dayKey()) {
  const done = new Set(s.completedDays);
  let day = done.has(today) ? today : addDays(today, -1);
  let count = 0;
  while (done.has(day)) {
    count += 1;
    day = addDays(day, -1);
  }
  return count;
}

/** The foods logged most often, newest first among equals, for one-tap logging. */
export function usualFoods(s, limit = 8) {
  const byKey = new Map();
  for (const e of s.entries) {
    const key = foodKey(e.food);
    const seen = byKey.get(key);
    byKey.set(key, { food: e.food, count: (seen?.count || 0) + 1, last: Math.max(seen?.last || 0, Date.parse(e.createdAt) || 0) });
  }
  return [...byKey.values()].sort((a, b) => b.count - a.count || b.last - a.last).slice(0, limit).map((v) => v.food);
}

export const foodKey = (food) => `${food.name}|${food.brand || ""}`.toLowerCase();

// MARK: - Writing

/** Logs `amount` of a food, in grams or servings; values are stored for the amount eaten. */
export function logFood(food, { day, meal, unit, amount }) {
  const factor = unit === "grams" && food.gramsPerServing ? amount / food.gramsPerServing : amount;
  update((s) => {
    s.entries.push({
      id: uid(), day, meal, food, unit, amount, createdAt: new Date().toISOString(),
      calories: Math.round(food.calories * factor),
      protein: food.protein * factor, carbs: food.carbs * factor, fat: food.fat * factor,
      label: unit === "grams" ? `${amount} g` : `${amount} × ${food.serving || "serving"}`,
    });
  });
}

export const deleteEntry = (id) => update((s) => { s.entries = s.entries.filter((e) => e.id !== id); });

export const toggleDay = (list, day) =>
  update((s) => {
    const set = new Set(s[list]);
    set.has(day) ? set.delete(day) : set.add(day);
    s[list] = [...set];
  });
