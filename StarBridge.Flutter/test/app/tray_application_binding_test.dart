import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/tray/tray_application_binding.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_port.dart';

void main() {
  testWidgets('tray projects only actual scene and follows language changes', (
    tester,
  ) async {
    const channel = MethodChannel('starbridge/tray-primary');
    final snapshots = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'configure') {
        snapshots.add(Map<Object?, Object?>.from(call.arguments as Map));
      }
      return null;
    });
    AppPreferencesProjection prefs(Locale locale) => AppPreferencesProjection(
      effective: AppPreferences.defaults.copyWith(locale: locale),
      confirmed: null,
      revision: null,
      phase: AppPreferencesPhase.ready,
      operation: AppPreferencesOperation.idle,
      source: null,
      failure: null,
    );
    final preferences = ValueNotifier(prefs(const Locale('zh', 'CN')));
    final chrome = InMemoryShellChrome(
      initial: InMemoryShellChrome.connectedProjection,
    );
    final overlay = OverlaySettingsModule(_UnavailableOverlay());
    final binding = TrayApplicationBinding(
      preferences: preferences,
      chrome: chrome.projection,
      overlay: overlay,
      openOverlaySettings: () async {},
    );
    await tester.pump();
    final firstScope = snapshots.last['scope'];
    expect(firstScope, isA<int>());
    expect(firstScope as int, inInclusiveRange(1, (1 << 52) - 1));
    expect(
      snapshots.last['scene'],
      AppStrings.resolve(const Locale('zh', 'CN'))
          .text('overlay.scene.default'),
    );
    preferences.value = prefs(const Locale('en'));
    await tester.pump();
    expect(snapshots.last['scope'], firstScope);
    expect(
      snapshots.last['scene'],
      AppStrings.resolve(const Locale('en')).text('overlay.scene.default'),
    );
    chrome.replace(InMemoryShellChrome.hostConnectedProjection);
    await tester.pump();
    expect(
      snapshots.last['scene'],
      isNull,
      reason: 'Preferred scene is not proof of an active overlay scene',
    );
    expect(snapshots.last['canToggleOverlay'], false);
    binding.dispose();
    await tester.pump();
    final replacement = TrayApplicationBinding(
      preferences: preferences,
      chrome: chrome.projection,
      overlay: overlay,
      openOverlaySettings: () async {},
    );
    await tester.pump();
    expect(snapshots.last['scope'], isNot(firstScope));
    replacement.dispose();
    await tester.pump();
    overlay.dispose();
    preferences.dispose();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });
}

class _UnavailableOverlay implements OverlaySettingsPort {
  @override
  Future<OverlaySettingsSnapshot> read() async =>
      const OverlaySettingsSnapshot.unavailable();
  @override
  Future<OverlaySettingsWriteResult> update(
    OverlaySettingsValue settings, {
    required int expectedRevision,
  }) async => const OverlaySettingsWriteResult.failed(
    OverlaySettingsFailure.hostUnavailable,
  );
  @override
  Future<void> close() async {}
}
