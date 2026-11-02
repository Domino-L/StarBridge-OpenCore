import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog_surface.dart';
import 'package:starbridge_flutter/features/settings/application_support_models.dart';
import 'package:starbridge_flutter/features/settings/application_support_module.dart';
import 'package:starbridge_flutter/features/settings/application_support_motion.dart';
import 'package:starbridge_flutter/features/settings/application_support_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3df_test.dart' show SupportPort, supportSnapshot;
import 'interaction_batch3cz_actions_test.dart' show fire;
import 'interaction_batch3i_test.dart' show scopedApp;

class SupportFixture {
  final port = SupportPort();
  late final owner = createApplicationSupportModule(port);
  Widget page(InteractionSuite suite, {bool reduce = false}) =>
      scopedApp(ApplicationSupportPanel(module: owner), suite, reduce: reduce);
  Future<void> mount(WidgetTester t, InteractionSuite suite) async {
    size(t, const Size(1400, 1100));
    await t.pumpWidget(page(suite));
    await t.pumpAndSettle();
    await fire(t, 'pointer', 'diagnostics-run');
    await t.pumpAndSettle();
    expect(port.inspections, 1);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    owner.dispose();
  }
}

ApplicationSupportMotionState readMotion(WidgetTester t) =>
    t.state(find.byType(ApplicationSupportMotion));
Future<void> frames(WidgetTester t) async {
  await t.pump();
  await t.pump();
  await t.pump(const Duration(milliseconds: 160));
}

void expectBusy(WidgetTester t) {
  for (final id in [
    'application-support-open-data-directory',
    'application-support-copy',
    'application-support-refresh',
  ]) {
    final button = find.ancestor(
      of: find.byKey(Key(id)),
      matching: find.byType(StarBridgeActionButton),
    );
    expect(t.widget<StarBridgeActionButton>(button).onActivate, isNull);
  }
}

