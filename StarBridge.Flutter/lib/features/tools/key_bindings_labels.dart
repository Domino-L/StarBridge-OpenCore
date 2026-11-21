import '../../app/localization/app_strings.dart';
import 'key_bindings_port.dart';

/// Our own words for the game's input names. Anything unknown stays as written.
String _pick(AppStrings strings, (String, String, String) copy) {
  if (strings.locale.languageCode == 'en') return copy.$3;
  if (strings.locale.countryCode == 'TW' ||
      strings.locale.scriptCode == 'Hant') {
    return copy.$2;
  }
  return copy.$1;
}

const _keys = <String, (String, String, String)>{
  'lalt': ('左 Alt', '左 Alt', 'Left Alt'),
  'ralt': ('右 Alt', '右 Alt', 'Right Alt'),
  'lctrl': ('左 Ctrl', '左 Ctrl', 'Left Ctrl'),
  'rctrl': ('右 Ctrl', '右 Ctrl', 'Right Ctrl'),
  'lshift': ('左 Shift', '左 Shift', 'Left Shift'),
  'rshift': ('右 Shift', '右 Shift', 'Right Shift'),
  'space': ('空格', '空白鍵', 'Space'),
  'enter': ('回车', 'Enter', 'Enter'),
  'escape': ('Esc', 'Esc', 'Esc'),
  'tab': ('Tab', 'Tab', 'Tab'),
  'backspace': ('退格', '退格', 'Backspace'),
  'capslock': ('大写锁定', '大寫鎖定', 'Caps Lock'),
  'insert': ('Insert', 'Insert', 'Insert'),
  'delete': ('Delete', 'Delete', 'Delete'),
  'home': ('Home', 'Home', 'Home'),
  'end': ('End', 'End', 'End'),
  'pgup': ('Page Up', 'Page Up', 'Page Up'),
  'pgdn': ('Page Down', 'Page Down', 'Page Down'),
  'up': ('方向键上', '方向鍵上', 'Up'),
  'down': ('方向键下', '方向鍵下', 'Down'),
  'left': ('方向键左', '方向鍵左', 'Left'),
  'right': ('方向键右', '方向鍵右', 'Right'),
  'minus': ('-', '-', '-'),
  'equals': ('=', '=', '='),
  'comma': ('逗号', '逗號', 'Comma'),
  'period': ('句号', '句號', 'Period'),
  'slash': ('斜杠', '斜線', 'Slash'),
  'backslash': ('\\', '\\', '\\'),
  'semicolon': (';', ';', ';'),
  'apostrophe': ("'", "'", "'"),
  'lbracket': ('[', '[', '['),
  'rbracket': (']', ']', ']'),
  'grave': ('`', '`', '`'),
  'np_add': ('小键盘 +', '數字鍵 +', 'Numpad +'),
  'np_subtract': ('小键盘 -', '數字鍵 -', 'Numpad -'),
  'np_multiply': ('小键盘 *', '數字鍵 *', 'Numpad *'),
  'np_divide': ('小键盘 /', '數字鍵 /', 'Numpad /'),
  'np_period': ('小键盘 .', '數字鍵 .', 'Numpad .'),
  'np_enter': ('小键盘回车', '數字鍵 Enter', 'Numpad Enter'),
  'mouse1': ('鼠标左键', '滑鼠左鍵', 'Left mouse button'),
  'mouse2': ('鼠标右键', '滑鼠右鍵', 'Right mouse button'),
  'mouse3': ('鼠标中键', '滑鼠中鍵', 'Middle mouse button'),
  'mwheel_up': ('滚轮向上', '滾輪向上', 'Wheel up'),
  'mwheel_down': ('滚轮向下', '滾輪向下', 'Wheel down'),
  'maxis_x': ('鼠标横向', '滑鼠橫向', 'Mouse X'),
  'maxis_y': ('鼠标纵向', '滑鼠縱向', 'Mouse Y'),
  'maxis_z': ('滚轮轴', '滾輪軸', 'Mouse wheel axis'),
  'mouse1_2': ('鼠标左右键同按', '滑鼠左右鍵同按', 'Both mouse buttons'),
};

