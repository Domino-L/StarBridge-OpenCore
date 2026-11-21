import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/overlay_visor_sim_palette.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_event_notification_preview.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_arrange.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_editor_content.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_layout.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_sim_panel.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_rules.dart';

import '../friends/social_layout_test.dart' show app, size;
import 'overlay_visor_layout_test.dart' show defaults, visor;

/// 11-12 user: the editor shows simplified panels with the real content ("编辑里
/// 还是要用模拟面板，只不过信息都一致", "只有框和背景那种，其他都按照真实的来，还要
/// 固定大小"), sample names are plainly samples, and the events may sit anywhere
/// ("我觉得应该允许事件随意调整位置了"), each event keeping its size.
void main() {
  test("the solid plate is the decoration colour's own dark (m102b)", () {
    // 11-18 user: "保持主题色不脏" — a warm theme keeps its hue at a high
    // background opacity; the default blue stays near the old dark plate
    const drake = Color(0xFFFFB230);
    final warm = OverlayVisorSimPalette.plate(drake);
    final warmHsv = HSVColor.fromColor(warm);
    final drakeHsv = HSVColor.fromColor(drake);
    expect(warm.a, 1);
    expect((warmHsv.hue - drakeHsv.hue).abs(), lessThan(1));
    // (the plate is stored in 8 bits a channel, so its saturation is only near)
    expect((warmHsv.saturation - drakeHsv.saturation).abs(), lessThan(0.03));
    expect(warmHsv.value, closeTo(OverlayVisorSimPalette.plateShade, 0.001));
    final blue = OverlayVisorSimPalette.plate(
      OverlayVisorSimPalette.defaultDecoration,
    );
    expect(blue.r, closeTo(0.02, 0.015));
    expect(blue.g, closeTo(0.035, 0.04));
    expect(blue.b, closeTo(0.05, 0.045));
  });

  Map<String, Object?> wire({bool sample = false, String colour = '#FFB230'}) =>
      {
        'schemaVersion': 1,
        'sample': sample,
        'decoration': colour,
        'members': {
          'title': '组织成员',
          'youAt': '美服 #001',
          'online': 2,
          'inGame': 1,
          'sameServer': 1,
          'page': '',
          'counts': ['在线', '游戏中', '同服'],
          'rows': [
            {
              'name': 'Pilot',
              'ship': '黑弯刀',
              'place': '奥里森',
              'status': '',
              'state': 'InGame',
              'sameServer': true,
              'pinned': false,
              'vitals': 'Alive',
              'health': 0.6,
            },
            {
              'name': 'Wing',
              'ship': '',
              'place': '',
              'status': '应用在线',
              'state': 'AppOnly',
              'sameServer': false,
              'pinned': false,
              'vitals': 'Unknown',
              'health': 0,
            },
          ],
        },
        'events': {
          'title': '事件',
          'sample': sample,
          'rows': [
            {
              'title': '换服',
              'detail': 'Pilot 换到 欧服',
              'time': '20:41',
              'tone': 'Server',
            },
          ],
        },
        'chat': {
          'title': '组织聊天',
          'sample': true,
          'rows': [
            {'who': '示例队员 01', 'text': '收到'},
          ],
        },
      };

  group('content from the Host', () {
    test('reads members, events, chat and the decoration colour', () {
      final content = OverlayVisorEditorContent.fromMap(wire());
      expect(content.sample, isFalse);
      expect(content.decoration, const Color(0xFFFFB230));
      expect(content.members.map((m) => m.name), ['Pilot', 'Wing']);
      expect(content.members.first.health, 0.6);
      expect(content.events.single.tone, 'Server');
      expect(content.chatSample, isTrue);
      expect(content.chat.single.who, '示例队员 01');
    });

    test('a malformed reply is refused', () {
      for (final bad in [
        {...wire(), 'schemaVersion': 2},
        {...wire(), 'decoration': 'orange'},
        {...wire(), 'members': 'none'},
        {...wire(), 'sample': 'yes'},
        // unknown states, colours, wrong types and out-of-range health
        _row(wire(), 'state', 'Flying'),
        _row(wire(), 'vitals', 'Fine'),
        _row(wire(), 'sameServer', 'no'),
        _row(wire(), 'health', 1.5),
        {
          ...wire(),
          'events': {
            'title': '事件',
            'sample': false,
            'rows': [
              {'title': 'x', 'detail': 'y', 'time': 'z', 'tone': 'Purple'},
            ],
          },
        },
      ]) {
        expect(
          () => OverlayVisorEditorContent.fromMap(bad),
          throwsFormatException,
        );
      }
    });

    test('the samples are plainly samples', () {
      final content = overlayVisorSampleContent(
        (key) => key == 'overlay.sample.visorMember' ? '示例队员' : key,
      );
      expect(content.sample, isTrue);
      expect(content.members.map((m) => m.name), [
        for (var i = 1; i <= 6; i++) '示例队员 0$i',
      ]);
      expect(content.chat.every((c) => c.who.startsWith('示例队员 ')), isTrue);
    });
  });

  group('the content source', () {
    testWidgets('one request at a time; a failure keeps what is shown', (
      tester,
    ) async {
      final port = _Port();
      final source = OverlayVisorEditorContentSource(
        port: port,
        language: () => 'zh-CN',
        draft: () => null,
        debounce: const Duration(milliseconds: 300),
        refresh: const Duration(seconds: 10),
      );
      var notified = 0;
      source.addListener(() => notified++);
      source.sync('a');
      await tester.pump(Duration.zero);
      expect(port.pending, hasLength(1));
      source.sync('b');
      await tester.pump(const Duration(milliseconds: 400));
      expect(port.pending, hasLength(1), reason: 'never two at once');
      port.pending
          .removeAt(0)
          .complete(OverlayVisorEditorContent.fromMap(wire()));
      await tester.pump();
      expect(source.content?.members.first.name, 'Pilot');
      expect(notified, 1);
      // the change while it ran is asked for once it returns
      expect(port.pending, hasLength(1));
      port.pending.removeAt(0).completeError(StateError('down'));
      await tester.pump();
      expect(source.content?.members.first.name, 'Pilot', reason: 'kept');
      // the periodic refresh asks again for live members
      await tester.pump(const Duration(seconds: 10));
      expect(port.pending, hasLength(1));
      port.pending
          .removeAt(0)
          .complete(OverlayVisorEditorContent.fromMap(wire(colour: '#53BEFF')));
      await tester.pump();
      expect(source.content?.decoration, const Color(0xFF53BEFF));
      source.dispose();
    });
  });

  group('the simplified panels', () {
    const surface = Size(1920, 1080);
    for (final block in ['team', 'events', 'chat']) {
      testWidgets('$block: frame, background and the visor layout', (
        tester,
      ) async {
        size(tester, surface);
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: 260,
                height: 300,
                child: OverlayVisorSimPanel(
                  block: block,
                  content: OverlayVisorEditorContent.fromMap(
                    wire(sample: true),
                  ),
                  settings: visor(),
                  right: block != 'chat',
                  sampleLabel: '示例数据',
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final painter =
            tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byType(OverlayVisorSimPanel),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .painter!
                as OverlayVisorSimPainter;
        // drawn by the block's width setting alone: text never grows on its own
        expect(painter.designWidth, 364);
        // samples (members, events and chat each flagged) say so
        expect(painter.sampleLabel, '示例数据');
      });
    }

    test('status colours stay fixed; event titles by kind', () {
      expect(OverlayVisorSimColors.tone('Bad'), OverlayVisorSimColors.bad);
      expect(
        OverlayVisorSimColors.tone('Server'),
        OverlayVisorSimColors.server,
      );
      expect(
        OverlayVisorSimColors.tone('SameServer'),
        OverlayVisorSimColors.ok,
      );
      expect(
        OverlayVisorSimColors.tone('anything'),
        OverlayVisorSimColors.accent,
      );
    });
  });

  group('events anywhere', () {
    const surface = Size(1920, 1080);

    test('a place across moves the events off the edge, by their side', () {
      final at = visor().withValue('visorEventsX', 0.5);
      final box = OverlayVisorArrange.all(defaults(), at, surface)['Events']!;
      // right side: the box's right edge at half the screen (layout units)
      expect(box.right, closeTo(1920 * 0.5, 1));
      final left = visor(side: 'Left', y: 0.5).withValue('visorEventsX', 0.2);
      final leftBox = OverlayVisorArrange.all(
        defaults(),
        left,
        surface,
      )['Events']!;
      expect(leftBox.left, closeTo(1920 * 0.2, 1));
      expect(OverlayVisorLayout.eventsX(visor()), isNull, reason: 'unset');
    });

    test('choosing the side from the list takes them back to that edge', () {
      final at = visor().withValue('visorEventsX', 0.5);
      final next = applyOverlayWorkspaceSettingChange(
        at,
        'eventNotificationSide',
        'Left',
      );
      expect(next['visorEventsX'], -1.0);
    });

    testWidgets('a drag to the middle saves a place across and the side', (
      tester,
    ) async {
      size(tester, surface);
      final saved = <(String, double, double?)>[];
      final settings = visor().withValue('visorTilt', 0.0);
      final rect = OverlayVisorLayout.eventsPlacement(
        defaults(),
        settings,
        surface,
      )!;
      await tester.pumpWidget(
        app(
          SizedBox.fromSize(
            size: surface,
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: OverlayEventNotificationPreview(
                    settings: settings,
                    eventRect: rect,
                    visorPlacement: true,
                    surfaceSize: surface,
                    scaleX: 1,
                    scaleY: 1,
                    snapPixels: 0,
                    smartSnap: false,
                    simulate: true,
                    onPlacementChanged: (side, y, {x}) =>
                        saved.add((side, y, x)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveBy(Offset(-(rect.center.dx - 700), 200));
      await gesture.up();
      await tester.pump();
      final (side, y, x) = saved.last;
      expect(side, 'Left', reason: 'its centre crossed the middle');
      expect(x, isNotNull);
      expect(x!, inExclusiveRange(0.2, 0.5));
      expect(y, greaterThan(0.34));
      // each event keeps its size: the box is the same size wherever it goes
      final moved = OverlayVisorLayout.eventsPlacement(
        defaults(),
        settings
            .withValue('eventNotificationSide', side)
            .withValue('eventNotificationY', y)
            .withValue('visorEventsX', x),
        surface,
      )!;
      expect(moved.size, rect.size);
      expect(tester.takeException(), isNull);
    });
  });
}

final class _Port implements OverlayVisorEditorContentPort {
  final pending = <Completer<OverlayVisorEditorContent>>[];

  @override
  bool get supportsVisorEditorContent => true;

  @override
  Future<OverlayVisorEditorContent> readVisorEditorContent({
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) {
    final completer = Completer<OverlayVisorEditorContent>();
    pending.add(completer);
    return completer.future;
  }
}

/// [body] with one field of the first member row replaced.
Map<String, Object?> _row(
  Map<String, Object?> body,
  String field,
  Object? value,
) {
  final members = Map<String, Object?>.from(body['members']! as Map);
  final rows = [
    for (final row in members['rows']! as List)
      Map<String, Object?>.from(row as Map),
  ];
  rows.first[field] = value;
  members['rows'] = rows;
  return {...body, 'members': members};
}
