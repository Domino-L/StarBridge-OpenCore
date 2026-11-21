import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'key_bindings_caps.dart';
import 'key_bindings_index.dart';

/// Mouse, gamepad and stick: one simple drawing of our own, one card per control
/// group, one leader line per card. No maker's art or marks.
enum KeyBindingsDevice { mouse, gamepad, stick }

const _stageWidth = 1168.0;
const _stageHeight = 590.0;
const _cardWidth = 300.0;

final class _Control {
  const _Control(this.labelKey, this.rows, this.x, this.y, this.left);
  final String labelKey;

  /// Input token and the words before its names.
  final List<(String, String)> rows;
  final double x, y;
  final bool left;
}

final class KeyBindingsDeviceStage extends StatelessWidget {
  const KeyBindingsDeviceStage({
    required this.device,
    required this.index,
    required this.scene,
    required this.layer,
    this.manySideButtons = false,
    this.stick = 1,
    required this.strings,
    this.query = '',
    this.onlyChanged = false,
    super.key,
  });
  final String query;
  final bool onlyChanged;

  /// The page's strings, for matching a search against key words.
  final AppStrings strings;
  final KeyBindingsDevice device;
  final KeyBindingsIndex? index;
  final String scene, layer;
  final bool manySideButtons;
  final int stick;

  String get _deviceName => switch (device) {
    KeyBindingsDevice.mouse => 'keyboardMouse',
    KeyBindingsDevice.gamepad => 'gamepad',
    KeyBindingsDevice.stick => 'joystick',
  };

  // The same filters the list uses: a search and "only changed" show here too.
  List<KeyBindingRef> _refs(String token) => [
    for (final ref
        in index?.onInput(
              _deviceName,
              token,
              scene: query.isEmpty ? scene : 'all',
              layer: layer,
              instance: device == KeyBindingsDevice.stick ? stick : null,
            ) ??
            const <KeyBindingRef>[])
      if ((!onlyChanged || ref.entry.customized) &&
          (query.isEmpty ||
              KeyBindingsIndex.matches(
                strings,
                ref.action,
                ref.name,
                query,
                entries: [ref.entry],
              )))
        ref,
  ];

  List<_Control> _controls(AppStrings strings) => switch (device) {
    KeyBindingsDevice.mouse => _mouseControls(strings),
    KeyBindingsDevice.gamepad => _gamepadControls(strings),
    KeyBindingsDevice.stick => _stickControls(strings),
  };

  List<_Control> _mouseControls(AppStrings strings) {
    String t(String key) => strings.text('keyBindings.device.$key');
    final sideRows = manySideButtons
        ? [
            for (var n = 4; n <= 15; n++)
              if (n <= 5 || _refs('mouse$n').isNotEmpty)
                ('mouse$n', t('sideNumber').replaceFirst('{0}', '$n')),
          ]
        : [('mouse5', t('sideFront')), ('mouse4', t('sideBack'))];
    return [
      _Control('leftButton', const [('mouse1', '')], 514, 150, true),
      _Control('bothButtons', const [('mouse1_2', '')], 584, 215, true),
      _Control(
        manySideButtons ? 'sideMany' : 'side',
        sideRows,
        manySideButtons ? 464 : 449,
        manySideButtons ? 310 : 318,
        true,
      ),
      _Control('moveX', const [('maxis_x', '')], 484, 470, true),
      _Control('rightButton', const [('mouse2', '')], 654, 130, false),
      _Control(
        'wheel',
        [
          ('mwheel_up', t('wheelUp')),
          ('mouse3', t('wheelPress')),
          ('mwheel_down', t('wheelDown')),
        ],
        598,
        156,
        false,
      ),
      _Control('moveY', const [('maxis_y', '')], 684, 470, false),
    ];
  }