const _gamepad = <String, (String, String, String)>{
  'shoulderl': ('左肩键', '左肩鍵', 'Left bumper'),
  'shoulderr': ('右肩键', '右肩鍵', 'Right bumper'),
  'triggerl_btn': ('左扳机', '左扳機', 'Left trigger'),
  'triggerr_btn': ('右扳机', '右扳機', 'Right trigger'),
  'thumbl': ('按下左摇杆', '按下左搖桿', 'Left stick press'),
  'thumbl_up': ('左摇杆上', '左搖桿上', 'Left stick up'),
  'thumbl_down': ('左摇杆下', '左搖桿下', 'Left stick down'),
  'thumbl_left': ('左摇杆左', '左搖桿左', 'Left stick left'),
  'thumbl_right': ('左摇杆右', '左搖桿右', 'Left stick right'),
  'thumbr_up': ('右摇杆上', '右搖桿上', 'Right stick up'),
  'thumbr_down': ('右摇杆下', '右搖桿下', 'Right stick down'),
  'thumbr_left': ('右摇杆左', '右搖桿左', 'Right stick left'),
  'thumbr_right': ('右摇杆右', '右搖桿右', 'Right stick right'),
  'triggerl_r_btn': ('左右扳机同按', '左右扳機同按', 'Both triggers'),
  'thumbr': ('按下右摇杆', '按下右搖桿', 'Right stick press'),
  'thumblx': ('左摇杆横向', '左搖桿橫向', 'Left stick X'),
  'thumbly': ('左摇杆纵向', '左搖桿縱向', 'Left stick Y'),
  'thumbrx': ('右摇杆横向', '右搖桿橫向', 'Right stick X'),
  'thumbry': ('右摇杆纵向', '右搖桿縱向', 'Right stick Y'),
  'dpad_up': ('十字键上', '十字鍵上', 'D-pad up'),
  'dpad_down': ('十字键下', '十字鍵下', 'D-pad down'),
  'dpad_left': ('十字键左', '十字鍵左', 'D-pad left'),
  'dpad_right': ('十字键右', '十字鍵右', 'D-pad right'),
  'back': ('返回键', '返回鍵', 'Back'),
  'start': ('开始键', '開始鍵', 'Start'),
};

final _mouseButton = RegExp(r'^mouse(\d+)$');
final _numpadDigit = RegExp(r'^np_(\d)$');
final _function = RegExp(r'^f\d{1,2}$');
final _button = RegExp(r'^button(\d+)$');
final _hat = RegExp(r'^hat(\d+)_(up|down|left|right)$');
final _slider = RegExp(r'^slider(\d+)$');
final _rotation = RegExp(r'^rot([xyz])$');
final _axis = RegExp(r'^[xyz]$');

String _token(AppStrings strings, String device, String token) {
  final t = token.toLowerCase();
  String text(String key, [String a = '']) =>
      strings.text('keyBindings.input.$key').replaceFirst('{0}', a);
  if (device == 'gamepad') {
    if (_gamepad[t] case final copy?) return _pick(strings, copy);
    if (t.length == 1) return t.toUpperCase();
  }
  if (device == 'joystick') {
    if (_button.firstMatch(t) case final m?) return text('button', m[1]!);
    if (_hat.firstMatch(t) case final m?) {
      return text('hat', m[1]!) + text(m[2]!);
    }
    if (_slider.firstMatch(t) case final m?) return text('slider', m[1]!);
    if (_rotation.firstMatch(t) case final m?) {
      return text('rotation', m[1]!.toUpperCase());
    }
    if (_axis.hasMatch(t)) return text('axis', t.toUpperCase());
    if (t == 'throttlez') return text('throttle');
  }
  if (_keys[t] case final copy?) return _pick(strings, copy);
  if (_mouseButton.firstMatch(t) case final m?) return text('mouse', m[1]!);
  if (_numpadDigit.firstMatch(t) case final m?) return text('numpad', m[1]!);
  if (_function.hasMatch(t) || t.length == 1) return t.toUpperCase();
  return token;
}

