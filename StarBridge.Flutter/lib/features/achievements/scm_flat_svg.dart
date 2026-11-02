import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Renders the flat achievement SVGs from the approved art delivery.
///
/// Those files use one fixed subset: a square viewBox and `<path fill d>`
/// elements whose `d` is `M` plus implicit straight segments and `Z`. Anything
/// outside that subset is rejected so the caller falls back to its placeholder.
class ScmFlatSvg extends StatefulWidget {
  const ScmFlatSvg(this.asset, {super.key, required this.fallback});

  final String asset;
  final Widget fallback;

  @override
  State<ScmFlatSvg> createState() => _ScmFlatSvgState();
}

class _ScmFlatSvgState extends State<ScmFlatSvg> {
  static final _cache = <String, Future<ScmFlatDrawing?>>{};
  late Future<ScmFlatDrawing?> _drawing;

  @override
  void initState() {
    super.initState();
    _drawing = _load(widget.asset);
  }

  @override
  void didUpdateWidget(ScmFlatSvg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) _drawing = _load(widget.asset);
  }

  static Future<ScmFlatDrawing?> _load(String asset) =>
      _cache[asset] ??= rootBundle
          .loadString(asset)
          .then(ScmFlatDrawing.parse, onError: (Object _) => null);

  @override
  Widget build(BuildContext context) => FutureBuilder<ScmFlatDrawing?>(
    future: _drawing,
    builder: (context, snapshot) {
      final drawing = snapshot.data;
      if (drawing == null) {
        return snapshot.connectionState == ConnectionState.done
            ? widget.fallback
            : const SizedBox.expand();
      }
      return CustomPaint(
        painter: _ScmFlatPainter(drawing),
        size: Size.infinite,
      );
    },
  );
}

/// Parsed flat SVG: filled polygons in viewBox units.
class ScmFlatDrawing {
  const ScmFlatDrawing(this.extent, this.shapes);

  final double extent;
  final List<(Color, Path)> shapes;

  static final _viewBox = RegExp(r'viewBox="0 0 ([0-9.]+) \1"');
  static final _path = RegExp(r'<path fill="#([0-9A-Fa-f]{6})" d="([^"]*)"/>');
  static final _element = RegExp(r'<(?!/)([a-zA-Z]+)');

  /// Returns null for any SVG outside the supported subset.
  static ScmFlatDrawing? parse(String source) {
    final box = _viewBox.firstMatch(source);
    if (box == null) return null;
    final elements = _element.allMatches(source).map((m) => m.group(1)).toSet();
    if (!elements.every((e) => e == 'svg' || e == 'path')) return null;
    final shapes = <(Color, Path)>[];
    for (final match in _path.allMatches(source)) {
      final path = _polygon(match.group(2)!);
      if (path == null) return null;
      final rgb = int.parse(match.group(1)!, radix: 16);
      // Colours are asset data parsed at runtime, not design tokens.
      shapes.add((
        Color.fromARGB(0xFF, rgb >> 16 & 0xFF, rgb >> 8 & 0xFF, rgb & 0xFF),
        path,
      ));
    }
    if (shapes.isEmpty) return null;
    return ScmFlatDrawing(double.parse(box.group(1)!), shapes);
  }

  static Path? _polygon(String d) {
    final text = d.trim();
    if (!text.startsWith('M') || !text.endsWith('Z')) return null;
    final body = text.substring(1, text.length - 1).trim();
    if (RegExp(r'[A-Za-z]').hasMatch(body)) return null;
    final numbers = body
        .split(RegExp(r'[\s,]+'))
        .where((n) => n.isNotEmpty)
        .map(double.tryParse)
        .toList();
    if (numbers.length < 6 || numbers.length.isOdd || numbers.contains(null)) {
      return null;
    }
    final path = Path()..moveTo(numbers[0]!, numbers[1]!);
    for (var i = 2; i < numbers.length; i += 2) {
      path.lineTo(numbers[i]!, numbers[i + 1]!);
    }
    return path..close();
  }
}

class _ScmFlatPainter extends CustomPainter {
  _ScmFlatPainter(this.drawing);

  final ScmFlatDrawing drawing;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas
      ..save()
      ..translate((size.width - side) / 2, (size.height - side) / 2)
      ..scale(side / drawing.extent);
    final paint = Paint()..isAntiAlias = true;
    for (final (color, path) in drawing.shapes) {
      canvas.drawPath(path, paint..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScmFlatPainter oldDelegate) =>
      oldDelegate.drawing != drawing;
}
