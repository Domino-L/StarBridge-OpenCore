import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_member_board.dart';
import 'package:starbridge_flutter/features/common/organization_workspace_frame.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../friends/social_layout_test.dart' show loadFonts;

final _capture = Platform.environment['STARBRIDGE_CAPTURE_HOLO'] == '1';

Future<void> _show(WidgetTester tester, {required bool surface}) async {
  tester.view.physicalSize = const Size(1200, 200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final theme = buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('zh', 'CN'),
  );
  final search = TextEditingController();
  addTearDown(search.dispose);
  final toolbar = OrganizationMemberToolbar(
    namespace: 'face',
    searchController: search,
    onSearch: (_) {},
    filters: OrganizationMemberFilter.values,
    onFilter: (_) {},
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      // A non-standard suite, as some users choose in settings.
      theme: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where(
            (e) => e is! StarBridgeInteractionTheme,
          ),
          const StarBridgeInteractionTheme(suite: InteractionSuite.rail),
        ],
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('face-capture'),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: surface
                ? OrganizationWorkspaceSurface(child: toolbar)
                : toolbar,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (_capture) await loadFonts();
  });

  testWidgets(
    'organization surfaces keep the holo shapes under any interaction suite',
    (tester) async {
      await _show(tester, surface: true);
      // No suite face is painted over the holo search button or filters.
      expect(find.byType(SuitePressable), findsNothing);
      final field = tester.getSize(find.byKey(const Key('face-search')));
      final button = tester.getSize(
        find.byKey(const Key('face-search-submit')),
      );
      // The search button is exactly as tall as the field it sits against.
      expect(button.height, closeTo(field.height, .5));
      if (_capture) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject(
            find.byKey(const ValueKey('face-capture')),
          ) as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/reviews').create(recursive: true);
          await File('build/reviews/holo-search-rail.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );

  testWidgets('outside organization surfaces the chosen suite stays', (
    tester,
  ) async {
    await _show(tester, surface: false);
    expect(find.byType(SuitePressable), findsWidgets);
  });
}
