import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_announcement_details_control.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_announcement_details_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_image.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_controller.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart'
    show CommunityFailure;
import 'package:starbridge_flutter/features/communities/community_announcement_details.dart';

import '../../app/menu_overlay/menu_announcement_details_control_test.dart'
    show fixture;
import '../../features/friends/social_layout_test.dart' show size;
import '../../app/menu_overlay/menu_announcement_details_session_test.dart'
    show SessionPort;
import '../../features/communities/community_announcements_controller_test.dart'
    show AnnouncementsFake;
import '../../features/communities/community_announcements_test.dart'
    show target;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3ca_test.dart' show fire;

class Harness extends StatefulWidget {
  const Harness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  final nav = GlobalKey<NavigatorState>();
  late var suite = widget.suite;
  bool active = true,
      visible = true,
      enabled = true,
      reduce = false,
      light = false;
  String? action = 'a1';
  Map<String, Object?> raw = fixture();
  final calls = <(String, String, InteractionSource)>[];
  bool localReduce = false;
  void change(VoidCallback f) {
    setState(f);
    _rebuild.value++;
  }

  @override
  Widget build(BuildContext context) => scopedApp(
    Navigator(
      key: nav,
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => AnimatedBuilder(
          animation: _rebuild,
          builder: (context, _) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: localReduce),
            child: Center(
              child: visible
                  ? MenuAnnouncementDetailsControl(
                      view: MenuAnnouncementDetailsView.parse(raw)!,
                      action: action,
                      active: active,
                      enabled: enabled,
                      dispatch: (action, value) => calls.add((
                        action,
                        value,
                        currentStarBridgeActivationSource,
                      )),
                    )
                  : const Text('entry removed'),
            ),
          ),
        ),
      ),
    ),
    suite,
    reduce: reduce,
    light: light,
  );
  final _rebuild = ValueNotifier(0);

  @override
  void dispose() {
    _rebuild.dispose();
    super.dispose();
  }
}

Future<HarnessState> mount(WidgetTester t, InteractionSuite suite) async {
  size(t, const Size(1100, 1000));
  await t.pumpWidget(Harness(suite));
  await frames(t);
  return t.state<HarnessState>(find.byType(Harness));
}

Future<void> activate(WidgetTester t, String input, String id) =>
    fire(t, input, find.byKey(Key(id)));
