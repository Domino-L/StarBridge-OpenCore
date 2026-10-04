import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import '../../platform/window/native_viewport_visibility.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'direct_messages_module.dart';
import 'chat_avatar.dart';
import '../common/user_avatar_menu.dart';
import '../common/user_interaction.dart';
import '../common/social_identity_text.dart';
import '../../app/shell/widgets/attention_badge.dart';
import '../../app/shell/chrome/presence_color.dart';
import 'chat_message_bubble.dart';
import 'direct_message_composer.dart';
import 'communication_time_formatter.dart';
import '../communities/community_invitation_card.dart';
import '../common/chat_room_invitation.dart';
import '../communities/community_invitation_send_copy.dart';

class DirectMessagesPage extends StatefulWidget {
  const DirectMessagesPage({
    required this.createPort,
    required this.onBack,
    this.initialConversation,
    this.sharedModule,
    this.openCommunityInvite,
    this.sendCommunityInvite,
    this.openProfile,
    super.key,
  });
  final DirectMessagesPort Function() createPort;
  final VoidCallback onBack;
  final Conversation? initialConversation;
  final DirectMessagesModule? sharedModule;
  final void Function(Conversation)? openProfile;
  final Future<void> Function(BuildContext, String)? openCommunityInvite;
  final Future<void> Function(BuildContext, DirectMessagesModule)?
  sendCommunityInvite;
  @override
  State<DirectMessagesPage> createState() => _DirectMessagesPageState();
}

