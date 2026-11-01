-- NAGISEN waitlist, filled by marketing/waitlist/index.html.
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run. Safe to re-run.
-- Visitors can only add an address. Nobody can read the list through the API; read it in
-- the dashboard (Table Editor → waitlist) or export it as CSV from there.

create table if not exists public.waitlist (
    email text primary key check (char_length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    created_at timestamptz not null default now()
);

alter table public.waitlist enable row level security;

drop policy if exists "waitlist insert by anyone" on public.waitlist;
create policy "waitlist insert by anyone" on public.waitlist
    for insert to anon, authenticated with check (true);
