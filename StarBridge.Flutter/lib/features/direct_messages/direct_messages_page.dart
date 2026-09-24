import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'direct_messages_module.dart';
import 'chat_avatar.dart';
import '../common/user_avatar_menu.dart';
import '../common/user_interaction.dart';
import '../../app/shell/widgets/attention_badge.dart';
import 'chat_message_bubble.dart';
import 'direct_message_composer.dart';
import 'communication_time_formatter.dart';
import '../communities/community_invitation_card.dart';
import '../communities/community_invitation_send_copy.dart';

class DirectMessagesPage extends StatefulWidget {
  const DirectMessagesPage({
    required this.createPort,
    required this.onBack,
    this.initialConversation,
    this.sharedModule,
    this.openCommunityInvite,
    this.sendCommunityInvite,
    super.key,
  });
  final DirectMessagesPort Function() createPort;
  final VoidCallback onBack;
  final Conversation? initialConversation;
  final DirectMessagesModule? sharedModule;
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
      _scheduleRead();
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  late final DirectMessagesModule module;
  final scroll = ScrollController();
  Timer? _timeRefresh;
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
    WidgetsBinding.instance.addObserver(this);
    scroll.addListener(_scheduleRead);
    _timeRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    final initial = widget.initialConversation;
    unawaited(initial == null ? module.refresh() : module.openFriend(initial));
  }

  @override
  void dispose() {
    _pageLeave?.confirm = null;
    WidgetsBinding.instance.removeObserver(this);
    scroll.removeListener(_scheduleRead);
    _timeRefresh?.cancel();
    if (widget.sharedModule == null) module.dispose();
    scroll.dispose();
    super.dispose();
  }

  String t(String key) => AppStrings.of(context).text('direct.$key');
  String time(DateTime value) {
    return communicationTime(value, AppStrings.of(context).locale);
  }

  Future<void> open(Conversation row) async {
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
    builder: (context, _) => Padding(
      padding: EdgeInsets.all(context.tokens.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton(
                onPressed: () async {
                  if (await leaveDraft()) widget.onBack();
                },
                child: Text(t('backFriends')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t('title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          Text(
            t(
              module.supportsReadReceipts
                  ? 'readingHint'
                  : module.supportsSending
                  ? 'sendingHint'
                  : 'readOnly',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
              TextButton(
                onPressed: module.busy
                    ? null
                    : () async {
                        if (await leaveDraft()) await module.refresh();
                      },
                child: Text(t('refresh')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (module.busy) const LinearProgressIndicator(),
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
                if (constraints.maxWidth < 780) {
                  return module.selected == null ? directory() : history();
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 290, child: directory()),
                    const VerticalDivider(width: 24),
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
  Widget directory() {
    if (module.visible.isEmpty) {
      return Center(
        child: Text(
          t(
            module.loaded
                ? 'empty'
                : module.busy
                ? 'loading'
                : 'refreshHint',
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: module.visible.length,
      itemBuilder: (context, index) {
        final row = module.visible[index];
        return Material(
          color: Colors.transparent,
          child: ListTile(
            leading: ChatAvatar(
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
            selected: module.selected == row,
            onTap: () => open(row),
            selectedTileColor: context.tokens.colors.accent.withValues(
              alpha: .15,
            ),
            title: Text(
              row.name,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.preview, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text('${time(row.time)} · ${t('state.${row.state}')}'),
              ],
            ),
            trailing: AttentionCount(count: row.unread),
          ),
        );
      },
    );
  }

  Widget history() {
    final target = module.selected;
    if (target == null) return Center(child: Text(t('select')));
    if (_viewportRef != target.ref) {
      _viewportRef = target.ref;
      _messageKeys.clear();
    }
    _scheduleRead();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () async {
                if (await leaveDraft()) module.back();
              },
              child: Text(t('backList')),
            ),
            ChatAvatar(
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
              child: Text(
                target.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        Text(
          t('state.${module.state}'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: module.busy ? null : () => module.load(newer: true),
              child: Text(t(module.hasNewer ? 'moreNew' : 'refreshMessages')),
            ),
            TextButton(
              onPressed: module.busy
                  ? null
                  : () {
                      if (scroll.hasClients) scroll.jumpTo(0);
                      unawaited(module.load());
                    },
              child: Text(t('latest')),
            ),
          ],
        ),
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
                      key: _messageKeys.putIfAbsent(message.id, GlobalKey.new),
                      child: ChatMessageBubble(
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
    );
  }
}
