import 'dart:async';

import '../../shared/diagnostics/loading_metrics.dart';
import '../diagnostics/loading_diagnostics.dart';
import '../diagnostics/loading_tour.dart';

import '../routing/room_invitation_destination.dart';

import 'dart:convert';

import 'package:flutter/services.dart';

import '../../features/direct_messages/direct_messages_module.dart';
import '../../features/marketplace/marketplace_chat_controller.dart';
import '../../features/marketplace/marketplace_port.dart';
import '../../features/notifications/notification_inbox_controller.dart';
import 'social_window_codec.dart';
import '../preferences/app_preferences_port.dart';
import 'window_presentation.dart';
import 'window_opening_source.dart';
import 'window_message_health.dart';

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
    this.tradeChat,
    MethodChannel? channel,
  }) : channel = channel ?? MethodChannel('starbridge/$kind-primary') {
    this.channel.setMethodCallHandler(_receive);
    // 0.7.2 G9: 交易消息 in the detached messages window. Requests go through
    // the existing rpc; pushes ride the snapshot (the native relay forwards
    // only its fixed methods), so a new message still shows without a read.
    if (kind == 'messages' && tradeChat != null) {
      _tradePushSub = tradeChat!.port.chatPushes.listen((push) {
        _tradePushes.add({'serial': ++_tradeSerial, 'push': push});
        if (_tradePushes.length > 20) _tradePushes.removeAt(0);
        // A burst of pushes costs one snapshot, not one each (DL-138).
        _tradePulse ??= Timer(const Duration(milliseconds: 50), () {
          _tradePulse = null;
          pulse();
        });
      });
      tradeChat!.requests.addListener(pulse);
    }
    _invalidations = messages.invalidations.listen((_) => invalidate());
    if (messages is DirectMessageActivityPort) {
      _activity = (messages as DirectMessageActivityPort).changes.listen(
        (_) => pulse(),
      );
    }
    inbox.addListener(pulse);
    if (kind == 'messages' && messages is DirectMessageReceptionPort) {
      _reception = (messages as DirectMessageReceptionPort)
          .observeVisibleReception(() => !_disposed && _visible && _active);
    }
    preferences?.projection.addListener(pulse);
    _unregisterTour = LoadingDiagnostics.registerTourWindow(
      kind,
      LoadingTourWindow(open: open, close: () => _notify('detach')),
    );
    if (kind == 'messages' && messages is DirectMessageActivityHealthPort) {
      _healthTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _publishHealth(),
      );
    }
  }
  final String kind;
  final AppPreferencesPort? preferences;
  final DirectMessagesPort messages;
  final NotificationInboxController inbox;
  final Future<void> Function(String) navigate;
  final Future<void> Function(String)? openInvite;
  final Future<void> Function(Conversation)? sendInvite;
  final Future<void> Function(Conversation)? openProfile;
  final MarketplaceChatController? tradeChat;
  StreamSubscription<Map<String, Object?>>? _tradePushSub;
  Timer? _tradePulse;
  final _tradePushes = <Map<String, Object?>>[];
  int _tradeSerial = 0;
  static const _tradeOperations = {
    'conversations',
    'history',
    'openScm',
    'open',
    'openOrder',
    'read',
    'unread',
    'send',
    'focus',
  };
  final Map<String, Conversation> _known = {};
  bool _active = false;
  void Function()? _unregisterTour;
  String? _visibleRef;
  String? get visibleConversationKey =>
      _active && _visible ? _known[_visibleRef]?.conversationKey : null;
  final MethodChannel channel;
  StreamSubscription<void>? _invalidations, _activity;
  bool _disposed = false, _visible = false, _openingNow = false;
  int _opening = 0, _revision = 0, _epoch = 0, _targetVersion = 0;
  int _healthRevision = 0;
  bool? _lastHealth;
  Timer? _healthTimer;
  DirectMessageReceiveLease? _reception;
  bool get _healthy =>
      messages is DirectMessageActivityHealthPort &&
      (messages as DirectMessageActivityHealthPort).activityHealthy;
  Map<String, Object?> get _healthPacket => {
    'opening': _opening,
    'scope': scope,
    'revision': _healthRevision,
    'healthy': _healthy,
    'leaseMilliseconds': WindowMessageHealth.leaseMilliseconds,
    'sentAtUtcMilliseconds': DateTime.now().millisecondsSinceEpoch,
  };
  void _publishHealth() {
    if (_disposed || !_visible || !_active) return;
    final healthy = _healthy;
    if (!healthy && _lastHealth == false) return;
    _lastHealth = healthy;
    _healthRevision++;
    unawaited(_notify('activityHealth', _healthPacket));
  }

  String _openingSource = 'programmatic';
  final String _instance = DateTime.now().microsecondsSinceEpoch.toString();
  Conversation? _target;
  String get scope => '$_instance:$_epoch';
  Map<String, Object?> get snapshot => {
    'opening': _opening,
    'revision': _revision,
    'openingSource': _openingSource,
    if (kind == 'messages') ...{
      'activityScope': scope,
      'activityHealth': _healthPacket,
    },
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
      if (kind == 'messages' && tradeChat != null) ...{
        'tradeChat': true,
        'tradePushes': _tradePushes,
        if (tradeChat!.pendingRef case final ref?)
          'tradeRequest': {
            'serial': tradeChat!.requests.value,
            'ref': ref,
            if (tradeChat!.attachment case final attach?) ...{
              'orderId': attach.orderId,
              'label': attach.label,
            },
          },
      },
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
    final starting = !_visible;
    if (starting) {
      _openingSource = captureWindowOpeningSource().name;
      _opening++;
      _recordOpening(LoadingAuxiliaryPhase.request);
      _visible = true;
    }
    try {
      final request = _pendingTradeRequest;
      final shown = await channel.invokeMethod<bool>('show', snapshot) == true;
      if (!shown) _visible = false;
      if (shown) _tradeRequestDelivered(request);
      // Native answers show only after it revealed the painted window.
      if (shown && starting) _recordOpening(LoadingAuxiliaryPhase.shown);
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

  LoadingAuxiliarySurface? get _surface => switch (kind) {
    'messages' => LoadingAuxiliarySurface.messages,
    'notifications' => LoadingAuxiliarySurface.notifications,
    _ => null,
  };

  void _recordOpening(LoadingAuxiliaryPhase phase) {
    final surface = _surface;
    if (surface != null) {
      LoadingMetrics.current?.auxiliaryOpening(surface, phase, _opening);
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
    _healthRevision++;
    _revision++;
    if (_opening > 0) unawaited(_sendSnapshot());
  }

  Future<void> _sendSnapshot() async {
    final request = _pendingTradeRequest;
    try {
      await channel.invokeMethod<void>('snapshot', snapshot);
    } on PlatformException {
      return; /* No replay of writes. */
    } on MissingPluginException {
      return; /* Page fallback. */
    }
    _tradeRequestDelivered(request);
  }

  /// The pending 打开会话 request, as (serial, ref), when there is one.
  (int, String)? get _pendingTradeRequest => switch (tradeChat?.pendingRef) {
    final ref? => (tradeChat!.requests.value, ref),
    _ => null,
  };

  /// A request the open window received is consumed here, once, so a later
  /// opening does not jump to it again.
  void _tradeRequestDelivered((int, String)? request) {
    if (_disposed || !_visible || request == null) return;
    if (_pendingTradeRequest == request) tradeChat!.takeRequest();
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
    try {
      return await _handle(call);
    } on DirectReadFailure catch (failure) {
      const codes = {
        'forbidden',
        'identity_unavailable',
        'target_changed',
        'data_invalid',
        'unavailable',
        'limit',
        'outcome_unknown',
      };
      throw PlatformException(
        code:
            'messages.read.${codes.contains(failure.code) ? failure.code : 'unavailable'}',
      );
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    final a = call.arguments;
    if (_disposed || a is! Map || a['opening'] != _opening) {
      throw PlatformException(code: 'window.stale');
    }
    if (call.method == 'hidden') {
      _visible = false;
      _active = false;
      return true;
    }
    if (call.method == 'engineCreated') {
      final from = a['beginWallUs'], to = a['endWallUs'], surface = _surface;
      if (from is int && to is int && surface != null) {
        LoadingMetrics.current?.auxiliaryEngine(surface, from, to);
      }
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
              '/marketplace?section=trades',
              '/messages?section=trade',
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
        final automatic = a['reuseFresh'] == true;
        // DL-138: an automatic refresh (opening, pulse) shows the list the
        // primary already holds; the refresh continues behind it and its
        // change pulses the window again. An explicit refresh still waits.
        if (automatic && inbox.ready && inbox.error == null) {
          unawaited(inbox.refresh(reuseFresh: true));
        } else {
          await inbox.refresh(reuseFresh: automatic);
        }
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
    } else if (kind == 'messages' &&
        op == 'trade' &&
        tradeChat != null &&
        // 解除拉黑 from a conversation is the one records operation relayed.
        (a['records'] == true
            ? a['operation'] == 'unblock' &&
                  tradeChat!.port is MarketplaceRecordsPort
            : _tradeOperations.contains(a['operation'])) &&
        (a['input'] == null || a['input'] is Map)) {
      final input = Map<String, Object?>.from(a['input'] as Map? ?? const {});
      final port = tradeChat!.port;
      try {
        result = a['records'] == true
            ? await (port as MarketplaceRecordsPort).records('unblock', input)
            : await port.chat(a['operation'] as String, input);
      } on MarketplaceTradeError catch (failure) {
        throw PlatformException(code: failure.code);
      }
    } else if (op == 'directory') {
      final reader = messages;
      final rows =
          a['published'] == true && reader is DirectMessageDirectoryUpdatesPort
          ? await (reader as DirectMessageDirectoryUpdatesPort)
                .receiveDirectory()
          : await reader.directory();
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
    _unregisterTour?.call();
    _healthTimer?.cancel();
    _reception?.dispose();
    _visible = false;
    _epoch++;
    channel.setMethodCallHandler(null);
    inbox.removeListener(pulse);
    tradeChat?.requests.removeListener(pulse);
    unawaited(_tradePushSub?.cancel());
    _tradePulse?.cancel();
    preferences?.projection.removeListener(pulse);
    unawaited(_activity?.cancel());
    unawaited(_invalidations?.cancel());
    unawaited(messages.close());
    unawaited(_notify('detach'));
  }
}
