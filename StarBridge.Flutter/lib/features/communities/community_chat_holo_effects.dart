import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo.dart';
import 'community_chat_controller.dart';
import 'community_chat_copy.dart';

/// Holo chat send/receive effects (user decision 2026-10-29, option one,
/// tuned): only the newest arrival plays, text is fully readable within
/// 0.2 s, nothing plays for history, catch-up batches or while the reader is
/// scrolled up, and reduced motion turns every effect off.
enum CommunityChatHoloArrivalKind { incoming, ownReveal, ownConfirmed }

const _arrivalLength = Duration(milliseconds: 1300);

/// Shared by every holo effect: the light edge colour, between the accent
/// and the primary text.
Color communityChatHoloLight(BuildContext context) => Color.lerp(
  context.tokens.colors.accent,
  context.tokens.colors.textPrimary,
  .55,
)!;

mixin CommunityChatHoloEffects<T extends StatefulWidget>
    on State<T>, TickerProvider {
  late final AnimationController holoArrival = AnimationController(
    vsync: this,
    duration: _arrivalLength,
  );
  Object? _arrivalId;
  CommunityChatHoloArrivalKind _arrivalKind =
      CommunityChatHoloArrivalKind.incoming;

  /// The first message that was unread when this visit's first read landed.
  String? holoUnreadRef;
  bool _unreadCaptured = false;
  bool holoLoadingOlder = false;
  int _localCount = 0;

  bool get _holoActive =>
      mounted &&
      OrganizationHolo.of(context) &&
      !resolveStarBridgeInteraction(context).reduceMotion;

  void holoReset(CommunityChatController model) {
    holoArrival.value = 0;
    _arrivalId = null;
    holoUnreadRef = null;
    _unreadCaptured = false;
    holoLoadingOlder = false;
    _localCount = model.localMessages.length;
    holoCaptureUnread(model);
  }

  void holoCaptureUnread(CommunityChatController model) {
    if (_unreadCaptured || !model.hasLoaded || model.loading) return;
    _unreadCaptured = true;
    final unread = model.unreadCount, messages = model.messages;
    if (unread > 0 && unread <= messages.length && !model.hasNewer) {
      holoUnreadRef = messages[messages.length - unread].messageRef;
    }
  }

  /// Called after each model change with the newest sequence before it.
  void holoObserve(
    CommunityChatController model, {
    required int? previousLast,
    required bool following,
  }) {
    final settled = _unreadCaptured;
    holoCaptureUnread(model);
    final locals = model.localMessages.length;
    final grewLocal = locals > _localCount, shrankLocal = locals < _localCount;
    _localCount = locals;
    // Nothing for the first read, history, or a reader scrolled up.
    if (!settled || !following) return;
    if (grewLocal) {
      _arrive(model.localMessages.last, CommunityChatHoloArrivalKind.ownReveal);
      return;
    }
    final newest = model.messages.lastOrNull;
    if (newest == null || previousLast == null) return;
    if (newest.sequence <= previousLast) return;
    _arrive(
      newest.messageRef,
      !newest.isSelf
          ? CommunityChatHoloArrivalKind.incoming
          // The local copy already played; the server copy only confirms.
          : shrankLocal
          ? CommunityChatHoloArrivalKind.ownConfirmed
          : CommunityChatHoloArrivalKind.ownReveal,
    );
  }

  void _arrive(Object id, CommunityChatHoloArrivalKind kind) {
    if (!_holoActive) return;
    _arrivalId = id;
    _arrivalKind = kind;
    holoArrival.forward(from: 0);
  }

  /// Wraps the tile that is arriving now; every other tile is returned as is.
  Widget holoTile(Object id, Widget tile) => id == _arrivalId
      ? CommunityChatHoloArrival(
          animation: holoArrival,
          kind: _arrivalKind,
          child: tile,
        )
      : tile;

  /// The signal line under the chat title, swept by an incoming message.
  Widget holoSignal() => SizedBox(
    height: 1,
    child: AnimatedBuilder(
      animation: holoArrival,
      builder: (context, _) {
        final ms = holoArrival.value * _arrivalLength.inMilliseconds;
        if (_arrivalKind != CommunityChatHoloArrivalKind.incoming ||
            !holoArrival.isAnimating ||
            ms > 500) {
          return const SizedBox.shrink();
        }
        return CustomPaint(
          painter: _SweepPainter(ms / 500, communityChatHoloLight(context)),
        );
      },
    ),
  );

  int holoNewCount(CommunityChatController model, int observedLatest) => model
      .messages
      .where((m) => !m.isSelf && m.sequence > observedLatest)
      .length;

  @override
  void dispose() {
    holoArrival.dispose();
    super.dispose();
  }
}

