import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_ships_copy.dart';

/// The ships page's title row, as the approved preview (2026-10-29): back,
/// the organization's name, the scope note beside it, then the sharing entry
/// when the port offers it and refresh. Narrow windows put the scope note
/// under the title.
class CommunityShipsHeader extends StatelessWidget {
  const CommunityShipsHeader({
    required this.name,
    required this.onBack,
    required this.onRefresh,
    this.sharingLabel,
    this.sharingHint,
    this.onSharing,
    super.key,
  });

  final String name;
  final VoidCallback onBack;

  /// Null while a read is busy or the scope is invalid.
  final VoidCallback? onRefresh;

  /// The copy key of the sharing entry; null hides it.
  final String? sharingLabel;

  /// The copy key of a note beside the entry; null shows none.
  final String? sharingHint;

  /// Null shows the entry disabled.
  final VoidCallback? onSharing;

  @override
  Widget build(BuildContext context) {
    String t(String key) => communityShipsText(context, key);
    final text = Theme.of(context).textTheme;
    final scope = Text(
      t('scope'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: text.bodySmall?.copyWith(
        color: context.tokens.colors.textSecondary,
      ),
    );
    final title = Text(
      '$name · ${t('title')}',
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
    final hint = sharingHint == null
        ? null
        : Text(
            t(sharingHint!),
            key: const Key('community-ships-sharing-hint'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelLarge?.copyWith(
              color: context.tokens.colors.warning,
              fontWeight: FontWeight.w700,
            ),
          );
    final actions = [
      if (sharingLabel case final label?)
        MediaQuery.sizeOf(context).width >= 800
            ? StarBridgeActionButton(
                controlKey: const Key('community-ships-sharing'),
                onActivate: onSharing == null ? null : (_) => onSharing!(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const StandardIcon(StandardIconSemantic.share, size: 18),
                    const SizedBox(width: 8),
                    Text(t(label)),
                  ],
                ),
              )
            : StarBridgeIconAction(
                controlKey: const Key('community-ships-sharing'),
                onActivate: onSharing == null ? null : (_) => onSharing!(),
                label: t(label),
                icon: const StandardIcon(StandardIconSemantic.share),
              ),
      const SizedBox(width: 8),
      StarBridgeIconAction(
        controlKey: const Key('community-ships-refresh'),
        onActivate: onRefresh == null ? null : (_) => onRefresh!(),
        label: t('refresh'),
        icon: const StandardIcon(StandardIconSemantic.refresh),
      ),
    ];
    final back = StarBridgeActionButton(
      controlKey: const Key('community-ships-back'),
      kind: StarBridgeActionKind.quiet,
      onActivate: (_) => onBack(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const StandardIcon(StandardIconSemantic.arrowBack, size: 18),
          const SizedBox(width: 8),
          Text(t('back')),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 1000
          ? Row(
              children: [
                back,
                const SizedBox(width: 8),
                Flexible(flex: 0, child: title),
                const SizedBox(width: 14),
                Expanded(child: scope),
                const SizedBox(width: 14),
                if (hint != null) ...[hint, const SizedBox(width: 10)],
                ...actions,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    back,
                    const SizedBox(width: 8),
                    Expanded(child: title),
                    ...actions,
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: scope,
                ),
                ?hint,
              ],
            ),
    );
  }
}