InteractionSource origin(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;
StarBridgeDialogRoute<void> route(WidgetTester t) =>
    ModalRoute.of(t.element(find.byType(AlertDialog)))!
        as StarBridgeDialogRoute<void>;

void waitScope(WidgetTester t, bool reduce) {
  final progress = find.byType(SuiteProgressBar);
  expect(progress, findsOneWidget);
  expect(t.getSize(progress).width, greaterThan(100));
  expect(t.widget<SuiteProgressBar>(progress).value, isNull);
  expect(t.widget<SuiteProgressBar>(progress).phase, ProgressPhase.running);
  expect(InteractionScope.of(t.element(progress)).reduceMotion, reduce);
  for (final e in find.byType(CommunityWorkspaceImage).evaluate()) {
    expect(InteractionScope.of(e).reduceMotion, reduce);
  }
}

class MainPort extends AnnouncementsFake {
  Completer<void>? hold;
  final sources = <InteractionSource>[];
  @override
  Future<Map<String, Object?>> readAnnouncementDetail(
    String target,
    String ref,
    int offset,
    String? version,
  ) async {
    sources.add(currentStarBridgeActivationSource);
    await hold?.future;
    return super.readAnnouncementDetail(target, ref, offset, version);
  }
}

class MainHarness extends StatefulWidget {
  const MainHarness(this.model, this.suite, {super.key});
  final CommunityAnnouncementsController model;
  final InteractionSuite suite;
  @override
  State<MainHarness> createState() => MainHarnessState();
}

class MainHarnessState extends State<MainHarness> {
  late var model = widget.model;
  var visible = true, reduce = false, light = false;
  void change(VoidCallback f) => setState(f);
  @override
  Widget build(BuildContext context) => scopedApp(
    SingleChildScrollView(
      child: visible
          ? CommunityAnnouncementDetails(
              model: model,
              entry: model.page!.current!,
            )
          : const Text('removed main detail'),
    ),
    widget.suite,
    reduce: reduce,
    light: light,
  );
}

class PanelFixture {
  PanelFixture() {
    session = MenuOrganizationsSession(port, (view) => data.value = view);
  }
  final port = SessionPort();
  final data = ValueNotifier<Map<String, Object?>>({'state': 'loading'});
  final active = ValueNotifier(true);
  late final MenuOrganizationsSession session;
  final sources = <InteractionSource>[];
  Future<void> ready(WidgetTester t) async {
    session.show(true);
    await frames(t);
    final first = MenuFeatureView.parse(session.currentView);
    session.act(first.organization!.sections['announcements']!, '');
    await frames(t);
    expect(
      MenuFeatureView.parse(data.value).organization!.tab,
      'announcements',
    );
  }

  Widget page(InteractionSuite suite, {bool light = false}) => scopedApp(
    ValueListenableBuilder<bool>(
      valueListenable: active,
      builder: (context, active, _) =>
          ValueListenableBuilder<Map<String, Object?>>(
            valueListenable: data,
            builder: (context, view, _) => MenuOrganizationsPanel(
              view: MenuFeatureView.parse(view),
              active: active,
              onAction: (key, value) {
                sources.add(currentStarBridgeActivationSource);
                session.act(key, value);
              },
            ),
          ),
    ),
    suite,
    light: light,
  );
  Future<void> close(WidgetTester t) async {
    final held = port.gate;
    if (held != null && !held.isCompleted) {
      held.completeError(const CommunityFailure('unavailable'));
    }
    session.dispose();
    await t.pumpWidget(const SizedBox());
    await frames(t);
    data.dispose();
    active.dispose();
  }
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite $input actual session denial retires the details', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        final f = PanelFixture();
        try {
          size(t, const Size(1100, 1000));
          await f.ready(t);
          f.port.gate = Completer<Map<String, Object?>>();
          await t.pumpWidget(f.page(suite));
          await frames(t);
          await t.ensureVisible(
            find.byKey(const Key('menu-announcement-details-open')),
          );
          await activate(t, input, 'menu-announcement-details-open');
          await t.pump();
          await t.pump();
          expect(find.byType(AlertDialog), findsOneWidget);
          f.port.gate!.completeError(const CommunityFailure('notAllowed'));
          await frames(t);
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(CommunityAnnouncementDetailsBody), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
          await f.close(t);
        }
      });
      testWidgets(
        '$suite $input actual organization panel/session failure then retry',
        (t) async {
          final semantics = t.ensureSemantics();
          final f = PanelFixture();
          try {
            size(t, const Size(1100, 1000));
            await f.ready(t);
            f.port.gate = Completer<Map<String, Object?>>();
            await t.pumpWidget(f.page(suite));
            await frames(t);
            await t.ensureVisible(
              find.byKey(const Key('menu-announcement-details-open')),
            );
            await activate(t, input, 'menu-announcement-details-open');
            await t.pump();
            await t.pump();
            waitScope(t, input != 'pointer');
            expect(f.sources, [origin(input)]);
            expect(f.port.targets, hasLength(1));
            f.port.gate!.completeError(const CommunityFailure('unavailable'));
            await frames(t);
            expect(find.byType(SuiteProgressBar), findsNothing);
            await t.ensureVisible(
              find.byKey(const Key('announcement-detail-retry')),
            );
            f.port.gate = null;
            await activate(t, input, 'announcement-detail-retry');
            await frames(t);
            expect(f.sources, [origin(input), origin(input)]);
            expect(f.port.targets, hasLength(2));
            expect(
              find.byKey(const Key('announcement-detail-retry')),
              findsNothing,
            );
            expect(find.byType(SelectableText), findsNWidgets(2));
            expect(find.text('远航准备通知'), findsWidgets);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await f.close(t);
          }
        },
      );
      testWidgets(
        '$suite $input actual main detail owner retries without fake completion',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = MainPort()..detailFailure = 'unavailable';
          final model = CommunityAnnouncementsController(port, target);
          try {
            await model.enter();
            size(t, const Size(1100, 1000));
            await t.pumpWidget(MainHarness(model, suite));
            await frames(t);
            port.detailFailure = null;
            port.hold = Completer<void>();
            await activate(t, input, 'announcement-detail-retry');
            await t.pump();
            await t.pump();
            waitScope(t, input != 'pointer');
            expect(port.sources.last, origin(input));
            expect(port.sources, hasLength(2));
            expect(find.byType(SelectableText), findsNWidgets(2));
            port.hold!.complete();
            await frames(t);
            expect(find.byType(SuiteProgressBar), findsNothing);
            expect(
              find.byKey(const Key('announcement-detail-retry')),
              findsNothing,
            );
            expect(model.active, true);
          } finally {
            if (port.hold != null && !port.hold!.isCompleted) {
              port.hold!.complete();
            }
            await t.pumpWidget(const SizedBox());
            await frames(t);
            model.dispose();
            await port.changes.close();
            semantics.dispose();
          }
        },
      );
      testWidgets('$suite $input real entry/nearest route and actual wait', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        try {
          final h = await mount(t, suite);
          final root = Navigator.of(
            t.element(find.text('查看详情')),
            rootNavigator: true,
          );
          await activate(t, input, 'menu-announcement-details-open');
          await t.pump();
          final r = route(t);
          expect(r.navigator, same(h.nav.currentState));
          expect(r.navigator, isNot(same(root)));
          expect(r.instant, input != 'pointer');
          expect(h.calls, [('a1', '', origin(input))]);
          h.change(() => h.raw = fixture(loading: true));
          await t.pump();
          await t.pump();
          waitScope(t, input != 'pointer');
          expect(find.byType(SelectableText), findsNWidgets(2));
          h.change(() => h.raw = fixture());
          await frames(t);
          expect(find.byType(SuiteProgressBar), findsNothing);
          final images = find.byType(CommunityWorkspaceImage).evaluate();
          for (final e in images) {
            // Avatar decoding can continue after server loading=false.
            expect(InteractionScope.of(e).reduceMotion, input != 'pointer');
          }
          await activate(t, input, 'menu-announcement-details-close');
          await t.pump();
          await t.pump();
          if (input != 'pointer') expect(r.animation!.value, 0);
          await frames(t);
          expect(find.byType(AlertDialog), findsNothing);
          expect(h.calls, hasLength(1));
        } finally {
          semantics.dispose();
          await t.pumpWidget(const SizedBox());
          await frames(t);
        }
      });
      testWidgets('$suite $input retry uses latest action and availability', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        try {
          final h = await mount(t, suite);
          await activate(t, 'pointer', 'menu-announcement-details-open');
          await frames(t);
          h.change(() {
            h.raw = fixture(failed: true);
            h.action = 'a2';
          });
          await frames(t);
          await t.ensureVisible(
            find.byKey(const Key('announcement-detail-retry')),
          );
          await activate(t, input, 'announcement-detail-retry');
          await t.pump();
          expect(h.calls.last, ('a2', '', origin(input)));
          h.change(() => h.raw = fixture(loading: true));
          await t.pump();
          await t.pump();
          waitScope(t, input != 'pointer');
          h.change(() {
            h.raw = fixture(failed: true);
            h.enabled = false;
          });
          await frames(t);
          final retry = t.widget<StarBridgeActionButton>(
            find.ancestor(
              of: find.byKey(const Key('announcement-detail-retry')),
              matching: find.byType(StarBridgeActionButton),
            ),
          );
          expect(retry.onActivate, isNull);
          expect(h.calls, hasLength(2));
          h.change(() {
            h.action = 'a3';
            h.enabled = true;
          });
          await frames(t);
          await activate(t, input, 'announcement-detail-retry');
          await t.pump();
          expect(h.calls.last, ('a3', '', origin(input)));
        } finally {
          semantics.dispose();
          await t.pumpWidget(const SizedBox());
          await frames(t);
        }
      });
    }
    for (final result in ['success', 'error']) {
      testWidgets('$suite actual hidden session ignores late $result', (
        t,
      ) async {
        final f = PanelFixture();
        try {
          size(t, const Size(1100, 1000));
          await f.ready(t);
          f.port.gate = Completer<Map<String, Object?>>();
          await t.pumpWidget(f.page(suite));
          await frames(t);
          await t.ensureVisible(
            find.byKey(const Key('menu-announcement-details-open')),
          );
          await activate(t, 'pointer', 'menu-announcement-details-open');
          await t.pump();
          await t.pump();
          f.active.value = false;
          f.session.show(false);
          await frames(t);
          expect(find.byType(AlertDialog), findsNothing);
          if (result == 'error') {
            f.port.gate!.completeError(const CommunityFailure('unavailable'));
          } else {
            // Real serialized fake-port result; no invented presentation receipt.
            final producer = AnnouncementsFake();
            final chunk = await producer.readAnnouncementDetail(
              target,
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              0,
              null,
            );
            f.port.gate!.complete(chunk);
            await producer.changes.close();
          }
          await frames(t);
          expect(find.byType(AlertDialog), findsNothing);
          expect(f.port.targets, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          await f.close(t);
        }
      });
    }
    testWidgets('$suite removed main detail ignores late failure', (t) async {
      final port = MainPort()..hold = Completer<void>();
      final model = CommunityAnnouncementsController(port, target);
      try {
        await model.enter();
        await t.pumpWidget(MainHarness(model, suite));
        await frames(t);
        t.state<MainHarnessState>(find.byType(MainHarness)).change(() {
          t.state<MainHarnessState>(find.byType(MainHarness)).visible = false;
        });
        await t.pump();
        port.hold!.completeError(const CommunityFailure('unavailable'));
        await frames(t);
        expect(find.text('removed main detail'), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        if (!port.hold!.isCompleted) port.hold!.complete();
        await t.pumpWidget(const SizedBox());
        await frames(t);
        model.dispose();
        await port.changes.close();
      }
    });
    testWidgets(
      '$suite main late detail failure cannot replace new model content',
      (t) async {
        final old = MainPort()..hold = Completer<void>();
        final next = MainPort();
        next.current!['title'] = 'New detail content';
        final first = CommunityAnnouncementsController(old, target);
        final second = CommunityAnnouncementsController(next, target);
        try {
          await first.enter();
          await second.enter();
          size(t, const Size(1100, 1000));
          await t.pumpWidget(MainHarness(first, suite));
          await frames(t);
          final h = t.state<MainHarnessState>(find.byType(MainHarness));
          h.change(() => h.model = second);
          await frames(t);
          old.hold!.completeError(const CommunityFailure('unavailable'));
          await frames(t);
          expect(find.text('New detail content'), findsOneWidget);
          expect(find.byType(SuiteProgressBar), findsNothing);
          expect(
            find.byKey(const Key('announcement-detail-retry')),
            findsNothing,
          );
          expect(t.takeException(), isNull);
        } finally {
          if (!old.hold!.isCompleted) old.hold!.complete();
          await t.pumpWidget(const SizedBox());
          await frames(t);
          first.dispose();
          second.dispose();
          await old.changes.close();
          await next.changes.close();
        }
      },
    );
    testWidgets('$suite current open guard does not queue duplicates', (
      t,
    ) async {
      final h = await mount(t, suite);
      final button = t.widget<StarBridgeActionButton>(
        find.ancestor(
          of: find.byKey(const Key('menu-announcement-details-open')),
          matching: find.byType(StarBridgeActionButton),
        ),
      );
      button.onActivate!(InteractionSource.pointer);
      button.onActivate!(InteractionSource.pointer);
      await frames(t);
      expect(h.calls, hasLength(1));
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    });
    for (final invalidate in ['remove', 'key', 'inactive']) {
      testWidgets('$suite $invalidate retires only its detail route', (
        t,
      ) async {
        final h = await mount(t, suite);
        await activate(t, 'pointer', 'menu-announcement-details-open');
        await frames(t);
        h.change(() {
          if (invalidate == 'remove') h.visible = false;
          if (invalidate == 'key') h.raw = fixture(key: 'd2');
          if (invalidate == 'inactive') h.active = false;
        });
        await frames(t);
        expect(find.byType(AlertDialog), findsNothing);
        if (invalidate == 'inactive') {
          h.change(() => h.raw = fixture(failed: true));
          await frames(t);
          final button = t.widget<StarBridgeActionButton>(
            find.ancestor(
              of: find.byKey(const Key('menu-announcement-details-open')),
              matching: find.byType(StarBridgeActionButton),
            ),
          );
          expect(button.onActivate, isNull);
        }
        expect(h.calls, hasLength(1));
        await t.pumpWidget(const SizedBox());
        await frames(t);
      });
    }
    testWidgets('$suite Esc finishes exit without clearing detail early', (
      t,
    ) async {
      await mount(t, suite);
      await activate(t, 'pointer', 'menu-announcement-details-open');
      await frames(t);
      final r = route(t);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      await t.pump();
      expect(r.animation!.value, 0);
      await frames(t);
      expect(find.byType(AlertDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$suite local reduce and palette follow within two frames', (
      t,
    ) async {
      final h = await mount(t, suite);
      await activate(t, 'pointer', 'menu-announcement-details-open');
      await t.pump();
      h.change(() {
        h.raw = fixture(loading: true);
        h.localReduce = true;
        h.light = true;
      });
      await t.pump();
      await t.pump();
      waitScope(t, true);
      expect(
        Theme.of(t.element(find.byType(AlertDialog))).brightness,
        Brightness.light,
      );
      final r = route(t);
      expect(r.animation!.value, 1);
      h.change(() => h.localReduce = false);
      await t.pump();
      await t.pump();
      waitScope(t, false);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    });
    testWidgets('$suite same-frame inactive refresh cannot revive detail', (
      t,
    ) async {
      await mount(t, suite);
      await activate(t, 'pointer', 'menu-announcement-details-open');
      await frames(t);
      final element = t.element(
        find.byType(MenuAnnouncementDetailsControl),
      ) as StatefulElement;
      final original = element.widget as MenuAnnouncementDetailsControl;
      MenuAnnouncementDetailsControl inactive(
        MenuAnnouncementDetailsView view,
      ) => MenuAnnouncementDetailsControl(
        view: view,
        action: original.action,
        enabled: original.enabled,
        active: false,
        dispatch: original.dispatch,
      );
      var updated = false;
      t.binding.addPersistentFrameCallback((_) {
        if (updated) return;
        updated = true;
        t.binding.buildOwner!.buildScope(element, () {
          // Real frame phase, two parent updates before post-frame listeners.
          element.update(inactive(original.view));
          element.update(
            inactive(MenuAnnouncementDetailsView.parse(fixture(failed: true))!),
          );
        });
      });
      t.binding.scheduleFrame();
      await t.pump();
      await t.pump();
      expect(find.byType(AlertDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    });
    testWidgets('$suite retirement preserves unrelated top route', (t) async {
      final h = await mount(t, suite);
      await t.tap(find.text('查看详情'));
      await frames(t);
      unawaited(
        h.nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('unrelated route')),
          ),
        ),
      );
      await frames(t);
      h.change(() => h.active = false);
      await frames(t);
      expect(find.text('unrelated route'), findsOneWidget);
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    });
  }
}
