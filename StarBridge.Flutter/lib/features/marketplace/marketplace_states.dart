import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/controls/semantic_action_style.dart'
    show ActionTone;
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_copy.dart';

/// Reuse the existing native-sized retry face without moving availability or
/// work out of its caller. Null means genuinely disabled, never an enabled no-op.
Widget marketRetryAction(VoidCallback? retry, {Key? key}) =>
    _MarketRetryAction(retry, key: key);

/// The same native-sized text action for marketplace labels other than retry.
/// Availability and work remain owned by the caller.
Widget marketTextAction({
  required Widget child,
  required VoidCallback? onPressed,
  Key? key,
}) => _MarketRetryAction(onPressed, key: key, child: child);

/// Apply the selected feedback to an existing marketplace button without
/// replacing its style, focus, callback availability or native hit geometry.
Widget marketButtonAction(
  ButtonStyleButton button, {
  Key? key,
  bool danger = false,
  bool hoverFace = true,
}) => _MarketRetryAction(
  button.onPressed,
  key: key,
  button: button,
  danger: danger,
  hoverFace: hoverFace,
);

class _MarketRetryAction extends StatelessWidget {
  const _MarketRetryAction(
    this.retry, {
    this.child,
    this.button,
    this.danger = false,
    this.hoverFace = true,
    super.key,
  });
  final VoidCallback? retry;
  final Widget? child;
  final ButtonStyleButton? button;
  final bool danger;

  /// False inside a hover card, which draws the hover itself.
  final bool hoverFace;

  @override
  Widget build(BuildContext context) {
    final onRetry = retry;
    final states = <WidgetState>{if (onRetry == null) WidgetState.disabled};
    final native =
        button ??
        TextButton(
          onPressed: onRetry,
          child: child ?? Text(marketText(context, 'retry')),
        );
    final kind = native is FilledButton
        ? StarBridgeActionKind.primary
        : native is OutlinedButton
        ? StarBridgeActionKind.secondary
        : StarBridgeActionKind.quiet;
    final themeStyle = switch (kind) {
      StarBridgeActionKind.primary ||
      StarBridgeActionKind.danger => FilledButtonTheme.of(context).style,
      StarBridgeActionKind.secondary => OutlinedButtonTheme.of(context).style,
      StarBridgeActionKind.quiet => TextButtonTheme.of(context).style,
    };
    final defaultStyle = switch (native) {
      FilledButton button => button.defaultStyleOf(context),
      OutlinedButton button => button.defaultStyleOf(context),
      TextButton button => button.defaultStyleOf(context),
      _ => throw ArgumentError('Unsupported marketplace button'),
    };
    final style = (native.style ?? const ButtonStyle())
        .merge(themeStyle)
        .merge(defaultStyle)
        .copyWith(
          // FilledButton.styleFrom supplies a property resolving to null.
          // Native buttons fall through by resolved value, not property
          // presence; otherwise a Row label inherits the suite's typography.
          textStyle: WidgetStateProperty.resolveWith(
            (states) =>
                native.style?.textStyle?.resolve(states) ??
                themeStyle?.textStyle?.resolve(states) ??
                defaultStyle.textStyle?.resolve(states),
          ),
        );
    final data = resolveStarBridgeInteraction(context);
    if (data.suite == InteractionSuite.standard) {
      return StarBridgeActionButton(
        hoverFace: hoverFace,
        kind: kind,
        tone: danger ? ActionTone.danger : null,
        nativeStyle: style,
        focusNode: native.focusNode,
        autofocus: native.autofocus,
        onActivate: onRetry == null ? null : (_) => onRetry(),
        child: native.child!,
      );
    }
    final theme = Theme.of(context);
    final density = style.visualDensity ?? theme.visualDensity;
    final adjustment = density.baseSizeAdjustment;
    var face = density.effectiveConstraints(
      BoxConstraints(
        minWidth: style.minimumSize!.resolve(states)!.width,
        minHeight: style.minimumSize!.resolve(states)!.height,
        maxWidth: style.maximumSize!.resolve(states)!.width,
        maxHeight: style.maximumSize!.resolve(states)!.height,
      ),
    );
    if (style.fixedSize?.resolve(states) case final fixed?) {
      final size = face.constrain(fixed);
      face = face.copyWith(
        minWidth: size.width.isFinite ? size.width : null,
        maxWidth: size.width.isFinite ? size.width : null,
        minHeight: size.height.isFinite ? size.height : null,
        maxHeight: size.height.isFinite ? size.height : null,
      );
    }
    final padding = style.padding!
        .resolve(states)!
        .add(
          EdgeInsets.fromLTRB(
            adjustment.dx.clamp(0, double.infinity),
            adjustment.dy,
            adjustment.dx.clamp(0, double.infinity),
            adjustment.dy,
          ),
        )
        .clamp(EdgeInsets.zero, EdgeInsetsGeometry.infinity);
    final action = StarBridgeActionButton(
      hoverFace: hoverFace,
      kind: kind,
      tone: danger ? ActionTone.danger : null,
      focusNode: native.focusNode,
      autofocus: native.autofocus,
      nativeStyle: style.copyWith(
        minimumSize: WidgetStatePropertyAll(face.smallest),
        maximumSize: WidgetStatePropertyAll(face.biggest),
      ),
      minHeight: face.minHeight,
      padding: padding,
      onActivate: onRetry == null ? null : (_) => onRetry(),
      // Native Material installs this button style directly. Do not inherit
      // ThemeData's merged label tracking through the suite's text defaults.
      child: DefaultTextStyle.merge(
        style: style.textStyle
            ?.resolve(states)
            ?.copyWith(
              inherit: false,
              color: style.foregroundColor?.resolve(states),
            ),
        child: native.child!,
      ),
    );
    if ((style.tapTargetSize ?? theme.materialTapTargetSize) !=
        MaterialTapTargetSize.padded) {
      return action;
    }
    // Mirror Material's separate InputPadding, not a larger painted face.
    // Merge once so the original single button also owns the outer bounds.
    return MergeSemantics(
      child: Semantics(
        container: true,
        child: _MarketRetryTapPadding(
          minimum: Size(
            kMinInteractiveDimension + adjustment.dx,
            kMinInteractiveDimension + adjustment.dy,
          ),
          child: _MarketButtonFaceAlignment(child: action),
        ),
      ),
    );
  }
}

