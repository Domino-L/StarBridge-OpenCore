// Batch 2: cross-region side navigation (01), top bar pieces (02).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

class _Host extends StatefulWidget {
  const _Host({required this.suite, required this.child});
  final InteractionSuite suite;
  final Widget child;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool reduce = false;
  void setReduce(bool v) => setState(() => reduce = v);

  @override
  Widget build(BuildContext context) => InteractionScope(
    data: InteractionData(suite: widget.suite, palette: palette, reduceMotion: reduce),
    child: MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(alignment: Alignment.topLeft, child: widget.child),
        ),
      ),
    ),
  );
}

const _home = SideNavItem(id: 'home', label: 'Home', icon: Icons.home);
final _primary = [
  SideNavSection(
    items: [for (var i = 0; i < 10; i++) SideNavItem(id: 'p$i', label: 'Primary $i', icon: Icons.circle)],
  ),
];
const _personal = [
  SideNavItem(id: 'me', label: 'Hangar', icon: Icons.warehouse),
  SideNavItem(id: 'set', label: 'Settings', icon: Icons.settings),
];

class _Nav extends StatefulWidget {
  const _Nav({this.onSource});
  final ValueChanged<InteractionSource>? onSource;

  @override
  State<_Nav> createState() => _NavState();
}

class _NavState extends State<_Nav> {
  String selected = 'p1';
  bool compact = false;
  void setCompact(bool v) => setState(() => compact = v);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 360,
    child: SuiteSideNav(
      home: _home,
      primary: _primary,
      personal: _personal,
      selectedId: selected,
      compact: compact,
      onSelect: (id, s) {
        widget.onSource?.call(s);
        setState(() => selected = id);
      },
    ),
  );
}

SuiteSideNavState _nav(WidgetTester t) => t.state<SuiteSideNavState>(find.byType(SuiteSideNav));

