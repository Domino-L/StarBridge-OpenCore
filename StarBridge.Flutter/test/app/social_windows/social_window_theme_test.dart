import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_frame.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_app.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_app.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import '../friends_window/friends_window_app_test.dart' as friends;
import 'social_window_test.dart' show native;
import '../../features/friends/social_layout_test.dart' show capture, size, loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final kind in ['friends', 'messages', 'notifications']) {
    testWidgets('$kind accepts initial and live primary appearance snapshots', (tester) async {
      final channel = MethodChannel('starbridge/$kind-surface');
      Map<String, Object?> snapshot(String mode, int revision) => {
        if (kind == 'friends') ...friends.snapshot(revision: revision)
        else ...{
          'opening': 1,
          'revision': revision,
          'view': jsonEncode({'scope': 'fixture', 'targetVersion': 0}),
        },
        'presentation': {
          'appearanceMode': mode, 'locale': 'zh-CN',
          'interactionStyle': revision == 1 ? 'rail' : 'glow',
          'reduceMotion': revision == 2,
        },
      };
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'ready') return snapshot('light', 1);
        if (call.method == 'rpc') {
          final args = call.arguments as Map;
          if (args['op'] == 'directory') return <Object?>[];
        }
        return null;
      });
      final shot = GlobalKey();
      if (kind == 'friends') size(tester, const Size(392, 640));
      await tester.pumpWidget(RepaintBoundary(key: shot, child: kind == 'friends'
          ? const FriendsWindowApp()
          : SocialWindowApp(kind: kind)));
      await tester.pumpAndSettle();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness, Brightness.light);
      expect(InteractionScope.of(tester.element(find.byType(Scaffold))).suite, InteractionSuite.rail);
      if (kind == 'friends') {
        final search = tester.widget<TextField>(find.byKey(const ValueKey('friends-account-search')));
        final light = FutureRestraintStyle.resolve(AppearanceMode.light);
        expect(search.decoration!.fillColor, light.surfaces.ground.fill);
        expect(search.style!.color, light.colors.textPrimary);
        await capture(tester, shot, 'friends-light-regression');
      }
      await native(channel.name, 'snapshot', snapshot('dark', 2));
      await tester.pump();
      await tester.pump();
      final interaction = InteractionScope.of(tester.element(find.byType(Scaffold)));
      expect(interaction.suite, InteractionSuite.glow);
      expect(interaction.reduceMotion, isTrue);
      await tester.pumpAndSettle();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness, Brightness.dark);
      expect(InteractionScope.of(tester.element(find.byType(Scaffold))).suite, InteractionSuite.glow);
      // A delayed earlier snapshot must not roll back the latest theme.
      await native(channel.name, 'snapshot', snapshot('light', 1));
      await tester.pumpAndSettle();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness, Brightness.dark);
      await tester.pumpWidget(const SizedBox());
      messenger.setMockMethodCallHandler(channel, null);
    });
  }
  for (final title in ['聊天', '通知']) {
    testWidgets('$title frame follows selected theme without recreating content', (
      tester,
    ) async {
      final contentKey = GlobalKey();
      Widget app(AppearanceMode mode) => MaterialApp(
        themeAnimationDuration: Duration.zero,
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(mode),
          const Locale('zh'),
        ),
        home: SocialWindowFrame(
          title: title,
          control: (_) {},
          child: SizedBox(key: contentKey),
        ),
      );
      await tester.pumpWidget(app(AppearanceMode.dark));
      // Localizations finish loading on the next frame.
      await tester.pump();
      final originalContent = contentKey.currentContext;
      await tester.pumpWidget(app(AppearanceMode.light));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        FutureRestraintStyle.resolve(AppearanceMode.light).surfaces.raised.fill,
      );
      expect(contentKey.currentContext, same(originalContent));
      expect(tester.takeException(), isNull);
    });
  }
}
