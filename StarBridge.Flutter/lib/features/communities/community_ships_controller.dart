import 'dart:async';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_ships_port.dart';
import 'community_workspace_port.dart';
import 'community_avatar_cache.dart';

/// One coherent server-filtered page; never filters only the rows already loaded.
final class CommunityShipsController extends ChangeNotifier {
  CommunityShipsController(
    this.port,
    this.targetRef, {
    CommunityShipQuery? initialQuery,
    this.mediaPort,
    CommunityAvatarCache? avatars,
    DateTime Function()? now,
  }) : query = initialQuery ?? CommunityShipQuery(),
       _now = now ?? DateTime.now,
       avatars = avatars ?? CommunityAvatarCache(),
       _ownsAvatars = avatars == null {
    _subscription = port.invalidations.listen((_) => invalidate());
    final refreshPort = port;
    if (refreshPort is CommunityShipsRefreshPort) {
      _publicationSubscription = (refreshPort as CommunityShipsRefreshPort)
          .shipRefreshes
          .listen((_) {
            // This controller can outlive its panel. Retain rows, but never treat a
            // pre-publication read as fresh when the user returns to an organization.
            _publicationVersion++;
            _lastSuccessfulRead = null;
          });
    }
  }
  final CommunityShipsPort port;
  final CommunityWorkspacePort? mediaPort;
  final String targetRef;
  final DateTime Function() _now;
  DateTime? _lastSuccessfulRead;
  Future<void> enter() async {
    final age = _lastSuccessfulRead == null
        ? null
        : _now().difference(_lastSuccessfulRead!);
    if (page != null &&
        error == null &&
        age != null &&
        !age.isNegative &&
        age < const Duration(seconds: 10)) {
      return;
    }
    await refreshVisible();
  }

  final CommunityAvatarCache avatars;
  final bool _ownsAvatars;
  final _avatarVersions = <String, String?>{};
  late final StreamSubscription<void> _subscription;
  StreamSubscription<void>? _publicationSubscription;
  int _publicationVersion = 0;
  CommunityShipQuery query;
  CommunityShipsPage? page;
  String? error;
  bool busy = false, invalidated = false;
  bool refreshing = false;
  bool mediaFailed = false;
  final Map<String, Uint8List> _avatars = {};
  final Set<String> _pendingAvatars = {};
  final Set<String> _failedAvatars = {};
  bool avatarLoading(String reference) => _pendingAvatars.contains(reference);
  Uint8List? avatar(String reference) => _avatars[reference];
  int _epoch = 0;
  int? _mediaEpoch;
  bool _closed = false;

  void invalidate() {
    if (_closed) return;
    _epoch++;
    page = null;
    _avatars.clear();
    _avatarVersions.clear();
    avatars.clear();
    _pendingAvatars.clear();
    _failedAvatars.clear();
    busy = false;
    refreshing = false;
    mediaFailed = false;
    invalidated = true;
    error = 'identityUnavailable';
    notifyListeners();
  }

  Future<void> load({
    CommunityShipQuery? selection,
    int offset = 0,
    String? revision,
  }) async {
    if (_closed || invalidated) return;
    final keepPage =
        page != null &&
        (selection == null || selection == page!.query) &&
        offset == page!.offset;
    if (busy && keepPage) return;
    final epoch = ++_epoch;
    final publicationVersion = _publicationVersion;
    refreshing = false;
    query = selection ?? query;
    final expectedQuery = query;
    if (!keepPage) {
      page = null;
      _avatars.clear();
    }
    _pendingAvatars.clear();
    mediaFailed = false;
    error = null;
    busy = true;
    notifyListeners();
    try {
      final result = await port.readShips(
        targetRef,
        offset: offset,
        revision: revision,
        query: expectedQuery,
      );
      if (_closed || epoch != _epoch) return;
      if (result.targetRef != targetRef ||
          result.offset != offset ||
          result.query != expectedQuery ||
          revision != null && result.revision != revision) {
        throw const CommunityFailure('dataInvalid');
      }
      page = result;
      _lastSuccessfulRead = publicationVersion == _publicationVersion
          ? _now()
          : null;
      busy = false;
      notifyListeners();
      await _loadAvatars(result, epoch);
    } catch (e) {
      if (_closed || epoch != _epoch) return;
      error = e is CommunityFailure ? e.code : 'unavailable';
      if (error != 'unavailable') {
        page = null;
        _avatars.clear();
      }
      _pendingAvatars.clear();
      if (const {
        'identityUnavailable',
        'notAllowed',
        'refreshRequired',
      }.contains(error)) {
        invalidated = true;
        avatars.clear();
      }
    }
    if (_closed || epoch != _epoch) return;
    busy = false;
    notifyListeners();
  }

  Future<void> next() async {
    final current = page;
    if (busy || current?.next == null) return;
    await load(offset: current!.next!, revision: current.revision);
  }

