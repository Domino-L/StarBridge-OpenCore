import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/help_support_strings.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/tools/key_bindings_labels.dart';
import 'package:starbridge_flutter/features/tools/key_bindings_caps.dart';
import 'package:starbridge_flutter/features/tools/key_bindings_layouts.dart';
import 'package:starbridge_flutter/features/tools/key_bindings_names.dart';
import 'package:starbridge_flutter/features/tools/key_bindings_page.dart';
import 'package:starbridge_flutter/features/tools/key_bindings_port.dart';
import 'package:starbridge_flutter/features/tools/key_bindings_split.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import '../friends/social_layout_test.dart' show app;

Finder inList(Finder finder) => find.descendant(
  of: find.byKey(const Key('key-bindings-list')),
  matching: finder,
);

var _nextKey = 0;
KeyBindingEntry _k() => KeyBindingEntry(
  device: 'keyboardMouse',
  instance: 1,
  input: const [
    'f1',
    'f2',
    'f3',
    'f4',
    'f5',
    'f6',
    'f7',
    'f9',
    'f10',
    'f11',
  ][_nextKey++ % 10],
  customized: false,
);

const _changed = KeyBindingEntry(
  device: 'keyboardMouse',
  instance: 1,
  input: 'lalt+f8',
  customized: true,
);
const _official = KeyBindingsSnapshot(
  state: 'ok',
  channel: 'LIVE',
  path: r'G:\StarCitizen\LIVE\user\client\0\Profiles\default\actionmaps.xml',
  defaultsVersion: '4.10.196.36804',
  maps: [
    KeyBindingMap('spaceship_general', [
      KeyBindingAction('v_toggle_all_doors', [_changed]),
      KeyBindingAction('v_untranslated', [
        KeyBindingEntry(
          device: 'joystick',
          instance: 1,
          input: 'button3',
          customized: false,
        ),
      ]),
      KeyBindingAction('v_no_key', []),
    ]),
    KeyBindingMap('player_emotes', [
      KeyBindingAction('emote_cs_no', [
        KeyBindingEntry(
          device: 'keyboardMouse',
          instance: 1,
          input: 'lalt+o',
          customized: true,
        ),
      ]),
    ]),
  ],
);

final class _HeldPort implements KeyBindingsPort {
  _HeldPort(this.answer);
  final Future<KeyBindingsSnapshot> answer;
  final saved = <KeyBindingsView>[];
  @override
  Future<void> saveView(KeyBindingsView view) async => saved.add(view);
  @override
  Future<KeyBindingsSnapshot> read(
    String channel,
    String language, {
    String? localization,
  }) => answer;
}

final class _Port implements KeyBindingsPort {
  _Port(this.result);
  KeyBindingsSnapshot Function(String channel) result;
  final reads = <String>[];
  final languages = <String>[];
  final localizations = <String?>[];
  final saved = <KeyBindingsView>[];
  @override
  Future<void> saveView(KeyBindingsView view) async => saved.add(view);
  @override
  Future<KeyBindingsSnapshot> read(
    String channel,
    String language, {
    String? localization,
  }) async {
    reads.add(channel);
    languages.add(language);
    localizations.add(localization);
    return result(channel);
  }
}

/// Under the list to the window's bottom: the page padding when the list reaches it.
double _bottomGap(WidgetTester tester, Size window) =>
    window.height -
    tester.getRect(find.byKey(const Key('key-bindings-list'))).bottom;

/// The list's bar with the gap under it, as laid out: the saved height counts it, and
/// the page measures it (it wraps with the width), so it is not a fixed 56.
double _chrome(WidgetTester tester) =>
    tester.getRect(find.byKey(const Key('key-bindings-list'))).top -
    tester
        .getRect(
          find
              .ancestor(
                of: find.byKey(const Key('key-bindings-help')),
                matching: find.byType(KeyBindingsMeasured),
              )
              .first,
        )
        .top;

/// How far the whole page could scroll (0: it all fits the window).
double _pageScroll(WidgetTester tester) =>
    _pageScrollPosition(tester).maxScrollExtent;

ScrollPosition _pageScrollPosition(WidgetTester tester) => tester
    .stateList<ScrollableState>(
      find.descendant(
        of: find.byType(KeyBindingsPage),
        matching: find.byType(Scrollable),
      ),
    )
    .first
    .position;

