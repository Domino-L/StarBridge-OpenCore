import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'painters.dart';
import 'pressable.dart';
import 'selection_track.dart';
import 'suite.dart';

// ---------------------------------------------------------------------------
// 33 · suite selection cards
// ---------------------------------------------------------------------------

/// The settings choice between the four suites. Each card holds a live
/// miniature (real components in that suite). Previews are still by default
/// and only demonstrate while their card is hovered or focused, plus once
/// right after being chosen, so a settings page never has four things
/// moving at once. Under reduced motion previews stay still.
class SuiteStyleCards extends StatelessWidget {
  const SuiteStyleCards({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final InteractionSuite value;
  final ValueChanged<InteractionSuite> onChanged;

  static const names = {
    InteractionSuite.standard: ('简洁', '系统默认的水波纹与淡入淡出'),
    InteractionSuite.rail: ('滑轨', '导轨滑动、拉伸后收拢'),
    InteractionSuite.scan: ('扫描', '四角框锁定、局部扫描线'),
    InteractionSuite.glow: ('光晕', '局部点亮、单次涟漪'),
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = c.maxWidth >= 700 ? 4 : 2;
      final w = (c.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final s in InteractionSuite.values)
            SizedBox(
              width: w,
              child: _StyleCard(
                suite: s,
                selected: s == value,
                onTap: () => onChanged(s),
              ),
            ),
        ],
      );
    },
  );
}

class _StyleCard extends StatefulWidget {
  const _StyleCard({
    required this.suite,
    required this.selected,
    required this.onTap,
  });
  final InteractionSuite suite;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_StyleCard> createState() => _StyleCardState();
}

class _StyleCardState extends State<_StyleCard> {
  int _demo = 0;
  Timer? _loop;
  bool _hover = false;
  bool _focus = false;

  @override
  void didUpdateWidget(_StyleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Play once on choice; a static preview stays where it is.
    if (widget.selected &&
        !oldWidget.selected &&
        InteractionScope.of(context).animates) {
      _step();
    }
  }

