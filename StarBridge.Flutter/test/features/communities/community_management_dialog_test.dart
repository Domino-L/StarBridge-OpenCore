import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/community_admissions_port.dart';
import 'package:starbridge_flutter/features/communities/community_management_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_management_controller.dart';
import 'package:starbridge_flutter/features/communities/community_management_copy.dart';

import 'community_admissions_test.dart' show admissionsPayload;
import '../friends/social_layout_test.dart' show loadFonts;

class ManagementTestPort implements CommunityAdmissionsPort {
  final changes = StreamController<void>.broadcast();
  final intents = <CommunityAdmissionIntent>[];
  bool canDecide = true, approved = false, revoked = false;
  bool currentAvailable = false, currentOutsidePage = false;
  String expiresAt = '2026-09-14T18:00:00Z';
  CommunityAdmissionOutcome outcome = const CommunityAdmissionOutcome(
    'accepted',
  );
  Completer<CommunityAdmissionOutcome>? hold;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<CommunityAdmissionsPage> readAdmissions(
    String targetRef,
    String section,
    int offset,
  ) async {
    final data = admissionsPayload();
    (data['access'] as Map)['canDecideApplications'] = canDecide;
    data['section'] = section;
    if (section == 'applications' && approved) {
      data['items'] = [];
      data['totalCount'] = 0;
    }
    if (section == 'invites') {
      data['items'] = [
        {
          'entryRef': 'd' * 32,
          'code': 'STAR-INVITE',
          'createdBy': 'Aster',
          'isOwn': true,
          'status': revoked ? 'Revoked' : 'Active',
          'createdAt': '2026-09-07T18:00:00Z',
          'expiresAt': expiresAt,
          'usedCount': 1,
          'maxUses': 5,
          'canRevoke': !revoked,
        },
      ];
      data['currentInviteAvailable'] = currentAvailable;
      data['currentInvite'] = null;
      if (currentAvailable && !revoked) {
        data['currentInvite'] = {
          ...(data['items'] as List).single as Map,
          if (currentOutsidePage) 'entryRef': 'e' * 32,
          if (currentOutsidePage) 'code': 'MY-CURRENT-CODE',
        };
      }
      if (currentOutsidePage) {
        data['items'] = List.generate(
          20,
          (index) => {
            ...(data['items'] as List).first as Map,
            'entryRef': index.toRadixString(16).padLeft(32, '0'),
            'isOwn': false,
            'code': 'OTHER-$index',
          },
        );
        data['totalCount'] = 21;
        data['next'] = 20;
      }
    }
    return CommunityAdmissionsPage.parse(data, targetRef, section, offset);
  }

  @override
  Future<CommunityAdmissionOutcome> manageAdmissions(
    CommunityAdmissionIntent intent,
  ) async {
    intents.add(intent);
    final result = hold == null ? outcome : await hold!.future;
    if (result.status == 'accepted' &&
        intent.action == CommunityAdmissionAction.approve) {
      approved = true;
    }
    if (result.status == 'accepted' &&
        intent.action == CommunityAdmissionAction.revokeInvite) {
      revoked = true;
    }
    return result;
  }
}

