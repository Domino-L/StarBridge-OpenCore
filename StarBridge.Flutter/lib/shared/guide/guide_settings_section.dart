import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'guide_copy.dart';
import 'guide_scope.dart';
import 'guide_state.dart';

/// Settings › General: bring back the checklist, page tips and tours.
class GuideSettingsSection extends StatefulWidget {
  const GuideSettingsSection({required this.panel, super.key});

  /// The settings page's own panel frame (title, subtitle, body).
  final Widget Function(String title, String subtitle, Widget child) panel;
  @override
  State<GuideSettingsSection> createState() => _GuideSettingsSectionState();
}

class _GuideSettingsSectionState extends State<GuideSettingsSection> {
  String? _done;

  @override
  Widget build(BuildContext context) {
    final hub = GuideScope.maybeOf(context);
    if (hub == null) return const SizedBox.shrink();
    final t = context.tokens;
    final copy = GuideCopy.of(context);
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder<GuideState>(
      valueListenable: hub.controller,
      builder: (context, state, _) {
        if (!state.available) return const SizedBox.shrink();
        Widget action(String key, VoidCallback run) => StarBridgeActionButton(
          controlKey: Key('guide-settings-$key'),
          onActivate: (_) {
            run();
            setState(() => _done = key);
          },
          child: Text(copy.text('settings.$key')),
        );
        return KeyedSubtree(
          key: const Key('guide-settings'),
          child: widget.panel(
            copy.text('settings.title'),
            copy.text('settings.body'),
            Wrap(
              spacing: t.space.sm,
              runSpacing: t.space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (state.eligible)
                  action('resetChecklist', hub.controller.resetChecklist),
                action('resetTips', hub.controller.resetSeen),
                if (_done != null)
                  Text(
                    copy.text('settings.done'),
                    style: text.bodySmall?.copyWith(color: t.colors.success),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
