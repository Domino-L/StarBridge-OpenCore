import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/application_support_module.dart';
import 'package:starbridge_flutter/features/settings/application_support_models.dart';
import 'package:starbridge_flutter/features/settings/diagnostics_maintenance_panel.dart';
import 'package:starbridge_flutter/features/settings/flutter_installation_panel.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/maintenance_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

// Match the existing real-theme fixture, without importing unrelated feature
// test libraries. Full settings/application consumers run separately as well.
Widget scopedApp(
  Widget child,
  InteractionSuite suite, {
  bool light = false,
  bool reduce = false,
  Locale locale = const Locale('zh', 'CN'),
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  supportedLocales: AppStrings.runtimeSupportedLocales(),
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  themeAnimationDuration: Duration.zero,
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(
      light ? AppearanceMode.light : AppearanceMode.dark,
    ).withReducedMotion(reduce),
    locale,
    interactionSuite: suite,
  ),
  builder: (context, child) => StarBridgeInteractionConfiguration(
    suite: suite,
    reduceMotion: reduce,
    child: child!,
  ),
  home: Scaffold(body: Center(child: child)),
);
void size(WidgetTester t, Size value) {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = value;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> loadFonts() async {
  for (final font in {
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
    'Saira': 'assets/fonts/Saira-VF.ttf',
    'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
    'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
  }.entries) {
    await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
  }
}

List<SemanticsNode> exposedNodes(WidgetTester t) {
  final result = <SemanticsNode>[];
  void visit(SemanticsNode n) {
    if (n.isMergedIntoParent) return;
    result.add(n);
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(t.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!);
  return result;
}

Future<void> act(
  WidgetTester t,
  Finder target,
  String source,
  String label,
) async {
  await t.ensureVisible(target);
  if (source == 'pointer') {
    await t.tap(target);
    return;
  }
  if (source == 'reader') {
    final nodes = exposedNodes(t)
        .where(
          (n) =>
              n.getSemanticsData().label == label &&
              n.getSemanticsData().hasAction(SemanticsAction.tap),
        )
        .toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      SemanticsAction.tap,
    );
    return;
  }
  var owned = find.descendant(
    of: target,
    matching: find.byWidgetPredicate(
      (w) => w is ButtonStyleButton || w is SuitePressable,
    ),
  );
  if (t.widget(target) is ButtonStyleButton ||
      t.widget(target) is SuitePressable) {
    owned = target;
  }
  final widget = t.widget(owned.first);
  final focus = switch (widget) {
    ButtonStyleButton b => b.focusNode!,
    SuitePressable b =>
      b.focusNode ??
          t
              .widget<FocusableActionDetector>(
                find
                    .descendant(
                      of: owned.first,
                      matching: find.byType(FocusableActionDetector),
                    )
                    .first,
              )
              .focusNode!,
    _ => throw StateError('Missing focus'),
  };
  focus.requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
}

class BridgeFixture {
  BridgeFixture({List<String>? capabilities}) {
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 1)
      ..acceptHostCapabilities(
        capabilities ??
            [
              'diagnostics.flutterInstallation',
              'diagnostics.openDataDirectory',
              'diagnostics.clearImageCache',
            ],
      );
    subscription = host.incoming.listen(requests.add);
  }
  late final BridgeConnection host;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  Future<void> reply(
    int index,
    Map<String, dynamic> payload, {
    String status = 'ok',
  }) => host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: requests[index].name,
      correlationId: requests[index].correlationId,
      sessionGeneration: 1,
      status: status,
      payload: payload,
    ),
  );
  Map<String, dynamic> plan({String mode = 'installed', bool clean = false}) =>
      {
        'schemaVersion': 1,
        'ticket': 'synthetic-ticket',
        'mode': mode,
        'directory': mode == 'portable' ? '' : r'C:\Synthetic\StarBridge',
        'canUninstall': mode == 'installed',
        'canClean': clean,
      };
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await host.close();
  }
}

class SupportFixture implements ApplicationSupportModule {
  @override
  final ValueNotifier<ApplicationSupportProjection> projection = ValueNotifier(
    const ApplicationSupportProjection.loading(),
  );
  final opening = Completer<ApplicationSupportActionResult>();
  int opens = 0, reads = 0;
  @override
  Future<void> initialize() async {
    reads++;
  }

  @override
  Future<void> refresh() async {
    reads++;
  }

  @override
  Future<ApplicationSupportActionResult> openDataDirectory() {
    opens++;
    return opening.future;
  }

  @override
  void dispose() {
    projection.dispose();
  }
}

Future<void> invoke(WidgetTester t, String key, String label, String source) =>
    act(t, find.byKey(Key(key)), source, label);
void waiting(WidgetTester t, String source) {
  final w = find.byType(HelpSupportWaiting);
  expect(w, findsOneWidget);
  expect(
    t.widget<HelpSupportWaiting>(w).source,
    source == 'pointer'
        ? InteractionSource.pointer
        : InteractionSource.keyboard,
  );
  expect(
    find.byType(SuiteProgressBar),
    source == 'pointer' ? findsOneWidget : findsNothing,
  );
}