String _device(AppStrings strings, KeyBindingEntry binding) {
  final number = '${binding.instance}';
  return switch (binding.device) {
    'joystick' =>
      strings.text('keyBindings.device.joystick').replaceFirst('{0}', number),
    'gamepad' => strings.text('keyBindings.device.gamepad'),
    'keyboardMouse' when binding.instance > 1 =>
      strings
          .text('keyBindings.device.secondKeyboard')
          .replaceFirst('{0}', number),
    _ => '',
  };
}

/// One binding in words, such as "左 Alt + F8" or "摇杆 1：按钮 3，双击".
String keyBindingLabel(AppStrings strings, KeyBindingEntry binding) {
  if (binding.device == 'unknown') return binding.input;
  final device = _device(strings, binding);
  if (binding.cleared) {
    return device.isEmpty
        ? strings.text('keyBindings.cleared')
        : '$device${strings.text('keyBindings.colon')}'
              '${strings.text('keyBindings.cleared')}';
  }
  // Modifiers first, as people say a combination, whatever order the file has.
  final tokens = binding.input.split('+').map((t) => t.trim()).toList()
    ..sort((a, b) {
      final ma = _modifierWords.containsKey(a.toLowerCase()) ? 0 : 1;
      final mb = _modifierWords.containsKey(b.toLowerCase()) ? 0 : 1;
      return ma - mb;
    });
  final keys = tokens
      .map((token) => _token(strings, binding.device, token))
      .join(' + ');
  final mode = _mode(strings, binding);
  return '${device.isEmpty ? '' : '$device${strings.text('keyBindings.colon')}'}'
      '$keys${mode == null ? '' : '${strings.text('keyBindings.comma')}$mode'}';
}

String? _mode(AppStrings strings, KeyBindingEntry binding) {
  if ((binding.multiTap ?? 1) == 2) {
    return strings.text('keyBindings.mode.double');
  }
  final mode = binding.mode;
  if (mode == null) return null;
  if (mode.startsWith('double_tap')) {
    return strings.text('keyBindings.mode.double');
  }
  if (mode.startsWith('delayed_press')) {
    return strings.text('keyBindings.mode.long');
  }
  if (mode.startsWith('hold') || mode.startsWith('delayed_hold')) {
    return strings.text('keyBindings.mode.hold');
  }
  return null;
}

const _modifierWords = {
  'lalt': 'alt',
  'ralt': 'alt',
  'alt': 'alt',
  'lctrl': 'ctrl',
  'rctrl': 'ctrl',
  'ctrl': 'ctrl',
  'lshift': 'shift',
  'rshift': 'shift',
  'shift': 'shift',
};

/// Shortcuts the Host listens for without a setting; the menu key can be changed
/// in settings, and this line compares with its default.
const fixedStarBridgeShortcuts = {'Alt+M', 'Ctrl+Alt+Y', 'Ctrl+Alt+N'};

/// The shortcut listener takes either side of a modifier, so "lalt+o" and "Alt+O" match.
String shortcutChord(String input) {
  final tokens = input.toLowerCase().split('+').map((t) => t.trim());
  final modifiers = <String>{};
  final keys = <String>[];
  for (final token in tokens) {
    if (token.isEmpty) continue;
    if (_modifierWords[token] case final word?) {
      modifiers.add(word);
    } else {
      keys.add(token);
    }
  }
  return [...modifiers.toList()..sort(), ...keys..sort()].join('+');
}

/// The StarBridge shortcut this keyboard binding shares, if any.
String? matchingShortcut(KeyBindingEntry binding, Set<String> shortcuts) {
  if (binding.device != 'keyboardMouse' || binding.instance != 1) return null;
  if (binding.cleared) return null;
  final chord = shortcutChord(binding.input);
  for (final shortcut in shortcuts) {
    if (shortcutChord(shortcut) == chord) return shortcut;
  }
  return null;
}
