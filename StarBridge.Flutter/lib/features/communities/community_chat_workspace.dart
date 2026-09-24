import '../../design_system/icons/standard_icon.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/user_avatar_menu.dart';
import 'community_online_members_controller.dart';
import 'community_workspace_port.dart';
import 'community_workspace_image.dart';
import 'community_workspace_copy.dart';
import 'community_visible_refresh.dart';
import 'community_avatar_cache.dart';

class CommunityChatWorkspace extends StatefulWidget {
  const CommunityChatWorkspace({
    required this.port,
    required this.targetRef,
    required this.chat,
    required this.onAllMembers,
    this.avatars,
    super.key,
  });
  final CommunityWorkspacePort port;
  final String targetRef;
  final Widget chat;
  final CommunityAvatarCache? avatars;
  final VoidCallback onAllMembers;
  @override
  State<CommunityChatWorkspace> createState() => _CommunityChatWorkspaceState();
}

class _CommunityChatWorkspaceState extends State<CommunityChatWorkspace> {
  bool _collapsed = false;
  DialogRoute<void>? _route;
  void _dismiss() {
    final route = _route;
    _route = null;
    scheduleMicrotask(() {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CommunityChatWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.targetRef != widget.targetRef) {
      _dismiss();
      _collapsed = false;
    }
  }

  Widget _members({VoidCallback? onCollapse}) => CommunityOnlineMembersPane(
    avatars: widget.avatars,
    onCollapse: onCollapse,
    port: widget.port,
    targetRef: widget.targetRef,
    onAllMembers: () {
      _dismiss();
      widget.onAllMembers();
    },
  );
  Future<void> _openNarrow() async {
    if (_route != null) return;
    final route = DialogRoute<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: SizedBox(width: 280, height: 480, child: _members()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
    _route = route;
    await Navigator.of(context).push(route);
    if (_route == route) _route = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final narrow = size.maxWidth < 900;
      final expanded = !narrow && !_collapsed;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: expanded ? 232 : 40,
            child: expanded
                ? _members(onCollapse: () => setState(() => _collapsed = true))
                : Align(
                    alignment: Alignment.topCenter,
                    child: IconButton(
                      key: const Key('community-online-toggle'),
                      tooltip: workspaceText(context, 'onlineMembers'),
                      onPressed: narrow
                          ? _openNarrow
                          : () => setState(() => _collapsed = false),
                      icon: const StandardIcon(StandardIconSemantic.people, size: 20),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(child: widget.chat),
        ],
      );
    },
  );
}

class CommunityOnlineMembersPane extends StatefulWidget {
  const CommunityOnlineMembersPane({
    required this.port,
    required this.targetRef,
    required this.onAllMembers,
    this.onCollapse,
    this.avatars,
    super.key,
  });
  final CommunityWorkspacePort port;
  final String targetRef;
  final VoidCallback onAllMembers;
  final VoidCallback? onCollapse;
  final CommunityAvatarCache? avatars;
  @override
  State<CommunityOnlineMembersPane> createState() => _OnlineMembersState();
}

class _OnlineMembersState extends State<CommunityOnlineMembersPane>
    with CommunityVisibleRefresh<CommunityOnlineMembersPane> {
  late CommunityOnlineMembersController model;
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    model = CommunityOnlineMembersController(widget.port, widget.targetRef);
    unawaited(model.refresh());
  }