  List<_Control> _gamepadControls(AppStrings strings) {
    String t(String key) => strings.text('keyBindings.device.$key');
    const x = 584.0, y = 290.0;
    String word(String key) => t(key);
    return [
      _Control(
        'triggerL',
        const [('triggerl_btn', '')],
        x - 134,
        y - 186,
        true,
      ),
      _Control('bumperL', const [('shoulderl', '')], x - 126, y - 150, true),
      _Control(
        'stickL',
        [
          ('thumbl', word('press')),
          ('thumblx', word('across')),
          ('thumbly', word('along')),
        ],
        x - 155,
        y - 54,
        true,
      ),
      _Control('back', const [('back', '')], x - 33, y - 52, true),
      _Control(
        'dpad',
        [
          ('dpad_up', word('up')),
          ('dpad_down', word('down')),
          ('dpad_left', word('left')),
          ('dpad_right', word('right')),
        ],
        x - 82,
        y + 24,
        true,
      ),
      _Control(
        'triggerR',
        const [('triggerr_btn', '')],
        x + 134,
        y - 186,
        false,
      ),
      _Control('bumperR', const [('shoulderr', '')], x + 126, y - 150, false),
      _Control('start', const [('start', '')], x + 46, y - 52, false),
      _Control(
        'letters',
        const [('y', 'Y'), ('b', 'B'), ('a', 'A'), ('x', 'X')],
        x + 195,
        y - 54,
        false,
      ),
      _Control(
        'stickR',
        [
          ('thumbr', word('press')),
          ('thumbrx', word('across')),
          ('thumbry', word('along')),
        ],
        x + 93,
        y + 34,
        false,
      ),
    ];
  }

  List<_Control> _stickControls(AppStrings strings) {
    String t(String key) => strings.text('keyBindings.device.$key');
    String button(int n) =>
        strings.text('keyBindings.input.button').replaceFirst('{0}', '$n');
    List<(String, String)> group(Iterable<int> numbers) {
      final rows = [
        for (final n in numbers)
          if (_refs('button$n').isNotEmpty) ('button$n', button(n)),
      ];
      return rows.isEmpty ? const [('none', '')] : rows;
    }

    const x = 584.0, y = -6.0;
    return [
      _Control('button3', const [('button3', '')], x - 34, y + 78, true),
      _Control('trigger', const [('button1', '')], x - 71, y + 138, true),
      _Control('axisX', const [('x', '')], x - 46, y + 250, true),
      _Control('baseLeft', group([5, 6, 7, 8, 9, 10]), x - 192, y + 418, true),
      _Control('button2', const [('button2', '')], x + 13, y + 46, false),
      _Control(
        'hat',
        [
          ('hat1_up', t('up')),
          ('hat1_down', t('down')),
          ('hat1_left', t('left')),
          ('hat1_right', t('right')),
        ],
        x + 21,
        y + 76,
        false,
      ),
      _Control('button4', const [('button4', '')], x + 45, y + 86, false),
      _Control('axisY', const [('y', '')], x + 47, y + 215, false),
      _Control('axisTwist', const [('rotz', '')], x + 49, y + 330, false),
      _Control(
        'baseRight',
        group([11, 12, 13, 14, 15, 16]),
        x + 192,
        y + 418,
        false,
      ),
      _Control('slider', const [('slider1', '')], x + 24, y + 494, false),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final controls = _controls(strings);
    final placed = <_Placed>[];
    for (final side in const [true, false]) {
      final column = controls.where((c) => c.left == side).toList()
        ..sort((a, b) => a.y.compareTo(b.y));
      final heights = [for (final c in column) 26.0 + c.rows.length * 18];
      final free = (_stageHeight - heights.fold(0.0, (a, b) => a + b)).clamp(
        0.0,
        _stageHeight,
      );
      final gap = free / column.length;
      var y = gap / 2;
      for (var i = 0; i < column.length; i++) {
        placed.add(_Placed(column[i], y.roundToDouble()));
        y += heights[i] + gap;
      }
    }
    final buttons = <int>{
      for (var n = 1; n <= 16; n++)
        if (_refs('button$n').isNotEmpty) n,
    };
    final lit = {
      for (final p in placed)
        p.control: p.control.rows.any((r) => _refs(r.$1).isNotEmpty),
    };
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: SizedBox(
        key: Key('key-bindings-stage-${device.name}'),
        width: _stageWidth,
        height: _stageHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DevicePainter(
                  device: device,
                  placed: placed,
                  lit: lit,
                  buttons: buttons,
                  manySideButtons: manySideButtons,
                  sliderBound: _refs('slider1').isNotEmpty,
                  fontFamily: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.fontFamily,
                  colors: context.tokens.colors,
                  textDirection: Directionality.of(context),
                ),
              ),
            ),
            for (final p in placed)
              Positioned(
                left: p.control.left ? 0 : _stageWidth - _cardWidth,
                top: p.top,
                width: _cardWidth,
                child: _Card(
                  control: p.control,
                  refsFor: _refs,
                  title: strings.text(
                    'keyBindings.device.${p.control.labelKey}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _Placed {
  const _Placed(this.control, this.top);
  final _Control control;
  final double top;
  double get lineY => top + 12;
  double get lineX => control.left ? _cardWidth : _stageWidth - _cardWidth;
}

final class _Card extends StatelessWidget {
  const _Card({
    required this.control,
    required this.refsFor,
    required this.title,
  });
  final _Control control;
  final List<KeyBindingRef> Function(String) refsFor;
  final String title;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('keyBindings.$key');
    final tokens = context.tokens;
    final changed = control.rows.any(
      (r) => refsFor(r.$1).any((ref) => ref.entry.customized),
    );
    final any = control.rows.any((r) => refsFor(r.$1).isNotEmpty);
    final align = control.left ? TextAlign.left : TextAlign.right;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          left: control.left
              ? BorderSide(
                  color: changed
                      ? tokens.colors.warning
                      : tokens.surfaces.panel.border,
                )
              : BorderSide.none,
          right: control.left
              ? BorderSide.none
              : BorderSide(
                  color: changed
                      ? tokens.colors.warning
                      : tokens.surfaces.panel.border,
                ),
        ),
      ),
      child: Column(
        crossAxisAlignment: control.left
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: align,
            style: TextStyle(
              fontSize: 13,
              fontWeight: any ? FontWeight.w600 : FontWeight.w400,
              color: any
                  ? tokens.colors.textPrimary
                  : tokens.colors.textDisabled,
            ),
          ),
          for (final row in control.rows)
            Builder(
              builder: (context) {
                final refs = refsFor(row.$1);
                final names = refs
                    .take(2)
                    .map((r) => keyCapShortened(r.name ?? r.action.name))
                    .join(' / ');
                final extra = refs.length > 2
                    ? t('card.more').replaceFirst('{0}', '${refs.length}')
                    : '';
                return Text.rich(
                  TextSpan(
                    children: [
                      if (row.$2.isNotEmpty)
                        TextSpan(
                          text: '${row.$2}  ',
                          style: TextStyle(color: tokens.colors.textSecondary),
                        ),
                      TextSpan(
                        text: refs.isEmpty ? t('card.none') : '$names$extra',
                        style: TextStyle(
                          color: refs.isEmpty
                              ? tokens.colors.textDisabled
                              : tokens.colors.accent,
                        ),
                      ),
                      if (refs.any((r) => r.entry.customized))
                        TextSpan(
                          text: '  ${t('tag.changed')}',
                          style: TextStyle(color: tokens.colors.warning),
                        ),
                    ],
                  ),
                  textAlign: align,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12, height: 1.32),
                );
              },
            ),
        ],
      ),
    );
  }
}

