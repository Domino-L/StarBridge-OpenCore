import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../features/onboarding/connection_mode_port.dart';
import '../platform/bridge/bridge_client_session.dart';

import 'remote_image_transport.dart';
import 'remote_image_uri.dart';
export 'remote_image_uri.dart' show remoteImageUri;
import 'remote_image_transfer_metrics.dart';
import 'remote_image_cache_policy.dart';
import 'remote_image_disk_cache.dart';
import 'downloadable_image_cache.dart';
import 'remote_image_rereads.dart';
export 'remote_image_disk_cache.dart' show RemoteImageResourceKind;

typedef RemoteImageKey = (String, int, bool, RemoteImageResourceKind);

/// Window-owned anonymous transport. Cache is not permission: callers must
/// still provide an authorized URL. Only positive original mode facts admit IO.
final class RemoteImageLoader extends ChangeNotifier
    implements DownloadableImageCache, ImageCacheMaintenanceBarrier {
  RemoteImageLoader({
    ConnectionModeControl? mode,
    BridgeClientSession? session,
    Future<void> Function()? reconcileMode,
    DateTime Function()? now,
    HttpClient Function()? createClient,
    RemoteImageDiskCache? diskCache,
  }) : this._(
         mode: mode,
         session: session,
         reconcileMode: reconcileMode,
         now: now,
         createClient: createClient,
         diskCache: diskCache,
       );

  RemoteImageLoader._({
    this.mode,
    BridgeClientSession? session,
    this.reconcileMode,
    DateTime Function()? now,
    HttpClient Function()? createClient,
    RemoteImageTransportPool? pool,
    this.diskCache,
  }) : _session = session,
       _now = now ?? DateTime.now,
       _createClient = createClient ?? HttpClient.new,
       _pool = pool ?? RemoteImageTransportPool(createClient ?? HttpClient.new),
       _ownsPool = pool == null {
    _lastAllowed = online;
    mode?.addListener(_modeChanged);
    try {
      _removeParticipant = session?.registerConnectionModeNetworkWork(
        ConnectionModeNetworkWork(
          pause: suspendAndDrain,
          reconcile: () async {
            if (_disposed) return;
            final reconcile = reconcileMode;
            if (reconcile == null) {
              return; // No positive reread, no resumed admission.
            }
            await reconcile();
            if (_disposed) return;
            _paused = false;
            _modeChanged();
          },
        ),
      );
    } on BridgeDisconnectedException {
      _paused = true; // A late window is a local fallback, never an IO bypass.
    }
  }
  final ConnectionModeControl? mode;
  final RemoteImageDiskCache? diskCache;
  final BridgeClientSession? _session;
  final Future<void> Function()? reconcileMode;
  final _children = <RemoteImageLoader>{};
  RemoteImageLoader? _parent;
  VoidCallback? _onRetired;
  final DateTime Function() _now;
  final HttpClient Function() _createClient;
  final _entries =
      <(String, int, bool, RemoteImageResourceKind), _RemoteBytes>{};
  // Physical work remains owned even after a consumer deadline. Admission,
  // offline transitions and retirement must join actual transport exit.
  final _pending = <Future<RemoteImageFetch?>>{};
  final _eligiblePending = <Future<RemoteImageFetch?>>{};
  final _cacheWork = <Future<void>, bool>{};
  final _resourceKinds = <RemoteImageTransport, RemoteImageResourceKind>{};
  bool _maintenancePaused = false;
  int _maintenanceEpoch = 0;
  bool _eligible(RemoteImageResourceKind kind) =>
      kind == RemoteImageResourceKind.ship ||
      kind == RemoteImageResourceKind.organization;
  final _requests = <HttpClientRequest>{};
  final RemoteImageTransportPool _pool;
  final bool _ownsPool;
  final _transports = <RemoteImageTransport>{};
  Future<void>? _retirement;
  bool _notifierDisposed = false;
  VoidCallback? _removeParticipant;
  int _epoch = 0, _bytes = 0;
  late final rereads = RemoteImageRereads<RemoteImageKey>(_now);
  bool rereadDue(
    String source, {
    bool followRedirects = true,
    RemoteImageResourceKind kind = RemoteImageResourceKind.other,
  }) =>
      online && rereads.isDue((source, 4 * 1024 * 1024, followRedirects, kind));

  bool _disposed = false, _paused = false, _lastAllowed = false;
  // Derivation fences and retention facts, never account or IO permission.
  bool get retired => _disposed;
  int get readEpoch => _epoch;
  bool retains(
    String source,
    Uint8List bytes, {
    int maxBytes = 4 * 1024 * 1024,
    bool followRedirects = true,
    RemoteImageResourceKind kind = RemoteImageResourceKind.other,
  }) =>
      !_disposed &&
      identical(
        _entries[(source, maxBytes, followRedirects, kind)]?.bytes,
        bytes,
      );
  bool get online =>
      !_disposed &&
      !_paused &&
      (_parent == null || _parent!.online) &&
      _modeAllows(const {ConnectionModeState.online});

  // Official builds have no connection-mode owner: the snapshot stays the
  // default "unsupported" (scope 0) and every other online reader follows
  // allowsOnlineTraffic. Requiring "online" here kept official clients from
  // ever loading a remote image (2026-10-21). With a mode owner, its state and
  // generation still decide.
  bool _modeAllows(Set<ConnectionModeState> states) {
    final control = mode;
    if (control == null || control.busy || control.failed) return false;
    final snapshot = control.snapshot;
    if (snapshot.state == ConnectionModeState.unsupported) {
      return control.allowsOnlineTraffic &&
          (_session == null || !_session.connectionModeChanging);
    }
    return states.contains(snapshot.state) &&
        (_session == null ||
            !_session.connectionModeChanging &&
                snapshot.scope == _session.activeGeneration);
  }

  RemoteImageLoader fork() {
    if (_disposed) return RemoteImageLoader()..dispose();
    final child = RemoteImageLoader._(
      mode: mode,
      session: _session,
      reconcileMode: reconcileMode,
      now: _now,
      createClient: _createClient,
      pool: _pool,
      diskCache: diskCache,
    );
    child._parent = this;
    if (_maintenancePaused) child.beginImageMaintenance();
    _children.add(child);
    child._onRetired = () => _children.remove(child);
    return child;
  }

  void _modeChanged() {
    if (_disposed) return;
    final allowed = online;
    if (!allowed) _cancel();
    if (_lastAllowed != allowed) {
      _lastAllowed = allowed;
      notifyListeners();
    }
  }

  void _cancel() {
    _epoch++;
    for (final request in _requests.toList()) {
      request.abort();
    }
    for (final work in _transports.toList()) {
      work.cancel();
    }
    if (_ownsPool) _pool.closeIdle();
  }

  Future<void> suspendAndDrain() async {
    if (_disposed) return retireAsync();
    _paused = true;
    _cancel();
    _lastAllowed = false;
    notifyListeners();
    await Future.wait(
      _pending.toList(),
    ); // Actual exit, never an abandoned timeout wait.
    await _settleCacheWork();
  }

  Future<void> retireAsync() {
    final previous = _retirement;
    if (previous != null) return previous;
    final completion = Completer<void>();
    _retirement = completion.future;
    _disposed = true;
    _paused = true;
    rereads.reset();
    mode?.removeListener(_modeChanged);
    // Keep the receipt registered until physical IO exits. A mode transition
    // must still join an already closed window's outstanding work.
    clear();
    unawaited(() async {
      await Future.wait<void>([
        ..._pending.toList().map((future) async {
          await future;
        }),
        ..._children.toList().map((child) => child.retireAsync()),
      ]);
      await _settleCacheWork();
      if (_ownsPool) _pool.dispose();
      _removeParticipant?.call();
      _removeParticipant = null;
      _onRetired?.call();
      _onRetired = null;
      completion.complete();
    }());
    return completion.future;
  }

  Uint8List? cached(
    String source, {
    int maxBytes = 4 * 1024 * 1024,
    bool followRedirects = true,
    RemoteImageResourceKind kind = RemoteImageResourceKind.other,
  }) {
    if (_disposed) return null;
    final key = (source, maxBytes, followRedirects, kind),
        entry = _entries[key];
    final bytes = entry?.displayBytes(_now());
    if (bytes != null) _touch(key, entry!);
    return bytes;
  }

  void _touch(
    (String, int, bool, RemoteImageResourceKind) key,
    _RemoteBytes entry,
  ) {
    if (!identical(_entries[key], entry)) return;
    _entries.remove(key);
    _entries[key] = entry;
  }

  Future<Uint8List?> load(
    String source, {
    int maxBytes = 4 * 1024 * 1024,
    bool followRedirects = true,
    RemoteImageResourceKind kind = RemoteImageResourceKind.other,
  }) {
    final uri = remoteImageUri(source);
    RemoteImageTransferMetrics.present();
    if (_disposed ||
        maxBytes <= 0 ||
        maxBytes > 4 * 1024 * 1024 ||
        uri == null) {
      return Future.value(null);
    }
    final key = (source, maxBytes, followRedirects, kind),
        entry = _entries[key];
    if (_eligible(kind) && _maintenancePaused) return Future.value(null);
    if (!online) {
      if (entry?.loading == true) return entry!.future;
      if (entry != null || diskCache == null || !_canReadDisk) {
        return Future.value(
          cached(
            source,
            maxBytes: maxBytes,
            followRedirects: followRedirects,
            kind: kind,
          ),
        );
      }
    }
    if (entry != null && (entry.loading || _now().isBefore(entry.expires))) {
      _touch(key, entry);
      return entry.future;
    }
    if (_pending.length >= 64) {
      rereads.failed(key);
      return Future.value(
        cached(
          source,
          maxBytes: maxBytes,
          followRedirects: followRedirects,
          kind: kind,
        ),
      );
    }
    while (entry == null && _entries.length >= 64) {
      final oldest = _entries.entries
          .where((e) => !e.value.loading)
          .firstOrNull;
      if (oldest == null) return Future.value(null);
      _entries.remove(oldest.key);
      _bytes -= oldest.value.bytes?.length ?? 0;
    }
    final next = _RemoteBytes(_now())
      ..bytes = entry?.bytes
      ..etag = entry?.etag
      ..validatorTarget = entry?.validatorTarget
      ..policy = entry?.policy ?? const RemoteImageCachePolicy();
    _entries.remove(key);
    _entries[key] = next;
    final epoch = _epoch;
    final maintenanceEpoch = _maintenanceEpoch;
    final deadline = Completer<void>();
    final physical = _fetchWithDisk(
      source,
      uri,
      maxBytes,
      followRedirects,
      epoch,
      kind,
      maintenanceEpoch,
      next,
      previous: entry,
      onDeadline: deadline.complete,
    );
    next.future =
        Future.any<RemoteImageFetch?>([
          physical,
          deadline.future.then<RemoteImageFetch?>((_) => null),
        ]).then((result) {
          next.loading = false;
          if (_disposed ||
              epoch != _epoch ||
              (_eligible(kind) &&
                  (_maintenancePaused ||
                      maintenanceEpoch != _maintenanceEpoch)) ||
              (!online && result?.fromDisk != true) ||
              !identical(_entries[key], next)) {
            if (identical(_entries[key], next)) {
              next.expires = DateTime.fromMillisecondsSinceEpoch(0);
              next.future = Future.value(next.displayBytes(_now()));
            }
            return _disposed || !identical(_entries[key], next)
                ? null
                : next.displayBytes(_now());
          }
          if (result != null && !result.policy.retain) {
            _entries.remove(key);
            _bytes -= next.bytes?.length ?? 0;
            return result.bytes;
          }
          if (result != null && result.isDenied) {
            _bytes -= next.bytes?.length ?? 0;
            next.bytes = null;
            next.etag = null;
            next.validatorTarget = null;
            next.policy = const RemoteImageCachePolicy();
            final retry = result.freshness < const Duration(seconds: 10)
                ? result.freshness
                : const Duration(seconds: 10);
            next.expires = _now().add(retry);
            return null;
          }
          if (result != null) {
            final bytes = result.bytes!;
            _bytes += bytes.length - (next.bytes?.length ?? 0);
            next.bytes = bytes;
            next.etag = result.etag;
            next.validatorTarget = result.validatorTarget;
            next.policy = result.policy;
          }
          next.validationFailed = result == null;
          if (result == null) {
            rereads.failed(key);
          } else {
            rereads.succeeded(key);
          }
          next.expires = _now().add(
            result == null ? const Duration(seconds: 10) : result.freshness,
          );
          while (_entries.length > 64 || _bytes > 16 * 1024 * 1024) {
            final removed = _entries.remove(_entries.keys.first)!;
            _bytes -= removed.bytes?.length ?? 0;
          }
          // Explicit server revalidation requirements also apply to read failures.
          return result == null && next.policy.requiresValidation
              ? null
              : next.bytes;
        });
    _pending.add(physical);
    if (_eligible(kind)) _eligiblePending.add(physical);
    unawaited(
      physical.then((_) {
        _pending.remove(physical);
        _eligiblePending.remove(physical);
      }),
    );
    return next.future;
  }

  bool get _canReadDisk =>
      !_disposed &&
      !_paused &&
      _modeAllows(const {
        ConnectionModeState.online,
        ConnectionModeState.offline,
      });

  Future<void> _settleCacheWork({bool eligibleOnly = false}) async {
    while (_cacheWork.entries.any((e) => !eligibleOnly || e.value)) {
      await Future.wait(
        _cacheWork.entries
            .where((e) => !eligibleOnly || e.value)
            .map((e) => e.key)
            .toList(),
      );
    }
  }

  void _retainCacheWork(Future<void> work, RemoteImageResourceKind kind) {
    final settled = work.catchError((Object _) {});
    _cacheWork[settled] = _eligible(kind);
    unawaited(settled.then((_) => _cacheWork.remove(settled)));
  }

  Future<RemoteImageFetch?> _fetchWithDisk(
    String source,
    Uri uri,
    int limit,
    bool redirects,
    int epoch,
    RemoteImageResourceKind kind,
    int maintenanceEpoch,
    _RemoteBytes next, {
    _RemoteBytes? previous,
    required void Function() onDeadline,
  }) async {
    bool current() =>
        !_disposed &&
        epoch == _epoch &&
        (!_eligible(kind) ||
            !_maintenancePaused && maintenanceEpoch == _maintenanceEpoch);
    RemoteImageDiskLease? lease;
    try {
      if (diskCache != null && _canReadDisk && current()) {
        try {
          lease = await diskCache!.open(
            source,
            maxBytes: limit,
            followRedirects: redirects,
            kind: kind,
          );
        } on Object {
          /* A resource failure must not fail a valid HTTP read. */
        }
      }
      if (!current()) return null;
      final snapshot = lease?.snapshot;
      if (previous == null && snapshot != null) {
        previous = _RemoteBytes(snapshot.freshUntil)
          ..loading = false
          ..bytes = snapshot.bytes
          ..etag = snapshot.etag
          ..validatorTarget = snapshot.validatorTarget
          ..policy = RemoteImageCachePolicy(
            maxAgeSeconds: snapshot.maxAgeSeconds,
            noCache: snapshot.noCache,
            mustRevalidate: snapshot.mustRevalidate,
          );
        if (!online &&
            (snapshot.noCache ||
                snapshot.mustRevalidate &&
                    !_now().isBefore(snapshot.freshUntil))) {
          return null;
        }
        if (_now().isBefore(snapshot.freshUntil) && !snapshot.noCache ||
            !online) {
          return RemoteImageFetch.disk(snapshot, _now());
        }
        // Stale-while-revalidate follows the original server policy.
        _bytes += snapshot.bytes.length - (next.bytes?.length ?? 0);
        next
          ..bytes = snapshot.bytes
          ..etag = snapshot.etag
          ..validatorTarget = snapshot.validatorTarget
          ..policy = previous.policy
          ..expires = snapshot.freshUntil;
        if (!previous.policy.requiresValidation) notifyListeners();
      }
      if (!online || !current()) return null;
      final result = await _fetch(
        uri,
        limit,
        redirects,
        epoch,
        previous: previous,
        onDeadline: onDeadline,
        resourceCurrent: current,
        kind: kind,
      );
      if (result != null && current() && online && lease != null) {
        final accepted = lease;
        lease = null;
        final now = _now();
        // Accepted writes do not delay paint. Retirement and maintenance join
        // their physical completion, including work accepted before closing.
        _retainCacheWork(() async {
          try {
            if (!result.policy.retain || result.isDenied) {
              await accepted.reject();
            } else {
              await accepted.store(
                RemoteImageDiskSnapshot(
                  bytes: result.bytes!,
                  storedAt: now,
                  freshUntil: now.add(result.freshness),
                  maxAgeSeconds: result.policy.maxAgeSeconds
                      .clamp(0, remoteImageMaxStoredAgeSeconds)
                      .toInt(),
                  noCache: result.policy.noCache,
                  mustRevalidate: result.policy.mustRevalidate,
                  etag: result.etag,
                  validatorTarget: result.validatorTarget,
                ),
              );
            }
          } finally {
            await accepted.close();
          }
        }(), kind);
      }
      return result;
    } finally {
      try {
        await lease?.close();
      } on Object {
        /* Host expiry remains bounded. */
      }
    }
  }

  Future<RemoteImageFetch?> _fetch(
    Uri uri,
    int limit,
    bool redirects,
    int epoch, {
    _RemoteBytes? previous,
    required void Function() onDeadline,
    required bool Function() resourceCurrent,
    required RemoteImageResourceKind kind,
  }) async {
    HttpClientRequest? request;
    RemoteImageTransport? work;
    RemoteImageTransferMetrics? measurement;
    Timer? deadline;
    var expired = false;
    var reusable = false;
    final storedBytes = previous?.bytes;
    final validator = storedBytes == null ? null : previous?.etag;
    bool current() =>
        !_disposed &&
        online &&
        epoch == _epoch &&
        !expired &&
        resourceCurrent();
    try {
      if (!current()) return null;
      work = _pool.take();
      if (work == null) return null;
      _transports.add(work);
      _resourceKinds[work] = kind;
      deadline = Timer(const Duration(seconds: 10), () {
        expired = true;
        onDeadline();
        request?.abort();
        work?.cancel();
      });
      final client = await work.ready;
      if (client == null || !current()) return null;
      client.connectionTimeout = const Duration(seconds: 5);
      Future<bool> discard(Stream<List<int>> response) async {
        request?.abort();
        try {
          await response.listen(null).cancel();
          return true;
        } on Object {
          work?.cancel();
          return false;
        }
      }

      var target = uri;
      RemoteImageCachePolicy? chain;
      for (var hop = 0; hop <= 5; hop++) {
        if (!current()) return null;
        // Retain only a fingerprint, not redirected URLs or signed parameters.
        final targetKey = sha256
            .convert(utf8.encode(target.toString()))
            .toString();
        final validate =
            validator != null && previous?.validatorTarget == targetKey;
        measurement?.finish();
        measurement = RemoteImageTransferMetrics.start(hop);
        request = await client.getUrl(target);
        if (!current()) {
          request.abort();
          return null;
        }
        _requests.add(request);
        // An automatic redirect can forward an ETag to a different resource.
        request.followRedirects = false;
        if (validate) {
          request.headers.set(HttpHeaders.ifNoneMatchHeader, validator);
        }
        final response = await request.close();
        final body = measurement?.observe(response) ?? response;
        if (!current()) return null;
        if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = singleImageHeader(
            response.headers,
            HttpHeaders.locationHeader,
            2048,
          );
          chain = RemoteImageCachePolicy.read(response.headers).restrict(chain);
          final drained = await discard(body);
          _requests.remove(request);
          if (!drained || !redirects || hop == 5 || location == null) {
            return null;
          }
          final next = remoteImageUri(target.resolve(location).toString());
          if (next == null) return null;
          target = next;
          continue;
        }
        if (response.statusCode == HttpStatus.notModified) {
          if (!validate || storedBytes == null) {
            return null;
          }
          final etag = imageEtag(response.headers);
          if (etag != null &&
              opaqueImageEtag(etag) != opaqueImageEtag(validator)) {
            return null;
          }
          // A validated304 has no body. Consume its stream before returning
          // the client to the idle pool; otherwise a healthy revalidation
          // would lose connection reuse or retain an unread response.
          await for (final chunk in body) {
            if (!current() || chunk.isNotEmpty) return null;
          }
          if (!current()) return null;
          reusable = true;
          return RemoteImageFetch(
            storedBytes,
            etag ?? validator,
            RemoteImageCachePolicy.read(
              response.headers,
              previous: previous?.policy,
            ).restrict(chain),
            response.headers,
            validatorTarget: targetKey,
            redirected: hop > 0,
          );
        }
        if (const {401, 403, 404, 410}.contains(response.statusCode)) {
          final result = RemoteImageFetch.denied(
            RemoteImageCachePolicy.read(response.headers).restrict(chain),
            response.headers,
            redirected: hop > 0,
          );
          await discard(body);
          return result;
        }
        if (response.statusCode != HttpStatus.ok ||
            response.contentLength > limit) {
          await discard(body);
          return null;
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in body) {
          if (!current() || bytes.length + chunk.length > limit) {
            request.abort();
            return null;
          }
          bytes.add(chunk);
        }
        if (!current() || bytes.isEmpty) return null;
        reusable = true;
        return RemoteImageFetch(
          bytes.takeBytes(),
          imageEtag(response.headers),
          RemoteImageCachePolicy.read(response.headers).restrict(chain),
          response.headers,
          validatorTarget: targetKey,
          redirected: hop > 0,
        );
      }
      return null;
    } on Object {
      return null;
    } finally {
      deadline?.cancel();
      if (request != null) _requests.remove(request);
      work?.release(reuse: reusable);
      _transports.remove(work);
      _resourceKinds.remove(work);
      measurement?.finish();
    }
  }

  void clear() {
    _cancel();
    rereads.reset();
    _entries.clear();
    _bytes = 0;
    for (final child in _children.toList()) {
      child.clear();
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void beginImageMaintenance() {
    _maintenancePaused = true;
    _maintenanceEpoch++;
    for (final row in _resourceKinds.entries.toList()) {
      if (_eligible(row.value)) row.key.cancel();
    }
    for (final key in _entries.keys.where((k) => _eligible(k.$4)).toList()) {
      _bytes -= _entries.remove(key)?.bytes?.length ?? 0;
    }
    for (final child in _children.toList()) {
      child.beginImageMaintenance();
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void endImageMaintenance() {
    _maintenancePaused = false;
    for (final child in _children.toList()) {
      child.endImageMaintenance();
    }
  }

  @override
  Future<void> get imageMaintenanceSettled async {
    await Future.wait(_eligiblePending.toList());
    await _settleCacheWork(eligibleOnly: true);
    await Future.wait(
      _children.toList().map((child) => child.imageMaintenanceSettled),
    );
  }

  @override
  void dispose() {
    unawaited(retireAsync());
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}

final class _RemoteBytes {
  _RemoteBytes(this.expires);
  DateTime expires;
  Uint8List? bytes;
  String? etag;
  String? validatorTarget;
  RemoteImageCachePolicy policy = const RemoteImageCachePolicy();
  bool validationFailed = false;
  Uint8List? displayBytes(DateTime now) =>
      policy.requiresValidation && (validationFailed || !now.isBefore(expires))
      ? null
      : bytes;
  bool loading = true;
  late Future<Uint8List?> future;
}