// Local equivalent of Flutter ButtonStyleButton's InputPadding. Existing
// Common/SharedAction/Suite adapters have no separate face-preserving target.
// ConstrainedBox/Center provide intrinsic and baseline layout; only padding
// hits need redirecting to the very same child, never a second callback.
class _MarketButtonFaceAlignment extends SingleChildRenderObjectWidget {
  const _MarketButtonFaceAlignment({required super.child});

  @override
  RenderPositionedBox createRenderObject(BuildContext context) =>
      _MarketButtonFaceAlignmentBox();
}

class _MarketButtonFaceAlignmentBox extends RenderPositionedBox {
  _MarketButtonFaceAlignmentBox()
    : super(alignment: Alignment.center, widthFactor: 1, heightFactor: 1);

  @override
  void performLayout() {
    if (child == null ||
        !constraints.hasTightWidth ||
        !constraints.hasBoundedWidth) {
      super.performLayout();
      return;
    }
    // Material keeps a parent's stretched width for the painted face, while
    // centering the shorter face inside its separate vertical tap padding.
    child!.layout(
      BoxConstraints(
        minWidth: constraints.maxWidth,
        maxWidth: constraints.maxWidth,
        maxHeight: constraints.maxHeight,
      ),
      parentUsesSize: true,
    );
    size = constraints.constrain(child!.size);
    alignChild();
  }
}

class _MarketRetryTapPadding extends SingleChildRenderObjectWidget {
  const _MarketRetryTapPadding({required this.minimum, required super.child});
  final Size minimum;
  @override
  RenderConstrainedBox createRenderObject(BuildContext context) =>
      _MarketRetryTapPaddingBox(minimum);
  @override
  void updateRenderObject(BuildContext context, RenderConstrainedBox box) =>
      box.additionalConstraints = BoxConstraints(
        minWidth: minimum.width,
        minHeight: minimum.height,
      );
}

class _MarketRetryTapPaddingBox extends RenderConstrainedBox {
  _MarketRetryTapPaddingBox(Size minimum)
    : super(
        additionalConstraints: BoxConstraints(
          minWidth: minimum.width,
          minHeight: minimum.height,
        ),
      );
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTestChildren(result, position: position)) return true;
    final target = child;
    if (target == null) return false;
    final center = target.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(center),
      position: center,
      hitTest: (result, position) => target.hitTest(result, position: position),
    );
  }
}

class MarketStale extends StatelessWidget {
  const MarketStale(this.readAt, {required this.retry, super.key});
  final DateTime readAt;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(marketText(context, 'stale')),
      Tooltip(
        message: readAt.toLocal().toString(),
        child: Text(
          '${readAt.toLocal().hour.toString().padLeft(2, '0')}:${readAt.toLocal().minute.toString().padLeft(2, '0')}',
        ),
      ),
      _MarketRetryAction(retry),
    ],
  );
}

