import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_announcements_port.dart';
import 'community_announcement_write_port.dart';

final class CommunityAnnouncementsController extends ChangeNotifier {
  CommunityAnnouncementsController(
    this.port,
    this.targetRef, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityAnnouncementsPort port;
  final String targetRef;
  final DateTime Function() _now;
  DateTime? _lastSuccessfulRead;
  bool _backgroundRead = false;
  bool get showProgress => loading && !_backgroundRead;

  Future<void> enter() async {
    if (!active || loading) return;
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
    await refresh(background: page != null);
  }

  late final StreamSubscription<void> _subscription;
  CommunityAnnouncementsPage? page;
  List<CommunityAnnouncement> _history = [];
  List<CommunityAnnouncement> get history => List.unmodifiable(_history);
  bool loading = false, saving = false, invalidated = false, editing = false;
  bool canManage = false, uncertain = false;
  String? error, writeError, success;
  String title = '', content = '';
  CommunityAnnouncement? editBaseline;
  bool _closed = false;
  int _epoch = 0,
      _readVersion = 0,
      _reads = 0,
      _uncertainRead = 0,
      _minimumRevision = 0;
  final _details = <String, CommunityAnnouncementDetail>{};
  bool get active => !_closed && !invalidated;
  bool get dirty =>
      uncertain ||
      editing &&
          (title != (editBaseline?.title ?? '') ||
              content != (editBaseline?.content ?? ''));
  bool get staleDraft =>
      editing &&
      editBaseline != null &&
      editBaseline!.announcementRef != page?.current?.announcementRef;
  bool get writable =>
      active &&
      !loading &&
      !saving &&
      !uncertain &&
      canManage &&
      page != null &&
      port is CommunityAnnouncementWritePort &&
      (port as CommunityAnnouncementWritePort).announcementWritesAvailable;
  bool get canReviewUnknown =>
      uncertain &&
      !loading &&
      !saving &&
      _reads > _uncertainRead &&
      page != null;

  Future<void> refresh({bool background = false}) =>
      _load(false, background: background);
  void refreshTimeLabels() {
    if (active) notifyListeners();
  }

  Future<void> loadMore() => _load(true);
  Future<void> _load(bool more, {bool background = false}) async {
    if (!active || loading || saving || more && page?.next == null) return;
    final epoch = _epoch;
    final previous = page;
    _lastSuccessfulRead = null;
    _backgroundRead = background && previous != null;
    loading = true;
    error = null;
    if (!background) notifyListeners();
    try {
      if (!port.announcementsAvailable) {
        throw const CommunityFailure('unavailable');
      }
      final next = await port.readAnnouncements(
        targetRef,
        offset: more ? previous!.next! : 0,
        expectedRevision: more ? previous!.revision : null,
      );
      if (!active || epoch != _epoch) return;
      if (next.targetRef != targetRef ||
          next.offset != (more ? previous!.next! : 0) ||
          next.revision < _minimumRevision ||
          previous != null && next.revision < previous.revision ||
          more &&
              (next.revision != previous!.revision ||
                  next.current?.announcementRef !=
                      previous.current?.announcementRef ||
                  next.totalHistoryCount != previous.totalHistoryCount)) {
        throw const FormatException();
      }
      final unchanged =
          background &&
          previous != null &&
          previous.revision == next.revision &&
          previous.current?.announcementRef == next.current?.announcementRef &&
          previous.totalHistoryCount == next.totalHistoryCount;
      final history = unchanged
          ? _history
          : more
          ? [..._history, ...next.history]
          : next.history.toList();
      if (history.map((v) => v.announcementRef).toSet().length !=
              history.length ||
          history.length > 100) {
        throw const FormatException();
      }
      page = unchanged
          ? CommunityAnnouncementsPage.refreshed(previous, next)
          : next;
      _history = history;
      if (!unchanged || canManage != next.canManage) {
        _readVersion++;
        _details.clear();
      }
      canManage = next.canManage;
      _reads++;
      _lastSuccessfulRead = _now();
    } catch (e) {
      if (!active || epoch != _epoch) return;
      error = e is CommunityFailure ? e.code : 'dataInvalid';
      canManage = false;
      if ({
        'identityUnavailable',
        'notAllowed',
        'notFound',
        'refreshRequired',
      }.contains(error)) {
        page = null;
        _history.clear();
        _details.clear();
        _readVersion++;
      }
      if (error == 'identityUnavailable') invalidate();
    } finally {
      if (active && epoch == _epoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<CommunityAnnouncementDetail> detail(
    CommunityAnnouncement entry,
  ) async {
    final epoch = _epoch, version = _readVersion;
    void check() {
      if (!active ||
          epoch != _epoch ||
          version != _readVersion ||
          page?.current?.announcementRef != entry.announcementRef &&
              !_history.any(
                (v) => v.announcementRef == entry.announcementRef,
              )) {
        throw const CommunityFailure('announcementsChanged');
      }
    }

    check();
    final cached = _details[entry.announcementRef];
    if (cached != null) return cached;
    try {
      final result = await assembleCommunityAnnouncementDetail(
        port,
        targetRef,
        entry,
        checkCurrent: check,
      );
      check();
      _details[entry.announcementRef] = result;
      canManage = canManage && result.canManage;
      notifyListeners();
      return result;
    } on CommunityFailure catch (e) {
      if (active && epoch == _epoch && version == _readVersion) {
        if ({
          'notAllowed',
          'identityUnavailable',
          'notFound',
          'refreshRequired',
        }.contains(e.code)) {
          page = null;
          _history.clear();
          _details.clear();
          canManage = false;
          error = e.code;
          _readVersion++;
          if (e.code == 'identityUnavailable') invalidate();
          if (active) notifyListeners();
        }
      }
      rethrow;
    }
  }

  bool startEditing({bool create = true}) {
    if (!writable || dirty || !create && page?.current == null) return false;
    editBaseline = create ? null : page!.current;
    title = editBaseline?.title ?? '';
    content = editBaseline?.content ?? '';
    editing = true;
    writeError = success = null;
    notifyListeners();
    return true;
  }

  void updateDraft(String nextTitle, String nextContent) {
    if (!active || !editing || saving) return;
    title = nextTitle;
    content = nextContent;
    notifyListeners();
  }

  void discardDraft() {
    if (!active || saving) return;
    editing = uncertain = false;
    title = content = '';
    editBaseline = null;
    writeError = null;
    notifyListeners();
  }

  void reviewedUnknown() {
    if (!canReviewUnknown) return;
    uncertain = false;
    writeError = null;
    notifyListeners();
  }

  Future<void> save() async {
    if (!editing || !writable) return;
    if (staleDraft) {
      writeError = 'announcementsChanged';
      notifyListeners();
      return;
    }
    await _write(editBaseline == null ? 'publish' : 'edit', editBaseline);
  }

  Future<void> withdraw(CommunityAnnouncement confirmed) async {
    if (!writable || editing) return;
    if (confirmed.announcementRef != page?.current?.announcementRef) {
      writeError = 'announcementsChanged';
      notifyListeners();
      return;
    }
    await _write('withdraw', confirmed);
  }

  Future<void> _write(String action, CommunityAnnouncement? baseline) async {
    final epoch = _epoch;
    final random = Random.secure();
    CommunityAnnouncementIntent intent;
    try {
      intent = CommunityAnnouncementIntent(
        targetRef: targetRef,
        requestId: List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        action: action,
        announcementRef: baseline?.announcementRef,
        title: action == 'withdraw' ? null : title,
        content: action == 'withdraw' ? null : content,
      );
    } on FormatException {
      writeError = 'dataInvalid';
      notifyListeners();
      return;
    }
    saving = true;
    writeError = success = null;
    notifyListeners();
    try {
      final result = await (port as CommunityAnnouncementWritePort)
          .manageAnnouncement(intent);
      if (!active || epoch != _epoch) return;
      if (result.status == 'accepted' &&
          result.revision != null &&
          result.revision! > 0) {
        _minimumRevision = result.revision!;
        editing = false;
        title = content = '';
        editBaseline = null;
        page = null;
        _history.clear();
        _details.clear();
        _readVersion++;
        canManage = false;
        success = action == 'publish'
            ? 'published'
            : action == 'edit'
            ? 'saved'
            : 'withdrawnSuccess';
      } else if (result.status == 'rejected') {
        writeError = result.error ?? 'unavailable';
        if ({
          'notAllowed',
          'identityUnavailable',
          'refreshRequired',
          'announcementsChanged',
        }.contains(writeError)) {
          canManage = false;
        }
        if (writeError == 'identityUnavailable') invalidate();
      } else {
        uncertain = true;
        _uncertainRead = _reads;
        writeError = 'outcomeUnknown';
      }
    } catch (_) {
      if (active && epoch == _epoch) {
        uncertain = true;
        _uncertainRead = _reads;
        writeError = 'outcomeUnknown';
      }
    } finally {
      if (active && epoch == _epoch) {
        saving = false;
        notifyListeners();
      }
    }
    if (active && epoch == _epoch && success != null) await refresh();
  }

  void invalidate() {
    if (_closed || invalidated) return;
    _epoch++;
    invalidated = true;
    page = null;
    _history.clear();
    _details.clear();
    title = content = '';
    editBaseline = null;
    canManage = editing = uncertain = saving = loading = false;
    error = 'identityUnavailable';
    writeError = success = null;
    notifyListeners();
  }

  @override
  void dispose() {
    invalidate();
    _closed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
