-- UrbanPulse schema: travellers, their settings and progress, trip briefs,
-- itineraries (stored whole as JSON, with the fields worth querying pulled out
-- into columns), every multi-agent planning run, and every decision the
-- traveller made when Yatri asked them.
--
-- Every table is private to its owner through row level security: a signed-in
-- traveller can read and write only their own rows. The app talks to the
-- database with the public anon key; the database password is never shipped.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles: one per auth user, created by the sign-up trigger below
-- ---------------------------------------------------------------------------

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text,
  full_name   text not null default '',
  home_city   text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public.profiles is 'One row per traveller (auth user): name and home city.';

-- ---------------------------------------------------------------------------
-- user_settings: what the traveller needs, remembered across devices
-- ---------------------------------------------------------------------------

create table public.user_settings (
  user_id                uuid primary key references auth.users (id) on delete cascade,
  wheelchair_mode        boolean not null default false,
  visual_assist          boolean not null default false,
  hearing_assist         boolean not null default false,
  service_animal_only    boolean not null default false,
  -- The planner's own answers: AccessibilityNeed names, follow-up answers
  -- ("a11y.mobility.walking" -> ["lt100"]) and Dietary names.
  accessibility_needs    text[] not null default '{}',
  accessibility_details  jsonb not null default '{}'::jsonb,
  dietary                text[] not null default '{}',
  -- Anything else worth keeping per traveller, so new settings need no migration.
  preferences            jsonb not null default '{}'::jsonb,
  updated_at             timestamptz not null default now()
);
comment on table public.user_settings is 'Accessibility flags and planner preferences per traveller.';

-- ---------------------------------------------------------------------------
-- user_progress: XP, PULSE credits, streak, CO2 saved and activity counters
-- ---------------------------------------------------------------------------

create table public.user_progress (
  user_id         uuid primary key references auth.users (id) on delete cascade,
  xp              integer not null default 0 check (xp >= 0),
  pulse           integer not null default 0 check (pulse >= 0),
  streak          integer not null default 0 check (streak >= 0),
  last_login_day  integer,
  co2_saved_kg    numeric(12, 3) not null default 0,
  -- TrackedAction key -> count ("trips_planned": 3, ...)
  activity        jsonb not null default '{}'::jsonb,
  updated_at      timestamptz not null default now()
);
comment on table public.user_progress is 'Gamification state and activity counters per traveller.';

-- ---------------------------------------------------------------------------
-- trip_briefs: what the traveller confirmed before planning
-- ---------------------------------------------------------------------------

create table public.trip_briefs (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null default auth.uid() references auth.users (id) on delete cascade,
  client_id            text not null,              -- TripBrief.id in the app
  destination          text,
  origin_city          text,
  start_at             timestamptz,
  end_at               timestamptz,
  traveller_count      integer,
  budget_min_inr       integer,
  budget_max_inr       integer,
  accessibility_needs  text[] not null default '{}',
  brief                jsonb not null,             -- TripBrief.toJson(), as the app wrote it
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (user_id, client_id)
);
comment on table public.trip_briefs is 'Confirmed trip briefs: the planner''s input, whole in "brief", key fields as columns.';

-- ---------------------------------------------------------------------------
-- itineraries: the multi-agent plans
-- ---------------------------------------------------------------------------

create table public.itineraries (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  client_id       text not null,                   -- Itinerary.id in the app
  brief_id        uuid references public.trip_briefs (id) on delete set null,
  destination     text not null,
  origin          text,
  start_at        timestamptz,
  end_at          timestamptz,
  day_count       integer,
  visit_count     integer,
  total_inr       integer,
  budget_max_inr  integer,
  hotel_name      text,
  status          text not null default 'planned' check (status in ('planned', 'partial')),
  -- What the plan assumes or the traveller knowingly accepted ("You chose to
  -- keep day 3 light", "Some places have no confirmed access; check before going").
  caveats         text[] not null default '{}',
  itinerary       jsonb not null,                  -- Itinerary.toJson(), days, budget, audit, footprint and all
  saved           boolean not null default false,  -- in My Trips
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, client_id)
);
comment on table public.itineraries is 'Itineraries built by the agents: whole in "itinerary", searchable fields and caveats as columns.';

-- ---------------------------------------------------------------------------
-- plan_runs: one run of the multi-agent planner, with its task graph
-- ---------------------------------------------------------------------------

create table public.plan_runs (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  client_id       text not null,                   -- generated by the app, so a retried upload never duplicates
  brief_id        uuid references public.trip_briefs (id) on delete set null,
  itinerary_id    uuid references public.itineraries (id) on delete set null,
  status          text not null check (status in ('planned', 'partial', 'unlocatable', 'failed')),
  summary         text,
  notes           text[] not null default '{}',
  active_seconds  integer,
  timings         jsonb not null default '{}'::jsonb,   -- seconds per agent
  task_graph      jsonb not null default '[]'::jsonb,   -- nodes: id, agent, title, status, summary, parents, delegatedBy, elapsed
  feed            jsonb not null default '[]'::jsonb,   -- the narrated events under the graph
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,
  unique (user_id, client_id)
);
comment on table public.plan_runs is 'Each planning run: outcome, timings and the full task graph and feed.';

