import '../../app/localization/app_strings.dart';

/// Physical key positions in key units, US layout. Written by hand from the
/// common arrangements; brands differ in the smaller sizes.
enum KeyBindingsKeyboardSize { full, tkl, p75, p65, p60 }

final class KeyCapSpec {
  const KeyCapSpec(
    this.token,
    this.x,
    this.y, [
    this.width = 1,
    this.height = 1,
  ]);
  final String token;
  final double x, y, width, height;
}

final class KeyboardLayout {
  KeyboardLayout(this.keys)
    : width = keys.map((k) => k.x + k.width).reduce(_max),
      height = keys.map((k) => k.y + k.height).reduce(_max),
      tokens = {for (final k in keys) k.token};
  final List<KeyCapSpec> keys;
  final double width, height;
  final Set<String> tokens;
  static double _max(double a, double b) => a > b ? a : b;
}

const _f = [
  'f1',
  'f2',
  'f3',
  'f4',
  'f5',
  'f6',
  'f7',
  'f8',
  'f9',
  'f10',
  'f11',
  'f12',
];
const _n = [
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  '0',
  'minus',
  'equals',
];
const _r2 = [
  'q',
  'w',
  'e',
  'r',
  't',
  'y',
  'u',
  'i',
  'o',
  'p',
  'lbracket',
  'rbracket',
];
const _r3 = [
  'a',
  's',
  'd',
  'f',
  'g',
  'h',
  'j',
  'k',
  'l',
  'semicolon',
  'apostrophe',
];
const _r4 = ['z', 'x', 'c', 'v', 'b', 'n', 'm', 'comma', 'period', 'slash'];

List<KeyCapSpec> _row(double y, double x, List<Object> items) {
  final out = <KeyCapSpec>[];
  var at = x;
  for (final item in items) {
    final (token, width) = item is (String, double)
        ? item
        : (item as String, 1.0);
    out.add(KeyCapSpec(token, at, y, width));
    at += width;
  }
  return out;
}

List<KeyCapSpec> _main60(double y) => [
  ..._row(y, 0, ['grave', ..._n, ('backspace', 2.0)]),
  ..._row(y + 1, 0, [('tab', 1.5), ..._r2, ('backslash', 1.5)]),
  ..._row(y + 2, 0, [('capslock', 1.75), ..._r3, ('enter', 2.25)]),
  ..._row(y + 3, 0, [('lshift', 2.25), ..._r4, ('rshift', 2.75)]),
  ..._row(y + 4, 0, [
    ('lctrl', 1.25),
    ('lwin', 1.25),
    ('lalt', 1.25),
    ('space', 6.25),
    ('ralt', 1.25),
    ('rwin', 1.25),
    ('apps', 1.25),
    ('rctrl', 1.25),
  ]),
];

List<KeyCapSpec> _functionRow() => [
  ..._row(0, 0, ['escape']),
  ..._row(0, 2, _f.sublist(0, 4)),
  ..._row(0, 6.5, _f.sublist(4, 8)),
  ..._row(0, 11, _f.sublist(8)),
  ..._row(0, 15.5, ['print', 'scrolllock', 'pause']),
];

List<KeyCapSpec> _navigation(double x, double y) => [
  ..._row(y, x, ['insert', 'home', 'pgup']),
  ..._row(y + 1, x, ['delete', 'end', 'pgdn']),
  ..._row(y + 3, x + 1, ['up']),
  ..._row(y + 4, x, ['left', 'down', 'right']),
];

List<KeyCapSpec> _bottom75(double y) => _row(y, 0, [
  ('lctrl', 1.25),
  ('lwin', 1.25),
  ('lalt', 1.25),
  ('space', 6.25),
  'ralt',
  'fn',
  'rctrl',
  'left',
  'down',
  'right',
]);

