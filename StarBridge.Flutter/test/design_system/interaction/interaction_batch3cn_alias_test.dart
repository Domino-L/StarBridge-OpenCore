import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_section_stack.dart';
import 'package:starbridge_flutter/features/communities/community_section_stack.dart';

class Probe extends StatefulWidget {
  const Probe(this.id, {super.key});
  final String id;
  @override
  State<Probe> createState() => ProbeState();
}

class ProbeState extends State<Probe> with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  final focus = FocusNode();
  int ticks = 0;
  bool disposed = false, ticking = false;
  @override
  void initState() {
    super.initState();
    animation =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 100),
          )
          ..addListener(() => ticks++)
          ..repeat();
  }

  @override
  Widget build(BuildContext context) {
    ticking = TickerMode.valuesOf(context).enabled;
    return Focus(focusNode: focus, child: Text(widget.id));
  }

  @override
  void dispose() {
    disposed = true;
    animation.dispose();
    focus.dispose();
    super.dispose();
  }
}

Widget subject(String scope, String selected, {bool includeB = true}) =>
    MaterialApp(
      home: Scaffold(
        body: CommunitySectionStack(
          key: ValueKey(scope),
          selected: selected,
          sections: {
            'a': (_) => const Probe('a', key: ValueKey('probe-a')),
            if (includeB)
              'b': (_) => const Probe('b', key: ValueKey('probe-b')),
          },
        ),
      ),
    );

Finder probe(String id) =>
    find.byKey(ValueKey('probe-$id'), skipOffstage: false);

void main() {
  test('historical CommunitySectionStack typedef is the actual shared implementation', () {
    final alias = CommunitySectionStack(
      selected: 'a',
      sections: {'a': (_) => const SizedBox()},
    );
    expect(alias, isA<OrganizationSectionStack>());
    expect(alias.runtimeType, OrganizationSectionStack);
  });
  testWidgets(
    'shared alias lazily retains visited state and excludes hidden focus/tickers',
    (t) async {
      await t.pumpWidget(subject('authorized-A', 'a'));
      await t.pump();
      expect(probe('b'), findsNothing);
      final a = t.state<ProbeState>(probe('a'));
      a.focus.requestFocus();
      await t.pump();
      expect(a.focus.hasFocus, isTrue);
      await t.pumpWidget(subject('authorized-A', 'b'));
      await t.pump();
      final b = t.state<ProbeState>(probe('b'));
      expect(t.state<ProbeState>(probe('a')), same(a));
      expect(a.ticking, isFalse);
      expect(b.ticking, isTrue);
      expect(a.focus.canRequestFocus, isFalse);
      expect(a.focus.hasFocus, isFalse);
      final frozen = a.ticks, live = b.ticks;
      await t.pump(const Duration(milliseconds: 160));
      expect(a.ticks, frozen);
      expect(b.ticks, greaterThan(live));
      await t.pumpWidget(subject('authorized-A', 'a', includeB: false));
      await t.pump();
      expect(t.state<ProbeState>(probe('a')), same(a));
      expect(a.ticking, isTrue);
      expect(a.focus.canRequestFocus, isTrue);
      expect(b.disposed, isTrue);
      expect(probe('b'), findsNothing);
      await t.pumpWidget(const SizedBox());
      expect(a.disposed, isTrue);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'caller context key replacement does not retain another workspace section state',
    (t) async {
      await t.pumpWidget(subject('authorized-A', 'a'));
      await t.pump();
      final oldA = t.state<ProbeState>(probe('a'));
      await t.pumpWidget(subject('authorized-A', 'b'));
      await t.pump();
      final oldB = t.state<ProbeState>(probe('b'));
      await t.pumpWidget(subject('authorized-B', 'a'));
      await t.pump();
      expect(oldA.disposed, isTrue);
      expect(oldB.disposed, isTrue);
      expect(probe('b'), findsNothing);
      expect(t.state<ProbeState>(probe('a')), isNot(same(oldA)));
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    },
  );
}