-- ---------------------------------------------------------------------------
-- plan_decisions: every question Yatri asked, and what the traveller chose
-- ---------------------------------------------------------------------------

create table public.plan_decisions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  run_id       uuid not null references public.plan_runs (id) on delete cascade,
  seq          integer not null,                   -- order within the run
  question_id  text not null,                      -- e.g. plan.hotels.choice, plan.gap.day.2#1, plan.access.unconfirmed
  topic        text not null,                      -- hotels, access, gap, budget, weather, transport, places, other
  agent        text,
  question     text not null,
  why          text,
  options      jsonb not null default '[]'::jsonb, -- [{id, label, subtitle, recommended}]
  answer       jsonb,                              -- {optionIds, labels}; null if never answered
  asked_at     timestamptz not null default now(),
  unique (run_id, seq)
);
comment on table public.plan_decisions is 'The traveller''s decisions during planning: accepted gaps, access trade-offs, budget choices.';

-- ---------------------------------------------------------------------------
-- saved_trips: My Trips
-- ---------------------------------------------------------------------------

create table public.saved_trips (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  client_id     text not null,                     -- TripPlan.id in the app
  itinerary_id  uuid references public.itineraries (id) on delete set null,
  destination   text,
  plan          jsonb not null,                    -- TripPlan.toJson()
  created_at    timestamptz not null default now(),
  unique (user_id, client_id)
);
comment on table public.saved_trips is 'Trips the traveller saved to My Trips.';

-- ---------------------------------------------------------------------------
-- indexes
-- ---------------------------------------------------------------------------

create index trip_briefs_user_created_idx   on public.trip_briefs (user_id, created_at desc);
create index itineraries_user_created_idx   on public.itineraries (user_id, created_at desc);
create index itineraries_brief_idx          on public.itineraries (brief_id);
create index plan_runs_user_started_idx     on public.plan_runs (user_id, started_at desc);
create index plan_runs_brief_idx            on public.plan_runs (brief_id);
create index plan_runs_itinerary_idx        on public.plan_runs (itinerary_id);
create index plan_decisions_user_idx        on public.plan_decisions (user_id, asked_at desc);
create index plan_decisions_topic_idx       on public.plan_decisions (user_id, topic);
create index saved_trips_user_created_idx   on public.saved_trips (user_id, created_at desc);
create index saved_trips_itinerary_idx      on public.saved_trips (itinerary_id);

-- ---------------------------------------------------------------------------
-- updated_at
-- ---------------------------------------------------------------------------

create trigger profiles_touch       before update on public.profiles       for each row execute function public.touch_updated_at();
create trigger user_settings_touch  before update on public.user_settings  for each row execute function public.touch_updated_at();
create trigger user_progress_touch  before update on public.user_progress  for each row execute function public.touch_updated_at();
create trigger trip_briefs_touch    before update on public.trip_briefs    for each row execute function public.touch_updated_at();
create trigger itineraries_touch    before update on public.itineraries    for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- a new auth user gets a profile, settings and progress row
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  insert into public.user_settings (user_id) values (new.id);
  insert into public.user_progress (user_id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- row level security: each traveller sees and changes only their own rows
-- ---------------------------------------------------------------------------

alter table public.profiles       enable row level security;
alter table public.user_settings  enable row level security;
alter table public.user_progress  enable row level security;
alter table public.trip_briefs    enable row level security;
alter table public.itineraries    enable row level security;
alter table public.plan_runs      enable row level security;
alter table public.plan_decisions enable row level security;
alter table public.saved_trips    enable row level security;

create policy "own profile: read"   on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy "own profile: update" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "own settings: read"   on public.user_settings for select to authenticated using (user_id = (select auth.uid()));
create policy "own settings: insert" on public.user_settings for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own settings: update" on public.user_settings for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "own progress: read"   on public.user_progress for select to authenticated using (user_id = (select auth.uid()));
create policy "own progress: insert" on public.user_progress for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own progress: update" on public.user_progress for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "own briefs" on public.trip_briefs for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "own itineraries" on public.itineraries for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "own runs" on public.plan_runs for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "own decisions" on public.plan_decisions for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.plan_runs r where r.id = run_id and r.user_id = (select auth.uid()))
  );

create policy "own saved trips" on public.saved_trips for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- The anon role gets nothing; signed-in travellers get table access, which the
-- policies above narrow to their own rows.
revoke all on public.profiles, public.user_settings, public.user_progress, public.trip_briefs,
  public.itineraries, public.plan_runs, public.plan_decisions, public.saved_trips from anon;
grant select, update on public.profiles to authenticated;
grant select, insert, update on public.user_settings, public.user_progress to authenticated;
grant select, insert, update, delete on public.trip_briefs, public.itineraries, public.plan_runs,
  public.plan_decisions, public.saved_trips to authenticated;
