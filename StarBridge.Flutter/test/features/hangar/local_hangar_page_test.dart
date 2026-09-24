import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/hangar/hangar_combat_icon.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_ship_row.dart';

void main() {
  testWidgets('ship detail image fills its frame with proportional cropping', (
    tester,
  ) async {
    final port = _LocalPort();
    await tester.pumpWidget(_app(port));
    port.reads.single.complete(
      const LocalHangarSnapshot(
        revision: 1,
        ships: [
          LocalHangarShip(
            id: 'crop-test',
            title: 'Carrack',
            imageAsset: 'assets/ships/carrack.png',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, 'crop-test');
    await tester.tap(find.byKey(const ValueKey('local-hangar-ship-crop-test')));
    await tester.pumpAndSettle();
    final image = tester.widget<LocalHangarShipImage>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(LocalHangarShipImage),
      ),
    );
    expect(image.fit, BoxFit.cover);
    expect(image.width / image.height, closeTo(300 / 105, .00001));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'saved scan review is available on demand, without a persistent warning',
    (tester) async {
      final port = _LocalPort();
      await tester.pumpWidget(_app(port));
      port.reads.single.complete(
        const LocalHangarSnapshot(
          revision: 1,
          partial: true,
          ships: [LocalHangarShip(id: 'read-ship', title: 'Carrack')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('读取不完整'), findsNothing);
      expect(find.textContaining('物品'), findsNothing);
      expect(find.byTooltip('部分物品类别待核对，已识别舰船已保存；原有舰船暂不移除。'), findsOneWidget);
    },
  );
  testWidgets(
    'history shows one model with the last removal time, separate from current ships',
    (tester) async {
      final port = _LocalPort();
      await tester.pumpWidget(_app(port));
      final first = LocalHangarShip(
        id: 'former-a',
        title: 'Carrack',
        removedAt: DateTime.utc(2026, 9, 19),
      );
      final last = LocalHangarShip(
        id: 'former-b',
        title: 'Carrack',
        removedAt: DateTime.utc(2026, 9, 20),
      );
      final snapshot = LocalHangarSnapshot(
        revision: 3,
        ships: [],
        formerShips: [last, first],
      );
      expect(snapshot.formerModels.single.id, 'former-b');
      expect(
        LocalHangarSnapshot(
          revision: 2,
          ships: [first],
          formerShips: [last],
        ).formerModels,
        isEmpty,
      );
      port.reads.single.complete(snapshot);
      await tester.pumpAndSettle();
      expect(find.text('Carrack'), findsNothing);
      await tester.tap(find.byKey(const Key('hangar-former')));
      await tester.pumpAndSettle();
      expect(find.text('Carrack'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('local-hangar-ship-former-a')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('local-hangar-ship-former-b')),
      );
      await tester.pumpAndSettle();
      expect(find.text('最后移出机库'), findsOneWidget);
      expect(find.textContaining('2026'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('missing combat size does not label a ship unclassified', (
    tester,
  ) async {
    final port = _LocalPort();
    await tester.pumpWidget(_app(port));
    port.reads.single.complete(
      const LocalHangarSnapshot(
        revision: 1,
        ships: [
          LocalHangarShip(
            id: 'synthetic-noncombat',
            title: 'Prospector',
            liner: 'MISC',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Prospector'), findsOneWidget);
    expect(find.text('MISC'), findsOneWidget);
    expect(find.text('未分类'), findsNothing);
    expect(find.byType(HangarCombatIcon), findsNothing);
  });

  setUpAll(() async {
    if (const bool.fromEnvironment('LOCAL_HANGAR_GOLDENS')) {
      for (final font in {
        'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
        'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
        'Source Code Pro': 'assets/fonts/SourceCodeVF-Upright.ttf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
    }
  });

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final mode in AppearanceMode.values) {
      testWidgets(
        'local hangar fits narrow and wide ${locale.toLanguageTag()} ${mode.name}',
        (tester) async {
          addTearDown(() => tester.binding.setSurfaceSize(null));
          for (final size in const [Size(1120, 720), Size(360, 720)]) {
            await tester.binding.setSurfaceSize(size);
            final port = _LocalPort();
            await tester.pumpWidget(_app(port, locale: locale, mode: mode));
            port.reads.single.complete(_visualSaved());
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final name = locale.languageCode == 'en'
                ? 'F8C Lightning'
                : locale.countryCode == 'TW'
                ? 'F8C 閃電'
                : 'F8C 闪电';
            await _reveal(tester, 'synthetic-lightning');
            expect(find.text(name), findsOneWidget);
            if (const bool.fromEnvironment('LOCAL_HANGAR_GOLDENS') &&
                locale.countryCode == 'CN' &&
                ((mode == AppearanceMode.dark && size.width == 1120) ||
                    (mode == AppearanceMode.light && size.width == 360))) {
              await expectLater(
                find.byType(Scaffold),
                matchesGoldenFile(
                  '../../../build/local_hangar_${mode.name}_${size.width.toInt()}.png',
                ),
              );
            }
            // Text scaling and short viewports must still leave every row reachable.
            await tester.pumpWidget(
              _app(port, locale: locale, mode: mode, scale: 1.5),
            );
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('local-hangar-ship-synthetic-unknown')),
              200,
              scrollable: find
                  .descendant(
                    of: find.byType(CustomScrollView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          }
        },
      );
    }
  }

  testWidgets(
    'keyboard opens the reader and ship details with reduced motion',
    (tester) async {
      final port = _LocalPort();
      var opened = false;
      await tester.pumpWidget(
        _app(port, reduced: true, onRead: () => opened = true),
      );
      port.reads.single.complete(_saved());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, isTrue);
      await tester.tap(find.byKey(const Key('local-hangar-search')));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('same-model instances remain separate and the list scrolls', (
    tester,
  ) async {
    final port = _LocalPort();
    await tester.pumpWidget(_app(port));
    port.reads.single.complete(
      LocalHangarSnapshot(
        revision: 1,
        ships: List.generate(
          60,
          (i) => LocalHangarShip(id: 'instance-$i', title: 'Repeated model'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('60 艘舰船'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('local-hangar-ship-instance-0')),
      findsOneWidget,
    );
    await _reveal(tester, 'instance-1');
    expect(
      find.byKey(const ValueKey('local-hangar-ship-instance-1')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('local-hangar-ship-instance-59')),
      400,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(
      find.byKey(const ValueKey('local-hangar-ship-instance-59')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('port replacement and disposal close only owned ship details', (
    tester,
  ) async {
    final previous = _LocalPort(), current = _LocalPort();
    await tester.pumpWidget(_app(previous));
    previous.reads.single.complete(_saved());
    await tester.pumpAndSettle();
    await tester.tap(find.text('F8C 闪电'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.pumpWidget(_app(current));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('F8C Lightning', skipOffstage: false), findsNothing);
    current.reads.single.complete(
      const LocalHangarSnapshot(
        revision: 1,
        ships: [LocalHangarShip(id: 'current', title: 'Current ship')],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current ship'));
    await tester.pumpAndSettle();
    final dialogContext = tester.element(find.byType(AlertDialog));
    unawaited(
      Navigator.of(dialogContext).push(
        DialogRoute<void>(
          context: dialogContext,
          builder: (_) => const AlertDialog(title: Text('Caller dialog')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _app(current, replacement: const Text('Signed out')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Current ship', skipOffstage: false), findsNothing);
    expect(find.text('Caller dialog'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a saved empty hangar stays distinct and opens the reader', (
    tester,
  ) async {
    final port = _LocalPort();
    var opened = false;
    await tester.pumpWidget(_app(port, onRead: () => opened = true));
    port.reads.single.complete(
      LocalHangarSnapshot(
        revision: 2,
        savedAt: DateTime(2026, 9, 3),
        ships: const [],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('机库中还没有舰船'), findsOneWidget);
    expect(find.text('尚未保存机库'), findsNothing);
    expect(find.textContaining('保存在本机'), findsOneWidget);
    await tester.tap(find.byKey(const Key('local-hangar-read')));
    expect(opened, isTrue);
  });

  testWidgets(
    'replacing the port ignores late reads and resets visible state',
    (tester) async {
      final previous = _LocalPort(), current = _LocalPort();
      await tester.pumpWidget(_app(previous));
      previous.reads.last.complete(_saved());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('local-hangar-search')),
        'anvil',
      );
      await tester.tap(find.byKey(const Key('local-hangar-refresh')));
      await tester.pump();

      await tester.pumpWidget(_app(current));
      expect(find.text('F8C 闪电'), findsNothing);
      expect(find.textContaining('保存在本机'), findsNothing);
      previous.reads.last.complete(_saved());
      await tester.pump();
      expect(find.text('F8C 闪电'), findsNothing);
      current.reads.single.complete(
        const LocalHangarSnapshot(
          revision: 1,
          ships: [LocalHangarShip(id: 'new-generation', title: 'Current ship')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current ship'), findsOneWidget);
      expect(find.text('没有符合条件的舰船'), findsNothing);

      await tester.tap(find.byKey(const Key('local-hangar-refresh')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      current.reads.last.completeError(const LocalHangarFailure('cancelled'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('partial saved ships show local time and factual click details', (
    tester,
  ) async {
    final port = _LocalPort();
    await tester.pumpWidget(_app(port));
    port.reads.single.complete(_saved(partial: true));
    await tester.pumpAndSettle();
    expect(find.text('部分物品类别待核对，已识别舰船已保存；原有舰船暂不移除。'), findsNothing);
    expect(find.text('2 艘舰船'), findsOneWidget);
    expect(find.textContaining('保存在本机 · '), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
    await _reveal(tester, 'synthetic-lightning');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('local-hangar-ship-synthetic-lightning')),
        matching: find.byType(HangarCombatIcon),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('F8C 闪电'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('F8C Lightning')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Anvil Aerospace')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('加入时间')),
      findsOneWidget,
    );
    expect(find.textContaining('USD'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    await _reveal(tester, 'synthetic-ironclad');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('local-hangar-ship-synthetic-ironclad')),
        matching: find.byType(HangarCombatIcon),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('铁甲 突袭'));
    await tester.pumpAndSettle();
    expect(find.text('加入时间'), findsNothing);
  });

  testWidgets('search matches original CN TW and manufacturer', (tester) async {
    final port = _LocalPort();
    await tester.pumpWidget(_app(port));
    port.reads.single.complete(_saved());
    await tester.pumpAndSettle();
    for (final query in ['  LIGHTNING  ', '闪电', '閃電', 'anvil']) {
      await tester.enterText(
        find.byKey(const Key('local-hangar-search')),
        query,
      );
      await tester.pump();
      expect(find.text('F8C 闪电'), findsOneWidget);
      expect(find.text('铁甲 突袭'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('local-hangar-total-count')))
            .data,
        '2',
      );
    }
    await tester.enterText(
      find.byKey(const Key('local-hangar-search')),
      'null',
    );
    await tester.pump();
    expect(find.text('没有符合条件的舰船'), findsOneWidget);
    expect(find.text('尚未保存机库'), findsNothing);
    await tester.tap(find.byKey(const Key('local-hangar-clear-search')));
    await tester.pump();
    expect(find.text('F8C 闪电'), findsOneWidget);
    await _reveal(tester, 'synthetic-ironclad');
    expect(find.text('铁甲 突袭'), findsOneWidget);
  });

  testWidgets('read errors retry and retain the last valid display', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final port = _LocalPort();
    await tester.pumpWidget(_app(port));
    port.reads.last.completeError(const LocalHangarFailure('unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取本机机库，请重试。'), findsOneWidget);
    expect(find.text('尚未保存机库'), findsNothing);
    expect(find.text('0 艘舰船'), findsNothing);
    expect(find.byKey(const Key('local-hangar-summary')), findsNothing);

    await tester.tap(find.byKey(const Key('local-hangar-retry')));
    await tester.pump();
    port.reads.last.complete(_saved());
    await tester.pumpAndSettle();
    expect(find.text('F8C 闪电'), findsOneWidget);
    expect(find.textContaining('保存在本机'), findsOneWidget);

    await tester.tap(find.byKey(const Key('local-hangar-refresh')));
    await tester.pump();
    expect(find.text('F8C 闪电'), findsOneWidget);
    port.reads.last.completeError(StateError('private storage detail'));
    await tester.pumpAndSettle();
    expect(find.text('F8C 闪电'), findsOneWidget);
    expect(find.text('private storage detail'), findsNothing);
    expect(find.byKey(const Key('local-hangar-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('local-hangar-retry')));
    await tester.pump();
    port.reads.last.complete(_saved());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-hangar-retry')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading is distinct from an unsaved empty hangar', (
    tester,
  ) async {
    final port = _LocalPort();
    await tester.pumpWidget(_app(port));
    expect(find.text('正在读取本机机库…'), findsOneWidget);
    expect(find.text('尚未保存机库'), findsNothing);
    expect(find.text('0 艘舰船'), findsNothing);

    port.reads.single.complete(
      const LocalHangarSnapshot(revision: 0, ships: []),
    );
    await tester.pumpAndSettle();
    expect(find.text('正在读取本机机库…'), findsNothing);
    expect(find.text('尚未保存机库'), findsOneWidget);
    expect(find.byKey(const Key('local-hangar-read')), findsOneWidget);
  });
}

Future<void> _reveal(WidgetTester tester, String id) async {
  final row = find.byKey(ValueKey('local-hangar-ship-$id'));
  await tester.scrollUntilVisible(
    row,
    180,
    scrollable: find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
}

LocalHangarSnapshot _saved({bool partial = false}) => LocalHangarSnapshot(
  revision: 4,
  savedAt: DateTime(2026, 9, 3, 14, 5),
  partial: partial,
  ships: [
    LocalHangarShip(
      id: 'synthetic-lightning',
      title: 'F8C Lightning',
      cn: 'F8C 闪电',
      tw: 'F8C 閃電',
      liner: 'Anvil Aerospace',
      size: 'small',
      addedAt: DateTime(2026, 8, 20),
    ),
    const LocalHangarShip(
      id: 'synthetic-ironclad',
      title: 'Ironclad Assault',
      cn: '铁甲 突袭',
      tw: '鐵甲 突襲',
      liner: 'Drake Interplanetary',
      size: 'large',
    ),
  ],
);

LocalHangarSnapshot _visualSaved() => LocalHangarSnapshot(
  revision: 4,
  savedAt: DateTime(2026, 9, 3, 14, 5),
  partial: true,
  ships: [
    ..._saved().ships,
    const LocalHangarShip(
      id: 'synthetic-hornet',
      title: 'F7C-M Super Hornet Mk II',
      cn: 'F7C-M 超级大黄蜂 Mk II',
      tw: 'F7C-M 超級大黃蜂 Mk II',
      liner: 'Anvil Aerospace',
      size: 'small',
    ),
    const LocalHangarShip(
      id: 'synthetic-cutlass',
      title: 'Cutlass Black',
      cn: '黑色弯刀',
      tw: '黑色彎刀',
      liner: 'Drake Interplanetary',
      size: 'medium',
    ),
    const LocalHangarShip(
      id: 'synthetic-idris',
      title: 'Idris-P Frigate',
      cn: '伊德里斯-P',
      tw: '伊德里斯-P',
      liner: 'Aegis Dynamics',
      size: 'capital',
    ),
    const LocalHangarShip(id: 'synthetic-unknown', title: 'Unlisted ship'),
  ],
);

Widget _app(
  LocalHangarPort port, {
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
  bool reduced = false,
  double scale = 1,
  VoidCallback? onRead,
  Widget? extraAction,
  Widget? replacement,
  Key? pageKey,
}) => MaterialApp(
  locale: locale,
  supportedLocales: const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(mode).withReducedMotion(reduced),
    locale,
  ),
  home: Scaffold(
    body:
        replacement ??
        LocalHangarPage(
          key: pageKey,
          port: port,
          onRead: onRead ?? () {},
          extraAction: extraAction,
        ),
  ),
);

class _LocalPort implements LocalHangarPort {
  final reads = <Completer<LocalHangarSnapshot>>[];

  @override
  Future<LocalHangarSnapshot> read() {
    final result = Completer<LocalHangarSnapshot>();
    reads.add(result);
    return result.future;
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) => throw StateError('The local list must not save or fabricate a scan.');
}
