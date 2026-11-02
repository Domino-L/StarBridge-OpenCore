import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_inline_avatar.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_avatar_actions.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_history.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3ca_test.dart' show fire;
import 'interaction_batch3bw_test.dart' show frames;

import 'package:starbridge_interaction/starbridge_interaction.dart';

/// Natural text paint bounds, not merely the constrained Paragraph size: a
/// 40px paragraph can hide a 60px line box and still report a legal layout.
Rect glyphBounds(WidgetTester t, Finder avatar) {
  final rich = find
      .descendant(of: avatar, matching: find.byType(RichText))
      .first;
  final paragraph = t.renderObject<RenderParagraph>(rich);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    maxLines: 1,
  )..layout();
  try {
    final box = t.renderObject<RenderBox>(avatar);
    return MatrixUtils.transformRect(
      paragraph.getTransformTo(box),
      Offset.zero & painter.size,
    );
  } finally {
    painter.dispose();
  }
}

void main() {
  setUpAll(loadFonts);
  for (final scale in [1.0, 2.0, 3.0]) {
    for (final name in [
      '白鸦',
      'Warden',
      'étoile',
      '👩🏽‍🚀 Pilot',
      'e\u0301toile',
    ]) {
      testWidgets('avatar $name text$scale keeps full glyph inside40px', (
        t,
      ) async {
        size(t, const Size(500, 300));
        await t.pumpWidget(
          scopedApp(
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Center(child: MenuInlineAvatar(name: name)),
            ),
            InteractionSuite.standard,
          ),
        );
        await t.pump();
        final avatar = find.byType(MenuInlineAvatar);
        expect(t.getSize(avatar), const Size(40, 40));
        final bounds = glyphBounds(t, avatar);
        expect(bounds.left, greaterThanOrEqualTo(3.9));
        expect(bounds.top, greaterThanOrEqualTo(3.9));
        expect(bounds.right, lessThanOrEqualTo(36.1));
        expect(bounds.bottom, lessThanOrEqualTo(36.1));
        expect(find.text(name.characters.first), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  }
  for (final invalid in [
    null,
    'https://invalid.test/portrait.png',
    'data:image/svg+xml;base64,PHN2Zy8+',
    'data:image/png;base64,%%%',
    'data:image/png;base64,${'A' * (128 * 1024)}',
  ]) {
    testWidgets(
      'avatar rejects external/invalid/oversized input ${invalid?.substring(0, 20)}',
      (t) async {
        size(t, const Size(500, 300));
        await t.pumpWidget(
          scopedApp(
            Center(
              child: MenuInlineAvatar(name: '白鸦', source: invalid),
            ),
            InteractionSuite.scan,
          ),
        );
        await t.pump();
        expect(find.byType(Image), findsNothing);
        expect(find.text('白'), findsOneWidget);
        expect(t.getSize(find.byType(MenuInlineAvatar)), const Size(40, 40));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('inline image contract and invalid replacement remain unchanged', (
    t,
  ) async {
    const png =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aO0cAAAAASUVORK5CYII=';
    Widget app(String? source) => scopedApp(
      Center(
        child: MenuInlineAvatar(name: '白鸦', source: source),
      ),
      InteractionSuite.standard,
    );
    await t.pumpWidget(app(png));
    await t.pump();
    final image = t.widget<Image>(find.byType(Image));
    expect(image.width, 40);
    expect(image.height, 40);
    expect(image.fit, BoxFit.cover);
    expect(image.gaplessPlayback, isFalse);
    expect(image.excludeFromSemantics, isTrue);
    final provider = image.image as ResizeImage;
    expect(provider.width, 96);
    expect(provider.height, 96);
    await t.pumpWidget(app('https://invalid.test/portrait.png'));
    await t.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('白'), findsOneWidget);
    await t.pumpWidget(app(null));
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });
  for (final suite in InteractionSuite.values) {
    for (final width in [700.0, 1100.0]) {
      testWidgets(
        '$suite $width actual private history keeps bounded portraits and scaled full names',
        (t) async {
          size(t, Size(width, 900));
          await t.pumpWidget(
            scopedApp(
              MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: MenuCommsHistory(
                  view: MenuCommsView(
                    'ready',
                    name: '白鸦飞行员',
                    profileKey: 'peer',
                    messages: [
                      (
                        incoming: true,
                        text: '完整姓名仍遵循文字缩放',
                        time: DateTime.utc(2026),
                        attachment: false,
                      ),
                    ],
                  ),
                  active: false,
                  onAction: (_, _) {},
                  onProfile: (_) {},
                ),
              ),
              suite,
            ),
          );
          await frames(t);
          final avatars = find.byType(MenuInlineAvatar);
          // Existing effective-width policy intentionally hides message portraits
          // in a compact column; the independent header portrait stays present.
          expect(avatars, findsNWidgets(width < 760 ? 1 : 2));
          for (var i = 0; i < avatars.evaluate().length; i++) {
            final bounds = glyphBounds(t, avatars.at(i));
            expect(t.getSize(avatars.at(i)), const Size(40, 40));
            expect(bounds.top, greaterThanOrEqualTo(3.9));
            expect(bounds.bottom, lessThanOrEqualTo(36.1));
          }
          expect(find.text('白鸦飞行员'), findsOneWidget);
          final name = find.descendant(
            of: find.text('白鸦飞行员'),
            matching: find.byType(RichText),
          );
          expect(t.widget<RichText>(name).textScaler.scale(10), 20);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source portrait menu still requires explicit profile and retires identity',
        (t) async {
          final semantics = t.ensureSemantics();
          final profiles = <InteractionSource>[];
          Widget subject(String identity, {bool enabled = true}) => scopedApp(
            Center(
              child: MenuAvatarActions(
                identity: identity,
                name: '白鸦飞行员',
                onProfile: enabled
                    ? () => profiles.add(captureStarBridgeActivationSource()())
                    : null,
                child: const MenuInlineAvatar(name: '白鸦飞行员'),
              ),
            ),
            suite,
          );
          try {
            await t.pumpWidget(subject('first'));
            await frames(t);
            expect(
              t.getSize(find.byType(MenuInlineAvatar)),
              const Size(40, 40),
            );
            await fire(t, source, find.byType(MenuInlineAvatar));
            await frames(t);
            expect(profiles, isEmpty);
            await fire(t, source, find.text('查看个人页面'));
            await frames(t);
            expect(
              profiles.single,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            await fire(t, source, find.byType(MenuInlineAvatar));
            await frames(t);
            await t.pumpWidget(subject('second', enabled: false));
            await frames(t);
            expect(find.text('查看个人页面'), findsNothing);
            expect(profiles.length, 1);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await t.pumpWidget(const SizedBox());
          }
        },
      );
    }
  }
}
