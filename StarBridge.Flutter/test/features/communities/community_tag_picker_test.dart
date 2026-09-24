import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/communities/community_creation_port.dart';
import 'package:starbridge_flutter/features/communities/community_tag_picker.dart';

import 'community_creation_bridge_test.dart' show optionsPayload;

void main() {
  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      'Tag picker preserves selection, limits choices and cancels: $locale',
      (tester) async {
        tester.view.physicalSize = const Size(680, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final payload = optionsPayload();
        payload['tags'] = List.generate(
          6,
          (i) => {
            'id': 'tag$i',
            'name': 'Activity $i',
            'categoryId': 'exploration',
            'description': 'Description $i',
          },
        );
        final options = CommunityCreationOptions.parse(payload);
        final original = ['tag0', 'tag1', 'tag2', 'tag3', 'tag4'];
        List<String>? result;
        var completed = false;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStringsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showDialog<List<String>>(
                      context: context,
                      builder: (_) => CommunityTagPicker(
                        options: options,
                        selected: original,
                      ),
                    );
                    completed = true;
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('tag-tag5')),
          100,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(const ValueKey('tag-tag5')))
              .onChanged,
          isNull,
        );
        final strings = AppStrings.resolve(locale);
        await tester.tap(
          find.text(strings.text('communities.tagPicker.clear')),
        );
        await tester.pump();
        expect(original, hasLength(5));
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(const ValueKey('tag-tag5')))
              .onChanged,
          isNotNull,
        );
        await tester.tap(find.byKey(const ValueKey('tag-tag5')));
        await tester.pump();
        expect(find.byKey(const ValueKey('selected-tag5')), findsOneWidget);
        await tester.tap(find.text(strings.text('communities.cancel')));
        await tester.pumpAndSettle();
        expect(completed, isTrue);
        expect(result, isNull);
        expect(original, hasLength(5));
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Description 5');
        await tester.pump();
        expect(find.byKey(const ValueKey('tag-tag5')), findsOneWidget);
        expect(find.byKey(const ValueKey('tag-tag0')), findsNothing);
        await tester.tap(find.text(strings.text('communities.applyFilters')));
        await tester.pumpAndSettle();
        expect(result, original);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
