import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_expansion_tile.dart';
import 'package:starbridge_flutter/features/settings/help_support_expansion_tile.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

const bodyKey = Key('body-content');
Finder get header => find.byType(SuitePressable).first;
SuiteExpander expander(WidgetTester t) =>
    t.widget<SuiteExpander>(find.byType(SuiteExpander));
Future<void> activate(WidgetTester t, String source) async {
  if (source == 'pointer') {
    await t.tap(header);
  } else if (source == 'reader') {
    final node = t.getSemantics(header);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  } else {
    t.widget<SuitePressable>(header).focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(
      source == 'space' ? LogicalKeyboardKey.space : LogicalKeyboardKey.enter,
    );
  }
  await t.pump();
}

List<SemanticsNode> nodes(WidgetTester t) {
  final result = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    result.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(t.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!);
  return result;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final storage in ['own', 'ancestor', 'none']) {
      testWidgets(
        '$suite native storage $storage survives replacement both ways',
        (t) async {
          size(t, const Size(800, 1000));
          final bucket = PageStorageBucket();
          Widget app(bool native, bool open) => scopedApp(
            PageStorage(
              bucket: bucket,
              child: KeyedSubtree(
                key: storage == 'ancestor'
                    ? const PageStorageKey('ancestor')
                    : null,
                child: native
                    ? ExpansionTile(
                        key: storage == 'own'
                            ? const PageStorageKey('entry')
                            : null,
                        initiallyExpanded: open,
                        title: const Text('Details'),
                        children: const [Text('Body')],
                      )
                    : HelpSupportExpansionTile(
                        key: storage == 'own'
                            ? const PageStorageKey('entry')
                            : null,
                        initiallyExpanded: open,
                        title: const Text('Details'),
                        children: const [Text('Body')],
                      ),
              ),
            ),
            suite,
          );
          await t.pumpWidget(app(true, false));
          await t.pumpAndSettle();
          await t.tap(find.byType(ListTile));
          await t.pumpAndSettle();
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(app(false, false));
          await t.pumpAndSettle();
          expect(expander(t).expanded, storage != 'none');
          if (expander(t).expanded) {
            await activate(t, 'pointer');
            await t.pumpAndSettle();
          }
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(app(true, true));
          await t.pumpAndSettle();
          expect(
            find.text('Body'),
            storage == 'none' ? findsOneWidget : findsNothing,
          );
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      '$suite native release keys isolate bool and default suite namespace',
      (t) async {
        size(t, const Size(800, 1000));
        final bucket = PageStorageBucket();
        Widget app(String id, {bool suiteDefault = false, bool open = false}) =>
            scopedApp(
              PageStorage(
                bucket: bucket,
                child: suiteDefault
                    ? StarBridgeExpansionTile(
                        key: PageStorageKey(id),
                        title: 'Details',
                        initiallyExpanded: open,
                        children: const [Text('Body')],
                      )
                    : HelpSupportExpansionTile(
                        key: PageStorageKey(id),
                        title: const Text('Details'),
                        initiallyExpanded: open,
                        children: const [Text('Body')],
                      ),
              ),
              suite,
            );
        await t.pumpWidget(app('release-A'));
        await t.pumpAndSettle();
        await activate(t, 'pointer');
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(app('release-B'));
        await t.pumpAndSettle();
        expect(expander(t).expanded, isFalse);
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(app('release-A'));
        await t.pumpAndSettle();
        expect(expander(t).expanded, isTrue);
        await activate(t, 'pointer');
        await t.pumpAndSettle(); // native false
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(app('release-A', suiteDefault: true, open: true));
        await t.pumpAndSettle();
        expect(
          expander(t).expanded,
          isTrue,
        ); // native false must not override namespace
        await activate(t, 'pointer');
        await t.pumpAndSettle(); // namespace false
        await activate(t, 'pointer');
        await t.pumpAndSettle(); // namespace true
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(app('release-A', open: true));
        await t.pumpAndSettle();
        expect(
          expander(t).expanded,
          isFalse,
        ); // namespace true must not override native
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final source in ['pointer', 'enter', 'space', 'reader']) {
      testWidgets('$suite builder $source single action and exit exclusion', (
        t,
      ) async {
        size(t, const Size(800, 1000));
        final semantics = t.ensureSemantics();
        final bodyFocus = FocusNode();
        var expanded = false, calls = 0, bodyCalls = 0;
        late StateSetter update;
        await t.pumpWidget(
          scopedApp(
            StatefulBuilder(
              builder: (context, set) {
                update = set;
                return StarBridgeExpansionTile(
                  title: 'Details',
                  subtitle: 'Date',
                  headerMinHeight: 0,
                  headerBuilder: (context, visual, open) => const ListTile(
                    mouseCursor: MouseCursor.defer,
                    title: Text('Details'),
                    subtitle: Text('Date'),
                  ),
                  initiallyExpanded: expanded,
                  onExpansionChanged: (value) {
                    calls++;
                    expanded = value;
                  },
                  children: [
                    TextButton(
                      key: bodyKey,
                      focusNode: bodyFocus,
                      onPressed: () => bodyCalls++,
                      child: const Text('Body action'),
                    ),
                  ],
                );
              },
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        var targets = nodes(t).where(
          (n) =>
              n.getSemanticsData().label == 'Details' &&
              n.getSemanticsData().hasAction(SemanticsAction.tap),
        );
        expect(targets, hasLength(1));
        expect(targets.single.getSemanticsData().value, 'Date');
        await activate(t, source);
        expect(calls, 1);
        expect(expanded, isTrue);
        if (source != 'pointer') expect(t.hasRunningAnimations, isFalse);
        await t.pumpAndSettle();
        final bodyPoint = t.getCenter(find.byKey(bodyKey));
        bodyFocus.requestFocus();
        await t.pump();
        expect(bodyFocus.hasFocus, isTrue);
        await activate(t, source);
        expect(calls, 2);
        expect(expanded, isFalse);
        expect(bodyFocus.hasFocus, isFalse);
        expect(t.widget<SuitePressable>(header).focusNode!.hasFocus, isTrue);
        expect(
          nodes(t).where((n) => n.getSemanticsData().label == 'Body action'),
          isEmpty,
        );
        await t.tapAt(bodyPoint);
        expect(bodyCalls, 0);
        await t.pumpAndSettle();
        expect(find.byKey(bodyKey, skipOffstage: false), findsNothing);
        update(() {});
        await t.pump();
        expect(calls, 2);
        await t.pumpWidget(const SizedBox());
        bodyFocus.dispose();
        semantics.dispose();
      });
    }
    testWidgets('$suite disabled custom builder cannot activate', (t) async {
      size(t, const Size(800, 1000));
      final semantics = t.ensureSemantics();
      await t.pumpWidget(
        scopedApp(
          SuiteExpander(
            title: 'Disabled',
            expanded: false,
            onChanged: null,
            headerBuilder: (context, visual, open) => ListTile(
              mouseCursor: MouseCursor.defer,
              title: Text(visual.enabled ? 'Enabled' : 'Disabled'),
            ),
            child: const Text('Body'),
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .getSemantics(header)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      await t.tap(header);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(expander(t).expanded, isFalse);
      expect(t.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
      await t.pumpWidget(const SizedBox());
      semantics.dispose();
    });
    for (final opening in [false, true]) {
      for (final system in [false, true]) {
        testWidgets(
          '$suite ${opening ? 'opening' : 'closing'} interrupted by ${system ? 'system' : 'local'} reduce',
          (t) async {
            size(t, const Size(800, 1000));
            var reduce = false;
            Widget app() => scopedApp(
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: system && reduce),
                  child: HelpSupportExpansionTile(
                    title: const Text('Details'),
                    initiallyExpanded: !opening,
                    children: const [
                      SizedBox(key: bodyKey, height: 200, child: Text('Body')),
                    ],
                  ),
                ),
              ),
              suite,
              reduce: !system && reduce,
            );
            await t.pumpWidget(app());
            await t.pumpAndSettle();
            await activate(t, 'pointer');
            await t.pump(const Duration(milliseconds: 45));
            expect(expander(t).expanded, opening);
            reduce = true;
            await t.pumpWidget(app());
            await t.pump();
            expect(t.hasRunningAnimations, isFalse);
            expect(
              find.byKey(bodyKey, skipOffstage: false),
              opening ? findsOneWidget : findsNothing,
            );
            if (opening) expect(t.getSize(find.byKey(bodyKey)).height, 200);
            await t.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
