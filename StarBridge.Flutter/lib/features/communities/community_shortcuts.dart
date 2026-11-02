import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/widgets/attention_badge.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../common/social_read_activity.dart';
import 'communities_module.dart';
import 'community_logo.dart';
import 'community_visible_refresh.dart';

class CommunityShortcuts extends StatefulWidget {
  const CommunityShortcuts({
    required this.module,
    required this.iconOnly,
    required this.selected,
    required this.activate,
    super.key,
  });
  final CommunitiesModule module;
  final bool iconOnly, selected;
  final Future<bool> Function() activate;
  @override
  State<CommunityShortcuts> createState() => _CommunityShortcutsState();
}

/// Fallback reconciliation for missed organization chat activity events.
abstract final class CommunityShortcutsReconcile {
  /// A failed read is retried at this pace, as WPF's chat list was.
  static const interval = Duration(seconds: 10);

  /// Each read of each joined organization reaches the partner about six times
  /// (CX-COUNT-WAIT 2026-10-31), which at 10 s was most of an idle client's load.
  /// A send already pushes an activity hint, so the full pass only catches a
  /// missed one: every this many ticks, once a minute.
  static const fullPassTicks = 6;
}

class _CommunityShortcutsState extends State<CommunityShortcuts>
    with CommunityVisibleRefresh<CommunityShortcuts> {
  @override
  Duration get communityRefreshInterval => CommunityShortcutsReconcile.interval;
  // Presence transport health does not certify delivery of chat changes.
  // Keep a shell reconciliation even after successful reads; activity events
  // still refresh immediately via chatAttention.
  int _ticks = 0;
  @override
  Future<void> refreshVisibleCommunity() async {
    if (!widget.module.joinedLoaded ||
        widget.module.joinedError == 'readTransient') {
      await widget.module.refreshJoined();
    }
    final attention = widget.module.chatAttention;
    if (++_ticks >= CommunityShortcutsReconcile.fullPassTicks) {
      _ticks = 0;
      attention.refresh(reconcile: true);
    } else if (attention.needsReconciliation) {
      attention.refresh(retryOnly: true, reconcile: true);
    }
  }

  int revision = 0;
  late SocialReadActivityBinding _readActivity;

  void _bindReadActivity() {
    final owner = widget.module;
    _readActivity = SocialReadActivityBinding(
      owner,
      () => owner.joinedBusy,
      initialRead: !owner.joinedLoaded,
    );
  }

  @override
  void initState() {
    super.initState();
    _bindReadActivity();
    revision = widget.module.accountRevision;
    widget.module.addListener(_changed);
    widget.module.chatAttention.addListener(_changed);
    scheduleMicrotask(() {
      if (mounted) unawaited(widget.module.refreshJoined());
    });
  }

  void _changed() {
    if (revision != widget.module.accountRevision) {
      revision = widget.module.accountRevision;
      scheduleMicrotask(() {
        if (mounted) unawaited(widget.module.refreshJoined());
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant CommunityShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module != widget.module) {
      oldWidget.module.removeListener(_changed);
      oldWidget.module.chatAttention.removeListener(_changed);
      _readActivity.dispose();
      _bindReadActivity();
      revision = widget.module.accountRevision;
      widget.module.addListener(_changed);
      widget.module.chatAttention.addListener(_changed);
      scheduleMicrotask(() {
        if (mounted) unawaited(widget.module.refreshJoined());
      });
    }
  }

  @override
  void dispose() {
    _readActivity.dispose();
    widget.module.removeListener(_changed);
    widget.module.chatAttention.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.module, tokens = context.tokens;
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('communities.$key');
    final cachedAt = model.joinedCachedAtUtc?.toLocal();
    final cacheCaption = cachedAt == null
        ? null
        : t(
            model.joinedCacheComplete
                ? 'shortcutsCached'
                : 'shortcutsCachedPartial',
          ).replaceAll(
            '{time}',
            '${MaterialLocalizations.of(context).formatMediumDate(cachedAt)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(cachedAt))}',
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          if (!widget.iconOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text(
                t(cachedAt == null ? 'joinedShortcuts' : 'cachedOrganizations'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          if (!widget.iconOnly && cacheCaption != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                cacheCaption,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (!widget.iconOnly && model.joinedError == 'readTransient')
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(t('readTransient')),
                StarBridgeActionButton(
                  controlKey: const Key('community-shortcuts-retry'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: model.joinedBusy
                      ? null
                      : (source) => unawaited(
                          runStarBridgeActivation(source, model.refreshJoined),
                        ),
                  child: Text(t('retry')),
                ),
              ],
            ),
          if (model.joinedBusy && model.joined.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SocialReadActivity(
                key: ValueKey((model, _readActivity.revision)),
                source: _readActivity.source,
                opening: _readActivity.opening,
                label: t('loading'),
                height: ProgressIndicatorTheme.of(context).linearMinHeight ?? 4,
              ),
            ),
          if (model.joined.isNotEmpty)
            SizedBox(
              height: (model.joined.length * 60.0).clamp(0, 360),
              child: ListView.builder(
                primary: false,
                itemCount: model.joined.length,
                itemExtent: 60,
                itemBuilder: (context, index) {
                  final row = model.joined[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: StarBridgeTooltip(
                      message: row.displayOnly && cacheCaption != null
                          ? '${row.name}\n$cacheCaption${model.joinedError == 'readTransient' ? '\n${t('readTransient')}' : ''}'
                          : row.name,
                      child: Material(
                        color: widget.selected && model.selected?.key == row.key
                            ? tokens.colors.accentSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        child: StarBridgeActionRow(
                          controlKey: ValueKey('community-shortcut-${row.key}'),
                          onActivate: model.writing || row.displayOnly
                              ? null
                              : (_, source) => unawaited(
                                  runStarBridgeActivation<void>(
                                    source,
                                    () async {
                                      final epoch = model.accountRevision;
                                      if (await widget.activate() &&
                                          mounted &&
                                          epoch == model.accountRevision) {
                                        await model.openJoined(row);
                                      }
                                    },
                                  ),
                                ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // One tree shape for every unread count: an
                                // appearing badge must not rebuild the logo
                                // (and decode it again; 2026-10-21 report).
                                AttentionIconBadge(
                                  count: widget.iconOnly
                                      ? model.chatAttention.count(row.targetRef)
                                      : 0,
                                  child: CommunityLogo(
                                    downloadedBy: row,
                                    data: row.logo,
                                    size: 28,
                                    framed: false,
                                  ),
                                ),
                                if (!widget.iconOnly) ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      row.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                  if (model.chatAttention.count(row.targetRef) >
                                      0)
                                    AttentionCount(
                                      count: model.chatAttention.count(
                                        row.targetRef,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (!widget.iconOnly && !model.joinedBusy && model.joined.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                t(
                  model.joinedLoaded
                      ? cachedAt == null
                            ? 'noJoinedShortcuts'
                            : 'shortcutsCachedEmpty'
                      : model.joinedError == 'offlineCacheUnavailable'
                      ? 'shortcutsCacheUnavailable'
                      : model.joinedError == 'onlinePaused'
                      ? 'shortcutsOnlinePaused'
                      : model.joinedError == 'identityUnavailable'
                      ? 'shortcutsUnavailable'
                      : 'shortcutsLoadFailed',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (model.joinedNext != null)
            StarBridgeActionButton(
              controlKey: const Key('community-shortcuts-more'),
              kind: StarBridgeActionKind.quiet,
              onActivate: model.joinedBusy
                  ? null
                  : (source) => unawaited(
                      runStarBridgeActivation(
                        source,
                        () => model.refreshJoined(next: true),
                      ),
                    ),
              child: Text(t('more')),
            ),
        ],
      ),
    );
  }
}