Future<void> _frames(WidgetTester t, int ms) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('01 side navigation', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: crosses into the personal region and settles on it', (t) async {
        await t.pumpWidget(_Host(suite: suite, child: const _Nav()));
        await t.pumpAndSettle();
        await t.tap(find.text('Settings'));
        await t.pump();
        // Glow's landing ripple ends ~760 ms after the click.
        await _frames(t, 900);
        final s = _nav(t);
        expect(s.indicatorRect, s.rectOf('set'));
        expect(t.hasRunningAnimations, isFalse);
      });

      testWidgets('${suite.name}: home hides the indicator; leaving home shows it on the target', (t) async {
        await t.pumpWidget(_Host(suite: suite, child: const _Nav()));
        await t.pumpAndSettle();
        await t.tap(find.text('Home'));
        await _frames(t, 400);
        final s = _nav(t);
        expect(s.indicatorRect, isNull);
        await t.tap(find.text('Primary 3'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 16));
        // Fading in on the target: never placed anywhere else.
        expect(s.indicatorRect, s.rectOf('p3'));
        await _frames(t, 400);
        expect(s.indicatorRect, s.rectOf('p3'));
      });
    }

    testWidgets('the indicator follows the target while the region scrolls', (t) async {
      await t.pumpWidget(const _Host(suite: InteractionSuite.rail, child: _Nav()));
      await t.pumpAndSettle();
      final s = _nav(t);
      final before = s.indicatorRect!;
      s.scrollController.jumpTo(60);
      await t.pump();
      expect(s.indicatorRect, s.rectOf('p1'));
      expect(s.indicatorRect!.top, closeTo(before.top - 60, 0.5));
      expect(t.hasRunningAnimations, isFalse);
    });

    for (final suite in [InteractionSuite.rail, InteractionSuite.scan, InteractionSuite.glow]) {
      testWidgets('${suite.name}: arrow keys walk every row instantly, across regions', (t) async {
        InteractionSource? source;
        await t.pumpWidget(_Host(suite: suite, child: _Nav(onSource: (s) => source = s)));
        await t.pumpAndSettle();
        final s = _nav(t);
        // Tab to Home, then walk down.
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        for (var i = 0; i < 12; i++) {
          await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await t.pump();
        }
        expect(source, InteractionSource.keyboard);
        final state = t.state<_NavState>(find.byType(_Nav));
        expect(state.selected, 'set');
        expect(s.indicatorRect, s.rectOf('set'));
        expect(t.hasRunningAnimations, isFalse);
      });

      testWidgets('${suite.name}: reduced motion mid-move lands at once', (t) async {
        await t.pumpWidget(_Host(suite: suite, child: const _Nav()));
        await t.pumpAndSettle();
        await t.tap(find.text('Settings'));
        await t.pump(const Duration(milliseconds: 60));
        t.state<_HostState>(find.byType(_Host)).setReduce(true);
        await t.pump();
        final s = _nav(t);
        expect(s.indicatorRect, s.rectOf('set'));
        expect(t.hasRunningAnimations, isFalse);
      });
    }

    testWidgets('compact rail narrows without replaying a selection effect', (t) async {
      await t.pumpWidget(const _Host(suite: InteractionSuite.glow, child: _Nav()));
      await t.pumpAndSettle();
      t.state<_NavState>(find.byType(_Nav)).setCompact(true);
      await t.pumpAndSettle();
      final s = _nav(t);
      expect(t.getSize(find.byType(SuiteSideNav)).width, 60);
      expect(s.indicatorRect, s.rectOf('p1'));
      expect(find.text('Primary 1'), findsNothing);
    });

    testWidgets('a new target mid-move retargets from the current position', (t) async {
      await t.pumpWidget(const _Host(suite: InteractionSuite.glow, child: _Nav()));
      await t.pumpAndSettle();
      await t.tap(find.text('Settings'));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.text('Primary 2'));
      await _frames(t, 800);
      final s = _nav(t);
      expect(s.indicatorRect, s.rectOf('p2'));
    });
  });

  group('02 top bar', () {
    Widget menu({ValueChanged<String>? onPick}) => Align(
      alignment: Alignment.topRight,
      child: SuiteMenuButton(
        semanticLabel: 'account',
        anchorBuilder: (context, open) => const Text('ME'),
        actions: [
          SuiteMenuAction(label: 'Profile', onSelected: () => onPick?.call('profile')),
          const SuiteMenuAction(label: 'Soon'),
          SuiteMenuAction(label: 'Security', onSelected: () => onPick?.call('security')),
          SuiteMenuAction(label: 'Sign out', danger: true, dividerBefore: true, onSelected: () => onPick?.call('out')),
        ],
      ),
    );

    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: keyboard opens on the first row, skips disabled, Esc returns focus', (t) async {
        final picked = <String>[];
        await t.pumpWidget(_Host(suite: suite, child: SizedBox(width: 500, child: menu(onPick: picked.add))));
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        await t.pump();
        expect(find.text('Profile'), findsOneWidget);
        // Standard is stock Material: its 200 ms focus-highlight fade is focus
        // feedback, which the keyboard path keeps.
        if (suite != InteractionSuite.standard) {
          expect(t.hasRunningAnimations, isFalse);
        }
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'menu-row-0');
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'menu-row-2');
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(find.text('Profile'), findsNothing);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'menu-anchor');
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(picked, ['out']);
        expect(find.text('Profile'), findsNothing);
      });
    }

    testWidgets('menu grows from the button: right edges line up', (t) async {
      await t.pumpWidget(_Host(suite: InteractionSuite.rail, child: SizedBox(width: 500, child: menu())));
      await t.tap(find.text('ME'));
      await t.pumpAndSettle();
      final anchor = t.getRect(find.byType(SuiteMenuButton));
      final menuRect = t.getRect(find.ancestor(of: find.text('Profile'), matching: find.byType(Container)).last);
      expect(menuRect.right, closeTo(anchor.right, 1));
      expect(menuRect.top, greaterThan(anchor.bottom));
      // Outside tap closes it and still reaches the page.
      await t.tapAt(const Offset(40, 300));
      await t.pumpAndSettle();
      expect(find.text('Profile'), findsNothing);
    });

    testWidgets('breadcrumb: earlier crumbs report index; the current one is text', (t) async {
      final taps = <int>[];
      await t.pumpWidget(
        _Host(
          suite: InteractionSuite.scan,
          child: SuiteBreadcrumb(crumbs: const ['Org', 'Fleet', 'Members'], onTap: (i, _) => taps.add(i)),
        ),
      );
      await t.tap(find.text('Fleet'));
      await t.tap(find.text('Members'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(taps, [1]);
    });
  });
}