class _DirectMessagesPageState extends State<DirectMessagesPage>
    with WidgetsBindingObserver {
  final _messageKeys = <String, GlobalKey>{};
  String? _viewportRef;
  bool _readScheduled = false;
  bool _openingInvite = false;
  String _search = '';
  final _searchController = TextEditingController();
  Future<void> openInvitation(String code) async {
    final open = widget.openCommunityInvite;
    if (_openingInvite || open == null) return;
    setState(() => _openingInvite = true);
    try {
      await open(context, code);
    } finally {
      if (mounted) setState(() => _openingInvite = false);
    }
  }

  void _scheduleRead() {
    if (!mounted || _readScheduled) return;
    _readScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readScheduled = false;
      if (!mounted ||
          !NativeViewportScope.isActive(context) ||
          !TickerMode.valuesOf(context).enabled ||
          !(ModalRoute.of(context)?.isCurrent ?? true) ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed)) {
        return;
      }
      var through = 0;
      for (final message in module.messages.where((m) => m.incoming)) {
        final element = _messageKeys[message.id]?.currentContext;
        final box = element?.findRenderObject();
        final viewport = element
            ?.findAncestorRenderObjectOfType<RenderViewport>();
        if (box is! RenderBox ||
            viewport == null ||
            !box.attached ||
            !box.hasSize) {
          continue;
        }
        final bounds = box.localToGlobal(Offset.zero) & box.size;
        final visible = viewport.localToGlobal(Offset.zero) & viewport.size;
        if (bounds.overlaps(visible) &&
            bounds.intersect(visible).height >= 16 &&
            message.sequence > through) {
          through = message.sequence;
        }
      }
      if (through > 0) unawaited(module.markVisibleRead(through));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastFallbackRead = null;
      _receiveVisible();
      _scheduleRead();
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  late final DirectMessagesModule module;
  late final bool Function() _viewportCurrent;
  late final ScrollController scroll;
  void _rememberScroll() {
    if (scroll.hasClients) module.scrollOffset = scroll.offset;
  }

  Timer? _timeRefresh;
  Timer? _receiveRefresh;
  DateTime? _lastFallbackRead;

  void _receiveVisible() {
    if (!mounted ||
        !NativeViewportScope.isActive(context) ||
        !TickerMode.valuesOf(context).enabled ||
        !(ModalRoute.of(context)?.isCurrent ?? true) ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    final now = DateTime.now();
    final live =
        module.port is DirectMessageActivityHealthPort &&
        (module.port as DirectMessageActivityHealthPort).activityHealthy;
    if (live &&
        _lastFallbackRead != null &&
        now.difference(_lastFallbackRead!) < const Duration(seconds: 15)) {
      return;
    }
    _lastFallbackRead = now;
    unawaited(module.receive());
  }

  UserPageLeaveGuard? _pageLeave;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final guard = UserPageLeaveScope.maybeOf(context);
    if (identical(guard, _pageLeave)) return;
    _pageLeave?.confirm = null;
    _pageLeave = guard;
    guard?.confirm = leaveDraft;
  }

  @override
  void initState() {
    super.initState();
    module = widget.sharedModule ?? DirectMessagesModule(widget.createPort());
    _viewportCurrent = () =>
        mounted &&
        NativeViewportScope.isActive(context) &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    module.isViewportCurrent = _viewportCurrent;
    scroll = ScrollController(initialScrollOffset: module.scrollOffset);
    scroll.addListener(_rememberScroll);
    WidgetsBinding.instance.addObserver(this);
    scroll.addListener(_scheduleRead);
    _timeRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Visible-chat catch-up; app-wide push/notification delivery is independent.
    _receiveRefresh = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _receiveVisible(),
    );
    final initial = widget.initialConversation;
    if (initial != null) {
      _scheduleInitial(initial);
    } else if (!module.loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(module.refresh());
      });
    }
  }

  @override
  void didUpdateWidget(covariant DirectMessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final initial = widget.initialConversation;
    if (initial != null && !identical(initial, oldWidget.initialConversation)) {
      _scheduleInitial(initial);
    }
  }

  bool _openingInitial = false;
  bool _isSelectedConversation(Conversation row) {
    final current = module.selected;
    return current != null &&
        (current.ref == row.ref ||
            (current.conversationKey?.isNotEmpty == true &&
                current.conversationKey == row.conversationKey));
  }

  void _scheduleInitial(Conversation initial) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          _openingInitial ||
          !identical(widget.initialConversation, initial)) {
        return;
      }
      _openingInitial = true;
      try {
        if (!_isSelectedConversation(initial) && !await leaveDraft()) return;
        if (mounted && identical(widget.initialConversation, initial)) {
          if (scroll.hasClients && !_isSelectedConversation(initial)) {
            scroll.jumpTo(0);
          }
          if (!_isSelectedConversation(initial)) {
            await module.openFriend(initial);
          }
        }
      } finally {
        _openingInitial = false;
      }
    });
  }

  @override
  void dispose() {
    if (identical(module.isViewportCurrent, _viewportCurrent)) {
      module.isViewportCurrent = null;
    }
    _pageLeave?.confirm = null;
    WidgetsBinding.instance.removeObserver(this);
    scroll.removeListener(_scheduleRead);
    _timeRefresh?.cancel();
    _receiveRefresh?.cancel();
    if (widget.sharedModule == null) module.dispose();
    scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String t(String key) => AppStrings.of(context).text('direct.$key');
  String time(DateTime value) {
    return communicationTime(value, AppStrings.of(context).locale);
  }

  Future<void> open(Conversation row) async {
    if (_isSelectedConversation(row)) return;
    if (!await leaveDraft()) return;
    if (scroll.hasClients) scroll.jumpTo(0);
    await module.open(row);
  }

  Future<void> send() async {
    await module.send();
    if (mounted &&
        scroll.hasClients &&
        const {'sent', 'request_sent'}.contains(module.sendStatus)) {
      scroll.jumpTo(0);
    }
  }

  Future<bool> leaveDraft() async {
    if (module.sending) return false;
    if (!module.hasDraft) return true;
    return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(t('send.leaveTitle')),
                content: Text(
                  t(
                    module.awaitingConfirmation
                        ? 'send.leaveUnknown'
                        : 'send.leaveBody',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(t('send.keep')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(t('send.discard')),
                  ),
                ],
              ),
            ) ==
            true &&
        mounted;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: module,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (module.busy) const LinearProgressIndicator(minHeight: 2),
        if (module.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              t('error.${module.error}'),
              style: TextStyle(color: context.tokens.colors.warning),
            ),
          ),
        if (module.readError != null)
          Text(
            t('readFailed'),
            style: TextStyle(color: context.tokens.colors.warning),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 680) {
                return module.selected == null
                    ? directoryPane()
                    : history(narrow: true);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: constraints.maxWidth < 900 ? 248 : 280,
                    child: directoryPane(),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(child: history()),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget directoryPane() => ColoredBox(
    color: context.tokens.surfaces.panel.fill,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t('conversations'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: t('backFriends'),
                icon: const StandardIcon(StandardIconSemantic.people, size: 19),
                onPressed: () async {
                  if (await leaveDraft()) widget.onBack();
                },
              ),
              IconButton(
                tooltip: t('refresh'),
                icon: const StandardIcon(
                  StandardIconSemantic.refresh,
                  size: 19,
                ),
                onPressed: module.busy
                    ? null
                    : () => module.loaded ? module.receive() : module.refresh(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            key: const ValueKey('chat-search'),
            controller: _searchController,
            onChanged: (value) =>
                setState(() => _search = value.trim().toLowerCase()),
            decoration: InputDecoration(
              isDense: true,
              hintText: t('search'),
              prefixIcon: const StandardIcon(
                StandardIconSemantic.search,
                size: 18,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 6,
            children: [
              for (final requests in [false, true])
                ChoiceChip(
                  label: Text(t(requests ? 'requests' : 'conversations')),
                  selected: module.requests == requests,
                  onSelected: module.busy
                      ? null
                      : (_) async {
                          if (await leaveDraft()) module.group(requests);
                        },
                ),
            ],
          ),
        ),
        Expanded(child: directory()),
      ],
    ),
  );
  Widget directory() {
    final visible = module.visible
        .where(
          (row) =>
              _search.isEmpty ||
              row.name.toLowerCase().contains(_search) ||
              row.gameId.toLowerCase().contains(_search),
        )
        .toList();
    if (visible.isEmpty) {
      return Center(
        child: Text(
          t(
            _search.isNotEmpty
                ? 'noSearchResults'
                : module.loaded
                ? 'empty'
                : module.busy
                ? 'loading'
                : 'refreshHint',
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final row = visible[index];
        return Material(
          color: Colors.transparent,
          child: ListTile(
            leading: ChatAvatar(
              onViewProfile: widget.openProfile == null
                  ? null
                  : () => widget.openProfile!(row),
              label: row.name,
              source: row.avatar,
              target: UserTarget('conversation', row.ref, query: row.gameId),
              actions: [
                AvatarMenuAction(
                  AppStrings.of(context).text('avatar.sendMessage'),
                  () => unawaited(open(row)),
                ),
              ],
            ),
            selected:
                module.selected?.ref == row.ref ||
                (row.conversationKey != null &&
                    module.selected?.conversationKey == row.conversationKey),
            onTap: () => open(row),
            selectedTileColor: context.tokens.colors.accent.withValues(
              alpha: .15,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            title: Row(
              children: [
                Expanded(
                  child: SocialIdentityText(
                    callsign: row.name,
                    gameId: row.gameId,
                    callsignStyle: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    gameIdColor: context.tokens.colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  time(row.time),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 11),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AttentionCount(count: row.unread),
                  ],
                ),
                if (conversationPresence(row.state, row.presence)
                    case final presence?)
                  presenceLabel(presence),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget history({bool narrow = false}) {
    final target = module.selected;
    if (target == null) return Center(child: Text(t('select')));
    if (_viewportRef != target.ref) {
      _viewportRef = target.ref;
      _messageKeys.clear();
    }
    _scheduleRead();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (narrow)
                IconButton(
                  tooltip: t('backList'),
                  onPressed: () async {
                    if (await leaveDraft()) module.back();
                  },
                  icon: const StandardIcon(
                    StandardIconSemantic.arrowBack,
                    size: 18,
                  ),
                ),
              ChatAvatar(
                onViewProfile: widget.openProfile == null
                    ? null
                    : () => widget.openProfile!(target),
                label: target.name,
                source: target.avatar,
                size: 30,
                target: UserTarget(
                  'conversation',
                  target.ref,
                  query: target.gameId,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SocialIdentityText(
                      callsign: target.name,
                      gameId: target.gameId,
                      callsignStyle: Theme.of(context).textTheme.titleMedium,
                      gameIdColor: context.tokens.colors.textSecondary,
                    ),
                    if (conversationPresence(target.state, target.presence)
                        case final presence?)
                      presenceLabel(presence),
                  ],
                ),
              ),
              IconButton(
                tooltip: t(module.hasNewer ? 'moreNew' : 'refreshMessages'),
                onPressed: module.busy ? null : () => module.load(newer: true),
                icon: const StandardIcon(
                  StandardIconSemantic.refresh,
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: t('latest'),
                onPressed: module.busy
                    ? null
                    : () {
                        if (scroll.hasClients) scroll.jumpTo(0);
                        unawaited(module.load());
                      },
                icon: const StandardIcon(
                  StandardIconSemantic.arrowDownward,
                  size: 18,
                ),
              ),
            ],
          ),
          if (module.state != 'friend' && module.state != 'accepted')
            Text(
              t('state.${module.state}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (!module.supportsSending)
            Text(t('readOnly'), style: Theme.of(context).textTheme.bodySmall),
          const Divider(height: 16),
          Expanded(
            child: module.messages.isEmpty && !module.hasOlder
                ? Center(
                    child: Text(
                      t(
                        module.busy
                            ? 'loading'
                            : module.error != null
                            ? 'refreshHint'
                            : 'emptyHistory',
                      ),
                    ),
                  )
                : ListView.builder(
                    key: ValueKey(target.ref),
                    controller: scroll,
                    reverse: true,
                    itemCount: module.messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == module.messages.length) {
                        return Center(
                          child: module.hasOlder
                              ? TextButton(
                                  onPressed: module.busy
                                      ? null
                                      : () => module.load(older: true),
                                  child: Text(t('older')),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(t('start')),
                                ),
                        );
                      }
                      final message =
                          module.messages[module.messages.length - 1 - index];
                      return KeyedSubtree(
                        key: _messageKeys.putIfAbsent(
                          message.id,
                          GlobalKey.new,
                        ),
                        child: ChatMessageBubble(
                          privateConversation: true,
                          onViewProfile:
                              !message.incoming || widget.openProfile == null
                              ? null
                              : () => widget.openProfile!(target),
                          userTarget: UserTarget(
                            'conversation',
                            target.ref,
                            query: target.gameId,
                          ),
                          key: ValueKey(message.id),
                          incoming: message.incoming,
                          sender: message.incoming ? target.name : t('me'),
                          time: time(message.time),
                          avatar: message.incoming
                              ? target.avatar
                              : module.viewerAvatar,
                          allowProfileUrl: !message.incoming,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (message.text.isNotEmpty)
                                SelectableText(message.text),
                              if (message.communityInvitation != null)
                                CommunityInvitationCard(
                                  value: message.communityInvitation!,
                                  busy: _openingInvite,
                                  onOpen: widget.openCommunityInvite == null
                                      ? null
                                      : () => unawaited(
                                          openInvitation(
                                            message
                                                .communityInvitation!
                                                .inviteCode,
                                          ),
                                        ),
                                )
                              else if (message.roomInvitation != null)
                                ChatRoomInvitationCard(
                                  value: message.roomInvitation!,
                                )
                              else if (message.attachment != null)
                                Text(
                                  '${t('attachment.${message.attachment}')} · ${t('attachmentReadOnly')}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          DirectMessageComposer(module, onSend: () => unawaited(send())),
          if (widget.sendCommunityInvite != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('chat-send-organization-invitation'),
                onPressed:
                    _openingInvite ||
                        !module.canSend ||
                        module.busy ||
                        module.sending ||
                        module.awaitingConfirmation
                    ? null
                    : () async {
                        setState(() => _openingInvite = true);
                        try {
                          await widget.sendCommunityInvite!(context, module);
                        } finally {
                          if (mounted) setState(() => _openingInvite = false);
                        }
                      },
                icon: const StandardIcon(StandardIconSemantic.groupAdd),
                label: Text(invitationSendText(context, 'sendTitle')),
              ),
            ),
        ],
      ),
    );
  }

  Widget presenceLabel(String presence) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: presenceColor(context.tokens.colors, 'presence.$presence'),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          t('presence.$presence'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: presenceColor(context.tokens.colors, 'presence.$presence'),
          ),
        ),
      ],
    ),
  );
}
