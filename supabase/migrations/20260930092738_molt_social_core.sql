create extension if not exists citext with schema extensions;

-- Profiles: one per account. Points and social status change only through server functions.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username extensions.citext not null unique check (username::text ~ '^[a-z0-9_]{3,20}$'),
  molt_name text not null default 'Molt' check (char_length(molt_name) between 1 and 40),
  palette text not null default 'sage' check (palette in ('sage', 'ocean', 'sunset', 'violet')),
  points integer not null default 0 check (points >= 0),
  social integer not null default 0 check (social >= 0),
  discoverable boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "Signed-in users can view profiles" on public.profiles
  for select to authenticated using (true);
create policy "Users update their own profile" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (molt_name, palette, discoverable) on public.profiles to authenticated;

-- Create the profile when an account is created, using the username chosen at sign-up.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, username)
  values (new.id, lower(new.raw_user_meta_data ->> 'username'));
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.username_available(name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select name ~ '^[a-z0-9_]{3,20}$'
    and not exists (select 1 from public.profiles where username = lower(name)::extensions.citext);
$$;
grant execute on function public.username_available(text) to anon, authenticated;

-- Friendships: one row per pair, requested by one side and accepted by the other.
create table public.friendships (
  requester uuid not null references public.profiles (id) on delete cascade,
  addressee uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);
create unique index friendships_pair on public.friendships (least(requester, addressee), greatest(requester, addressee));
create index friendships_addressee on public.friendships (addressee);
alter table public.friendships enable row level security;
create policy "Members see their friendships" on public.friendships
  for select to authenticated using ((select auth.uid()) in (requester, addressee));
create policy "Users send friend requests" on public.friendships
  for insert to authenticated with check (requester = (select auth.uid()) and status = 'pending');
create policy "Addressee accepts requests" on public.friendships
  for update to authenticated using (addressee = (select auth.uid())) with check (status = 'accepted');
create policy "Either side removes a friendship" on public.friendships
  for delete to authenticated using ((select auth.uid()) in (requester, addressee));
revoke update on public.friendships from anon, authenticated;
grant update (status) on public.friendships to authenticated;

create or replace function public.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester = a and addressee = b) or (requester = b and addressee = a)));
$$;

-- Hangouts: both Molts meet in a small shared playground.
create table public.hangouts (
  id uuid primary key default gen_random_uuid(),
  host uuid not null references public.profiles (id) on delete cascade,
  guest uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'invited' check (status in ('invited', 'active', 'ended', 'declined')),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz,
  awarded integer not null default 0,
  check (host <> guest)
);
create index hangouts_guest on public.hangouts (guest, status);
create index hangouts_host on public.hangouts (host, status);
alter table public.hangouts enable row level security;
create policy "Participants see hangouts" on public.hangouts
  for select to authenticated using ((select auth.uid()) in (host, guest));
create policy "Hosts invite friends" on public.hangouts
  for insert to authenticated
  with check (host = (select auth.uid()) and status = 'invited' and public.are_friends(host, guest));
revoke update, delete on public.hangouts from anon, authenticated;

create or replace function public.accept_hangout(hangout uuid) returns public.hangouts
language plpgsql security definer set search_path = '' as $$
declare result public.hangouts;
begin
  update public.hangouts set status = 'active', started_at = now()
  where id = hangout and guest = auth.uid() and status = 'invited'
    and created_at > now() - interval '10 minutes'
  returning * into result;
  if result.id is null then raise exception 'Invitation is no longer available'; end if;
  return result;
end;
$$;

create or replace function public.decline_hangout(hangout uuid) returns void
language sql security definer set search_path = '' as $$
  update public.hangouts set status = 'declined', ended_at = now()
  where id = hangout and auth.uid() in (host, guest) and status = 'invited';
$$;

-- Ending an active hangout awards both players. At least one minute is required, points are
-- capped per hangout, and a pair earns from at most one hangout per hour.
create or replace function public.end_hangout(hangout uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  row public.hangouts;
  minutes numeric;
  reward integer := 0;
begin
  select * into row from public.hangouts
  where id = hangout and auth.uid() in (host, guest) for update;
  if row.id is null then raise exception 'Hangout not found'; end if;
  if row.status <> 'active' then return row.awarded; end if;
  minutes := extract(epoch from (now() - row.started_at)) / 60;
  if minutes >= 1 and not exists (
    select 1 from public.hangouts other
    where other.id <> row.id and other.awarded > 0
      and least(other.host, other.guest) = least(row.host, row.guest)
      and greatest(other.host, other.guest) = greatest(row.host, row.guest)
      and other.ended_at > now() - interval '1 hour')
  then
    reward := least(50, 10 + floor(minutes)::integer * 2);
    update public.profiles set points = points + reward, social = social + 1
    where id in (row.host, row.guest);
  end if;
  update public.hangouts set status = 'ended', ended_at = now(), awarded = reward where id = row.id;
  return reward;
end;
$$;
revoke execute on function public.accept_hangout(uuid), public.decline_hangout(uuid), public.end_hangout(uuid) from public, anon;
grant execute on function public.accept_hangout(uuid), public.decline_hangout(uuid), public.end_hangout(uuid) to authenticated;
revoke execute on function public.are_friends(uuid, uuid), public.handle_new_user() from public, anon, authenticated;

-- Loans: lend your notch setup (widgets, colors, Molt's look) to a friend.
create table public.loans (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references public.profiles (id) on delete cascade,
  borrower uuid not null references public.profiles (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 60),
  payload jsonb not null check (pg_column_size(payload) < 16384),
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  returned_at timestamptz,
  check (owner <> borrower)
);
create index loans_borrower on public.loans (borrower);
create index loans_owner on public.loans (owner);
alter table public.loans enable row level security;
create policy "Owner and borrower see loans" on public.loans
  for select to authenticated using ((select auth.uid()) in (owner, borrower));
create policy "Lend to friends" on public.loans
  for insert to authenticated
  with check (owner = (select auth.uid()) and public.are_friends(owner, borrower) and returned_at is null);
create policy "Borrower returns a loan" on public.loans
  for update to authenticated using (borrower = (select auth.uid())) with check (borrower = (select auth.uid()));
create policy "Owner takes a loan back" on public.loans
  for delete to authenticated using (owner = (select auth.uid()));
revoke update on public.loans from anon, authenticated;
grant update (returned_at) on public.loans to authenticated;

-- Realtime: private channels.
--   hangout:<id>  only its host and guest, while invited or active
--   user:<id>     an inbox that only its owner reads and only friends write to
--   lobby         presence for signed-in users, used for "online now"
create policy "Hangout participants read" on realtime.messages
  for select to authenticated using (
    exists (select 1 from public.hangouts h
      where 'hangout:' || h.id::text = (select realtime.topic())
        and (select auth.uid()) in (h.host, h.guest)
        and h.status in ('invited', 'active'))
    or (select realtime.topic()) = 'user:' || (select auth.uid())::text
    or ((select realtime.topic()) = 'lobby' and realtime.messages.extension = 'presence'));
create policy "Hangout participants write" on realtime.messages
  for insert to authenticated with check (
    exists (select 1 from public.hangouts h
      where 'hangout:' || h.id::text = (select realtime.topic())
        and (select auth.uid()) in (h.host, h.guest)
        and h.status in ('invited', 'active'))
    or ((select realtime.topic()) like 'user:%'
      and public.are_friends((select auth.uid()), substring((select realtime.topic()) from 6)::uuid))
    or ((select realtime.topic()) = 'lobby' and realtime.messages.extension = 'presence'));
