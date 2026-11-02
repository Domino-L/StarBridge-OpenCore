import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import '../../platform/window/native_viewport_visibility.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/trade_chat_slot.dart';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_dialog_owner.dart';

import 'package:flutter/rendering.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'direct_messages_module.dart';
import 'direct_message_directory.dart';
import '../../app/shell/chrome/presence_color.dart';
import 'chat_avatar.dart';
import '../common/user_interaction.dart';
import '../common/social_identity_text.dart';
import 'chat_connection_notice.dart';
import 'direct_message_history_list.dart';
import 'direct_message_composer.dart';
import 'communication_time_formatter.dart';
import '../communities/community_invitation_card.dart';
import '../common/chat_room_invitation.dart';
import '../common/social_read_activity.dart';
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

  /// B1: reads only the existing activity health; none means never shown.
  late final _connection = ChatConnectionNotice(
    healthy: () => module.port is DirectMessageActivityHealthPort
        ? (module.port as DirectMessageActivityHealthPort).activityHealthy
        : null,
    onRestored: module.connectionRestored,
  );
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
      _receiveLease.wake();
      _scheduleRead();
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  late final DirectMessagesModule module;
  late final SocialReadActivityBinding _readActivity;
  late final bool Function() _viewportCurrent;
  late final ScrollController scroll;
  void _rememberScroll() {
    if (scroll.hasClients) module.scrollOffset = scroll.offset;
  }

  Timer? _timeRefresh;
  late final DirectMessageReceiveLease _receiveLease;

  UserPageLeaveGuard? _pageLeave;
  StarBridgeDialogRoute<bool>? _leaveRoute;
  // 0.7.2 G9: 交易消息, offered by the composition through [TradeChatSlot].
  bool _trade = false;
  Listenable? _tradeRequests;
  void _tradeRequested() {
    if (mounted && !_trade) setState(() => _trade = true);
  }

  Widget _groupSwitch(TradeChatSlot slot) => TradeChatGroupSwitch(
    trade: _trade,
    unread: slot.unread,
    onChanged: (trade) => setState(() => _trade = trade),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final requests = TradeChatSlot.maybeOf(context)?.requests;
    if (!identical(requests, _tradeRequests)) {
      _tradeRequests?.removeListener(_tradeRequested);
      _tradeRequests = requests?..addListener(_tradeRequested);
    }
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
    _readActivity = SocialReadActivityBinding(
      module,
      () => module.busy || module.directoryRefreshing,
      initialRead: !module.loaded,
    );
    _viewportCurrent = () =>
        mounted &&
        NativeViewportScope.isActive(context) &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    module.isViewportCurrent = _viewportCurrent;
    _connection.start();
    scroll = ScrollController(initialScrollOffset: module.scrollOffset);
    scroll.addListener(_rememberScroll);
    WidgetsBinding.instance.addObserver(this);
    scroll.addListener(_scheduleRead);
    _timeRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // All visible borrowers share the module's bounded catch-up schedule.
    _receiveLease = module.observeVisibleReception(
      () =>
          _viewportCurrent() &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed),
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
    _tradeRequests?.removeListener(_tradeRequested);
    _readActivity.dispose();
    retireStarBridgeDialog(_leaveRoute);
    if (identical(module.isViewportCurrent, _viewportCurrent)) {
      module.isViewportCurrent = null;
    }
    _pageLeave?.confirm = null;
    WidgetsBinding.instance.removeObserver(this);
    scroll.removeListener(_scheduleRead);
    _timeRefresh?.cancel();
    _connection.dispose();
    _receiveLease.dispose();
    if (widget.sharedModule == null) module.dispose();
    scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String t(String key) => AppStrings.of(context).text('direct.$key');
  String time(DateTime value) {
    return communicationTime(value, AppStrings.of(context).locale);
  }

  Future<void> open(Conversation row) => runStarBridgeActivation<void>(
    currentStarBridgeActivationSource,
    () async {
      if (_isSelectedConversation(row)) return;
      if (!await leaveDraft()) return;
      if (scroll.hasClients) scroll.jumpTo(0);
      await module.open(row);
    },
  );

  Future<void> send() async {
    await module.send();
    // A2: the message is already in the list; show the newest end.
    if (mounted && scroll.hasClients) scroll.jumpTo(0);
  }

  Future<bool> leaveDraft() async {
    if (!mounted || _leaveRoute != null) return false;
    if (!module.hasDraft) return true;
    final selectedRef = module.selected?.ref;
    final draftRevision = module.draftRevision;
    bool current() =>
        mounted &&
        module.selected?.ref == selectedRef &&
        module.draftRevision == draftRevision;
    void check() {
      if (!current()) retireStarBridgeDialog(_leaveRoute);
    }

    module.addListener(check);
    try {
      final result = await showStarBridgeDialog<bool>(
        context,
        onRouteCreated: (route) => _leaveRoute = route,
        builder: (context) {
          String text(String key) => AppStrings.of(context).text('direct.$key');
          return StarBridgeDialogOwnerGuard(
            isCurrent: current,
            child: AlertDialog(
              title: Text(text('send.leaveTitle')),
              content: Text(text('send.leaveBody')),
              actions: [
                StarBridgeActionButton(
                  controlKey: const ValueKey('chat-leave-keep'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: (source) => dismissStarBridgeDialog(
                    context,
                    source: source,
                    result: false,
                  ),
                  child: Text(text('send.keep')),
                ),
                StarBridgeActionButton(
                  controlKey: const ValueKey('chat-leave-discard'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: (source) => dismissStarBridgeDialog(
                    context,
                    source: source,
                    result: true,
                  ),
                  child: Text(text('send.discard')),
                ),
              ],
            ),
          );
        },
      );
      return result == true && current();
    } finally {
      module.removeListener(check);
      _leaveRoute = null;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: module,
    builder: (context, _) => _loadingContent(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (module.busy || module.directoryRefreshing)
            SocialReadActivity(
              key: ValueKey(_readActivity.revision),
              source: _readActivity.source,
              opening: _readActivity.opening,
              label: t('loading'),
            ),
          if (module.directoryError != null)
            Padding(
              key: const ValueKey('chat-directory-sync-failed'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                module.lastDirectorySyncUtc == null
                    ? t('syncFailed')
                    : t('syncFailedAt').replaceAll(
                        '{time}',
                        communicationTime(
                          module.lastDirectorySyncUtc!,
                          AppStrings.of(context).locale,
                        ),
                      ),
                style: TextStyle(color: context.tokens.colors.warning),
              ),
            ),
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
            child: _trade && TradeChatSlot.maybeOf(context) != null
                ? TradeChatSlot.maybeOf(context)!.build(
                    context,
                    _groupSwitch(TradeChatSlot.maybeOf(context)!),
                  )
                : LayoutBuilder(
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
    ),
  );

  Widget _loadingContent(Widget child) {
    final metrics = LoadingMetrics.current;
    if (metrics == null || metrics.stopped) return child;
    final items = module.selected == null
        ? module.visible
              .where(
                (row) =>
                    _search.isEmpty ||
                    row.name.toLowerCase().contains(_search) ||
                    row.gameId.toLowerCase().contains(_search),
              )
              .length
        : module.messages.length;
    return LoadingContentProbe(
      route: '/messages',
      status: module.busy
          ? (items == 0
                ? LoadingContentStatus.waiting
                : LoadingContentStatus.partial)
          : module.error != null
          ? (items == 0
                ? LoadingContentStatus.failed
                : LoadingContentStatus.partial)
          : !module.loaded
          ? LoadingContentStatus.unavailable
          : module.selected != null && module.historySyncError != null
          ? (items == 0
                ? LoadingContentStatus.failed
                : LoadingContentStatus.partial)
          : module.directoryError != null && items > 0
          ? LoadingContentStatus.partial
          : items == 0
          ? LoadingContentStatus.empty
          : LoadingContentStatus.data,
      items: items,
      child: child,
    );
  }

  Widget directoryPane() => ColoredBox(
    color: context.tokens.surfaces.panel.fill,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (TradeChatSlot.maybeOf(context) case final slot?) _groupSwitch(slot),
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
              StarBridgeIconAction(
                controlKey: const ValueKey('chat-back-friends'),
                label: t('backFriends'),
                icon: const StandardIcon(StandardIconSemantic.people, size: 19),
                onActivate: (source) => unawaited(
                  runStarBridgeActivation<void>(source, () async {
                    if (await leaveDraft()) widget.onBack();
                  }),
                ),
              ),
              StarBridgeIconAction(
                controlKey: const ValueKey('chat-refresh-directory'),
                label: t('refresh'),
                icon: const StandardIcon(
                  StandardIconSemantic.refresh,
                  size: 19,
                ),
                onActivate: module.busy || module.directoryRefreshing
                    ? null
                    : (_) => module.refresh(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: StarBridgeFieldFrame(
            enabled: true,
            builder: (_, focus) => TextField(
              focusNode: focus,
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
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 6,
            children: [
              for (final requests in [false, true])
                StarBridgeChoiceChip(
                  controlKey: Key('direct-messages-filter-$requests'),
                  label: t(requests ? 'requests' : 'conversations'),
                  selected: module.requests == requests,
                  onSelected: module.busy
                      ? null
                      : (_) => unawaited(
                          runStarBridgeActivation<void>(
                            currentStarBridgeActivationSource,
                            () async {
                              if (await leaveDraft()) module.group(requests);
                            },
                          ),
                        ),
                ),
            ],
          ),
        ),
        Expanded(child: directory()),
      ],
    ),
  );
  Widget directory() => DirectMessageDirectory(
    module: module,
    search: _search,
    onOpen: open,
    onOpenProfile: widget.openProfile,
  );

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
                StarBridgeIconAction(
                  controlKey: const ValueKey('chat-back-list'),
                  label: t('backList'),
                  onActivate: (source) => unawaited(
                    runStarBridgeActivation<void>(source, () async {
                      if (await leaveDraft()) module.back();
                    }),
                  ),
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
                      directMessagePresenceLabel(context, presence),
                  ],
                ),
              ),
              StarBridgeIconAction(
                controlKey: const ValueKey('chat-refresh-history'),
                label: t(module.hasNewer ? 'moreNew' : 'refreshMessages'),
                onActivate: module.busy
                    ? null
                    : (_) => module.load(newer: true),
                icon: const StandardIcon(
                  StandardIconSemantic.refresh,
                  size: 18,
                ),
              ),
              StarBridgeIconAction(
                controlKey: const ValueKey('chat-latest'),
                label: t('latest'),
                onActivate: module.busy
                    ? null
                    : (_) {
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
          if (module.error == null && module.historySyncError != null)
            Semantics(
              key: const ValueKey('chat-history-sync-failed'),
              liveRegion: true,
              child: Text(
                t(
                  module.historySyncError == 'limit'
                      ? 'error.limit'
                      : 'historySyncFailed',
                ),
                style: TextStyle(color: context.tokens.colors.warning),
              ),
            ),
          const Divider(height: 16),
          ChatReconnectLine(_connection),
          Expanded(
            child: DirectMessageHistoryList(
              module: module,
              target: target,
              scroll: scroll,
              messageKeys: _messageKeys,
              time: time,
              openProfile: widget.openProfile == null
                  ? null
                  : () => widget.openProfile!(target),
              body: (message) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.text.isNotEmpty) SelectableText(message.text),
                  if (message.communityInvitation != null)
                    CommunityInvitationCard(
                      value: message.communityInvitation!,
                      busy: _openingInvite,
                      onOpen: widget.openCommunityInvite == null
                          ? null
                          : () => unawaited(
                              openInvitation(
                                message.communityInvitation!.inviteCode,
                              ),
                            ),
                    )
                  else if (message.roomInvitation != null)
                    ChatRoomInvitationCard(value: message.roomInvitation!)
                  else if (message.attachment != null)
                    Text(
                      '${t('attachment.${message.attachment}')} · ${t('attachmentReadOnly')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          DirectMessageComposer(
            module,
            onSend: () => unawaited(send()),
            connection: _connection,
          ),
          if (widget.sendCommunityInvite != null)
            Align(
              alignment: Alignment.centerLeft,
              child: StarBridgeActionButton(
                controlKey: const ValueKey('chat-send-organization-invitation'),
                kind: StarBridgeActionKind.quiet,
                onActivate: _openingInvite || !module.canSend || module.busy
                    ? null
                    : (source) => unawaited(
                        runStarBridgeActivation<void>(source, () async {
                          setState(() => _openingInvite = true);
                          try {
                            await widget.sendCommunityInvite!(context, module);
                          } finally {
                            if (mounted) setState(() => _openingInvite = false);
                          }
                        }),
                      ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const StandardIcon(StandardIconSemantic.groupAdd),
                    const SizedBox(width: 8),
                    Text(invitationSendText(context, 'sendTitle')),
                  ],
                ),
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
