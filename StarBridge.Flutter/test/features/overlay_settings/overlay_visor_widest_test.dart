import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_editor_content.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_sim_panel.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_members_size.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_layout.dart';

import 'overlay_visor_layout_test.dart' show visor;

const _cn = Locale('zh', 'CN');

OverlayVisorEditorContent _content({bool sample = true, int count = 2}) =>
    OverlayVisorEditorContent(
      sample: sample,
      decoration: Colors.teal,
      membersTitle: 'Team',
      youAt: '',
      online: 7,
      inGame: 5,
      sameServer: 2,
      page: '',
      countLabels: const ['Online', 'In game', 'Same server'],
      members: [
        for (var i = 0; i < count; i++)
          OverlayVisorEditorMember(
            name: 'P$i',
            ship: 'S',
            place: 'L',
            status: '',
            state: 'InGame',
            sameServer: false,
            pinned: false,
          ),
      ],
      eventsTitle: '',
      events: const [],
      chatTitle: '',
      chatSample: true,
      chat: const [],
    );

OverlayVisorSimPainter _paint({
  bool? adaptive,
  bool sample = true,
  int count = 2,
  double width = 364,
  double height = 400,
  double scale = 1,
  bool right = false,
  Locale locale = _cn,
}) {
  var settings = visor().withValue('visorMembersWidth', width);
  // the shared fixture has adaptive width off; null means the product default (on)
  settings = settings.withValue('visorMembersAutoWidth', adaptive ?? true);
  final painter = OverlayVisorSimPainter(
    block: 'team',
    content: _content(sample: sample, count: count),
    settings: settings,
    right: right,
    locale: locale,
    textOpacity: 1,
    backgroundOpacity: 1,
    decorationOpacity: 1,
  );
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Size(width * scale, height * scale));
  recorder.endRecording().dispose();
  return painter;
}

List<String> _names(OverlayVisorSimPainter painter) => [
  // Header/counts precede y=51; each member emits name, ship, place.
  for (final field in painter.debugPaintedFields)
    if (field.y >= 48 &&
        (field.text.startsWith('P') ||
            field.text ==
                AppStrings.resolve(painter.locale)
                    .text('overlay.sample.visorWidestMember')))
      field.text,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adaptive short samples paint widest row last at maximum width', () {
    for (final adaptive in [null, true]) {
      for (final width in [220.0, 364.0, 480.0]) {
        for (final right in [false, true]) {
          final painter = _paint(
            adaptive: adaptive,
            width: width,
            right: right,
            scale: 0.75,
          );
          expect(_names(painter), ['P0', 'P1', '模拟成员']);
          expect(painter.debugPaintedWidth, closeTo(width * 0.75, 1));
          final fields = painter.debugPaintedFields;
          expect(fields[fields.length - 2].clip, isNotNull);
          expect(fields.last.clip, isNotNull);
          expect(fields.last.text, startsWith('模拟地点'));
        }
      }
    }
  });

  test('fixed width paints original rows without widest sample', () {
    final painter = _paint(adaptive: false);
    expect(_names(painter), ['P0', 'P1']);
    expect(painter.debugPaintedWidth, 364);
    expect(painter.debugPaintedFields.last.text, 'L');
  });

  test('full real member box replaces last row and keeps three rows', () {
    final painter = _paint(sample: false, count: 3, height: 179);
    expect(_names(painter), ['P0', 'P1', '模拟成员']);
    expect(
      painter.debugPaintedFields.map((f) => f.text),
      isNot(contains('P2')),
    );
    expect(painter.debugPaintedFields.last.y, lessThan(179));
  });

  test('widest sample preserves painted online in-game same-server counts', () {
    for (final sample in [false, true]) {
      final before = _paint(adaptive: false, sample: sample);
      final after = _paint(adaptive: true, sample: sample);
      List<String> counts(OverlayVisorSimPainter p) => [
        for (final f in p.debugPaintedFields)
          if (f.y == 20) f.text,
      ];
      expect(counts(before), ['7', '5', '2']);
      expect(counts(after), counts(before));
    }
  });

  test('widest row capacity clamps to one and twenty', () {
    expect(OverlayMembersSize.height.maximum, 874);
    expect(OverlayMembersSize.height.divisions, 683);
    expect(OverlayMembersSize.rows(554), 12);
    expect(OverlayMembersSize.rows(874), 20);
    expect(OverlayMembersSize.rows(OverlayMembersSize.stepHeight(554, 1)), 13);
    expect(OverlayMembersSize.rows(OverlayMembersSize.stepHeight(555, -1)), 12);
    expect(OverlayMembersSize.stepHeight(874, 1), 874);
    expect(
      OverlayVisorLayout.membersHeight(
        visor().withValue('visorMembersHeight', 874.0),
      ),
      874,
    );
    expect(_names(_paint(count: 15, height: 100)), ['模拟成员']);
    final painter = _paint(count: 25, height: 874);
    final names = _names(painter);
    expect(names, hasLength(20));
    expect(names.last, '模拟成员');
    expect(names[names.length - 2], 'P18');
    expect(painter.debugPaintedFields.last.y, lessThan(874));
  });

  test('all three locales paint localized clipped widest fields', () {
    for (final (locale, name, prefix) in [
      (_cn, '模拟成员', '模拟地点'),
      (const Locale('zh', 'TW'), '模擬成員', '模擬地點'),
      (const Locale('en', 'US'), 'Widest sample', 'Sample place'),
    ]) {
      final strings = AppStrings.resolve(locale);
      for (final suffix in ['Member', 'Ship', 'Place']) {
        final key = 'overlay.sample.visorWidest$suffix';
        expect(strings.text(key), isNotEmpty);
        expect(strings.text(key), isNot(key));
      }
      final painter = _paint(locale: locale, width: 480);
      expect(_names(painter).last, name);
      expect(painter.debugPaintedFields.last.text, startsWith(prefix));
      expect(painter.debugPaintedFields.last.clip, isNotNull);
      expect(painter.debugPaintedWidth, closeTo(480, 1));
    }
  });
}