Widget host(
  ManagementTestPort port,
  Locale locale, {
  String section = 'applications',
}) => MaterialApp(
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
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => RepaintBoundary(
            key: const ValueKey('management-capture'),
            child: CommunityManagementDialog(
              port: port,
              targetRef: 'a' * 32,
              name: '星海探索组织 · Aster Explorers',
              initialSection: section,
            ),
          ),
        ),
        child: const Text('Open'),
      ),
    ),
  ),
);

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'expired cached invite is labelled and cannot be copied or revoked',
    (tester) async {
      final port = ManagementTestPort()
        ..currentAvailable = true
        ..expiresAt = '2026-09-07T11:59:00Z';
      addTearDown(port.changes.close);
      await tester.pumpWidget(
        host(port, const Locale('en'), section: 'invites'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Expired'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Copy'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Revoke invite'),
            )
            .onPressed,
        isNull,
      );
      final context = tester.element(find.byType(CommunityManagementDialog));
      for (final entry in <Duration, String>{
        Duration.zero: 'Expired',
        const Duration(seconds: 59): 'Less than a minute remaining',
        const Duration(minutes: 2): '2 minutes remaining',
        const Duration(hours: 2): '2 hours remaining',
        const Duration(days: 2): '2 days remaining',
      }.entries) {
        expect(managementRemainingText(context, entry.key), entry.value);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('own current code is shown independently of the first page', (
    tester,
  ) async {
    final port = ManagementTestPort()
      ..currentAvailable = true
      ..currentOutsidePage = true;
    addTearDown(port.changes.close);
    await tester.pumpWidget(host(port, const Locale('en'), section: 'invites'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('My current invite'), findsOneWidget);
    expect(find.text('MY-CURRENT-CODE'), findsOneWidget);
    expect(find.text('7 days remaining'), findsOneWidget);
    expect(find.textContaining('could not be confirmed'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'current code is not duplicated and revoked code clears current area',
    (tester) async {
      final port = ManagementTestPort()..currentAvailable = true;
      addTearDown(port.changes.close);
      await tester.pumpWidget(
        host(port, const Locale('en'), section: 'invites'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('STAR-INVITE'), findsOneWidget);
      await tester.tap(find.text('Revoke invite'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Revoke invite'));
      await tester.pumpAndSettle();
      expect(
        find.text('You have no active invite in this organization.'),
        findsOneWidget,
      );
      expect(find.text('STAR-INVITE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'copy feedback and confirmed revocation stay inside invite card',
    (tester) async {
      final port = ManagementTestPort();
      addTearDown(port.changes.close);
      String? copied;
      var failCopy = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              if (failCopy) throw PlatformException(code: 'unavailable');
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        host(port, const Locale('en'), section: 'invites'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, 'STAR-INVITE');
      expect(find.text('Copied'), findsOneWidget);
      failCopy = true;
      await tester.ensureVisible(find.text('Copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(find.text('Could not copy. Try again.'), findsOneWidget);
      await tester.ensureVisible(find.text('Revoke invite'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoke invite'));
      await tester.pumpAndSettle();
      expect(port.intents, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Revoke invite'));
      await tester.pumpAndSettle();
      expect(port.intents.single.action, CommunityAdmissionAction.revokeInvite);
      expect(find.text('Revoked'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Revoke invite'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final width in [620.0, 1100.0]) {
      testWidgets('management cards fit ${locale.toLanguageTag()} at $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = ManagementTestPort()..currentAvailable = true;
        addTearDown(port.changes.close);
        await tester.pumpWidget(host(port, locale));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(UserAvatarMenu), findsOneWidget);
        final avatarMenu = tester.widget<UserAvatarMenu>(
          find.byType(UserAvatarMenu),
        );
        expect(avatarMenu.target?.source, 'communityApplicant');
        expect(avatarMenu.target?.contextRef, 'a' * 32);
        expect(
          avatarMenu.target?.reference,
          (admissionsPayload()['items'] as List).first['entryRef'],
        );
        expect(find.text('Callsign · Applicant'), findsOneWidget);
        await tester.tap(find.byType(UserAvatarMenu));
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsWidgets);
        await tester.tapAt(const Offset(15, 15));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ChoiceChip).last);
        await tester.pumpAndSettle();
        expect(find.text('STAR-INVITE'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets(
    'approval requires confirmation and refreshes pending applicants',
    (tester) async {
      final port = ManagementTestPort();
      addTearDown(port.changes.close);
      await tester.pumpWidget(host(port, const Locale('en')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(port.intents, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(port.intents, isEmpty);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(port.intents.single.action, CommunityAdmissionAction.approve);
      expect(find.text('No pending applications.'), findsOneWidget);
      expect(find.text('Action completed.'), findsOneWidget);
    },
  );
  testWidgets('read-only applicants never expose enabled approval buttons', (
    tester,
  ) async {
    final port = ManagementTestPort()..canDecide = false;
    addTearDown(port.changes.close);
    await tester.pumpWidget(host(port, const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Approve'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Decline'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'generation retains WPF defaults and warns before repeating unknown outcome',
    (tester) async {
      final port = ManagementTestPort()
        ..outcome = const CommunityAdmissionOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
      addTearDown(port.changes.close);
      await tester.pumpWidget(
        host(port, const Locale('en'), section: 'invites'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate invite'));
      await tester.pumpAndSettle();
      expect(port.intents, isEmpty);
      await tester.tap(find.text('Generate invite').last);
      await tester.pumpAndSettle();
      expect(port.intents.single.expiresInDays, 7);
      expect(port.intents.single.maxUses, 1);
      expect(port.intents.single.confirmUncertainRetry, isFalse);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(port.intents.length, 1);
      await tester.tap(find.text('Generate invite'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The previous action may have completed.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Generate invite').last);
      await tester.pumpAndSettle();
      expect(port.intents.length, 2);
      expect(port.intents.last.confirmUncertainRetry, isTrue);
      expect(port.intents.first.requestId, isNot(port.intents.last.requestId));
    },
  );
  testWidgets('account change closes management and nested confirmation', (
    tester,
  ) async {
    final port = ManagementTestPort();
    addTearDown(port.changes.close);
    await tester.pumpWidget(host(port, const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    port.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(CommunityManagementDialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(port.intents, isEmpty);
    expect(tester.takeException(), isNull);
  });
  test(
    'controller blocks duplicate clicks and drops receipt after invalidation',
    () async {
      final port = ManagementTestPort()
        ..hold = Completer<CommunityAdmissionOutcome>();
      addTearDown(port.changes.close);
      final model = CommunityManagementController(port, 'a' * 32);
      addTearDown(model.dispose);
      await model.load();
      final pending = model.execute(
        CommunityAdmissionAction.approve,
        entryRef: 'b' * 32,
      );
      await model.execute(CommunityAdmissionAction.approve, entryRef: 'b' * 32);
      expect(port.intents.length, 1);
      port.changes.add(null);
      await Future<void>.delayed(Duration.zero);
      port.hold!.complete(const CommunityAdmissionOutcome('accepted'));
      await pending;
      expect(model.outcome, isNull);
      expect(model.page, isNull);
      expect(model.images, isEmpty);
    },
  );
  testWidgets(
    'render management UI for local inspection without visible client',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = ManagementTestPort()..currentAvailable = true;
      addTearDown(port.changes.close);
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      for (final section in ['applications', 'invites']) {
        if (section == 'invites') {
          await tester.tap(find.byType(ChoiceChip).last);
          await tester.pumpAndSettle();
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('management-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          final output = File('build/community-management-$section.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
