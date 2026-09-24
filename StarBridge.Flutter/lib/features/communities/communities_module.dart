import 'dart:async';

import 'package:flutter/foundation.dart';

import 'community_workspace_session.dart';
import 'community_workspace_port.dart';

final class CommunityCard {
  const CommunityCard({
    required this.targetRef,
    required this.name,
    this.description = '',
    this.organizationRef,
    this.tags = '',
    this.recruiting = false,
    this.recruitingTarget = '',
    this.recruitingNote = '',
    this.memberScale = '',
    this.systems = const [],
    this.language = '',
    this.activeTime = '',
    this.memberCount,
    this.relationship = 'none',
    this.joinMode = 'unavailable',
    this.actions = const [],
    this.logo,
  });
  final String targetRef,
      name,
      description,
      language,
      activeTime,
      relationship,
      joinMode;
  final String? organizationRef;
  String get key => organizationRef ?? targetRef;
  final String tags, recruitingTarget, recruitingNote, memberScale;
  final bool recruiting;
  final List<String> systems;
  final int? memberCount;
  final List<String> actions;
  final String? logo;

  CommunityCard _named(String value) => CommunityCard(
    targetRef: targetRef,
    organizationRef: organizationRef,
    name: value,
    description: description,
    tags: tags,
    recruiting: recruiting,
    recruitingTarget: recruitingTarget,
    recruitingNote: recruitingNote,
    memberScale: memberScale,
    systems: systems,
    language: language,
    activeTime: activeTime,
    memberCount: memberCount,
    relationship: relationship,
    joinMode: joinMode,
    actions: actions,
    logo: logo,
  );
}

final class CommunityDirectory {
  const CommunityDirectory(
    this.view,
    this.query,
    this.items, {
    this.next,
    this.totalCount,
  });
  final String view, query;
  final List<CommunityCard> items;
  final String? next;
  final int? totalCount;
}

final class CommunityFailure implements Exception {
  const CommunityFailure(this.code);
  final String code;
}

abstract interface class CommunitiesPort {
  Stream<void> get invalidations;
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  });
  Future<String> execute(String action, String targetRef);
  Future<void> close();
}

final class UnavailableCommunities implements CommunitiesPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async => throw const CommunityFailure('unavailable');
  @override
  Future<String> execute(String action, String targetRef) async => 'rejected';
  @override
  Future<void> close() async {}
}

final class CommunitiesModule extends ChangeNotifier {
  CommunitiesModule(
    this.port, {
    DateTime Function()? now,
    this.onOrganizationRenamed,
    this.onWorkspaceFocused,
  }) : _now = now ?? DateTime.now,
       workspaceSession = CommunityWorkspaceSession(now: now) {
    _subscription = port.invalidations.listen((_) {
      _epoch++;
      _joinedEpoch++;
      _joinedRead = null;
      _lastOrganizationKey = null;
      accountRevision++;
      _nameChanges.clear();
      _retiredActionRefs.clear();
      _directoryReadAt = null;
      workspaceSession.clear();
      directory = null;
      joined = const [];
      joinedNext = null;
      joinedLoaded = false;
      joinedBusy = false;
      joinedError = null;
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
    });
  }
  final CommunitiesPort port;
  final void Function(String code, String name)? onOrganizationRenamed;
  final void Function(String code)? onWorkspaceFocused;
  final _nameChanges = <String, ({int revision, String name})>{};
  int _nameRevision = 0;

  /// Apply only an authorized, confirmed name; never reset access or page state.
  void applyOrganizationName(String key, String code, String name) {
    if (_closed || name.isEmpty) return;
    _nameChanges[key] = (revision: ++_nameRevision, name: name);
    CommunityCard update(CommunityCard row) =>
        row.key == key ? row._named(name) : row;
    joined = List.unmodifiable(joined.map(update));
    if (directory case final current?) {
      directory = CommunityDirectory(
        current.view,
        current.query,
        List.unmodifiable(current.items.map(update)),
        next: current.next,
        totalCount: current.totalCount,
      );
    }
    if (selected case final current?) selected = update(current);
    _namesChanged(code, name);
  }

  CommunityDirectory _mergeNames(CommunityDirectory value, int readRevision) =>
      CommunityDirectory(
        value.view,
        value.query,
        List.unmodifiable(
          value.items.map((row) {
            final changed = _nameChanges[row.key];
            return changed != null && changed.revision > readRevision
                ? row._named(changed.name)
                : row;
          }),
        ),
        next: value.next,
        totalCount: value.totalCount,
      );

  void _namesChanged(String code, String name) {
    notifyListeners();
    onOrganizationRenamed?.call(code, name);
  }

