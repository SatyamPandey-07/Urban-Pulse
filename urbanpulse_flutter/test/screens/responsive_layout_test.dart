import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:urbanpulse/core/app_colors.dart';
import 'package:urbanpulse/core/app_theme.dart';
import 'package:urbanpulse/core/responsive.dart';
import 'package:urbanpulse/core/routes.dart';
import 'package:urbanpulse/screens/home_screen.dart';
import 'package:urbanpulse/services/web_relay_client.dart';

const _destinations = [
  NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
  NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Live Map'),
  NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
];

void _size(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _shell(ValueNotifier<int> index) => MaterialApp(
  theme: AppTheme.dark(AccentColor.green),
  home: ValueListenableBuilder<int>(
    valueListenable: index,
    builder: (context, i, _) => AdaptiveNavShell(
      selectedIndex: i,
      onDestinationSelected: (n) => index.value = n,
      destinations: _destinations,
      header: AppBar(title: const Text('Header')),
      body: Text('page $i'),
    ),
  ),
);

void main() {
  group('window size classes', () {
    test('phones, tablets and desktops', () {
      expect(WindowSize.fromWidth(390), WindowSize.compact);
      expect(WindowSize.fromWidth(599), WindowSize.compact);
      expect(WindowSize.fromWidth(600), WindowSize.medium);
      expect(WindowSize.fromWidth(1199), WindowSize.medium);
      expect(WindowSize.fromWidth(1200), WindowSize.expanded);
    });
  });

  group('home navigation adapts to the window', () {
    testWidgets('phone: a bottom navigation bar', (tester) async {
      _size(tester, 390, 844);
      final index = ValueNotifier(0);
      await tester.pumpWidget(_shell(index));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      await tester.tap(find.text('Settings'));
      await tester.pump();
      expect(find.text('page 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet: a rail with labels', (tester) async {
      _size(tester, 820, 1180);
      final index = ValueNotifier(0);
      await tester.pumpWidget(_shell(index));
      expect(find.byType(NavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
      expect(find.text('Header'), findsOneWidget);
      await tester.tap(find.text('Live Map'));
      await tester.pump();
      expect(find.text('page 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop: a labelled side menu with the brand', (tester) async {
      _size(tester, 1440, 900);
      final index = ValueNotifier(0);
      await tester.pumpWidget(_shell(index));
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
      expect(find.text('UrbanPulse'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('pushed screens on wide windows', () {
    Future<double> pageWidth(WidgetTester tester, String route) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AccentColor.green),
          initialRoute: '/start',
          routes: {
            '/start': (_) => const Scaffold(body: Text('start')),
            route: (_) => const Scaffold(key: Key('page'), body: Text('page')),
          },
        ),
      );
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route);
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(const Key('page'))).width;
    }

    testWidgets('are centred at a readable width on a desktop', (tester) async {
      _size(tester, 1440, 900);
      expect(await pageWidth(tester, Routes.hospitality), 1120);
    });

    testWidgets('sign-in forms are a narrow card', (tester) async {
      _size(tester, 1440, 900);
      expect(await pageWidth(tester, Routes.login), 560);
    });

    testWidgets('the home shell keeps the whole window', (tester) async {
      _size(tester, 1440, 900);
      expect(await pageWidth(tester, Routes.home), 1440);
    });

    testWidgets('phones see pages full width, as before', (tester) async {
      _size(tester, 390, 844);
      expect(await pageWidth(tester, Routes.hospitality), 390);
    });
  });

  group('website relay', () {
    test('only sources that refuse browsers go through the relay', () {
      final c = WebRelayClient(http.Client(), 'https://api.example.org');
      final news = Uri.parse('https://news.google.com/rss/search?q=Jaipur+rain&hl=en-IN');
      final routed = c.route(news);
      expect(routed.toString(), startsWith('https://api.example.org/relay?url='));
      expect(Uri.parse(routed.queryParameters['url']!), news);
      expect(c.route(Uri.parse('https://data.xotelo.com/api/list?location_key=g1')).path, '/relay');
      expect(c.route(Uri.parse('https://api.nugen.in/api/v3/inference/chat/completions')).path, '/relay');
      // Everything else goes straight out.
      final meteo = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=26.9');
      expect(c.route(meteo), meteo);
      expect(c.route(Uri.parse('https://api.groq.com/openai/v1/chat/completions')).host, 'api.groq.com');
    });

    test('a relayed request keeps its method, headers and body', () async {
      late http.Request seen;
      final inner = MockClient((r) async {
        seen = r;
        return http.Response('{"ok":true}', 200);
      });
      final c = WebRelayClient(inner, 'https://api.example.org');
      final res = await c.post(
        Uri.parse('https://api.nugen.in/api/v3/inference/chat/completions'),
        headers: {'Authorization': 'Bearer k', 'Content-Type': 'application/json'},
        body: '{"model":"m"}',
      );
      expect(res.statusCode, 200);
      expect(seen.method, 'POST');
      expect(seen.url.host, 'api.example.org');
      expect(seen.headers['Authorization'], 'Bearer k');
      expect(seen.body, '{"model":"m"}');
    });
  });
}
