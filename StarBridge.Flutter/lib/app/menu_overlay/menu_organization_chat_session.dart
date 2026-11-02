import 'menu_overlay_text.dart';

import 'dart:async';

import '../../features/communities/communities_module.dart';
import '../../features/communities/community_chat_controller.dart';
import '../../features/communities/community_chat_port.dart';
import '../../features/communities/community_own_avatar.dart';
import '../../platform/window/menu_profile_navigation.dart';
import 'menu_account_avatar.dart';
import 'menu_chat_archive.dart';
import 'menu_feature_session.dart';
import 'menu_organization_chat_portraits.dart';
import 'menu_organization_presentation.dart';
import 'menu_organization_profiles.dart';

/// Owns the organization chat's authorized controllers, outbox and projections.
/// The enclosing feature session retains visibility/account epochs and grants
/// every action; this module never schedules an independent read or lease.
final class MenuOrganizationChatSession {
  MenuOrganizationChatSession(
    this.port,
    this.session, {
    required this.selected,
    required this.nextProfileKey,
    required this.observed,
    required this.chatSelected,
    this.archive,
  });
  final CommunitiesPort port;
  final MenuFeatureSession session;
  final String? Function() selected;
  final String Function() nextProfileKey;
  final void Function(String, List<CommunityChatMessage>, int) observed;
  final MenuChatArchive? archive;
  final bool Function() chatSelected;
  CommunityChatController? active;
  int sentRevision = 0;
  String sendStatus = 'idle';
  String? failedVisibleMessageRef;
  final views = <String, Map<String, Object?>>{};
  final portraits = MenuOrganizationChatPortraits();
  late final ownPhoto = MenuAccountAvatar(() {
    if (session.visible && !session.disposed) session.emit(session.templateView);
  });

  final _chats = <String, CommunityChatController>{};
  final _deliveries = Expando<_MenuOrganizationDelivery>();
  int _deliverySerial = 0;

  CommunityChatController _createChat(String target) {
    final chat = CommunityChatController(
      port as CommunityChatPort,
      target,
      localEcho: true,
    );
    _deliveries[chat] = _MenuOrganizationDelivery('o${++_deliverySerial}');
    return chat;
  }

  Future<void> _sendLocal(
    CommunityChatController chat,
    String key,
    String text, {
    CommunityLocalMessage? retry,
  }) async {
    final account = session.accountEpoch;
    if (retry == null
        ? !chat.canSubmit || _deliveries[chat]!.shown.length >= 20
        : !chat.canRetry(retry)) {
      session.emit({...session.templateView, 'rejectedAction': key});
      return;
    }
    final delivery = _deliveries[chat]!;
    final previousCount = chat.localMessages.length;
    final previousIntent = retry?.intent;
    if (retry == null) chat.updateDraft(text);
    final work = chat.submit(retry: retry);
    final owned = retry == null
        ? chat.localMessages.length > previousCount
        : !identical(retry.intent, previousIntent);
    if (!owned) {
      // Validation can fail synchronously before a local record is created.
      // The menu editor remains the owner in that case and must keep its text.
      if (retry == null) chat.updateDraft('');
      session.emit({...session.templateView, 'rejectedAction': key});
      await work;
      return;
    }
    delivery.acceptedAction = key;
    delivery.timedOut = false;
    // Local ownership is acknowledged before waiting for the remote result.
    session.emit(session.templateView);
    await work;
    if (!session.currentAccount(account) || !identical(active, chat)) return;
    if (chat.invalidated) {
      session.changeScope();
      session.emit({'state': 'unavailable'});
      return;
    }
    sendStatus = chat.sendUncertain
        ? 'unknown'
        : chat.sendError != null
        ? 'rejected'
        : 'sent';
    if (sendStatus == 'sent') sentRevision++;
    // Usually the feature session owns the final refresh. A late result
    // still needs one coherent history/outbox projection, never a text match.
    unawaited(session.refresh(silent: true));
  }

