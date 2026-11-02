import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';
import 'package:starbridge_flutter/features/communities/community_directory_notice.dart';
import 'package:starbridge_flutter/features/communities/community_shortcuts.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_content_probe.dart';

import '../friends/social_layout_test.dart' show loadFonts;
import '../personal_profile/profile_polish_regression_test.dart' show app;
import 'community_directory_failure_policy_test.dart' show FailurePolicyPort;

const visibleOrganization = CommunityCard(
  targetRef: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  organizationRef: 'org-one',
  name: 'Existing directory',
  description: 'Read before the outage.',
  language: 'en',
  activeTime: 'weekends',
  memberCount: 12,
  relationship: 'member',
  joinMode: 'direct',
  actions: ['leave'],
);

void main() {
  setUpAll(loadFonts);
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [800.0, 1280.0]) {
      testWidgets(
        'actual directory keeps rows and original time through refresh failure $locale $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final port = FailurePolicyPort()..rows = [visibleOrganization];
          var now = DateTime.utc(2026, 10, 15, 10);
          final model = CommunitiesModule(port, now: () => now);
          await model.refresh(newView: 'discover');
          await tester.pumpWidget(
            app(
              CommunitiesPage(createPort: () => port, module: model),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          port.pending = Completer();
          final refreshing = model.refresh();
          await tester.pump();
          expect(find.text(visibleOrganization.name), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          now = now.add(const Duration(minutes: 5));
          port.pending!.completeError(const CommunityFailure('readTransient'));
          await refreshing;
          await tester.pumpAndSettle();
          final strings = AppStrings.resolve(locale);
          expect(find.text(visibleOrganization.name), findsOneWidget);
          expect(
            find.text(strings.text('communities.readTransient')),
            findsOneWidget,
          );
          expect(
            find.text(strings.text('communities.cachedMembershipUnknown')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('community-directory-retry')),
            findsNothing,
          );
          final context = tester.element(find.byType(CommunityDirectoryNotice));
          final material = MaterialLocalizations.of(context),
              at = DateTime.utc(2026, 10, 15, 10).toLocal();
          final caption = strings
              .text('communities.shortcutsCached')
              .replaceAll(
                '{time}',
                '${material.formatMediumDate(at)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(at))}',
              );
          expect(find.text(caption), findsOneWidget);
          StarBridgeActionButton primary() => tester
              .widgetList<StarBridgeActionButton>(
                find.byType(StarBridgeActionButton),
              )
              .firstWhere(
                (button) =>
                    button.controlKey ==
                    const ValueKey('community-card-primary-org-one'),
              );
          expect(primary().onActivate, isNull);
          final probe = tester
              .widgetList<LoadingContentProbe>(find.byType(LoadingContentProbe))
              .firstWhere((value) => value.route == '/communities');
          expect(probe.status.name, 'partial');
          expect(port.writes, isEmpty);
          expect(tester.takeException(), isNull);
          port.pending = null;
          await tester.tap(
            find.byKey(const Key('community-directory-retained-retry')),
          );
          await tester.pumpAndSettle();
          expect(model.directory!.items.single.displayOnly, isFalse);
          expect(
            find.text(strings.text('communities.readTransient')),
            findsNothing,
          );
          expect(primary().onActivate, isNotNull);
          await tester.pumpWidget(const SizedBox());
          model.dispose();
        },
      );
    }
    testWidgets(
      'sidebar transient failure remains visible with explicit retry in $locale',
      (tester) async {
        final port = FailurePolicyPort()..rows = [visibleOrganization];
        final model = CommunitiesModule(port);
        await model.refreshJoined();
        await tester.pumpWidget(
          app(
            SizedBox(
              width: 260,
              child: CommunityShortcuts(
                module: model,
                iconOnly: false,
                selected: false,
                activate: () async => true,
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        port.failure = 'readTransient';
        await model.refreshJoined();
        await tester.pumpAndSettle();
        final strings = AppStrings.resolve(locale);
        expect(find.text(visibleOrganization.name), findsOneWidget);
        expect(
          find.text(strings.text('communities.readTransient')),
          findsOneWidget,
        );
        expect(
          find.text(strings.text('communities.cachedOrganizations')),
          findsOneWidget,
        );
        expect(find.text(strings.text('communities.retry')), findsOneWidget);
        expect(model.joined.single.displayOnly, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        model.dispose();
      },
    );
  }
}
