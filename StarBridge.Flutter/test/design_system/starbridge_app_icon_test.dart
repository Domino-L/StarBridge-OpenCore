import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/brand/starbridge_app_icon.dart';

const frames = [16, 20, 24, 30, 32, 36, 40, 48, 64, 72, 96, 128, 256];

void main() {
  const publicSource = bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE');
  final delivery = publicSource
      ? <String, dynamic>{}
      : jsonDecode(
          File('../docs/brand-assets/small-icons-v11.manifest.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>;

  test(
    'all 62 V11 resources match the approved locked delivery',
    () {
      expect(delivery['version'], 'approved-preview-faithful-v11');
      final files = delivery['files'] as List<dynamic>;
      expect(files, hasLength(62));
      expect(files.map((f) => f['path']).toSet(), hasLength(62));
      for (final file in files) {
        final path = file['path'] as String;
        expect(
          sha256.convert(File('../$path').readAsBytesSync()).toString(),
          file['sha256'],
          reason: 'Approved bytes changed: $path; do not re-render locked PNGs',
        );
      }
    },
    skip: publicSource
        ? 'Full private brand delivery is not a runtime source asset.'
        : false,
  );

  test(
    'default ICOs preserve the eight original large frame payloads',
    () {
      final preserved = delivery['largeFrames'] as List<dynamic>;
      expect(preserved, hasLength(8));
      for (final frame in preserved) {
        final bytes = File('../${frame['path']}').readAsBytesSync();
        final header = ByteData.sublistView(bytes);
        final matches = <Uint8List>[];
        for (var i = 0; i < header.getUint16(4, Endian.little); i++) {
          final p = 6 + i * 16;
          if ((bytes[p] == 0 ? 256 : bytes[p]) != frame['n']) continue;
          final offset = header.getUint32(p + 12, Endian.little);
          final length = header.getUint32(p + 8, Endian.little);
          matches.add(bytes.sublist(offset, offset + length));
        }
        expect(matches, hasLength(1));
        expect(sha256.convert(matches.single).toString(), frame['sha256']);
      }
    },
    skip: publicSource ? 'Historical master frame manifest is private.' : false,
  );

  test('public runtime brand resources retain reviewed hashes', () {
    final inventory = jsonDecode(
      File('../client-assets.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final files = (inventory['files'] as List<dynamic>).where(
      (dynamic file) =>
          (file['path'] as String).contains('/brand/') ||
          (file['path'] as String).endsWith('.ico'),
    );
    expect(files, isNotEmpty);
    for (final dynamic file in files) {
      expect(
        sha256.convert(File('../${file['path']}').readAsBytesSync()).toString(),
        file['sha256'],
        reason: file['path'] as String,
      );
    }
  }, skip: !publicSource);

  test(
    'small physical frames resolve independently from large brand assets',
    () {
      for (final size in frames) {
        for (final brightness in Brightness.values) {
          final theme = brightness == Brightness.dark
              ? 'dark_surface'
              : 'light_surface';
          expect(
            StarBridgeAppIconAssets.smallAsset(
              physicalSize: size.toDouble(),
              backgroundBrightness: brightness,
            ),
            'assets/brand/small_icons/$theme/$size.png',
          );
        }
      }
      expect(
        StarBridgeAppIconAssets.resolve(StarBridgeAppIconSurface.universalTile),
        'assets/brand/starbridge_app_icon.png',
      );
    },
  );

  test('all default and themed ICOs contain native target sizes', () {
    for (final suffix in ['', '_dark_surface', '_light_surface']) {
      final bytes = File('windows/runner/resources/app_icon$suffix.ico')
          .readAsBytesSync();
      final header = ByteData.sublistView(bytes);
      expect(header.getUint16(2, Endian.little), 1);
      final count = header.getUint16(4, Endian.little);
      final sizes = <int>[];
      for (var i = 0; i < count; i++) {
        final p = 6 + i * 16;
        sizes.add(bytes[p] == 0 ? 256 : bytes[p]);
        final offset = header.getUint32(p + 12, Endian.little);
        final length = header.getUint32(p + 8, Endian.little);
        expect(offset + length, lessThanOrEqualTo(bytes.length));
        expect(bytes.sublist(offset, offset + 8), [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
      }
      expect(sizes, frames);
    }
  });

  testWidgets(
    'exported small frames have genuine transparency and antialiasing',
    (tester) async {
      await tester.runAsync(() async {
        for (final theme in ['dark_surface', 'light_surface']) {
          for (final size in frames) {
            final codec = await ui.instantiateImageCodec(
              File('assets/brand/small_icons/$theme/$size.png')
                  .readAsBytesSync(),
            );
            final image = (await codec.getNextFrame()).image;
            expect(image.width, size);
            expect(image.height, size);
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            final alphas = [for (var i = 3; i < rgba.length; i += 4) rgba[i]];
            expect(alphas, contains(0));
            expect(alphas, contains(255));
            expect(alphas.where((a) => a > 0 && a < 255), isNotEmpty);
            for (final index in [
              0,
              size - 1,
              size * (size - 1),
              size * size - 1,
            ]) {
              expect(
                alphas[index],
                0,
                reason: '$theme/$size has no tile corners',
              );
            }
            if (size == 24) {
              final quadrants = [0, 0, 0, 0];
              for (var i = 0; i < size * size; i++) {
                final p = i * 4;
                if (rgba[p + 3] > 50 && rgba[p + 2] - rgba[p] > 20) {
                  quadrants[(i ~/ size >= size / 2 ? 2 : 0) +
                      (i % size >= size / 2 ? 1 : 0)]++;
                }
              }
              expect(
                quadrants.every((n) => n >= 3),
                isTrue,
                reason: 'All four approved trails remain represented',
              );
              final center = ((size ~/ 2 - 1) * size + size ~/ 2 - 1) * 4;
              expect(rgba[center + 3], 255);
              expect(
                rgba[center],
                theme == 'dark_surface' ? greaterThan(240) : lessThan(10),
              );
            }
            image.dispose();
            codec.dispose();
          }
        }
      });
    },
  );

  testWidgets(
    'small widget follows theme and physical DPI without a background',
    (tester) async {
      for (final brightness in [Brightness.dark, Brightness.light]) {
        for (final dpr in [1.0, 2.0, 3.0]) {
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(devicePixelRatio: dpr),
              child: Theme(
                data: ThemeData(brightness: brightness),
                child: const Directionality(
                  textDirection: TextDirection.ltr,
                  child: Center(child: StarBridgeAppIcon(size: 24)),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final image = tester.widget<Image>(
            find.descendant(
              of: find.byType(StarBridgeAppIcon),
              matching: find.byType(Image),
            ),
          );
          final expected = StarBridgeAppIconAssets.smallAsset(
            physicalSize: 24 * dpr,
            backgroundBrightness: brightness,
          );
          expect((image.image as AssetImage).assetName, expected);
          expect(
            find.descendant(
              of: find.byType(StarBridgeAppIcon),
              matching: find.byType(ColoredBox),
            ),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('large icon still resolves the original formal master', (
    tester,
  ) async {
    for (final surface in StarBridgeAppIconSurface.values) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StarBridgeAppIcon(size: 96, surface: surface),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        StarBridgeAppIconAssets.resolve(surface),
      );
      expect(tester.takeException(), isNull);
    }
  });

  test(
    'native small icon routing follows shell theme and preserves large icon',
    () {
      final helper = File('windows/runner/small_application_icon.h')
          .readAsStringSync();
      final runner = File('windows/runner/win32_window.cpp').readAsStringSync();
      final cache = File('windows/runner/small_application_icon_cache.h')
          .readAsStringSync();
      final tray = File('windows/runner/application_lifecycle_bridge.cpp')
          .readAsStringSync();
      final rc = File('windows/runner/Runner.rc').readAsStringSync();
      expect(helper, contains('SystemUsesLightTheme'));
      expect(helper, isNot(contains('AppsUseLightTheme')));
      expect(helper, contains('SPI_GETHIGHCONTRAST'));
      expect(helper, contains('WM_SETTINGCHANGE'));
      // Actual message routing, sizing and lifetime are exercised by the
      // native tests; this only checks the source/asset integration boundary.
      expect(runner, contains('TaskbarIconForDpi(lparam)'));
      expect(runner, contains('SmallIconUsesDarkForeground()'));
      expect(
        cache,
        contains('LoadSmallApplicationIcon(pixels, dark_foreground)'),
      );
      expect(runner, contains('WM_SETICON, ICON_SMALL'));
      expect(tray, contains('RefreshTrayIcon()'));
      expect(tray, contains('data.uFlags = NIF_ICON;'));
      expect(rc, contains('app_icon_light_surface.ico'));
      expect(rc, contains('app_icon_dark_surface.ico'));
    },
  );
}
