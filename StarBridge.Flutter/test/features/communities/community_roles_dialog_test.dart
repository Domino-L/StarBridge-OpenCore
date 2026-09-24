import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_roles_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_roles_copy.dart';

import 'community_roles_test.dart' show RolesFake;
import '../friends/social_layout_test.dart' show loadFonts;

Future<void> openRoles(
  WidgetTester tester,
  RolesFake port, {
  double width = 1100,
  Locale locale = const Locale('zh', 'CN'),
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(port.events.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open roles'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RepaintBoundary(
                key: const ValueKey('roles-capture'),
                child: CommunityRolesDialog(port: port, targetRef: 'a' * 32),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open roles'));
  await tester.pumpAndSettle();
}

String copy(WidgetTester tester, String key) =>
    rolesText(tester.element(find.byType(CommunityRolesDialog)), key);

void main() {
  setUpAll(loadFonts);
  testWidgets('role name input limits length and copy reserves suffix space', (
    tester,
  ) async {
    final port = RolesFake();
    await openRoles(tester, port);
    await tester.tap(find.byKey(const ValueKey('role-custom_navigation')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('role-name')), '名' * 30);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('role-name')))
          .controller!
          .text,
      '名' * 12,
    );
    await tester.tap(find.text(copy(tester, 'copyRole')));
    await tester.pumpAndSettle();
    final name = tester
        .widget<TextField>(find.byKey(const ValueKey('role-name')))
        .controller!
        .text;
    expect(name.characters.length, 12);
    expect(name, endsWith(' 副本'));
    await tester.enterText(
      find.byKey(const ValueKey('role-description')),
      '介' * 100,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('role-description')))
          .controller!
          .text,
      '介' * 80,
    );
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final width in [620.0, 1100.0]) {
      testWidgets('roles editor fits $locale at $width', (tester) async {
        final port = RolesFake();
        await openRoles(tester, port, width: width, locale: locale);
        expect(find.text(copy(tester, 'rolesTitle')), findsOneWidget);
        await tester.tap(find.text(copy(tester, 'newRole')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('role-name')),
          'Navigation',
        );
        await tester.pumpAndSettle();
        expect(port.writes, 0);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(copy(tester, 'save')));
        await tester.pumpAndSettle();
        expect(port.writes, 1);
        expect(port.saved!.last.name, 'Navigation');
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('system seats protected; deletion remains a draft until save', (
    tester,
  ) async {
    final port = RolesFake();
    await openRoles(tester, port);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, copy(tester, 'deleteRole')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('role-custom_navigation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(copy(tester, 'deleteRole')));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存后'), findsWidgets);
    await tester.tap(
      find.widgetWithText(FilledButton, copy(tester, 'deleteRole')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('role-custom_navigation')), findsNothing);
    expect(port.writes, 0);
    await tester.tap(find.text(copy(tester, 'discard')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('role-custom_navigation')),
      findsOneWidget,
    );
  });
  testWidgets(
    'account change dismisses nested confirmation and clears private text',
    (tester) async {
      final port = RolesFake();
      await openRoles(tester, port);
      await tester.enterText(
        find.byKey(const ValueKey('role-name')),
        'Private role draft',
      );
      await tester.tap(find.byTooltip(copy(tester, 'close')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      port.events.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Private role draft'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(port.writes, 0);
    },
  );
  testWidgets('capture role editor', (tester) async {
    final port = RolesFake();
    await openRoles(tester, port);
    await tester.tap(find.byKey(const ValueKey('role-custom_navigation')));
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('roles-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/community-roles-editor.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
