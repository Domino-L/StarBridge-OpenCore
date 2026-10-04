import 'dart:ui';
import 'dart:typed_data';
import 'dart:math' as math;

/// Fit a selected region of the displayed, rotated image to its viewport.
/// Letterbox margins are excluded and the existing viewer limit is respected.
({double scale, Offset center})? menuImageRegionView(
  Size image,
  Size viewport,
  int turns,
  Rect selection,
  double maxScale,
) {
  if (![
        image.width,
        image.height,
        viewport.width,
        viewport.height,
        maxScale,
      ].every((n) => n.isFinite && n > 0) ||
      const MenuImageEdit().select(selection) == null) {
    return null;
  }
  final oriented = turns.isOdd ? Size(image.height, image.width) : image;
  final fit = math.min(
    viewport.width / oriented.width,
    viewport.height / oriented.height,
  );
  final displayed = oriented * fit;
  final center =
      viewport.center(Offset.zero) +
      Offset(
        (selection.center.dx - .5) * displayed.width,
        (selection.center.dy - .5) * displayed.height,
      );
  final scale = math
      .min(
        viewport.width / (selection.width * displayed.width),
        viewport.height / (selection.height * displayed.height),
      )
      .clamp(.2, math.max(.2, maxScale))
      .toDouble();
  return (scale: scale, center: center);
}

/// Scale relative to a contain-fit image: one decoded pixel per physical
/// screen pixel. Rotation swaps the image dimensions, not the DPI ratio.
double? menuReferenceActualScale(
  Size image,
  Size viewport,
  double pixelRatio,
  int turns,
) {
  if (![
    image.width,
    image.height,
    viewport.width,
    viewport.height,
    pixelRatio,
  ].every((n) => n.isFinite && n > 0)) {
    return null;
  }
  final rotated = turns.isOdd ? Size(image.height, image.width) : image;
  final fit = math.min(
    viewport.width / rotated.width,
    viewport.height / rotated.height,
  );
  final scale = 1 / (fit * pixelRatio);
  return scale.isFinite && scale > 0 ? scale : null;
}

/// Native tools normalize to PNG. Read bounded IHDR dimensions without decoding
/// a second full-size image merely to lay out the editor.
Size? menuPngSize(Uint8List bytes) {
  const header = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 33) return null;
  for (var i = 0; i < header.length; i++) {
    if (bytes[i] != header[i]) return null;
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(8) != 13 || data.getUint32(12) != 0x49484452) return null;
  final width = data.getUint32(16), height = data.getUint32(20);
  if (width < 1 ||
      height < 1 ||
      width > 16384 ||
      height > 16384 ||
      width * height > 64000000) {
    return null;
  }
  return Size(width.toDouble(), height.toDouble());
}

/// Non-destructive edits in normalized, rotated-original image coordinates.
class MenuImageEdit {
  const MenuImageEdit({
    this.turns = 0,
    this.crop = const Rect.fromLTWH(0, 0, 1, 1),
  });
  final int turns;
  final Rect crop;

  MenuImageEdit rotate() => MenuImageEdit(
    turns: (turns + 1) % 4,
    crop: Rect.fromLTRB(1 - crop.bottom, crop.left, 1 - crop.top, crop.right),
  );

  MenuImageEdit? select(Rect selection) {
    if (![
          selection.left,
          selection.top,
          selection.right,
          selection.bottom,
        ].every((n) => n.isFinite) ||
        selection.left < 0 ||
        selection.top < 0 ||
        selection.right > 1 ||
        selection.bottom > 1 ||
        selection.width < .005 ||
        selection.height < .005) {
      return null;
    }
    return MenuImageEdit(
      turns: turns,
      crop: Rect.fromLTRB(
        crop.left + selection.left * crop.width,
        crop.top + selection.top * crop.height,
        crop.left + selection.right * crop.width,
        crop.top + selection.bottom * crop.height,
      ),
    );
  }

  Map<String, Object?> toMap() => {
    'turns': turns,
    'cropLeft': crop.left,
    'cropTop': crop.top,
    'cropRight': crop.right,
    'cropBottom': crop.bottom,
  };
}