const summary =
    'StarBridge · 诊断与维护\n本地数据：正常 · 数据目录可以正常写入。\n游戏日志：正常 · Game.log 存在且可以读取。\n开机启动：正常 · 当前未启用开机启动。\n安装状态：正常 · 当前正式安装状态正常。';

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final result in ['ready', 'partial', 'timeout', 'invalid']) {
        testWidgets(
          '$suite $input refresh $result keeps real receipt and source',
          (t) async {
            final h = SupportFixture();
            final sem = t.ensureSemantics();
            try {
              await h.mount(t, suite);
              h.port.delayed = true;
              await fire(t, input, 'application-support-refresh');
              await frames(t);
              expect(h.port.inspections, 2);
              expect(
                h.owner.projection.value.snapshot,
                isNull,
              ); // Original loading clears ready content.
              expect(h.owner.projection.value.loading, isTrue);
              expect(
                readMotion(t).source,
                input == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(
                find.byType(SuiteProgressBar),
                input == 'pointer' ? findsOneWidget : findsNothing,
              );
              if (input == 'pointer') {
                expect(
                  t.getSize(find.byType(SuiteProgressBar)).width,
                  greaterThan(100),
                );
              }
              expect(
                find.byKey(const Key('application-support-ready')),
                findsNothing,
              );
              if (result == 'timeout' || result == 'invalid') {
                h.port.pending.single.completeError(
                  result == 'timeout'
                      ? const ApplicationSupportException(
                          ApplicationSupportFailure.timeout,
                        )
                      : StateError('synthetic malformed receipt'),
                );
              } else {
                h.port.pending.single.complete(
                  result == 'ready'
                      ? supportSnapshot
                      : ApplicationSupportSnapshot(
                          hasIssues: false,
                          hasUnavailableChecks: true,
                          dataDirectory: const ApplicationSupportCheck(
                            state: ApplicationSupportCheckState.unavailable,
                            detail: 'readFailed',
                          ),
                          gameLog: supportSnapshot.gameLog,
                          startup: supportSnapshot.startup,
                          installation: supportSnapshot.installation,
                        ),
                );
              }
              await t.pumpAndSettle();
              if (result == 'timeout' || result == 'invalid') {
                expect(h.owner.projection.value.snapshot, isNull);
                expect(
                  h.owner.projection.value.failure,
                  result == 'timeout'
                      ? ApplicationSupportFailure.timeout
                      : ApplicationSupportFailure.invalidResponse,
                );
                await fire(t, input, 'application-support-retry');
                await frames(t);
                expect(h.port.inspections, 3);
                expect(
                  readMotion(t).source,
                  input == 'pointer'
                      ? InteractionSource.pointer
                      : InteractionSource.keyboard,
                );
                h.port.pending.last.complete(supportSnapshot);
                await t.pumpAndSettle();
              } else if (result == 'partial') {
                expect(find.text('部分项目暂时无法检查'), findsOneWidget);
                expect(find.text('当前检查项目均正常'), findsNothing);
              }
              expect(
                find.byKey(const Key('application-support-ready')),
                findsOneWidget,
              );
              expect(find.byType(ApplicationSupportWaiting), findsNothing);
              expect(h.port.opens, 0);
              expect(t.takeException(), isNull);
            } finally {
              sem.dispose();
              await h.close(t);
            }
          },
        );
      }
      for (final result in ['completed', 'failed', 'unavailable']) {
        testWidgets(
          '$suite $input directory $result preserves busy and original result message',
          (t) async {
            final h = SupportFixture();
            final sem = t.ensureSemantics();
            try {
              await h.mount(t, suite);
              h.port.open = Completer<void>();
              await fire(t, input, 'application-support-open-data-directory');
              await frames(t);
              expect(h.port.opens, 1);
              expectBusy(t);
              expect(find.text('已打开数据目录'), findsNothing);
              if (result == 'completed') {
                h.port.open!.complete();
              } else {
                h.port.open!.completeError(
                  result == 'unavailable'
                      ? const ApplicationSupportException(
                          ApplicationSupportFailure.hostUnavailable,
                        )
                      : StateError('synthetic directory failure'),
                );
              }
              await t.pumpAndSettle();
              expect(h.port.opens, 1);
              expect(h.port.inspections, 1);
              expect(
                find.text(switch (result) {
                  'completed' => '已打开数据目录',
                  'unavailable' => '后台服务暂时不可用，请稍后重试。',
                  _ => '未能打开数据目录，请稍后重试。',
                }),
                findsOneWidget,
              );
              final surface = find.byType(StarBridgeMeasuredSurface);
              expect(surface, findsOneWidget);
              if (input != 'pointer') {
                expect(
                  t.widget<StarBridgeMeasuredSurface>(surface).animation.value,
                  1,
                );
              }
              expect(t.takeException(), isNull);
            } finally {
              sem.dispose();
              await h.close(t);
            }
          },
        );
      }
      for (final fail in [false, true]) {
        testWidgets(
          '$suite $input clipboard fail=$fail keeps exact safe summary and busy until platform receipt',
          (t) async {
            final h = SupportFixture();
            final sem = t.ensureSemantics();
            final pending = Completer<void>();
            final copied = <String>[];
            t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              (call) async {
                if (call.method == 'Clipboard.setData') {
                  copied.add((call.arguments as Map)['text'] as String);
                  await pending.future;
                }
                return null;
              },
            );
            try {
              await h.mount(t, suite);
              await fire(t, input, 'application-support-copy');
              await frames(t);
              expect(copied, [summary]);
              expectBusy(t);
              expect(find.text('诊断摘要已复制'), findsNothing);
              if (fail) {
                pending.completeError(
                  PlatformException(code: 'synthetic unavailable'),
                );
              } else {
                pending.complete();
              }
              await t.pumpAndSettle();
              expect(find.text(fail ? '未能复制，请重试。' : '诊断摘要已复制'), findsOneWidget);
              expect(copied, hasLength(1));
              expect(h.port.opens, 0);
              expect(t.takeException(), isNull);
            } finally {
              sem.dispose();
              await h.close(t);
              t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                SystemChannels.platform,
                null,
              );
            }
          },
        );
      }
    }
  }
}
