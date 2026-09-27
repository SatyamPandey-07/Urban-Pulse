we have merged all the PRs till #11 

we are done creating agent orchestration but it fails during this steps:

the hotspot agent does find spots but yatri agent stops and dont plan actual iteniary, it even asked   about hotspot preferences and yet it dont use it 

basically agents system stops too early without planning the itenary so we need fixing

find the actual issue in system, it evens fails on finding the reviews from forums, also if we give it tight constraints like wheelchair-low walk-elderly... it just fails, if no hotels /hotspot... matches the preferences yatri should ask user explicitly using mcq to tell which option would be good enough 


most importantly it should stop only when entire itenary is built current itenary is just hotel checkin and thats it find the issue plan accordingly and improve the system
improve system prompts, tools, loops mechanism

---

# Diagnosis and fix plan (2026-09-27)

Line references are for `main` at ef76818 (PRs #8–#12 merged).

## What is actually wrong

### 1. Time budgets end the plan (the main cause of "only hotel check-in")
- `PlanClock` degrades after **35 s** and has a deadline of **60 s** ([plan_clock.dart:7-8](urbanpulse_flutter/lib/agents/runtime/plan_clock.dart#L7-L8)). This is shared wall time across hotels, places, journey and weather, which all run at once.
- Each worker also has a hard timeout; Atithi and Bhatkanti get 55 s ([planner_orchestrator.dart:349, 485](urbanpulse_flutter/lib/agents/yatri/planner_orchestrator.dart#L485)). When it expires, `TaskBoard` abandons the worker and **discards its late result** ([task_board.dart:193-219, 283](urbanpulse_flutter/lib/agents/runtime/task_board.dart#L193)).
- Bhatkanti's real work regularly takes longer than 55 s:
  - Overpass.
  - The `web_search` tool loop: up to 5 LLM calls plus 3 searches.
  - `_fromLlmKnowledge`, which starts only after the merge ([hotspot_finder.dart:199](urbanpulse_flutter/lib/agents/bhatkanti/hotspot_finder.dart#L199)) and then geocodes up to 30 places **one after another** ([line 621](urbanpulse_flutter/lib/agents/bhatkanti/hotspot_finder.dart#L621)).
  - AI enrichment.
  - Khoji checks, run inside the same timeout.
  - The build has one Groq key, so all agents share 3 concurrent slots ([llm_pool.dart:211](urbanpulse_flutter/lib/agents/runtime/llm_pool.dart#L211)).
- When the timeout fires, Bhatkanti has no payload, so `st.spots` stays null ([planner_orchestrator.dart:494](urbanpulse_flutter/lib/agents/yatri/planner_orchestrator.dart#L494)). Raah then gets no places ([day_planner.dart:146](urbanpulse_flutter/lib/agents/raah/day_planner.dart#L146)), and each day holds only arrival, "Check in at …" ([line 703](urbanpulse_flutter/lib/agents/raah/day_planner.dart#L703)) and check-out.
- The feed still shows Bhatkanti "finding" places, because the abandoned worker keeps narrating.

### 2. Time switches off quality work and decisions
- Past 35 s, `HotspotFinder` skips web search and AI enrichment ([hotspot_finder.dart:169, 219](urbanpulse_flutter/lib/agents/bhatkanti/hotspot_finder.dart#L169)).
- Khoji returns without checking anything whenever `parent.degraded` is true ([khoji_agent.dart:37, 173](urbanpulse_flutter/lib/agents/khoji/khoji_agent.dart#L37); [khoji.dart:115](urbanpulse_flutter/lib/agents/khoji/khoji.dart#L115)). The global clock is past 35 s by then, so **reviews are almost never fetched**.
- Past 60 s, `clock.expired` stops the questions, auto-picks the hotel and ends the audit loop ([planner_orchestrator.dart:393, 429, 504, 580, 685](urbanpulse_flutter/lib/agents/yatri/planner_orchestrator.dart#L393)). The traveller's constraints are overridden without asking.

### 3. No goal: the plan is "planned" whatever it contains
- `_plan` always returns `PlanStatus.planned` ([planner_orchestrator.dart:299](urbanpulse_flutter/lib/agents/yatri/planner_orchestrator.dart#L299)).
- `_settle` only gives up when both spots and hotel are null ([line 643](urbanpulse_flutter/lib/agents/yatri/planner_orchestrator.dart#L643)).
- Nothing checks that the days contain visits, and nothing repairs them when they don't.

### 4. Review search is weak
- The chain is Tavily → `groq/compound` → Wikipedia ([web_search_tool.dart:341-347](urbanpulse_flutter/lib/agents/tools/web_search_tool.dart#L341-L347)). Wikipedia cannot return reviews, yet it is the last fallback for review queries.
- The compound budget is 6 calls per plan, shared by every agent ([agent_toolkit.dart:138](urbanpulse_flutter/lib/agents/runtime/agent_toolkit.dart#L138)).
- Khoji's compound call times out after 14 s ([khoji.dart:149](urbanpulse_flutter/lib/agents/khoji/khoji.dart#L149)).
- Queries are generic ([khoji.dart:195-196](urbanpulse_flutter/lib/agents/khoji/khoji.dart#L195-L196)). None target forum sites.

### 5. Preferences are asked for but never used
- `TripBrief.accessibilityDetails` is read by **no agent**. It holds the answers to the follow-up questions: walk "under 100 m", "avoid stairs", "rest stops", "slower pace", "ground floor / lift room", "roll-in shower", "medical facility nearby".
- `dietary` is not used when picking meal places.
- Raah's walking limit is fixed at 0.25/0.7 km ([transport_planner.dart:362](urbanpulse_flutter/lib/agents/safar/transport_planner.dart#L362)).
- Hotspot selection only penalises access marked `no`. Places with `unknown` access still dominate for wheelchair users.

### 6. Tight constraints hit dead ends instead of choices
- `HotelGates` offers only generic ways out: accept, search wider, raise the budget, skip ([hotel_gates.dart:60-166](urbanpulse_flutter/lib/agents/yatri/hotel_gates.dart#L60)).
- `HotspotGates` offers only "look further out" or "leave the days open" ([hotspot_gates.dart:28](urbanpulse_flutter/lib/agents/yatri/hotspot_gates.dart#L28)).
- The traveller is never shown the actual near-miss hotels or places, each with what it does and does not meet, to choose from.

### 7. Invented locations
- Places that could not be geocoded used to get a coordinate computed from their name, so their pins and routes were not real. Now a place that cannot be located is left out ([hotspot_finder.dart](urbanpulse_flutter/lib/agents/bhatkanti/hotspot_finder.dart)).

## Principles for the fix
- **No time limits on planning.** The loop ends only when:
  - the itinerary passes the completeness goal; or
  - the traveller explicitly accepts a gap in an MCQ; or
  - the traveller presses Stop.
- **No agent is ever asked to hurry.** Nothing skips enrichment, verification or questions because of elapsed time.
- The only speed-ups allowed keep results the same or better: parallelism, caching, a second Groq key, and reusing data already fetched.
- Per-request network timeouts stay. They are I/O hygiene (a dead socket fails over to the next provider or key) and never cut an agent's work short.
- **The loop is finite without timers.** Every automatic repair is tried at most once per missing item. When a missing item has no automatic repair left, Yatri must ask the traveller.

## Fix plan (in order)

### Step 0: set up and reproduce
1. Sync `main`, then branch `fix/yatri-goal-driven-planner`.
2. Put the test Groq key in the gitignored `urbanpulse_flutter/config.json` as `GROQ_API_KEY_2` (two keys give 6 concurrent LLM slots). **Never commit it.**
3. Add a live trace harness, `test/live/plan_trace_test.dart`:
   - Tag it `live`. It is skipped unless a key comes in through an env var or dart-define.
   - It builds `AgentToolkit.fromConfig` and runs `PlannerOrchestrator` with the auto-answering `Traveller` from `test/agents/planner_orchestrator_test.dart`.
   - It prints every node (status, elapsed, summary), the feed, `LlmPool.calls`, and the visits per day.
   - Scenarios:
     - (a) Goa, 3 days from Mumbai, no needs.
     - (b) Jaipur, 4 days, wheelchair + elderly + walking `lt100`.
     - (c) Munnar on a tight budget.
   - Run it before any fix, to confirm the timeout and skip trail.

### Step 1: remove time as a control signal
1. `TaskBoard`: drop the task-level timeout (`_withActiveTimeout`, `_abandonedIds`, `_stopDescendants` on timeout, and "late results ignored").
   - A task ends when its worker returns, or when the traveller cancels.
   - `TaskSpec.timeout` is removed.
2. `PlanClock` becomes a stopwatch only: `elapsed`, pause while waiting for the user, and the per-agent timings.
   - Delete `degradeAfter`, `deadline`, `degraded`, `expired` and `remaining`.
   - Delete `TaskContext.degraded`, and the `spec.optional && clock.degraded` skip.
3. Remove every time-based exit, and replace any that bounded a loop with a progress bound:
   - `planner_orchestrator.dart`: `clock.expired` at 393, 429, 504, 580 and 685.
   - `hotspot_finder.dart`: `isDegraded` at 169, 198 and 219.
   - `khoji_agent.dart`: 37 and 173.
   - `khoji.dart`: 115 and 199.
   - `atithi_agent.dart` and `bhatkanti_agent.dart`: their `!ctx.degraded` checks.
4. Keep Stop: `board.cancel()` is wired to a Stop button in the task-graph card. It ends the run and shows whatever exists as `PlanStatus.partial`.
5. Update the tests that assert time-based behaviour to the new semantics:
   - `planner_orchestrator_test.dart`: "a slow plan stops asking…".
   - `runtime_test.dart`: the timeout cases.
   - The chaos tests: add a source that never answers. Its HTTP timeout fires and the agent carries on.

### Step 2: the loop runs until the goal is met
1. Add a new `lib/agents/yatri/completeness_gate.dart`, `PlanCompleteness.check(itinerary, brief, accepted)`. It returns `Issue`s for:
   - A full day with fewer visits than the pace needs (relaxed 2, balanced 3, packed 4). Arrival and departure days need at least 1 visit when they have 3 h or more free.
   - No stay chosen and none explicitly skipped.
   - A journey that is neither planned nor noted.
   - A visit without a real location.
   - An unresolved access failure from Saksham.
2. Restructure `_plan` and `_settle` as a goal loop:
   1. Build.
   2. Run the gate.
   3. For each missing item, try the next untried automatic repair:
      - (i) fill from the pool or alternates;
      - (ii) re-run Bhatkanti with a wider radius or another style mix, at full quality;
      - (iii) reuse other agents' data (Wikipedia and Overpass candidates already fetched).
   4. When an item has no automatic repair left, ask an MCQ (Step 4).
   5. Rebuild.
   - The loop ends when the gate passes. An "accept this gap" answer counts as passing for that item.
3. `PlanStatus.planned` means the gate passed. `PlanStatus.partial` is used only after Stop.
4. Bhatkanti failing outright (an exception) is a missing item to repair. It is never "leave the days open" without asking.

### Step 3: faster without being worse
1. Start `_fromLlmKnowledge` in stage 1, alongside Overpass, Geoapify, Wikipedia and web search, instead of after the merge.
2. Geocode in parallel (6 at a time) everywhere, removing the sequential loop at [hotspot_finder.dart:621](urbanpulse_flutter/lib/agents/bhatkanti/hotspot_finder.dart#L621). The order:
   - Name-match against candidates already fetched from Overpass, Geoapify and Wikipedia (no network).
   - TomTom, when `AppConfig.hasTomTomKey`.
   - `PlaceGeocoder`.
   - Overpass by name.
3. Replace the hash dispersion with `locationApproximate: true`. Those places are never routed; the gate treats them as missing locations, and the traveller is asked if no source can place them.
4. Cache every geocode and search result, reusing the existing `DataCache`.
5. `LlmPool` already spreads agents across keys; with two keys configured, confirm that the agent-to-key spread balances the load.

### Step 4: when nothing fits, Yatri asks with real options (MCQ)
1. **Hotels** (`hotel_gates.dart`: `_access`, `_budget`). When no stay meets every need and the budget, ask one MCQ.
   - Options are the top 3 *actual* hotels. Each subtitle shows what is met, unknown and failed, plus the price.
   - Also offer: "raise the budget to ₹X", "search wider" and "I'll arrange my own stay".
   - Picking a hotel sets it directly (the `swapHotel` path in `_applyChoice`).
2. **Places** (`hotspot_gates.dart`, fed by the gate). When there are too few suitable places, ask one multi-select question.
   - Options are near-miss places, each with its reason ("≈40 steps at entrance", "access unconfirmed").
   - Also offer: "look further out", "fill with accessible indoor options" and "leave this half-day free".
3. **Relaxation ladder.** Relax in a fixed order: radius → budget → unconfirmed access with a check → pace.
   - Each step is asked, never applied silently.
   - Accepted relaxations are recorded in `_State` and shown in the itinerary's assumptions.
4. **Answers must change the plan.** Add a test for each question type that the answer changes state:
   - The mix choice changes `selected`.
   - The a11y details change selection and Raah's limits.
   - A picked hotel becomes `st.hotel`.

### Step 5: use every preference
1. Pass `accessibilityDetails`, `dietary`, `seniors` and `pace` into `HotspotQuery` and `HotelQuery`.
2. `HotspotFinder.select`, when mobility needs are present:
   - Exclude access `no` whenever alternatives exist.
   - Penalise `unknown`.
   - Drop stair-heavy and trek places when the answers include "avoid stairs" or `lt100`.
3. Hotel ranking: add facility matching for "lift", "roll-in shower", "ground floor" and "medical nearby".
4. Raah:
   - Take the walk limit from `a11y.mobility.walking`: `lt100` → 0.1 km, `100_500` → 0.4 km, `500_1000` → 0.8 km.
   - When the answers include `slow_pace` or `elderlyCare`: one visit fewer per day and visit time ×1.25.
   - Add rest slots when `rest_stops` is chosen.
   - Filter or annotate meal places using `dietary`.
   - Treat a `brief.end` at 00:00 (a date-only end) as 18:00 on that day.

### Step 6: Khoji finds forum reviews
1. Run Khoji as its own Yatri-delegated nodes after Atithi and Bhatkanti return: 3 hotels plus 3 places, run in parallel, never skipped.
2. Use forum-targeted queries:
   - `"<name>" <city> review site:reddit.com`
   - `site:tripadvisor.in "<name>"`
   - `"<name>" wheelchair OR accessible review`
3. Raise the compound request timeout from 14 s to 30 s (an I/O timeout). Give Khoji its own `maxLlmSearches` budget.
4. Never use the Wikipedia provider for review queries (add a `purpose` argument to `WebSearchTool.run`).
5. When no provider could search, the plan notes say "reviews unavailable: no search provider".

### Step 7: prompts, UI and narration
1. **Bhatkanti web and knowledge prompts:**
   - Add the access details as hard constraints.
   - Ask for the locality of each place (for geocoding), opening days, and `stepFree: true|false|unknown` with a reason.
   - When needs are present, ask for accessible alternatives.
2. **Khoji prompt:** lower-rated reviews first, source URLs, quoted access mentions, and "none found" when there are none.
3. **Optional Yatri critique (flag):** after assembly, make one heavy-tier call that checks the itinerary against the brief. Its structured `Issue`s feed the same goal loop; the deterministic policy stays in charge.
4. **`yatri_controller._planWithAgents`:**
   - Show a live "what's still missing" line while the loop repairs.
   - Offer a Stop button.
   - Handle `partial` with a retry action.
   - Stop falling back to the phase-1 plan when an itinerary exists.
5. Narrate every repair step in the feed.

## Verification
- **Unit and orchestrator tests** (scripted replies in `test/agents/scripted.dart` and `hotel_world.dart`):
  - A slow Bhatkanti (a scripted HTTP delay of several minutes on the test clock) still completes, and the days have visits.
  - An itinerary with only check-in fails the gate and triggers a repair.
  - Wheelchair + elderly + `lt100` with no matching hotel leads to an MCQ listing real hotels, and picking one sets the stay.
  - Too few accessible places leads to the near-miss multi-select question, and "accept gap" ends the loop.
  - The a11y details change selection and Raah's walk limit.
  - Khoji always runs for the top hotels and places.
  - The loop terminates when every repair fails, because each item ends in a question.
- **Existing suites** stay green once updated for the no-timeout semantics: `planner_orchestrator_test`, `runtime_test`, `chaos_test`, `full_pipeline_chaos_test`, `day_planner_test`, `tools_test`.
- **Live:** `flutter test --tags live` with the test key on scenarios (a)–(c). Every scenario must meet all of these:
  - It ends `planned`.
  - Every full day has at least the pace minimum of visits.
  - At least one hotel or place has review claims from a non-Wikipedia source.
  - No node was skipped for time.
  - Total active time is printed, for information only.
- **Manual:** build the APK and run the same three trips in the app.
