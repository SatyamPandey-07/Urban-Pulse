-- Emergency SOS: a traveller in trouble raises an SOS (three quick presses of
-- the phone's power button, or from the SOS screen). It carries their location
-- and stays active until they resolve it. UrbanPulse users nearby see it in
-- real time and can say they are on their way.
--
-- Proximity is enforced by the database, not the app: every signed-in app keeps
-- a private presence row (its last location and alert radius), and an SOS is
-- readable only by users whose recent presence is within their radius of it.
-- Supabase Realtime applies the same row level security, so an SOS is only ever
-- delivered to people near it.

-- Great-circle distance in km.
create or replace function public.km_between(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision
language sql
immutable
parallel safe
set search_path = ''
as $$
  select 6371.0 * 2 * asin(least(1.0, sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  )));
$$;

-- ---------------------------------------------------------------------------
-- presence: where each app user was last seen, private to them
-- ---------------------------------------------------------------------------
create table public.sos_presence (
  user_id    uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  lat        double precision not null check (lat between -90 and 90),
  lng        double precision not null check (lng between -180 and 180),
  -- how far away an SOS may be to be shown to this user
  radius_km  real not null default 5 check (radius_km between 0.5 and 50),
  updated_at timestamptz not null default now()
);
comment on table public.sos_presence is 'Each user''s last known location and SOS alert radius; used only to decide which SOS events they may see.';

create trigger sos_presence_touch before update on public.sos_presence for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- SOS events
-- ---------------------------------------------------------------------------
create table public.sos_events (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- first name only: enough for helpers, nothing more
  display_name text not null check (char_length(display_name) between 1 and 40),
  category     text not null default 'general' check (category in ('general', 'medical', 'safety', 'accident', 'fire')),
  lat          double precision check (lat between -90 and 90),
  lng          double precision check (lng between -180 and 180),
  accuracy_m   real check (accuracy_m >= 0),
  status       text not null default 'active' check (status in ('active', 'resolved', 'cancelled')),
  source       text not null default 'app' check (source in ('power_button', 'app', 'notification')),
  created_at   timestamptz not null default now(),
  -- refreshed by the sender's heartbeat while active; an SOS without one for
  -- two hours is treated as stale
  updated_at   timestamptz not null default now(),
  resolved_at  timestamptz,
  check ((lat is null) = (lng is null))
);
comment on table public.sos_events is 'Emergency SOS alerts. Active until the sender resolves them; visible only to users nearby.';

-- One active SOS per user: a second trigger while one is active is a duplicate.
create unique index sos_events_one_active on public.sos_events (user_id) where status = 'active';
create index sos_events_live on public.sos_events (status, updated_at desc);
create index sos_events_lat on public.sos_events (lat) where status = 'active';

-- Senders may move their SOS (location heartbeat) and close it, nothing else;
-- a closed SOS stays closed.
create or replace function public.sos_event_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.user_id <> old.user_id or new.created_at <> old.created_at or new.source <> old.source then
    raise exception 'an SOS cannot be reassigned' using errcode = '42501';
  end if;
  if old.status <> 'active' and new.status <> old.status then
    raise exception 'a closed SOS cannot be reopened' using errcode = '42501';
  end if;
  if old.status = 'active' and new.status <> 'active' then
    new.resolved_at := now();
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger sos_events_guard before update on public.sos_events for each row execute function public.sos_event_guard();

-- ---------------------------------------------------------------------------
-- responses: "I'm on my way"
-- ---------------------------------------------------------------------------
create table public.sos_responses (
  sos_id         uuid not null references public.sos_events (id) on delete cascade,
  responder_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  responder_name text not null check (char_length(responder_name) between 1 and 40),
  created_at     timestamptz not null default now(),
  primary key (sos_id, responder_id)
);
comment on table public.sos_responses is 'Nearby users who said they are on their way to an SOS.';

-- ---------------------------------------------------------------------------
-- row level security
-- ---------------------------------------------------------------------------
alter table public.sos_presence  enable row level security;
alter table public.sos_events    enable row level security;
alter table public.sos_responses enable row level security;

create policy "sos presence: own" on public.sos_presence
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "sos events: own" on public.sos_events
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Nearby: an active, fresh SOS within the viewer's radius of their own recent
-- location. A just-closed one stays visible for 15 minutes so the change to
-- "resolved" reaches everyone who saw it.
create policy "sos events: nearby" on public.sos_events
  for select to authenticated
  using (
    lat is not null
    and (
      (status = 'active' and updated_at > now() - interval '2 hours')
      or (status <> 'active' and resolved_at > now() - interval '15 minutes')
    )
    and exists (
      select 1 from public.sos_presence p
      where p.user_id = (select auth.uid())
        and p.updated_at > now() - interval '1 hour'
        and abs(p.lat - sos_events.lat) <= p.radius_km / 111.0
        and public.km_between(p.lat, p.lng, sos_events.lat, sos_events.lng) <= p.radius_km
    )
  );

create policy "sos events: raise own" on public.sos_events
  for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'active');

create policy "sos events: update own" on public.sos_events
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Respond to an SOS you can see (the events policy decides that).
create policy "sos responses: respond" on public.sos_responses
  for insert to authenticated
  with check (
    responder_id = (select auth.uid())
    and exists (select 1 from public.sos_events e where e.id = sos_id and e.status = 'active' and e.user_id <> (select auth.uid()))
  );

create policy "sos responses: read" on public.sos_responses
  for select to authenticated
  using (
    responder_id = (select auth.uid())
    or exists (select 1 from public.sos_events e where e.id = sos_id and e.user_id = (select auth.uid()))
  );

create policy "sos responses: withdraw" on public.sos_responses
  for delete to authenticated
  using (responder_id = (select auth.uid()));

revoke all on public.sos_presence, public.sos_events, public.sos_responses from anon;
grant select, insert, update, delete on public.sos_presence to authenticated;
grant select, insert, update on public.sos_events to authenticated;
grant select, insert, delete on public.sos_responses to authenticated;

-- ---------------------------------------------------------------------------
-- realtime
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.sos_events, public.sos_responses;
