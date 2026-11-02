import '../../design_system/icons/standard_icon.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../common/organization_holo.dart';
import '../common/organization_holo_online.dart';
import '../common/user_avatar_menu.dart';
import '../common/social_read_activity.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
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
  StarBridgeDialogRoute<void>? _route;
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
  Future<void> _openNarrow(InteractionSource source) async {
    if (_route != null) return;
    StarBridgeDialogRoute<void>? opened;
    await showStarBridgeDialog<void>(
      context,
      source: source,
      onRouteCreated: (route) => _route = opened = route,
      builder: (context) => AlertDialog(
        content: SizedBox(width: 280, height: 480, child: _members()),
        actions: [
          StarBridgeActionButton(
            key: const Key('community-online-close'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) =>
                dismissStarBridgeDialog<void>(context, source: source),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
    if (_route == opened) _route = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!OrganizationHolo.of(context)) return _standard(context);
    // Holo chat shares the main fleet's left online column (option B).
    return OrganizationHoloChatDock(
      key: const Key('community-chat-dock'),
      resetKey: (widget.port, widget.targetRef),
      closeKey: const Key('community-online-close'),
      online: (_, {required collapsed, onToggle}) => CommunityOnlineMembersPane(
        avatars: widget.avatars,
        port: widget.port,
        targetRef: widget.targetRef,
        holoCollapsed: collapsed,
        onCollapse: onToggle,
        onAllMembers: widget.onAllMembers,
      ),
      chat: widget.chat,
    );
  }

  Widget _standard(BuildContext context) => LayoutBuilder(
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
                    child: StarBridgeIconAction(
                      controlKey: const Key('community-online-toggle'),
                      label: workspaceText(context, 'onlineMembers'),
                      onActivate: narrow
                          ? _openNarrow
                          : (_) => setState(() => _collapsed = false),
                      icon: const StandardIcon(
                        StandardIconSemantic.people,
                        size: 20,
                      ),
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
    this.holoCollapsed = false,
    super.key,
  });
  final CommunityWorkspacePort port;
  final String targetRef;
  final VoidCallback onAllMembers;
  final VoidCallback? onCollapse;

  /// On holo surfaces: the rail instead of the column; [onCollapse] toggles.
  final bool holoCollapsed;
  final CommunityAvatarCache? avatars;
  @override
  State<CommunityOnlineMembersPane> createState() => _OnlineMembersState();
}

class _OnlineMembersState extends State<CommunityOnlineMembersPane>
    with CommunityVisibleRefresh<CommunityOnlineMembersPane> {
  late CommunityOnlineMembersController model;
  late SocialReadActivityBinding _readActivity;
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    model = CommunityOnlineMembersController(widget.port, widget.targetRef);
    _readActivity = SocialReadActivityBinding(
      model,
      () => model.showProgress,
      initialRead: true,
    );
    unawaited(model.refresh());
  }

  @override
  void didUpdateWidget(covariant CommunityOnlineMembersPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port) {
      _readActivity.dispose();
      model.dispose();
      _start();
    } else if (oldWidget.targetRef != widget.targetRef) {
      // Same port, renewed reference: keep the list and its avatars.
      model.renewTarget(widget.targetRef);
    }
  }

  @override
  Future<void> refreshVisibleCommunity() => model.refresh(silent: true);
  @override
  void dispose() {
    _readActivity.dispose();
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      String t(String key) => workspaceText(context, key);
      if (OrganizationHolo.of(context)) return _holo(context, t);
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
                StarBridgeIconAction(
                  controlKey: const Key('community-online-refresh'),
                  label: t('refresh'),
                  onActivate: model.loading || model.invalidated
                      ? null
                      : (_) => model.refresh(),
                  icon: const StandardIcon(
                    StandardIconSemantic.refresh,
                    size: 18,
                  ),
                ),
                if (widget.onCollapse != null)
                  StarBridgeIconAction(
                    controlKey: const Key('community-online-toggle'),
                    label: t('hideOnlineMembers'),
                    onActivate: (_) => widget.onCollapse!(),
                    icon: const StandardIcon(
                      StandardIconSemantic.chevronLeft,
                      size: 18,
                    ),
                  ),
              ],
            ),
            if (model.partial)
              Text(
                '${t('membersRead')} ${model.scanned}/${model.total}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (model.showProgress)
              SocialReadActivity(
                key: ValueKey((model, _readActivity.revision)),
                source: _readActivity.source,
                opening: _readActivity.opening,
                label: t('onlineMembers'),
                height: 4,
              ),
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
                            : context.tokens.colors.stateAccent;
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
                                    StarBridgeTooltip(
                                      message: member.displayName,
                                      child: Text(
                                        member.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.fade,
                                        softWrap: false,
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
              StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                onActivate: (_) => model.loadMore(),
                child: Text(t('loadMoreMembers')),
              ),
            const Divider(),
            StarBridgeActionButton(
              key: const Key('community-all-members'),
              kind: StarBridgeActionKind.quiet,
              onActivate: (_) => widget.onAllMembers(),
              child: Text(t('allMembers')),
            ),
          ],
        ),
      );
    },
  );
}