ButtonStyleButton template(WidgetTester t, String key) => t
    .widgetList<MaintenanceAction>(find.byType(MaintenanceAction))
    .singleWhere((w) => w.button.key == Key(key))
    .button;
Future<void> scanReady(
  WidgetTester t,
  BridgeFixture fixture, {
  String source = 'pointer',
  String mode = 'installed',
  bool clean = false,
}) async {
  final index = fixture.requests.length;
  await invoke(t, 'flutter-installation-scan', '检查安装状态', source);
  await t.pump();
  await fixture.reply(index, fixture.plan(mode: mode, clean: clean));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source scan refusal preserves explicit retry and no-op guards',
        (t) async {
          final semantics = t.ensureSemantics();
          final fixture = BridgeFixture();
          addTearDown(fixture.close);
          try {
            size(t, const Size(900, 700));
            await t.pumpWidget(
              scopedApp(
                FlutterInstallationPanel(session: fixture.session),
                suite,
              ),
            );
            await t.pumpAndSettle();
            final old = template(t, 'flutter-installation-scan').onPressed!;
            await invoke(t, 'flutter-installation-scan', '检查安装状态', source);
            await t.pump(const Duration(milliseconds: 100));
            waiting(t, source);
            final phase = t.widget(find.byType(HelpSupportWaiting)).key;
            await runStarBridgeActivation<void>(InteractionSource.pointer, old);
            await t.pump(const Duration(milliseconds: 100));
            expect(fixture.requests, hasLength(1));
            expect(t.widget(find.byType(HelpSupportWaiting)).key, phase);
            expect(template(t, 'flutter-installation-scan').onPressed, isNull);
            await fixture.reply(0, {'schemaVersion': 2});
            await t.pumpAndSettle();
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(
              find.byKey(const Key('flutter-installation-uninstall')),
              findsNothing,
            );
            expect(find.textContaining('操作未确认完成'), findsOneWidget);
            await scanReady(t, fixture, source: source, mode: 'portable');
            expect(fixture.requests, hasLength(2));
            expect(
              find.byKey(const Key('flutter-installation-clean')),
              findsNothing,
            );
            expect(find.text('未发现需要清理的安装残留。'), findsOneWidget);
            await t.pumpWidget(const SizedBox());
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source installation cancel and confirmed source preserve exact ticket and refusal',
        (t) async {
          final semantics = t.ensureSemantics();
          final fixture = BridgeFixture();
          addTearDown(fixture.close);
          try {
            size(t, const Size(900, 700));
            await t.pumpWidget(
              scopedApp(
                FlutterInstallationPanel(session: fixture.session),
                suite,
              ),
            );
            await t.pumpAndSettle();
            final uninstall = source == 'pointer';
            final operation = uninstall ? 'uninstall' : 'clean',
                label = uninstall ? '卸载客户端' : '清理安装残留';
            await scanReady(
              t,
              fixture,
              source: source,
              mode: uninstall ? 'installed' : 'orphaned',
              clean: !uninstall,
            );
            final old = template(
              t,
              'flutter-installation-$operation',
            ).onPressed!;
            await invoke(t, 'flutter-installation-$operation', label, source);
            await t.pumpAndSettle();
            expect(
              ModalRoute.of(t.element(find.byType(AlertDialog)))
                  is StarBridgeDialogRoute,
              isTrue,
            );
            expect(
              (ModalRoute.of(
                t.element(find.byType(AlertDialog)),
              ) as StarBridgeDialogRoute).instant,
              source != 'pointer',
            );
            expect(find.byType(HelpSupportWaiting), findsNothing);
            await runStarBridgeActivation<void>(InteractionSource.pointer, old);
            await t.pump();
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(fixture.requests, hasLength(1));
            await invoke(t, 'installation-confirm-cancel', '保留', source);
            await t.pumpAndSettle();
            expect(fixture.requests, hasLength(1));
            expect(
              find.byKey(Key('flutter-installation-$operation')),
              findsOneWidget,
            );
            await invoke(t, 'flutter-installation-$operation', label, source);
            await t.pumpAndSettle();
            final confirmation = source == 'pointer'
                ? 'keyboard'
                : source == 'keyboard'
                ? 'pointer'
                : 'reader';
            await invoke(
              t,
              'installation-confirm-execute',
              label,
              confirmation,
            );
            await t.pump(const Duration(milliseconds: 350));
            waiting(t, confirmation);
            expect(fixture.requests, hasLength(2));
            expect(
              fixture.requests.last.name,
              'diagnostics.flutterInstallationExecute',
            );
            expect(fixture.requests.last.payload, {
              'schemaVersion': 1,
              'ticket': 'synthetic-ticket',
              'action': operation,
            });
            expect(fixture.requests.last.accountContext, isNull);
            expect(find.text('卸载向导已启动，请在向导中继续。'), findsNothing);
            await fixture.reply(1, {'schemaVersion': 1, 'completed': false});
            await t.pumpAndSettle();
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(find.textContaining('操作未确认完成'), findsOneWidget);
            expect(
              find.byKey(Key('flutter-installation-$operation')),
              findsNothing,
            );
            expect(fixture.requests, hasLength(2));
            await t.pumpWidget(const SizedBox());
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source cleanup confirms before request and preserves zero-count and failure semantics',
        (t) async {
          final semantics = t.ensureSemantics();
          final fixture = BridgeFixture();
          final support = SupportFixture();
          addTearDown(fixture.close);
          addTearDown(support.dispose);
          try {
            size(t, const Size(900, 700));
            await t.pumpWidget(
              scopedApp(
                DiagnosticsMaintenancePanel(
                  support: support,
                  session: fixture.session,
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            final old = template(t, 'maintenance-clear-cache').onPressed!;
            await invoke(t, 'maintenance-clear-cache', '清理图片缓存', source);
            await t.pumpAndSettle();
            expect(fixture.requests, isEmpty);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(fixture.requests, isEmpty);
            await invoke(t, 'maintenance-clear-cache', '清理图片缓存', source);
            await t.pumpAndSettle();
            final confirmation = source == 'pointer'
                ? 'keyboard'
                : source == 'keyboard'
                ? 'pointer'
                : 'reader';
            await invoke(
              t,
              'maintenance-confirm-execute',
              '清理图片缓存',
              confirmation,
            );
            await t.pump(const Duration(milliseconds: 350));
            waiting(t, confirmation);
            await runStarBridgeActivation<void>(InteractionSource.pointer, old);
            await t.pump();
            expect(fixture.requests, hasLength(1));
            expect(fixture.requests.single.name, 'diagnostics.clearImageCache');
            expect(fixture.requests.single.payload, {'schemaVersion': 1});
            expect(support.opens, 0);
            expect(support.reads, 0);
            await fixture.reply(0, {'schemaVersion': 1, 'count': 0});
            await t.pumpAndSettle();
            expect(find.textContaining('已清理可重新下载'), findsOneWidget);
            await invoke(t, 'maintenance-clear-cache', '清理图片缓存', source);
            await t.pumpAndSettle();
            await invoke(
              t,
              'maintenance-confirm-execute',
              '清理图片缓存',
              confirmation,
            );
            await t.pump(const Duration(milliseconds: 350));
            expect(
              find.textContaining('已清理可重新下载'),
              findsOneWidget,
              reason: 'original previous result is not erased during the next pending operation',
            );
            await fixture.reply(1, {'schemaVersion': 1, 'count': -1});
            await t.pumpAndSettle();
            expect(find.textContaining('操作未确认完成'), findsOneWidget);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(fixture.requests, hasLength(2));
            await t.pumpWidget(const SizedBox());
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source data folder uses only original support owner and real acknowledgement',
        (t) async {
          final semantics = t.ensureSemantics();
          final fixture = BridgeFixture();
          final support = SupportFixture();
          addTearDown(fixture.close);
          addTearDown(support.dispose);
          try {
            size(t, const Size(900, 700));
            await t.pumpWidget(
              scopedApp(
                DiagnosticsMaintenancePanel(
                  support: support,
                  session: fixture.session,
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            final old = template(t, 'maintenance-open-folder').onPressed!;
            await invoke(t, 'maintenance-open-folder', '打开数据目录', source);
            await t.pump(const Duration(milliseconds: 100));
            waiting(t, source);
            await runStarBridgeActivation<void>(InteractionSource.pointer, old);
            await t.pump();
            expect(support.opens, 1);
            expect(fixture.requests, isEmpty);
            expect(find.text('已打开。'), findsNothing);
            support.opening.complete(
              source == 'pointer'
                  ? ApplicationSupportActionResult.completed
                  : ApplicationSupportActionResult.failed,
            );
            await t.pumpAndSettle();
            expect(
              find.text(
                source == 'pointer' ? '已打开。' : '操作未确认完成，请检查后重试。不会自动重复执行。',
              ),
              findsOneWidget,
            );
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(support.reads, 0);
            await t.pumpWidget(const SizedBox());
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite explicit scan pending uses approved waiting and never executes maintenance',
      (t) async {
        size(t, const Size(900, 700));
        final fixture = BridgeFixture();
        addTearDown(fixture.close);
        await t.pumpWidget(
          scopedApp(FlutterInstallationPanel(session: fixture.session), suite),
        );
        await t.pumpAndSettle();
        expect(fixture.requests, isEmpty);
        await t.tap(find.byKey(const Key('flutter-installation-scan')));
        await t.pump(const Duration(milliseconds: 100));
        waiting(t, 'pointer');
        expect(fixture.requests.single.name, 'diagnostics.flutterInstallation');
        expect(fixture.requests.single.payload, {'schemaVersion': 1});
        await fixture.reply(0, fixture.plan());
        await t.pumpAndSettle();
        expect(find.byType(HelpSupportWaiting), findsNothing);
        expect(fixture.requests, hasLength(1));
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
  }
}
