import 'agent_kind.dart';
import 'report.dart';
import 'task_board.dart';
import 'task_graph.dart';

typedef DemoAsk = Future<String> Function(String question, List<String> options);

/// A scripted, offline run of the whole planner: no network, no models. It
/// drives the same [TaskBoard] the real orchestrator uses, so the task-graph UI
/// can be developed and demonstrated before every agent exists, and tests can
/// assert on the graph's behaviour.
///
/// The story is the one from the product brief: Atithi finds hotels but none is
/// wheelchair accessible within the budget, so Yatri asks the user, then
/// re-tasks Atithi; Khoji verifies claims; Hisab negotiates the budget; Raah
/// moves a rainy-day outdoor stop.
Future<AgentReport> runDemoPlan(
  TaskBoard board, {
  double speed = 1.0,
  DemoAsk? ask,
}) async {
  Future<void> work(int ms) => Future<void>.delayed(Duration(milliseconds: (ms * speed).round()));

  AgentReport done(AgentKind a, String summary, {String? why, ReportStatus status = ReportStatus.done}) =>
      AgentReport(agent: a, status: status, summary: summary, why: why);

  final answer = ask ?? (q, options) async {
    await work(2500);
    return options.first;
  };

  // 1. Yatri plans and allocates.
  final plan = await board.submit(
    const TaskSpec(
      id: 'yatri.plan',
      agent: AgentKind.yatri,
      title: 'Plan the trip',
      why: 'Yatri reads your trip brief and decides who should research what.',
    ),
    (ctx) async {
      await work(500);
      ctx.say(
        'allocated tasks to Atithi, Bhatkanti and Safar',
        why: 'Hotels, places and transport can be researched at the same time, which gets you a plan sooner.',
        kind: FeedKind.allocate,
      );
      return done(AgentKind.yatri, 'Plan made: 4 workers assigned',
          why: 'Yatri splits the trip into stay, places and travel.');
    },
  );

  // 2. Workers run in parallel.
  final atithi = board.submit(
    const TaskSpec(
      id: 'atithi.hotels',
      agent: AgentKind.atithi,
      title: 'Find hotels',
      parents: ['yatri.plan'],
      why: 'You need somewhere to sleep that fits your budget and access needs.',
    ),
    (ctx) async {
      await work(1800);
      ctx.say('found 4 relevant hotels', why: 'Shortlisted from live listings near the places you will visit.', kind: FeedKind.found);
      final verified = await ctx.delegate(
        const TaskSpec(
          id: 'khoji.hotels',
          agent: AgentKind.khoji,
          title: 'Verify hotel claims',
          why: 'Listings often overstate accessibility, so Khoji checks reviews and other sources.',
        ),
        (c) async {
          await work(1400);
          c.say('found 2 lower-rated reviews that mention narrow doorways', why: 'Low ratings show what listings leave out.', kind: FeedKind.verify);
          return done(AgentKind.khoji, 'Checked 4 claims across 3 sources');
        },
        say: 'asked Khoji to verify the accessibility claims',
      );
      return done(AgentKind.atithi, '4 hotels found, ${verified.summary.toLowerCase()}');
    },
  );

  final bhatkanti = board.submit(
    const TaskSpec(
      id: 'bhatkanti.spots',
      agent: AgentKind.bhatkanti,
      title: 'Find hotspots',
      parents: ['yatri.plan'],
      why: 'A 4-day trip fits roughly 20 places; Bhatkanti picks the best for your interests.',
    ),
    (ctx) async {
      await work(2400);
      ctx.say('found 18 hotspots, 1 needs your call', why: 'A famous fort and a newly opened cafe are both good but compete for the same afternoon.', kind: FeedKind.found);
      return done(AgentKind.bhatkanti, '18 hotspots found');
    },
  );

  final safar = board.submit(
    const TaskSpec(
      id: 'safar.transport',
      agent: AgentKind.safar,
      title: 'Plan transport',
      parents: ['yatri.plan'],
      why: 'How you get there decides the cost, the time and the carbon footprint.',
    ),
    (ctx) async {
      await work(1500);
      return done(AgentKind.safar, 'priced train, bus and flight options');
    },
  );

  final hisab = board.submit(
    const TaskSpec(
      id: 'hisab.budget',
      agent: AgentKind.hisab,
      title: 'Check the budget',
      parents: ['atithi.hotels', 'safar.transport'],
      why: 'Hisab makes sure the hotel and the travel together stay inside your budget.',
    ),
    (ctx) async {
      ctx.say('negotiating with Atithi and Safar', why: 'A pricier hotel leaves less for travel, so the two have to be balanced.', kind: FeedKind.negotiate);
      await work(900);
      return done(AgentKind.hisab, 'Budget holds with ₹3,200 to spare', status: ReportStatus.degraded);
    },
  );

  await Future.wait([atithi, bhatkanti, safar, hisab]);

  // 3. Yatri finds a conflict and asks the user.
  const question = 'None of the 4 hotels are wheelchair accessible within ₹1,000 a night. '
      'Should I look at options with a higher budget?';
  const options = ['Yes, up to ₹1,800 a night', 'No, keep searching at ₹1,000'];
  final choice = await board.submit(
    const TaskSpec(
      id: 'yatri.ask',
      agent: AgentKind.yatri,
      title: 'Ask about budget',
      parents: ['atithi.hotels', 'hisab.budget'],
      why: 'Access matters more than a few hundred rupees, but it is your money, so Yatri asks first.',
    ),
    (ctx) async {
      ctx.say('needs your decision on the hotel budget', why: 'The only accessible hotels cost more than you set.', kind: FeedKind.ask);
      final picked = await ctx.waitForUser(() => answer(question, options));
      return AgentReport(
        agent: AgentKind.yatri,
        status: ReportStatus.done,
        summary: 'You chose: $picked',
        payload: picked,
      );
    },
  );

  // 4. Re-task Atithi with the new constraint.
  await board.submit(
    const TaskSpec(
      id: 'atithi.retry',
      agent: AgentKind.atithi,
      title: 'Find accessible hotels',
      parents: ['yatri.ask'],
      why: 'With the higher budget, Atithi searches again for step-free rooms.',
    ),
    (ctx) async {
      await work(1300);
      return done(AgentKind.atithi, 'found 3 step-free hotels within ₹1,800');
    },
  );

  // 5. Gates run in parallel.
  final saksham = board.submit(
    const TaskSpec(
      id: 'saksham.audit',
      agent: AgentKind.saksham,
      title: 'Audit accessibility',
      parents: ['atithi.retry', 'bhatkanti.spots'],
      why: 'Checks every step (hotel, taxi, attraction, restaurant) works for the whole group, not just each place alone.',
    ),
    (ctx) async {
      await work(1300);
      ctx.say('flagged 1 step that needs confirmation', why: 'The fort entrance is step-free but the viewpoint path is steep.', kind: FeedKind.warn);
      return done(AgentKind.saksham, '11 of 12 steps confirmed', status: ReportStatus.degraded);
    },
  );
  final raah = board.submit(
    const TaskSpec(
      id: 'raah.route',
      agent: AgentKind.raah,
      title: 'Order the days',
      parents: ['atithi.retry', 'bhatkanti.spots'],
      why: 'Puts places in a practical order using distance, opening hours and the weather forecast.',
    ),
    (ctx) async {
      await work(1100);
      ctx.say('moved the ghat walk to day 3', why: 'Heavy rain is forecast on day 2, and the ghat is outdoors.', kind: FeedKind.decide);
      return done(AgentKind.raah, 'Days ordered around the weather');
    },
  );
  final hariyali = board.submit(
    const TaskSpec(
      id: 'hariyali.green',
      agent: AgentKind.hariyali,
      title: 'Score sustainability',
      parents: ['safar.transport'],
      why: 'Shows what each choice costs the planet and suggests greener ones.',
    ),
    (ctx) async {
      await work(800);
      ctx.say('found the train saves 96 kg CO2 over flying', why: 'Trains emit far less per passenger than planes.', kind: FeedKind.found);
      return done(AgentKind.hariyali, 'Green score 82 of 100');
    },
  );
  await Future.wait([saksham, raah, hariyali]);

  // 6. Yatri finalises.
  final result = await board.submit(
    const TaskSpec(
      id: 'yatri.final',
      agent: AgentKind.yatri,
      title: 'Finalise itinerary',
      parents: ['saksham.audit', 'raah.route', 'hariyali.green'],
      why: 'Yatri merges every agent’s work into one itinerary and flags anything still unconfirmed.',
    ),
    (ctx) async {
      await work(700);
      return AgentReport(
        agent: AgentKind.yatri,
        status: ReportStatus.done,
        summary: 'Itinerary ready: ${choice.summary.toLowerCase()}',
        payload: {'choice': choice.payload, 'plan': plan.summary},
      );
    },
  );
  return result;
}
