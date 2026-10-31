// The same estimates the iPhone app uses (EnergyMath, OnboardingPlan, CaffeineMath).

export const ACTIVITY = {
  sedentary: { label: "Mostly sitting", factor: 1.2 },
  light: { label: "Lightly active", factor: 1.375 },
  moderate: { label: "Moderately active", factor: 1.55 },
  veryActive: { label: "Very active", factor: 1.725 },
};

export function activityFor(trainingDays) {
  if (trainingDays <= 1) return "sedentary";
  if (trainingDays <= 3) return "light";
  if (trainingDays <= 5) return "moderate";
  return "veryActive";
}

/** Mifflin–St Jeor, times activity, then ±300/250 for cutting or bulking, rounded to 25 kcal. */
export function dailyCalories({ weight, height, age, equation, activity, direction }) {
  const resting = 10 * weight + 6.25 * height - 5 * age + (equation === "male" ? 5 : -161);
  const maintenance = resting * ACTIVITY[activity].factor;
  const adjustment = direction === "lose" ? -300 : direction === "gain" ? 250 : 0;
  return Math.round(Math.max(1200, maintenance + adjustment) / 25) * 25;
}

/** Protein 2 g/kg when cutting, 1.8 g/kg otherwise; fat about 27% of calories; carbs fill the rest. */
export function targetsFor({ equation, age, height, weight, direction, trainingDays }) {
  if (!equation || !(age >= 13 && age <= 100) || !(height >= 120 && height <= 230) ||
      !(weight >= 30 && weight <= 300) || !direction || trainingDays == null) return null;
  const calories = dailyCalories({ weight, height, age, equation, activity: activityFor(trainingDays), direction });
  const protein = Math.round(weight * (direction === "lose" ? 2.0 : 1.8));
  const fat = Math.round(calories * 0.27 / 9);
  const carbs = Math.max(0, Math.floor((calories - 4 * protein - 9 * fat) / 4));
  const water = Math.min(4000, Math.max(1500, Math.round(weight * 35 / 250) * 250));
  return { goals: { calories, protein, carbs, fat }, water };
}

/** Caffeine left from one dose after `hours`, on a half-life curve. */
export const remaining = (mg, hours, halfLife) =>
  mg <= 0 ? 0 : hours <= 0 ? mg : halfLife <= 0 ? 0 : mg * Math.pow(0.5, hours / halfLife);

export const caffeineLevel = (entries, at, halfLife) =>
  entries.reduce((sum, e) => {
    const hours = (at - new Date(e.at)) / 3600000;
    return hours < 0 ? sum : sum + remaining(e.mg, hours, halfLife);
  }, 0);

export const BORDERS = [
  { tier: 0, name: "No border yet", at: 0, colors: ["var(--line)"] },
  { tier: 1, name: "Washi", at: 10, colors: ["#F2EBDF", "#CFC3B0", "#F2EBDF"] },
  { tier: 2, name: "Hinoki", at: 30, colors: ["#E8D1A8", "#9C7650", "#D2B385", "#E8D1A8"] },
  { tier: 3, name: "Copper", at: 60, colors: ["#E0A070", "#8A4B24", "#C7834F", "#E0A070"] },
  { tier: 4, name: "Bronze", at: 100, colors: ["#D6A665", "#6F4A24", "#B08045", "#D6A665"] },
  { tier: 5, name: "Silver", at: 160, colors: ["#F4F6F7", "#8F989F", "#DADFE3", "#F4F6F7"] },
  { tier: 6, name: "Gold", at: 250, colors: ["#F5DFA3", "#A97A3E", "#E9C77B", "#F5DFA3"] },
  { tier: 7, name: "Sakura", at: 360, colors: ["#F9E6EA", "#C98A98", "#F0C6CF", "#F9E6EA"] },
  { tier: 8, name: "Indigo", at: 500, colors: ["#8FA3D6", "#223666", "#4C64A3", "#8FA3D6"] },
  { tier: 9, name: "Jade", at: 680, colors: ["#9AD5BC", "#1F5E4A", "#4FA285", "#9AD5BC"] },
  { tier: 10, name: "Sumi", at: 900, colors: ["#8A8A92", "#111113", "#4A4A50", "#8A8A92"] },
  { tier: 11, name: "Kintsugi", at: 1200, colors: ["#17171A", "#E2BC66", "#17171A", "#F5DC92", "#17171A"] },
];
export const ENJI = ["#8B2B49", "#3A0C18", "#6E1B33", "#B04A66", "#3A0C18", "#8B2B49"];