  @override
  void didUpdateWidget(covariant CommunityOnlineMembersPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.targetRef != widget.targetRef) {
      model.dispose();
      _start();
    }
  }

  @override
  Future<void> refreshVisibleCommunity() => model.refresh(silent: true);
  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      String t(String key) => workspaceText(context, key);
      return Container(
        key: const Key('community-online-members'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.tokens.surfaces.panel.fill,
          border: Border.all(color: context.tokens.surfaces.panel.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${t('onlineMembers')} · ${model.error != null || model.showProgress ? '…' : '${model.members.length}${model.partial ? '+' : ''}'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: t('refresh'),
                  onPressed: model.loading || model.invalidated
                      ? null
                      : model.refresh,
                  icon: const StandardIcon(StandardIconSemantic.refresh, size: 18),
                ),
                if (widget.onCollapse != null)
                  IconButton(
                    key: const Key('community-online-toggle'),
                    tooltip: t('hideOnlineMembers'),
                    onPressed: widget.onCollapse,
                    icon: const StandardIcon(StandardIconSemantic.chevronLeft, size: 18),
                  ),
              ],
            ),
            if (model.partial)
              Text(
                '${t('membersRead')} ${model.scanned}/${model.total}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (model.showProgress) const LinearProgressIndicator(),
            if (model.error != null && model.members.isNotEmpty)
              Text(t(model.error!)),
            const SizedBox(height: 6),
            Expanded(
              child: model.error != null && model.members.isEmpty
                  ? Text(t(model.error!))
                  : model.members.isEmpty && !model.loading
                  ? Text(
                      t(model.partial ? 'noOnlineLoaded' : 'noOnlineMembers'),
                    )
                  : ListView.separated(
                      key: const Key('community-online-list'),
                      itemCount: model.members.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final member = model.members[index];
                        final state = member.liveStatus.toLowerCase();
                        final color = state == 'ingame'
                            ? context.tokens.colors.success
                            : state == 'away'
                            ? context.tokens.colors.warning
                            : context.tokens.colors.accent;
                        return Container(
                          key: ValueKey('online-member-${member.memberRef}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: context.tokens.surfaces.raised.fill,
                            border: Border.all(
                              color: context.tokens.surfaces.panel.border,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              _OnlineAvatar(
                                  avatars: widget.avatars,
                                  key: ValueKey(member.memberRef),
                                  port: widget.port,
                                  targetRef: widget.targetRef,
                                  member: member,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Tooltip(
                                      message: member.displayName,
                                      child: Text(
                                        member.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      t(
                                        state == 'ingame'
                                            ? 'gaming'
                                            : state == 'away'
                                            ? 'away'
                                            : 'online',
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: color),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (model.next != null && !model.loading)
              TextButton(
                onPressed: model.loadMore,
                child: Text(t('loadMoreMembers')),
              ),
            const Divider(),
            TextButton(
              key: const Key('community-all-members'),
              onPressed: widget.onAllMembers,
              child: Text(t('allMembers')),
            ),
          ],
        ),
      );
    },
  );
}

class _OnlineAvatar extends StatefulWidget {
  const _OnlineAvatar({
    required this.port,
    required this.targetRef,
    required this.member,
    this.avatars,
    super.key,
  });
  final CommunityWorkspacePort port;
  final String targetRef;
  final CommunityWorkspaceMember member;
  final CommunityAvatarCache? avatars;
  @override
  State<_OnlineAvatar> createState() => _OnlineAvatarState();
}

class _OnlineAvatarState extends State<_OnlineAvatar> {
  late CommunityAvatarCache avatars;
  late Future<Uint8List?> image;
  void _bind() {
    avatars = widget.avatars ?? CommunityAvatarCache();
    image = widget.member.hasAvatar
        ? avatars.member(widget.port, widget.targetRef, widget.member)
        : Future.value(null);
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant _OnlineAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.targetRef != widget.targetRef ||
        oldWidget.avatars != widget.avatars ||
        oldWidget.member.memberRef != widget.member.memberRef ||
        oldWidget.member.avatarVersion != widget.member.avatarVersion ||
        oldWidget.member.hasAvatar != widget.member.hasAvatar) {
      if (oldWidget.avatars == null) avatars.dispose();
      _bind();
    }
  }

  @override
  void dispose() {
    if (widget.avatars == null) avatars.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 32,
    height: 32,
    child: FutureBuilder<Uint8List?>(
      future: image,
      builder: (_, snapshot) => UserAvatarMenu(
        name: widget.member.displayName, isSelf: widget.member.isSelf,
        target: UserTarget.community(widget.targetRef, widget.member.memberRef, query: widget.member.gameName),
        avatarBytes: snapshot.data,
        child: CommunityWorkspaceImage(
        decoder: avatars.images.decode,
        bytes: snapshot.data,
        loading:
            snapshot.connectionState != ConnectionState.done &&
            widget.member.hasAvatar,
        loadFailed: snapshot.hasError,
        icon: StandardIconSemantic.person,
        maxWidth: 96,
      )),
    ),
  );
}