  Map<String, Object?> deliveryProjection(
    CommunityChatController chat, {
    bool coherent = false,
  }) {
    final delivery = _deliveries[chat]!;
    final localMessages = chat.localMessages;
    final shown = [
      if (!coherent)
        ...delivery.shown.where(
          (m) => m.state == 'sent' && !localMessages.contains(m),
        ),
      ...localMessages,
    ];
    delivery.shown = shown;
    return {
      'outboxVersion': 1,
      'outboxOwner': delivery.owner,
      'acceptedAction': delivery.acceptedAction,
      if (delivery.timedOut && chat.sending) 'status': 'unknown',
      'localMessages': [
        for (final local in shown)
          {
            'id': delivery.ids[local] ??= 'l${++delivery.serial}',
            'text': local.intent.text,
            'time': local.createdAt.toUtc().toIso8601String(),
            'state': delivery.timedOut && local.state == 'sending'
                ? 'unknown'
                : local.state,
            'error': local.error,
            if (chat.canRetry(local))
              'retry': (() {
                late Map<String, Object?> action;
                action = session.button(
                  MenuOverlayText('menu.overlay.comms.retryMessage'),
                  (_) => _sendLocal(
                    chat,
                    action['key'] as String,
                    '',
                    retry: local,
                  ),
                );
                return action['key'];
              })(),
            if (chat.canRestore(local))
              'restore': (() {
                late Map<String, Object?> action;
                action = session.button(
                  MenuOverlayText('menu.overlay.comms.editMessage'),
                  (_) async {
                    final key = action['key'] as String;
                    if (!chat.canRestore(local)) {
                      session.emit({
                        ...session.templateView,
                        'rejectedAction': key,
                      });
                      return;
                    }
                    chat.restoreLocalDraft(local);
                    // The renderer already holds a guarded copy. Confirm that
                    // the failed record has been retired before unlocking it.
                    chat.updateDraft('');
                    delivery.acceptedAction = key;
                    session.emit(session.templateView);
                  },
                  role: 'editMessage',
                );
                return action['key'];
              })(),
          },
      ],
    };
  }

  Map<String, Object?>? failedWrite() {
    final chat = active;
    if (chat == null ||
        chat.invalidated ||
        !chat.hasLocalDelivery ||
        session.templateView['chat'] is! Map) {
      return null;
    }
    _deliveries[chat]!.timedOut = true;
    return {
      ...session.templateView,
      'busy': false,
      'refreshing': false,
      'notice': MenuOverlayText('menu.overlay.comms.sendRetained'),
    };
  }

  Map<String, Object?>? get writingView {
    final chat = active;
    if (chat == null || chat.invalidated || !chat.hasLocalDelivery) return null;
    // Reopening during a write exposes only account-owned local text. Remote
    // history, directory, profiles and receipts wait for a fresh authorized read.
    return {
      'state': 'ready',
      'title': MenuOverlayText('menu.overlay.organizations.chat'),
      'busy': true,
      'rows': <Map<String, Object?>>[],
      'buttons': <Map<String, Object?>>[],
      'chat': {
        ...deliveryProjection(chat),
        'status': sendStatus,
        'revision': sentRevision,
        'availability': 'checking',
        'messages': <Map<String, Object?>>[],
        'receipts': <String, String>{},
      },
      'organization': {
        'tab': 'chat',
        'total': 0,
        'matched': 0,
        'offset': 0,
        'rows': <Map<String, Object?>>[],
      },
    };
  }

  // Chat avatar keys survive quiet polls; authority stays in the primary engine.
  final _chatProfiles =
      <
        String,
        ({String target, CommunityChatMessage message, DateTime expires})
      >{};
  MenuProfileTarget? profileTarget(String key) {
    final binding = _chatProfiles[key];
    if (binding != null) {
      final identity = session.accountEpoch;
      bool valid() =>
          session.currentAccount(identity) &&
          session.visible &&
          selected() == binding.target &&
          _chatProfiles[key]?.message.senderRef == binding.message.senderRef &&
          _chatProfiles[key]?.message.isSelf == binding.message.isSelf &&
          DateTime.now().isBefore(binding.expires);
      if (!valid()) return null;
      final message = binding.message;
      final Object source = port;
      return organizationChatProfileTarget(
        port as CommunityChatPort,
        target: binding.target,
        message: message,
        avatar: message.isSelf && source is CommunityOwnAvatarSource
            ? ownPhoto.read(source.ownAvatarImageData)
            : portraits.photos[binding.target]?[message.messageRef],
        isCurrent: valid,
        isAccountCurrent: () => session.currentAccount(identity),
      );
    }
    return null;
  }

