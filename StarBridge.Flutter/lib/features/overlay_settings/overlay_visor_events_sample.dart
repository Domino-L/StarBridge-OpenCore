import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// Sample events laid out the visor's way (StarBridge.Desktop
/// OverlayVisorDraw.Events), so the editors show the events block at the size
/// the visor gives it (11-11 user: "事件的大小和位置还是不对，我觉得应该跟用户选择的
/// 最大同时事件挂钩"): the group title, then one row per event up to the
/// "most events at once" setting, each 70 design units tall (the type with its
/// time, the detail below, a bar on the screen-edge side and a rule). On the
/// right side everything reads from the right edge.
///
/// [unit] is surface pixels per visor design unit (0.53 x the size setting x
/// screen height / 1080); the parent gives the box the visor places the events
/// by (OverlayVisorLayout.eventsPlacement).
class OverlayVisorEventsSample extends StatelessWidget {
  const OverlayVisorEventsSample({
    super.key,
    required this.count,
    required this.right,
    required this.unit,
    this.textOpacity = 1,
    this.decorationOpacity = 1,
  });

  /// How many events (1 to 5).
  final int count;
  final bool right;
  final double unit;

  /// The events' text and decoration opacities, apart, as the visor draws
  /// its text and its shapes (review CX-VISOR-EVENTS3D-R1).
  final double textOpacity, decorationOpacity;

  static const _labelHeight = 22.0, _row = 70.0;
  static const _times = ['20:41', '20:39', '20:37', '20:35', '20:33'];

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = context.tokens.colors;
    final u = unit;
    final align = right ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    TextStyle style(double size, Color color, FontWeight weight) => TextStyle(
      fontSize: size * u,
      height: 1.0,
      color: color.withValues(alpha: color.a * textOpacity.clamp(0.0, 1.0)),
      fontWeight: weight,
    );
    Widget line(String text, TextStyle style) => Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: style,
    );
    final rows = count.clamp(1, 5);
    // rows past the box are clipped, as in the visor (never an overflow)
    return ClipRect(
      key: const Key('overlay-visor-events-sample'),
      child: OverflowBox(
        alignment: right ? Alignment.topRight : Alignment.topLeft,
        maxHeight: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: align,
          children: [
            SizedBox(
              height: _labelHeight * u,
              child: line(
                strings.text('overlay.sample.eventsTitle'),
                style(13, colors.textSecondary, FontWeight.w500),
              ),
            ),
            for (var i = 0; i < rows; i++)
              SizedBox(
                key: Key('overlay-visor-events-sample-row-$i'),
                height: _row * u,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // the bar on the screen-edge side
                    Positioned(
                      top: 2 * u,
                      height: 46 * u,
                      width: 2.5 * u,
                      left: right ? null : 0,
                      right: right ? 0 : null,
                      child: ColoredBox(
                        color: colors.accent.withValues(
                          alpha: 0.3 * decorationOpacity.clamp(0.0, 1.0),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      left: right ? 0 : 10 * u,
                      right: right ? 10 * u : 0,
                      child: Column(
                        crossAxisAlignment: align,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            textDirection: right
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              line(
                                strings.text(
                                  'overlay.sample.visorEvent${i + 1}Type',
                                ),
                                style(16, colors.accent, FontWeight.w600),
                              ),
                              SizedBox(width: 10 * u),
                              line(
                                _times[i],
                                style(
                                  13,
                                  colors.textSecondary,
                                  FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8 * u),
                          line(
                            strings.text(
                              'overlay.sample.visorEvent${i + 1}Detail',
                            ),
                            style(15, colors.textPrimary, FontWeight.w500),
                          ),
                          SizedBox(height: 14 * u),
                          // the rule under the row
                          Container(
                            height: 1,
                            width: 300 * u,
                            color: colors.accent.withValues(
                              alpha: 0.18 * decorationOpacity.clamp(0.0, 1.0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Surface pixels per visor design unit for these settings on [surface].
  static double unitFor(double sizeFactor, Size surface) =>
      0.53 * sizeFactor * surface.height / 1080;
}
