import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_choice_navigation.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo_choice.dart';
import 'key_bindings_layouts.dart';

/// The bar between the keyboard and the list. Dragging it, or the arrow keys while it
/// has focus, shares the height between them; the button folds the list to one line.
final class KeyBindingsSplitter extends StatelessWidget {
  const KeyBindingsSplitter({
    required this.open,
    required this.onToggle,
    required this.onResize,
    required this.onSettled,
    super.key,
  });
  final bool open;
  final VoidCallback onToggle;

  /// How far the list grows, in pixels; negative gives the room to the keyboard.
  final ValueChanged<double> onResize;

  /// A drag or a key press is over: the height is worth remembering.
  final VoidCallback onSettled;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('keyBindings.$key');
    final tokens = context.tokens;
    return Focus(
      key: const Key('key-bindings-splitter'),
      canRequestFocus: open,
      onKeyEvent: (_, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        final step = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowUp => 24.0,
          LogicalKeyboardKey.arrowDown => -24.0,
          _ => null,
        };
        if (step == null) return KeyEventResult.ignored;
        onResize(step);
        onSettled();
        return KeyEventResult.handled;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Semantics(
            label: t('split.label'),
            onIncrease: open
                ? () {
                    onResize(24);
                    onSettled();
                  }
                : null,
            onDecrease: open
                ? () {
                    onResize(-24);
                    onSettled();
                  }
                : null,
            child: MouseRegion(
              cursor: open ? SystemMouseCursors.resizeRow : MouseCursor.defer,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: open ? () => Focus.of(context).requestFocus() : null,
                onVerticalDragUpdate: open
                    ? (details) => onResize(-details.delta.dy)
                    : null,
                onVerticalDragEnd: open ? (_) => onSettled() : null,
                child: SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 64,
                            height: 4,
                            decoration: BoxDecoration(
                              color: focused
                                  ? tokens.colors.focusRing
                                  : tokens.surfaces.panel.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('key-bindings-fold'),
                        onPressed: onToggle,
                        child: Text(t(open ? 'split.fold' : 'split.unfold')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Past the size the words were checked at, the keyboard is laid out there and scaled up
/// whole: the key text grows with the key and wraps exactly as it did.
final class KeyBindingsScaledKeyboard extends StatelessWidget {
  const KeyBindingsScaledKeyboard({
    required this.size,
    required this.unit,
    required this.builder,
    super.key,
  });
  static const checkedUnit = 70.0;
  final KeyBindingsKeyboardSize size;
  final double unit;
  final Widget Function(double unit) builder;

  @override
  Widget build(BuildContext context) {
    if (unit <= checkedUnit) return builder(unit);
    final layout = keyboardLayouts[size]!;
    return SizedBox(
      width: layout.width * unit,
      height: layout.height * unit,
      child: FittedBox(child: builder(checkedUnit)),
    );
  }
}

/// The opened key's panel, beside the key and toward the keyboard's middle.
final class KeyBindingsKeyPopover extends StatelessWidget {
  const KeyBindingsKeyPopover({
    required this.link,
    required this.size,
    required this.keyToken,
    required this.unit,
    required this.child,
    super.key,
  });
  final LayerLink link;

  /// The key size: past the checked size the keyboard, and so the link, is scaled.
  final double unit;
  final KeyBindingsKeyboardSize size;
  final String keyToken;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = keyboardLayouts[size]!;
    final specs = layout.keys.where((k) => k.token == keyToken);
    final spec = specs.isEmpty ? null : specs.first;
    final toLeft = spec != null && spec.x + spec.width / 2 > layout.width * .55;
    final upward = spec == null || spec.y > layout.height * .5;
    // A key on the scaled keyboard hands the follower its scale; the panel keeps its own
    // size. A key the layout lacks opens from the line under it, which is not scaled.
    final scale = spec == null
        ? 1.0
        : math.max(1.0, unit / KeyBindingsScaledKeyboard.checkedUnit);
    final corner = toLeft
        ? (upward ? Alignment.bottomRight : Alignment.topRight)
        : (upward ? Alignment.bottomLeft : Alignment.topLeft);
    return CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      targetAnchor: toLeft
          ? (upward ? Alignment.bottomLeft : Alignment.topLeft)
          : (upward ? Alignment.bottomRight : Alignment.topRight),
      followerAnchor: toLeft
          ? (upward ? Alignment.bottomRight : Alignment.topRight)
          : (upward ? Alignment.bottomLeft : Alignment.topLeft),
      offset: Offset((toLeft ? -14 : 14) / scale, 0),
      child: Align(
        alignment: corner,
        child: Transform.scale(
          scale: 1 / scale,
          alignment: corner,
          child: child,
        ),
      ),
    );
  }
}

/// The words under the keyboard, coloured like the keys they describe.
final class KeyBindingsLegend extends StatelessWidget {
  const KeyBindingsLegend({required this.style, super.key});
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('keyBindings.legend.$key');
    final colors = context.tokens.colors;
    TextSpan strong(String key, Color color) => TextSpan(
      text: t(key),
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
    return Text.rich(
      key: const Key('key-bindings-legend'),
      TextSpan(
        children: [
          strong('lit', colors.accent),
          TextSpan(text: t('litRest')),
          strong('changed', colors.warning),
          TextSpan(text: t('changedRest')),
          strong('shared', colors.warning),
          TextSpan(text: t('sharedRest')),
          TextSpan(text: t('rest')),
        ],
      ),
      textAlign: TextAlign.center,
      style: style,
    );
  }
}

/// The key size: what it always was (the width's, up to the checked size), or larger
/// when both the width and the room left in the window allow it.
double keyBindingsUnit({
  required double across,
  required double rows,
  required double room,
}) => math
    .max(
      math.min(across, KeyBindingsScaledKeyboard.checkedUnit),
      math.min(across, room / rows),
    )
    .clamp(36.0, 120.0);

/// Reports its child's height after layout, when it changed by more than a pixel: the
/// controls above the keyboard wrap with the width, and their height sets its room.
final class KeyBindingsMeasured extends StatefulWidget {
  const KeyBindingsMeasured({
    required this.onHeight,
    required this.child,
    super.key,
  });
  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<KeyBindingsMeasured> createState() => _KeyBindingsMeasuredState();
}

final class _KeyBindingsMeasuredState extends State<KeyBindingsMeasured> {
  double? _reported;

  void _measure(Duration _) {
    final box = context.findRenderObject();
    if (!mounted || box is! RenderBox || !box.hasSize) return;
    final height = box.size.height;
    if (_reported != null && (height - _reported!).abs() <= 1) return;
    _reported = height;
    widget.onHeight(height);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_measure);
    return widget.child;
  }
}

/// The list's height, the range the splitter moves it in, and the key size the rest of
/// the window allows. [list] is null while the list is folded to its line.
///
/// With the keyboard shown, the range is where the keyboard really changes: the key
/// size runs from its smallest (the checked size, or the width's if narrower) to its
/// largest (the width's), so the list stops where the keyboard can grow no more and
/// where it can shrink no more. Inside it the keyboard takes exactly the room the list
/// leaves, so the list always reaches the page's bottom: no blank band under it when
/// the keyboard is held by the width, and no page scrolling when it is held at its
/// smallest (11-15 user on b99: "这个把手有一些问题", a blank band under the list).
///
/// [between] is what sits between the keyboard and the list (the missing keys, the
/// legend, the splitter) and [chrome] the list's own bar above its rows, [folded] that
/// bar alone: the page measures them, since they wrap with the width and come and go
/// (review CX-KEYBIND-SPLIT-073-R1 P2). The list's height counts its bar.
({double most, double least, double lower, double unit}) keyBindingsRoom({
  required double window,
  required double above,
  required double across,
  required double rows,
  required double? list,
  bool keyboard = true,
  double between = 108,
  double chrome = 56,
  double folded = 56,
}) {
  final cap = math.max(160.0, window - 360);
  final free = window - above - between;
  var most = cap, least = 160.0;
  if (keyboard) {
    final smallest = math
        .min(across, KeyBindingsScaledKeyboard.checkedUnit)
        .clamp(36.0, 120.0);
    final largest = across.clamp(36.0, 120.0);
    most = math.max(160.0, math.min(cap, free - rows * smallest));
    least = (free - rows * largest).clamp(160.0, most);
  }
  final lower = (list ?? 476).clamp(least, most);
  final room = free - (list == null ? folded : lower);
  return (
    most: most,
    least: least,
    lower: lower,
    unit: keyBindingsUnit(across: across, rows: rows, room: room),
  );
}

/// What sits between the keyboard and the list (the missing keys, the legend, the
/// splitter), measured as one: the page shares the window by its real height.
Widget keyBindingsBetween(
  ValueChanged<double> onHeight,
  List<Widget> children,
) => KeyBindingsMeasured(
  onHeight: onHeight,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  ),
);

/// A splitter step from the height the list really shows, kept where the keyboard
/// follows, so the splitter stays under the pointer and stops at the ends.
double keyBindingsResized(
  double wished,
  double by,
  double least,
  double most,
) => (wished.clamp(least, most) + by).clamp(least, most);

/// A row of choices in the page's own holo look.
Widget keyBindingsChoices(
  String id,
  List<(String, String, bool)> items,
  String selected,
  ValueChanged<String> onSelected,
) => StarBridgeChoiceNavigation(
  key: Key('key-bindings-$id'),
  selected: selected,
  onSelected: onSelected,
  faceBuilder: organizationHoloNavigationFace,
  choices: [
    for (final (value, label, enabled) in items)
      StarBridgeNavigationChoice(
        id: value,
        label: label,
        enabled: enabled,
        controlKey: Key('key-bindings-$id-$value'),
        child: Text(label),
      ),
  ],
);
