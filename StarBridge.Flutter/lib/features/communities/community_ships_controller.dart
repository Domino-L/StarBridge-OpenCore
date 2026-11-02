import 'dart:async';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_ships_port.dart';
import 'community_ship_avatar_access.dart';
import 'community_ship_statistics.dart';
import 'community_workspace_port.dart';
import 'community_avatar_cache.dart';

/// One coherent server-filtered page; never filters only the rows already loaded.
final class CommunityShipsController extends ChangeNotifier {
  CommunityShipsController(
    this.port,
    this.targetRef, {
    CommunityShipQuery? initialQuery,
    this.mediaPort,
    this.avatarAccess,
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
  final CommunityShipAvatarAccess? avatarAccess;
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

  /// Owners with an avatar across the whole inventory. The owner view and the
  /// summary strip show people whose ships are not on the page read last.
  final _inventoryOwners = <String, String?>{};
  late final StreamSubscription<void> _subscription;
  StreamSubscription<void>? _publicationSubscription;
  int _publicationVersion = 0;
  CommunityShipQuery query;
  CommunityShipsPage? page;

  /// Every page read for the current query, in order. They outlive the panel
  /// with this controller, so returning shows them all and not just the last.
  List<CommunityShipsPage> get pages => List.unmodifiable(_pages);
  final _pages = <CommunityShipsPage>[];

  void _accumulate(CommunityShipsPage read) {
    if (_pages.isEmpty ||
        read.offset == 0 ||
        read.query != _pages.last.query ||
        read.targetRef != _pages.last.targetRef) {
      _pages
        ..clear()
        ..add(read);
      return;
    }
    final at = _pages.indexWhere((p) => p.offset == read.offset);
    if (at >= 0) {
      _pages[at] = read;
    } else if (read.offset == _pages.last.next) {
      _pages.add(read);
    } else {
      _pages
        ..clear()
        ..add(read);
    }
  }

  /// The complete inventory, kept with the pages. The first page's revision
  /// says on the next visit whether it must be read again.
  CommunityShipStatistics? _statistics;
  String? _statisticsCulture;
  CommunityShipStatistics? get statistics => _statistics;
  CommunityShipStatistics? statisticsFor(String culture) =>
      _statisticsCulture == culture ? _statistics : null;
  void holdStatistics(CommunityShipStatistics? value, String culture) {
    _statistics = value;
    _statisticsCulture = culture;
  }

  /// Presentation memory for the ships panel (user 2026-10-29, option D):
  /// the chosen view and the ship open in the side column survive leaving
  /// the tab, like the page itself.
  String viewMode = 'cards';
  String? selectedShipRef;
  bool selectionIsDefault = false;
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

  /// Retires a pending explicit scope refresh when an intervening read or invalidation wins.
  int get readScopeRevision => _epoch;
  int? _mediaEpoch;
  int _mediaReads = 0;
  bool _closed = false;

  void invalidate() {
    if (_closed) return;
    _epoch++;
    page = null;
    _pages.clear();
    _statistics = null;
    _avatars.clear();
    _avatarVersions.clear();
    _inventoryOwners.clear();
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
    // Loading a later page of the same query keeps the rows already on
    // screen, so their owners' avatars stay too.
    final sameQuery =
        page != null && (selection == null || selection == page!.query);
    if (!keepPage) {
      page = null;
      // Another filter shows the same owners: keep what is drawn, no reread.
      if (sameQuery && offset == 0) _avatars.clear();
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
      _accumulate(result);
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
        _pages.clear();
        _statistics = null;
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
      final held = _pages.isEmpty ? previous.offset : _pages.last.offset;
      final offset = held.clamp(0, lastOffset);
      // The rows on screen stay until every page held has its new answer, so
      // one list never mixes two revisions.
      final fresh = [first];
      while (fresh.last.offset < offset) {
        final at = fresh.last.next!;
        final next = await port.readShips(
          targetRef,
          query: expectedQuery,
          offset: at,
          revision: first.revision,
        );
        if (!current()) return;
        validate(next, at, first.revision);
        if (next.totalCount != first.totalCount ||
            next.matchedCount != first.matchedCount) {
          throw const CommunityFailure('shipsChanged');
        }
        fresh.add(next);
      }
      final next = fresh.last;
      _pages
        ..clear()
        ..addAll(fresh);
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
        _pages.clear();
        _statistics = null;
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

  /// The complete inventory's owners, read while they are still authorized.
  void showOwners(Iterable<CommunitySharedShip> ships) {
    if (_closed) return;
    _inventoryOwners
      ..clear()
      ..addAll({
        for (final ship in ships)
          if (ship.ownerHasAvatar) ship.ownerMemberRef: ship.ownerAvatarVersion,
      });
    final shown = page;
    // A read in progress picks them up when its page arrives.
    if (invalidated || busy || shown == null) return;
    unawaited(_loadAvatars(shown, _epoch).catchError((Object _) {}));
  }

  Future<void> _loadAvatars(CommunityShipsPage result, int epoch) async {
    _mediaEpoch = epoch;
    _mediaReads++;
    try {
      await _readAvatars(result, epoch);
    } finally {
      // The inventory can start a read beside the page's own.
      if (--_mediaReads == 0) _mediaEpoch = null;
    }
  }

  Future<void> _readAvatars(CommunityShipsPage result, int epoch) async {
    final access = avatarAccess;
    final media = mediaPort;
    // Null configuration preserves the existing community adapter. An explicit
    // empty access grants nothing and must never fall back to that adapter.
    final CommunityShipAvatarReader? readAvatar = access == null
        ? media == null
              ? null
              : (
                  String target,
                  String member, {
                  required int offset,
                  String? version,
                }) => media.readMedia(
                  target,
                  'avatar',
                  memberRef: member,
                  offset: offset,
                  version: version,
                )
        : access.read;
    if (readAvatar == null) return;
    void current() {
      if (_closed || invalidated || epoch != _epoch) {
        throw const CommunityFailure('identityUnavailable');
      }
    }

    current();
    // A later page joins the rows above it on screen, and a page is the newer
    // answer for the owners it shows.
    final versions = {
      if (result.offset > 0) ..._avatarVersions,
      ..._inventoryOwners,
    };
    final onPage = <String>{};
    for (final ship in result.ships) {
      onPage.add(ship.ownerMemberRef);
      if (ship.ownerHasAvatar) {
        versions[ship.ownerMemberRef] = ship.ownerAvatarVersion;
      } else {
        versions.remove(ship.ownerMemberRef);
      }
    }
    final references = versions.keys.toSet();
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
            (offset, version) =>
                readAvatar(targetRef, ref, offset: offset, version: version),
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
        // An owner off this page has no row to invalidate: the reference may
        // simply have lapsed, and the page's own reads stay authoritative.
        if (onPage.contains(ref) &&
            e is CommunityFailure &&
            const {
              'notAllowed',
              'identityUnavailable',
              'refreshRequired',
            }.contains(e.code)) {
          rethrow;
        }
        if (onPage.contains(ref)) mediaFailed = true;
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
    _pages.clear();
    _statistics = null;
    _avatars.clear();
    _pendingAvatars.clear();
    unawaited(_subscription.cancel());
    unawaited(_publicationSubscription?.cancel());
    // The organization directory owns the adapter.
    super.dispose();
  }
}
