-- Feed push notifications: likes, comments and follows reach the member's iPhone.
-- Run this once in the Supabase SQL Editor after the steps in supabase/PUSH.md. Safe to re-run.
-- Until the two Vault secrets below exist, the triggers do nothing.

-- Each iPhone's push token, owned by the member signed in on it.
create table if not exists public.device_tokens (
    token text primary key,
    member_id uuid not null references auth.users (id) on delete cascade,
    platform text not null default 'ios',
    updated_at timestamptz not null default now()
);
alter table public.device_tokens enable row level security;

drop policy if exists "device tokens own" on public.device_tokens;
create policy "device tokens own" on public.device_tokens
    for all to authenticated using (member_id = auth.uid()) with check (member_id = auth.uid());

-- New likes, comments and follows call the notify function. It reads the secret and project URL
-- from Vault, so neither is written in this file.
create extension if not exists pg_net;

create or replace function public.notify_feed_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    secret text;
    project text;
begin
    select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_webhook_secret';
    select decrypted_secret into project from vault.decrypted_secrets where name = 'project_url';
    if secret is null or project is null then
        return new;
    end if;
    perform net.http_post(
        url := project || '/functions/v1/notify',
        body := jsonb_build_object('table', tg_table_name, 'record', to_jsonb(new)),
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', secret)
    );
    return new;
end;
$$;

drop trigger if exists notify_like on public.appreciations;
create trigger notify_like after insert on public.appreciations
    for each row execute function public.notify_feed_event();
drop trigger if exists notify_comment on public.comments;
create trigger notify_comment after insert on public.comments
    for each row execute function public.notify_feed_event();
drop trigger if exists notify_follow on public.follows;
create trigger notify_follow after insert on public.follows
    for each row execute function public.notify_feed_event();
