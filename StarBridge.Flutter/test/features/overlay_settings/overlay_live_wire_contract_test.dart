import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';

import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_live_session.dart';

import 'overlay_appearance_live_session_test.dart'
    show frame, fullLayout, settings;

// This test invokes the compiled real Host codec, not a permissive echo fixture.
// It neither constructs a visible client nor reads account/business data.
Future<(int, Map<String, dynamic>)> nativeCodec(
  Map<String, Object?> value,
) async {
  final assembly = Platform.environment['STARBRIDGE_LIVE_PREVIEW_REGRESSION'];
  if (assembly == null) {
    throw StateError(
      'Set STARBRIDGE_LIVE_PREVIEW_REGRESSION to the isolated regression DLL.',
    );
  }
  final process = await Process.start('dotnet', [assembly, '--validate-frame']);
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  process.stdin.write(jsonEncode(value));
  await process.stdin.close();
  final exit = await process.exitCode;
  final text = await output;
  expect(await errors, isEmpty);
  return (exit, jsonDecode(text) as Map<String, dynamic>);
}

void main() {
  final nativeUnavailable =
      Platform.environment['STARBRIDGE_LIVE_PREVIEW_REGRESSION'] == null
      ? 'Requires the explicitly built native regression DLL; no echo substitute.'
      : false;
  for (final skin in ['Default', 'NightShadow', 'Verdict', 'HajiCitizen']) {
    test(
      '$skin Dart display frame is accepted by actual Host codec without geometry substitution',
      () async {
        final request = frame(skin).toMap();
        final result = await nativeCodec(request);
        expect(result.$1, 0);
        expect(result.$2['appearanceId'], skin);
        expect(result.$2['layout'], request['layout']);
        expect(result.$2['language'], 'zh-CN');
        expect(result.$2['reduceMotion'], false);
        expect(result.$2['appearanceOptions'], request['appearanceOptions']);
      },
      skip: nativeUnavailable,
    );
  }
  test(
    'black background remains a profile option, not a screen or source setting',
    () async {
      final options = OverlayAppearanceOptions.fromMap({
        'schemaVersion': 1,
        'profiles': {
          'haji-citizen': {
            'version': 1,
            'values': {'decorations': [], 'blackBackground': true},
          },
        },
      });
      final f = OverlayAppearanceLiveFrame(
        appearanceId: 'HajiCitizen',
        settings: settings(),
        layout: fullLayout(),
        options: options,
        language: 'en-US',
        reduceMotion: true,
      );
      final result = await nativeCodec(f.toMap());
      expect(result.$1, 0);
      expect(result.$2['appearanceOptions'], options.toMap());
      expect(result.$2['reduceMotion'], true);
      expect(result.$2['language'], 'en-US');
    },
    skip: nativeUnavailable,
  );
  test(
    'actual Host rejects incomplete layout and non-display fields',
    () async {
      for (final invalid in [
        {
          ...frame().toMap(),
          'layout': [fullLayout().first.toMap()],
        },
        {...frame().toMap(), 'source': 'private-message'},
        {...frame().toMap(), 'petAction': 'wake'},
      ]) {
        final result = await nativeCodec(invalid);
        expect(result.$1, 2);
        expect(result.$2, {'error': 'invalid_frame'});
      }
    },
    skip: nativeUnavailable,
  );
}
