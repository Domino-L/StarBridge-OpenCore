import 'dart:async';

import '../routing/room_invitation_destination.dart';

import 'dart:convert';

import 'package:flutter/services.dart';

import '../../features/direct_messages/direct_messages_module.dart';
import '../../features/notifications/notification_inbox_controller.dart';
import 'social_window_codec.dart';
import '../preferences/app_preferences_port.dart';
import 'window_presentation.dart';

/// Primary-engine authority. Secondary engines never receive credentials,
/// a BridgeClientSession, or an arbitrary Host request capability.
class SocialWindowBinding {
  SocialWindowBinding({
    required this.kind,
    required this.messages,
    required this.inbox,
    required this.navigate,
    this.openInvite,
    this.sendInvite,
    this.openProfile,
    this.preferences,
    MethodChannel? channel,
  }) : channel = channel ?? MethodChannel('starbridge/$kind-primary') {
    this.channel.setMethodCallHandler(_receive);
    _invalidations = messages.invalidations.listen((_) => invalidate());
    if (messages is DirectMessageActivityPort) {
      _activity = (messages as DirectMessageActivityPort).changes.listen(
        (_) => pulse(),
      );
    }
    inbox.addListener(pulse);
    preferences?.projection.addListener(pulse);
  }
  final String kind;
  final AppPreferencesPort? preferences;
  final DirectMessagesPort messages;
  final NotificationInboxController inbox;
  final Future<void> Function(String) navigate;
  final Future<void> Function(String)? openInvite;
  final Future<void> Function(Conversation)? sendInvite;
  final Future<void> Function(Conversation)? openProfile;
  final Map<String, Conversation> _known = {};
  bool _active = false;
  String? _visibleRef;
  String? get visibleConversationKey =>
      _active && _visible ? _known[_visibleRef]?.conversationKey : null;
  final MethodChannel channel;
  StreamSubscription<void>? _invalidations, _activity;
  bool _disposed = false, _visible = false, _openingNow = false;
  int _opening = 0, _revision = 0, _epoch = 0, _targetVersion = 0;
  final String _instance = DateTime.now().microsecondsSinceEpoch.toString();
  Conversation? _target;
  String get scope => '$_instance:$_epoch';
  Map<String, Object?> get snapshot => {
    'opening': _opening,
    'revision': _revision,
    if (preferences != null)
      'presentation': encodeWindowPresentation(
        preferences!.projection.value.effective,
      ),
    'view': jsonEncode({
      'scope': scope,
      'targetVersion': _targetVersion,
      'openInvite': openInvite != null,
      'sendInvite': sendInvite != null,
      'openProfile': openProfile != null,
      if (_target != null) 'target': encodeConversation(_target!),
      'supportsSending':
          messages is DirectMessageSender &&
          (messages as DirectMessageSender).supportsSending,
      'supportsRead':
          messages is DirectReadReceiptPort &&
          (messages as DirectReadReceiptPort).supportsReadReceipts,
      'viewerAvatar': messages is DirectViewerAvatarPort
          ? (messages as DirectViewerAvatarPort).viewerAvatar
          : null,
    }),
  };
  Future<bool> open({Conversation? target}) async {
    if (_disposed) return false;
    if (target != null) {
      _target = target;
      _known[target.ref] = target;
      _targetVersion++;
    }
    if (_openingNow) {
      pulse();
      return true;
    }
    _openingNow = true;
    if (!_visible) {
      _opening++;
      _visible = true;
    }
    try {
      final shown = await channel.invokeMethod<bool>('show', snapshot) == true;
      if (!shown) _visible = false;
      return shown;
    } on PlatformException {
      _visible = false;
      return false;
    } on MissingPluginException {
      _visible = false;
      return false;
    } finally {
      _openingNow = false;
    }
  }

  void invalidate() {
    if (_disposed) return;
    _epoch++;
    _known.clear();
    _visibleRef = null;
    _target = null;
    _targetVersion++;
    messages.cancel();
    pulse();
  }

  void pulse() {
    if (_disposed) return;
    _revision++;
    if (_opening > 0) unawaited(_notify('snapshot', snapshot));
  }

  Future<void> _notify(String method, [Object? value]) async {
    try {
      await channel.invokeMethod<void>(method, value);
    } on PlatformException {
      /* No replay of writes. */
    } on MissingPluginException {
      /* Page fallback. */
    }
  }