  final CommunityWorkspaceSession workspaceSession;
  final DateTime Function() _now;
  DateTime? _directoryReadAt;
  List<CommunityCard> joined = const [];
  String? joinedNext, filters;
  bool joinedLoaded = false, joinedBusy = false;
  String? joinedError;
  bool _recoverDirectory = false;
  int _joinedEpoch = 0;
  Future<void>? _joinedRead;
  String? _lastOrganizationKey;
  Future<void> refreshJoined({bool next = false}) {
    if (_closed) return Future.value();
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
    final revision = accountRevision;
    final request = ++_joinedEpoch;
    final nameRevision = _nameRevision;
    joinedBusy = true;
    joinedError = null;
    notifyListeners();
    try {
      var result = await port.read(
        view: 'mine',
        query: '',
        after: next ? joinedNext : null,
      );
      if (_closed || revision != accountRevision || request != _joinedEpoch) {
        return;
      }
      result = _mergeNames(result, nameRevision);
      joined = List.unmodifiable(
        next
            ? [
                ...joined,
                ...result.items.where(
                  (r) => !joined.any((j) => j.key == r.key),
                ),
              ]
            : result.items,
      );
      joinedNext = result.next;
      joinedLoaded = true;
      if (_recoverDirectory && selected != null) _recoverDirectory = false;
      if (_recoverDirectory && !busy) {
        _recoverDirectory = false;
        await refresh(newView: 'discover');
      }
    } catch (failure) {
      if (!_closed && revision == accountRevision && request == _joinedEpoch) {
        joined = const [];
        joinedNext = null;
        joinedLoaded = false;
        joinedError = failure is CommunityFailure
            ? failure.code
            : 'unavailable';
      }
    } finally {
      if (!_closed && revision == accountRevision && request == _joinedEpoch) {
        joinedBusy = false;
        notifyListeners();
      }
    }
  }

  late final StreamSubscription<void> _subscription;
  int _epoch = 0, accountRevision = 0;
  bool _closed = false, writing = false;
  final _retiredActionRefs = <String>{};
  bool canExecute(CommunityCard card) =>
      !_closed && !writing && !_retiredActionRefs.contains(card.targetRef);
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
    for (final row in candidates) {
      if (_closed || revision != accountRevision) return false;
      if (row.organizationRef == null ||
          !const {'owner', 'member'}.contains(row.relationship)) {
        continue;
      }
      if (await workspaceSession.prepareNext(
        port as CommunityWorkspacePort,
        row.targetRef,
        row.organizationRef!,
        culture,
      )) {
        return true;
      }
    }
    return false;
  }

  Future<void> openJoined(CommunityCard card) async {
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
  CommunityDirectory? directory;
  CommunityCard? selected;
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
        sameQuery &&
        directory != null &&
        error == null &&
        age != null &&
        !age.isNegative &&
        age < const Duration(seconds: 10)) {
      return;
    }
    final retainDirectory = silent && sameQuery && directory != null;
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
    final nameRevision = _nameRevision;
    _reading = request;
    error = null;
    selected = null;
    _directoryReadAt = null;
    if (!retainDirectory) directory = null;
    notifyListeners();
    try {
      var result = await port.read(
        view: request.view,
        query: request.query,
        after: request.after,
        filters: request.filters,
      );
      if (_closed || epoch != _epoch) return;
      result = _mergeNames(result, nameRevision);
      directory = result;
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
      if (view == 'mine' && query.isEmpty && _after == null) {
        _joinedEpoch++;
        joinedBusy = false;
        joined = result.items;
        joinedNext = result.next;
        joinedLoaded = true;
      }
    } on CommunityFailure catch (failure) {
      if (!_closed && epoch == _epoch) {
        error = failure.code;
        if (failure.code != 'unavailable') directory = null;
        if (failure.code == 'refreshRequired') {
          _after = null;
          _pages.clear();
        }
      }
    } catch (_) {
      if (!_closed && epoch == _epoch) error = 'unavailable';
    } finally {
      if (!_closed && epoch == _epoch) {
        _reading = null;
        notifyListeners();
      }
    }
  }

  void open(CommunityCard? card) {
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
    _retiredActionRefs.add(card.targetRef);
    if (_retiredActionRefs.length > 256) {
      _retiredActionRefs.remove(_retiredActionRefs.first);
    }
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
    workspaceSession.clear();
    confirmWorkspaceLeave = null;
    primaryNavigationSelected.dispose();
    _epoch++;
    unawaited(_subscription.cancel());
    unawaited(port.close());
    super.dispose();
  }
}