class CommunityChatHoloArrival extends StatelessWidget {
  const CommunityChatHoloArrival({
    required this.animation,
    required this.kind,
    required this.child,
    super.key,
  });

  final Animation<double> animation;
  final CommunityChatHoloArrivalKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final light = communityChatHoloLight(context);
    final accent = context.tokens.colors.accent;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final ms = animation.value * _arrivalLength.inMilliseconds;
        // The tree keeps its shape after the arrival; only painting stops.
        final reveal = switch (kind) {
          CommunityChatHoloArrivalKind.incoming => _ease(ms / 200),
          CommunityChatHoloArrivalKind.ownReveal => _ease(ms / 220),
          CommunityChatHoloArrivalKind.ownConfirmed => 1.0,
        };
        return CustomPaint(
          foregroundPainter: _ArrivalPainter(
            kind: kind,
            ms: ms,
            reveal: reveal,
            light: light,
            accent: accent,
          ),
          child: ClipRect(
            clipper: _RevealClipper(
              reveal,
              fromEnd: kind == CommunityChatHoloArrivalKind.ownReveal,
              vertical: kind == CommunityChatHoloArrivalKind.incoming,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

double _ease(double x) => 1 - math.pow(1 - x.clamp(0.0, 1.0), 3).toDouble();
double _fade(double ms, double start, double length) =>
    1 - ((ms - start) / length).clamp(0.0, 1.0);

class _RevealClipper extends CustomClipper<Rect> {
  const _RevealClipper(
    this.fraction, {
    required this.fromEnd,
    required this.vertical,
  });
  final double fraction;
  final bool fromEnd, vertical;

  @override
  Rect getClip(Size size) {
    if (fraction >= 1) return Offset.zero & size;
    if (vertical) {
      return Rect.fromLTWH(0, 0, size.width, size.height * fraction);
    }
    final width = size.width * fraction;
    return fromEnd
        ? Rect.fromLTWH(size.width - width, 0, width, size.height)
        : Rect.fromLTWH(0, 0, width, size.height);
  }

  @override
  bool shouldReclip(_RevealClipper old) =>
      old.fraction != fraction ||
      old.fromEnd != fromEnd ||
      old.vertical != vertical;
}

class _ArrivalPainter extends CustomPainter {
  _ArrivalPainter({
    required this.kind,
    required this.ms,
    required this.reveal,
    required this.light,
    required this.accent,
  });
  final CommunityChatHoloArrivalKind kind;
  final double ms, reveal;
  final Color light, accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    switch (kind) {
      case CommunityChatHoloArrivalKind.incoming:
        _scanlines(canvas, rect, .6 * _fade(ms, 100, 300));
        if (reveal < 1) {
          final y = size.height * reveal;
          _edge(canvas, Offset(0, y), Offset(size.width, y));
        }
        final bar = _fade(ms, 200, 1000);
        if (bar > 0) {
          canvas.drawRect(
            Rect.fromLTWH(0, 6, 2, math.max(0, size.height - 12)),
            Paint()..color = accent.withValues(alpha: bar),
          );
        }
      case CommunityChatHoloArrivalKind.ownReveal:
        _scanlines(canvas, rect, .5 * (1 - reveal));
        if (reveal < 1) {
          final x = size.width * (1 - reveal);
          _edge(canvas, Offset(x, 0), Offset(x, size.height));
        }
      case CommunityChatHoloArrivalKind.ownConfirmed:
        final alpha = ms < 100 ? .9 : .9 * _fade(ms, 100, 240);
        communityChatHoloCorners(canvas, rect, light.withValues(alpha: alpha));
    }
  }

  void _edge(Canvas canvas, Offset a, Offset b) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = light.withValues(alpha: .6)
        ..strokeWidth = 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = light
        ..strokeWidth = 1.5,
    );
  }

  void _scanlines(Canvas canvas, Rect rect, double alpha) {
    if (alpha <= 0) return;
    final paint = Paint()..color = light.withValues(alpha: .22 * alpha);
    for (var y = rect.top; y < rect.bottom; y += 3) {
      canvas.drawRect(Rect.fromLTWH(rect.left, y, rect.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_ArrivalPainter old) =>
      old.ms != ms || old.reveal != reveal || old.kind != kind;
}

/// Four L-shaped holo corners just inside [rect].
void communityChatHoloCorners(Canvas canvas, Rect rect, Color color) {
  if (color.a <= 0) return;
  const arm = 10.0;
  final paint = Paint()
    ..color = color
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;
  final r = rect.deflate(1);
  for (final (corner, dx, dy) in [
    (r.topLeft, 1.0, 1.0),
    (r.topRight, -1.0, 1.0),
    (r.bottomLeft, 1.0, -1.0),
    (r.bottomRight, -1.0, -1.0),
  ]) {
    canvas.drawPath(
      Path()
        ..moveTo(corner.dx + dx * arm, corner.dy)
        ..lineTo(corner.dx, corner.dy)
        ..lineTo(corner.dx, corner.dy + dy * arm),
      paint,
    );
  }
}

/// Static faint corners around a message that is still sending.
class CommunityChatHoloSending extends StatelessWidget {
  const CommunityChatHoloSending({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!OrganizationHolo.of(context) ||
        resolveStarBridgeInteraction(context).reduceMotion) {
      return child;
    }
    return CustomPaint(
      foregroundPainter: _CornersPainter(
        communityChatHoloLight(context).withValues(alpha: .4),
      ),
      child: child,
    );
  }
}

class _CornersPainter extends CustomPainter {
  const _CornersPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) =>
      communityChatHoloCorners(canvas, Offset.zero & size, color);
  @override
  bool shouldRepaint(_CornersPainter old) => old.color != color;
}

class _SweepPainter extends CustomPainter {
  const _SweepPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * .3;
    final left = progress * (size.width + width) - width;
    final rect = Rect.fromLTWH(left, 0, width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color,
            color.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.progress != progress;
}

/// The faint static scanline texture behind holo messages. Off with
/// reduced motion, so the surface is plain.
class CommunityChatHoloAmbient extends StatelessWidget {
  const CommunityChatHoloAmbient({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!OrganizationHolo.of(context) ||
        resolveStarBridgeInteraction(context).reduceMotion) {
      return child;
    }
    return CustomPaint(
      painter: _TexturePainter(communityChatHoloLight(context)),
      child: child,
    );
  }
}

class _TexturePainter extends CustomPainter {
  const _TexturePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: .035);
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_TexturePainter old) => old.color != color;
}

/// "New messages below": drawn once at the first message that was unread
/// when the chat opened; the line draws out from the centre.
class CommunityChatUnreadBreak extends StatelessWidget {
  const CommunityChatUnreadBreak({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = context.tokens.colors.accent;
    final reduce = resolveStarBridgeInteraction(context).reduceMotion;
    Widget line(Alignment from) => Expanded(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduce ? 1 : 0, end: 1),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        builder: (context, value, _) => Align(
          alignment: from,
          child: FractionallySizedBox(
            widthFactor: value,
            child: Container(height: 1, color: accent.withValues(alpha: .6)),
          ),
        ),
      ),
    );
    return Padding(
      key: const Key('community-chat-unread-break'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          line(Alignment.centerRight),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              communityChatText(context, 'unreadBelow'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(letterSpacing: 2, color: accent),
            ),
          ),
          line(Alignment.centerLeft),
        ],
      ),
    );
  }
}

