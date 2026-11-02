import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/communities/community_holo_workspace.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_copy.dart';

void main() {
  test('the activity section opens only when announcements really exist', () {
    expect(
      communityWorkspaceSections(chat: true, ships: true, manage: false)['broadcast'],
      isFalse,
    );
    expect(
      communityWorkspaceSections(
        chat: true,
        ships: true,
        manage: false,
        announcements: true,
      )['broadcast'],
      isTrue,
    );
  });

  for (final (locale, tab, title) in const [
    (Locale('zh', 'CN'), '活动', '组织活动'),
    (Locale('zh', 'TW'), '活動', '組織活動'),
    (Locale('en'), 'Activity', 'Organization activity'),
  ]) {
    testWidgets('names read correctly in $locale', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Builder(
            builder: (context) {
              expect(workspaceText(context, 'section.broadcast'), tab);
              expect(workspaceText(context, 'activity.title'), title);
              final strings = AppStrings.of(context);
              expect(strings.text('officialFleet.tab.broadcasts'), tab);
              expect(
                strings.text('officialFleet.activity.title'),
                locale.languageCode == 'en'
                    ? 'Fleet activity'
                    : locale.countryCode == 'TW'
                    ? '艦隊活動'
                    : '舰队活动',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  }
}
