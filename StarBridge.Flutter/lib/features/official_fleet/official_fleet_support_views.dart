import '../../shared/guide/guide_empty_state.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/brand/scm_brand_mark.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_native_ink.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/social_read_activity.dart';

class OfficialFleetLoadingView extends StatelessWidget {
  const OfficialFleetLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Row(
        children: [
          SizedBox.square(
            dimension: tokens.icons.medium,
            child: Center(
              child: ExcludeSemantics(
                child: SocialReadActivity(
                  // The existing caller does not publish this read's source.
                  source: InteractionSource.programmatic,
                  opening: false,
                  label: AppStrings.of(context).text('officialFleet.loading'),
                  circularStandard: true,
                  circularSize: tokens.icons.medium,
                  circularStrokeWidth: 2,
                ),
              ),
            ),
          ),
          SizedBox(width: tokens.space.md),
          Text(AppStrings.of(context).text('officialFleet.loading')),
        ],
      ),
    );
  }
}

class OfficialFleetSignedOutView extends StatelessWidget {
  const OfficialFleetSignedOutView({super.key});

  @override
  Widget build(BuildContext context) =>
      guideOnlineRequired(
        context,
        AppStrings.of(context).text('navigation.officialFleet'),
      ) ??
      const OfficialFleetStatePanel(
        icon: StarBridgeIconSemantic.login,
        titleKey: 'officialFleet.signedOut.title',
        bodyKey: 'officialFleet.signedOut.body',
        showScmBrand: true,
      );
}

class OfficialFleetNotMemberView extends StatelessWidget {
  const OfficialFleetNotMemberView({required this.onRetry, super.key});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => GuideEmptyState.active(context)
      ? KeyedSubtree(
          key: const Key('official-fleet-not-member'),
          child: GuideEmptyState('fleet', onPrimary: onRetry),
        )
      : OfficialFleetStatePanel(
          key: const Key('official-fleet-not-member'),
          icon: StarBridgeIconSemantic.officialFleet,
          titleKey: 'officialFleet.notMember.title',
          bodyKey: 'officialFleet.notMember.body',
          actionKey: 'officialFleet.action.retry',
          onAction: onRetry,
        );
}

class OfficialFleetUnavailableView extends StatelessWidget {
  const OfficialFleetUnavailableView({
    required this.failureKey,
    required this.onRetry,
    super.key,
  });

  final String failureKey;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => OfficialFleetStatePanel(
    key: const Key('official-fleet-unavailable'),
    icon: StarBridgeIconSemantic.warning,
    color: context.tokens.colors.warning,
    titleKey: 'officialFleet.unavailable.title',
    bodyKey: failureKey,
    actionKey: 'officialFleet.action.retry',
    onAction: onRetry,
  );
}

class OfficialFleetStatePanel extends StatelessWidget {
  const OfficialFleetStatePanel({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
    this.color,
    this.actionKey,
    this.onAction,
    this.showScmBrand = false,
    super.key,
  });

