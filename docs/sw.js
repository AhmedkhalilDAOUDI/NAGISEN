// Keeps NAGISEN working offline: the app's own files come from the network when there is one (so an
// update shows at once) and from the cache when there isn't. Feed, food search and the coach are online only.
const CACHE = "nagisen-v2";
const SHELL = ["./", "index.html", "app.css", "manifest.webmanifest", "icon-192.png", "icon-512.png", "apple-touch-icon.png",
  "config.js", "data/quests.json", "vendor/preact.js", "vendor/hooks.js", "vendor/htm.js", "vendor/supabase.js",
  "js/main.js", "js/lib.js", "js/math.js", "js/store.js", "js/ui.js", "js/region.js", "js/onboarding.js", "js/dashboard.js",
  "js/food.js", "js/profile.js", "js/lab.js", "js/workouts.js", "js/coach.js", "js/feed.js", "js/feedClient.js", "js/feedSheets.js"];

self.addEventListener("install", (e) => e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting())));
self.addEventListener("activate", (e) => e.waitUntil(
  caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin) return;
  e.respondWith(caches.open(CACHE).then((cache) =>
    fetch(e.request)
      .then((r) => { if (r.ok) cache.put(e.request, r.clone()); return r; })
      .catch(() => cache.match(e.request, { ignoreSearch: true }))));
});
