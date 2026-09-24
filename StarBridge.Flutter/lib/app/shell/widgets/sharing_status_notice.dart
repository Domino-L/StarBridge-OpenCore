import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import '../../../design_system/icons/icon_semantic.dart';
import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../localization/app_strings.dart';

/// Repeated status reads update one persistent strip, never a toast queue.
class SharingStatusNotice extends StatelessWidget {
  const SharingStatusNotice({
    required this.status,
    required this.onOpenSettings,
    super.key,
  });
  final ValueListenable<String?> status;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: status,
    builder: (context, issue, _) =>
        issue == null ? const SizedBox.shrink() : _buildNotice(context, issue),
  );

  Widget _buildNotice(BuildContext context, String issue) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final informational = issue == 'identity' || issue == 'paused';
    final foreground = informational
        ? tokens.colors.info
        : tokens.colors.warning;
    final action = TextButton(
      key: const Key('sharing-status-settings'),
      onPressed: onOpenSettings,
      child: Text(strings.text('privacy.notice.settings')),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('sharing-status-notice'),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space.lg,
          vertical: tokens.space.xs,
        ),
        decoration: BoxDecoration(
          color: informational
              ? tokens.colors.infoSoft
              : tokens.colors.warningSoft,
          border: Border(
            bottom: BorderSide(color: foreground.withValues(alpha: .6)),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 650 ||
                MediaQuery.textScalerOf(context).scale(14) > 20;
            final content = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: tokens.space.xs),
                  child: StarBridgeIcon(
                    informational
                        ? StarBridgeIconSemantic.privacy
                        : StarBridgeIconSemantic.warning,
                    size: tokens.icons.small,
                    color: foreground,
                  ),
                ),
                SizedBox(width: tokens.space.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.text('privacy.notice.$issue.title'),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        strings.text('privacy.notice.$issue.body'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!compact) action,
              ],
            );
            return compact
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [content, action],
                  )
                : content;
          },
        ),
      ),
    );
  }
}
