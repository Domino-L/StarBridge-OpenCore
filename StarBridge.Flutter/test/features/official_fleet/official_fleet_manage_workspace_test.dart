import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_governance_port.dart';
import 'package:starbridge_flutter/features/common/organization_governance_settings.dart';

// The left-hand structure: panes only for who may use them.
Future<void> _pump(
  WidgetTester tester, {
  List<OrganizationGovernancePane> before = const [],
  List<OrganizationGovernancePane> after = const [],
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        const Locale('zh', 'CN'),
      ),
      home: Scaffold(
        body: OrganizationGovernanceSettings(
          port: const UnavailableOrganizationGovernance(),
          sourceRef: 'officialFleet:7',
          name: 'Fleet',
          onBack: () async {},
          panesBefore: before,
          panesAfter: after,
          initialPane: before.isEmpty ? 'permissions' : before.first.id,
          permissionsGroup: 'team',
          label: (key) => key,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

OrganizationGovernancePane _pane(String id) => OrganizationGovernancePane(
  id: id,
  icon: StandardIconSemantic.dashboard,
  builder: (select) => TextButton(
    key: ValueKey('go-$id'),
    onPressed: () => select('permissions'),
    child: Text('body-$id'),
  ),
);

void main() {
  Finder nav(String id) =>
      find.byKey(ValueKey('official-fleet-settings-nav-$id'));
  final permissions = find.byKey(
    const Key('official-fleet-governance-content'),
  );

  testWidgets('a narrow layout offers the sections in a list', (tester) async {
    await _pump(
      tester,
      before: [_pane('overview')],
      size: const Size(600, 900),
    );
    expect(
      find.byKey(const ValueKey('official-fleet-settings-category')),
      findsOneWidget,
    );
    expect(find.text('body-overview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no extra pane the page is still the permissions read', (
    tester,
  ) async {
    await _pump(tester);
    expect(nav('permissions'), findsOneWidget);
    expect(permissions, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panes switch in place and can jump to permissions', (
    tester,
  ) async {
    await _pump(tester, before: [_pane('overview')], after: [_pane('sharing')]);
    expect(find.text('body-overview'), findsOneWidget);
    expect(permissions, findsNothing);
    await tester.tap(nav('sharing'));
    await tester.pumpAndSettle();
    expect(find.text('body-sharing'), findsOneWidget);
    await tester.tap(nav('overview'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('go-overview')));
    await tester.pumpAndSettle();
    expect(permissions, findsOneWidget);
  });

  testWidgets('a pane the viewer lost falls back instead of breaking', (
    tester,
  ) async {
    await _pump(tester, before: [_pane('overview'), _pane('announcements')]);
    await tester.tap(nav('announcements'));
    await tester.pumpAndSettle();
    expect(find.text('body-announcements'), findsOneWidget);
    await _pump(tester, before: [_pane('overview')]);
    expect(nav('announcements'), findsNothing);
    expect(find.text('body-overview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
