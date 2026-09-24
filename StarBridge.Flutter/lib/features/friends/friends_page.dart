import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import '../common/user_avatar_menu.dart';
import '../direct_messages/chat_avatar.dart';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../platform/window/native_viewport_visibility.dart';
import '../../app/shell/widgets/attention_badge.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'friends_module.dart';
import 'friend_action_controls.dart';
import 'example_friends_adapter.dart';
import '../direct_messages/direct_messages_module.dart';
import '../direct_messages/direct_messages_page.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({
    required this.createPort,
    this.module,
    this.createChatPort,
    this.inboxRequests,
    this.openCommunityInvite,
    this.sendCommunityInvite,
    super.key,
  });
  final FriendsPort Function() createPort;
  final FriendsModule? module;
  final DirectMessagesPort Function()? createChatPort;
  final ValueNotifier<int>? inboxRequests;
  final Future<void> Function(BuildContext, String)? openCommunityInvite;
  final Future<void> Function(BuildContext, DirectMessagesModule)?
  sendCommunityInvite;
  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  late final FriendsModule _module;
  final _search = TextEditingController();
  int _accountRevision = 0;
  late final bool _example;
  bool _chat = false;
  bool _notificationInbox = false;
  Conversation? _initialConversation;
  DirectMessagesModule? _messages;
  Timer? _attentionRefresh;
  Timer? _sharingRefresh;
  int unread(FriendRow row) => row.conversationKey == null
      ? 0
      : _messages?.rows
                .where((c) => c.conversationKey == row.conversationKey)
                .firstOrNull
                ?.unread ??
            0;
  @override
  void initState() {
    super.initState();
    _chat = (widget.inboxRequests?.value ?? 0) > 0;
    _notificationInbox = _chat;
    if (_chat) widget.inboxRequests?.value = 0;
    widget.inboxRequests?.addListener(_openInbox);
    final port = widget.module == null ? widget.createPort() : null;
    _example =
        port is ExampleFriendsAdapter || widget.module?.isExample == true;
    _module = widget.module ?? FriendsModule(port!);
    _module.addListener(_syncAccount);
    _accountRevision = _module.accountRevision;
    _search.text = _module.query;
    unawaited(_module.enter());
    _sharingRefresh = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_visible && !_chat && !_module.busy && !_module.searching) {
        unawaited(_module.refresh(silent: true));
      }
    });
    if (widget.createChatPort != null) {
      _messages = DirectMessagesModule(widget.createChatPort!());
      unawaited(_messages!.refresh());
      _attentionRefresh = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_visible && !_chat && !(_messages?.busy ?? true)) {
          unawaited(_messages!.refresh(retainDirectory: true));
        }
      });
    }
  }

  void _syncAccount() {
    if (_accountRevision != _module.accountRevision || !_module.searching) {
      _accountRevision = _module.accountRevision;
      _search.clear();
    }
  }

  bool get _visible =>
      mounted &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      NativeViewportScope.isActive(context) &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  void _openInbox() {
    if (!mounted || (widget.inboxRequests?.value ?? 0) == 0) return;
    widget.inboxRequests?.value = 0;
    if (_chat) return; // Never replace an active conversation or unsent draft.
    setState(() {
      _chat = true;
      _notificationInbox = true;
      _initialConversation = null;
    });
  }

  @override
  void dispose() {
    widget.inboxRequests?.removeListener(_openInbox);
    _attentionRefresh?.cancel();
    _sharingRefresh?.cancel();
    _messages?.dispose();
    _module.removeListener(_syncAccount);
    if (widget.module == null) _module.dispose();
    _search.dispose();
    super.dispose();
  }

  String t(String key) => AppStrings.of(context).text('friends.$key');
  String _sharedText(FriendRow row) {
    final s = row.shared, strings = AppStrings.of(context);
    final parts = <String>[];
    final presence = s['presence'];
    if (presence != null) {
      parts.add(
        strings.text(switch (presence) {
          'InGame' => 'presence.inGame',
          'AppOnline' => 'presence.online',
          'Away' => 'presence.away',
          _ => 'presence.offline',
        }),
      );
    }
    if (s['sameServer'] is bool) {
      parts.add(
        strings.text(
          s['sameServer'] == true
              ? 'settings.privacy.friends.sameServer'
              : 'settings.privacy.friends.otherServer',
        ),
      );
    }
    for (final key in const ['serverId', 'serverRegion', 'ship', 'location']) {
      if (s[key] is String && (s[key] as String).isNotEmpty) {
        parts.add(s[key] as String);
      }
    }
    if (s['lastOnlineAt'] is String) {
      final date = DateTime.tryParse(s['lastOnlineAt'] as String)?.toLocal();
      if (date != null) {
        parts.add(
          '${strings.text('settings.privacy.field.lastOnline')}: ${MaterialLocalizations.of(context).formatShortDate(date)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
        );
      }
    }
    return parts.join(' · ');
  }

  void _openRecent() => setState(() {
    _initialConversation = null;
    _chat = true;
  });

  @override
  Widget build(BuildContext context) => _chat
      ? DirectMessagesPage(
          createPort: widget.createChatPort!,
          initialConversation: _initialConversation,
          sharedModule: _notificationInbox ? null : _messages,
          openCommunityInvite: widget.openCommunityInvite,
          sendCommunityInvite: widget.sendCommunityInvite,
          onBack: () {
            setState(() {
              _chat = false;
              _notificationInbox = false;
            });
            unawaited(_messages!.refresh());
          },
        )
      : ListenableBuilder(
          listenable: Listenable.merge([_module, ?_messages]),
          builder: (context, _) => Padding(
            padding: EdgeInsets.all(context.tokens.space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _panelDecoration(),
                  child: LayoutBuilder(
                    builder: (context, bounds) {
                      final title = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('title'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t(
                              _example
                                  ? 'exampleActions'
                                  : _module.commandsAvailable
                                  ? 'manageHint'
                                  : 'readOnly',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      );
                      final search = Row(
                        children: [
                          Expanded(
                            child: TextField(
                              enabled: !_module.busy,
                              controller: _search,
                              maxLength: 128,
                              decoration: InputDecoration(
                                labelText: t('search'),
                                hintText: t('searchHint'),
                                counterText: '',
                                suffixIcon: _module.searching
                                    ? IconButton(
                                        tooltip: t('clear'),
                                        icon: const StarBridgeIcon(
                                          StarBridgeIconSemantic.windowClose,
                                        ),
                                        onPressed: () {
                                          _search.clear();
                                          _module.editQuery('');
                                        },
                                      )
                                    : null,
                              ),
                              onChanged: _module.editQuery,
                              onSubmitted: (_) {
                                if (_module.validQuery) {
                                  unawaited(_module.refresh());
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed:
                                !_module.busy &&
                                    _module.validQuery &&
                                    _module.state != FriendsReadState.loading
                                ? _module.refresh
                                : null,
                            child: Text(t('searchButton')),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed:
                                _module.busy ||
                                    _module.state == FriendsReadState.loading
                                ? null
                                : _module.refresh,
                            child: Text(t('refresh')),
                          ),
                        ],
                      );
                      return bounds.maxWidth >= 1000
                          ? Row(
                              children: [
                                Expanded(child: title),
                                const SizedBox(width: 24),
                                SizedBox(width: 490, child: search),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                title,
                                const SizedBox(height: 12),
                                search,
                              ],
                            );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, bounds) => Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: bounds.maxWidth < 640 ? 124 : 190,
                          child: Container(
                            decoration: _panelDecoration(),
                            child: Material(
                              color: Colors.transparent,
                              child: ListView(
                                children: [
                                  if (widget.createChatPort != null) ...[
                                    ListTile(
                                      key: const Key('friends-recent'),
                                      title: Text(
                                        t('recent'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                      trailing: AttentionCount(
                                        count:
                                            _messages?.rows.fold<int>(
                                              0,
                                              (n, c) => n + c.unread,
                                            ) ??
                                            0,
                                      ),
                                      onTap: _module.busy ? null : _openRecent,
                                    ),
                                    const Divider(),
                                  ],
                                  for (final section in FriendsSection.values)
                                    ListTile(
                                      key: ValueKey(
                                        'friends-nav-${section.name}',
                                      ),
                                      title: Text(
                                        t(section.name),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                      trailing:
                                          !_module.searching &&
                                              _module.snapshot != null
                                          ? section == FriendsSection.incoming
                                                ? AttentionCount(
                                                    count:
                                                        _module
                                                            .snapshot!
                                                            .groups[section]
                                                            ?.length ??
                                                        0,
                                                  )
                                                : Text(
                                                    '${_module.snapshot!.groups[section]?.length ?? 0}',
                                                  )
                                          : null,
                                      selected:
                                          !_module.searching &&
                                          _module.section == section,
                                      selectedTileColor:
                                          context.tokens.surfaces.selected.fill,
                                      selectedColor:
                                          context.tokens.colors.accent,
                                      onTap: _module.busy
                                          ? null
                                          : () {
                                              _search.clear();
                                              _module.select(section);
                                            },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: _panelDecoration(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  t(
                                    _module.searching
                                        ? 'search'
                                        : _module.section.name,
                                  ),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 12),
                                if (_module.busy)
                                  const LinearProgressIndicator(),
                                if (_module.feedback != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      t(_module.feedback!),
                                      style: TextStyle(
                                        color: _module.feedbackSuccess
                                            ? context.tokens.colors.success
                                            : context.tokens.colors.warning,
                                      ),
                                    ),
                                  ),
                                if (_module.searching)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      t('searchLimit'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                Expanded(child: _content()),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
  BoxDecoration _panelDecoration() => BoxDecoration(
    color: context.tokens.surfaces.panel.fill,
    border: Border.all(color: context.tokens.surfaces.panel.border),
    borderRadius: BorderRadius.circular(8),
  );
  void _openFriend(FriendRow row) {
    if (_module.busy ||
        row.chatTargetRef == null ||
        widget.createChatPort == null) {
      return;
    }
    setState(() {
      _initialConversation = Conversation(
        row.chatTargetRef!,
        row.name,
        '',
        row.updatedAt,
        0,
        'friend',
        avatar: row.avatar,
        gameId: row.gameId,
        conversationKey: row.conversationKey,
      );
      _chat = true;
    });
  }

  List<AvatarMenuAction> _avatarActions(FriendRow row) => [
    if (row.relationship == 'friend' && widget.createChatPort != null)
      AvatarMenuAction(
        AppStrings.of(context).text('avatar.sendMessage'),
        !_module.busy && row.chatTargetRef != null
            ? () => _openFriend(row)
            : null,
      ),
    for (final action in row.actions)
      AvatarMenuAction(
        t('action.$action'),
        _module.canExecute(row, action)
            ? () => unawaited(
                FriendActionControls(
                  module: _module,
                  row: row,
                ).perform(context, action),
              )
            : null,
        color: switch (action) {
          'remove' || 'block' => context.tokens.colors.danger,
          'accept' => context.tokens.colors.success,
          _ => null,
        },
      ),
  ];

  Widget _friendActions(FriendRow row, int index) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (row.relationship == 'friend' && widget.createChatPort != null)
        OutlinedButton.icon(
          key: ValueKey('friend-message-$index'),
          onPressed: _module.busy || row.chatTargetRef == null
              ? null
              : () => _openFriend(row),
          icon: const StandardIcon(StandardIconSemantic.chatBubble, size: 16),
          label: AttentionBadge(
            count: unread(row),
            child: Text(AppStrings.of(context).text('direct.title')),
          ),
        ),
      FriendActionControls(module: _module, row: row, compact: true),
    ],
  );
  Widget _content() {
    if (_module.state == FriendsReadState.loading) {
      return Center(
        child: Semantics(
          label: t('loading'),
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (_module.state == FriendsReadState.idle) {
      return _message(t(_module.validQuery ? 'submitSearch' : 'queryLength'));
    }
    if (_module.state == FriendsReadState.signedOut) {
      return _message(t('signedOut'));
    }
    if (_module.state == FriendsReadState.unavailable) {
      return _message(t(_module.failure), retry: true);
    }
    final rows = _module.rows;
    if (rows.isEmpty) {
      return _message(
        t(_module.searching ? 'noResults' : 'empty.${_module.section.name}'),
      );
    }
    return ListView.separated(
      key: ValueKey('${_module.section.name}:${_module.snapshot?.query}'),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = rows[index];
        return Container(
          key: ValueKey('friend-card-$index'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.tokens.surfaces.panel.fill,
            border: Border.all(color: context.tokens.surfaces.panel.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: LayoutBuilder(
            builder: (context, bounds) {
              final person = Row(
                children: [
                  ChatAvatar(
                    label: row.name,
                    source: row.avatar,
                    size: 44,
                    actions: _avatarActions(row),
                    target: row.targetRef == null ? null : UserTarget('friend', row.targetRef!, query: row.gameId),
                    includeSocialActions: false,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.name.isEmpty ? t('unnamed') : row.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t('relation.${row.relationship}'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (row.shared.values.any((value) => value != null))
                          Text(
                            _sharedText(row),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              );
              return bounds.maxWidth >= 680
                  ? Row(
                      children: [
                        Expanded(child: person),
                        const SizedBox(width: 16),
                        _friendActions(row, index),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        person,
                        const SizedBox(height: 12),
                        _friendActions(row, index),
                      ],
                    );
            },
          ),
        );
      },
    );
  }

  Widget _message(String message, {bool retry = false}) => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (retry)
            TextButton(onPressed: _module.refresh, child: Text(t('retry'))),
        ],
      ),
    ),
  );
}