  /// Reduced motion turned on while demonstrating: stop on the current item.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates) {
      _loop?.cancel();
      _loop = null;
    }
  }

  @override
  void dispose() {
    _loop?.cancel();
    super.dispose();
  }

  void _sync() {
    final active = (_hover || _focus) && InteractionScope.of(context).animates;
    if (active && _loop == null) {
      _step();
      _loop = Timer.periodic(
        Duration(milliseconds: (950 * timeDilation).round()),
        (_) => _step(),
      );
    } else if (!active) {
      _loop?.cancel();
      _loop = null;
    }
  }

  void _step() {
    if (!mounted) return;
    setState(() => _demo = (_demo + 1) % 3);
  }

  @override
  Widget build(BuildContext context) {
    final outer = InteractionScope.of(context);
    final p = outer.palette;
    final (name, desc) = SuiteStyleCards.names[widget.suite]!;
    final preview = InteractionScope(
      data: InteractionData(
        suite: widget.suite,
        palette: p,
        reduceMotion: outer.reduceMotion,
      ),
      child: IgnorePointer(
        child: ExcludeFocus(
          child: ExcludeSemantics(
            child: SizedBox(
              width: 132,
              child: SuiteSelectionTrack(
                style: TrackStyle.navigation,
                items: const [
                  TrackItem(label: '舰队', icon: Icons.star_outline),
                  TrackItem(label: '房间', icon: Icons.meeting_room_outlined),
                  TrackItem(label: '机库', icon: Icons.warehouse_outlined),
                ],
                selected: _demo,
                onChanged: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        _focus = f;
        _sync();
      },
      child: MouseRegion(
        onEnter: (_) {
          _hover = true;
          _sync();
        },
        onExit: (_) {
          _hover = false;
          _sync();
        },
        child: Semantics(
          selected: widget.selected,
          child: SuitePressable(
            kind: PressableKind.card,
            selected: widget.selected,
            padding: const EdgeInsets.all(10),
            semanticLabel: '$name：$desc',
            onPressed: widget.onTap,
            child: CustomPaint(
              foregroundPainter: widget.selected ? _ChosenMark(p) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                      if (widget.selected)
                        Icon(Icons.check_circle, size: 16, color: p.accent),
                    ],
                  ),
                  Text(
                    desc,
                    style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                  ),
                  preview,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChosenMark extends CustomPainter {
  _ChosenMark(this.p);
  final InteractionPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectXY((Offset.zero & size).inflate(9), 6, 6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = p.accent,
    );
  }

  @override
  bool shouldRepaint(_ChosenMark old) => old.p != p;
}

// ---------------------------------------------------------------------------
// 12 · shortcut recording and colour choice
// ---------------------------------------------------------------------------

/// Records a key combination (e.g. the overlay hotkey). Click / Enter /
/// Space starts recording; the next non-modifier key with its modifiers is
/// taken, Esc cancels, Backspace clears. The keys shown are always the real
/// ones. Combinations listed in [reserved] are refused with a static error.
/// Recording shows a static mark (rail lit line, scan brackets, glow halo):
/// no blinking, and it never steals keys from anything outside the field.
class SuiteHotkeyField extends StatefulWidget {
  const SuiteHotkeyField({
    required this.value,
    required this.onChanged,
    this.reserved = const {},
    this.semanticLabel,
    super.key,
  });

  /// Current combination, e.g. "Ctrl + Shift + O"; null when unset.
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Combination → what already uses it.
  final Map<String, String> reserved;
  final String? semanticLabel;

  @override
  State<SuiteHotkeyField> createState() => SuiteHotkeyFieldState();
}

class SuiteHotkeyFieldState extends State<SuiteHotkeyField> {
  final _focus = FocusNode(debugLabel: 'hotkey');
  bool recording = false;
  String? _error;
  String _live = '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && recording) setState(() => recording = false);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    _focus.requestFocus();
    setState(() {
      recording = true;
      _error = null;
      _live = '';
    });
  }

  static String _name(LogicalKeyboardKey k) {
    final l = k.keyLabel;
    return l.length == 1 ? l.toUpperCase() : l;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!recording) {
      if (e is KeyDownEvent &&
          (e.logicalKey == LogicalKeyboardKey.enter ||
              e.logicalKey == LogicalKeyboardKey.space)) {
        _start();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final mods = [
      if (keys.isControlPressed) 'Ctrl',
      if (keys.isAltPressed) 'Alt',
      if (keys.isShiftPressed) 'Shift',
      if (keys.isMetaPressed) 'Win',
    ];
    if (e is! KeyDownEvent) {
      setState(() => _live = mods.join(' + '));
      return KeyEventResult.handled;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      setState(() => recording = false);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace && mods.isEmpty) {
      setState(() => recording = false);
      widget.onChanged(null);
      return KeyEventResult.handled;
    }
    final modifierKeys = {
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    };
    if (modifierKeys.contains(k)) {
      setState(() => _live = mods.join(' + '));
      return KeyEventResult.handled;
    }
    final combo = [...mods, _name(k)].join(' + ');
    final clash = widget.reserved[combo];
    setState(() {
      recording = false;
      _error = clash == null ? null : '「$combo」已用于$clash，请换一个';
    });
    if (clash == null) widget.onChanged(combo);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final text = recording
        ? (_live.isEmpty ? '请按下组合键…' : '$_live + …')
        : (widget.value ?? '未设置');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Semantics(
          button: true,
          label: widget.semanticLabel,
          value: recording ? '正在录入' : (widget.value ?? '未设置'),
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            child: GestureDetector(
              onTap: _start,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: CustomPaint(
                  foregroundPainter: _RecordMark(
                    data,
                    recording,
                    _error != null,
                    _focus.hasFocus,
                  ),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: suiteRadius(data.suite, 6),
                      border: Border.all(
                        color: _error != null
                            ? p.danger
                            : recording
                            ? p.accent
                            : p.border,
                      ),
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontFamily: recording || widget.value == null
                            ? null
                            : 'Source Code Pro',
                        color: recording ? p.textSecondary : p.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(fontSize: 11.5, color: p.danger))
        else if (recording)
          Text(
            'Esc 取消 · Backspace 清除',
            style: TextStyle(fontSize: 11.5, color: p.textSecondary),
          ),
      ],
    );
  }
}

class _RecordMark extends CustomPainter {
  _RecordMark(this.data, this.recording, this.error, this.focused);
  final InteractionData data;
  final bool recording;
  final bool error;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rect = Offset.zero & size;
    if (focused && !recording) {
      canvas.drawRRect(
        suiteRadius(data.suite, 6).toRRect(rect).inflate(2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = p.focusRing,
      );
    }
    if (!recording) return;
    final color = error ? p.danger : p.edge();
    switch (data.suite) {
      case InteractionSuite.rail:
        canvas.drawRect(
          Rect.fromLTWH(0, size.height - 2, size.width, 2),
          Paint()..color = color,
        );
      case InteractionSuite.scan:
        paintBrackets(canvas, rect.inflate(3), color: color);
      case InteractionSuite.glow:
        paintGlowStrokes(
          canvas,
          suiteRadius(data.suite, 6).toRRect(rect),
          p.accent,
          0.6,
        );
      case InteractionSuite.standard:
        break;
    }
  }

  @override
  bool shouldRepaint(_RecordMark old) => true;
}

/// Preset colour choice (overlay accent, team colour). The selected swatch
/// carries a static suite mark (rail underline, scan brackets, glow ring);
/// the colour value itself is applied at once.
class SuiteSwatchPicker extends StatelessWidget {
  const SuiteSwatchPicker({
    required this.colors,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<Color> colors;
  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    return Wrap(
      spacing: 6,
      children: [
        for (final c in colors)
          SuitePressable(
            kind: PressableKind.icon,
            minHeight: 30,
            padding: const EdgeInsets.all(5),
            semanticLabel:
                '颜色 #${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
            selected: c == value,
            onPressed: () => onChanged(c),
            child: CustomPaint(
              foregroundPainter: c == value ? _SwatchMark(data) : null,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: c,
                  shape: data.suite == InteractionSuite.scan
                      ? BoxShape.rectangle
                      : BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SwatchMark extends CustomPainter {
  _SwatchMark(this.data);
  final InteractionData data;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rect = Offset.zero & size;
    switch (data.suite) {
      case InteractionSuite.rail:
        canvas.drawRect(
          Rect.fromLTWH(0, size.height + 3, size.width, 2),
          Paint()..color = p.edge(),
        );
      case InteractionSuite.scan:
        paintBrackets(
          canvas,
          rect.inflate(3),
          color: p.edge(),
          length: 4,
          width: 1.5,
        );
      case InteractionSuite.glow || InteractionSuite.standard:
        canvas.drawCircle(
          rect.center,
          size.width / 2 + 3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = data.suite == InteractionSuite.glow
                ? p.edge()
                : p.textPrimary,
        );
    }
  }

  @override
  bool shouldRepaint(_SwatchMark old) => old.data != data;
}