Future<void> _pump(
  WidgetTester tester,
  KeyBindingsPort? port, {
  Future<Set<String>> Function()? shortcuts,
  Size size = const Size(1200, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    app(KeyBindingsPage(port: port, shortcuts: shortcuts)),
  );
  await tester.pumpAndSettle();
}

Future<void> _clear(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  group('labels', () {
    final strings = AppStrings.resolve(const Locale('zh', 'CN'));
    String label(KeyBindingEntry binding) => keyBindingLabel(strings, binding);
    KeyBindingEntry entry(
      String device,
      String input, {
      int instance = 1,
      int? multiTap,
      String? mode,
    }) => KeyBindingEntry(
      device: device,
      instance: instance,
      input: input,
      customized: false,
      multiTap: multiTap,
      mode: mode,
    );

    test('say each key in words', () {
      expect(label(entry('keyboardMouse', 'lalt+f8')), '左 Alt + F8');
      expect(label(entry('keyboardMouse', 'mouse5')), '鼠标按键 5');
      expect(label(entry('keyboardMouse', 'mouse1')), '鼠标左键');
      expect(label(entry('joystick', 'button3')), '摇杆 1：按钮 3');
      expect(label(entry('joystick', 'hat1_up', instance: 2)), '摇杆 2：苦力帽 1 上');
      expect(label(entry('gamepad', 'b', multiTap: 2)), '手柄：B，双击');
      expect(label(entry('gamepad', 'a', mode: 'delayed_press')), '手柄：A，长按');
      expect(label(entry('keyboardMouse', '')), '已清除绑定');
      expect(label(entry('joystick', '')), '摇杆 1：已清除绑定');
    });

    test('never guess at an input they do not know', () {
      expect(label(entry('unknown', 'zz9_what')), 'zz9_what');
      expect(label(entry('keyboardMouse', 'newkey_x')), 'newkey_x');
      expect(label(entry('joystick', 'strange_axis')), '摇杆 1：strange_axis');
    });

    test('match a shortcut whichever side the modifier is on', () {
      expect(shortcutChord('lalt+o'), shortcutChord('Alt+O'));
      expect(shortcutChord('o+ralt'), shortcutChord('Alt+O'));
      expect(shortcutChord('lctrl+lalt+y'), shortcutChord('Ctrl+Alt+Y'));
      expect(
        matchingShortcut(entry('keyboardMouse', 'lalt+o'), {'Alt+O'}),
        'Alt+O',
      );
      expect(matchingShortcut(entry('keyboardMouse', 'o'), {'Alt+O'}), isNull);
      expect(matchingShortcut(entry('joystick', 'lalt+o'), {'Alt+O'}), isNull);
      expect(
        matchingShortcut(entry('keyboardMouse', 'lalt+o', instance: 2), {
          'Alt+O',
        }),
        isNull,
      );
      expect(matchingShortcut(entry('keyboardMouse', ''), {''}), isNull);
    });
  });

  group('wire', () {
    Map<String, Object?> payload() => {
      'schemaVersion': 1,
      'state': 'ok',
      'channel': 'LIVE',
      'namesState': 'unused',
      'namesPath': null,
      'path': r'G:\x\actionmaps.xml',
      'modifiedAtUtc': '2026-11-01T02:34:23Z',
      'defaultsVersion': null,
      'maps': [
        {
          'name': 'a',
          'actions': [
            {
              'name': 'b',
              'bindings': [
                {
                  'device': 'keyboardMouse',
                  'instance': 1,
                  'input': 'f8',
                  'customized': true,
                  'multiTap': null,
                  'mode': null,
                },
              ],
            },
          ],
        },
      ],
    };

    test('reads the Host answer', () {
      final snapshot = BridgeKeyBindings.parseKeyBindings(payload(), 'LIVE');
      expect(snapshot.defaultsVersion, isNull);
      expect(snapshot.modifiedAt, DateTime.utc(2026, 11, 1, 2, 34, 23));
      expect(snapshot.maps.single.actions.single.customized, isTrue);
    });

    test('rejects an answer for the other version or of another shape', () {
      expect(
        () => BridgeKeyBindings.parseKeyBindings(payload(), 'PTU'),
        throwsA(isA<BridgeFormatException>()),
      );
      for (final change in <Map<String, Object?>>[
        {'schemaVersion': 2},
        {'state': 'secret'},
        {'maps': 'x'},
        {'modifiedAtUtc': 'soon'},
        {
          'maps': [
            {'name': 'a', 'actions': 1},
          ],
        },
      ]) {
        expect(
          () => BridgeKeyBindings.parseKeyBindings({
            ...payload(),
            ...change,
          }, 'LIVE'),
          throwsA(isA<BridgeFormatException>()),
          reason: '$change',
        );
      }
    });
  });

  testWidgets('key caps paint above an opaque page ground, as in the shell', (
    tester,
  ) async {
    // The shell lays an opaque ground over the app's Material; Ink drawn on that Material
    // would sit beneath it and leave only the text (build 63).
    const ground = Key('test-page-ground');
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => ColoredBox(
            key: ground,
            color: context.tokens.surfaces.ground.fill,
            child: KeyBindingsPage(port: _Port((_) => _official)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    void above(Finder control, String what) {
      final painter = find
          .ancestor(of: control, matching: find.byType(Material))
          .first;
      expect(
        find.ancestor(of: painter, matching: find.byKey(ground)),
        findsOneWidget,
        reason: '$what paints under the page ground',
      );
    }

    for (final token in ['q', 'f8', 'lalt']) {
      above(find.byKey(Key('key-cap-$token')), 'key $token');
    }
    above(
      find
          .descendant(
            of: find.byKey(const Key('key-bindings-list')),
            matching: find.byType(InkWell),
          )
          .first,
      'a list row',
    );
    await expectLater(
      find.byKey(ground),
      matchesGoldenFile('goldens/key_bindings_keyboard_dark.png'),
    );
    // A 60% board lists the keys it lacks under it, inked the same way.
    await tester.tap(find.byKey(const Key('key-bindings-size-p60')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('key-bindings-layer-lalt')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('key-missing-f8')), findsOneWidget);
    above(find.byKey(const Key('key-missing-f8')), 'the missing F8');
    await _clear(tester);
  });

  testWidgets('the list folds to its search line, and a search unfolds it', (
    tester,
  ) async {
    final port = _Port((_) => _official);
    await _pump(tester, port);
    expect(find.byKey(const Key('key-bindings-list')), findsOneWidget);
    await tester.tap(find.byKey(const Key('key-bindings-fold')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('key-bindings-list')), findsNothing);
    expect(find.byKey(const Key('key-bindings-search')), findsOneWidget);
    expect(port.saved.last.listOpen, isFalse);
    await tester.enterText(find.byKey(const Key('key-bindings-search')), 'F8');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('key-bindings-list')), findsOneWidget);
    await _clear(tester);
  });

  // A wide window, where the keyboard can grow past the checked size: the splitter
  // has a range there. (A narrow one holds the keyboard at the width's size: below.)
  const wide = Size(2400, 1500);

  testWidgets('the splitter answers the arrow keys and remembers the height', (
    tester,
  ) async {
    final port = _Port((_) => _official);
    await _pump(tester, port, size: wide);
    final list = tester.getSize(find.byKey(const Key('key-bindings-list')));
    await tester.tap(find.byKey(const Key('key-bindings-splitter')));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('key-bindings-list'))).height,
      closeTo(list.height + 24, .5),
    );
    expect(
      port.saved.last.listHeight,
      closeTo(list.height + _chrome(tester) + 24, 1),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      port.saved.last.listHeight,
      closeTo(list.height + _chrome(tester), 1),
    );
    await _clear(tester);
  });

  testWidgets('a drag keeps every step, within the window', (tester) async {
    final port = _Port((_) => _official);
    await _pump(tester, port, size: wide);
    final bottom = _bottomGap(tester, wide);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('key-bindings-splitter'))),
      kind: PointerDeviceKind.mouse,
    );
    // Past the slop first, so the drag has started.
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    final list = tester.getSize(find.byKey(const Key('key-bindings-list')));
    final splitter = tester.getRect(
      find.byKey(const Key('key-bindings-splitter')),
    );
    // Several moves before a frame: each one counts.
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, -10));
    }
    await tester.pump();
    await gesture.moveBy(const Offset(0, -10));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('key-bindings-list'))).height,
      closeTo(list.height + 50, 3),
    );
    // the keyboard gives up just that: the splitter stays under the pointer
    expect(
      tester.getRect(find.byKey(const Key('key-bindings-splitter'))).top,
      closeTo(splitter.top - 50, 3),
    );
    expect(
      port.saved.last.listHeight,
      closeTo(list.height + _chrome(tester) + 50, 3),
    );
    expect(_bottomGap(tester, wide), closeTo(bottom, 1));
    await _clear(tester);
  });

  // 11-15 user on b99 ("这个把手有一些问题"): dragged down far, the keyboard stopped
  // growing at the width's size and a blank band opened under the list; dragged up
  // far, the keyboard could shrink no more and the whole page scrolled.
  testWidgets('dragged to either end the list still reaches the bottom', (
    tester,
  ) async {
    final port = _Port((_) => _official);
    await _pump(tester, port, size: wide);
    final bottom = _bottomGap(tester, wide);
    expect(
      bottom,
      lessThan(40),
      reason: 'only the page padding under the list',
    );
    Future<double> drag(double by) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('key-bindings-splitter'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(Offset(0, by.sign * 20));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(Offset(0, by / 4));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      return tester.getRect(find.byKey(const Key('key-bindings-splitter'))).top;
    }

    for (final by in [1200.0, -1200.0]) {
      final end = await drag(by);
      expect(_bottomGap(tester, wide), closeTo(bottom, 1), reason: 'by $by');
      expect(
        _pageScroll(tester),
        0,
        reason: 'by $by: the page does not scroll',
      );
      expect(
        port.saved.last.listHeight,
        closeTo(
          tester.getSize(find.byKey(const Key('key-bindings-list'))).height +
              _chrome(tester),
          1,
        ),
      );
      // at the end it stops: going on moves nothing, and coming back moves at once
      expect(await drag(by.sign * 200), closeTo(end, 1));
      expect(await drag(-by.sign * 40), closeTo(end - by.sign * 40, 3));
    }
    await _clear(tester);
  });

  testWidgets('a window resize keeps the list at the bottom', (tester) async {
    final port = _Port((_) => _official);
    await _pump(tester, port, size: wide);
    final bottom = _bottomGap(tester, wide);
    for (final size in [
      const Size(2400, 1800),
      const Size(2400, 1100),
      const Size(1200, 1600),
      wide,
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(_bottomGap(tester, size), closeTo(bottom, 1), reason: '$size');
      expect(_pageScroll(tester), 0, reason: '$size');
    }
    await _clear(tester);
  });

  // review CX-KEYBIND-SPLIT-073-R1 P2: what sits between the keyboard and the list is
  // measured, not assumed: the missing keys line, a legend wrapping on a narrow page
  testWidgets('measured parts keep the list at the bottom', (tester) async {
    final port = _Port((_) => _official);
    await _pump(tester, port, size: wide);
    final bottom = _bottomGap(tester, wide);
    await tester.tap(find.byKey(const Key('key-bindings-size-p60')));
    await tester.pumpAndSettle();
    expect(_bottomGap(tester, wide), closeTo(bottom, 1), reason: 'p60');
    expect(_pageScroll(tester), 0, reason: 'p60');
    for (final size in [const Size(900, 1400), const Size(1400, 1200)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(_bottomGap(tester, size), closeTo(bottom, 1), reason: '$size');
      expect(_pageScroll(tester), 0, reason: '$size');
    }
    await _clear(tester);
  });

  // review P3: the remembered height is the one wished for; a window that cannot give
  // it only changes what shows, and saving something else keeps the wish
  testWidgets('a remembered height is kept as wished', (tester) async {
    final port = _Port(
      (_) => KeyBindingsSnapshot(
        state: 'ok',
        channel: 'LIVE',
        path: _official.path,
        defaultsVersion: _official.defaultsVersion,
        maps: _official.maps,
        view: const KeyBindingsView(
          keyboard: 'full',
          mouse: 'many',
          listHeight: 160,
          listOpen: true,
          notesOpen: false,
        ),
      ),
    );
    await _pump(tester, port, size: wide);
    expect(
      tester.getSize(find.byKey(const Key('key-bindings-list'))).height,
      greaterThan(160),
      reason: 'the list fills what the keyboard leaves',
    );
    expect(_pageScroll(tester), 0);
    await tester.tap(find.byKey(const Key('key-bindings-help')));
    await tester.pumpAndSettle();
    expect(port.saved.last.listHeight, 160);
    await _clear(tester);
  });

  testWidgets('a layout change keeps the width choosing the keyboard', (
    tester,
  ) async {
    final port = _Port((_) => _official);
    await _pump(tester, port);
    await tester.tap(find.byKey(const Key('key-bindings-fold')));
    await tester.pumpAndSettle();
    expect(port.saved.last.keyboard, isNull);
    expect(port.saved.last.listOpen, isFalse);
    // The notes sit beside the list, so asking for them brings it back.
    await tester.tap(find.byKey(const Key('key-bindings-help')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('key-bindings-list')), findsOneWidget);
    expect(find.byKey(const Key('key-bindings-file')), findsOneWidget);
    await _clear(tester);
  });

  testWidgets('nothing is saved over the remembered view before it arrives', (
    tester,
  ) async {
    final answer = Completer<KeyBindingsSnapshot>();
    final port = _HeldPort(answer.future);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(KeyBindingsPage(port: port)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('key-bindings-fold')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('key-bindings-size-p60')));
    await tester.pump();
    expect(port.saved, isEmpty);
    answer.complete(
      KeyBindingsSnapshot(
        state: 'ok',
        channel: 'LIVE',
        path: _official.path,
        defaultsVersion: '1',
        maps: _official.maps,
        view: const KeyBindingsView(
          keyboard: 'tkl',
          mouse: 'many',
          listHeight: 600,
          listOpen: true,
          notesOpen: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // What was chosen while it read stays; the rest comes from the file.
    expect(find.byKey(const Key('key-bindings-list')), findsNothing);
    expect(find.byKey(const Key('key-cap-f12')), findsNothing);
    expect(port.saved, hasLength(1));
    final saved = port.saved.single;
    expect(saved.keyboard, 'p60');
    expect(saved.listOpen, isFalse);
    expect(saved.mouse, 'many');
    expect(saved.listHeight, 600);
    expect(saved.notesOpen, isTrue);
    await _clear(tester);
  });

  testWidgets('an opened key keeps its panel size on a scaled keyboard', (
    tester,
  ) async {
    await _pump(tester, _Port((_) => _official));
    await tester.tap(find.byKey(const Key('key-bindings-size-p60')));
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('key-bindings-key-panel'));
    void drawnAtOwnSize(String what) {
      expect(
        tester.getRect(panel).width,
        closeTo(tester.getSize(panel).width, 1),
        reason: what,
      );
    }

    // 1152 wide over 15 keys: past the checked size, so the board is scaled.
    await tester.tap(find.byKey(const Key('key-cap-o')));
    await tester.pumpAndSettle();
    drawnAtOwnSize('a key on the board');
    await tester.tap(find.byKey(const Key('key-bindings-layer-lalt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('key-missing-f8')));
    await tester.pumpAndSettle();
    drawnAtOwnSize('a key the board lacks');
    await _clear(tester);
  });

  testWidgets('hover hints wait while a key is opened', (tester) async {
    await _pump(tester, _Port((_) => _official));
    final bubble = find.byWidgetPredicate(
      (w) =>
          w.runtimeType.toString() == '_Bubble' &&
          ((w as dynamic).message as String).isNotEmpty,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    Future<void> hover(String token) async {
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 50));
      await mouse.moveTo(tester.getCenter(find.byKey(Key('key-cap-$token'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    // On the Alt layer F8 carries a hint; O opens a panel of its own.
    await tester.tap(find.byKey(const Key('key-bindings-layer-lalt')));
    await tester.pumpAndSettle();
    await hover('f8');
    expect(bubble, findsOneWidget, reason: 'a bound key shows its hint');
    await tester.tap(find.byKey(const Key('key-cap-o')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('key-bindings-key-panel')), findsOneWidget);
    expect(bubble, findsNothing, reason: 'the opened key shows no hint');
    await hover('f8');
    expect(bubble, findsNothing, reason: 'nor does another key under it');
    await tester.tap(find.byKey(const Key('key-cap-o')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('key-bindings-key-panel')), findsNothing);
    await hover('f8');
    expect(bubble, findsOneWidget, reason: 'hints come back once it closes');
    await mouse.removePointer();
    await _clear(tester);
  });

  testWidgets('a remembered layout comes back folded as it was left', (
    tester,
  ) async {
    await _pump(
      tester,
      _Port(
        (_) => KeyBindingsSnapshot(
          state: 'ok',
          channel: 'LIVE',
          path: _official.path,
          defaultsVersion: '1',
          maps: _official.maps,
          view: const KeyBindingsView(
            keyboard: 'tkl',
            mouse: 'standard',
            listOpen: false,
            notesOpen: true,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('key-bindings-list')), findsNothing);
    await tester.tap(find.byKey(const Key('key-bindings-fold')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('key-bindings-file')), findsOneWidget);
    await _clear(tester);
  });

  testWidgets('a narrow keyboard grows with the room; a wide one stays', (
    tester,
  ) async {
    await _pump(tester, _Port((_) => _official));
    final wide = tester.getSize(find.byKey(const Key('key-bindings-keyboard')));
    await tester.tap(find.byKey(const Key('key-bindings-size-p60')));
    await tester.pumpAndSettle();
    // Laid out at the checked size and scaled: the drawn board is wider than that.
    final board = find.byType(KeyBindingsScaledKeyboard);
    expect(
      tester.getSize(board).width,
      greaterThan(
        tester.getSize(find.byKey(const Key('key-bindings-keyboard'))).width,
      ),
    );
    expect(wide.width, lessThanOrEqualTo(1200));
    await _clear(tester);
  });

  testWidgets('names come in a language installed with the game', (
    tester,
  ) async {
    late final _Port port;
    port = _Port(
      (_) => KeyBindingsSnapshot(
        state: 'ok',
        channel: 'LIVE',
        defaultsVersion: '1',
        maps: _official.maps,
        localizations: const ['chinese_(simplified)', 'japanese_(japan)'],
        localization: 'chinese_(simplified)',
        localizationFallback:
            port.localizations.lastOrNull == 'korean_(south_korea)',
        view: const KeyBindingsView(
          keyboard: 'tkl',
          mouse: 'standard',
          localization: 'korean_(south_korea)',
        ),
      ),
    );
    await _pump(tester, port);
    expect(find.byKey(const Key('key-bindings-localization')), findsOneWidget);
    expect(port.localizations, [null, 'korean_(south_korea)']);
    expect(
      find.byKey(const Key('key-bindings-localization-missing')),
      findsOneWidget,
    );
    expect(find.textContaining('没有装 한국어'), findsOneWidget);
    await _clear(tester);
  });

  testWidgets(
    'the release players know is shown, the build sits in the notes',
    (tester) async {
      await _pump(
        tester,
        _Port(
          (_) => KeyBindingsSnapshot(
            state: 'ok',
            channel: 'LIVE',
            path: 'G:/x/actionmaps.xml',
            defaultsVersion: '4.10.196.36804',
            defaultsRelease: '4.10.2',
            maps: _official.maps,
          ),
        ),
      );
      expect(find.textContaining('默认按键基于游戏 4.10.2。'), findsOneWidget);
      // The notes, with the file, start folded.
      expect(find.byKey(const Key('key-bindings-file')), findsNothing);
      await tester.tap(find.byKey(const Key('key-bindings-help')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SelectableText>(find.byKey(const Key('key-bindings-file')))
            .data,
        contains('4.10.196.36804'),
      );
      await _clear(tester);
    },
  );

  testWidgets('official build shows every key and marks what changed', (
    tester,
  ) async {
    final port = _Port((_) => _official);
    await _pump(tester, port);
    expect(port.reads, ['LIVE']);
    expect(find.textContaining('默认按键基于游戏 4.10.196.36804'), findsOneWidget);
    expect(inList(find.text('开关所有舱门')), findsOneWidget);
    expect(inList(find.text('左 Alt + F8（已改）')), findsOneWidget);
    await tester.tap(find.byKey(const Key('key-bindings-device-stick')));
    await tester.pumpAndSettle();
    expect(inList(find.text('暂无中文名')), findsOneWidget);
    expect(inList(find.text('v_untranslated')), findsOneWidget);
    await tester.tap(find.byKey(const Key('key-bindings-help')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('key-bindings-file')))
          .data,
      contains('actionmaps.xml'),
    );
    await _clear(tester);
  });

  testWidgets(
    'search finds an action by name or key, and says when it cannot',
    (tester) async {
      await _pump(tester, _Port((_) => _official));
      final search = find.byKey(const Key('key-bindings-search'));
      await tester.enterText(search, 'Alt + F8');
      await tester.pump();
      expect(inList(find.text('开关所有舱门')), findsOneWidget);
      expect(inList(find.text('表情：否定')), findsNothing);
      await tester.enterText(search, 'alt+o');
      await tester.pump();
      expect(inList(find.text('表情：否定')), findsOneWidget);
      expect(inList(find.text('开关所有舱门')), findsNothing);
      await tester.enterText(search, '舱门');
      await tester.pump();
      expect(inList(find.text('开关所有舱门')), findsOneWidget);
      await tester.enterText(search, '找不到的词');
      await tester.pump();
      expect(find.byKey(const Key('key-bindings-no-match')), findsOneWidget);
      await _clear(tester);
    },
  );

  testWidgets('only-changed leaves defaults out', (tester) async {
    await _pump(tester, _Port((_) => _official));
    await tester.tap(find.text('只看我改过的'));
    await tester.pumpAndSettle();
    expect(inList(find.text('v_untranslated')), findsNothing);
    expect(inList(find.text('v_no_key')), findsNothing);
    expect(inList(find.text('开关所有舱门')), findsOneWidget);
    await _clear(tester);
  });

  testWidgets('a shared shortcut gets one line saying both may respond', (
    tester,
  ) async {
    await _pump(
      tester,
      _Port((_) => _official),
      shortcuts: () async => {'Alt+O', 'Alt+M'},
    );
    await tester.tap(find.byKey(const Key('key-bindings-scene-social')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('key-bindings-layer-lalt')));
    await tester.pumpAndSettle();
    expect(find.text('已改'), findsWidgets);
    await tester.tap(find.byKey(const Key('key-cap-o')));
    await tester.pumpAndSettle();
    expect(find.textContaining('星海舰桥也用 Alt+O'), findsOneWidget);
    expect(find.textContaining('两边都可能响应'), findsOneWidget);
    await _clear(tester);
  });

  testWidgets('a failed shortcut read does not touch the list', (tester) async {
    await _pump(
      tester,
      _Port((_) => _official),
      shortcuts: () async => throw StateError('no'),
    );
    expect(inList(find.text('开关所有舱门')), findsOneWidget);
    await _clear(tester);
  });

  testWidgets(
    'public build says only changed keys are listed, with no filter',
    (tester) async {
      await _pump(
        tester,
        _Port(
          (_) => const KeyBindingsSnapshot(
            state: 'ok',
            channel: 'LIVE',
            maps: [
              KeyBindingMap('spaceship_general', [
                KeyBindingAction('v_toggle_all_doors', [_changed]),
              ]),
            ],
          ),
        ),
      );
      expect(find.textContaining('这里只有你改过的按键'), findsOneWidget);
      expect(find.textContaining('默认按键基于'), findsNothing);
      expect(find.byKey(const Key('key-bindings-only-changed')), findsNothing);
      await _clear(tester);
    },
  );

  testWidgets('versions read apart, and another version warns about defaults', (
    tester,
  ) async {
    final port = _Port(
      (channel) => KeyBindingsSnapshot(
        state: 'ok',
        channel: channel,
        defaultsVersion: '4.10.196.36804',
        maps: _official.maps,
      ),
    );
    await _pump(tester, port);
    expect(find.textContaining('这个游戏版本的默认按键可能和这张表不同'), findsNothing);
    await tester.tap(find.text('PTU 测试版'));
    await tester.pumpAndSettle();
    expect(port.reads, ['LIVE', 'PTU']);
    expect(find.textContaining('这个游戏版本的默认按键可能和这张表不同'), findsOneWidget);
    await _clear(tester);
  });

  testWidgets('reads once on open and again only when asked', (tester) async {
    final port = _Port((_) => _official);
    await _pump(tester, port);
    await tester.pump(const Duration(minutes: 5));
    expect(port.reads, ['LIVE'], reason: 'nothing polls');
    await tester.tap(find.byKey(const Key('key-bindings-reload')));
    await tester.pumpAndSettle();
    expect(port.reads, ['LIVE', 'LIVE']);
    await _clear(tester);
  });

  for (final (state, version, text) in const [
    ('notInstalled', null, '没找到这个游戏版本的文件夹'),
    ('multiple', null, '找到了多个安装位置'),
    ('unreadable', null, '读不了按键文件'),
    ('format', null, '看不懂这个文件的内容'),
    ('noFile', null, '没找到按键文件。'),
    ('noFile', '4.10.196.36804', '下面是默认按键'),
    ('ok', null, '这个文件里没有改过的按键'),
  ]) {
    testWidgets('$state says so in words ($version)', (tester) async {
      await _pump(
        tester,
        _Port(
          (_) => KeyBindingsSnapshot(
            state: state,
            channel: 'LIVE',
            defaultsVersion: version,
          ),
        ),
      );
      expect(find.byKey(const Key('key-bindings-state')), findsOneWidget);
      expect(find.textContaining(text), findsOneWidget);
      await _clear(tester);
    });
  }

  testWidgets('a failed read says so, and reading again recovers', (
    tester,
  ) async {
    var fail = true;
    final port = _Port((_) {
      if (fail) throw StateError('no');
      return _official;
    });
    await _pump(tester, port);
    expect(find.byKey(const Key('key-bindings-failed')), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('key-bindings-reload')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('key-bindings-failed')), findsNothing);
    expect(inList(find.text('开关所有舱门')), findsOneWidget);
    await _clear(tester);
  });

  testWidgets('without the Host route the page says it cannot read', (
    tester,
  ) async {
    await _pump(tester, null);
    expect(find.textContaining('当前无法读取按键'), findsOneWidget);
    await _clear(tester);
  });

  testWidgets(
    'a late answer for the old version does not replace the new one',
    (tester) async {
      final first = Completer<KeyBindingsSnapshot>();
      final port = _LatePort(first);
      await _pump(tester, port);
      await tester.tap(find.text('PTU 测试版'));
      await tester.pumpAndSettle();
      first.complete(_official);
      await tester.pumpAndSettle();
      expect(inList(find.text('开关所有舱门')), findsNothing);
      await _clear(tester);
    },
  );

  group('names', () {
    final withPlayerNames = KeyBindingsSnapshot(
      state: 'ok',
      channel: 'LIVE',
      defaultsVersion: '1.2.3.4',
      namesState: 'ok',
      namesPath:
          r'G:\SC\LIVE\data\Localization\chinese_(simplified)\global.ini',
      maps: [
        KeyBindingMap('spaceship_general', [
          // The game gives these two the same label.
          KeyBindingAction('attack1', [_k()], localizedName: '武器 - 攻击'),
          KeyBindingAction('consume', [_k()], localizedName: '武器 - 攻击'),
          KeyBindingAction('v_no_own_a', [_k()], localizedName: '同名'),
          KeyBindingAction('v_no_own_b', [_k()], localizedName: '同名'),
          KeyBindingAction('v_toggle_all_doors', [
            _k(),
          ], localizedName: '玩家文件的舱门'),
          KeyBindingAction('v_starmap', [_k()]),
          KeyBindingAction('v_no_name_anywhere', [_k()]),
        ], localizedName: '徒步 - 通用'),
      ],
    );

    testWidgets('the player file wins, then our own, then the original', (
      tester,
    ) async {
      await _pump(tester, _Port((_) => withPlayerNames));
      expect(inList(find.text('玩家文件的舱门')), findsOneWidget);
      expect(inList(find.text('开关所有舱门')), findsNothing);
      expect(inList(find.text('打开星图')), findsOneWidget);
      expect(inList(find.text('徒步 - 通用')), findsOneWidget);
      expect(inList(find.text('v_no_name_anywhere')), findsOneWidget);
      expect(inList(find.text('暂无中文名')), findsOneWidget);
      expect(find.textContaining('操作名来自你游戏文件夹里的本地化文件'), findsOneWidget);
      await _clear(tester);
    });

    testWidgets('a label two actions share prefers our own name', (
      tester,
    ) async {
      await _pump(tester, _Port((_) => withPlayerNames));
      expect(inList(find.text('武器 - 攻击')), findsNothing);
      expect(inList(find.text('攻击或开火')), findsOneWidget);
      expect(inList(find.text('使用物品')), findsOneWidget);
      expect(inList(find.text('同名')), findsNWidgets(2));
      expect(inList(find.text('v_no_own_a')), findsOneWidget);
      await _clear(tester);
    });

    testWidgets('search finds the player names', (tester) async {
      await _pump(tester, _Port((_) => withPlayerNames));
      await tester.enterText(
        find.byKey(const Key('key-bindings-search')),
        '玩家文件',
      );
      await tester.pump();
      expect(inList(find.text('玩家文件的舱门')), findsOneWidget);
      expect(inList(find.text('打开星图')), findsNothing);
      await _clear(tester);
    });

    testWidgets('without the file the page says the names are ours', (
      tester,
    ) async {
      for (final state in const ['missing', 'unreadable']) {
        await _pump(
          tester,
          _Port(
            (_) => KeyBindingsSnapshot(
              state: 'ok',
              channel: 'LIVE',
              defaultsVersion: '1',
              namesState: state,
              maps: _official.maps,
            ),
          ),
        );
        expect(find.textContaining('操作名是星海舰桥自己写的'), findsOneWidget);
        expect(find.textContaining('操作名来自你游戏'), findsNothing);
        expect(inList(find.text('开关所有舱门')), findsOneWidget);
        await _clear(tester);
      }
    });

    test('the interface language picks the file, and our names fill gaps', () {
      for (final (locale, language) in const [
        (Locale('zh', 'CN'), 'zh-Hans'),
        (Locale('zh', 'TW'), 'zh-Hant'),
        (Locale('en', 'US'), 'en'),
      ]) {
        expect(keyBindingLanguage(AppStrings.resolve(locale)), language);
      }
      final actions = [
        const KeyBindingAction(
          'v_toggle_all_doors',
          [],
          localizedName: 'Doors',
        ),
        const KeyBindingAction('v_starmap', []),
      ];
      final names = keyBindingActionNames(
        AppStrings.resolve(const Locale('en', 'US')),
        actions,
      );
      expect(names['v_toggle_all_doors'], 'Doors');
      expect(names['v_starmap'], 'Open star map');
    });

    testWidgets(
      'the page asks for its interface language and names bundled text',
      (tester) async {
        final port = _Port(
          (_) => KeyBindingsSnapshot(
            state: 'ok',
            channel: 'LIVE',
            defaultsVersion: '1.2.3.4',
            namesState: 'bundled',
            maps: [
              KeyBindingMap('spaceship_general', [
                KeyBindingAction('a', [_k()], localizedName: 'Bundled name'),
              ]),
            ],
          ),
        );
        await _pump(tester, port);
        expect(port.languages, ['zh-Hans']);
        expect(inList(find.text('Bundled name')), findsOneWidget);
        expect(find.textContaining('游戏版本 1.2.3.4 的英文名称'), findsOneWidget);
        await _clear(tester);
      },
    );

    test('the wire carries names and rejects a wrong shape', () {
      final parsed = BridgeKeyBindings.parseKeyBindings({
        'schemaVersion': 1,
        'state': 'ok',
        'channel': 'LIVE',
        'path': null,
        'modifiedAtUtc': null,
        'defaultsVersion': '1',
        'namesState': 'ok',
        'namesPath': r'G:\x\global.ini',
        'maps': [
          {
            'name': 'm',
            'localizedName': '分类',
            'actions': [
              {'name': 'a', 'localizedName': '操作', 'bindings': const []},
            ],
          },
        ],
      }, 'LIVE');
      expect(parsed.maps.single.localizedName, '分类');
      expect(parsed.maps.single.actions.single.localizedName, '操作');
      expect(
        () => BridgeKeyBindings.parseKeyBindings({
          'schemaVersion': 1,
          'state': 'ok',
          'channel': 'LIVE',
          'namesState': 'strange',
          'maps': const [],
        }, 'LIVE'),
        throwsA(isA<BridgeFormatException>()),
      );
    });
  });

  group('keyboard', () {
    testWidgets('a held modifier is a layer, and its keys say what changed', (
      tester,
    ) async {
      await _pump(tester, _Port((_) => _official));
      expect(find.byKey(const Key('key-bindings-keyboard')), findsOneWidget);
      await tester.tap(find.byKey(const Key('key-cap-lalt')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('key-cap-f8')),
          matching: find.textContaining('已改', findRichText: true),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('key-cap-f8')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('key-bindings-key-panel')), findsOneWidget);
      expect(find.text('你改过'), findsOneWidget);
      await tester.tap(find.byKey(const Key('key-bindings-panel-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('key-bindings-key-panel')), findsNothing);
      await _clear(tester);
    });

    testWidgets(
      'a chosen size is remembered, and missing keys stay reachable',
      (tester) async {
        final port = _Port((_) => _official);
        await _pump(tester, port);
        await tester.tap(find.byKey(const Key('key-bindings-size-p60')));
        await tester.pumpAndSettle();
        expect(port.saved.single.keyboard, 'p60');
        expect(find.byKey(const Key('key-cap-f8')), findsNothing);
        await tester.tap(find.byKey(const Key('key-bindings-layer-lalt')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('key-bindings-missing')), findsOneWidget);
        await tester.tap(find.byKey(const Key('key-missing-f8')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('key-bindings-key-panel')), findsOneWidget);
        await _clear(tester);
      },
    );

    testWidgets('the remembered size comes back with the first answer', (
      tester,
    ) async {
      await _pump(
        tester,
        _Port(
          (_) => KeyBindingsSnapshot(
            state: 'ok',
            channel: 'LIVE',
            defaultsVersion: '1',
            maps: _official.maps,
            view: const KeyBindingsView(keyboard: 'p65', mouse: 'many'),
          ),
        ),
      );
      expect(find.byKey(const Key('key-cap-f1')), findsNothing);
      expect(find.byKey(const Key('key-cap-grave')), findsOneWidget);
      await _clear(tester);
    });

    testWidgets('mouse, gamepad and stick draw their own stage', (
      tester,
    ) async {
      await _pump(tester, _Port((_) => _official));
      for (final (tab, stage) in const [
        ('mouse', 'mouse'),
        ('gamepad', 'gamepad'),
        ('stick', 'stick'),
      ]) {
        await tester.tap(find.byKey(Key('key-bindings-device-$tab')));
        await tester.pumpAndSettle();
        expect(find.byKey(Key('key-bindings-stage-$stage')), findsOneWidget);
      }
      await _clear(tester);
    });

    test('a key label keeps the name and drops only how it is pressed', () {
      expect(keyCapShortened('开关舱门（切换）'), '开关舱门');
      expect(keyCapShortened('Launch (hold)'), 'Launch');
      expect(keyCapShortened('（切换）'), '（切换）');
      final strings = AppStrings.resolve(const Locale('zh', 'CN'));
      expect(
        keyBindingCapLabel(strings, 'v_target_toggle_lock_index_1'),
        '锁定目标 1',
      );
      expect(
        keyBindingCapLabel(
          AppStrings.resolve(const Locale('en', 'US')),
          'v_target_toggle_lock_index_1',
        ),
        'Lock 1',
      );
      expect(keyBindingCapLabel(strings, 'not_an_action'), isNull);
    });

    test('the default size follows the room there is', () {
      expect(defaultKeyboardSize(1400), KeyBindingsKeyboardSize.full);
      expect(defaultKeyboardSize(1168), KeyBindingsKeyboardSize.tkl);
      expect(defaultKeyboardSize(500), KeyBindingsKeyboardSize.p60);
      expect(keyboardLayouts[KeyBindingsKeyboardSize.full]!.keys.length, 104);
      expect(keyboardLayouts[KeyBindingsKeyboardSize.tkl]!.keys.length, 87);
      expect(keyboardLayouts[KeyBindingsKeyboardSize.p75]!.keys.length, 84);
      expect(keyboardLayouts[KeyBindingsKeyboardSize.p65]!.keys.length, 68);
      expect(keyboardLayouts[KeyBindingsKeyboardSize.p60]!.keys.length, 61);
    });
  });

  test('the legal text names the one file and no promise', () {
    for (final strings in [helpSupportZhCn, helpSupportZhTw, helpSupportEnUs]) {
      final body = strings['help.legal.safety.body']!;
      expect(body, contains('actionmaps.xml'));
      expect(body, isNot(contains('p4k')));
      expect(body, contains(r'data\Localization'));
      expect(body, isNot(contains('chinese_(simplified)')));
    }
    expect(
      helpSupportZhCn['help.legal.safety.body'],
      isNot(contains('只读取你选择的 Game.log')),
    );
  });
}

final class _LatePort implements KeyBindingsPort {
  _LatePort(this.first);
  final Completer<KeyBindingsSnapshot> first;
  var _reads = 0;
  @override
  Future<void> saveView(KeyBindingsView view) async {}
  @override
  Future<KeyBindingsSnapshot> read(
    String channel,
    String language, {
    String? localization,
  }) => _reads++ == 0
      ? first.future
      : Future.value(
          KeyBindingsSnapshot(
            state: 'ok',
            channel: channel,
            defaultsVersion: '1',
          ),
        );
}
