import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'marketplace_port.dart';

String? tradeAction(MarketRow r) {
  final role = r['actorRole'], state = r['deliveryStatus'];
  if (role != 'buyer' && role != 'seller') return null;
  if (state != 3 && r['transactionStatus'] != 1) return null;
  if (state == 0 && role == 'buyer' && r['creatorType'] == 0) return 'approve';
  if (state == 1 && role == 'seller') return 'ship';
  if (state == 2 && role == 'buyer') return 'receive';
  if (state == 3 &&
      r['transactionStatus'] == 2 &&
      r['${role}CommentId'] == null) {
    return 'review';
  }
  return null;
}

bool tradeCanCancel(MarketRow r) =>
    ['buyer', 'seller'].contains(r['actorRole']) &&
    r['transactionStatus'] == 1 &&
    [0, 1].contains(r['deliveryStatus']);
String tradeError(Object e, {bool writing = false}) =>
    switch (e is MarketplaceTradeError ? e.code : '') {
      'marketplace.sign_in_required' => '请先登录 SCM，再打开我的交易。',
      'marketplace.forbidden' => '交易功能暂时不可用，请稍后再试；一直这样请联系支持',
      'marketplace.state_changed' => '交易状态已变化，请查看更新后的交易单再操作。',
      'marketplace.not_participant' => '此交易不属于当前账号，请核对登录账号。',
      'marketplace.busy' => '上一项操作仍在处理中，请稍候。',
      'marketplace.trade_rejected' => '服务器未接受此操作。请核对交易状态、数量和账号限制后再试。',
      'marketplace.account_unbound' =>
        '你的 SCM 账号还没有绑定游戏账号，暂时不能交易。请先在 SCM 网站「设置 → 验证」完成绑定，再回到这里重试。',
      'marketplace.trade_time_required' =>
        '你还没有设置交易时段，SCM 暂时不允许发起交易。请在 SCM 网站「个人档案」里设置并保存交易时段，再回到这里重试；已填的内容会保留。',
      'marketplace.contact_required' =>
        '你还没有设置联系方式，SCM 暂时不允许发起交易。请在 SCM 网站「个人档案」里填写联系方式，再回到这里重试；已填的内容会保留。',
      'marketplace.account_abnormal' =>
        'SCM 显示你的游戏账号状态异常，暂时不能交易。请在 SCM 网站「设置 → 验证」重新验证游戏账号后再试。',
      'marketplace.account_banned' => '你的 SCM 账号已被永久封禁，无法交易。如有疑问请联系 SCM。',
      'marketplace.own_listing' => '这是你自己发布的挂单，不能和自己交易。',
      _ => writing ? '操作已发出，但没有收到结果。请先刷新交易单确认，不要重复提交。' : '暂时读不到交易',
    };

/// SCM account checks that reject a trade before it is created. These are
/// definite answers (nothing was written), so the draft stays and retry is safe.
const tradeAccountPrechecks = {
  'marketplace.account_unbound',
  'marketplace.trade_time_required',
  'marketplace.contact_required',
  'marketplace.account_abnormal',
  'marketplace.account_banned',
  'marketplace.own_listing',
};

/// The running app's binding; null in pure unit tests that never start one.
WidgetsBinding? marketplaceAppBinding() {
  try {
    return WidgetsBinding.instance;
  } on FlutterError {
    return null;
  }
}