final class _DevicePainter extends CustomPainter {
  const _DevicePainter({
    required this.device,
    required this.placed,
    required this.lit,
    required this.buttons,
    required this.manySideButtons,
    required this.sliderBound,
    required this.fontFamily,
    required this.colors,
    required this.textDirection,
  });
  final KeyBindingsDevice device;
  final List<_Placed> placed;
  final Map<_Control, bool> lit;
  final Set<int> buttons;
  final bool manySideButtons, sliderBound;
  final String? fontFamily;
  final ColorTokens colors;
  final TextDirection textDirection;

  Paint get _outline => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = colors.accent.withValues(alpha: .62);
  Paint get _detail => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = colors.accent.withValues(alpha: .34);
  Paint get _bodyFill =>
      Paint()..color = colors.accentSoft.withValues(alpha: .35);
  Paint get _partFill => Paint()..color = colors.accentSoft;
  Paint get _partEdge => Paint()
    ..style = PaintingStyle.stroke
    ..color = colors.accent.withValues(alpha: .68);

  void _body(Canvas canvas, Path path) {
    canvas.drawPath(path, _bodyFill);
    canvas.drawPath(path, _outline);
  }

  void _part(Canvas canvas, Path path) {
    canvas.drawPath(path, _partFill);
    canvas.drawPath(path, _partEdge);
  }