class MarketNotice extends StatelessWidget {
  const MarketNotice(this.text, {this.retry, super.key});
  final String text;
  final VoidCallback? retry;
  @override
  // One centred, fixed-width block wherever it is placed, so a tall parent
  // never stretches it into a narrow column (the empty 合约 tab did).
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: CustomPaint(
          painter: MarketDashedFrame(context.tokens.surfaces.panel.border),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StarBridgeIcon(
                  retry == null
                      ? StarBridgeIconSemantic.marketplace
                      : StarBridgeIconSemantic.warning,
                  color: context.tokens.colors.textSecondary,
                  size: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  text,
                  style: TextStyle(color: context.tokens.colors.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  marketText(
                    context,
                    retry == null ? 'emptyHint' : 'failureHint',
                  ),
                  style: TextStyle(
                    fontSize: context.tokens.typography.label,
                    color: context.tokens.colors.textSecondary,
                  ),
                ),
                if (retry != null) _MarketRetryAction(retry!),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class MarketDashedFrame extends CustomPainter {
  MarketDashedFrame(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.zero));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (double i = 0; i < metric.length; i += 10) {
        canvas.drawPath(
          metric.extractPath(i, (i + 5).clamp(0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(MarketDashedFrame oldDelegate) =>
      color != oldDelegate.color;
}

class MarketSkeleton extends StatelessWidget {
  const MarketSkeleton({this.kind = 'categories', super.key});
  final String kind;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final categories = kind == 'categories', quotes = kind == 'quotes';
      final columns = quotes
          ? 1
          : categories
          ? (box.maxWidth >= 850 ? 9 : 3)
          : (box.maxWidth / 196).floor().clamp(1, 20);
      final extent = quotes
          ? 56.0
          : categories
          ? (box.maxWidth >= 850 ? 108.0 : 66.0)
          : kind == 'latest'
          ? 280.0
          : 100.0;
      final count = quotes
          ? 3
          : categories
          ? 9
          : columns * (kind == 'latest' ? 2 : 1);
      return Semantics(
        label: marketText(context, 'loading'),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: extent,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (_, i) => Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.tokens.surfaces.panel.fill,
              borderRadius: BorderRadius.circular(9),
            ),
            child: ColoredBox(
              color: Color.lerp(
                context.tokens.surfaces.panel.fill,
                context.tokens.colors.textPrimary,
                .035,
              )!,
            ),
          ),
        ),
      );
    },
  );
}

class MarketStamp extends StatelessWidget {
  const MarketStamp(this.readAt, {super.key});
  final DateTime? readAt;
  @override
  Widget build(BuildContext context) {
    if (readAt == null) return const SizedBox.shrink();
    final time = readAt!.toLocal();
    final age = DateTime.now().difference(time).inMinutes.clamp(0, 52560000);
    final en = marketLocale(context) == 'en';
    final relative = age < 1
        ? (en ? 'Just updated' : '刚刚更新')
        : age < 60
        ? (en ? 'Updated ${age}m ago' : '$age 分钟前更新')
        : (en ? 'Updated ${age ~/ 60}h ago' : '${age ~/ 60} 小时前更新');
    return Tooltip(
      message: time.toString(),
      child: Text(
        relative,
        style: TextStyle(
          fontSize: context.tokens.typography.label,
          color: context.tokens.colors.textSecondary,
        ),
      ),
    );
  }
}

/// Rows of the previous filter while the new filter's rows load (user 10-29 via
/// 调度: a click answers at once, the page never blanks). They dim at once;
/// after a second "正在加载…" shows; after ten the wait shows its length and
/// can be cancelled, which puts the previous filter back.
class MarketRefilter extends StatefulWidget {
  const MarketRefilter({
    required this.active,
    required this.onCancel,
    required this.child,
    super.key,
  });
  final bool active;
  final VoidCallback onCancel;
  final Widget child;
  @override
  State<MarketRefilter> createState() => _MarketRefilterState();
}

class _MarketRefilterState extends State<MarketRefilter> {
  Timer? _tick;
  int _seconds = 0;

  void _sync() {
    if (widget.active && _tick == null) {
      _seconds = 0;
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
    } else if (!widget.active && _tick != null) {
      _tick!.cancel();
      _tick = null;
      _seconds = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(MarketRefilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final still = MediaQuery.disableAnimationsOf(context);
    final slow = _seconds >= 10;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        AnimatedOpacity(
          opacity: widget.active ? 0.45 : 1,
          duration: still ? Duration.zero : const Duration(milliseconds: 120),
          child: IgnorePointer(ignoring: widget.active, child: widget.child),
        ),
        if (widget.active && _seconds >= 1)
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Semantics(
                liveRegion: true,
                child: DecoratedBox(
                  key: const Key('market-refilter-status'),
                  decoration: BoxDecoration(
                    color: t.surfaces.panel.fill,
                    border: Border.all(color: t.surfaces.panel.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            // Reduced motion: a still ring instead of a spinner.
                            value: still ? 0.75 : null,
                          ),
                        ),
                        Text(
                          slow
                              ? marketTextN(context, 'refilterSlow', _seconds)
                              : marketText(context, 'refilterLoading'),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: t.colors.textPrimary,
                          ),
                        ),
                        if (slow)
                          marketTextAction(
                            key: const Key('market-refilter-cancel'),
                            onPressed: widget.onCancel,
                            child: Text(marketText(context, 'refilterCancel')),
                          )
                        else
                          const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