/// Only server-confirmed snapshots enter rows/detail. Requests from old accounts are discarded.
class MarketplaceTradesController extends ChangeNotifier
    with WidgetsBindingObserver {
  MarketplaceTradesController(this.port);
  static const reconciliationInterval = Duration(seconds: 120);
  bool _visible = false, _foreground = true;
  String? _firstPage;
  bool get _shouldCheck => _foreground && (_visible || todo.isNotEmpty);

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
    _ensureTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _drainInvalidation();
    _ensureTimer();
    if (_foreground && _shouldCheck && _started) unawaited(checkUpdates());
  }

  static String _signature(MarketRow page) =>
      jsonEncode({'rows': page['rows'], 'total': page['total']});
  final MarketplacePort port;
  List<MarketRow> rows = [];
  MarketRow? detail;
  String? error, errorCode, writeError, writeErrorCode;
  bool writeUncertain = false;
  String get diagnostic =>
      'StarBridge marketplace; code=${errorCode == "marketplace.forbidden" || writeErrorCode == "marketplace.forbidden" ? "403" : "unavailable"}; utc=${DateTime.now().toUtc().toIso8601String()}';
  void readFailure(Object e) {
    errorCode = e is MarketplaceTradeError ? e.code : 'marketplace.read_failed';
    error = tradeError(e);
    if (_isAuthorizationFailure(e)) _blockAutomaticReads(errorCode!);
  }

  bool _isAuthorizationFailure(Object e) =>
      e is MarketplaceTradeError &&
      const {
        'marketplace.forbidden',
        'marketplace.sign_in_required',
      }.contains(e.code);

  String? _pollBlock;
  int _pollGeneration = 0;
  void _blockAutomaticReads(String reason) {
    _pollBlock = reason;
    _pollGeneration++;
    _timer?.cancel();
    _timer = null;

    _checking = false;
  }

  bool _pollIsCurrent(int epoch, int generation) =>
      !_disposed &&
      epoch == _epoch &&
      generation == _pollGeneration &&
      _pollBlock == null;

  void _ensureTimer() {
    if (!_shouldCheck) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (!_started || _disposed || _pollBlock != null || _timer != null) return;
    _timer = Timer.periodic(
      reconciliationInterval,
      (_) => unawaited(checkUpdates()),
    );
  }

  // A successful read enables a new, explicit decision; it never repeats a write.
  Future<bool> inspectUncertainWrite([String? number]) async {
    await refresh();
    if (error != null || loading) return false;
    if (number != null) await open(number);
    if (error != null) return false;
    writeUncertain = false;
    writeError = null;
    writeErrorCode = null;
    notifyListeners();
    return true;
  }

  bool loading = false, pending = false, ended = false;
  int? total;
  int _epoch = 0, _page = 0, _revision = -1, notices = 0;
  bool _disposed = false, _checking = false, _started = false;
  Timer? _timer;
  StreamSubscription<void>? _changes;
  bool _refreshQueued = false;

  void _invalidateTrades() {
    if (_disposed || !_started || _pollBlock != null) return;
    _refreshQueued = true;
    _drainInvalidation();
  }

  void _drainInvalidation() {
    if (!_refreshQueued ||
        _checking ||
        loading ||
        pending ||
        _disposed ||
        !_started ||
        !_foreground ||
        _pollBlock != null) {
      return;
    }
    _refreshQueued = false;
    unawaited(checkUpdates(force: true));
  }

  int _detailRequest = 0;
  bool get supported => port is MarketplaceTradePort;
  List<MarketRow> get todo =>
      rows.where((r) => tradeAction(r) != null).toList();
  Future<MarketRow> request(String op, [MarketRow args = const {}]) => supported
      ? (port as MarketplaceTradePort).trade(op, args)
      : Future.error(const MarketplaceTradeError('marketplace.unavailable'));
  Future<void> start() async {
    if (_started || !supported || _disposed) return;
    _started = true;
    if (marketplaceAppBinding() case final binding?) attachLifecycle(binding);
    if (port case final MarketplaceTradeEvents events) {
      _changes ??= events.tradeChanges.listen((_) => _invalidateTrades());
    }
    final epoch = _epoch;
    await refresh();
    if (_disposed || !_started || epoch != _epoch) return;
    _ensureTimer();
    _drainInvalidation();
  }

  Future<void> checkUpdates({bool force = false}) async {
    if (_checking ||
        loading ||
        _disposed ||
        pending ||
        _pollBlock != null ||
        !_foreground ||
        !force && !_shouldCheck) {
      return;
    }
    _checking = true;
    final epoch = _epoch, generation = _pollGeneration;
    try {
      // Host revision is local. A remote first-page snapshot also catches
      // lost SCM pushes; an unchanged snapshot never rereads loaded pages/detail.
      MarketRow? first;
      var changed = false;
      if (!force) {
        final r = await request('revision');
        if (!_pollIsCurrent(epoch, generation) || !_shouldCheck) return;
        final revision = r['revision'] as int;
        changed = _revision >= 0 && _revision != revision;
        _revision = revision;
        first = await request('list', {'page': 1});
        if (!_pollIsCurrent(epoch, generation) || !_shouldCheck) return;
        changed = changed || _firstPage != _signature(first);
      }
      if (force || changed) {
        if (changed) notices++;
        await _refresh(automatic: true, firstPage: first);
        if (!_pollIsCurrent(epoch, generation)) return;
        if (!_foreground) return;
        final number = detail?['transactionNumber'];
        if (number is String) await open(number);
        if (!_pollIsCurrent(epoch, generation)) return;
      }
    } on Object catch (e) {
      if (_pollIsCurrent(epoch, generation) && _isAuthorizationFailure(e)) {
        readFailure(e);
        notifyListeners();
      }
      // Other revision failures retain the last confirmed data.
    } finally {
      if (epoch == _epoch && generation == _pollGeneration) _checking = false;
      _drainInvalidation();
    }
  }

  Future<void> refresh({bool more = false}) => _refresh(more: more);

  Future<void> _refresh({
    bool more = false,
    bool automatic = false,
    MarketRow? firstPage,
  }) async {
    if (loading ||
        _disposed ||
        !supported ||
        more && ended ||
        _pollBlock != null && (automatic || more)) {
      return;
    }
    final epoch = _epoch, generation = _pollGeneration;
    final authorizationProbe = _pollBlock != null;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final nextPage = more ? _page + 1 : 1;
      // A manual retry of an authorization denial probes one page only.
      // Further pages remain explicit pagination after authorization succeeds.
      final lastPage = authorizationProbe
          ? 1
          : more
          ? nextPage
          : (_page < 1 ? 1 : _page);
      final next = <MarketRow>[];
      int? nextTotal;
      var loadedPage = nextPage;
      var exhausted = false;
      for (var page = nextPage; page <= lastPage; page++) {
        if (automatic && !_foreground) return;
        final result = page == 1 && firstPage != null
            ? firstPage
            : await request('list', {'page': page});
        if (_disposed || epoch != _epoch || generation != _pollGeneration) {
          return;
        }
        if (page == 1) _firstPage = _signature(result);
        final batch = marketRows(result['rows']);
        next.addAll(batch);
        nextTotal = result['total'] as int?;
        loadedPage = page;
        exhausted =
            batch.isEmpty ||
            nextTotal != null &&
                (more ? rows.length : 0) + next.length >= nextTotal;
        if (exhausted) break;
      }
      final combined = more ? [...rows, ...next] : next;
      rows = {for (final row in combined) row['transactionNumber']: row}.values
          .toList();
      total = nextTotal;
      _page = loadedPage;
      ended = exhausted;
      error = null;
      errorCode = null;
      if (authorizationProbe) {
        _pollBlock = null;

        _revision = -1;
        _firstPage = null;
      }
      _ensureTimer();
    } on Object catch (e) {
      if (!_disposed && epoch == _epoch && generation == _pollGeneration) {
        readFailure(e);
      }
    } finally {
      if (!_disposed && epoch == _epoch) {
        loading = false;
        notifyListeners();
        _drainInvalidation();
      }
    }
  }

  /// A trade reminder's opaque ref (CX-T23) waiting for 我的交易 to show its
  /// sheet. The page takes it once; a newer reminder replaces an older one.
  String? pendingRef;

  void requestOpen(String ref) {
    pendingRef = ref;
    notifyListeners();
  }

  String? takePendingRef() {
    final ref = pendingRef;
    pendingRef = null;
    return ref;
  }

  /// Reads one transaction by a reminder's ref. The Host resolves the ref in
  /// this account only; the answer carries the real transactionNumber that
  /// every later action uses. Null when the ref expired or the read failed.
  Future<MarketRow?> openRef(String ref) async {
    final epoch = _epoch, generation = _pollGeneration;
    final requestId = ++_detailRequest;
    try {
      final next = await request('detail', {'transactionRef': ref});
      if (_disposed ||
          epoch != _epoch ||
          generation != _pollGeneration ||
          requestId != _detailRequest ||
          next['transactionNumber'] is! String) {
        return null;
      }
      detail = next;
      error = null;
      errorCode = null;
      notifyListeners();
      return next;
    } on Object catch (e) {
      if (!_disposed &&
          epoch == _epoch &&
          generation == _pollGeneration &&
          requestId == _detailRequest) {
        readFailure(e);
        notifyListeners();
      }
      return null;
    }
  }

  Future<void> open(String number) async {
    final epoch = _epoch, generation = _pollGeneration;
    final requestId = ++_detailRequest;
    try {
      final next = await request('detail', {'transactionNumber': number});
      if (!_disposed &&
          epoch == _epoch &&
          generation == _pollGeneration &&
          requestId == _detailRequest) {
        detail = next;
        error = null;
        errorCode = null;
        notifyListeners();
      }
    } on Object catch (e) {
      if (!_disposed &&
          epoch == _epoch &&
          generation == _pollGeneration &&
          requestId == _detailRequest) {
        readFailure(e);
        notifyListeners();
      }
    }
  }

  Future<String?> submit(String op, MarketRow args) async {
    if (pending || _disposed || writeUncertain) return null;
    final epoch = _epoch, generation = _pollGeneration;
    pending = true;
    writeError = null;
    writeErrorCode = null;
    error = null;
    notifyListeners();
    try {
      final result = await request(op, args);
      if (_disposed || epoch != _epoch) return null;
      final number =
          result['transactionNumber'] as String? ??
          args['transactionNumber'] as String?;
      // Deliver the confirmed write result, but never use its automatic
      // follow-up reads to recover an authorization-blocked generation.
      if (!_pollIsCurrent(epoch, generation)) return number;
      await _refresh(automatic: true);
      if (_disposed || epoch != _epoch) return null;
      if (!_pollIsCurrent(epoch, generation)) return number;
      if (number != null) await open(number);
      if (_disposed || epoch != _epoch) return null;
      return number;
    } on Object catch (e) {
      if (!_disposed && epoch == _epoch) {
        writeErrorCode = e is MarketplaceTradeError
            ? e.code
            : 'marketplace.unknown';
        writeUncertain = !const {
          'marketplace.sign_in_required',
          'marketplace.forbidden',
          'marketplace.state_changed',
          'marketplace.not_participant',
          'marketplace.busy',
          ...tradeAccountPrechecks,
          'marketplace.trade_rejected',
        }.contains(writeErrorCode);
        writeError = tradeError(e, writing: true);
        errorCode = writeErrorCode;
        error = writeError;
        notifyListeners();
      }
      return null;
    } finally {
      if (!_disposed && epoch == _epoch) {
        pending = false;
        notifyListeners();
        _drainInvalidation();
      }
    }
  }

  void reset() {
    unawaited(_changes?.cancel());
    _changes = null;
    _refreshQueued = false;
    _epoch++;
    _pollGeneration++;
    _pollBlock = null;
    _timer?.cancel();
    _timer = null;
    _started = false;
    _checking = false;

    _detailRequest++;
    rows = [];
    detail = null;
    errorCode = null;
    writeErrorCode = null;
    writeError = null;
    writeUncertain = false;
    error = null;
    pending = false;
    loading = false;
    ended = false;
    total = null;
    _page = 0;
    _revision = -1;
    _firstPage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _lifecycle?.removeObserver(this);
    unawaited(_changes?.cancel());
    _changes = null;
    _refreshQueued = false;
    _disposed = true;
    _epoch++;
    _pollGeneration++;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

// SCM stores unit price in amount; its web timeline shows amount * number.
// Preserve missing values. Barter has no monetary total.
num? tradeItemsTotal(MarketRow row) {
  if (row['displayType'] == 3 || row['orderType'] == 2) return null;
  final unit = marketNumber(row['amount']),
      quantity = marketNumber(row['number']);
  if (unit == null || quantity == null || quantity <= 0) return null;
  final total = unit * quantity;
  return total.isFinite ? total : null;
}
