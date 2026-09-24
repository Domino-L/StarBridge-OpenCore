import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon_set.dart';

const _writePreview = bool.fromEnvironment('STARBRIDGE_WRITE_ICON_PREVIEW');
const _previewPath = 'build/icon_review/starbridge_icon_gallery.png';

void main() {
  testWidgets('StarBridge icon review board renders without paint errors', (
    tester,
  ) async {
    final font = FontLoader('Source Sans 3')
      ..addFont(rootBundle.load('assets/fonts/SourceSans3VF-Upright.ttf'));
    await font.load();
    await tester.binding.setSurfaceSize(const Size(1600, 1320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const previewKey = Key('starbridge-icon-preview');
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: previewKey,
          child: SizedBox(width: 1600, height: 1320, child: _IconReviewBoard()),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(StarBridgeIcon), findsWidgets);
    if (_writePreview) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(previewKey),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File(_previewPath);
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}

class _IconReviewBoard extends StatelessWidget {
  const _IconReviewBoard();

  static const _identity = [
    StarBridgeIconSemantic.home,
    StarBridgeIconSemantic.room,
    StarBridgeIconSemantic.operation,
    StarBridgeIconSemantic.officialFleet,
    StarBridgeIconSemantic.community,
    StarBridgeIconSemantic.hangar,
    StarBridgeIconSemantic.overlay,
    StarBridgeIconSemantic.settings,
    StarBridgeIconSemantic.friends,
    StarBridgeIconSemantic.notifications,
    StarBridgeIconSemantic.account,
    StarBridgeIconSemantic.profile,
  ];

  static const _profile = [
    StarBridgeIconSemantic.edit,
    StarBridgeIconSemantic.add,
    StarBridgeIconSemantic.dragHandle,
    StarBridgeIconSemantic.resize,
    StarBridgeIconSemantic.remove,
    StarBridgeIconSemantic.schedule,
    StarBridgeIconSemantic.playtime,
    StarBridgeIconSemantic.activity,
    StarBridgeIconSemantic.publicProfile,
    StarBridgeIconSemantic.generalData,
    StarBridgeIconSemantic.privacy,
    StarBridgeIconSemantic.reminder,
    StarBridgeIconSemantic.diagnostics,
  ];

  static const _system = [
    StarBridgeIconSemantic.login,
    StarBridgeIconSemantic.logout,
    StarBridgeIconSemantic.refresh,
    StarBridgeIconSemantic.save,
    StarBridgeIconSemantic.cache,
    StarBridgeIconSemantic.scene,
    StarBridgeIconSemantic.statusHost,
    StarBridgeIconSemantic.statusGame,
    StarBridgeIconSemantic.statusIdentity,
    StarBridgeIconSemantic.statusNetwork,
    StarBridgeIconSemantic.connected,
    StarBridgeIconSemantic.disconnected,
    StarBridgeIconSemantic.warning,
    StarBridgeIconSemantic.forward,
    StarBridgeIconSemantic.windowMinimize,
    StarBridgeIconSemantic.windowMaximize,
    StarBridgeIconSemantic.windowRestore,
    StarBridgeIconSemantic.windowClose,
    StarBridgeIconSemantic.pending,
    StarBridgeIconSemantic.menuDown,
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF080C10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 40, 48, 34),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: 'Source Sans 3',
            color: Color(0xFFE7EEF2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(),
              const SizedBox(height: 28),
              _IconGroup(title: '01  IDENTITY + NAVIGATION', icons: _identity),
              const SizedBox(height: 22),
              _IconGroup(title: '02  PROFILE + SETTINGS', icons: _profile),
              const SizedBox(height: 22),
              _IconGroup(title: '03  SYSTEM + STATUS', icons: _system),
              const Spacer(),
              const _ContextStrip(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 54,
          height: 54,
          child: Center(
            child: StarBridgeIcon(
              StarBridgeIconSemantic.home,
              size: 34,
              color: Color(0xFF7CC7D6),
            ),
          ),
        ),
        const SizedBox(width: 18),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'STARBRIDGE  /  ICON SYSTEM',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'OUTLINE V1  ·  24 × 24 MASTER  ·  16 / 20 / 24 OPTICAL GRADES',
              style: TextStyle(
                color: Color(0xFF93A4AE),
                fontSize: 13,
                letterSpacing: 1.15,
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF183A42),
            border: Border.all(color: const Color(0xFF5BA6B4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            '45 SEMANTICS',
            style: TextStyle(
              color: Color(0xFF7CC7D6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _IconGroup extends StatelessWidget {
  const _IconGroup({required this.title, required this.icons});

  final String title;
  final List<StarBridgeIconSemantic> icons;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF93A4AE),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final semantic in icons) _IconCell(semantic)],
        ),
      ],
    );
  }
}

class _IconCell extends StatelessWidget {
  const _IconCell(this.semantic);

  final StarBridgeIconSemantic semantic;

  @override
  Widget build(BuildContext context) {
    final signature = StarBridgeIconSet.resolve(semantic).signature;
    final signalColor = signature == StarBridgeIconSignature.none
        ? const Color(0xFF93A4AE)
        : const Color(0xFF5BA6B4);
    return Container(
      width: 205,
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111920),
        border: Border.all(color: const Color(0xFF344650)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StarBridgeIcon(semantic, size: 16, color: signalColor),
                StarBridgeIcon(
                  semantic,
                  size: 20,
                  color: const Color(0xFFE7EEF2),
                ),
                StarBridgeIcon(semantic, size: 24, color: signalColor),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _labelFor(semantic),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  signature.name.toUpperCase(),
                  style: TextStyle(
                    color: signalColor,
                    fontSize: 9,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextStrip extends StatelessWidget {
  const _ContextStrip();

  static const _navigation = [
    StarBridgeIconSemantic.home,
    StarBridgeIconSemantic.officialFleet,
    StarBridgeIconSemantic.operation,
    StarBridgeIconSemantic.room,
    StarBridgeIconSemantic.community,
    StarBridgeIconSemantic.hangar,
    StarBridgeIconSemantic.overlay,
    StarBridgeIconSemantic.settings,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFB),
        border: Border.all(color: const Color(0xFFCBD6DB)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 166,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIGHT SURFACE',
                  style: TextStyle(
                    color: Color(0xFF17242C),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '20 PX NAVIGATION',
                  style: TextStyle(
                    color: Color(0xFF4A5B64),
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < _navigation.length; index++) ...[
            if (index > 0) const SizedBox(width: 10),
            _NavigationSample(
              semantic: _navigation[index],
              selected: index == 2,
            ),
          ],
        ],
      ),
    );
  }
}

class _NavigationSample extends StatelessWidget {
  const _NavigationSample({required this.semantic, required this.selected});

  final StarBridgeIconSemantic semantic;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 142,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFD7E9EC) : Colors.transparent,
        border: Border.all(
          color: selected ? const Color(0xFF2F7480) : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          StarBridgeIcon(
            semantic,
            size: 20,
            color: selected ? const Color(0xFF2F7480) : const Color(0xFF4A5B64),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _labelFor(semantic),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF17242C)
                    : const Color(0xFF4A5B64),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _labelFor(StarBridgeIconSemantic semantic) {
  final words = semantic.name.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return '${words[0].toUpperCase()}${words.substring(1)}';
}