  /// Reauthorize without blanking unchanged rows or moving to the first page.
  /// Transport failures retain explicitly stale rows until the next visible tick.
  /// Permission, account, reference and integrity failures still clear them.
  Future<void> refreshVisible() async {
    final previous = page;
    if (_closed ||
        invalidated ||
        busy ||
        refreshing ||
        _mediaEpoch == _epoch ||
        error != null && error != 'unavailable' ||
        previous == null) {
      return;
    }
    final epoch = ++_epoch;
    final publicationVersion = _publicationVersion;
    final expectedQuery = query;
    refreshing = true;
    error = null;
    bool current() => !_closed && epoch == _epoch;
    void validate(CommunityShipsPage value, int offset, [String? revision]) {
      if (value.targetRef != targetRef ||
          value.query != expectedQuery ||
          value.offset != offset ||
          revision != null && value.revision != revision) {
        throw const CommunityFailure('dataInvalid');
      }
    }

    try {
      final first = await port.readShips(targetRef, query: expectedQuery);
      if (!current()) return;
      validate(first, 0);
      _lastSuccessfulRead = publicationVersion == _publicationVersion
          ? _now()
          : null;
      if (first.revision == previous.revision) {
        if (first.totalCount != previous.totalCount ||
            first.matchedCount != previous.matchedCount) {
          throw const CommunityFailure('dataInvalid');
        }
        return;
      }
      final lastOffset = first.matchedCount == 0
          ? 0
          : ((first.matchedCount - 1) ~/ 20) * 20;
      final offset = previous.offset.clamp(0, lastOffset);
      final next = offset == 0
          ? first
          : await port.readShips(
              targetRef,
              query: expectedQuery,
              offset: offset,
              revision: first.revision,
            );
      if (!current()) return;
      validate(next, offset, first.revision);
      if (next.totalCount != first.totalCount ||
          next.matchedCount != first.matchedCount) {
        throw const CommunityFailure('shipsChanged');
      }
      page = next;
      _pendingAvatars.clear();
      mediaFailed = false;
      notifyListeners();
      await _loadAvatars(next, epoch);
    } catch (e) {
      if (!current()) return;
      error = e is CommunityFailure ? e.code : 'unavailable';
      if (error != 'unavailable') {
        page = null;
        _avatars.clear();
      }
      _pendingAvatars.clear();
      if (const {
        'identityUnavailable',
        'notAllowed',
        'notFound',
        'refreshRequired',
      }.contains(error)) {
        invalidated = true;
      }
    } finally {
      if (current()) {
        refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadAvatars(CommunityShipsPage result, int epoch) async {
    _mediaEpoch = epoch;
    try {
      await _readAvatars(result, epoch);
    } finally {
      if (_mediaEpoch == epoch) _mediaEpoch = null;
    }
  }

  Future<void> _readAvatars(CommunityShipsPage result, int epoch) async {
    final media = mediaPort;
    if (media == null) return;
    void current() {
      if (_closed || invalidated || epoch != _epoch) {
        throw const CommunityFailure('identityUnavailable');
      }
    }

    current();
    final references = result.ships
        .where((s) => s.ownerHasAvatar)
        .map((s) => s.ownerMemberRef)
        .toSet();
    final versions = {
      for (final ship in result.ships)
        ship.ownerMemberRef: ship.ownerAvatarVersion,
    };
    _avatars.removeWhere((ref, _) => _avatarVersions[ref] != versions[ref]);
    _avatarVersions
      ..clear()
      ..addAll(versions);
    _avatars.removeWhere((ref, _) => !references.contains(ref));
    _pendingAvatars.addAll(
      references.where((ref) => !_avatars.containsKey(ref)),
    );
    notifyListeners();
    Future<void> read(String ref) async {
      current();
      if (_avatars.containsKey(ref)) return;
      try {
        final retry = _failedAvatars.remove(ref);
        final bytes = await avatars.get(
          ref,
          versions[ref],
          () => assembleCommunityMedia(
            (offset, version) => media.readMedia(
              targetRef,
              'avatar',
              memberRef: ref,
              offset: offset,
              version: version,
            ),
            'avatar',
            memberRef: ref,
            checkCurrent: () {
              if (_closed || invalidated) {
                throw StateError('Expired ship avatar');
              }
            },
          ),
          retry: retry,
        );
        current();
        if (bytes != null) _avatars[ref] = bytes;
      } catch (e) {
        current();
        if (e is CommunityFailure &&
            const {
              'notAllowed',
              'identityUnavailable',
              'refreshRequired',
            }.contains(e.code)) {
          rethrow;
        }
        mediaFailed = true;
        _failedAvatars.add(ref);
      } finally {
        if (!_closed && epoch == _epoch) _pendingAvatars.remove(ref);
      }
      notifyListeners();
    }

    final pending = references.toList();
    var next = 0;
    Future<void> worker() async {
      while (next < pending.length) {
        await read(pending[next++]);
      }
    }

    await Future.wait(List.generate(3, (_) => worker()), eagerError: true);
  }

  Future<void> previous() async {
    final current = page;
    if (busy || current == null || current.offset == 0) return;
    await load(offset: current.offset - 20, revision: current.revision);
  }

  @override
  void dispose() {
    _closed = true;
    if (_ownsAvatars) avatars.dispose();
    _epoch++;
    page = null;
    _avatars.clear();
    _pendingAvatars.clear();
    unawaited(_subscription.cancel());
    unawaited(_publicationSubscription?.cancel());
    // The organization directory owns the adapter.
    super.dispose();
  }
}