extension on _OnlineMembersState {
  Widget _holo(BuildContext context, String Function(String) t) {
    final colors = context.tokens.colors;
    final groups = <String, List<OrganizationHoloOnlineMember>>{
      'gaming': [],
      'online': [],
      'away': [],
    };
    for (final member in model.members) {
      final state = member.liveStatus.toLowerCase();
      final kind = state == 'ingame'
          ? 'gaming'
          : state == 'away'
          ? 'away'
          : 'online';
      groups[kind]!.add(
        OrganizationHoloOnlineMember(
          key: ValueKey('online-member-${member.memberRef}'),
          name: member.displayName,
          // State only, as before: location has its own privacy rules.
          detail: t(kind),
          dot: kind == 'gaming'
              ? colors.success
              : kind == 'away'
              ? colors.warning
              : colors.stateAccent,
          avatar: _OnlineAvatar(
            avatars: widget.avatars,
            key: ValueKey(member.memberRef),
            port: widget.port,
            targetRef: widget.targetRef,
            member: member,
          ),
        ),
      );
    }
    final count = model.error != null || model.showProgress
        ? '…'
        : '${model.members.length}${model.partial ? '+' : ''}';
    const keys = OrganizationHoloOnlineKeys(
      pane: Key('community-online-members'),
      list: Key('community-online-list'),
      toggle: Key('community-online-toggle'),
      allMembers: Key('community-all-members'),
    );
    if (widget.holoCollapsed) {
      return OrganizationHoloOnlineRail(
        keys: keys,
        label: t('onlineMembers'),
        count: count,
        members: [for (final list in groups.values) ...list],
        onExpand: widget.onCollapse ?? () {},
      );
    }
    final empty = model.members.isEmpty && !model.loading;
    return OrganizationHoloOnlineColumn(
      keys: keys,
      title: t('onlineMembers'),
      count: count,
      status: model.error != null && model.members.isEmpty
          ? t(model.error!)
          : empty
          ? t(model.partial ? 'noOnlineLoaded' : 'noOnlineMembers')
          : null,
      progress: model.showProgress
          ? SocialReadActivity(
              key: ValueKey((model, _readActivity.revision)),
              source: _readActivity.source,
              opening: _readActivity.opening,
              label: t('onlineMembers'),
              height: 4,
            )
          : null,
      groups: [
        for (final MapEntry(:key, :value) in groups.entries)
          if (value.isNotEmpty)
            OrganizationHoloOnlineGroup('${t(key)} · ${value.length}', value),
      ],
      trailing: [
        StarBridgeIconAction(
          controlKey: const Key('community-online-refresh'),
          label: t('refresh'),
          onActivate: model.loading || model.invalidated
              ? null
              : (_) => model.refresh(),
          icon: const StandardIcon(StandardIconSemantic.refresh, size: 18),
        ),
      ],
      toggleLabel: t('hideOnlineMembers'),
      onToggle: widget.onCollapse,
      footer: [
        if (model.partial)
          Text(
            '${t('membersRead')} ${model.scanned}/${model.total}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (model.error != null && model.members.isNotEmpty)
          Text(t(model.error!)),
        if (model.next != null && !model.loading)
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            onActivate: (_) => model.loadMore(),
            child: Text(t('loadMoreMembers')),
          ),
      ],
      allMembersLabel: t('allMembers'),
      onAllMembers: widget.onAllMembers,
    );
  }
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

  /// The bound read delivered a portrait; only such a read survives a
  /// renewed reference (review 2026-10-29: a pending or failed read would
  /// otherwise stay failed under the retired generation).
  bool _delivered = false;
  void _bind() {
    avatars = widget.avatars ?? CommunityAvatarCache();
    _delivered = false;
    final read = widget.member.hasAvatar
        ? avatars.member(widget.port, widget.targetRef, widget.member)
        : Future<Uint8List?>.value(null);
    image = read;
    read.then((bytes) {
      if (identical(image, read) && bytes != null) _delivered = true;
    }, onError: (_) {});
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant _OnlineAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A renewed reference alone keeps a portrait that already arrived (the
    // cache entry is the member's version); one still pending or failed is
    // read again on the new reference.
    if (oldWidget.port != widget.port ||
        oldWidget.avatars != widget.avatars ||
        oldWidget.member.memberRef != widget.member.memberRef ||
        oldWidget.member.avatarVersion != widget.member.avatarVersion ||
        oldWidget.member.hasAvatar != widget.member.hasAvatar ||
        oldWidget.targetRef != widget.targetRef && !_delivered) {
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
        name: widget.member.displayName,
        isSelf: widget.member.isSelf,
        target: UserTarget.community(
          widget.targetRef,
          widget.member.memberRef,
          query: widget.member.gameName,
        ),
        avatarBytes: snapshot.data,
        child: CommunityWorkspaceImage(
          decoder: avatars.images.decode,
          peek: avatars.images.peek,
          bytes: snapshot.data,
          loading:
              snapshot.connectionState != ConnectionState.done &&
              widget.member.hasAvatar,
          loadFailed: snapshot.hasError,
          icon: StandardIconSemantic.person,
          maxWidth: 96,
        ),
      ),
    ),
  );
}