  Future<Object?> _receive(MethodCall call) async {
    final a = call.arguments;
    if (_disposed || a is! Map || a['opening'] != _opening) {
      throw PlatformException(code: 'window.stale');
    }
    if (call.method == 'hidden') {
      _visible = false;
      _active = false;
      return true;
    }
    if (call.method == 'viewportActive') {
      _active = a['active'] == true;
      return true;
    }
    if (call.method != 'rpc' || !_visible || a['scope'] != scope) {
      throw PlatformException(code: 'window.stale');
    }
    final epoch = _epoch;
    final op = a['op'];
    Object? result;
    if (op == 'viewport') {
      _visibleRef = a['ref'] is String && _known.containsKey(a['ref'])
          ? a['ref'] as String
          : null;
      return true;
    }
    if (op == 'navigate' &&
        (const [
              '/friends',
              '/profile',
              '/rooms',
              '/rooms/invitations',
              '/communities',
              '/overlay',
              '/account-safety',
            ].contains(a['route']) ||
            a['route'] is String &&
                isRoomInvitationDestination(a['route'] as String))) {
      await navigate(a['route'] as String);
      result = true;
    } else if (kind == 'messages' &&
        op == 'profile' &&
        openProfile != null &&
        _known[a['ref']] != null) {
      await openProfile!(_known[a['ref']]!);
      result = true;
    } else if (kind == 'messages' &&
        op == 'openInvite' &&
        openInvite != null &&
        a['code'] is String &&
        RegExp(r'^[A-Za-z0-9_-]{6,40}$').hasMatch(a['code'] as String)) {
      await openInvite!(a['code'] as String);
      result = true;
    } else if (kind == 'messages' &&
        op == 'sendInvite' &&
        sendInvite != null &&
        _known[a['ref']] != null) {
      await sendInvite!(_known[a['ref']]!);
      result = true;
    } else if (kind == 'notifications') {
      if (op == 'refresh') {
        await inbox.refresh(reuseFresh: a['reuseFresh'] == true);
      } else if (op == 'markRead' &&
          a['refs'] is List &&
          (a['refs'] as List).length <= 5000) {
        final refs = (a['refs'] as List).whereType<String>().toSet();
        await inbox.markRead(
          inbox.items.where((i) => refs.contains(i.reference)).toList(),
        );
      } else {
        throw PlatformException(code: 'window.invalid');
      }
      result = {
        'items': inbox.items.map(encodeInbox).toList(),
        'ready': inbox.ready,
        'error': inbox.error,
      };
    } else if (op == 'directory') {
      final rows = await messages.directory();
      if (epoch == _epoch) {
        for (final row in rows) {
          _known[row.ref] = row;
        }
      }
      result = rows.map(encodeConversation).toList();
    } else {
      final ref = a['ref'];
      if (ref is! String || ref.isEmpty || ref.length > 256) {
        throw PlatformException(code: 'window.invalid');
      }
      if (op == 'history' &&
          a['before'] is int &&
          a['after'] is int &&
          (a['before'] as int) >= 0 &&
          (a['after'] as int) >= 0) {
        final page = await messages.history(
          ref,
          before: a['before'] as int,
          after: a['after'] as int,
        );
        result = {
          'ref': page.ref,
          'messages': page.messages.map(encodeMessage).toList(),
          'oldest': page.oldest,
          'latest': page.latest,
          'hasOlder': page.hasOlder,
          'state': page.state,
          'canSend': page.canSend,
          'localHistoryUnavailable': page.localHistoryUnavailable,
        };
      } else if (op == 'send' &&
          messages is DirectMessageSender &&
          a['text'] is String &&
          (a['text'] as String).trim().isNotEmpty &&
          (a['text'] as String).length <= 1000 &&
          a['id'] is String &&
          RegExp(r'^[a-f0-9]{32}$').hasMatch(a['id'] as String)) {
        final sent = await (messages as DirectMessageSender).send(
          ref,
          a['text'] as String,
          a['id'] as String,
        );
        result = {
          'status': sent.status,
          'error': sent.error,
          if (sent.message != null) 'message': encodeMessage(sent.message!),
        };
      } else if (op == 'markRead' &&
          messages is DirectReadReceiptPort &&
          a['through'] is int &&
          (a['through'] as int) > 0) {
        final read = await (messages as DirectReadReceiptPort).markRead(
          ref,
          a['through'] as int,
        );
        result = {'through': read.through, 'unread': read.unread};
      } else {
        throw PlatformException(code: 'window.invalid');
      }
    }
    if (_disposed || epoch != _epoch || a['scope'] != scope) {
      throw PlatformException(code: 'window.stale');
    }
    return result;
  }

  void dispose() {
    _disposed = true;
    _visible = false;
    _epoch++;
    channel.setMethodCallHandler(null);
    inbox.removeListener(pulse);
    preferences?.projection.removeListener(pulse);
    unawaited(_activity?.cancel());
    unawaited(_invalidations?.cancel());
    unawaited(messages.close());
    unawaited(_notify('detach'));
  }
}
