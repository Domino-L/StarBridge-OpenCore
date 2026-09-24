import 'package:flutter/material.dart';

import '../../../design_system/icons/icon_semantic.dart';
import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../localization/app_strings.dart';
import '../chrome/shell_chrome_projection.dart';

class ConnectionStatusNotice extends StatefulWidget {
  const ConnectionStatusNotice({
    required this.issue,
    this.onRetry,
    this.retrying = false,
    super.key,
  });

  final ConnectionIssueProjection issue;
  final Future<void> Function()? onRetry;
  final bool retrying;

  @override
  State<ConnectionStatusNotice> createState() => _ConnectionStatusNoticeState();
}

class _ConnectionStatusNoticeState extends State<ConnectionStatusNotice> {
  var _retryInFlight = false;

  bool get _retrying => widget.retrying || _retryInFlight;

  Future<void> _retry() async {
    final callback = widget.onRetry;
    if (callback == null || _retrying) {
      return;
    }
    setState(() => _retryInFlight = true);
    try {
      await callback();
    } finally {
      if (mounted) {
        setState(() => _retryInFlight = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final tone = switch (widget.issue.state) {
      ConnectionVisualState.normal => (
        foreground: tokens.colors.textSecondary,
        background: tokens.surfaces.status.fill,
      ),
      ConnectionVisualState.pending => (
        foreground: tokens.colors.info,
        background: tokens.colors.infoSoft,
      ),
      ConnectionVisualState.limited => (
        foreground: tokens.colors.warning,
        background: tokens.colors.warningSoft,
      ),
      ConnectionVisualState.disconnected => (
        foreground: tokens.colors.danger,
        background: tokens.colors.dangerSoft,
      ),
      ConnectionVisualState.stale => (
        foreground: tokens.colors.warning,
        background: tokens.colors.warningSoft,
      ),
    };
    final semantic = switch (widget.issue.domain) {
      ConnectionStatusDomain.host => StarBridgeIconSemantic.statusHost,
      ConnectionStatusDomain.game => StarBridgeIconSemantic.statusGame,
      ConnectionStatusDomain.identity => StarBridgeIconSemantic.statusIdentity,
      ConnectionStatusDomain.network => StarBridgeIconSemantic.statusNetwork,
    };
    final title = strings.text(widget.issue.titleKey);
    final detail = strings.text(widget.issue.detailKey);

    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title $detail',
      child: Container(
        key: const Key('connection-status-notice'),
        height: tokens.density.statusBarHeight,
        padding: EdgeInsets.symmetric(horizontal: tokens.space.lg),
        decoration: BoxDecoration(
          color: tone.background,
          border: Border(
            bottom: BorderSide(
              color: tone.foreground.withValues(alpha: 0.72),
              width: tokens.stroke.hairline,
            ),
          ),
        ),
        child: Row(
          children: [
            StarBridgeIcon(
              semantic,
              size: tokens.icons.small,
              color: tone.foreground,
            ),
            SizedBox(width: tokens.space.xs),
            Flexible(
              child: Text(
                title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tone.foreground,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: tokens.space.md),
            Container(
              width: tokens.stroke.hairline,
              height: tokens.icons.small,
              color: tone.foreground.withValues(alpha: 0.36),
            ),
            SizedBox(width: tokens.space.md),
            Expanded(
              flex: 3,
              child: Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.onRetry != null) ...[
              SizedBox(width: tokens.space.sm),
              TextButton.icon(
                key: const Key('connection-status-retry'),
                onPressed: _retrying ? null : _retry,
                style: TextButton.styleFrom(
                  foregroundColor: tone.foreground,
                  disabledForegroundColor: tone.foreground.withValues(
                    alpha: 0.72,
                  ),
                  minimumSize: Size(
                    0,
                    tokens.density.statusBarHeight - tokens.space.xxs,
                  ),
                  padding: EdgeInsets.symmetric(horizontal: tokens.space.sm),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                icon: _retrying
                    ? SizedBox.square(
                        dimension: tokens.icons.small,
                        child: CircularProgressIndicator(
                          key: const Key('connection-status-retry-loading'),
                          strokeWidth: tokens.stroke.strong,
                          color: tone.foreground,
                        ),
                      )
                    : StarBridgeIcon(
                        StarBridgeIconSemantic.refresh,
                        size: tokens.icons.small,
                      ),
                label: Text(
                  strings.text(
                    _retrying
                        ? 'connection.action.retrying'
                        : 'connection.action.retryNow',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