/// First open without anything to show yet: quiet placeholder rows instead
/// of a blank list. A light passes over them unless motion is reduced.
class CommunityChatHoloSkeleton extends StatefulWidget {
  const CommunityChatHoloSkeleton({super.key});
  @override
  State<CommunityChatHoloSkeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<CommunityChatHoloSkeleton>
    with SingleTickerProviderStateMixin {
  late final _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (resolveStarBridgeInteraction(context).reduceMotion) {
      _shine.stop();
    } else if (!_shine.isAnimating) {
      _shine.repeat();
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.tokens.colors.textPrimary;
    const rows = [
      (320.0, 120.0, false),
      (260.0, 90.0, false),
      (380.0, 110.0, true),
      (220.0, 80.0, false),
      (300.0, 100.0, false),
    ];
    return AnimatedBuilder(
      key: const Key('community-chat-skeleton'),
      animation: _shine,
      builder: (context, _) {
        final glow = _shine.isAnimating
            ? .05 + .04 * math.sin(_shine.value * 2 * math.pi)
            : .06;
        final fill = base.withValues(alpha: glow);
        Widget bar(double width) => Container(
          width: width,
          height: 10,
          margin: const EdgeInsets.only(top: 6),
          color: fill,
        );
        return ExcludeSemantics(
          child: ListView(
            primary: false,
            children: [
              for (final (text, meta, self) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    textDirection: self ? TextDirection.rtl : null,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 36, height: 36, color: fill),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: self
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [bar(meta), bar(text)],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Loading older messages: a thin line in place of the button, so the row
/// above the list never disappears and comes back.
class CommunityChatOlderProgress extends StatelessWidget {
  const CommunityChatOlderProgress({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      key: const Key('community-chat-older-progress'),
      width: 160,
      height: 36,
      child: Center(
        child: LinearProgressIndicator(
          minHeight: 2,
          value: resolveStarBridgeInteraction(context).reduceMotion ? .5 : null,
          color: context.tokens.colors.accent,
          backgroundColor: OrganizationHoloColors(context).hair,
        ),
      ),
    ),
  );
}
