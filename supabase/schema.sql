-- NAGISEN Feed schema for Supabase.
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Safe to re-run: every statement checks before it creates.

-- Profiles: one per account, holds the public username.
create table if not exists public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    username text not null unique check (username ~ '^[[:alnum:]_.]{1,30}$'),
    created_at timestamptz not null default now()
);

-- Profile picture, bio and earned border (0 none … 11 kintsugi), added after the first release.
alter table public.profiles add column if not exists avatar_path text;
alter table public.profiles add column if not exists bio text not null default ''
    check (char_length(bio) <= 150);
alter table public.profiles add column if not exists border_tier smallint not null default 0;
-- Room for future borders without another migration.
alter table public.profiles drop constraint if exists profiles_border_tier_check;
alter table public.profiles add constraint profiles_border_tier_check check (border_tier between 0 and 30);

-- A one-off border granted by hand (only 'enji', the developer's). Members can't set it:
-- the trigger rejects any change made through the app, and only the SQL editor can grant it.
alter table public.profiles add column if not exists special_border text;
alter table public.profiles drop constraint if exists profiles_special_border_check;
alter table public.profiles add constraint profiles_special_border_check
    check (special_border is null or special_border in ('enji'));

create or replace function public.protect_special_border()
returns trigger
language plpgsql
as $$
begin
    if current_user in ('authenticated', 'anon') then
        if tg_op = 'INSERT' then
            new.special_border := null;
        elsif new.special_border is distinct from old.special_border then
            raise exception 'special_border can only be granted by the developer';
        end if;
    end if;
    return new;
end;
$$;
drop trigger if exists protect_special_border on public.profiles;
create trigger protect_special_border before insert or update on public.profiles
    for each row execute function public.protect_special_border();

-- Usernames: 1 to 30 letters (any language), numbers, periods or underscores. Uniqueness ignores
-- case, so "Khalil" and "khalil" can't both exist.
alter table public.profiles drop constraint if exists profiles_username_check;
alter table public.profiles add constraint profiles_username_check check (username ~ '^[[:alnum:]_.]{1,30}$');
create unique index if not exists profiles_username_lower_idx on public.profiles (lower(username));

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
-- Authors can edit the text of their own posts; media, author and dates stay as posted.
drop policy if exists "posts update own" on public.posts;
create policy "posts update own" on public.posts
    for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());
revoke update on public.posts from authenticated;
grant update (body) on public.posts to authenticated;

-- Pinned posts sit at the top of every feed. Only the developer (the Enji border, which members
-- can't grant themselves) can pin or unpin, through this function.
alter table public.posts add column if not exists pinned_at timestamptz;
create or replace function public.set_post_pinned(target uuid, pin boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and special_border = 'enji') then
        raise exception 'Only the developer can pin posts' using errcode = '42501';
    end if;
    update public.posts set pinned_at = case when pin then now() else null end where id = target;
end;
$$;
revoke all on function public.set_post_pinned(uuid, boolean) from public;
grant execute on function public.set_post_pinned(uuid, boolean) to authenticated;

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
-- Which target a report points at is checked further down, once stories exist.

-- Likes (stored as appreciations, the table's original name). Every signed-in member can see
-- likes on posts they can see, so counts are public; members like and unlike for themselves.
create table if not exists public.appreciations (
    post_id uuid not null references public.posts (id) on delete cascade,
    member_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (post_id, member_id)
);
alter table public.appreciations enable row level security;

drop policy if exists "appreciations visible to giver and author" on public.appreciations;
drop policy if exists "likes visible on visible posts" on public.appreciations;
create policy "likes visible on visible posts" on public.appreciations
    for select to authenticated using (exists (select 1 from public.posts p where p.id = post_id));
drop policy if exists "appreciations give on others' visible posts" on public.appreciations;
drop policy if exists "likes given on visible posts" on public.appreciations;
create policy "likes given on visible posts" on public.appreciations
    for insert to authenticated with check (
        member_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id)
    );
drop policy if exists "appreciations take back own" on public.appreciations;
create policy "appreciations take back own" on public.appreciations
    for delete to authenticated using (member_id = auth.uid());

-- Video posts carry a poster frame for profile grids.
alter table public.posts add column if not exists poster_path text;

-- Follows: public (counts and lists are visible to members); members follow and unfollow for themselves.
create table if not exists public.follows (
    follower_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    followee_id uuid not null references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (follower_id, followee_id),
    check (follower_id <> followee_id)
);
create index if not exists follows_followee_idx on public.follows (followee_id);
alter table public.follows enable row level security;
drop policy if exists "follows visible to members" on public.follows;
create policy "follows visible to members" on public.follows
    for select to authenticated using (true);
drop policy if exists "follows own" on public.follows;
create policy "follows own" on public.follows
    for insert to authenticated with check (follower_id = auth.uid());
drop policy if exists "unfollow own" on public.follows;
create policy "unfollow own" on public.follows
    for delete to authenticated using (follower_id = auth.uid());

-- Stories: one photo or video, visible for 24 hours, hidden from people who blocked the author.
create table if not exists public.stories (
    id uuid primary key default gen_random_uuid(),
    author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    media_path text not null,
    media_kind text not null check (media_kind in ('photo', 'video')),
    poster_path text,
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default now() + interval '24 hours'
);
create index if not exists stories_live_idx on public.stories (expires_at desc);
alter table public.stories enable row level security;
drop policy if exists "stories live and not blocked" on public.stories;
create policy "stories live and not blocked" on public.stories
    for select to authenticated using (
        (expires_at > now() or author_id = auth.uid()) and
        not exists (select 1 from public.blocks b
                    where b.blocker_id = auth.uid() and b.blocked_id = stories.author_id)
    );
drop policy if exists "stories insert own" on public.stories;
create policy "stories insert own" on public.stories
    for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "stories delete own" on public.stories;
create policy "stories delete own" on public.stories
    for delete to authenticated using (author_id = auth.uid());

-- Who saw a story: the viewer records it; the viewer and the story's author can read it.
create table if not exists public.story_views (
    story_id uuid not null references public.stories (id) on delete cascade,
    viewer_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (story_id, viewer_id)
);
alter table public.story_views enable row level security;
drop policy if exists "story views insert own" on public.story_views;
create policy "story views insert own" on public.story_views
    for insert to authenticated with check (
        viewer_id = auth.uid() and exists (select 1 from public.stories s where s.id = story_id)
    );
drop policy if exists "story views readable by viewer and author" on public.story_views;
create policy "story views readable by viewer and author" on public.story_views
    for select to authenticated using (
        viewer_id = auth.uid() or
        exists (select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid())
    );

-- Reports can point at a post, a comment or a story: exactly one.
alter table public.reports add column if not exists
    story_id uuid references public.stories (id) on delete cascade;
alter table public.reports drop constraint if exists reports_one_target;
alter table public.reports add constraint reports_one_target
    check (num_nonnulls(post_id, comment_id, story_id) = 1);

-- Account deletion (App Store guideline 5.1.1(v)). The app removes the member's media
-- folder first; deleting the auth user cascades to profile, posts, comments, likes, follows, stories, reports and blocks.
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
