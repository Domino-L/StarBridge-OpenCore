import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'effect_host.dart';
import 'icon_swap.dart';
import 'pressable.dart';
import 'suite.dart';

enum AttachmentPhase { uploading, done, failed }

/// A file attached to a chat message (draft or sent). [progress] is the real
/// upload fraction (0–1) while uploading.
@immutable
class SuiteAttachment {
  const SuiteAttachment({
    required this.id,
    required this.name,
    required this.sizeLabel,
    this.isImage = false,
    this.phase = AttachmentPhase.done,
    this.progress = 1,
  });

  final String id;
  final String name;
  final String sizeLabel;
  final bool isImage;
  final AttachmentPhase phase;
  final double progress;

  SuiteAttachment copyWith({AttachmentPhase? phase, double? progress}) =>
      SuiteAttachment(
        id: id,
        name: name,
        sizeLabel: sizeLabel,
        isImage: isImage,
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
      );
}

/// The composer's attachment tray: one chip per file with its real upload
/// state. Chips added while the tray is showing grow in (the suite's
/// short entrance); chips that were already there when the tray appeared —
/// e.g. coming back to a page whose uploads finished meanwhile — show their
/// final state with no replay.
///
/// Uploading: a thin progress line at the chip's foot follows the real
/// value and never runs backwards (rail: a fill with a lit tip; scan: ten
/// segments; glow: a soft fill with an end light; standard: plain). Done
/// while visible: the line completes and fades, the upload glyph turns into
/// the file glyph. Failed: a static danger edge, "上传失败" and a retry
/// button; nothing shakes or flashes. Removing a chip (× or Delete/Backspace) moves
/// focus to the next chip, or to [fallbackFocus].
class SuiteAttachmentTray extends StatefulWidget {
  const SuiteAttachmentTray({
    required this.attachments,
    required this.onRemove,
    required this.onRetry,
    this.fallbackFocus,
    super.key,
  });

  final List<SuiteAttachment> attachments;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onRetry;
  final FocusNode? fallbackFocus;

  @override
  State<SuiteAttachmentTray> createState() => _SuiteAttachmentTrayState();
}

class _SuiteAttachmentTrayState extends State<SuiteAttachmentTray> {
  late final Set<String> _initial;
  final _focus = <String, FocusNode>{};

  FocusNode _nodeFor(String id) =>
      _focus.putIfAbsent(id, () => FocusNode(debugLabel: 'attachment-$id'));

  /// Ids in the order last shown. Kept here rather than read from
  /// `oldWidget.attachments`: callers may change one list in place, and then
  /// the old and new widget hold the same, already changed list.
  /// Filled in [initState], not lazily: a lazy first read could already see
  /// the changed list.
  late List<String> _order;

  @override
  void initState() {
    super.initState();
    _order = [for (final a in widget.attachments) a.id];
    _initial = _order.toSet();
  }

  /// A chip that should receive focus after this frame (a removal moved it
  /// there). Counts as focused if it is removed before that happens too.
  String? _pendingFocus;
  int _focusSeq = 0;

  @override
  void didUpdateWidget(SuiteAttachmentTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = {for (final a in widget.attachments) a.id};
    final old = _order;
    String? moveTo;
    var moveToFallback = false;
    for (var i = 0; i < old.length; i++) {
      final id = old[i];
      if (now.contains(id)) continue;
      final node = _focus.remove(id);
      final hadFocus = (node?.hasFocus ?? false) || _pendingFocus == id;
      if (hadFocus) {
        String? next;
        for (var j = i + 1; j < old.length && next == null; j++) {
          if (now.contains(old[j])) next = old[j];
        }
        for (var j = i - 1; j >= 0 && next == null; j--) {
          if (now.contains(old[j])) next = old[j];
        }
        moveTo = next;
        moveToFallback = next == null;
      }
      if (node != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => node.dispose());
      }
    }
    _order = [for (final a in widget.attachments) a.id];
    if (moveTo != null || moveToFallback) {
      _pendingFocus = moveTo;
      final seq = ++_focusSeq;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // A later removal in the same frame decides instead.
        if (!mounted || seq != _focusSeq) return;
        final id = _pendingFocus;
        _pendingFocus = null;
        // Only a target that still exists: never a disposed node.
        final target = id == null ? widget.fallbackFocus : _focus[id];
        if (target != null && target.context != null) target.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final n in _focus.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    return AnimatedSize(
      duration: data.sizeDuration(const Duration(milliseconds: 160)),
      curve: SuiteMotion.curve,
      alignment: Alignment.bottomCenter,
      child: widget.attachments.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in widget.attachments)
                    _AttachmentChip(
                      key: ValueKey(a.id),
                      attachment: a,
                      focusNode: _nodeFor(a.id),
                      enter: !_initial.contains(a.id),
                      onRemove: () => widget.onRemove(a.id),
                      onRetry: () => widget.onRetry(a.id),
                    ),
                ],
              ),
            ),
    );
  }
}

