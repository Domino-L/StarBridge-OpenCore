import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

@immutable
final class MotionTokens {
  const MotionTokens({
    required this.pointerPageSwap,
    required this.pointerMicro,
    required this.surfaceEnter,
    required this.surfaceExit,
    required this.tooltipDelay,
    required this.enterCurve,
    required this.exitCurve,
    required this.pageOffset,
    required this.splashEnabled,
  });

  final Duration pointerPageSwap;
  final Duration pointerMicro;
  final Duration surfaceEnter;
  final Duration surfaceExit;
  final Duration tooltipDelay;
  final Curve enterCurve;
  final Curve exitCurve;
  final double pageOffset;
  final bool splashEnabled;

  Duration get keyboard => Duration.zero;

  MotionTokens get stilled => MotionTokens(
    pointerPageSwap: Duration.zero,
    pointerMicro: Duration.zero,
    surfaceEnter: Duration.zero,
    surfaceExit: Duration.zero,
    tooltipDelay: tooltipDelay,
    enterCurve: enterCurve,
    exitCurve: exitCurve,
    pageOffset: 0,
    splashEnabled: false,
  );
}
