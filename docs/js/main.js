import { html, render, useState, useEffect } from "./lib.js";
import { useStore } from "./store.js";
import { Icon, DialogHost } from "./ui.js";
import { Onboarding } from "./onboarding.js";
import { Dashboard } from "./dashboard.js";
import { Lab } from "./lab.js";
import { Workouts } from "./workouts.js";
import { Feed } from "./feed.js";
import { Coach } from "./coach.js";

const SECTIONS = [
  { id: "dashboard", label: "Dashboard", icon: "grid", view: Dashboard },
  { id: "lab", label: "Lab", icon: "basket", view: Lab },
  { id: "workouts", label: "Workouts", icon: "run", view: Workouts },
  { id: "feed", label: "Feed", icon: "people", view: Feed },
];

function useTheme(appearance) {
  useEffect(() => {
    const media = matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const dark = appearance === "dark" || (appearance === "system" && media.matches);
      document.documentElement.dataset.theme = dark ? "dark" : "light";
      document.querySelector('meta[name="theme-color"]')?.setAttribute("content", dark ? "#242427" : "#F9F7F2");
    };
    apply();
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [appearance]);
}

const Intro = () => html`
  <div class="intro" aria-hidden="true">
    <div class="mark">
      <div class="sunbox"><div class="sun" /></div>
      <div class="l1" /><div class="l2" />
      <div class="name">NAGISEN</div>
    </div>
  </div>`;

function App() {
  const s = useStore();
  useTheme(s.appearance);
  // A sign-in or password-reset link arrives as #access_token=…; keep it for Feed and open Feed.
  const [section, setSection] = useState(() => {
    if (location.hash.includes("access_token=")) { sessionStorage.setItem("nagisen.authHash", location.hash.slice(1)); return "feed"; }
    return location.hash.slice(1) || "dashboard";
  });
  const [coach, setCoach] = useState(false);
  useEffect(() => { if (location.hash !== `#${section}`) history.pushState(null, "", `#${section}`); window.scrollTo(0, 0); }, [section]);
  useEffect(() => {
    const follow = () => setSection(location.hash.slice(1) || "dashboard");
    addEventListener("hashchange", follow);
    addEventListener("popstate", follow);
    return () => { removeEventListener("hashchange", follow); removeEventListener("popstate", follow); };
  }, []);

  const current = SECTIONS.find((x) => x.id === section) || SECTIONS[0];
  const View = current.view;
  return html`
    <${Intro} />
    ${!s.onboarded ? html`<${Onboarding} />` : html`
      <main><${View} key=${current.id} /></main>
      <div class="dock-fade" />
      <div class="dock">
        <nav aria-label="Sections">
          ${SECTIONS.map((x) => html`
            <button class=${x.id === current.id ? "on" : ""} aria-current=${x.id === current.id ? "page" : null}
              onClick=${() => setSection(x.id)}>
              <${Icon} name=${x.icon} /><span>${x.label}</span>
            </button>`)}
        </nav>
        <button class="coach" aria-label="NAGISEN AI coach" onClick=${() => setCoach(true)}>
          <${Icon} name="sparkle" />
        </button>
      </div>
      ${coach && html`<${Coach} onClose=${() => setCoach(false)} />`}
    `}
    <${DialogHost} />`;
}

render(html`<${App} />`, document.getElementById("app"));

if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => {});
