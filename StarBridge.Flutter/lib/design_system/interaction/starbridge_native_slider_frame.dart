import 'package:flutter/material.dart';

/// Native geometry and recognizers stay alive. Position follows the owner's
/// actual value independently of decorative animation, including input handoff.
/// Static input never exposes a muted Material discrete-position tween. No SDK-private
/// state/controller access, value changes, persistence or callback ownership.
class StarBridgeNativeSliderFrame extends StatelessWidget {
  const StarBridgeNativeSliderFrame({
    required this.child,
    required this.instant,
    required this.engaged,
    this.indicatorLabel,
    super.key,
  });
  final Slider child;
  final bool instant, engaged;

  /// Painted value text, separate from the native slider's accessible name.
  final String? indicatorLabel;

  @override
  Widget build(BuildContext context) {
    final original = SliderTheme.of(context);
    final indicator =
        original.valueIndicatorShape ??
        (Theme.of(context).useMaterial3
            ? const DropSliderValueIndicatorShape()
            : const RectangularSliderValueIndicatorShape());
    final range = child.max - child.min;
    var value = range == 0 ? 0.0 : (child.value - child.min) / range;
    final steps = child.divisions;
    if (steps != null && steps > 0) value = (value * steps).round() / steps;
    final position = _Position(
      value.clamp(0, 1),
      child.onChanged != null,
      steps != null,
      engaged,
      original.trackShape ?? const RoundedRectSliderTrackShape(),
      original.thumbShape ?? const RoundSliderThumbShape(),
      original.overlayShape ?? const RoundSliderOverlayShape(),
      indicatorLabel ?? child.label,
      MediaQuery.textScalerOf(context),
      instant,
    );
    final style = original.copyWith(
      trackShape: _Track(position),
      thumbShape: _Thumb(position),
      tickMarkShape: _Ticks(
        position,
        original.tickMarkShape ?? const RoundSliderTickMarkShape(),
      ),
      overlayShape: _Overlay(position),
      // Preserve the native rectangular marker's colour-resolution contract.
      valueIndicatorShape: indicator is RectangularSliderValueIndicatorShape
          ? _RectangularIndicator(position, indicator)
          : _Indicator(position, indicator),
      showValueIndicator: instant
          ? ShowValueIndicator.never
          : original.showValueIndicator,
    );
    // A stable parent mutes native decorative tickers in static mode without
    // replacing the Slider/recognizer. Shapes still read the owner's real value,
    // so held drags and discrete updates do not freeze with those tickers.
    return TickerMode(
      enabled: !instant,
      child: SliderTheme(data: style, child: child),
    );
  }
}

class _Position {
  const _Position(
    this.value,
    this.enabled,
    this.discrete,
    this.engaged,
    this.track,
    this.thumb,
    this.overlay,
    this.label,
    this.textScaler,
    this.instant,
  );
  final double value;
  final bool enabled, discrete, engaged, instant;
  final SliderTrackShape track;
  final SliderComponentShape thumb, overlay;
  final String? label;
  final TextScaler textScaler;
  Animation<double> get enable =>
      enabled ? kAlwaysCompleteAnimation : kAlwaysDismissedAnimation;
  Animation<double> get activation =>
      enabled && engaged ? kAlwaysCompleteAnimation : kAlwaysDismissedAnimation;

  TextPainter indicatorPainter(TextPainter original) => TextPainter(
    text: TextSpan(text: label ?? '', style: original.text?.style),
    textAlign: original.textAlign,
    textDirection: original.textDirection,
    textScaler: original.textScaler,
    maxLines: original.maxLines,
    ellipsis: original.ellipsis,
    locale: original.locale,
    strutStyle: original.strutStyle,
    textWidthBasis: original.textWidthBasis,
    textHeightBehavior: original.textHeightBehavior,
  )..layout();

  Offset center(
    RenderBox box,
    Offset offset,
    SliderThemeData theme,
    TextDirection direction,
  ) {
    final rect = track.getPreferredRect(
      parentBox: box,
      offset: offset,
      sliderTheme: theme,
      // Material's paint measurement uses this public method's default flag;
      // enabled colours/animation are independent. Keep explicit theme insets.
      isEnabled: false,
      isDiscrete: discrete,
    );
    final t = direction == TextDirection.rtl ? 1 - value : value;
    final padding = track.isRounded ? rect.height : 0.0;
    final x = discrete
        ? rect.left + t * (rect.width - padding) + padding / 2
        : rect.left + t * rect.width;
    final thumbSize = thumb.getPreferredSize(enabled, discrete);
    final inset = padding > thumbSize.width / 2 ? padding / 2 : 0.0;
    return Offset(
      x.clamp(rect.left + inset, rect.right - inset),
      rect.center.dy,
    );
  }
}

