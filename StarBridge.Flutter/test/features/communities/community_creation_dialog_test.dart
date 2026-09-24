import 'dart:async';
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
import 'package:starbridge_flutter/features/communities/community_creation_copy.dart';
import 'package:starbridge_flutter/features/communities/community_creation_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_creation_port.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';

import 'community_creation_bridge_test.dart' show optionsPayload;
import '../friends/social_layout_test.dart' show loadFonts;

class FormPort
    implements CommunityCreationPort, CommunityLogoPort, CommunitiesPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final writes = <Map<String, Object?>>[];
  int picks = 0, crops = 0, clears = 0;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async => CommunityDirectory(view, query, [
    const CommunityCard(
      targetRef: 'existing-a',
      name: 'Existing A',
      relationship: 'member',
    ),
    const CommunityCard(
      targetRef: 'existing-b',
      name: 'Existing B',
      relationship: 'member',
    ),
    if (writes.isNotEmpty && result.status == 'accepted') result.organization!,
  ]);
  @override
  Future<String> execute(String action, String targetRef) async => 'rejected';
  @override
  Future<void> close() async {}
  CommunityCreationOutcome result = const CommunityCreationOutcome(
    'accepted',
    organization: CommunityCard(
      targetRef: 'a',
      name: 'Test Organization',
      relationship: 'owner',
    ),
  );
  @override
  Future<CommunityCreationOptions> creationOptions() async =>
      CommunityCreationOptions.parse(optionsPayload());
  @override
  Future<CommunityCreationOutcome> createCommunity(
    String requestId,
    Map<String, Object?> draft,
  ) async {
    writes.add(draft);
    return result;
  }

  static const image =
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
  @override
  bool get canPickLogo => true;
  @override
  Future<CommunityLogoSource?> pickLogo() async {
    picks++;
    return CommunityLogoSource('a' * 32, image, 1000, 500);
  }

  @override
  Future<String> cropLogo(
    String sourceRef,
    double x,
    double y,
    double size,
  ) async {
    crops++;
    return image;
  }

  @override
  Future<void> clearLogo() async {
    clears++;
  }
}

Future<void> showForm(
  WidgetTester tester,
  FormPort port,
  Locale locale, {
  double width = 850,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(port.changes.close);
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
            child: const Text('Open'),
            onPressed: () {
              showDialog<CommunityCreationOutcome>(
                context: context,
                barrierDismissible: false,
                builder: (_) => RepaintBoundary(
                  key: const ValueKey('create-capture'),
                  child: CommunityCreationDialog(
                    port: port,
                    invalidations: port.changes.stream,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'Formal page enters the confirmed organization and preserves other memberships',
    (tester) async {
      final port = FormPort();
      final module = CommunitiesModule(port);
      addTearDown(module.dispose);
      addTearDown(port.changes.close);
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const locale = Locale('zh', 'CN');
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
          home: Scaffold(
            body: CommunitiesPage(createPort: () => port, module: module),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '创建组织'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('create-name')),
        'Test Organization',
      );
      await tester.enterText(find.byKey(const ValueKey('create-code')), 'TEST');
      await tester.tap(
        find.descendant(
          of: find.byType(CommunityCreationDialog),
          matching: find.widgetWithText(FilledButton, '创建组织'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(module.selected?.name, 'Test Organization');
      expect(module.joined.map((card) => card.name), [
        'Existing A',
        'Existing B',
        'Test Organization',
      ]);
      expect(port.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  for (var index = 0; index < AppStrings.supportedLocales.length; index++) {
    final locale = AppStrings.supportedLocales[index];
    String copy(String key) => [
      communityCreationCopy[key]!.$1,
      communityCreationCopy[key]!.$2,
      communityCreationCopy[key]!.$3,
    ][index];
    testWidgets(
      'Complete creation form confirms, preserves WPF defaults and closes $locale',
      (tester) async {
        final port = FormPort();
        await showForm(tester, port, locale, width: index == 2 ? 480 : 850);
        expect(port.writes, isEmpty);
        for (final field in [
          'name',
          'code',
          'description',
          'activeFrom',
          'activeTo',
        ]) {
          expect(find.byKey(ValueKey('create-$field')), findsOneWidget);
        }
        await tester.enterText(
          find.byKey(const ValueKey('create-name')),
          'Test Organization',
        );
        await tester.enterText(
          find.byKey(const ValueKey('create-code')),
          'test',
        );
        expect(port.writes, isEmpty);
        await tester.tap(find.widgetWithText(FilledButton, copy('title')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(port.writes, isEmpty);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle();
        expect(port.writes.single['code'], 'TEST');
        expect(port.writes.single['joinPolicy'], 'Open');
        expect(port.writes.single['activeSystemIds'], ['stanton']);
        expect(port.writes.single.containsKey('bannerImageData'), isFalse);
        expect(find.byType(CommunityCreationDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Cancel keeps draft; discard explicitly closes; nested picker closes on account change',
    (tester) async {
      final port = FormPort();
      await showForm(tester, port, const Locale('zh', 'CN'));
      await tester.enterText(
        find.byKey(const ValueKey('create-name')),
        'Private Draft',
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(find.text('Private Draft'), findsOneWidget);
      final tags = find.widgetWithText(OutlinedButton, '选择标签');
      await tester.ensureVisible(tags);
      await tester.tap(tags);
      await tester.pumpAndSettle();
      expect(find.text('选择组织玩法标签'), findsOneWidget);
      port.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(CommunityCreationDialog), findsNothing);
      expect(find.text('选择组织玩法标签'), findsNothing);
      expect(port.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Logo crop is local, explicit and cleaned up; uncertain create does not repeat',
    (tester) async {
      final port = FormPort()
        ..result = const CommunityCreationOutcome('unknown');
      await showForm(tester, port, const Locale('zh', 'CN'));
      await tester.tap(find.text('选择图片并裁剪'));
      await tester.pumpAndSettle();
      expect(find.text('裁剪组织标志'), findsOneWidget);
      await tester.tap(find.text('采用图片'));
      await tester.pumpAndSettle();
      expect(port.crops, 1);
      expect(port.clears, 1);
      expect(port.writes, isEmpty);
      expect(find.text('移除图片'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('create-name')),
        'Test Organization',
      );
      await tester.enterText(find.byKey(const ValueKey('create-code')), 'TEST');
      if (const bool.fromEnvironment('COMMUNITY_CREATE_CAPTURE')) {
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('create-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '${Directory.systemTemp.path}/starbridge-community-create-${DateTime.now().microsecondsSinceEpoch}.png',
          );
          await file.writeAsBytes(data!.buffer.asUint8List());
          // ignore: avoid_print
          print('COMMUNITY_CREATE_CAPTURE=${file.path}');
          image.dispose();
        });
      }
      await tester.tap(find.widgetWithText(FilledButton, '创建组织'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(port.writes.single['logoImageData'], FormPort.image);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '创建组织'))
            .onPressed,
        isNull,
      );
      expect(find.text('检查我的组织'), findsOneWidget);
      await tester.tap(find.text('检查我的组织'));
      await tester.pumpAndSettle();
      expect(port.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
