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
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_names.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_personal_data_editor.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_removal_dialog.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_reconciliation.dart';
import 'package:starbridge_flutter/features/hangar/cached_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/bridge_local_hangar.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_local_projection.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_dialog.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

import 'bridge_local_hangar_test.dart' show LocalConnection;

const ship = LocalHangarShip(
  id: 'instance-a',
  title: 'Carrack',
  cn: '克拉克',
  nickname: '北辰',
  notes: '远航旗舰\n保留探索配装',
  catalogId: 'carrack',
);
const former = LocalHangarShip(
  id: 'instance-b',
  title: 'Carrack',
  cn: '克拉克',
  nickname: '归途',
  notes: '已移出但保留资料',
  catalogId: 'carrack',
);
final inventoryTime = DateTime.utc(2026, 10, 16);
LocalHangarSnapshot snapshot({
  int revision = 3,
  String? operation,
  LocalHangarShip current = ship,
}) => LocalHangarSnapshot(
  revision: revision,
  ships: [current],
  formerShips: [former],
  inventorySavedAt: inventoryTime,
  operationId: operation,
);

void main() {
  test(
    'lost cached write checks fresh receipt and never joins pre-edit refresh',
    () async {
      final source = _Port();
      final cache = CachedLocalHangar(source, isCurrent: () => true);
      await cache.read();
      source.readGate = Completer<LocalHangarSnapshot>();
      final old = cache.read();
      source.lostReply = true;
      await expectLater(
        cache.savePersonalData(ship.id, '已提交', '备注', 3, operationId: 'receipt'),
        throwsA(isA<TimeoutException>()),
      );
      final receipt = await cache.readPersonalDataReceipt();
      expect(receipt.operationId, 'receipt');
      expect(receipt.ships.single.nickname, '已提交');
      source.readGate!.complete(snapshot());
      expect(await old, same(receipt));
      expect(source.calls, hasLength(1));
    },
  );
  setUpAll(() async {
    if (Platform.environment['STARBRIDGE_HANGAR_N3_CAPTURE'] == null) return;
    for (final font in [
      ('Source Han Sans CN', 'SourceHanSansCN-VF.ttf'),
      ('Source Sans 3', 'SourceSans3VF-Upright.ttf'),
      ('Saira', 'Saira-VF.ttf'),
      ('Rajdhani', 'Rajdhani-SemiBold.ttf'),
    ]) {
      await (FontLoader(
        font.$1,
      )..addFont(rootBundle.load('assets/fonts/${font.$2}'))).load();
    }
  });
  test('names search local metadata without changing model keys', () {
    expect(LocalHangarNames.primary(const Locale('en'), ship), '北辰');
    expect(LocalHangarNames.model(const Locale('zh', 'CN'), ship), '克拉克');
    for (final query in ['北辰', '远航', 'carrack', '克拉克']) {
      expect(LocalHangarNames.matches(ship, query), isTrue);
    }
    expect(ship.modelKey, former.modelKey);
    expect(
      LocalHangarNames.primary(
        const Locale('en'),
        const LocalHangarShip(id: 'a', title: 'Carrack', nickname: '  '),
      ),
      'Carrack',
    );
  });
  for (final mode in ['online', 'offline', 'retained']) {
    test('bridge $mode retains personal fields and guards writes', () async {
      final connection = LocalConnection()
        ..nickname = '北辰'
        ..notes = '本机备注'
        ..history = true;
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 7,
      )..acceptHostCapabilities(['hangar.localPersonalData']);
      addTearDown(session.close);
      final port = mode == 'offline'
          ? BridgeLocalHangar.offline(session, 22)
          : mode == 'retained'
          ? BridgeLocalHangar.retained(
              session,
              '1234567890abcdef1234567890abcdef',
              isCurrent: () => true,
            )
          : BridgeLocalHangar(session);
      final read = await port.read();
      expect(read.ships.first.nickname, '北辰');
      expect(read.formerShips.first.notes, '本机备注');
      expect(port.personalDataAvailable, mode == 'online');
      if (mode == 'online') {
        final result = await port.savePersonalData(
          'ship-0',
          '新昵称',
          '新备注',
          1,
          operationId: 'aabb',
        );
        expect(result.ships.first.nickname, '新昵称');
        final request = connection.requests.firstWhere(
          (r) => r.name == 'hangarReader.personalData',
        );
        expect(request.payload, {
          'schemaVersion': 1,
          'shipId': 'ship-0',
          'nickname': '新昵称',
          'notes': '新备注',
          'expectedRevision': 1,
          'operationId': 'aabb',
        });
        session.advanceGeneration(8);
        await expectLater(
          port.savePersonalData('ship-0', 'x', null, 2, operationId: 'bb'),
          throwsA(isA<LocalHangarFailure>()),
        );
      } else {
        final count = connection.requests.length;
        await expectLater(
          port.savePersonalData('ship-0', 'x', null, 1, operationId: 'bb'),
          throwsA(isA<LocalHangarFailure>()),
        );
        expect(connection.requests, hasLength(count));
      }
    });
  }
  test('cache adopts text save without stale read replacing it', () async {
    final source = _Port();
    var current = true;
    final cache = CachedLocalHangar(source, isCurrent: () => current);
    await cache.read();
    final saved = await cache.savePersonalData(
      ship.id,
      '新船名',
      '备注',
      3,
      operationId: 'operation',
    );
    expect(cache.snapshot, same(saved));
    expect(saved.inventoryReadSavedAt, inventoryTime);
    expect(source.calls.single.$3, 'operation');
    current = false;
    expect(cache.personalDataAvailable, isFalse);
  });

  testWidgets('editor saves exact instance and returns committed snapshot', (
    t,
  ) async {
    final port = _Port();
    LocalHangarSnapshot? saved;
    await _open(t, port, onResult: (r) => saved = r);
    await t.enterText(find.byKey(const Key('hangar-nickname')), '新北辰');
    await t.enterText(find.byKey(const Key('hangar-notes')), '新的备注');
    await t.tap(find.byKey(const Key('hangar-personal-save')));
    await t.pumpAndSettle();
    expect(port.calls.single.$1, '新北辰');
    expect(port.calls.single.$2, '新的备注');
    expect(saved!.ships.single.id, ship.id);
    expect(saved!.inventoryReadSavedAt, inventoryTime);
  });
  testWidgets('cancel leaves metadata unchanged', (t) async {
    final port = _Port();
    await _open(t, port);
    await t.enterText(find.byKey(const Key('hangar-nickname')), 'discard');
    await t.tap(find.byKey(const Key('hangar-personal-cancel')));
    await t.pumpAndSettle();
    expect(port.calls, isEmpty);
    expect(port.value.ships.single.nickname, '北辰');
  });
  testWidgets('conflict keeps draft and prevents blind overwrite', (t) async {
    final port = _Port()
      ..failure = const LocalHangarFailure('hangar.revision_conflict');
    await _open(t, port);
    await t.enterText(find.byKey(const Key('hangar-nickname')), '保留草稿');
    await t.tap(find.byKey(const Key('hangar-personal-save')));
    await t.pumpAndSettle();
    expect(find.textContaining('Your hangar changed.'), findsOneWidget);
    expect(
      t
          .widget<TextFormField>(find.byKey(const Key('hangar-nickname')))
          .controller!
          .text,
      '保留草稿',
    );
    await t.tap(find.byKey(const Key('hangar-personal-save')));
    await t.pumpAndSettle();
    expect(port.calls, hasLength(1));
  });
  testWidgets('lost reply queries receipt without resubmitting', (t) async {
    final port = _Port()..lostReply = true;
    LocalHangarSnapshot? saved;
    await _open(t, port, onResult: (r) => saved = r);
    await t.tap(find.byKey(const Key('hangar-personal-save')));
    await t.pumpAndSettle();
    expect(find.text('Check save status'), findsOneWidget);
    await t.tap(find.byKey(const Key('hangar-personal-save')));
    await t.pumpAndSettle();
    expect(saved, isNotNull);
    expect(port.calls, hasLength(1));
  });
  testWidgets('uncommitted timeout retries only original operation and draft', (
    t,
  ) async {
    final port = _Port()..failure = TimeoutException('synthetic');
    await _open(t, port);
    await t.enterText(find.byKey(const Key('hangar-nickname')), '同次提交');
    await t.tap(find.byKey(const Key('hangar-personal-save')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('hangar-personal-save')));
    await t.pumpAndSettle();
    port.failure = null;
    await t.tap(find.byKey(const Key('hangar-personal-save')));
    await t.pumpAndSettle();
    expect(port.calls, hasLength(2));
    expect(port.calls.first, port.calls.last);
  });
  testWidgets('page edits, updates header and searches nickname and notes', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final port = _Port();
    await t.pumpWidget(_app(LocalHangarPage(port: port, onRead: () {})));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('hangar-open-instance-a')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('hangar-edit-personal-data')));
    await t.tap(find.byKey(const Key('hangar-edit-personal-data')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('hangar-nickname')), '启明星');
    await t.enterText(find.byKey(const Key('hangar-notes')), '深空计划');
    await t.tap(find.byKey(const Key('hangar-personal-save')));
    await t.pumpAndSettle();
    expect(find.text('启明星'), findsWidgets);
    await t.tap(find.byKey(const Key('hangar-detail-close')));
    await t.pumpAndSettle();
    for (final query in ['启明星', '深空计划', 'Carrack']) {
      await t.enterText(find.byKey(const Key('local-hangar-search')), query);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('hangar-open-instance-a')),
        findsOneWidget,
      );
    }
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'profile picker projects and searches current and former nicknames',
    (t) async {
      final choices = [
        projectProfileShip(ship),
        projectProfileShip(former).withFormerOwnership(true),
      ];
      final local = PersonalProfileLocalView(
        choices: choices,
        retainedChoices: [choices.last],
        favoriteShipIds: const [],
        hangarAvailable: true,
        remoteAvailable: false,
        needsCreation: false,
      );
      await t.pumpWidget(
        _app(
          ProfileFavoriteDialog(
            local: local,
            selected: const [],
            capacity: 2,
            reserved: const {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('归途'), findsOneWidget);
      await t.enterText(find.byKey(const Key('profile-favorite-search')), '归途');
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('profile-favorite-instance-b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('profile-favorite-instance-a')),
        findsNothing,
      );
      expect(choices.first.identity.englishName, 'Carrack');
    },
  );
  testWidgets(
    'removal group keeps model while each instance has its nickname',
    (t) async {
      await t.pumpWidget(
        _app(
          LocalHangarRemovalDialog(
            snapshot: LocalHangarSnapshot(
              revision: 3,
              ships: const [ship, former],
            ),
            groups: const [
              LocalHangarRemovalGroup(
                id: 'group',
                requiredCount: 1,
                shipIds: ['instance-a', 'instance-b'],
              ),
            ],
            port: _Port(),
            selected: const {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Carrack · Previously'), findsOneWidget);
      expect(find.text('北辰'), findsOneWidget);
      expect(find.text('归途'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('owner replacement retires editor and ignores late save', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final port = _Port()..gate = Completer<void>();
    await t.pumpWidget(_app(LocalHangarPage(port: port, onRead: () {})));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('hangar-open-instance-a')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('hangar-edit-personal-data')));
    await t.tap(find.byKey(const Key('hangar-edit-personal-data')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('hangar-nickname')), '旧账号草稿');
    await t.tap(find.byKey(const Key('hangar-personal-save')));
    await t.pump();
    await t.pumpWidget(_app(LocalHangarPage(port: _Port(), onRead: () {})));
    await t.pumpAndSettle();
    port.gate!.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('hangar-nickname')), findsNothing);
    expect(find.text('旧账号草稿'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'nickname counter respects graphemes and clearing restores model',
    (t) async {
      final port = _Port();
      await _open(t, port);
      await t.enterText(
        find.byKey(const Key('hangar-nickname')),
        List.filled(65, '🚀').join(),
      );
      expect(
        t
            .widget<TextFormField>(find.byKey(const Key('hangar-nickname')))
            .controller!
            .text
            .characters
            .length,
        64,
      );
      expect(port.calls, isEmpty);
      await t.enterText(find.byKey(const Key('hangar-nickname')), '');
      await t.enterText(find.byKey(const Key('hangar-notes')), '');
      await t.tap(find.byKey(const Key('hangar-personal-save')));
      await t.pumpAndSettle();
      expect(
        LocalHangarNames.primary(const Locale('en'), port.value.ships.single),
        'Carrack',
      );
    },
  );
  for (final layout in [
    ('dark', const Size(1200, 900), 1.0, AppearanceMode.dark),
    ('light', const Size(800, 700), 1.0, AppearanceMode.light),
    ('narrow', const Size(360, 800), 1.0, AppearanceMode.dark),
    ('large-text', const Size(800, 900), 2.0, AppearanceMode.dark),
  ]) {
    testWidgets('personal editor visual ${layout.$1}', (t) async {
      await t.binding.setSurfaceSize(layout.$2);
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        _app(
          LocalHangarPersonalDataEditor(
            port: _Port(),
            snapshot: snapshot(),
            ship: ship,
            isCurrent: () => true,
          ),
          mode: layout.$4,
          scale: layout.$3,
          locale: const Locale('zh', 'CN'),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('personal-data-capture')),
      );
      final path = Platform.environment['STARBRIDGE_HANGAR_N3_CAPTURE']!;
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$path/${layout.$1}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }, skip: Platform.environment['STARBRIDGE_HANGAR_N3_CAPTURE'] == null);
  }
}

Widget _app(
  Widget child, {
  AppearanceMode mode = AppearanceMode.dark,
  double scale = 1,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(mode).withReducedMotion(true),
    locale,
  ),
  builder: (context, child) => RepaintBoundary(
    key: const Key('personal-data-capture'),
    child: MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
  ),
  home: Scaffold(body: child),
);
Future<void> _open(
  WidgetTester t,
  _Port port, {
  void Function(LocalHangarSnapshot?)? onResult,
}) async {
  await t.pumpWidget(
    _app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final result = await showStarBridgeDialog<LocalHangarSnapshot>(
              context,
              builder: (_) => LocalHangarPersonalDataEditor(
                port: port,
                snapshot: port.value,
                ship: ship,
                isCurrent: () => true,
              ),
            );
            onResult?.call(result);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

class _Port implements LocalHangarPort, LocalHangarPersonalDataPort {
  LocalHangarSnapshot value = snapshot();
  final calls = <(String?, String?, String)>[];
  Object? failure;
  bool lostReply = false;
  Completer<void>? gate;
  Completer<LocalHangarSnapshot>? readGate;
  @override
  bool get personalDataAvailable => true;
  @override
  Future<LocalHangarSnapshot> readPersonalDataReceipt() async => value;
  @override
  Future<LocalHangarSnapshot> read() async => readGate?.future ?? value;
  @override
  Future<LocalHangarSnapshot> savePersonalData(
    String shipId,
    String? nickname,
    String? notes,
    int expectedRevision, {
    required String operationId,
  }) async {
    expect(shipId, ship.id);
    expect(expectedRevision, 3);
    calls.add((nickname, notes, operationId));
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    value = snapshot(
      revision: 4,
      operation: operationId,
      current: LocalHangarShip(
        id: shipId,
        title: ship.title,
        cn: ship.cn,
        catalogId: ship.catalogId,
        nickname: nickname,
        notes: notes,
      ),
    );
    if (lostReply) throw TimeoutException('synthetic lost reply');
    return value;
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) => throw UnimplementedError();
}