class _Track extends SliderTrackShape {
  const _Track(this.position);
  final _Position position;
  @override
  bool get isRounded => position.track.isRounded;
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) => position.track.getPreferredRect(
    parentBox: parentBox,
    offset: offset,
    sliderTheme: sliderTheme,
    isEnabled: isEnabled,
    isDiscrete: isDiscrete,
  );

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final center = position.center(
      parentBox,
      offset,
      sliderTheme,
      textDirection,
    );
    if (position.instant && position.enabled && position.engaged) {
      final label = TextPainter(
        text: TextSpan(
          text: position.label ?? '',
          style: sliderTheme.valueIndicatorTextStyle,
        ),
        textDirection: textDirection,
        textScaler: position.textScaler,
      )..layout();
      position.overlay.paint(
        context,
        center,
        activationAnimation: kAlwaysCompleteAnimation,
        enableAnimation: position.enable,
        isDiscrete: isDiscrete,
        labelPainter: label,
        parentBox: parentBox,
        sliderTheme: sliderTheme,
        textDirection: textDirection,
        value: position.value,
        textScaleFactor: position.textScaler.scale(1),
        sizeWithOverflow: parentBox.size,
      );
      label.dispose();
    }
    position.track.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: position.instant ? position.enable : enableAnimation,
      textDirection: textDirection,
      thumbCenter: center,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
    );
  }
}

class _Thumb extends SliderComponentShape {
  const _Thumb(this.position);
  final _Position position;
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      position.thumb.getPreferredSize(isEnabled, isDiscrete);
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) => position.thumb.paint(
    context,
    position.center(parentBox, Offset.zero, sliderTheme, textDirection),
    activationAnimation: position.instant
        ? position.activation
        : activationAnimation,
    enableAnimation: position.instant ? position.enable : enableAnimation,
    isDiscrete: isDiscrete,
    labelPainter: labelPainter,
    parentBox: parentBox,
    sliderTheme: sliderTheme,
    textDirection: textDirection,
    value: position.value,
    textScaleFactor: textScaleFactor,
    sizeWithOverflow: sizeWithOverflow,
  );
}

class _Ticks extends SliderTickMarkShape {
  const _Ticks(this.position, this.delegate);
  final _Position position;
  final SliderTickMarkShape delegate;
  @override
  Size getPreferredSize({
    required SliderThemeData sliderTheme,
    required bool isEnabled,
  }) =>
      delegate.getPreferredSize(sliderTheme: sliderTheme, isEnabled: isEnabled);
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    required bool isEnabled,
    required TextDirection textDirection,
  }) => delegate.paint(
    context,
    center,
    parentBox: parentBox,
    sliderTheme: sliderTheme,
    enableAnimation: position.instant ? position.enable : enableAnimation,
    thumbCenter: position.center(
      parentBox,
      Offset.zero,
      sliderTheme,
      textDirection,
    ),
    isEnabled: isEnabled,
    textDirection: textDirection,
  );
}

class _Overlay extends SliderComponentShape {
  const _Overlay(this.position);
  final _Position position;
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      position.overlay.getPreferredSize(isEnabled, isDiscrete);
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    if (position.instant) return;
    position.overlay.paint(
      context,
      position.center(parentBox, Offset.zero, sliderTheme, textDirection),
      activationAnimation: activationAnimation,
      enableAnimation: enableAnimation,
      isDiscrete: isDiscrete,
      labelPainter: labelPainter,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      textDirection: textDirection,
      value: position.value,
      textScaleFactor: textScaleFactor,
      sizeWithOverflow: sizeWithOverflow,
    );
  }
}

class _Indicator extends SliderComponentShape with _IndicatorPaint {
  const _Indicator(this.position, this.delegate);
  @override
  final _Position position;
  @override
  final SliderComponentShape delegate;
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      delegate.getPreferredSize(isEnabled, isDiscrete);
}

class _RectangularIndicator extends RectangularSliderValueIndicatorShape
    with _IndicatorPaint {
  const _RectangularIndicator(this.position, this.delegate);
  @override
  final _Position position;
  @override
  final RectangularSliderValueIndicatorShape delegate;
  @override
  Size getPreferredSize(
    bool isEnabled,
    bool isDiscrete, {
    TextPainter? labelPainter,
    double? textScaleFactor,
  }) {
    final numeric = labelPainter == null
        ? null
        : position.indicatorPainter(labelPainter);
    try {
      return delegate.getPreferredSize(
        isEnabled,
        isDiscrete,
        labelPainter: numeric,
        textScaleFactor: textScaleFactor,
      );
    } finally {
      numeric?.dispose();
    }
  }
}

mixin _IndicatorPaint on SliderComponentShape {
  _Position get position;
  SliderComponentShape get delegate;
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final numeric = position.indicatorPainter(labelPainter);
    try {
      delegate.paint(
        context,
        // Native value indicators are composited followers of the slider's leader;
        // their paint origin, like its thumb's, is local to that leader.
        position.center(parentBox, Offset.zero, sliderTheme, textDirection),
        activationAnimation: activationAnimation,
        enableAnimation: enableAnimation,
        isDiscrete: isDiscrete,
        labelPainter: numeric,
        parentBox: parentBox,
        sliderTheme: sliderTheme,
        textDirection: textDirection,
        value: position.value,
        textScaleFactor: textScaleFactor,
        sizeWithOverflow: sizeWithOverflow,
      );
    } finally {
      numeric.dispose();
    }
  }
}
