-- NAGISEN Feed schema for Supabase.
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Safe to re-run: every statement checks before it creates.

-- Profiles: one per account, holds the public username.
create table if not exists public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    username text not null unique check (username ~ '^[a-z0-9_]{3,20}$'),
    created_at timestamptz not null default now()
);

-- Posts: text, one photo or video, or both.
create table if not exists public.posts (
    id uuid primary key default gen_random_uuid(),
    author_id uuid not null references public.profiles (id) on delete cascade,
    body text not null default '' check (char_length(body) <= 1000),
    media_path text,
    media_kind text check (media_kind in ('photo', 'video')),
    created_at timestamptz not null default now(),
    check ((media_path is null) = (media_kind is null)),
    check (char_length(btrim(body)) > 0 or media_path is not null)
);
create index if not exists posts_created_at_idx on public.posts (created_at desc);

-- Reports: members can file them; only the owner reads them, in the dashboard.
create table if not exists public.reports (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references public.posts (id) on delete cascade,
    reporter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    reason text not null check (char_length(reason) <= 100),
    created_at timestamptz not null default now()
);

-- Blocks: who each member has blocked.
create table if not exists public.blocks (
    blocker_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    blocked_id uuid not null references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    check (blocker_id <> blocked_id)
);

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.reports enable row level security;
alter table public.blocks enable row level security;

-- Profiles: signed-in members see usernames; each member creates and edits only their own.
drop policy if exists "profiles readable by members" on public.profiles;
create policy "profiles readable by members" on public.profiles
    for select to authenticated using (true);
drop policy if exists "profiles insert own" on public.profiles;
create policy "profiles insert own" on public.profiles
    for insert to authenticated with check (id = auth.uid());
drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles
    for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Posts: members see everyone's except people they blocked; write and delete only their own.
drop policy if exists "posts readable except blocked" on public.posts;
create policy "posts readable except blocked" on public.posts
    for select to authenticated using (
        not exists (select 1 from public.blocks b
                    where b.blocker_id = auth.uid() and b.blocked_id = posts.author_id)
    );
drop policy if exists "posts insert own" on public.posts;
create policy "posts insert own" on public.posts
    for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "posts delete own" on public.posts;
create policy "posts delete own" on public.posts
    for delete to authenticated using (author_id = auth.uid());

-- Reports: insert only, never readable through the app.
drop policy if exists "reports insert" on public.reports;
create policy "reports insert" on public.reports
    for insert to authenticated with check (reporter_id = auth.uid());

-- Blocks: each member manages only their own list.
drop policy if exists "blocks own" on public.blocks;
create policy "blocks own" on public.blocks
    for all to authenticated using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

-- Media: public read so posts can show it; members upload and delete only in their own folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('post-media', 'post-media', true, 52428800, array['image/jpeg', 'video/mp4'])
on conflict (id) do update set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "post-media upload own folder" on storage.objects;
create policy "post-media upload own folder" on storage.objects
    for insert to authenticated with check (
        bucket_id = 'post-media' and (storage.foldername(name))[1] = auth.uid()::text
    );
drop policy if exists "post-media delete own folder" on storage.objects;
create policy "post-media delete own folder" on storage.objects
    for delete to authenticated using (
        bucket_id = 'post-media' and (storage.foldername(name))[1] = auth.uid()::text
    );
drop policy if exists "post-media list own folder" on storage.objects;
create policy "post-media list own folder" on storage.objects
    for select to authenticated using (
        bucket_id = 'post-media' and (storage.foldername(name))[1] = auth.uid()::text
    );

-- Comments on posts.
create table if not exists public.comments (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references public.posts (id) on delete cascade,
    author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    body text not null check (char_length(btrim(body)) between 1 and 500),
    created_at timestamptz not null default now()
);
create index if not exists comments_post_idx on public.comments (post_id, created_at);
alter table public.comments enable row level security;

-- Members see comments except from people they blocked; they comment only on posts they can
-- see; they delete their own comments, and a post's author deletes any comment on it.
drop policy if exists "comments readable except blocked" on public.comments;
create policy "comments readable except blocked" on public.comments
    for select to authenticated using (
        not exists (select 1 from public.blocks b
                    where b.blocker_id = auth.uid() and b.blocked_id = comments.author_id)
    );
drop policy if exists "comments insert own on visible posts" on public.comments;
create policy "comments insert own on visible posts" on public.comments
    for insert to authenticated with check (
        author_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id)
    );
drop policy if exists "comments delete own or on own post" on public.comments;
create policy "comments delete own or on own post" on public.comments
    for delete to authenticated using (
        author_id = auth.uid() or
        exists (select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid())
    );

-- Reports can point at a post or a comment, never both.
alter table public.reports alter column post_id drop not null;
alter table public.reports add column if not exists
    comment_id uuid references public.comments (id) on delete cascade;
alter table public.reports drop constraint if exists reports_one_target;
alter table public.reports add constraint reports_one_target
    check ((post_id is null) <> (comment_id is null));

-- Account deletion (App Store guideline 5.1.1(v)). The app removes the member's media
-- folder first; deleting the auth user cascades to profile, posts, comments, reports and blocks.
create or replace function public.delete_my_account()
returns void
language sql
security definer
set search_path = ''
as $$
    delete from auth.users where id = auth.uid();
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