  Path _rrect(double x, double y, double w, double h, double r) =>
      Path()..addRRect(RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(r)));
  Path _circle(double x, double y, double r) =>
      Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));

  void _label(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  void _mouse(Canvas canvas) {
    canvas.save();
    canvas.translate(584, 66);
    _body(
      canvas,
      Path()
        ..moveTo(0, 0)
        ..cubicTo(-92, 0, -128, 62, -128, 148)
        ..lineTo(-128, 300)
        ..cubicTo(-128, 402, -74, 462, 0, 462)
        ..cubicTo(74, 462, 128, 402, 128, 300)
        ..lineTo(128, 148)
        ..cubicTo(128, 62, 92, 0, 0, 0)
        ..close(),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-128, 164)
        ..cubicTo(-70, 176, 70, 176, 128, 164)
        ..moveTo(0, 0)
        ..lineTo(0, 48)
        ..moveTo(0, 132)
        ..lineTo(0, 170),
      _detail,
    );
    _part(canvas, _rrect(-14, 48, 28, 84, 14));
    canvas.drawPath(
      Path()
        ..moveTo(-14, 72)
        ..lineTo(14, 72)
        ..moveTo(-14, 90)
        ..lineTo(14, 90)
        ..moveTo(-14, 108)
        ..lineTo(14, 108),
      _detail,
    );
    if (manySideButtons) {
      for (var i = 0; i < 12; i++) {
        final x = -120.0 + (i % 3) * 26, y = 200.0 + (i ~/ 3) * 26;
        _part(canvas, _rrect(x, y, 22, 22, 3));
        _label(
          canvas,
          '${i + 4}',
          Offset(x + 11, y + 11),
          colors.textPrimary,
          10.5,
        );
      }
    } else {
      _part(canvas, _rrect(-135, 196, 13, 50, 4));
      _part(canvas, _rrect(-135, 252, 13, 50, 4));
    }
    canvas.restore();
  }

  void _gamepad(Canvas canvas) {
    canvas.save();
    canvas.translate(584, 290);
    _body(
      canvas,
      Path()
        ..moveTo(-178, -128)
        ..cubicTo(-120, -150, 120, -150, 178, -128)
        ..cubicTo(232, -106, 268, 40, 266, 128)
        ..cubicTo(264, 188, 212, 208, 172, 158)
        ..cubicTo(138, 112, 110, 92, 66, 92)
        ..lineTo(-66, 92)
        ..cubicTo(-110, 92, -138, 112, -172, 158)
        ..cubicTo(-212, 208, -264, 188, -266, 128)
        ..cubicTo(-268, 40, -232, -106, -178, -128)
        ..close(),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-176, -141)
        ..cubicTo(-158, -160, -96, -160, -78, -144)
        ..moveTo(176, -141)
        ..cubicTo(158, -160, 96, -160, 78, -144),
      _detail,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-168, -166)
        ..lineTo(-168, -196)
        ..cubicTo(-168, -206, -100, -206, -100, -196)
        ..lineTo(-100, -166)
        ..close()
        ..moveTo(168, -166)
        ..lineTo(168, -196)
        ..cubicTo(168, -206, 100, -206, 100, -196)
        ..lineTo(100, -166)
        ..close(),
      _detail,
    );
    for (final (x, y) in const [(-142.0, -54.0), (74.0, 34.0)]) {
      canvas.drawPath(_circle(x, y, 35), _detail);
      _part(canvas, _circle(x, y, 19));
    }
    final cross = Path.combine(
      PathOperation.union,
      _rrect(-66, -8, 22, 66, 0),
      _rrect(-88, 14, 66, 22, 0),
    );
    _part(canvas, cross);
    for (final (text, x, y) in const [
      ('Y', 142.0, -92.0),
      ('X', 104.0, -54.0),
      ('B', 180.0, -54.0),
      ('A', 142.0, -16.0),
    ]) {
      _part(canvas, _circle(x, y, 15));
      _label(canvas, text, Offset(x, y), colors.textPrimary, 13);
    }
    canvas.drawPath(_rrect(-46, -66, 26, 14, 7), _detail);
    canvas.drawPath(_rrect(20, -66, 26, 14, 7), _detail);
    canvas.restore();
  }

  void _stick(Canvas canvas) {
    canvas.save();
    canvas.translate(584, -6);
    _body(
      canvas,
      Path()
        ..moveTo(-210, 410)
        ..cubicTo(-210, 386, -96, 376, 0, 376)
        ..cubicTo(96, 376, 210, 386, 210, 410)
        ..lineTo(210, 486)
        ..cubicTo(210, 512, 96, 524, 0, 524)
        ..cubicTo(-96, 524, -210, 512, -210, 486)
        ..close(),
    );
    _body(
      canvas,
      Path()
        ..moveTo(-44, 396)
        ..cubicTo(-52, 300, -48, 230, -40, 170)
        ..cubicTo(-36, 132, -52, 104, -44, 72)
        ..cubicTo(-38, 46, 40, 40, 58, 62)
        ..cubicTo(74, 84, 54, 118, 44, 168)
        ..cubicTo(40, 240, 46, 310, 50, 396)
        ..close(),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-40, 170)
        ..cubicTo(-16, 180, 22, 180, 44, 168)
        ..moveTo(-210, 448)
        ..cubicTo(-120, 466, 120, 466, 210, 448),
      _detail,
    );
    _part(canvas, _circle(6, 76, 15));
    canvas.drawPath(
      Path()
        ..moveTo(6, 66)
        ..lineTo(6, 86)
        ..moveTo(-4, 76)
        ..lineTo(16, 76),
      _partEdge,
    );
    _part(canvas, _circle(-27, 78, 7));
    _part(canvas, _circle(38, 86, 7));
    _part(canvas, _circle(6, 46, 7));
    _part(
      canvas,
      Path()
        ..moveTo(-50, 118)
        ..cubicTo(-76, 122, -80, 150, -56, 156)
        ..lineTo(-46, 150)
        ..close(),
    );
    final slider = _rrect(-24, 488, 48, 13, 3);
    if (sliderBound) {
      _part(canvas, slider);
    } else {
      canvas.drawPath(slider, _detail);
    }
    void cell(int n, double x, double y) {
      final on = buttons.contains(n);
      final rect = _rrect(x, y, 25, 19, 2);
      if (on) {
        _part(canvas, rect);
      } else {
        canvas.drawPath(rect, _detail);
      }
      _label(
        canvas,
        '$n',
        Offset(x + 12.5, y + 9.5),
        on ? colors.textPrimary : colors.textDisabled,
        11,
      );
    }

    const left = [
      (5, 0, 0),
      (6, 1, 0),
      (7, 2, 0),
      (10, 0, 1),
      (9, 1, 1),
      (8, 2, 1),
    ];
    const right = [
      (11, 0, 0),
      (12, 1, 0),
      (13, 2, 0),
      (16, 0, 1),
      (15, 1, 1),
      (14, 2, 1),
    ];
    for (final (n, c, r) in left) {
      cell(n, -184.0 + c * 29, 396.0 + r * 23);
    }
    for (final (n, c, r) in right) {
      cell(n, 97.0 + c * 29, 396.0 + r * 23);
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    switch (device) {
      case KeyBindingsDevice.mouse:
        _mouse(canvas);
      case KeyBindingsDevice.gamepad:
        _gamepad(canvas);
      case KeyBindingsDevice.stick:
        _stick(canvas);
    }
    for (final p in placed) {
      final on = lit[p.control] ?? false;
      final x = p.control.x, y = p.control.y;
      final run = (y - p.lineY).abs();
      final mid = p.control.left
          ? (x - run).clamp(p.lineX + 10, x)
          : (x + run).clamp(x, p.lineX - 10);
      canvas.drawPath(
        Path()
          ..moveTo(p.lineX, p.lineY)
          ..lineTo(mid.toDouble(), p.lineY)
          ..lineTo(x, y),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = on
              ? colors.accent.withValues(alpha: .7)
              : colors.textDisabled.withValues(alpha: .45),
      );
      canvas.drawCircle(
        Offset(x, y),
        on ? 3 : 2.2,
        Paint()..color = on ? colors.focusRing : colors.textDisabled,
      );
    }
  }

  @override
  bool shouldRepaint(_DevicePainter old) =>
      old.device != device ||
      old.manySideButtons != manySideButtons ||
      old.sliderBound != sliderBound ||
      old.colors != colors ||
      old.buttons.length != buttons.length ||
      old.placed != placed;
}
