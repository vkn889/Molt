-- Invitations reach the guest as database changes, filtered by the table's own security rules.
alter publication supabase_realtime add table public.hangouts;

drop policy "Hangout participants read" on realtime.messages;
drop policy "Hangout participants write" on realtime.messages;
-- hangout:<id>  only its host and guest, while invited or active
-- user:<id>     only its owner (used to receive database changes)
-- lobby         presence for signed-in users, used for "online now"
create policy "Molt channels read" on realtime.messages
  for select to authenticated using (
    exists (select 1 from public.hangouts h
      where 'hangout:' || h.id::text = (select realtime.topic())
        and (select auth.uid()) in (h.host, h.guest)
        and h.status in ('invited', 'active'))
    or (select realtime.topic()) = 'user:' || (select auth.uid())::text
    or ((select realtime.topic()) = 'lobby' and realtime.messages.extension = 'presence'));
create policy "Molt channels write" on realtime.messages
  for insert to authenticated with check (
    exists (select 1 from public.hangouts h
      where 'hangout:' || h.id::text = (select realtime.topic())
        and (select auth.uid()) in (h.host, h.guest)
        and h.status in ('invited', 'active'))
    or ((select realtime.topic()) = 'lobby' and realtime.messages.extension = 'presence'));
