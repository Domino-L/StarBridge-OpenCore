import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/social_windows/window_presentation.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';

void main() {
  test('detached windows retain every supported client locale', () {
    for (final tag in ['zh-CN', 'zh-TW', 'en-US']) {
      final locale = WindowPresentation.decode({'locale': tag}).locale;
      expect(locale.toLanguageTag(), tag);
    }
    expect(
      WindowPresentation.decode({'locale': 'invalid'}).locale,
      const Locale('zh', 'CN'),
    );
  });

  // Review CX-PERF-MODE-073-REVIEW P2: detached windows learn the performance
  // mode from the snapshot; anything but true keeps the full look.
  test('detached windows carry the performance mode', () {
    final on = AppPreferences.defaults.copyWith(performanceMode: true);
    expect(
      WindowPresentation.decode(encodeWindowPresentation(on)).performanceMode,
      isTrue,
    );
    expect(
      WindowPresentation.decode(
        encodeWindowPresentation(AppPreferences.defaults),
      ).performanceMode,
      isFalse,
    );
    expect(WindowPresentation.decode(const {}).performanceMode, isFalse);
    expect(
      WindowPresentation.decode({'performanceMode': 'true'}).performanceMode,
      isFalse,
    );
  });

  // Review CX-ISCAN-DEFAULT-073-REVIEW P2: before the main window sends a
  // style, detached windows use the 0.7.3 default (scan); a sent style wins.
  test('detached windows default to scan and follow the sent style', () {
    expect(
      WindowPresentation.decode(const {}).interactionSuite,
      InteractionSuite.scan,
    );
    expect(
      WindowPresentation.decode(null).interactionSuite,
      InteractionSuite.scan,
    );
    expect(
      WindowPresentation.decode(
        encodeWindowPresentation(AppPreferences.defaults),
      ).interactionSuite,
      InteractionSuite.scan,
    );
    for (final style in InteractionStyle.values) {
      expect(
        WindowPresentation.decode({'interactionStyle': style.name})
            .interactionSuite
            .name,
        style.name,
      );
    }
  });
}
