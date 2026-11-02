import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_hotkey_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';

import '../../_support/overlay_loading_payload.dart';
import '../friends/social_layout_test.dart' show app;

// The 0.7.2 release installs no keyboard hook (user decision 2026-10-31), so
// settings have no safe hotkey switch and the wire has no field to turn one on.
void main() {
  const hotkey = {
    'binding': 'Alt+O',
    'enabled': true,
    'runtimeState': 'registered',
  };

  test('a hotkey save carries only what the Host reported', () {
    expect(OverlayWorkspaceHotkey.fromMap(hotkey).toUpdateMap(), {
      'binding': 'Alt+O',
      'enabled': true,
    });
    final choice = OverlayWorkspaceHotkey.fromMap({
      ...hotkey,
      'registerHotKey': false,
    });
    expect(choice.registerHotKey, isFalse);
    expect(choice.toUpdateMap()['registerHotKey'], isFalse);
    expect(
      () => OverlayWorkspaceHotkey.fromMap({...hotkey, 'registerHotKey': 'no'}),
      throwsFormatException,
    );
  });

  test('the strict parsers do not know the removed fields', () {
    expect(
      () => OverlayWorkspaceHotkey.fromMap({...hotkey, 'safeHotkeys': true}),
      throwsFormatException,
    );
    expect(
      OverlayRuntimeSnapshot.fromMap(
        loadingRuntimePayload,
      ).hotkeyRegistrationFailures,
      isNull,
    );
    expect(
      OverlayRuntimeSnapshot.fromMap({
        ...loadingRuntimePayload,
        'hotkeyRegistrationFailures': 'Alt+O, Ctrl+Alt+Y',
      }).hotkeyRegistrationFailures,
      'Alt+O, Ctrl+Alt+Y',
    );
    expect(
      () => OverlayRuntimeSnapshot.fromMap({
        ...loadingRuntimePayload,
        'hotkeyRegistrationFailures': 1,
      }),
      throwsFormatException,
    );
    for (final field in const [
      'safeHotkeys',
      'hotkeyMode',
      'hotkeyFallbackReason',
      'hotkeyHealth',
      'hotkeyMessage',
    ]) {
      expect(
        () => OverlayRuntimeSnapshot.fromMap({
          ...loadingRuntimePayload,
          field: null,
        }),
        throwsFormatException,
        reason: field,
      );
    }
  });

  testWidgets('the hotkey card has no safe hotkey switch', (tester) async {
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: OverlayWorkspaceHotkeyCard(
            hotkey: OverlayWorkspaceHotkey.fromMap(hotkey),
            onBindingChanged: (_) {},
            onEnabledChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-hotkey-enabled')), findsOneWidget);
    expect(find.byKey(const Key('overlay-hotkey-safe')), findsNothing);
    expect(find.textContaining('安全热键'), findsNothing);
    expect(find.byKey(const Key('overlay-hotkey-register')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the RegisterHotKey choice says what it does and saves', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: OverlayWorkspaceHotkeyCard(
            hotkey: OverlayWorkspaceHotkey.fromMap({
              ...hotkey,
              'registerHotKey': false,
            }),
            onBindingChanged: (_) {},
            onEnabledChanged: (_) {},
            onRegisterHotKeyChanged: changes.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Measured: the switch does not keep the chord from Star Citizen.
    expect(find.textContaining('这个开关挡不住'), findsOneWidget);
    expect(find.textContaining('不再传给游戏'), findsNothing);
    expect(find.textContaining('安全'), findsNothing);
    await tester.tap(find.byKey(const Key('overlay-hotkey-register')));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(find.textContaining('注册失败'), findsNothing);
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: OverlayWorkspaceHotkeyCard(
            hotkey: OverlayWorkspaceHotkey.fromMap({
              ...hotkey,
              'registerHotKey': true,
            }),
            onBindingChanged: (_) {},
            onEnabledChanged: (_) {},
            onRegisterHotKeyChanged: changes.add,
            registrationFailures: 'Alt+O, Ctrl+Alt+Y',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('注册失败：Alt+O, Ctrl+Alt+Y。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