class _AttachmentChip extends StatefulWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.focusNode,
    required this.enter,
    required this.onRemove,
    required this.onRetry,
    super.key,
  });

  final SuiteAttachment attachment;
  final FocusNode focusNode;
  final bool enter;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  State<_AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends State<_AttachmentChip>
    with TickerProviderStateMixin {
  late final _in = AnimationController(vsync: this, value: 1);

  /// Shown progress: eases toward the real value, never backwards.
  late final _shown = AnimationController(
    vsync: this,
    value: widget.attachment.phase == AttachmentPhase.done
        ? 1
        : widget.attachment.progress,
  );

  /// Fades the progress line out after completion (1 → 0).
  late final _line = AnimationController(
    vsync: this,
    value: widget.attachment.phase == AttachmentPhase.uploading ? 1 : 0,
  );
  final _fx = GlobalKey<EffectHostState>();

  @override
  void initState() {
    super.initState();
    if (!widget.enter) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final data = InteractionScope.of(context);
      if (!data.animates || data.suite == InteractionSuite.standard) return;
      _in
        ..duration = const Duration(milliseconds: 200)
        ..value = 0
        ..forward();
    });
  }

  @override
  void didUpdateWidget(_AttachmentChip old) {
    super.didUpdateWidget(old);
    final a = widget.attachment, o = old.attachment;
    final data = InteractionScope.of(context);
    final target = a.phase == AttachmentPhase.done ? 1.0 : a.progress;
    if (a.phase == AttachmentPhase.uploading &&
        o.phase != AttachmentPhase.uploading) {
      // Retry: start over from the real value.
      _shown.value = a.progress;
      _line.value = 1;
    } else if (target > _shown.value) {
      if (data.animates) {
        _shown.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _shown.value = target;
      }
    }
    if (a.phase == AttachmentPhase.done &&
        o.phase == AttachmentPhase.uploading) {
      if (data.animates) {
        _line
          ..duration = const Duration(milliseconds: 260)
          ..reverse();
        if (data.suite == InteractionSuite.scan) {
          _fx.currentState?.play(
            TransientEffect.bracketFlash,
            duration: const Duration(milliseconds: 320),
          );
        }
      } else {
        _line.value = 0;
      }
    }
    if (a.phase == AttachmentPhase.failed) _line.value = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (InteractionScope.of(context).animates) return;
    if (_in.isAnimating) _in.value = 1;
    if (_shown.isAnimating) {
      _shown.value = widget.attachment.phase == AttachmentPhase.done
          ? 1
          : widget.attachment.progress;
    }
    if (_line.isAnimating) _line.value = 0;
  }

  @override
  void dispose() {
    _in.dispose();
    _shown.dispose();
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final a = widget.attachment;
    final failed = a.phase == AttachmentPhase.failed;
    final uploading = a.phase == AttachmentPhase.uploading;
    final state = switch (a.phase) {
      AttachmentPhase.uploading => '上传中 ${(a.progress * 100).round()}%',
      AttachmentPhase.done => '已上传',
      AttachmentPhase.failed => '上传失败',
    };
    Widget small(IconData icon, String label, VoidCallback onTap) =>
        SuitePressable(
          kind: PressableKind.icon,
          minHeight: 22,
          padding: const EdgeInsets.all(3),
          semanticLabel: label,
          onPressed: onTap,
          child: Icon(icon, size: 13),
        );
    final chip = EffectHost(
      key: _fx,
      borderRadius: suiteRadius(data.suite, 6),
      bracketInset: -3,
      bracketLength: 5,
      child: Focus(
        focusNode: widget.focusNode,
        skipTraversal: true,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent &&
              (e.logicalKey == LogicalKeyboardKey.delete ||
                  e.logicalKey == LogicalKeyboardKey.backspace)) {
            widget.onRemove();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          container: true,
          label: '${a.name}，${a.sizeLabel}，$state',
          child: AnimatedBuilder(
            animation: Listenable.merge([_shown, _line]),
            builder: (context, child) => CustomPaint(
              foregroundPainter: _UploadLine(data, _shown.value, _line.value),
              child: child,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              decoration: BoxDecoration(
                color: p.raised,
                borderRadius: suiteRadius(data.suite, 6),
                border: Border.all(
                  color: failed ? p.danger : p.border,
                  width: failed ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  ExcludeSemantics(
                    child: SuiteIconSwap(
                      icon: failed
                          ? Icons.error_outline
                          : uploading
                          ? Icons.upload
                          : a.isImage
                          ? Icons.image_outlined
                          : Icons.description_outlined,
                      size: 15,
                      color: failed
                          ? p.danger
                          : uploading
                          ? p.textSecondary
                          : p.accent,
                    ),
                  ),
                  Flexible(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: p.textPrimary,
                            ),
                          ),
                          Text(
                            failed ? '上传失败' : a.sizeLabel,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: failed ? p.danger : p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (failed)
                    small(Icons.refresh, '重试上传${a.name}', widget.onRetry),
                  small(Icons.close, '移除${a.name}', widget.onRemove),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _in,
      child: chip,
      builder: (context, child) {
        if (_in.value >= 1) return child!;
        final c = SuiteMotion.curve.transform(_in.value);
        return Opacity(
          opacity: c,
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - c)),
            child: child,
          ),
        );
      },
    );
  }
}

class _UploadLine extends CustomPainter {
  _UploadLine(this.data, this.v, this.alpha);
  final InteractionData data;
  final double v;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0) return;
    final p = data.palette;
    final track = Rect.fromLTWH(6, size.height - 3, size.width - 12, 2);
    canvas.drawRect(
      track,
      Paint()..color = p.border.withValues(alpha: 0.5 * alpha),
    );
    final color = p.accent.withValues(alpha: alpha);
    switch (data.suite) {
      case InteractionSuite.scan:
        const n = 10;
        final w = track.width / n;
        final lit = (v * n).floor();
        for (var i = 0; i < lit; i++) {
          canvas.drawRect(
            Rect.fromLTWH(track.left + i * w, track.top, w - 1.5, 2),
            Paint()..color = color,
          );
        }
      case InteractionSuite.rail:
        final fill = Rect.fromLTWH(track.left, track.top, track.width * v, 2);
        canvas.drawRect(fill, Paint()..color = color);
        canvas.drawRect(
          Rect.fromLTWH(fill.right - 4, track.top - 0.5, 4, 3),
          Paint()..color = p.edge(alpha),
        );
      case InteractionSuite.glow:
        final fill = Rect.fromLTWH(track.left, track.top, track.width * v, 2);
        canvas.drawRect(fill, Paint()..color = color);
        final tip = Rect.fromCircle(
          center: Offset(fill.right, fill.center.dy),
          radius: 6,
        );
        canvas.drawOval(
          tip,
          Paint()
            ..shader = RadialGradient(
              colors: [p.light(0.35 * alpha), p.light(0)],
            ).createShader(tip),
        );
      case InteractionSuite.standard:
        canvas.drawRect(
          Rect.fromLTWH(track.left, track.top, track.width * v, 2),
          Paint()..color = color,
        );
    }
  }

  @override
  bool shouldRepaint(_UploadLine old) =>
      old.v != v || old.alpha != alpha || old.data != data;
}

/// A sent attachment inside a message bubble: static file row.
class SuiteAttachmentTile extends StatelessWidget {
  const SuiteAttachmentTile({required this.attachment, super.key});

  final SuiteAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final a = attachment;
    return Semantics(
      label: '附件 ${a.name}，${a.sizeLabel}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: p.surface.withValues(alpha: 0.6),
          borderRadius: suiteRadius(data.suite, 5),
          border: Border.all(color: p.border.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(
              a.isImage ? Icons.image_outlined : Icons.description_outlined,
              size: 15,
              color: p.accent,
            ),
            Flexible(
              child: Text(
                a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.textPrimary),
              ),
            ),
            Text(
              a.sizeLabel,
              style: TextStyle(fontSize: 10.5, color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
