import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_play_reminders.dart';

void main() {
  testWidgets(
    'loads real settings before showing controls, without an account',
    (tester) async {
      final port = _Port()..reading = Completer<ContinuousPlayValue>();
      final controller = ContinuousPlayController(port);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pump();
      expect(find.byKey(const Key('continuous-play-loading')), findsOneWidget);
      expect(find.byType(ContinuousPlayReminderPanel), findsNothing);
      expect(port.reads, 1);
      expect(port.writes, isEmpty);
      port.reading!.complete(_value(enabled: false, first: 90, repeat: 60));
      await tester.pumpAndSettle();
      expect(_switch(tester).value, isFalse);
      expect(_switch(tester).onChanged, isNotNull);
      final panel = tester.widget<ContinuousPlayReminderPanel>(
        find.byType(ContinuousPlayReminderPanel),
      );
      expect(panel.settings.localInAppOnly, isTrue);
      expect(panel.settings.continuousPlay.firstReminderMinutes, 90);
      expect(_field(tester, 'notification-play-first').value, 90);
      expect(_field(tester, 'notification-play-repeat').value, 60);
    },
  );

  testWidgets(
    'failed read retries without writing defaults or exposing errors',
    (tester) async {
      final port = _Port()..failRead = true;
      final controller = ContinuousPlayController(port);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      expect(find.text('暂时无法读取提醒设置。'), findsOneWidget);
      expect(find.byType(ContinuousPlayReminderPanel), findsNothing);
      expect(find.textContaining('private'), findsNothing);
      port.failRead = false;
      await tester.tap(find.byKey(const Key('continuous-play-reload')));
      await tester.pumpAndSettle();
      expect(find.byType(ContinuousPlayReminderPanel), findsOneWidget);
      expect(port.reads, 2);
      expect(port.writes, isEmpty);
    },
  );

  testWidgets(
    'saving disables controls and displays the authoritative response',
    (tester) async {
      final port = _Port()..saving = Completer<ContinuousPlayValue>();
      final controller = ContinuousPlayController(port);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-play-enabled')));
      await tester.pump();
      expect(_switch(tester).onChanged, isNull);
      expect(_switch(tester).value, isTrue);
      expect(find.byKey(const Key('continuous-play-busy')), findsOneWidget);
      expect(port.writes.single.enabled, isFalse);
      expect(port.writes.single.revision, 4);
      port.saving!.complete(_value(enabled: false, first: 90, revision: 5));
      await tester.pumpAndSettle();
      expect(_switch(tester).value, isFalse);
      expect(_field(tester, 'notification-play-first').value, 90);
      expect(controller.value.settings!.revision, 5);
    },
  );

  testWidgets(
    'failed toggle keeps real value and reloads uncertain save result',
    (tester) async {
      final port = _Port()..saving = Completer<ContinuousPlayValue>();
      final controller = ContinuousPlayController(port);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-play-enabled')));
      port.saving!.completeError(StateError('private host failure'));
      await tester.pumpAndSettle();
      expect(_switch(tester).value, isTrue);
      expect(find.text('未能确认保存结果，请重新读取设置。'), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
      // A lost response may have followed a successful write on the host.
      port.current = _value(enabled: false, revision: 5);
      await tester.tap(find.byKey(const Key('continuous-play-reload')));
      await tester.pumpAndSettle();
      expect(_switch(tester).value, isFalse);
      expect(port.writes.length, 1);
      expect(port.reads, 2);
      expect(find.byKey(const Key('continuous-play-failure')), findsNothing);
    },
  );

  testWidgets(
    'failed dropdown save restores the form field, not just the model',
    (tester) async {
      final port = _Port()..saving = Completer<ContinuousPlayValue>();
      final controller = ContinuousPlayController(port);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      final selector = find.descendant(
        of: find.byKey(const Key('notification-play-first')),
        matching: find.byType(DropdownButtonFormField<int>),
      );
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      final choice = find
          .byWidgetPredicate((w) => w is DropdownMenuItem<int> && w.value == 90)
          .last;
      await tester.tap(
        find.descendant(of: choice, matching: find.byType(Text)).last,
      );
      await tester.pump();
      expect(port.writes.single.firstMinutes, 90);
      port.saving!.completeError(StateError('write failed'));
      await tester.pumpAndSettle();
      expect(controller.value.settings!.firstMinutes, 120);
      expect(_field(tester, 'notification-play-first').value, 120);
      expect(_switch(tester).onChanged, isNotNull);
    },
  );

  testWidgets('controller replacement ignores an old pending read', (
    tester,
  ) async {
    final oldPort = _Port()..reading = Completer<ContinuousPlayValue>();
    final oldController = ContinuousPlayController(oldPort);
    final newPort = _Port()..current = _value(enabled: false, first: 180);
    final newController = ContinuousPlayController(newPort);
    addTearDown(oldController.dispose);
    addTearDown(newController.dispose);
    await tester.pumpWidget(_app(oldController));
    await tester.pump();
    await tester.pumpWidget(_app(newController));
    await tester.pumpAndSettle();
    oldPort.reading!.complete(_value());
    await tester.pumpAndSettle();
    expect(_switch(tester).value, isFalse);
    expect(_field(tester, 'notification-play-first').value, 180);
    expect(newPort.reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing while saving does not dispose the caller controller', (
    tester,
  ) async {
    final port = _Port()..saving = Completer<ContinuousPlayValue>();
    final controller = ContinuousPlayController(port);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-play-enabled')));
    await tester.pumpWidget(const SizedBox());
    port.saving!.complete(_value(enabled: false));
    await tester.pumpAndSettle();
    expect(controller.value.settings!.enabled, isFalse);
    expect(await controller.refresh(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preloaded controller is reused without another read', (
    tester,
  ) async {
    final port = _Port();
    final controller = ContinuousPlayController(port);
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    expect(port.reads, 1);
    expect(find.byKey(const Key('continuous-play-loading')), findsNothing);
  });

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('read failure fits a narrow dialog: $locale $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = _Port()..failRead = true;
        final controller = ContinuousPlayController(port);
        addTearDown(controller.dispose);
        await tester.pumpWidget(_app(controller, locale: locale, mode: mode));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('continuous-play-reload')), findsOneWidget);
        expect(
          find.byKey(const Key('continuous-play-failure')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Switch _switch(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(const Key('notification-play-enabled')));

FormFieldState<int> _field(WidgetTester tester, String key) =>
    tester.state<FormFieldState<int>>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(DropdownButtonFormField<int>),
      ),
    );

Widget _app(
  ContinuousPlayController controller, {
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
}) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, mode)
      .tokens;
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.runtimeSupportedLocales(),
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, locale),
    home: Scaffold(
      body: AlertDialog(
        content: ContinuousPlayConnectedPanel(controller: controller),
      ),
    ),
  );
}

ContinuousPlayValue _value({
  bool enabled = true,
  int first = 120,
  int repeat = 120,
  int revision = 4,
}) => ContinuousPlayValue(
  enabled: enabled,
  firstMinutes: first,
  repeatMinutes: repeat,
  revision: revision,
);

class _Port implements ContinuousPlayPort {
  ContinuousPlayValue current = _value();
  Completer<ContinuousPlayValue>? reading;
  Completer<ContinuousPlayValue>? saving;
  bool failRead = false;
  int reads = 0;
  final List<ContinuousPlayValue> writes = [];
  @override
  Future<ContinuousPlayValue> read() async {
    reads++;
    if (failRead) throw StateError('private host failure');
    return reading == null ? current : reading!.future;
  }

  @override
  Future<ContinuousPlayValue> save(ContinuousPlayValue desired) async {
    writes.add(desired);
    return saving == null ? desired : saving!.future;
  }
}
