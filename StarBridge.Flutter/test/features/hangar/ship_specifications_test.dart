import '../../_support/development_fixture_path.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/hangar/bridge_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/cached_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/ship_specifications_panel.dart';
import 'package:starbridge_flutter/features/hangar/ship_specifications_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_local_hangar_test.dart' show LocalConnection;

const ship = LocalHangarShip(id: 'fixture', title: 'Anvil Carrack');
const specs = ShipSpecifications(
  state: 'ready',
  modelName: 'Carrack',
  dataVersion: 'fixture-version',
  groups: [
    ShipSpecificationGroup('overview', [
      ShipSpecificationField('cargo', '0', 'SCU'),
      ShipSpecificationField('mass', '12000', 'kg'),
    ]),
    ShipSpecificationGroup('flight', [
      ShipSpecificationField('flight.speed.scm', '220', 'm/s'),
    ]),
  ],
  components: [
    ShipSpecificationComponent(
      group: 'weapons',
      name: 'Fixture cannon',
      size: '2',
    ),
    ShipSpecificationComponent(
      group: 'weapons',
      name: 'Fixture cannon',
      size: '2',
    ),
  ],
);

void main() {
  testWidgets(
    'concept ships still query and show data when present, with factual missing copy otherwise',
    (tester) async {
      const concept = LocalHangarShip(
        id: 'concept',
        title: 'Javelin',
        deliveryStatus: 'concept',
      );
      final found = Port();
      await tester.pumpWidget(panel(found, selected: concept));
      expect(found.requests, hasLength(1));
      found.requests.single.complete(specs);
      await tester.pumpAndSettle();
      expect(find.text('Matched model: Carrack'), findsOneWidget);
      final missing = Port();
      await tester.pumpWidget(panel(missing, selected: concept));
      missing.requests.single.complete(
        const ShipSpecifications(state: 'notFound', modelName: 'Javelin'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Public specifications are not yet available for this concept ship.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Refresh to try again'), findsNothing);
    },
  );

  testWidgets(
    'component labels do not reuse numeric missile labels and radar size is explicit',
    (tester) async {
      final port = Port();
      await tester.pumpWidget(panel(port));
      port.requests.single.complete(
        const ShipSpecifications(
          state: 'ready',
          modelName: 'Test model',
          groups: [
            ShipSpecificationGroup('weapons', [
              ShipSpecificationField('missiles', '4', ''),
            ]),
            ShipSpecificationGroup('radar', [
              ShipSpecificationField('radar.size', '2', ''),
            ]),
          ],
          components: [
            ShipSpecificationComponent(
              group: 'missiles',
              name: 'Test rack payload',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('S2'), findsOneWidget);
      final components = find.byKey(const ValueKey('ship-spec-components'));
      await tester.ensureVisible(components);
      await tester.tap(components);
      await tester.pumpAndSettle();
      expect(find.text('Missile count'), findsOneWidget);
      expect(find.text('Missiles and racks'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    },
  );
  setUpAll(() async {
    if (!const bool.fromEnvironment('SHIP_SPEC_REVIEW')) return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final font in {
      'Source Sans 3': 'SourceSans3VF-Upright.ttf',
      'Saira': 'Saira-VF.ttf',
      'Rajdhani': 'Rajdhani-SemiBold.ttf',
      'Source Han Sans CN': 'SourceHanSansCN-VF.ttf',
      'Source Code Pro': 'SourceCodeVF-Upright.ttf',
    }.entries) {
      await (FontLoader(
        font.key,
      )..addFont(rootBundle.load('assets/fonts/${font.value}'))).load();
    }
  });
  testWidgets(
    'only opening a ship detail starts the public specification read',
    (tester) async {
      final port = Port();
      await tester.pumpWidget(app(LocalHangarPage(port: port, onRead: () {})));
      await tester.pumpAndSettle();
      expect(port.requests, isEmpty);
      await tester.ensureVisible(
        find.byKey(const ValueKey('local-hangar-ship-fixture')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('local-hangar-ship-fixture')));
      await tester.pumpAndSettle();
      expect(port.requests, hasLength(1));
      expect(find.text('Loading specifications…'), findsOneWidget);
      port.requests.single.complete(specs);
      await tester.pumpAndSettle();
      expect(find.text('Data version fixture-version'), findsOneWidget);
      expect(find.text('0 SCU'), findsOneWidget);
      expect(find.text('12,000 kg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refresh failure retains details and a retry can recover', (
    tester,
  ) async {
    final port = Port();
    await tester.pumpWidget(panel(port));
    port.requests.single.complete(specs);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh specifications'));
    await tester.pump();
    expect(port.refreshes.last, isTrue);
    port.requests.last.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(
      find.text('Specifications are unavailable. Try again shortly.'),
      findsOneWidget,
    );
    expect(find.text('0 SCU'), findsOneWidget);
    await tester.tap(find.text('Refresh specifications'));
    port.requests.last.complete(specs);
    await tester.pumpAndSettle();
    expect(
      find.text('Specifications are unavailable. Try again shortly.'),
      findsNothing,
    );
  });

  testWidgets(
    'cosmetic edition explains which default model supplies parameters',
    (tester) async {
      final port = Port();
      await tester.pumpWidget(panel(port));
      port.requests.single.complete(
        ShipSpecifications.fromJson({
          'state': 'ready',
          'modelName': 'MOLE Carbon',
          'paintBaseModel': 'MOLE',
        }),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Cosmetic edition · Using default MOLE specifications.'),
        findsOneWidget,
      );
      await tester.pumpWidget(
        panel(
          port,
          selected: const LocalHangarShip(id: 'mole', title: 'MOLE'),
        ),
      );
      port.requests.last.complete(
        const ShipSpecifications(state: 'ready', modelName: 'MOLE'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Cosmetic edition · Using default MOLE specifications.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'bundle explains carrier-only parameters and clears on model switch',
    (tester) async {
      final port = Port();
      await tester.pumpWidget(panel(port));
      port.requests.single.complete(
        ShipSpecifications.fromJson({
          'state': 'ready',
          'modelName': 'Carrack Expedition w/C8X',
          'bundleBaseModel': 'Carrack Expedition',
        }),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Includes C8X · Specifications below are for the Carrack Expedition carrier only, with its default loadout.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(
        panel(
          port,
          selected: const LocalHangarShip(
            id: 'carrier',
            title: 'Carrack Expedition',
          ),
        ),
      );
      port.requests.last.complete(
        const ShipSpecifications(
          state: 'ready',
          modelName: 'Carrack Expedition',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Includes C8X'), findsNothing);
    },
  );

  testWidgets('offline has no public IO; ambiguous and missing are distinct', (
    tester,
  ) async {
    final port = Port()..available = false;
    await tester.pumpWidget(panel(port));
    expect(port.requests, isEmpty);
    expect(find.text('Connect to view SCM specifications.'), findsOneWidget);
    for (final state in ['notFound', 'ambiguous']) {
      final next = Port();
      await tester.pumpWidget(panel(next));
      next.requests.single.complete(
        ShipSpecifications(state: state, modelName: 'Carrack'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          state == 'notFound'
              ? 'No matching SCM specifications were found. Refresh to try again.'
              : 'Several records share this name. The exact variant could not be confirmed.',
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'late model response cannot replace the currently selected ship',
    (tester) async {
      final port = Port();
      await tester.pumpWidget(panel(port));
      await tester.pumpWidget(
        panel(
          port,
          selected: const LocalHangarShip(id: 'b', title: 'Arrow'),
        ),
      );
      port.requests.last.complete(
        const ShipSpecifications(state: 'notFound', modelName: 'Arrow'),
      );
      await tester.pumpAndSettle();
      port.requests.first.complete(specs);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No matching SCM specifications were found. Refresh to try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Data version fixture-version'), findsNothing);
    },
  );

  for (final locale in [
    const Locale('en'),
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
  ]) {
    testWidgets('narrow detail and large text remain readable in $locale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(340, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final port = Port();
      await tester.pumpWidget(panel(port, locale: locale, scale: 1.7));
      port.requests.single.complete(
        ShipSpecifications(
          state: specs.state,
          modelName: specs.modelName,
          dataVersion: specs.dataVersion,
          groups: specs.groups,
          components: specs.components,
          paintBaseModel: 'Carrack',
        ),
      );
      await tester.pumpAndSettle();
      final components = find.byKey(const ValueKey('ship-spec-components'));
      await tester.ensureVisible(components);
      await tester.tap(components);
      await tester.pumpAndSettle();
      expect(find.text('Fixture cannon × 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'cached owner rejects a specification response after account invalidation',
    () async {
      var current = true;
      final source = Port();
      final cache = CachedLocalHangar(source, isCurrent: () => current);
      final read = cache.specificationsFor(ship);
      current = false;
      source.requests.single.complete(specs);
      await expectLater(read, throwsA(isA<LocalHangarFailure>()));
      expect(cache.specificationsAvailable, isFalse);
    },
  );

  test(
    'bridge sends a model read only and denies offline or retired generation',
    () async {
      final connection = SpecificationConnection();
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 7,
      )..acceptHostCapabilities(['ships.specifications']);
      addTearDown(session.close);
      final port = BridgeLocalHangar(session);
      await port.read();
      final result = await port.specificationsFor(ship);
      expect(result.groups.single.fields.single.value, '0');
      final request = connection.requests.last;
      expect(request.name, 'ships.specifications');
      expect(request.payload, {
        'schemaVersion': 1,
        'model': 'Anvil Carrack',
        'refresh': false,
      });
      expect(request.accountContext?.subject, 'owner');
      final count = connection.requests.length;
      await expectLater(
        BridgeLocalHangar.offline(session, 1).specificationsFor(ship),
        throwsA(isA<LocalHangarFailure>()),
      );
      session.advanceGeneration(8);
      await expectLater(
        port.specificationsFor(ship),
        throwsA(isA<LocalHangarFailure>()),
      );
      expect(connection.requests, hasLength(count));
    },
  );

  test(
    'unrecognised wire states cannot silently become an empty specification',
    () {
      expect(
        () => ShipSpecifications.fromJson({
          'state': 'new-state',
          'modelName': 'Carrack',
        }),
        throwsFormatException,
      );
    },
  );

  testWidgets('review image', (tester) async {
    if (!const bool.fromEnvironment('SHIP_SPEC_REVIEW')) return;
    await tester.binding.setSurfaceSize(const Size(980, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final port = Port();
    await tester.pumpWidget(app(LocalHangarPage(port: port, onRead: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('local-hangar-ship-fixture')));
    await tester.pumpAndSettle();
    port.requests.single.complete(specs);
    await tester.pumpAndSettle();
    final boundary =
        tester.renderObject(find.byKey(const Key('spec-review'))) as dynamic;
    // Capture remains in the test harness; product code never writes screenshots.
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      expect(bytes.lengthInBytes, greaterThan(1000));
      final file = File(
        developmentFixturePath(const String.fromEnvironment(
          'SHIP_SPEC_REVIEW_PATH',
          defaultValue: 'Star-Bridge/.artifacts/scm-ship-details-20261015/detail-review.png',
        )),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.byKey(const Key('hangar-detail-expand')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      const path = String.fromEnvironment(
        'SHIP_SPEC_REVIEW_PATH',
        defaultValue: 'Star-Bridge/.artifacts/scm-ship-details-20261015/detail-review.png',
      );
      await File(developmentFixturePath(path).replaceFirst('.png', '-expanded.png'))
          .writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
  });
}

Widget panel(
  Port port, {
  LocalHangarShip selected = ship,
  Locale locale = const Locale('en'),
  double scale = 1,
}) => app(
  SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: ShipSpecificationsPanel(ship: selected, provider: port),
    ),
  ),
  locale: locale,
  scale: scale,
);

Widget app(
  Widget child, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) => RepaintBoundary(
  key: const Key('spec-review'),
  child: MaterialApp(
    locale: locale,
    supportedLocales: const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh', 'TW'),
    ],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildStarBridgeTheme(
      FutureRestraintStyle.resolve(AppearanceMode.dark).withReducedMotion(true),
      locale,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(body: child),
  ),
);

class Port implements LocalHangarPort, ShipSpecificationsProvider {
  final requests = <Completer<ShipSpecifications>>[];
  final refreshes = <bool>[];
  bool available = true;
  @override
  bool get specificationsAvailable => available;
  @override
  Future<ShipSpecifications> specificationsFor(
    LocalHangarShip ship, {
    bool refresh = false,
  }) {
    final request = Completer<ShipSpecifications>();
    requests.add(request);
    refreshes.add(refresh);
    return request.future;
  }

  @override
  Future<LocalHangarSnapshot> read() async =>
      const LocalHangarSnapshot(revision: 1, ships: [ship]);
  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) => throw UnimplementedError();
}

class SpecificationConnection extends LocalConnection {
  @override
  Future<void> send(BridgeEnvelope request) async {
    if (request.name != 'ships.specifications') return super.send(request);
    requests.add(request);
    stream.add(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        sessionGeneration: request.sessionGeneration,
        correlationId: request.correlationId,
        accountContext: request.accountContext,
        status: 'ok',
        payload: {
          'schemaVersion': 1,
          'specifications': {
            'state': 'ready',
            'modelName': 'Carrack',
            'groups': [
              {
                'key': 'overview',
                'fields': [
                  {'key': 'cargo', 'value': '0', 'unit': 'SCU'},
                ],
              },
            ],
          },
        },
      ),
    );
  }
}
