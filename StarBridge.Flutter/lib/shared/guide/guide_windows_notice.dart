import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'guide_copy.dart';
import 'guide_scope.dart';

/// Loading: not known yet (hide the item, but do not finish the list).
enum GuideWindowsNoticeState { loading, unavailable, off, on }

/// The "Windows notifications" switch as the guide sees it. Off by default;
/// the guide only recommends it and turns it on when the user clicks.
abstract interface class GuideWindowsNoticePort {
  ValueListenable<GuideWindowsNoticeState> get state;

  /// Turns on only the Windows desktop switch, exactly like Settings does.
  Future<bool> enable();

  /// The Settings "test notification" control (shows Windows' own reason,
  /// e.g. Do Not Disturb, when nothing appears).
  Widget testButton();
}

/// Done id shared by the notifications card and the home checklist item:
/// once the user chose (turned it on, or "Later") neither asks again.
const guideWindowsNoticeId = 'notify';

/// Whether the card has something to say on the notifications page now.
bool guideWindowsNoticeCardVisible(GuideHub hub) {
  final port = hub.windowsNotice;
  if (port == null) return false;
  final state = port.state.value;
  if (hub.windowsNoticeEnabledHere.value) {
    return state == GuideWindowsNoticeState.on;
  }
  return state == GuideWindowsNoticeState.off &&
      !hub.controller.value.done.contains(guideWindowsNoticeId);
}

class GuideWindowsNoticeCard extends StatefulWidget {
  const GuideWindowsNoticeCard({required this.hub, super.key});
  final GuideHub hub;

  @override
  State<GuideWindowsNoticeCard> createState() => _GuideWindowsNoticeCardState();
}

class _GuideWindowsNoticeCardState extends State<GuideWindowsNoticeCard> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _enable() async {
    final hub = widget.hub;
    final port = hub.windowsNotice;
    if (_busy || port == null) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await port.enable();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
    });
    if (ok) {
      hub.windowsNoticeEnabledHere.value = true;
      hub.controller.markDone(guideWindowsNoticeId);
    }
  }

  void _later() {
    widget.hub.windowsNoticeRequested.value = false;
    widget.hub.controller.markDone(guideWindowsNoticeId);
  }

  void _close() {
    widget.hub.windowsNoticeEnabledHere.value = false;
    widget.hub.windowsNoticeRequested.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final copy = GuideCopy.of(context);
    final text = Theme.of(context).textTheme;
    final port = widget.hub.windowsNotice!;
    final on = widget.hub.windowsNoticeEnabledHere.value;
    final secondary = text.bodySmall?.copyWith(color: t.colors.textSecondary);
    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: t.colors.accentSoft,
        borderRadius: BorderRadius.circular(t.shape.radiusSmall),
        border: Border.all(color: t.colors.accent.withValues(alpha: .45)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space.xs),
        child: Text(
          copy.text('notice.recommended'),
          style: text.labelSmall?.copyWith(color: t.colors.accent),
        ),
      ),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: t.space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              copy.text(on ? 'notice.onTitle' : 'notice.title'),
              style: text.titleSmall,
            ),
            if (!on) badge,
          ],
        ),
        SizedBox(height: t.space.xxs),
        Text(copy.text(on ? 'notice.onBody' : 'notice.body'), style: secondary),
        if (!on)
          Text(
            copy.text('notice.choice'),
            style: text.bodySmall?.copyWith(color: t.colors.textDisabled),
          ),
        if (_failed)
          Text(
            copy.text('notice.failed'),
            key: const Key('guide-notice-failed'),
            style: text.bodySmall?.copyWith(color: t.colors.danger),
          ),
        if (on) ...[SizedBox(height: t.space.xs), port.testButton()],
      ],
    );
    return DecoratedBox(
      key: Key(on ? 'guide-notice-on' : 'guide-notice-off'),
      decoration: BoxDecoration(
        color: t.surfaces.raised.fill,
        borderRadius: BorderRadius.circular(t.shape.radiusMedium),
        border: Border.all(color: t.surfaces.raised.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(t.space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: body),
            SizedBox(width: t.space.sm),
            if (on)
              StarBridgeActionButton(
                controlKey: const Key('guide-notice-close'),
                kind: StarBridgeActionKind.quiet,
                onActivate: (_) => _close(),
                child: Text(copy.text('notice.close')),
              )
            else ...[
              StarBridgeActionButton(
                controlKey: const Key('guide-notice-enable'),
                kind: StarBridgeActionKind.primary,
                onActivate: _busy ? null : (_) => _enable(),
                child: Text(copy.text('notice.enable')),
              ),
              StarBridgeActionButton(
                controlKey: const Key('guide-notice-later'),
                kind: StarBridgeActionKind.quiet,
                onActivate: _busy ? null : (_) => _later(),
                child: Text(copy.text('notice.later')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
