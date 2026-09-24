import 'package:flutter/material.dart';

import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/icons/icon_semantic.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
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
    super.key,
  });
  final Widget avatar;
  final String name;
  final String? gameId, issueLabel;
  final VoidCallback onPressed;
  final ManualPresenceController presence;
  final bool compact, menuOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final id = gameId?.trim();
    return ListenableBuilder(
      listenable: presence,
      builder: (context, _) => Tooltip(
        message: [
          name,
          if (id != null && id.isNotEmpty) '@$id',
          manualPresenceText(context, presence.snapshot.selfKey),
          ?issueLabel,
        ].join(' · '),
        child: SizedBox(
          width: compact ? 44 : null,
          height: 44,
          child: TextButton(
            key: const Key('account-identity-command'),
            onPressed: onPressed,
            style: ButtonStyle(
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                              if (id != null && id.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '@$id',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    key: const Key('account-identity-handle'),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: tokens.colors.textSecondary,
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
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
        ),
      ),
    );
  }
}