  Future<
    ({
      List<Map<String, Object?>> rows,
      List<Map<String, Object?>> actions,
      List<Map<String, Object?>> messages,
      Map<String, String> profiles,
      Map<String, String> receipts,
      Object notice,
    })
  >
  read(String target, int epoch) async {
    final rows = <Map<String, Object?>>[], actions = <Map<String, Object?>>[];
    final messagePresentation = <Map<String, Object?>>[];
    final messageProfiles = <String, String>{}, receipts = <String, String>{};
    Object notice = '';
    if (!_chats.containsKey(target) && _chats.length >= 12) {
      final clean = _chats.entries
          .where((e) => !e.value.hasLocalDelivery)
          .firstOrNull;
      if (clean == null) throw const CommunityFailure('unavailable');
      _chats.remove(clean.key)?.dispose();
    }
    active = _chats.putIfAbsent(target, () => _createChat(target));
    final chat = active!;
    await chat.refresh(silent: session.silentRead);
    if (!session.current(epoch)) {
      throw StateError('retired');
    }
    if (chat.invalidated) {
      views.remove(target);
      throw StateError('restricted');
    }
    if (chat.error != null) throw CommunityFailure(chat.error!);
    observed(target, chat.messages, chat.unreadCount);
    if (chat.localHistoryUnavailable) {
      notice = MenuOverlayText('menu.overlay.comms.cacheFailed');
    }
    if (archive != null) {
      actions.add(
        session.button(
          MenuOverlayText('menu.overlay.comms.clearLocal'),
          (_) async {
            await archive!.clear('organization', target);
            views.remove(target);
          },
          confirm: MenuOverlayText('menu.overlay.comms.clearConfirm'),
          role: 'clearLocalHistory',
        ),
      );
    }
    if (sendStatus == 'unknown' &&
        !chat.sendUncertain &&
        chat.sendError == null &&
        chat.draft.isEmpty) {
      sendStatus = 'sent';
      sentRevision++;
    }
    {
      final senders = chat.messages.map((m) => m.senderRef).toSet();
      _chatProfiles.removeWhere(
        (_, b) => b.target != target || !senders.contains(b.message.senderRef),
      );
    }
    for (final (index, message) in chat.messages.indexed) {
      rows.add({
        'title': message.callsign.isEmpty ? message.gameId : message.callsign,
        'detail': MenuOverlayJoin([
          message.text,
          if (message.hasAttachment)
            const MenuOverlayText('menu.overlay.comms.attachmentClient'),
        ]),
      });
      {
        final key =
            _chatProfiles.entries
                .where(
                  (e) =>
                      e.value.target == target &&
                      e.value.message.senderRef == message.senderRef &&
                      e.value.message.isSelf == message.isSelf,
                )
                .firstOrNull
                ?.key ??
            nextProfileKey();
        _chatProfiles[key] = (
          target: target,
          message: message,
          expires: DateTime.now().add(const Duration(minutes: 2)),
        );
        messageProfiles['$index'] = key;
        messagePresentation.add({
          'self': message.isSelf,
          'time': message.createdAt.toUtc().toIso8601String(),
          'role': message.roleTitle,
          'roleColor': message.roleColor,
        });
        if (!message.isSelf &&
            message.sequence > chat.confirmedReadThrough &&
            chat.receiptError == null) {
          receipts['$index'] =
              session.button(
                    MenuOverlayText('menu.overlay.comms.readMessages'),
                    (_) async {
                      failedVisibleMessageRef = message.messageRef;
                      chat.setReadingContext(visible: true, foreground: true);
                      try {
                        await chat.acknowledgeVisible(message.messageRef);
                      } finally {
                        chat.setReadingContext(
                          visible: false,
                          foreground: false,
                        );
                      }
                    },
                    silent: true,
                    role: 'readMessages',
                  )['key']
                  as String;
        }
      }
    }
    if (chat.canSubmit && _deliveries[chat]!.shown.length < 20) {
      late Map<String, Object?> sendAction;
      sendAction = session.button(
        MenuOverlayText('menu.overlay.comms.sendMessage'),
        (text) async {
          await _sendLocal(chat, sendAction['key'] as String, text);
        },
        input: MenuOverlayText('menu.overlay.comms.input'),
        limit: 1000,
        role: 'sendMessage',
      );
      actions.add(sendAction);
    }
    if (chat.sendUncertain) {
      notice = MenuOverlayText('menu.overlay.comms.checkHistory');
    } else if (chat.sendError != null) {
      notice = MenuOverlayText('menu.overlay.comms.editRejected');
    } else if (_deliveries[chat]!.shown.length >= 20) {
      notice = MenuOverlayText('menu.overlay.comms.pendingLimit');
    }
    if (chat.hasOlder) {
      actions.add(
        session.button(MenuOverlayText('menu.overlay.comms.older'), (_) async {
          await chat.loadOlder();
        }, role: 'olderMessages'),
      );
    }
    if (!session.silentRead &&
        chat.receiptError != null &&
        failedVisibleMessageRef != null) {
      actions.add(
        session.button(MenuOverlayText('menu.overlay.comms.retryReadSync'), (
          _,
        ) async {
          chat.setReadingContext(visible: true, foreground: true);
          try {
            await chat.acknowledgeVisible(
              failedVisibleMessageRef!,
              retry: true,
            );
          } finally {
            chat.setReadingContext(visible: false, foreground: false);
          }
        }, role: 'retryReadReceipt'),
      );
    }

    return (
      rows: rows,
      actions: actions,
      messages: messagePresentation,
      profiles: messageProfiles,
      receipts: receipts,
      notice: notice,
    );
  }

