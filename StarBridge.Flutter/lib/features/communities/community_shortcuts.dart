import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
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

class _CommunityShortcutsState extends State<CommunityShortcuts>
    with CommunityVisibleRefresh<CommunityShortcuts> {
  @override
  Future<void> refreshVisibleCommunity() async {
    if (!widget.module.joinedLoaded) await widget.module.refreshJoined();
  }

  int revision = 0;
  @override
  void initState() {
    super.initState();
    revision = widget.module.accountRevision;
    widget.module.addListener(_changed);
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
      revision = widget.module.accountRevision;
      widget.module.addListener(_changed);
      scheduleMicrotask(() {
        if (mounted) unawaited(widget.module.refreshJoined());
      });
    }
  }

  @override
  void dispose() {
    widget.module.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.module, tokens = context.tokens;
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('communities.$key');
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
                t('joinedShortcuts'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          if (model.joinedBusy && model.joined.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
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
                    child: Tooltip(
                      message: row.name,
                      child: Material(
                        color: widget.selected && model.selected?.key == row.key
                            ? tokens.colors.accentSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: model.writing
                              ? null
                              : () async {
                                  final epoch = model.accountRevision;
                                  if (await widget.activate() &&
                                      mounted &&
                                      epoch == model.accountRevision) {
                                    await model.openJoined(row);
                                  }
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CommunityLogo(
                                  data: row.logo,
                                  size: 28,
                                  framed: false,
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
                      ? 'noJoinedShortcuts'
                      : model.joinedError == 'identityUnavailable'
                      ? 'shortcutsUnavailable'
                      : 'shortcutsLoadFailed',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (model.joinedNext != null)
            TextButton(
              onPressed: model.joinedBusy
                  ? null
                  : () => model.refreshJoined(next: true),
              child: Text(t('more')),
            ),
        ],
      ),
    );
  }
}
