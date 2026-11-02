import 'package:flutter/material.dart';

import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/icons/icon_semantic.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../../design_system/interaction/starbridge_action_button.dart';
import '../../../design_system/interaction/starbridge_tooltip.dart';
import '../../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../presence/manual_presence.dart';
import '../../presence/manual_presence_widgets.dart';

/// Content-sized identity with a bounded name/ID column. Caller retains the existing
/// avatar (including image/loading/issue state) and owns opening the real menu.
class AccountIdentityButton extends StatelessWidget {
  const AccountIdentityButton({
    required this.avatar,
    required this.name,
    required this.onPressed,
    required this.presence,
    this.gameId,
    this.compact = false,
    this.menuOpen = false,
    this.issueLabel,
    this.focusNode,
    this.onActivate,
    super.key,
  });
  final Widget avatar;
  final String name;
  final String? gameId, issueLabel;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final ValueChanged<InteractionSource>? onActivate;
  final ManualPresenceController presence;
  final bool compact, menuOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final id = gameId?.trim();
    final height =
        44 *
        (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
          1.0,
          double.infinity,
        );
    return ListenableBuilder(
      listenable: presence,
      builder: (context, _) => StarBridgeTooltip(
        consumeEscape: false,
        message: [
          name,
          if (id != null && id.isNotEmpty) '@$id',
          manualPresenceText(context, presence.snapshot.selfKey),
          ?issueLabel,
        ].join(' · '),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The real shell keeps a bounded top bar. Preserve the user's font
            // size, moving the status beside the name when two lines cannot fit.
            final inline = constraints.maxHeight < height;
            final identityLine = Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (id != null && id.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '@$id',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      key: const Key('account-identity-handle'),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                  ),
                ],
              ],
            );
            return SizedBox(
              width: compact ? 44 : null,
              height: height,
              child: StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('account-identity-command'),
                focusNode: focusNode,
                minHeight: height,
                padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 10),
                onActivate: (source) =>
                    onActivate != null ? onActivate!(source) : onPressed(),
                nativeStyle: ButtonStyle(
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: compact ? 5 : 10),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(borderRadius: tokens.shape.small),
                  ),
                  side: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.focused)
                        ? BorderSide(
                            color: tokens.colors.focusRing,
                            width: tokens.stroke.focusWidth,
                          )
                        : BorderSide.none,
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => menuOpen || states.contains(WidgetState.hovered)
                        ? tokens.surfaces.selected.fill
                        : Colors.transparent,
                  ),
                  foregroundColor: WidgetStatePropertyAll(
                    tokens.colors.textPrimary,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(dimension: 32, child: avatar),
                      if (!compact) ...[
                        const SizedBox(width: 10),
                        Flexible(
                          child: Flex(
                            direction: inline ? Axis.horizontal : Axis.vertical,
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: inline
                                ? CrossAxisAlignment.center
                                : CrossAxisAlignment.start,
                            children: [
                              if (inline)
                                Flexible(child: identityLine)
                              else
                                identityLine,
                              if (inline) const SizedBox(width: 7),
                              if (inline)
                                Flexible(
                                  child: ManualPresenceBadge(
                                    controller: presence,
                                  ),
                                )
                              else
                                ManualPresenceBadge(controller: presence),
                            ],
                          ),
                        ),
                        if (issueLabel != null) ...[
                          const SizedBox(width: 5),
                          StarBridgeIcon(
                            StarBridgeIconSemantic.warning,
                            size: 13,
                            color: tokens.colors.warning,
                          ),
                        ],
                        const SizedBox(width: 7),
                        StarBridgeIcon(
                          StarBridgeIconSemantic.menuDown,
                          size: 12,
                          color: tokens.colors.textSecondary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