  Iterable<String> get targets => _chats.keys;
  void rebind(String previous, String target) {
    final retained = _chats.remove(previous);
    if (retained != null) {
      retained.renewVerifiedReference(target);
      _chats[target] = retained;
    }
  }

  void remove(String target) => _chats.remove(target)?.dispose();
  void clearProfiles() => _chatProfiles.clear();
  void closeChats() {
    for (final chat in _chats.values) {
      chat.dispose();
    }
    _chats.clear();
    active = null;
  }

  void clear() {
    views.clear();
    portraits.clear();
    ownPhoto.clear();
    _chatProfiles.clear();
    sentRevision = 0;
    sendStatus = 'idle';
    failedVisibleMessageRef = null;
  }

  void dispose() {
    portraits.dispose();
    ownPhoto.dispose();
  }

  Map<String, Object?> projectDelivery(Map<String, Object?> view) {
    final chat = active;
    final channel = view['chat'];
    if (chat != null &&
        !chat.invalidated &&
        channel is Map &&
        channel['outboxOwner'] == _deliveries[chat]?.owner) {
      view = {
        ...view,
        'chat': {...channel, ...deliveryProjection(chat)},
      };
    }
    return view;
  }

  Map<String, Object?> projectPortraits(Map<String, Object?> view) {
    final Object source = port;
    final own = ownPhoto.read(
      source is CommunityOwnAvatarSource ? source.ownAvatarImageData : null,
    );
    if (view['chat'] is Map && (view['chat'] as Map)['outboxVersion'] == 1) {
      view = {
        ...view,
        'chat': {...(view['chat'] as Map), 'ownAvatar': own},
      };
    }
    return organizationPortraits(
      view,
      own,
      portraits.messages[selected()],
      portraits.photos[selected()],
    );
  }

  void cache(String target, Map<String, Object?> view) {
    if (!views.containsKey(target) && views.length >= 24) {
      final expired = views.keys.first;
      views.remove(expired);
      portraits.remove(expired);
    }
    views[target] = view;
    final messages = List<CommunityChatMessage>.of(
      active?.messages ?? const [],
    );
    final account = session.accountEpoch;
    portraits.load(
      port as CommunityChatPort,
      target,
      messages,
      () => session.currentAccount(account),
      () {
        if (session.visible && selected() == target && chatSelected()) {
          session.emit(session.templateView);
        }
      },
    );
  }
}

final class _MenuOrganizationDelivery {
  _MenuOrganizationDelivery(this.owner);
  final String owner;
  String? acceptedAction;
  bool timedOut = false;
  int serial = 0;
  final ids = Expando<String>();
  List<CommunityLocalMessage> shown = const [];
}
