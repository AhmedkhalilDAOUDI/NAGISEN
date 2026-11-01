// Copy to config.js (ignored by git) and fill in from Supabase → Project Settings → API.
// The publishable key is public by design; row-level security (supabase/waitlist.sql)
// lets visitors add an address and read nothing.
window.WAITLIST_URL = "https://your-project-ref.supabase.co/rest/v1/waitlist";
window.WAITLIST_KEY = "your-publishable-key";
