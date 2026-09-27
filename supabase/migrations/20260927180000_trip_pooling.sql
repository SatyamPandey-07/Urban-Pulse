-- Trip-pooling: travellers going to the same place on the same day share the
-- ride. A traveller who opens a trip to pooling publishes a listing; others
-- going there that day see it and ask to join; the owner approves or declines.
-- On approval both apps update their itinerary (shared journey, split cost).
--
-- Privacy: a listing shows a first name, the origin city, the destination, the
-- dates, the group size and the free seats. Never an email or the full trip.

-- ---------------------------------------------------------------------------
-- listings
-- ---------------------------------------------------------------------------
create table public.trip_pool_listings (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  brief_client_id text not null,
  display_name    text not null check (char_length(display_name) between 1 and 40),
  origin          text,
  destination     text not null,
  -- lower-case city, so "Jaipur, Rajasthan" and "jaipur" match
  destination_key text not null,
  start_date      date not null,
  end_date        date,
  travellers      int  not null default 1 check (travellers between 1 and 20),
  seats_free      int  not null default 0 check (seats_free between 0 and 12),
  mode            text,
  status          text not null default 'open' check (status in ('open', 'closed')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, brief_client_id)
);
comment on table public.trip_pool_listings is 'Trips opened to Trip-pooling (shared rides to the same destination on the same day).';

create index trip_pool_listings_match on public.trip_pool_listings (destination_key, start_date) where status = 'open';
create trigger trip_pool_listings_touch before update on public.trip_pool_listings for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- requests
-- ---------------------------------------------------------------------------
create table public.trip_pool_requests (
  id                   uuid primary key default gen_random_uuid(),
  listing_id           uuid not null references public.trip_pool_listings (id) on delete cascade,
  from_user            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  to_user              uuid not null references auth.users (id) on delete cascade,
  from_name            text not null check (char_length(from_name) between 1 and 40),
  from_origin          text,
  from_travellers      int  not null default 1 check (from_travellers between 1 and 20),
  from_brief_client_id text not null,
  message              text check (char_length(message) <= 280),
  status               text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'cancelled')),
  created_at           timestamptz not null default now(),
  responded_at         timestamptz,
  unique (listing_id, from_user),
  check (from_user <> to_user)
);
comment on table public.trip_pool_requests is 'Requests to join a pooled trip; the listing owner approves or declines.';

create index trip_pool_requests_to   on public.trip_pool_requests (to_user, status);
create index trip_pool_requests_from on public.trip_pool_requests (from_user, status);

-- Only the owner answers (approve / decline, once), only the requester cancels,
-- and nobody rewrites who or what the request is about.
create or replace function public.trip_pool_request_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if new.listing_id <> old.listing_id or new.from_user <> old.from_user or new.to_user <> old.to_user
     or new.from_brief_client_id <> old.from_brief_client_id then
    raise exception 'a request cannot be moved to another trip or traveller' using errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if me = old.to_user and old.status = 'pending' and new.status in ('approved', 'declined') then
    new.responded_at := now();
    return new;
  end if;
  if me = old.from_user and old.status in ('pending', 'approved') and new.status = 'cancelled' then
    new.responded_at := now();
    return new;
  end if;
  raise exception 'this change is not allowed (% -> %)', old.status, new.status using errcode = '42501';
end;
$$;

create trigger trip_pool_requests_guard before update on public.trip_pool_requests
  for each row execute function public.trip_pool_request_guard();

-- ---------------------------------------------------------------------------
-- row level security
-- ---------------------------------------------------------------------------
alter table public.trip_pool_listings enable row level security;
alter table public.trip_pool_requests enable row level security;

-- "Did I ask to join this listing?" without going through the requests
-- table's policies (which read listings): avoids policy recursion.
create or replace function public.trip_pool_asked(listing uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.trip_pool_requests r
    where r.listing_id = listing and r.from_user = (select auth.uid())
  );
$$;
revoke all on function public.trip_pool_asked(uuid) from public, anon;
grant execute on function public.trip_pool_asked(uuid) to authenticated;

-- Open listings are visible to every signed-in traveller (to find a match);
-- your own always; a closed one only to people who asked to join it.
create policy "pool listings: read open, own or requested" on public.trip_pool_listings
  for select to authenticated
  using (
    status = 'open'
    or user_id = (select auth.uid())
    or public.trip_pool_asked(id)
  );
create policy "pool listings: insert own" on public.trip_pool_listings
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "pool listings: update own" on public.trip_pool_listings
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "pool listings: delete own" on public.trip_pool_listings
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "pool requests: read if involved" on public.trip_pool_requests
  for select to authenticated
  using ((select auth.uid()) in (from_user, to_user));
-- Ask to join someone else's open trip, as yourself.
create policy "pool requests: ask" on public.trip_pool_requests
  for insert to authenticated
  with check (
    from_user = (select auth.uid())
    and exists (
      select 1 from public.trip_pool_listings l
      where l.id = listing_id and l.status = 'open' and l.user_id = to_user and l.user_id <> (select auth.uid())
    )
  );
create policy "pool requests: answer or cancel" on public.trip_pool_requests
  for update to authenticated
  using ((select auth.uid()) in (from_user, to_user))
  with check ((select auth.uid()) in (from_user, to_user));

revoke all on public.trip_pool_listings, public.trip_pool_requests from anon;
grant select, insert, update, delete on public.trip_pool_listings to authenticated;
grant select, insert, update on public.trip_pool_requests to authenticated;