final Map<KeyBindingsKeyboardSize, KeyboardLayout> keyboardLayouts = {
  KeyBindingsKeyboardSize.full: KeyboardLayout([
    ..._functionRow(),
    ..._main60(1.25),
    ..._navigation(15.5, 1.25),
    ..._row(1.25, 19, ['numlock', 'np_divide', 'np_multiply', 'np_subtract']),
    ..._row(2.25, 19, ['np_7', 'np_8', 'np_9']),
    ..._row(3.25, 19, ['np_4', 'np_5', 'np_6']),
    ..._row(4.25, 19, ['np_1', 'np_2', 'np_3']),
    ..._row(5.25, 19, [('np_0', 2.0), 'np_period']),
    const KeyCapSpec('np_add', 22, 2.25, 1, 2),
    const KeyCapSpec('np_enter', 22, 4.25, 1, 2),
  ]),
  KeyBindingsKeyboardSize.tkl: KeyboardLayout([
    ..._functionRow(),
    ..._main60(1.25),
    ..._navigation(15.5, 1.25),
  ]),
  KeyBindingsKeyboardSize.p75: KeyboardLayout([
    ..._row(0, 0, ['escape', ..._f, 'print', 'pause', 'delete']),
    ..._row(1, 0, ['grave', ..._n, ('backspace', 2.0), 'home']),
    ..._row(2, 0, [('tab', 1.5), ..._r2, ('backslash', 1.5), 'pgup']),
    ..._row(3, 0, [('capslock', 1.75), ..._r3, ('enter', 2.25), 'pgdn']),
    ..._row(4, 0, [('lshift', 2.25), ..._r4, ('rshift', 1.75), 'up', 'end']),
    ..._bottom75(5),
  ]),
  KeyBindingsKeyboardSize.p65: KeyboardLayout([
    ..._row(0, 0, ['grave', ..._n, ('backspace', 2.0), 'delete']),
    ..._row(1, 0, [('tab', 1.5), ..._r2, ('backslash', 1.5), 'pgup']),
    ..._row(2, 0, [('capslock', 1.75), ..._r3, ('enter', 2.25), 'pgdn']),
    ..._row(3, 0, [('lshift', 2.25), ..._r4, ('rshift', 1.75), 'up', 'end']),
    ..._bottom75(4),
  ]),
  KeyBindingsKeyboardSize.p60: KeyboardLayout(_main60(0)),
};

/// A key's size class: what the page chooses when the player has not chosen.
KeyBindingsKeyboardSize defaultKeyboardSize(double contentWidth) {
  for (final size in KeyBindingsKeyboardSize.values) {
    if (contentWidth / keyboardLayouts[size]!.width >= 56) return size;
  }
  return KeyBindingsKeyboardSize.p60;
}

const _sameEverywhere = <String, String>{
  'escape': 'Esc',
  'grave': '`',
  'minus': '-',
  'equals': '=',
  'tab': 'Tab',
  'lbracket': '[',
  'rbracket': ']',
  'backslash': r'\',
  'capslock': 'Caps',
  'semicolon': ';',
  'apostrophe': "'",
  'comma': ',',
  'period': '.',
  'slash': '/',
  'lwin': 'Win',
  'rwin': 'Win',
  'print': 'PrtSc',
  'scrolllock': 'ScrLk',
  'pause': 'Pause',
  'insert': 'Ins',
  'delete': 'Del',
  'home': 'Home',
  'end': 'End',
  'pgup': 'PgUp',
  'pgdn': 'PgDn',
  'up': '↑',
  'down': '↓',
  'left': '←',
  'right': '→',
  'numlock': 'Num',
  'np_divide': '/',
  'np_multiply': '*',
  'np_subtract': '-',
  'np_add': '+',
  'np_period': '.',
  'fn': 'Fn',
};

/// What is printed on the key: short, because it sits above the action's name.
String keyCapLegend(AppStrings strings, String token) {
  if (_sameEverywhere[token] case final same?) return same;
  if (const {
    'backspace',
    'enter',
    'space',
    'apps',
    'lalt',
    'ralt',
    'lctrl',
    'rctrl',
    'lshift',
    'rshift',
    'np_enter',
  }.contains(token)) {
    return strings.text('keyBindings.cap.$token');
  }
  if (token.startsWith('np_')) return token.substring(3);
  return token.toUpperCase();
}