  final StarBridgeIconSemantic icon;
  final String titleKey;
  final String bodyKey;
  final Color? color;
  final String? actionKey;
  final Future<void> Function()? onAction;
  final bool showScmBrand;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final resolvedColor = color ?? tokens.colors.accent;
    return StarBridgeSurface(
      role: SurfaceRole.raised,
      padding: EdgeInsets.all(tokens.space.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showScmBrand)
              const ScmBrandMark(key: Key('official-fleet-scm-brand'))
            else
              StarBridgeIcon(
                icon,
                size: tokens.icons.large,
                color: resolvedColor,
              ),
            SizedBox(height: tokens.space.md),
            Text(
              strings.text(titleKey),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.space.xs),
            Text(
              strings.text(bodyKey),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
            if (actionKey != null && onAction != null) ...[
              SizedBox(height: tokens.space.lg),
              _OfficialFleetRetryMotion(
                label: strings.text(actionKey!),
                onAction: onAction!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Local presentation seam: native owns input, layout and all text/icon state
/// resolution. Neither a pending Future nor decoration gates the command.
class _OfficialFleetRetryMotion extends StatefulWidget {
  const _OfficialFleetRetryMotion({
    required this.label,
    required this.onAction,
  });

  final String label;
  final Future<void> Function() onAction;

  @override
  State<_OfficialFleetRetryMotion> createState() =>
      _OfficialFleetRetryMotionState();
}

class _OfficialFleetRetryMotionState extends State<_OfficialFleetRetryMotion>
    with TickerProviderStateMixin {
  final _focus = FocusNode();
  final _ink = StarBridgeNativeInk();
  final _fx = GlobalKey<EffectHostState>();
  final _face = GlobalKey();
  late final _hover = AnimationController(vsync: this);
  late final _press = AnimationController(vsync: this);
  InteractionData? _data;
  bool _hovered = false, _pressed = false, _disposing = false;
  int _generation = 0;
  int? _pointer, _claim, _queuedCleanup;
  Offset? _globalDown;

  @override
  void initState() {
    super.initState();
    _ink.states.addListener(_statesChanged);
  }

  void _invalidateClaim({bool preservePhysical = false}) {
    final accepted = _pointer != null && _claim == _generation;
    _generation++;
    if (preservePhysical) {
      // Retiring feedback must not relabel a still-native pending mouse-up.
      // The recognizer, not a keyboard action or theme update, owns that input.
      _claim = accepted ? _generation : null;
    } else {
      _pointer = null;
      _claim = null;
      _globalDown = null;
    }
    _queuedCleanup = null;
  }

  void _clearFeedback() {
    _ink.retire();
    _fx.currentState?.clear();
    _press.value = 0;
    _hover.value = _hovered ? 1 : 0;
  }

  @override
  void didUpdateWidget(_OfficialFleetRetryMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onAction != widget.onAction) {
      _invalidateClaim(preservePhysical: true);
      _clearFeedback();
    }
  }

  void _cleanupAfterNativeCallback() {
    final generation = _generation;
    if (_queuedCleanup == generation) return;
    _queuedCleanup = generation;
    // InkWell clears pressed before its synchronous onPressed. A cancelled
    // gesture has no callback; only its unconsumed claim expires here.
    scheduleMicrotask(() {
      if (_disposing || !mounted || generation != _generation) return;
      _invalidateClaim();
    });
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointer != null || event.buttons != kPrimaryButton) return;
    _generation++;
    _queuedCleanup = null;
    _pointer = event.pointer;
    _globalDown = event.position;
    // This is only a raw candidate. Native pressed confirms acceptance below.
    _claim = null;
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (_pointer != event.pointer) return;
    _invalidateClaim();
    if (_data?.animates == true) {
      _press.reverse();
    } else {
      _press.value = 0;
    }
  }

  Rect _faceBounds(Size _) {
    final face = _face.currentContext?.findRenderObject();
    final host = _fx.currentContext?.findRenderObject();
    if (face is! RenderBox || host is! RenderBox || !face.hasSize) {
      return Rect.zero;
    }
    return face.localToGlobal(Offset.zero, ancestor: host) & face.size;
  }

  void _pointerFeedback(InteractionData data) {
    if (!data.animates || data.suite == InteractionSuite.standard) return;
    _press.value = 1;
    final bounds = _faceBounds(Size.zero);
    if (bounds.isEmpty) return;
    switch (data.suite) {
      case InteractionSuite.scan:
        _fx.currentState?.play(TransientEffect.beam);
      case InteractionSuite.glow:
        final host = _fx.currentContext?.findRenderObject() as RenderBox?;
        final point = host == null || _globalDown == null
            ? null
            : host.globalToLocal(_globalDown!);
        // Explicit FX policy for InputPadding hits, not native splash parity.
        // Standard retains InkWell's real global-position ink origin.
        final origin = point != null && bounds.contains(point)
            ? point
            : bounds.center;
        _fx.currentState?.play(
          TransientEffect.ring,
          at: origin,
          ringScale: math.min(bounds.width / 2, bounds.height * 1.4) / 9,
        );
      case InteractionSuite.standard || InteractionSuite.rail:
        break;
    }
  }

  void _statesChanged() {
    if (_disposing) return;
    final data = _data;
    if (data == null) return;
    final states = _ink.states.value;
    final hovered = states.contains(WidgetState.hovered);
    if (_hovered != hovered) {
      _hovered = hovered;
      if (!data.animates || data.suite == InteractionSuite.standard) {
        _hover.value = hovered ? 1 : 0;
      } else {
        _hover.animateTo(
          hovered ? 1 : 0,
          duration: data.timed(data.motion.hover),
        );
      }
    }
    final pressed = states.contains(WidgetState.pressed);
    if (_pressed == pressed) return;
    _pressed = pressed;
    if (pressed) {
      if (_pointer != null && _globalDown != null) {
        _claim = _generation;
        _pointerFeedback(data);
      }
    } else {
      if (data.animates) {
        _press.reverse();
      } else {
        _press.value = 0;
      }
      _cleanupAfterNativeCallback();
    }
  }

  void _activate(InteractionSource source) {
    _invalidateClaim(preservePhysical: source != InteractionSource.pointer);
    if (source != InteractionSource.pointer) _clearFeedback();
    unawaited(runStarBridgeActivation<void>(source, widget.onAction));
  }

  void _nativeActivate() => _activate(
    _claim == _generation && _pointer != null
        ? InteractionSource.pointer
        : InteractionSource.keyboard,
  );

  @override
  Widget build(BuildContext context) {
    final data = resolveStarBridgeInteraction(context);
    final old = _data;
    _data = data;
    _hover.duration = data.timed(data.motion.hover);
    _press.duration = data.timed(data.motion.press);
    if (old != null &&
        (old.suite != data.suite || old.reduceMotion != data.reduceMotion)) {
      _invalidateClaim(preservePhysical: true);
      _clearFeedback();
    }
    final themeStyle = OutlinedButtonTheme.of(context).style;
    final defaults = OutlinedButton.icon(
      onPressed: _nativeActivate,
      icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
      label: Text(widget.label),
    ).defaultStyleOf(context);
    // Resolve ONLY the paint properties owned by the retiring-ink helper.
    // Never lift default text/icon/foreground into widget style priority.
    final paint = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            themeStyle?.backgroundColor?.resolve(states) ??
            defaults.backgroundColor?.resolve(states),
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) =>
            themeStyle?.overlayColor?.resolve(states) ??
            defaults.overlayColor?.resolve(states),
      ),
      splashFactory: themeStyle?.splashFactory ?? defaults.splashFactory,
    );
    var style = _ink.resolveStyle(
      context,
      animated: data.animates && data.suite == InteractionSuite.standard,
      style: paint,
      themeStyle: themeStyle,
    );
    if (data.suite != InteractionSuite.standard) {
      // Override AFTER NativeInk has composed its background; null would fall
      // through to theme/default and draw a second face or state tint.
      style = style.copyWith(
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: const WidgetStatePropertyAll(BorderSide.none),
        splashFactory: NoSplash.splashFactory,
      );
    }
    final baseRadius =
        Theme.of(context).extension<StarBridgeTokens>()?.shape.radiusSmall ?? 6;
    final originalBuilder =
        themeStyle?.backgroundBuilder ?? defaults.backgroundBuilder;
    style = style.copyWith(
      backgroundBuilder: (context, states, child) => _OfficialFleetRetryFace(
        key: _face,
        owner: this,
        data: data,
        radius: suiteRadius(data.suite, baseRadius),
        child: originalBuilder == null
            ? child ?? const SizedBox.shrink()
            : originalBuilder(context, states, child),
      ),
    );
    return InteractionScope(
      data: data,
      child: CallbackShortcuts(
        bindings: {
          for (final key in [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.numpadEnter,
            LogicalKeyboardKey.space,
          ])
            SingleActivator(key): () => _activate(InteractionSource.keyboard),
        },
        child: Listener(
          onPointerDown: _pointerDown,
          onPointerUp: (event) {
            // Raw up can precede a held arena's native decision. Keep its
            // provenance while the real button still owns a pressed input;
            // native pressed=false handles cancellation/callback cleanup.
            if (_pointer == event.pointer &&
                !_ink.states.value.contains(WidgetState.pressed)) {
              _cleanupAfterNativeCallback();
            }
          },
          onPointerCancel: _pointerCancel,
          child: MergeSemantics(
            key: const Key('official-fleet-retry-target'),
            child: Semantics(
              // Facts and labels still come from native descendants. This
              // earlier handler prevents reader actions synthesizing mouse ink.
              onTap: () => _activate(InteractionSource.keyboard),
              child: EffectHost(
                key: _fx,
                borderRadius: suiteRadius(data.suite, baseRadius),
                boundsResolver: _faceBounds,
                child: OutlinedButton.icon(
                  key: const Key('official-fleet-retry-native'),
                  focusNode: _focus,
                  statesController: _ink.states,
                  onPressed: _nativeActivate,
                  style: style,
                  // A backgroundBuilder otherwise silently enables antiAlias
                  // clipping, losing the original outsetting focus/glow edges.
                  clipBehavior: Clip.none,
                  icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                  label: Text(widget.label),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposing = true;
    _invalidateClaim();
    _ink.states.removeListener(_statesChanged);
    _hover.dispose();
    _press.dispose();
    _focus.dispose();
    _ink.dispose();
    super.dispose();
  }
}

/// This proxy changes only paint. Inherited layout, hitTest,
/// applyPaintTransform and semantics remain untransformed native geometry.
class _OfficialFleetRetryFace extends SingleChildRenderObjectWidget {
  const _OfficialFleetRetryFace({
    required this.owner,
    required this.data,
    required this.radius,
    required super.child,
    super.key,
  });
  final _OfficialFleetRetryMotionState owner;
  final InteractionData data;
  final BorderRadius radius;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _OfficialFleetRetryPaint(owner, data, radius);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _OfficialFleetRetryPaint renderObject,
  ) {
    renderObject.update(data, radius);
  }
}

class _OfficialFleetRetryPaint extends RenderProxyBox {
  _OfficialFleetRetryPaint(this._motion, this.data, this.radius);
  final _OfficialFleetRetryMotionState _motion;
  InteractionData data;
  BorderRadius radius;
  late final _repaint = Listenable.merge([
    _motion._hover,
    _motion._press,
    _motion._focus,
    _motion._ink.states,
  ]);

  void update(InteractionData next, BorderRadius nextRadius) {
    data = next;
    radius = nextRadius;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final pr = _motion._press.value;
    final scale = switch (data.suite) {
      InteractionSuite.rail => 1 - .02 * pr,
      InteractionSuite.glow => 1 - .03 * pr,
      _ => 1.0,
    };
    final dy = data.suite == InteractionSuite.rail ? pr : 0.0;
    if (scale == 1 && dy == 0) {
      _paintBody(context, offset);
    } else {
      final center = size.center(Offset.zero);
      final transform = Matrix4.identity()
        ..translateByDouble(center.dx, center.dy + dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-center.dx, -center.dy, 0, 1);
      context.pushTransform(needsCompositing, offset, transform, _paintBody);
    }
  }

  void _paintBody(PaintingContext context, Offset offset) {
    final suite = data.suite, p = data.palette;
    final h = _motion._hover.value, pr = _motion._press.value;
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    if (suite != InteractionSuite.standard) {
      final canvas = context.canvas;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.drawRRect(
        rrect,
        Paint()..color = Color.lerp(p.raised, p.accent, .08 * h)!,
      );
      canvas.restore();
    }
    if (child != null) context.paintChild(child!, offset);
    if (suite == InteractionSuite.standard) return;
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final border = switch (suite) {
      InteractionSuite.rail => Color.lerp(p.border, p.edge(), h)!,
      InteractionSuite.glow => Color.lerp(p.border, p.edge(.8), h)!,
      _ => p.border,
    };
    canvas.drawRRect(
      rrect.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = border,
    );
    switch (suite) {
      case InteractionSuite.rail:
        canvas.save();
        canvas.clipRRect(rrect);
        if (h > 0) {
          canvas.drawRect(
            Rect.fromLTWH(0, 0, size.width, 1),
            Paint()..color = p.edge().withValues(alpha: .55 * h),
          );
        }
        paintEdgeLine(canvas, rect, p.edge(), scale: h);
        canvas.restore();
        if (pr > 0) {
          if (p.isDark) {
            paintGlowStrokes(canvas, rrect, p.edge(), pr);
          } else {
            canvas.drawRRect(
              rrect.inflate(1),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = p.accent.withValues(alpha: pr),
            );
          }
        }
      case InteractionSuite.scan:
        paintBrackets(
          canvas,
          rect.deflate(pr > 0 ? 1 : 4 - 2 * h),
          color: p.edge().withValues(alpha: math.max(h, pr)),
        );
      case InteractionSuite.glow:
        paintGlowStrokes(canvas, rrect, p.edge(.8), .8 * h);
      case InteractionSuite.standard:
        break;
    }
    if (_motion._focus.hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      canvas.drawRRect(
        rrect.inflate(2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = p.focusRing,
      );
    }
    canvas.restore();
  }
}
