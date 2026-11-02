// Renders the default banner pictures from the code that once drew them live.
// Source: StarBridge's own gradients and panes. No game or third-party media.
//
//   flutter run -d windows --profile -t tool/render_default_banner.dart \
//     --dart-define=OUTPUT_DIR=<absolute directory>
//
// Run it with the real renderer: flutter test uses another one, and its pixels
// differ. See docs/brand-assets/default-banner/README.md.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:starbridge_flutter/design_system/styles/official_fleet_holo_palette.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_holo_paint.dart';

const _width = 2560, _height = 854;

class _DefaultBanner extends StatelessWidget {
  const _DefaultBanner({required this.light});

  final bool light;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: const Alignment(-1, -.6),
        end: const Alignment(.4, 1),
        colors: light
            ? OfficialFleetHoloPalette.deckLight
            : OfficialFleetHoloPalette.deckDark,
      ),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          for (final left in const [.44, .58, .72])
            Positioned(
              left: constraints.maxWidth * left,
              top: -constraints.maxHeight * .05,
              bottom: -constraints.maxHeight * .05,
              width: constraints.maxWidth * .12,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.skewX(-officialFleetHoloSkew),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: OfficialFleetHoloPalette.deckEdge,
                      ),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: OfficialFleetHoloPalette.deckGlow,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Future<void> _render(bool light, String directory) async {
  final key = GlobalKey();
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: OverflowBox(
          minWidth: _width.toDouble(),
          maxWidth: _width.toDouble(),
          minHeight: _height.toDouble(),
          maxHeight: _height.toDouble(),
          child: RepaintBoundary(
            key: key,
            child: _DefaultBanner(light: light),
          ),
        ),
      ),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image image = await boundary.toImage();
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final name = light ? 'light' : 'dark';
  await File(
    '$directory/default_banner_$name.png',
  ).writeAsBytes(png!.buffer.asUint8List(), flush: true);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const output = String.fromEnvironment('OUTPUT_DIR');
  if (output.isEmpty) throw StateError('OUTPUT_DIR is required');
  await Directory(output).create(recursive: true);
  await _render(false, output);
  await _render(true, output);
  exit(0);
}
