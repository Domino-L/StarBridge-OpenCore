import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_field.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_configuration.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_configuration_panel.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_options.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts;

Map<String, Object?> label(String text) => {
  'zhCN': text,
  'zhTW': text,
  'en': text,
};
Map<String, Object?> fixture() => {
  'schemaVersion': 1,
  'appearanceId': 'Default',
  'profileId': 'fixture',
  'version': 1,
  'collection': 'items',
  'title': label('Scene fixture'),
  'description': label('No items by default.'),
  'slots': [
    for (var i = 0; i < 2; i++)
      {
        'id': 'slot$i',
        'group': label('Group $i'),
        'label': label('Edge $i'),
        'identity': {'module': i},
        'selector': 'kind',
        'choices': [
          for (var k = 0; k < 2; k++)
            {
              'value': k,
              'label': label('Variant $k'),
              'fields': [
                {
                  'key': 'color',
                  'label': label('Color'),
                  'default': 0,
                  'options': [
                    for (var c = 0; c < 2; c++)
                      {'value': c, 'label': label('Color $c')},
                  ],
                },
              ],
            },
        ],
      },
  ],
};

Map<String, Object?> withGlobalField() => fixture()
  ..['fields'] = [
    {
      'key': 'backdrop',
      'label': label('Module background'),
      'default': false,
      'options': [
        {'value': false, 'label': label('Original')},
        {'value': true, 'label': label('Black')},
      ],
    },
  ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['STARBRIDGE_APPEARANCE_CONFIGURATION_CAPTURE'] !=
        null) {
      await loadFonts();
    }
  });
  test(
    'optional global field preserves legacy rows and edits independently',
    () {
      final config = OverlayAppearanceConfiguration.fromMap(withGlobalField());
      var options = const OverlayAppearanceOptions.empty().withProfile(
        'other',
        {
          'version': 1,
          'values': {'keep': true},
        },
      );
      expect(config.readFields(options), {'backdrop': false});
      expect(options.profile('fixture'), isNull);
      options = config.changeField(options, 'backdrop', true);
      expect(config.readFields(options), {'backdrop': true});
      expect(config.read(options)!.values.every((r) => r == null), isTrue);
      options = config.select(options, 'slot0', 1);
      options = config.change(options, 'slot0', 'color', 1);
      expect(config.readFields(options), {'backdrop': true});
      options = config.clearCollection(options);
      expect(config.read(options)!.values.every((r) => r == null), isTrue);
      expect(config.readFields(options), {'backdrop': true});
      expect(options.profile('other')!['values'], {'keep': true});
      expect(
        () => config.changeField(options, 'backdrop', 1),
        throwsFormatException,
      );
      final legacy = const OverlayAppearanceOptions.empty().withProfile(
        'fixture',
        {
          'version': 1,
          'values': {'items': []},
        },
      );
      expect(config.readFields(legacy), {'backdrop': false});
      expect(config.clearCollection(legacy).profile('fixture'), isNull);
      expect(() => config.fields.clear(), throwsUnsupportedError);
      for (final value in [1, 'true', null]) {
        final bad = const OverlayAppearanceOptions.empty().withProfile(
          'fixture',
          {
            'version': 1,
            'values': {'items': [], 'backdrop': value},
          },
        );
        expect(config.read(bad), isNull);
        expect(config.readFields(bad), isNull);
        expect(
          () => config.changeField(bad, 'backdrop', false),
          throwsFormatException,
        );
        expect(() => config.clearCollection(bad), throwsFormatException);
      }
      final collision = withGlobalField();
      ((collision['fields'] as List).single as Map)['key'] = 'items';
      expect(
        () => OverlayAppearanceConfiguration.fromMap(collision),
        throwsFormatException,
      );
      final duplicate = withGlobalField();
      (duplicate['fields'] as List).add((duplicate['fields'] as List).single);
      expect(
        () => OverlayAppearanceConfiguration.fromMap(duplicate),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'global background field is reversible without placing or removing items',
    (tester) async {
      size(tester, const Size(420, 1000));
      final config = OverlayAppearanceConfiguration.fromMap(withGlobalField());
      var options = const OverlayAppearanceOptions.empty();
      var writes = 0;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: OverlayAppearanceConfigurationPanel(
                configuration: config,
                options: options,
                onChanged: (next) => setState(() {
                  options = next;
                  writes++;
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(writes, 0);
      final global = find.byKey(const Key('appearance-config-global-backdrop'));
      await tester.tap(global);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Black').last);
      await tester.pumpAndSettle();
      expect(config.readFields(options)!['backdrop'], isTrue);
      expect(config.read(options)!.values.every((r) => r == null), isTrue);
      await tester.tap(find.byKey(const Key('appearance-config-slot-slot0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Variant 0').last);
      await tester.pumpAndSettle();
      final clear = find.byKey(const Key('appearance-config-clear-fixture'));
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(config.readFields(options)!['backdrop'], isTrue);
      await tester.ensureVisible(global);
      await tester.tap(global);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original').last);
      await tester.pumpAndSettle();
      expect(config.readFields(options)!['backdrop'], isFalse);
      expect(writes, 4);
      expect(tester.takeException(), isNull);
    },
  );
  test('declarative choices preserve other profiles, explicit absence and valid variants', () {
    final raw = fixture();
    final config = OverlayAppearanceConfiguration.fromMap(raw);
    (raw['slots'] as List).clear();
    expect(config.slots.length, 2);
    var options = const OverlayAppearanceOptions.empty().withProfile('other', {
      'version': 1,
      'values': {'keep': true},
    });
    expect(config.read(options)!.values.every((v) => v == null), isTrue);
    options = config.select(options, 'slot0', 1);
    expect(config.read(options)!['slot0']!['kind'], 0);
    options = config.change(options, 'slot0', 'color', 1);
    options = config.select(options, 'slot0', 2);
    expect(config.read(options)!['slot0']!['color'], 1);
    expect(options.profile('other')!['values'], {'keep': true});
    expect(
      () => config.change(options, 'slot0', 'color', 99),
      throwsFormatException,
    );
    options = config.select(options, 'slot0', 0);
    expect(config.read(options)!['slot0'], isNull);
    expect(() => config.slots.clear(), throwsUnsupportedError);
    expect(() => config.slots.first.identity.clear(), throwsUnsupportedError);
  });
  test(
    'unknown saved version/rows/fields never infer defaults or overwrite',
    () {
      final c = OverlayAppearanceConfiguration.fromMap(fixture());
      for (final profile in [
        {
          'version': 2,
          'values': {'items': []},
        },
        {
          'version': 1,
          'values': {
            'items': [
              {'module': 0, 'kind': 0, 'color': 99},
            ],
          },
        },
        {
          'version': 1,
          'values': {
            'items': [
              {'module': 0, 'kind': 0, 'color': 0, 'extra': true},
            ],
          },
        },
        {
          'version': 1,
          'values': {
            'items': [
              {'module': 0, 'kind': 0, 'color': 0},
              {'module': 0, 'kind': 1, 'color': 0},
            ],
          },
        },
        {
          'version': 1,
          'values': {'items': [], 'extra': true},
        },
      ]) {
        final o = const OverlayAppearanceOptions.empty().withProfile(
          'fixture',
          profile,
        );
        expect(c.read(o), isNull);
        expect(() => c.select(o, 'slot0', 1), throwsFormatException);
      }
    },
  );
  test('finite form rejects extra commands, duplicate identities and illegal defaults', () {
    final bad = fixture();
    (bad['slots'] as List).add((bad['slots'] as List).first);
    for (final value in [
      fixture()..['schemaVersion'] = 2,
      fixture()..['execute'] = 'launch',
      bad,
    ]) {
      expect(
        () => OverlayAppearanceConfiguration.fromMap(value),
        throwsFormatException,
      );
    }
    final collision = fixture();
    ((collision['slots'] as List).first as Map)['selector'] = 'module';
    expect(
      () => OverlayAppearanceConfiguration.fromMap(collision),
      throwsFormatException,
    );
    final ambiguous = fixture();
    ((ambiguous['slots'] as List).last as Map)['identity'] = {
      'module': 0,
      'slot': 1,
    };
    expect(
      () => OverlayAppearanceConfiguration.fromMap(ambiguous),
      throwsFormatException,
    );
    final initial = fixture();
    ((((initial['slots'] as List).first as Map)['choices'] as List).first
        as Map)['fields'] = [
      {
        'key': 'color',
        'label': label('Color'),
        'default': 99,
        'options': [
          {'value': 0, 'label': label('0')},
        ],
      },
    ];
    expect(
      () => OverlayAppearanceConfiguration.fromMap(initial),
      throwsFormatException,
    );
  });
  for (final mode in AppearanceMode.values) {
    for (final width in [280.0, 420.0, 760.0]) {
      testWidgets(
        'configuration panel edits reversible draft at $width $mode',
        (tester) async {
          size(tester, Size(width, 1000));
          final config = OverlayAppearanceConfiguration.fromMap(fixture());
          var options = const OverlayAppearanceOptions.empty();
          var writes = 0;
          await tester.pumpWidget(
            app(
              StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: OverlayAppearanceConfigurationPanel(
                    configuration: config,
                    options: options,
                    onChanged: (next) => setState(() {
                      options = next;
                      writes++;
                    }),
                  ),
                ),
              ),
              mode,
            ),
          );
          await tester.pumpAndSettle();
          expect(writes, 0);
          expect(find.text('无装饰'), findsOneWidget);
          expect(
            find.byKey(const Key('appearance-config-slot-slot1')),
            findsNothing,
          );
          await tester.tap(find.text('Group 1'));
          await tester.pumpAndSettle();
          expect(find.text('无装饰'), findsNWidgets(2));
          expect(writes, 0); // Browsing another module never equips anything.
          await tester.tap(
            find.byKey(const Key('appearance-config-slot-slot0')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Variant 0').last);
          await tester.pumpAndSettle();
          expect(config.read(options)!['slot0']!['kind'], 0);
          expect(
            find.byKey(const Key('appearance-config-field-slot0-color')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const Key('appearance-config-field-slot0-color')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Color 1').last);
          await tester.pumpAndSettle();
          expect(config.read(options)!['slot0']!['color'], 1);
          final reset = find.byKey(
            const Key('appearance-config-clear-fixture'),
          );
          await tester.ensureVisible(reset);
          await tester.tap(reset);
          await tester.pumpAndSettle();
          expect(options.profile('fixture'), isNull);
          expect(writes, 3);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'full profile envelope retains previous values without throwing',
    (tester) async {
      size(tester, const Size(420, 1000));
      final configuration = OverlayAppearanceConfiguration.fromMap(fixture());
      final options = OverlayAppearanceOptions.fromMap({
        'schemaVersion': 1,
        'profiles': {
          for (var i = 0; i < 8; i++) 'other$i': {'version': 1, 'values': {}},
        },
      });
      await tester.pumpWidget(
        app(
          OverlayAppearanceConfigurationPanel(
            configuration: configuration,
            options: options,
            onChanged: (_) => fail('Full envelope was overwritten'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appearance-config-slot-slot0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Variant 0').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('原配置未改变'), findsOneWidget);
      expect(options.profile('fixture'), isNull);
      expect(tester.takeException(), isNull);
    },
  );
  for (final reason in [
    'screen-edge',
    'joined-edge',
    'neighbor-module',
    'decoration-overlap',
    'module-hidden',
    'module-space',
    'invalid',
  ]) {
    testWidgets(
      'nested decoration fields explain $reason without changing the draft',
      (tester) async {
        size(tester, const Size(320, 1000));
        final config = OverlayAppearanceConfiguration.fromMap(
          withGlobalField(),
        );
        final options = config.select(
          const OverlayAppearanceOptions.empty(),
          'slot0',
          1,
        );
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: OverlayAppearanceConfigurationPanel(
                configuration: config,
                options: options,
                placementStates: {'slot0': reason},
                onChanged: (_) =>
                    fail('Feedback or browsing changed saved intent'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final warning = find.byKey(const Key('appearance-config-status-slot0'));
        expect(warning, findsOneWidget);
        expect(find.textContaining('1 件暂不能显示'), findsOneWidget);
        final decoration = tester.getRect(
          find.byKey(const Key('appearance-config-slot-slot0')),
        );
        final detail = tester.getRect(
          find.byKey(const Key('appearance-config-field-slot0-color')),
        );
        expect(detail.left, greaterThan(decoration.left));
        expect(find.text('模块外观'), findsOneWidget);
        expect(find.text('装饰布置'), findsOneWidget);
        await tester.tap(find.text('Group 0'));
        await tester.pumpAndSettle();
        expect(warning, findsNothing);
        expect(find.textContaining('1 件暂不能显示'), findsOneWidget);
        expect(config.read(options)!['slot0'], isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final entry in {
    'interaction-space': '1 件暂不能互动',
    'observation-only': '1 件仅供观察',
  }.entries) {
    testWidgets(
      'visible decoration explains ${entry.key} without hidden count',
      (tester) async {
        size(tester, const Size(320, 1000));
        final config = OverlayAppearanceConfiguration.fromMap(
          withGlobalField(),
        );
        final options = config.select(
          const OverlayAppearanceOptions.empty(),
          'slot0',
          1,
        );
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: OverlayAppearanceConfigurationPanel(
                configuration: config,
                options: options,
                placementStates: {'slot0': entry.key},
                onChanged: (_) => fail('Feedback rewrote the draft'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('appearance-config-status-slot0')),
          findsOneWidget,
        );
        expect(find.textContaining(entry.value), findsOneWidget);
        expect(find.textContaining('暂不能显示'), findsNothing);
        expect(config.read(options)!['slot0'], isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('unsupported or busy configuration never exposes editing', (
    tester,
  ) async {
    size(tester, const Size(420, 1000));
    final c = OverlayAppearanceConfiguration.fromMap(fixture());
    for (final unsupported in [false, true]) {
      final options = const OverlayAppearanceOptions.empty().withProfile(
        'fixture',
        {
          'version': unsupported ? 2 : 1,
          'values': {'items': []},
        },
      );
      await tester.pumpWidget(
        app(
          OverlayAppearanceConfigurationPanel(
            configuration: c,
            options: options,
            enabled: unsupported,
            onChanged: (_) => fail('Disabled form wrote values'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StarBridgeSelectField<int>), findsWidgets);
      for (final dropdown in tester.widgetList<StarBridgeSelectField<int>>(
        find.byType(StarBridgeSelectField<int>),
      )) {
        expect(dropdown.onSelected, isNull);
      }
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      if (unsupported) {
        expect(find.textContaining('原配置会保留'), findsOneWidget);
      }
    }
  });

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final reason in [
      'joined-edge',
      'interaction-space',
      'observation-only',
    ]) {
      testWidgets(
        'nested placement feedback fits narrow large text $locale $reason',
        (tester) async {
          size(tester, const Size(280, 1000));
          final c = OverlayAppearanceConfiguration.fromMap(withGlobalField());
          final o = c.select(
            const OverlayAppearanceOptions.empty(),
            'slot0',
            1,
          );
          final base = app(const SizedBox()) as MaterialApp;
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              theme: base.theme,
              supportedLocales: base.supportedLocales,
              localizationsDelegates: base.localizationsDelegates,
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.5),
                  ),
                  child: SingleChildScrollView(
                    child: OverlayAppearanceConfigurationPanel(
                      configuration: c,
                      options: o,
                      placementStates: {'slot0': reason},
                      onChanged: (_) =>
                          fail('Reading feedback mutated arrangement'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('appearance-config-status-slot0')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('appearance-config-field-slot0-color')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  final privatePath =
      Platform.environment['STARBRIDGE_APPEARANCE_CONFIGURATION_FIXTURE'];
  if (privatePath != null) {
    test(
      'installed private Native form generates only runtime-compatible choices',
      () {
        final c = OverlayAppearanceConfiguration.fromMap(
          (jsonDecode(File(privatePath).readAsStringSync()) as Map)
              .cast<String, Object?>(),
        );
        expect(c.slots.length, inInclusiveRange(1, 12));
        final cases = <Map<String, Object?>>[];
        void globalCases(OverlayAppearanceOptions value, int index) {
          if (index == c.fields.length) {
            cases.add(value.toMap());
            if (cases.length > 4096) {
              throw StateError('Installed form exceeds probe case budget');
            }
            return;
          }
          final field = c.fields[index];
          for (final option in field.options) {
            globalCases(
              c.changeField(value, field.key, option.value),
              index + 1,
            );
          }
        }

        void enumerate(
          OverlayAppearanceOptions value,
          AppearanceSlot slot,
          AppearanceChoice choice,
          int index,
        ) {
          if (index == choice.fields.length) {
            globalCases(value, 0);
            return;
          }
          final field = choice.fields[index];
          for (final option in field.options) {
            enumerate(
              c.change(value, slot.id, field.key, option.value),
              slot,
              choice,
              index + 1,
            );
          }
        }

        for (final slot in c.slots) {
          for (var i = 1; i <= slot.choices.length; i++) {
            var o = c.select(
              const OverlayAppearanceOptions.empty(),
              slot.id,
              i,
            );
            expect(c.read(o), isNotNull);
            enumerate(o, slot, slot.choices[i - 1], 0);
            for (final f in slot.choices[i - 1].fields) {
              for (final value in f.options) {
                o = c.change(o, slot.id, f.key, value.value);
                expect(c.read(o), isNotNull);
              }
            }
          }
        }
        var selected = c.select(
          const OverlayAppearanceOptions.empty(),
          c.slots[0].id,
          1,
        );
        final firstField = c.slots[0].choices[0].fields[1];
        selected = c.change(
          selected,
          c.slots[0].id,
          firstField.key,
          firstField.options[1].value,
        );
        selected = c.select(selected, c.slots[1].id, 1);
        final sideField = c.slots[1].choices[0].fields.last;
        selected = c.change(
          selected,
          c.slots[1].id,
          sideField.key,
          sideField.options[1].value,
        );
        selected = c.select(selected, c.slots[3].id, 1);
        for (final field in c.fields) {
          selected = c.changeField(
            selected,
            field.key,
            field.options.last.value,
          );
        }
        final output =
            Platform.environment['STARBRIDGE_APPEARANCE_CONFIGURATION_OUTPUT'];
        if (output != null) {
          File(output).writeAsStringSync(jsonEncode(selected.toMap()));
        }
        final casesOutput =
            Platform.environment['STARBRIDGE_APPEARANCE_CONFIGURATION_CASES'];
        if (casesOutput != null) {
          File(casesOutput).writeAsStringSync(jsonEncode(cases));
        }
      },
    );
    testWidgets(
      'private Native form renders its real scene arrangement panel',
      (tester) async {
        size(tester, const Size(1000, 1500));
        final c = OverlayAppearanceConfiguration.fromMap(
          (jsonDecode(File(privatePath).readAsStringSync()) as Map)
              .cast<String, Object?>(),
        );
        var o = c.select(
          const OverlayAppearanceOptions.empty(),
          c.slots[0].id,
          2,
        );
        o = c.select(o, c.slots[1].id, 1);
        final field = c.slots[1].choices[0].fields.last;
        o = c.change(o, c.slots[1].id, field.key, field.options[1].value);
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: OverlayAppearanceConfigurationPanel(
                  configuration: c,
                  options: o,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(c.title.zhCN), findsOneWidget);
        final groups = c.slots.map((s) => s.group.zhCN).toSet();
        if (groups.length > 1) {
          final other = find.text(groups.last);
          await tester.ensureVisible(other);
          await tester.tap(other);
          await tester.pumpAndSettle();
        }
        expect(
          find.byType(StarBridgeSelectField<int>),
          findsNWidgets(
            c.slots.length +
                c.fields.length +
                c.slots[0].choices[1].fields.length +
                c.slots[1].choices[0].fields.length,
          ),
        );
        expect(tester.takeException(), isNull);
        final output =
            Platform.environment['STARBRIDGE_APPEARANCE_CONFIGURATION_CAPTURE'];
        if (output != null) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(output).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }
}
