import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_ship_banner.dart';
import 'package:starbridge_flutter/features/communities/community_dispatch_composition.dart';
import 'package:starbridge_flutter/features/communities/community_ship_row_surface.dart';
import 'package:starbridge_flutter/features/communities/community_ship_vehicle_icon.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/shared/ships/catalog_vehicle_icon.dart';

import 'community_ships_test.dart' show shipRow;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final width in [420.0, 1200.0]) {
      for (final reduced in [false, true]) {
        testWidgets(
          'ship controls stable ${locale.toLanguageTag()} $width reduced=$reduced',
          (tester) async {
            tester.view.physicalSize = Size(width, 1100);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final port = ExampleCommunities();
            addTearDown(port.close);
            await tester.pumpWidget(
              host(
                port,
                locale,
                target: '00000000000000000000000000000001',
                disableAnimations: reduced,
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('community-section-ships')),
            );
            await tester.pumpAndSettle();
            final filters = find.byKey(
              const ValueKey('community-ship-filters'),
            );
            for (final banner in tester.widgetList<CommunityShipBanner>(
              find.byType(CommunityShipBanner),
            )) {
              final row = find.byWidget(banner);
              final icon = find.descendant(
                of: row,
                matching: find.byType(CommunityShipVehicleIcon),
              );
              final spec = find.descendant(
                of: row,
                matching: find.byWidget(banner.spec),
              );
              expect(
                tester.getRect(icon).right,
                lessThanOrEqualTo(tester.getRect(spec).left),
                reason:
                    'Vehicle type icon belongs to the left of the size badge.',
              );
            }
            await tester.ensureVisible(filters);
            await tester.pumpAndSettle();
            final chips = find.descendant(
              of: filters,
              matching: find.byType(ChoiceChip),
            );
            List<Rect> positions() => chips
                .evaluate()
                .map((e) => tester.getRect(find.byWidget(e.widget)))
                .toList();
            final mouse = await tester.createGesture(
              kind: ui.PointerDeviceKind.mouse,
            );
            addTearDown(mouse.removePointer);
            for (final id in ['capital', 'all', 'capital', 'all']) {
              final chip = find.byKey(ValueKey('community-ship-filter-$id'));
              final before = positions();
              await mouse.moveTo(tester.getCenter(chip));
              await tester.pump(const Duration(milliseconds: 30));
              expect(positions(), before);
              await mouse.down(tester.getCenter(chip));
              await tester.pump();
              expect(positions(), before);
              await mouse.up();
              await tester.pump();
              expect(positions(), before);
              await tester.pumpAndSettle();
              expect(positions(), before);
              expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
              expect(tester.widget<ChoiceChip>(chip).showCheckmark, isFalse);
            }
            final summary = find.byKey(
              const ValueKey('community-fleet-summary'),
            );
            final dispatch = find.byKey(
              const ValueKey('community-dispatch-summary'),
            );
            expect(summary, findsOneWidget);
            expect(dispatch, findsOneWidget);
            final summaryRect = tester.getRect(summary),
                dispatchRect = tester.getRect(dispatch);
            if (width > 760) {
              expect(summaryRect.top, dispatchRect.top);
              expect(summaryRect.right, lessThan(dispatchRect.left));
              expect(summaryRect.width / dispatchRect.width, closeTo(1.5, .01));
              expect(find.byType(CommunityShipColumnHeader), findsOneWidget);
              final banner = tester.widget<CommunityShipBanner>(
                find.byType(CommunityShipBanner).first,
              );
              final specRect = tester.getRect(find.byWidget(banner.spec));
              final roleRect = tester.getRect(find.byWidget(banner.role));
              final iconRect = tester.getRect(
                find.byWidget(banner.vehicleIcon),
              );
              expect(roleRect.left - specRect.right, closeTo(8, .1));
              expect(specRect.left - iconRect.right, closeTo(8, .1));
              final row = find.byType(CommunityShipRowSurface).first;
              final beforeHover = tester.getRect(row);
              final background = find
                  .descendant(of: row, matching: find.byType(Container))
                  .first;
              final beforeDecoration = tester
                  .widget<Container>(background)
                  .decoration;
              await mouse.moveTo(tester.getCenter(row));
              await tester.pump();
              expect(tester.getRect(row), beforeHover);
              expect(
                tester.widget<Container>(background).decoration,
                isNot(beforeDecoration),
              );
              await mouse.moveTo(Offset.zero);
              await tester.pump();
              expect(tester.getRect(row), beforeHover);
            } else {
              expect(summaryRect.bottom, lessThan(dispatchRect.top));
            }
            for (final isDispatch in [false, true]) {
              final action = find.byKey(
                ValueKey(
                  isDispatch
                      ? 'community-dispatch-details'
                      : 'community-ship-statistics-expand',
                ),
              );
              await tester.ensureVisible(action);
              await tester.tap(action);
              await tester.pumpAndSettle();
              final dialog = find.byKey(
                ValueKey(
                  isDispatch
                      ? 'community-dispatch-dialog'
                      : 'community-statistics-dialog',
                ),
              );
              expect(dialog, findsOneWidget);
              if (isDispatch) {
                expect(
                  find.descendant(
                    of: dialog,
                    matching: find.byType(CommunityDispatchComposition),
                  ),
                  findsOneWidget,
                );
              } else {
                expect(
                  find.byKey(const ValueKey('ship-distribution-table-toggle')),
                  findsOneWidget,
                );
              }
              if (isDispatch) {
                final owner = find
                    .descendant(
                      of: dialog,
                      matching: find.byType(ExpansionTile),
                    )
                    .first;
                await tester.ensureVisible(owner);
                await tester.tap(owner);
                await tester.pumpAndSettle();
                expect(
                  find.descendant(of: dialog, matching: find.byType(ListTile)),
                  findsWidgets,
                );
              }
              await tester.tap(
                find
                    .descendant(of: dialog, matching: find.byType(TextButton))
                    .last,
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            if (width == 1200 && locale.countryCode == 'CN' && !reduced) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('workspace-capture')),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final bytes = (await image.toByteData(
                  format: ui.ImageByteFormat.png,
                ))!;
                await File('build/community-ships-presentation.png')
                    .writeAsBytes(bytes.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.tap(
              find.byKey(const ValueKey('community-dispatch-details')),
            );
            await tester.pumpAndSettle();
            port.close();
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('community-dispatch-dialog')),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
  testWidgets(
    'icons use explicit catalog keys only, old DTOs stay compatible',
    (tester) async {
      final oldShip = CommunitySharedShip.parse(shipRow());
      expect(oldShip.catalogIconKey, isNull);
      for (final key in [
        null,
        'combat-small',
        '../combat-small',
        'utility-small',
        'combat-unknown',
      ]) {
        final ship = CommunitySharedShip.parse(
          shipRow()..['catalogIconKey'] = key,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildStarBridgeTheme(
              FutureRestraintStyle.resolve(AppearanceMode.dark),
              const Locale('en'),
            ),
            home: CommunityShipVehicleIcon(ship: ship),
          ),
        );
        expect(
          find.byType(CatalogVehicleIcon),
          key == 'combat-small' ? findsOneWidget : findsNothing,
        );
      }
    },
  );
}
