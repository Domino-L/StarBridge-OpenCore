import 'dart:async';

import 'package:flutter/foundation.dart';

import 'communities_port.dart';
import 'community_workspace_session.dart';
import 'community_workspace_port.dart';
import 'community_chat_attention.dart';
import 'community_cached_presentation_port.dart';
import 'community_directory_models.dart';
import 'community_cached_page.dart';
import 'community_directory_images.dart';
import 'community_directory_read_owner.dart';
import '../../shared/downloadable_image_cache.dart';

export 'community_directory_models.dart';
export 'communities_port.dart';

final class CommunitiesModule extends ChangeNotifier
    implements DownloadableImageCache {
  CommunitiesModule(
    this.port, {
    DateTime Function()? now,
    this.onOrganizationRenamed,
    this.onWorkspaceFocused,
  }) : _now = now ?? DateTime.now {
    _subscription = port.invalidations.listen((_) => _invalidateAccount());
    if (port is CommunityCachedPresentationPort) {
      _cachedSelection = (port as CommunityCachedPresentationPort)
          .cachedSelectionChanges
          .listen(_renewCachedSelection);
      _cachedPresentation = (port as CommunityCachedPresentationPort)
          .cachedLogoChanges
          .listen((value) {
            if (_closed) return;
            _directoryReads.cachedLogo(value, joinedCacheVersion);
          });
    }
  }
  final CommunitiesPort port;
  late final CommunityDirectoryReadOwner _directoryReads =
      CommunityDirectoryReadOwner(port, _images, notifyListeners);
  late final _images = CommunityDirectoryImages(
    workspaceSession,
    port,
    () => _directoryReads.retireLogos(),
  );
  @override
  void beginImageMaintenance() {
    if (!_closed) _images.beginImageMaintenance();
  }

  @override
  void endImageMaintenance() {
    if (!_closed) _images.endImageMaintenance();
  }

  void _invalidateAccount() {
    _directoryReads.retireAll();
    _epoch++;
    _joinedEpoch++;
    _joinedRead = null;
    _lastOrganizationKey = null;
    accountRevision++;
    _directoryReads.clearNames();
    _retiredActionRefs.clear();
    _directoryReadAt = null;
    workspaceSession.clear();
    directory = null;
    joined = const [];
    joinedNext = null;
    joinedLoaded = false;
    joinedBusy = false;
    joinedError = null;
    joinedCachedAtUtc = null;
    joinedCacheComplete = true;
    joinedCacheVersion = null;
    _joinedReadAt = null;
    _recoverDirectory = true;
    filters = null;
    selected = null;
    view = 'mine';
    query = '';
    _pages.clear();
    _after = null;
    _reading = null;
    writing = false;
    _selectionRevision++;
    message = null;
    error = 'identityUnavailable';
    notifyListeners();
  }

  void _renewCachedSelection(CommunityCachedSelectionChange change) {
    if (_closed) return;
    final prepareDirectory = _reading != null || directory != null;
    if (change == CommunityCachedSelectionChange.replace) {
      // A missing predecessor is the existing account boundary, including
      // private workspace owners. Do not duplicate a partial invalidation.
      _invalidateAccount();
      unawaited(refreshJoined());
      if (prepareDirectory) unawaited(refresh(silent: true, force: true));
      return;
    }
    _epoch++;
    _joinedEpoch++;
    _joinedRead = null;
    _reading = null;
    joinedBusy = false;
    // A display descriptor never restores commands or replays an uncertain
    // write. Only already read-only cards survive this preparation boundary.
    if (writing) message = 'outcomeUnknown';
    writing = false;
    selected = null;
    joined = List.unmodifiable(joined.where((row) => row.displayOnly));
    if (directory?.items.any((row) => !row.displayOnly) == true) {
      directory = null;
      joinedLoaded = false;
      joinedCachedAtUtc = _joinedReadAt = null;
      joinedCacheVersion = joinedNext = null;
      _after = null;
      _pages.clear();
    }
    joinedError = error = null;
    _recoverDirectory = false;
    if (prepareDirectory &&
        view == 'mine' &&
        query.isEmpty &&
        filters == null) {
      _silentRead = true;
      _reading = (view: view, query: query, after: _after, filters: filters);
      unawaited(_restoreCachedPage(_epoch, refreshJoined()));
    } else {
      unawaited(refreshJoined());
      if (prepareDirectory) unawaited(refresh(silent: true, force: true));
    }
  }

  Future<void> _restoreCachedPage(int epoch, Future<void> first) async {
    final imageEpoch = _images.epoch;
    final page = await prepareCachedCommunityPage(
      after: _after,
      firstPage: first,
      current: () => !_closed && epoch == _epoch,
      snapshot: () => !joinedLoaded || joinedError != null
          ? null
          : CommunityDirectory(
              'mine',
              '',
              joined,
              next: joinedNext,
              cachedAtUtc: joinedCachedAtUtc,
              cacheComplete: joinedCacheComplete,
              displayVersion: joinedCacheVersion,
            ),
      advance: () => refreshJoined(next: true),
    );
    if (_closed || epoch != _epoch) return;
    directory = _images.current(imageEpoch)
        ? page?.directory
        : page?.directory.withoutDownloadedLogos();
    _after = page?.after;
    _pages
      ..clear()
      ..addAll(page?.previous ?? const []);
    error = page == null ? joinedError ?? 'offlineCacheUnavailable' : null;
    _directoryReadAt = page == null ? null : _now();
    _reading = null;
    notifyListeners();
  }

  final void Function(String code, String name)? onOrganizationRenamed;
  final void Function(String code)? onWorkspaceFocused;

  /// Apply only an authorized, confirmed name; never reset access or page state.
  void applyOrganizationName(String key, String code, String name) {
    if (_closed || name.isEmpty) return;
    _directoryReads.rename(key, name);
    notifyListeners();
    onOrganizationRenamed?.call(code, name);
  }

  late final chatAttention = CommunityChatAttention(port);
  late final workspaceSession = CommunityWorkspaceSession(
    now: _now,
    attention: chatAttention,
  );
  bool get overviewAvailable => !_closed && !writing;
  final DateTime Function() _now;
  DateTime? _directoryReadAt;
  List<CommunityCard> get joined => _directoryReads.joined;
  set joined(List<CommunityCard> value) => _directoryReads.joined = value;
  String? joinedNext, filters;
  bool joinedLoaded = false, joinedBusy = false;
  String? joinedError;
  DateTime? joinedCachedAtUtc;
  DateTime? _joinedReadAt;
  bool joinedCacheComplete = true;
  String? joinedCacheVersion;
  bool _recoverDirectory = false;
  int _joinedEpoch = 0;
  Future<void>? _joinedRead;
  String? _lastOrganizationKey;
  Future<void> refreshJoined({bool next = false}) {
    if (_closed ||
        const {
          'onlinePaused',
          'offlineCacheUnavailable',
        }.contains(joinedError)) {
      return Future.value();
    }
    final pending = _joinedRead;
    if (pending != null) return pending;
    final reading = _readJoined(next: next);
    _joinedRead = reading;
    unawaited(
      reading.whenComplete(() {
        if (identical(_joinedRead, reading)) _joinedRead = null;
      }),
    );
    return reading;
  }

  Future<void> _readJoined({bool next = false}) async {
    if (_closed || joinedBusy) return;
    _directoryReads.retireJoined();
    final revision = accountRevision;
    final request = ++_joinedEpoch;
    final nameRevision = _directoryReads.nameRevision;
    final imageEpoch = _images.epoch;
    joinedBusy = true;
    joinedError = null;
    notifyListeners();
    try {
      final read = await _directoryReads.read(
        view: 'mine',
        query: '',
        after: next ? joinedNext : null,
      );
      if (_closed || revision != accountRevision || request != _joinedEpoch) {
        read.retireImages();
        return;
      }
      final result = _directoryReads.joinedMetadata(
        read,
        nameRevision,
        imageEpoch,
      );
      final items = _images.mergeJoined(
        result,
        joined,
        joinedCacheVersion,
        imageEpoch,
      );
      joined = List.unmodifiable(
        next
            ? [
                ...joined,
                ...items.where((r) => !joined.any((j) => j.key == r.key)),
              ]
            : items,
      );
      joinedNext = result.next;
      joinedLoaded = true;
      joinedCachedAtUtc = result.cachedAtUtc;
      joinedCacheComplete = result.cacheComplete;
      joinedCacheVersion = result.displayVersion;
      _joinedReadAt = result.cachedAtUtc ?? _now().toUtc();
      _retiredActionRefs.removeWhere(
        (reference) =>
            items.any((row) => !row.displayOnly && row.targetRef == reference),
      );
      chatAttention.bind(
        joined.where((row) => !row.displayOnly).map((row) => row.targetRef),
      );
      _directoryReads.watchJoined(
        read,
        imageEpoch,
        () => revision == accountRevision && request == _joinedEpoch,
      );
      if (joinedCachedAtUtc != null) _recoverDirectory = false;
      if (_recoverDirectory && selected != null) _recoverDirectory = false;
      if (_recoverDirectory && !busy) {
        _recoverDirectory = false;
        await refresh(newView: 'discover');
      }
    } catch (failure) {
      if (!_closed && revision == accountRevision && request == _joinedEpoch) {
        _joinedFailed(
          failure is CommunityFailure ? failure.code : 'unavailable',
        );
      }
    } finally {
      if (!_closed && revision == accountRevision && request == _joinedEpoch) {
        joinedBusy = false;
        notifyListeners();
      }
    }
  }

  void _joinedFailed(String code) {
    chatAttention.clear();
    joinedError = code;
    _retireActions(joined.map((row) => row.targetRef));
    if (code == 'readTransient' && joinedLoaded && _joinedReadAt != null) {
      joinedCacheComplete = joinedCacheComplete && joinedNext == null;
      joined = List.unmodifiable(joined.map((row) => row.asDisplayOnly()));
      joinedCachedAtUtc = _joinedReadAt;
    } else {
      joined = const [];
      joinedLoaded = false;
      joinedCachedAtUtc = _joinedReadAt = null;
      joinedCacheVersion = null;
      joinedCacheComplete = true;
    }
    joinedNext = null;
  }

  late final StreamSubscription<void> _subscription;
  StreamSubscription<CommunityCachedLogo>? _cachedPresentation;
  StreamSubscription<CommunityCachedSelectionChange>? _cachedSelection;
  int _epoch = 0, accountRevision = 0;
  bool _closed = false, writing = false;
  bool _silentRead = false;
  bool get showDirectoryProgress => _reading != null && !_silentRead;
  // Existing epoch, exposed read-only for presentation. No request is started.
  int? get directoryReadEpoch => _reading == null ? null : _epoch;
  final _retiredActionRefs = <String>{};
  bool canExecute(CommunityCard card) =>
      !_closed &&
      !writing &&
      !card.displayOnly &&
      !_retiredActionRefs.contains(card.targetRef);

  void _retireActions(Iterable<String> references) {
    for (final reference in references.where((value) => value.isNotEmpty)) {
      _retiredActionRefs.add(reference);
      if (_retiredActionRefs.length > 256) {
        _retiredActionRefs.remove(_retiredActionRefs.first);
      }
    }
  }

  ({String view, String query, String? after, String? filters})? _reading;
  int _selectionRevision = 0;
  bool get busy => writing || _reading != null;
  String view = 'mine', query = '';
  final primaryNavigationSelected = ValueNotifier<bool>(true);
  Future<bool> Function()? confirmWorkspaceLeave;

  Future<bool> confirmLeave() async =>
      await confirmWorkspaceLeave?.call() ?? true;

  Future<void> openDiscovery() async {
    final revision = accountRevision;
    if (!await confirmLeave() ||
        _closed ||
        writing ||
        revision != accountRevision) {
      return;
    }
    selected = null;
    _selectionRevision++;
    notifyListeners();
    if (view == 'discover') {
      // Navigation should not wait for the network when a picture is available.
      unawaited(refresh(silent: true, reuseFresh: true));
      return;
    }
    unawaited(refresh(newView: 'discover'));
  }

  /// Intent-based warming never opens an organization or discards its editor.
  Future<void> prefetch() async {
    if (_closed || writing || selected != null) return;
    await refresh(
      newView: view == 'discover' ? null : 'discover',
      silent: true,
      reuseFresh: true,
    );
  }

  /// Warm one known workspace, not every joined organization or its media.
  /// Without a remembered selection, a sole membership is unambiguous.
  Future<void> prefetchWorkspace() async {
    if (_closed || writing || port is! CommunityWorkspacePort) return;
    final revision = accountRevision;
    if (!joinedLoaded) await refreshJoined();
    if (_closed || writing || revision != accountRevision || !joinedLoaded) {
      return;
    }
    final key = selected?.key ?? _lastOrganizationKey;
    final candidate = key != null
        ? joined.where((row) => row.key == key).firstOrNull
        : joined.length == 1
        ? joined.single
        : null;
    if (candidate == null ||
        candidate.organizationRef == null ||
        !const {'owner', 'member'}.contains(candidate.relationship)) {
      return;
    }
    await workspaceSession.prefetch(
      port as CommunityWorkspacePort,
      candidate.targetRef,
      candidate.organizationRef!,
    );
  }

  /// Continue the session's idle queue across admitted organizations, using
  /// the same bounded controllers that foreground navigation obtains.
  Future<bool> prepareNextWorkspace(String culture) async {
    if (_closed || port is! CommunityWorkspacePort) return false;
    if (busy || joinedBusy) return true;
    if (!joinedLoaded) {
      if (joinedError != null) return false;
      await refreshJoined();
      return joinedLoaded;
    }
    final revision = accountRevision;
    final candidates = [
      ?selected,
      ...joined.where((row) => row.key != selected?.key),
    ];
    // Idle media speculation is limited to the first eligible workspace (the
    // selected one, else the first joined). Device traces showed ~260 media
    // reads per 7 minutes when every joined organization prepared all media,
    // competing with page reads for the Host's request workers.
    var mediaCandidate = true;
    for (final row in candidates) {
      if (_closed || revision != accountRevision) return false;
      if (row.organizationRef == null ||
          !const {'owner', 'member'}.contains(row.relationship)) {
        continue;
      }
      final includeMedia = mediaCandidate;
      mediaCandidate = false;
      if (await workspaceSession.prepareNext(
        port as CommunityWorkspacePort,
        row.targetRef,
        row.organizationRef!,
        culture,
        includeMedia: includeMedia,
      )) {
        return true;
      }
    }
    return false;
  }

  Future<void> openJoined(CommunityCard card) async {
    if (card.displayOnly) return;
    if (selected?.key == card.key) return;
    final revision = accountRevision;
    if (!await confirmLeave() || _closed || revision != accountRevision) return;
    open(card);
  }

  Future<void> refreshCurrentMembership() async {
    final key = selected?.key;
    final revision = accountRevision;
    await refreshJoined();
    bool current() =>
        !_closed && revision == accountRevision && selected?.key == key;
    // Discovery filters do not decide whether the current membership exists.
    // Rebind against the existing joined directory, including later pages.
    while (current() &&
        joinedLoaded &&
        joinedNext != null &&
        !joined.any((row) => row.key == key)) {
      final cursor = joinedNext;
      await refreshJoined(next: true);
      if (joinedNext == cursor) return;
    }
    if (!current() || !joinedLoaded) return;
    for (final row in joined) {
      if (row.key == key) {
        open(row);
        return;
      }
    }
    workspaceSession.clear();
    await refresh(newView: 'discover');
  }

  @override
  void notifyListeners() {
    primaryNavigationSelected.value =
        selected == null ||
        !const {'owner', 'member'}.contains(selected!.relationship);
    super.notifyListeners();
  }

  String? error, message, _after;
  final List<String?> _pages = [];
  CommunityDirectory? get directory => _directoryReads.directory;
  set directory(CommunityDirectory? value) => _directoryReads.directory = value;
  CommunityCard? get selected => _directoryReads.selected;
  set selected(CommunityCard? value) => _directoryReads.selected = value;
  bool get canPrevious => _pages.isNotEmpty;
  Future<void> refresh({
    String? newView,
    String? newQuery,
    String? newFilters,
    bool preserveSelection = false,
    bool silent = false,
    bool reuseFresh = false,
    bool force = false,
  }) async {
    if (writing || _closed) return;
    final sameQuery = newView == null && newQuery == null && newFilters == null;
    final request = (
      view: newView ?? view,
      query: (newQuery ?? (newView != null ? '' : query)).trim(),
      after: sameQuery ? _after : null,
      filters: (newView ?? view) == 'discover' ? (newFilters ?? filters) : null,
    );
    if (!force && _reading == request) return;
    final age = _directoryReadAt == null
        ? null
        : _now().difference(_directoryReadAt!);
    if (reuseFresh &&
        !_images.referencesStale &&
        sameQuery &&
        directory != null &&
        error == null &&
        age != null &&
        !age.isNegative &&
        age < const Duration(seconds: 10)) {
      return;
    }
    final retainDirectory =
        directory != null &&
        request.view == view &&
        request.query == query &&
        request.filters == (view == 'discover' ? filters : null) &&
        request.after == _after;
    final previousReadAt = _directoryReadAt;
    _directoryReads.retireDirectory();
    final selectedKey = preserveSelection ? selected?.key : null;
    final selectionRevision = _selectionRevision;
    if (newView != null || newQuery != null || newFilters != null) {
      view = newView ?? view;
      query = (newQuery ?? (newView != null ? '' : query)).trim();
      if (newFilters != null) filters = newFilters;
      if (newView == 'mine') filters = null;
      _after = null;
      _pages.clear();
    }
    final epoch = ++_epoch;
    final joinedEpoch = _joinedEpoch;
    final nameRevision = _directoryReads.nameRevision;
    final imageEpoch = _images.epoch;
    _silentRead = silent;
    _reading = request;
    error = null;
    selected = null;
    _directoryReadAt = null;
    if (!retainDirectory) directory = null;
    notifyListeners();
    try {
      final read = await _directoryReads.read(
        view: request.view,
        query: request.query,
        after: request.after,
        filters: request.filters,
      );
      if (_closed || epoch != _epoch) {
        read.retireImages();
        return;
      }
      final result = _directoryReads.directoryMetadata(
        read,
        nameRevision,
        imageEpoch,
      );
      directory = result;
      _images.acceptedRead(imageEpoch);
      // Only an authoritative fresh read can make an action usable again.
      // Example/local ports may reuse addresses; no write is automatically replayed.
      _retiredActionRefs.removeWhere(
        (reference) => result.items.any((row) => row.targetRef == reference),
      );
      _directoryReadAt = _now();
      if (selectedKey != null && selectionRevision == _selectionRevision) {
        for (final card in result.items) {
          if (card.key == selectedKey) selected = card;
        }
      }
      if (view == 'mine' &&
          query.isEmpty &&
          _after == null &&
          joinedEpoch == _joinedEpoch) {
        _joinedEpoch++;
        joinedBusy = false;
        joined = result.items;
        joinedNext = result.next;
        joinedLoaded = true;
        joinedError = null;
        _joinedRead = null;
        _joinedReadAt = result.cachedAtUtc ?? _directoryReadAt?.toUtc();
        joinedCachedAtUtc = result.cachedAtUtc;
        joinedCacheComplete = result.cacheComplete;
        joinedCacheVersion = result.displayVersion;
        chatAttention.bind(
          result.items
              .where((row) => !row.displayOnly)
              .map((row) => row.targetRef),
        );
      }
      final joinedImageOwner = _joinedEpoch;
      final mirrorsJoined =
          request.view == 'mine' &&
          request.query.isEmpty &&
          request.after == null;
      _directoryReads.watchDirectory(
        read,
        imageEpoch,
        () => epoch == _epoch,
        mirrorJoined: () => mirrorsJoined && joinedImageOwner == _joinedEpoch,
      );
    } on CommunityFailure catch (failure) {
      if (!_closed && epoch == _epoch) {
        error = failure.code;
        final previous = directory;
        _retireActions(previous?.items.map((row) => row.targetRef) ?? const []);
        directory = failure.code == 'readTransient'
            ? previous?.asDisplayOnly(previousReadAt)
            : null;
        if (request.view == 'mine' &&
            request.query.isEmpty &&
            request.after == null &&
            joinedEpoch == _joinedEpoch) {
          _joinedEpoch++;
          joinedBusy = false;
          _joinedRead = null;
          _joinedFailed(failure.code);
        }
        if (failure.code == 'refreshRequired') {
          _after = null;
          _pages.clear();
        }
      }
    } catch (_) {
      if (!_closed && epoch == _epoch) {
        error = 'unavailable';
        directory = null;
        if (request.view == 'mine' &&
            request.query.isEmpty &&
            request.after == null &&
            joinedEpoch == _joinedEpoch) {
          _joinedEpoch++;
          joinedBusy = false;
          _joinedRead = null;
          _joinedFailed('unavailable');
        }
      }
    } finally {
      if (!_closed && epoch == _epoch) {
        _reading = null;
        notifyListeners();
      }
    }
  }

  void open(CommunityCard? card) {
    if (card?.displayOnly == true) return;
    if (!_closed && !writing) {
      if (card != null &&
          !const {'owner', 'member'}.contains(card.relationship)) {
        workspaceSession.clear();
      }
      selected = card;
      if (card != null &&
          const {'owner', 'member'}.contains(card.relationship)) {
        _lastOrganizationKey = card.key;
      }
      _selectionRevision++;
      notifyListeners();
    }
  }

  Future<void> next() async {
    if (busy || directory?.next == null) return;
    _pages.add(_after);
    _after = directory!.next;
    await refresh();
  }

  Future<void> previous() async {
    if (busy || _pages.isEmpty) return;
    _after = _pages.removeLast();
    await refresh();
  }

  Future<void> execute(CommunityCard card, String action) async {
    if (!canExecute(card) || !card.actions.contains(action)) return;
    if (action == 'leave') {
      final beforeConfirmation = _epoch;
      if (!await confirmLeave() ||
          _closed ||
          writing ||
          beforeConfirmation != _epoch) {
        return;
      }
    }
    final epoch = ++_epoch;
    _reading = null;
    writing = true;
    _retireActions([card.targetRef]);
    // In-flight reads from before this write must not restore an old membership.
    _directoryReadAt = null;
    workspaceSession.clear();
    _joinedEpoch++;
    _joinedRead = null;
    joinedBusy = false;
    error = null;
    message = null;
    notifyListeners();
    String status;
    try {
      status = await port.execute(action, card.targetRef);
    } catch (_) {
      status = 'unknown';
    }
    if (_closed || epoch != _epoch) return;
    writing = false;
    selected = null;
    if (action == 'leave' && status == 'accepted') {
      joined = List.unmodifiable(joined.where((row) => row.key != card.key));
    }
    message = status == 'accepted'
        ? 'done.$action'
        : status == 'unknown'
        ? 'outcomeUnknown'
        : 'refreshRequired';
    // Do not replay a write after uncertainty. A fresh directory supplies new action targets.
    // Independent readbacks: a slow discovery directory must not delay the
    // joined sidebar. Keep old cards visible, but never reuse consumed actions.
    await Future.wait([refresh(silent: action != 'leave'), refreshJoined()]);
    if (!_closed && epoch + 1 == _epoch && message == 'outcomeUnknown') {
      final fresh = directory?.items
          .where((row) => row.key == card.key)
          .firstOrNull;
      final member = joinedLoaded && joined.any((row) => row.key == card.key);
      if ((action == 'join' || action == 'apply') &&
              (member ||
                  const {'owner', 'member'}.contains(fresh?.relationship)) ||
          action == 'apply' && fresh?.relationship == 'pending') {
        message = 'done.$action';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _directoryReads.dispose();
    workspaceSession.clear();
    chatAttention.dispose();
    confirmWorkspaceLeave = null;
    primaryNavigationSelected.dispose();
    _epoch++;
    unawaited(_subscription.cancel());
    unawaited(_cachedPresentation?.cancel());
    unawaited(_cachedSelection?.cancel());
    unawaited(port.close());
    super.dispose();
  }
}
