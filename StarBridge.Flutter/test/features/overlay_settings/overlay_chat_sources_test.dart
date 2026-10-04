import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_chat_sources_field.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_sources.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_controller.dart';

import '../friends/social_layout_test.dart' show app, size;

void main() {
  test(
    'v2 compatibility, canonical v3 ordering, immutable selection and transfer',
    () {
      final org = OverlaySourceBinding.community(
        'fixture-org',
        'fixture-owner',
      );
      final values = [org, const OverlaySourceBinding.room()];
      final policy = OverlayPresetSources(chatSources: values);
      values.clear();
      expect(policy.chatSources.first.mode, OverlaySourceMode.room);
      expect(policy.chatSources.length, 2);
      expect(OverlayPresetSources.fromMap(policy.toMap()), policy);
      expect(policy.toMap()['schemaVersion'], 3);
      expect(OverlayPresetSources().toMap()['schemaVersion'], 2);
      expect(() => policy.chatSources.clear(), throwsUnsupportedError);
      expect(
        () => OverlayPresetSources(chatSources: [org, org]),
        throwsFormatException,
      );
      expect(
        () => OverlayPresetSources(
          chatSources: [const OverlaySourceBinding.automatic()],
        ),
        throwsFormatException,
      );
      expect(
        () => OverlayPresetSources(
          chatSources: List.generate(
            9,
            (i) => OverlaySourceBinding.community('org-$i', 'fixture-owner'),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => OverlayPresetSources.fromMap({
          ...policy.toMap(),
          'schemaVersion': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => OverlayPresetSources.fromMap({
          ...policy.toMap(),
          'chatSources': [],
        }),
        throwsFormatException,
      );
      final transferred = policy.forTransfer();
      expect(transferred.chatSources, isEmpty);
      expect(
        transferred.forModule(OverlaySourceModule.chat),
        const OverlaySourceBinding.room(),
      );
      expect(transferred.toMap()['schemaVersion'], 2);
      final onlyOrganizations = OverlayPresetSources(
        modules: {OverlaySourceModule.chat: const OverlaySourceBinding.room()},
        chatSources: [org],
      );
      expect(
        onlyOrganizations.forTransfer().forModule(OverlaySourceModule.chat),
        const OverlaySourceBinding.follow(),
      );
      expect(transferred.autoSwitch, isFalse);
      expect(jsonEncode(transferred.toMap()), isNot(contains('fixture-')));
      expect(
        policy
            .withModule(
              OverlaySourceModule.notice,
              const OverlaySourceBinding.room(),
            )
            .chatSources,
        policy.chatSources,
      );
      expect(
        policy
            .withModule(
              OverlaySourceModule.chat,
              const OverlaySourceBinding.room(),
            )
            .chatSources,
        isEmpty,
      );
    },
  );

  for (final width in [1280.0, 1440.0]) {
    testWidgets(
      'chat source selector supports room and eight selections at $width',
      (tester) async {
        size(tester, Size(width, 900));
        final port = _ScenePort();
        final controller = OverlaySceneController(port, autoStart: false);
        addTearDown(controller.dispose);
        await controller.refresh();
        List<OverlaySourceBinding>? result;
        await tester.pumpWidget(
          app(
            SizedBox(
              width: 320,
              child: OverlayChatSourcesField(
                value: OverlayPresetSources(),
                scenes: controller,
                onChanged: (value) => result = value,
                onSingleChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('overlay-chat-select-sources')));
        await tester.pumpAndSettle();
        for (var i = 0; i < 8; i++) {
          final row = find.byType(CheckboxListTile).at(i);
          await tester.ensureVisible(row);
          await tester.tap(row);
          await tester.pumpAndSettle();
        }
        expect(find.text('已选 8 / 8 个聊天来源'), findsOneWidget);
        expect(
          tester
              .widget<CheckboxListTile>(find.byType(CheckboxListTile).last)
              .onChanged,
          isNull,
        );
        await tester.tap(find.text('应用选择'));
        await tester.pumpAndSettle();
        expect(result!.length, 8);
        expect(
          result!.where((s) => s.mode == OverlaySourceMode.room).length,
          1,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('account generation changes prevent applying an old selection', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final port = _ScenePort();
    final controller = OverlaySceneController(port, autoStart: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    var writes = 0;
    await tester.pumpWidget(
      app(
        OverlayChatSourcesField(
          value: OverlayPresetSources(
            chatSources: [const OverlaySourceBinding.room()],
          ),
          scenes: controller,
          onChanged: (_) => writes++,
          onSingleChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overlay-chat-select-sources')));
    await tester.pumpAndSettle();
    port.generation++;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('账号已更改，请关闭后重新选择。'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '应用选择'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox());
  });
}

class _ScenePort implements OverlayScenePort {
  int generation = 1;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OverlaySceneState> read() async => OverlaySceneState(
    available: true,
    sourceOwnerKey: 'fixture-owner',
    contextGeneration: generation,
    targets: List.generate(
      8,
      (i) => OverlaySceneTarget('org-$i', 'Organization $i'),
    ),
  );
  @override
  Future<OverlaySceneState> select(int revision, String mode, String? code) =>
      read();
  @override
  Future<OverlaySceneState> focusCommunity(String code) => read();
  @override
  void close() {}
}
