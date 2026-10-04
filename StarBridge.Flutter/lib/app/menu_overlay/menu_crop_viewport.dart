import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_bridge_style.dart';

/// Selection uses displayed image coordinates, never the surrounding letterbox.
/// The same surface serves selected references and captured screenshots.
class MenuCropViewport extends StatefulWidget {
  const MenuCropViewport({
    super.key,
    required this.bytes,
    required this.size,
    required this.turns,
    required this.busy,
    required this.selection,
    required this.onSelection,
    required this.onCancel,
    required this.hint,
  });
  final Uint8List bytes;
  final Size size;
  final int turns;
  final bool busy;
  final Rect? selection;
  final ValueChanged<Rect?> onSelection;
  final VoidCallback onCancel;
  final String hint;
  @override
  State<MenuCropViewport> createState() => _MenuCropViewportState();
}

class _MenuCropViewportState extends State<MenuCropViewport> {
  Offset? start;
  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (_, event) {
      if (!widget.busy &&
          event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onCancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Center(
      child: AspectRatio(
        aspectRatio: widget.turns.isOdd
            ? 1 / widget.size.aspectRatio
            : widget.size.aspectRatio,
        child: LayoutBuilder(
          builder: (context, bounds) {
            Offset normalized(Offset p) => Offset(
              (p.dx / bounds.maxWidth).clamp(0, 1),
              (p.dy / bounds.maxHeight).clamp(0, 1),
            );
            return Semantics(
              label: widget.hint,
              child: MouseRegion(
                cursor: widget.busy
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.precise,
                child: GestureDetector(
                  key: const Key('menu-crop-selection'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: widget.busy
                      ? null
                      : (details) {
                          start = normalized(details.localPosition);
                          widget.onSelection(null);
                        },
                  onPanUpdate: widget.busy
                      ? null
                      : (details) {
                          if (start == null) return;
                          final rect = Rect.fromPoints(
                            start!,
                            normalized(details.localPosition),
                          );
                          widget.onSelection(
                            rect.width * bounds.maxWidth >= 8 &&
                                    rect.height * bounds.maxHeight >= 8
                                ? rect
                                : null,
                          );
                        },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RotatedBox(
                        quarterTurns: widget.turns,
                        child: Image.memory(
                          widget.bytes,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                      CustomPaint(painter: _CropPainter(widget.selection)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.selection);
  final Rect? selection;
  @override
  void paint(Canvas canvas, Size size) {
    if (selection == null) return;
    final r = Rect.fromLTRB(
      selection!.left * size.width,
      selection!.top * size.height,
      selection!.right * size.width,
      selection!.bottom * size.height,
    );
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(r);
    canvas.drawPath(
      shade,
      Paint()..color = BridgeInk.scrim.withValues(alpha: .6),
    );
    canvas.drawRect(
      r,
      Paint()
        ..color = BridgeInk.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.selection != selection;
}
