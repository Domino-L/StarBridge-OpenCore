import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'marketplace_port.dart';
import 'marketplace_trades_controller.dart' show marketplaceAppBinding;

/// A message this client sent and is still waiting on, or one SCM refused or
/// never answered. Never resent automatically; the user decides.
/// An order to send along with the next message (交易单「私信对方」, or the
/// composer's 附上订单); the receiver sees SCM's order card.
class MarketChatAttachment {
  const MarketChatAttachment(this.orderId, this.label);
  final int orderId;
  final String label;
}

class MarketChatOutgoing {
  MarketChatOutgoing(this.content, {this.orderId}) : clientMessageId = _newId();
  final String content;
  final int? orderId;

  /// SCM's key for this one message: a manual resend keeps it, so SCM
  /// stores the message once however often it is sent (SCM spec §6.2).
  final String clientMessageId;
  String status = 'sending'; // sending | rejected | uncertain
  String? reason;

  static final _random = Random.secure();
  static String _newId() => [
    for (var i = 0; i < 16; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// SCM trade messages (0.7.2 G9): the conversation list, one open thread with
/// older pages, sends and read marks. Live pushes carry the message and are
/// merged at once (no round trip, user decision 2026-10-21 "无延迟同步");
/// REST reads only reconcile, merging by message id so nothing flickers back.
class MarketplaceChatController extends ChangeNotifier
    with WidgetsBindingObserver {
  MarketplaceChatController(this.port) {
    _pushes = port.chatPushes.listen(_onPush);
  }
  final MarketplaceChatPort port;
  late final StreamSubscription<MarketRow> _pushes;
  Timer? _reconcile, _periodic;
  static const reconciliationInterval = Duration(seconds: 120);
  static const maxCatchUpPages = 10;
  bool _visible = false, _foreground = true, _autoBlocked = false;
  bool _refreshing = false, _resyncQueued = false, _catchUpQueued = false;
  final _anchors = <String, int>{};
  int _threadGeneration = 0;
  int? _gapBefore, _gapAnchor, _queuedAnchor;
  int? get gapStartId => _gapBefore;
  bool get hasGap => _gapBefore != null;

  WidgetsBinding? _lifecycle;
  void attachLifecycle(WidgetsBinding binding) {
    if (identical(_lifecycle, binding)) return;
    _lifecycle?.removeObserver(this);
    _lifecycle = binding;
    binding.addObserver(this);
    final state = binding.lifecycleState;
    if (state != null) didChangeAppLifecycleState(state);
  }

  void setVisible(bool value) {
    attachLifecycle(WidgetsBinding.instance);
    _visible = value;
    _ensurePeriodic();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _ensurePeriodic();
    if (_foreground && _visible) unawaited(_refresh());
  }

  void _ensurePeriodic() {
    if (_disposed || !_visible || !_foreground || _autoBlocked) {
      _periodic?.cancel();
      _periodic = null;
      return;
    }
    _periodic ??= Timer.periodic(
      reconciliationInterval,
      (_) {
        if (_visible && _foreground) unawaited(_refresh(catchUp: false));
      },
    );
  }

  void _authorizationFailure(Object e) {
    if (e is MarketplaceTradeError &&
        const {
          'marketplace.forbidden',
          'marketplace.sign_in_required',
          'marketplace.reauthorize_required',
        }.contains(e.code)) {
      _autoBlocked = true;
      _reconcile?.cancel();
      _ensurePeriodic();
    }
  }

  static int _compare(MarketRow a, MarketRow b) {
    int? time(MarketRow row) {
      final value = row['time'];
      // Host preserves JSON epoch milliseconds or ISO text from SCM.
      return value is num && value.isFinite
          ? value.toInt() * 1000
          : DateTime.tryParse('$value')?.microsecondsSinceEpoch;
    }

    final at = time(a), bt = time(b);
    final order = at != null && bt != null ? at.compareTo(bt) : 0;
    return order == 0 ? _id(a).compareTo(_id(b)) : order;
  }

  bool _pushedDuringLoad = false;

  /// SCM's own unread total, pushed live; null until the first push.
  int? serverUnread;

  List<MarketRow> conversations = const [];
  bool loading = false, failed = false;
  String? error;

  String? openRef;
  MarketChatAttachment? attachment;

  /// Set by the trading hall: recent trades for 附上订单, and 在 SCM 打开.
  List<MarketChatAttachment> Function()? recentOrders;
  VoidCallback? openScm;

  /// A conversation another surface asked to show (交易单「私信对方」,
  /// 订单详情「联系卖家」). The messages page switches to 交易消息 when this
  /// changes and the trade-chat view opens [pendingRef] once.
  final requests = ValueNotifier<int>(0);
  String? pendingRef;
  List<MarketRow> thread = const [];
  bool threadLoading = false, threadFailed = false, threadEnd = false;
  final outgoing = <MarketChatOutgoing>[];
  bool _disposed = false;
  int _epoch = 0;

  bool get supported => port.chatSupported;

  int get unread =>
      serverUnread ??
      conversations.fold(
        0,
        (sum, row) => sum + ((row['unread'] as num?)?.toInt() ?? 0),
      );

  static int _id(MarketRow message) => (message['id'] as num?)?.toInt() ?? 0;

  /// SCM's limit on one message, in UTF-16 code units like SCM and the Host.
  static const maxLength = 150;

  /// Message ids already shown, newest last (bounded, as SCM's Web does):
  /// a repeated event changes nothing a second time (SCM spec §6.3).
  final _seen = <int>{};
  bool _remember(int id) {
    if (id <= 0) return true;
    if (!_seen.add(id)) return false;
    if (_seen.length > 1000) _seen.remove(_seen.first);
    return true;
  }

  void _onPush(MarketRow push) {
    if (_disposed) return;
    switch (push['kind']) {
      case 'message':
        final reference = push['ref'];
        final message = push['message'];
        if (reference is! String || message is! Map) return;
        _merge(reference, message.cast<String, Object?>(), push['name']);
      case 'unread':
        serverUnread = (push['count'] as num?)?.toInt();
        _notify();
      default:
        unawaited(_refresh());
    }
  }

  /// Shows one message now: in the open thread and as the conversation's
  /// latest line, moved to the top. Each server message counts once; my own
  /// (sent here or synced from another session) never adds unread, and a
  /// pending send is confirmed only by its own reply (SCM spec §6.3).
  void _merge(String reference, MarketRow message, Object? name) {
    final id = _id(message);
    final open = reference == openRef;
    if (open && thread.any((m) => _id(m) == id && id > 0)) return;
    if (!_remember(id)) return;
    final mine = message['mine'] == true;
    if (open) {
      thread = [...thread, message]..sort(_compare);
      if (!hasGap && !threadLoading && !_catchUpQueued) {
        _anchors[reference] = thread.map(_id).reduce(max);
      }
    }
    final index = conversations.indexWhere((row) => row['ref'] == reference);
    final previous = index >= 0 ? conversations[index] : null;
    final unreadBefore = (previous?['unread'] as num?)?.toInt() ?? 0;
    final row = <String, Object?>{
      ...?previous,
      'ref': reference,
      if (previous == null) 'name': name,
      'lastMessage': message['content'],
      'lastTime': message['time'],
      'unread': open
          ? 0
          : (mine || message['read'] == true ? unreadBefore : unreadBefore + 1),
    };
    conversations = [
      row,
      for (var i = 0; i < conversations.length; i++)
        if (i != index) conversations[i],
    ];
    if (loading) _pushedDuringLoad = true;
    // A new conversation needs SCM's full row (ban history, presence, …).
    if (previous == null) _scheduleReconcile();
    _notify();
  }

  void _scheduleReconcile() {
    _reconcile?.cancel();
    _reconcile = Timer(const Duration(seconds: 2), () {
      if (!_disposed && !_autoBlocked && _foreground) {
        unawaited(loadConversations(automatic: true));
      }
    });
  }

  MarketRow? get openConversation {
    for (final row in conversations) {
      if (row['ref'] == openRef) return row;
    }
    return null;
  }

  /// 在 SCM 打开: the open conversation on the SCM site (the Host turns the
  /// reference into SCM's own link). A Host without that answers
  /// invalid_request; then the SCM home page opens as before.
  Future<void> openInScm() async {
    final reference = openRef;
    if (reference == null) return openScm?.call();
    try {
      await port.chat('openScm', {'ref': reference});
    } on MarketplaceTradeError catch (e) {
      if (e.code == 'marketplace.invalid_request') openScm?.call();
    } on Object {
      // The browser opens or it does not; nothing to show here.
    }
  }

  /// The open conversation's block when this client can lift it here
  /// (the Host sends blockRef only while I block the member).
  String? get blockRef {
    final records = port;
    if (records is! MarketplaceRecordsPort ||
        !(records as MarketplaceRecordsPort).recordsSupported) {
      return null;
    }
    return switch (openConversation?['blockRef']) {
      final String ref when ref.isNotEmpty => ref,
      _ => null,
    };
  }

  bool unblocking = false;

  /// 解除拉黑 from the conversation; true when SCM confirmed. The list is read
  /// again either way, so the banner shows SCM's state.
  Future<bool> unblock() async {
    final reference = blockRef;
    if (reference == null || unblocking) return false;
    unblocking = true;
    _notify();
    var confirmed = false;
    try {
      final data = await (port as MarketplaceRecordsPort).records('unblock', {
        'ref': reference,
      });
      confirmed = data['confirmed'] == true;
    } on Object {
      // The read below shows the real state.
    } finally {
      unblocking = false;
      if (!_disposed) await loadConversations();
    }
    return confirmed;
  }

  /// [unread] as a listenable, for the 交易消息 group and other badges.
  final unreadValue = ValueNotifier<int>(0);

  void _notify() {
    if (_disposed) return;
    unreadValue.value = unread;
    notifyListeners();
  }

  static List<MarketRow> _rows(MarketRow data) => [
    for (final row in data['rows'] as List? ?? const [])
      if (row is Map) row.cast<String, Object?>(),
  ];

  /// SCM's unread total, for the sidebar before any push arrived.
  Future<void> loadUnread() async {
    if (marketplaceAppBinding() case final binding?) attachLifecycle(binding);
    final epoch = _epoch;
    try {
      final data = await port.chat('unread');
      if (_disposed || epoch != _epoch) return;
      serverUnread = (data['count'] as num?)?.toInt();
      _notify();
    } on Object catch (e) {
      if (_disposed || epoch != _epoch) return;
      _authorizationFailure(e);
      // The next push or read corrects it.
    }
  }

  Future<void> loadConversations({bool automatic = false}) async {
    if (automatic && _autoBlocked) return;
    if (loading) return;
    final epoch = _epoch;
    loading = true;
    failed = false;
    _pushedDuringLoad = false;
    _notify();
    try {
      final data = await port.chat('conversations');
      if (_disposed || epoch != _epoch) return;
      conversations = _rows(data);
      if (!automatic) _autoBlocked = false;
      _ensurePeriodic();
      error = null;
      if (_pushedDuringLoad) _scheduleReconcile();
    } on MarketplaceTradeError catch (e) {
      if (_disposed || epoch != _epoch) return;
      failed = true;
      error = e.code;
      _authorizationFailure(e);
    } on Object {
      if (_disposed || epoch != _epoch) return;
      failed = true;
    } finally {
      if (!_disposed && epoch == _epoch) {
        loading = false;
        _notify();
      }
    }
  }

  /// Opens a thread: newest page, SCM read mark, and live focus so SCM marks
  /// further messages from this member read while it stays open.
  Future<void> open(String reference) async {
    _threadGeneration++;
    threadLoading = false;
    _catchUpQueued = false;
    _gapBefore = _gapAnchor = _queuedAnchor = null;
    _autoBlocked = false; // Explicit open permits one new authorization probe.
    openRef = reference;
    thread = const [];
    threadEnd = false;
    outgoing.clear();
    _notify();
    final generation = _threadGeneration;
    await _loadThread(reconcile: true);
    if (openRef != reference ||
        _disposed ||
        generation != _threadGeneration ||
        _autoBlocked) {
      return;
    }
    _ensurePeriodic();
    unawaited(_quiet(() => port.chat('focus', {'ref': reference})));
    final row = openConversation;
    if ((row?['unread'] as num? ?? 0) > 0) {
      await _quiet(() => port.chat('read', {'ref': reference}));
      if (!_disposed && !_autoBlocked && _foreground) {
        unawaited(loadConversations(automatic: true));
      }
    }
  }

  Future<void> close() async {
    if (openRef == null) return;
    _threadGeneration++;
    threadLoading = false;
    _catchUpQueued = false;
    _gapBefore = _gapAnchor = _queuedAnchor = null;
    openRef = null;
    thread = const [];
    outgoing.clear();
    _notify();
    await _quiet(() => port.chat('focus'));
  }

  Future<void> loadOlder() async {
    if (threadLoading || thread.isEmpty || threadEnd && !hasGap) return;
    await _loadThread(before: _gapBefore ?? thread.map(_id).reduce(min));
  }

  Future<void> _loadThread({
    int? before,
    bool reconcile = false,
    int? anchorOverride,
  }) async {
    final reference = openRef;
    if (reference == null || _disposed || _autoBlocked) return;
    if (threadLoading) {
      if (reconcile) {
        _catchUpQueued = true;
        final anchor = anchorOverride ?? _gapAnchor ?? _anchors[reference];
        if (anchor != null) {
          _queuedAnchor = min(_queuedAnchor ?? anchor, anchor);
        }
      }
      return;
    }
    final epoch = _epoch, generation = _threadGeneration;
    bool current() =>
        !_disposed &&
        epoch == _epoch &&
        generation == _threadGeneration &&
        openRef == reference;
    // Keep the pre-reconnect anchor fixed while live messages arrive.
    final anchor = reconcile
        ? (anchorOverride ?? _gapAnchor ?? _queuedAnchor ?? _anchors[reference])
        : _gapAnchor;
    var cursor = before;
    _catchUpQueued = false;
    _queuedAnchor = null;
    threadLoading = true;
    threadFailed = false;
    _notify();
    try {
      final pages = reconcile && anchor != null ? maxCatchUpPages : 1;
      for (var i = 0; i < pages; i++) {
        if (reconcile && !_foreground) {
          _catchUpQueued = true;
          _queuedAnchor = anchor;
          return;
        }
        final data = await port.chat('history', {
          'ref': reference,
          'before': ?cursor,
        });
        if (!current()) return;
        final page = _rows(data).where((m) => _id(m) > 0).take(20).toList();
        final byId = <int, MarketRow>{
          for (final m in page) _id(m): m,
          for (final m in thread) _id(m): m,
        };
        for (final m in page) {
          _remember(_id(m));
        }
        thread = byId.values.toList()..sort(_compare);
        final joined = anchor != null && page.any((m) => _id(m) == anchor);
        final exhausted = page.length < 20;
        if (joined || exhausted || anchor == null) {
          if (reconcile || hasGap) _gapBefore = _gapAnchor = null;
          if (exhausted) threadEnd = true;
          if (thread.isNotEmpty) {
            _anchors[reference] = thread.map(_id).reduce(max);
          }
          break;
        }
        final next = page.map(_id).reduce(min);
        // A non-advancing cursor must leave an honest, manually recoverable gap.
        _gapBefore = next;
        _gapAnchor = anchor;
        threadEnd = false;
        if (cursor != null && next >= cursor) break;
        cursor = next;
      }
    } on Object catch (e) {
      if (!current()) return;
      _authorizationFailure(e);
      threadFailed = true;
      // Preserve a continuation if any pages arrived before the failure.
      if (anchor != null) {
        _gapAnchor = anchor;
        _gapBefore ??= cursor;
      }
    } finally {
      if (current()) {
        threadLoading = false;
        _notify();
        if (_catchUpQueued && _foreground) {
          _catchUpQueued = false;
          final anchor = _queuedAnchor;
          _queuedAnchor = null;
          unawaited(_loadThread(reconcile: true, anchorOverride: anchor));
        }
      }
    }
  }

  /// Sends once. A confirmed message shows from the reply (or its push, if
  /// that comes first); refused
  /// and unanswered ones stay visible with their state.
  /// Asks the messages page to show [reference], optionally with an order
  /// already attached to the composer.
  void requestOpen(String reference, {MarketChatAttachment? attach}) {
    pendingRef = reference;
    if (attach != null) attachment = attach;
    requests.value++;
  }

  /// 订单详情「联系卖家」: the Host finds the seller from the order and opens
  /// (or creates) the conversation. False when SCM refused or is unreachable.
  Future<bool> openOrder(
    String orderNumber, {
    MarketChatAttachment? attach,
  }) async {
    try {
      final row = await port.chat('openOrder', {'orderNumber': orderNumber});
      final reference = row['ref'];
      if (_disposed || reference is! String) return false;
      if (!conversations.any((c) => c['ref'] == reference)) {
        conversations = [row, ...conversations];
        _notify();
      }
      requestOpen(reference, attach: attach);
      return true;
    } on Object {
      return false;
    }
  }

  /// Shows 交易消息 without opening a conversation (通知中心 → 交易私信):
  /// an empty pending reference switches the group and opens nothing.
  void requestShow() => requestOpen('');

  /// The pending request, once.
  String? takeRequest() {
    final reference = pendingRef;
    pendingRef = null;
    return reference;
  }

  Future<void> send(String text, {int? orderId}) async {
    final reference = openRef;
    final content = text.trim();
    if (reference == null || content.isEmpty || content.length > maxLength) {
      return;
    }
    if (orderId == null && attachment != null) {
      orderId = attachment!.orderId;
      attachment = null;
    }
    final pending = MarketChatOutgoing(content, orderId: orderId);
    outgoing.add(pending);
    await _deliver(reference, pending);
  }

  /// Sends a refused or unanswered message again, as the same message.
  Future<void> resend(MarketChatOutgoing pending) async {
    final reference = openRef;
    if (reference == null ||
        pending.status == 'sending' ||
        !outgoing.contains(pending)) {
      return;
    }
    pending
      ..status = 'sending'
      ..reason = null;
    await _deliver(reference, pending);
  }

  Future<void> _deliver(String reference, MarketChatOutgoing pending) async {
    _notify();
    MarketRow? data;
    try {
      data = await port.chat('send', {
        'ref': reference,
        'content': pending.content,
        'orderId': ?pending.orderId,
        'clientMessageId': pending.clientMessageId,
      });
      pending
        ..status = data['status'] as String? ?? 'uncertain'
        ..reason = data['reason'] as String?;
    } on MarketplaceTradeError catch (e) {
      pending
        ..status = 'rejected'
        ..reason = e.code;
    } on Object {
      pending.status = 'uncertain';
    }
    if (_disposed) return;
    if (pending.status == 'sent') {
      outgoing.remove(pending);
      final message = data?['message'];
      if (message is Map) {
        _merge(reference, message.cast<String, Object?>(), null);
      }
    }
    _notify();
  }

  void dismiss(MarketChatOutgoing message) {
    if (outgoing.remove(message)) _notify();
  }

  /// A resync repairs only the open thread. Closed threads retain their anchor
  /// and catch up on their next explicit open, without background history reads.
  Future<void> _refresh({bool catchUp = true}) async {
    if (_disposed || _autoBlocked || !_foreground) return;
    if (_refreshing) {
      _resyncQueued = _resyncQueued || catchUp;
      return;
    }
    final epoch = _epoch;
    _refreshing = true;
    final reference = openRef, generation = _threadGeneration;
    final anchor = _gapAnchor ?? _anchors[reference];
    try {
      if (loading) _pushedDuringLoad = true;
      // Sequential admission: a 403 stops the rest of this automatic batch.
      bool stop() =>
          _disposed ||
          epoch != _epoch ||
          _autoBlocked ||
          !_foreground ||
          !catchUp && !_visible;
      await loadConversations(automatic: true);
      if (stop()) return;
      await loadUnread();
      if (stop()) return;
      if (catchUp &&
          openRef == reference &&
          generation == _threadGeneration &&
          reference != null) {
        await _loadThread(reconcile: true, anchorOverride: anchor);
      }
    } finally {
      if (epoch == _epoch) {
        _refreshing = false;
        if (_resyncQueued) {
          _resyncQueued = false;
          unawaited(_refresh());
        }
      }
    }
  }

  static Future<void> _quiet(Future<Object?> Function() work) async {
    try {
      await work();
    } on Object {
      // Read marks and focus are best effort; the next read shows the truth.
    }
  }

  /// A new account starts empty.
  void reset() {
    _epoch++;
    _threadGeneration++;
    _anchors.clear();
    _gapBefore = _gapAnchor = _queuedAnchor = null;
    _autoBlocked = _refreshing = _resyncQueued = _catchUpQueued = false;
    _periodic?.cancel();
    _periodic = null;
    conversations = const [];
    loading = failed = false;
    error = null;
    openRef = null;
    thread = const [];
    threadLoading = threadFailed = threadEnd = false;
    outgoing.clear();
    _seen.clear();
    serverUnread = null;
    attachment = null;
    pendingRef = null;
    unblocking = false;
    _reconcile?.cancel();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle?.removeObserver(this);
    _periodic?.cancel();
    _reconcile?.cancel();
    requests.dispose();
    unreadValue.dispose();
    unawaited(_pushes.cancel());
    super.dispose();
  }
}
