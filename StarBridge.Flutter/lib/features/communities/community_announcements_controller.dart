import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_announcements_port.dart';
import 'community_announcement_author_surface.dart';
import 'community_author_projection_port.dart';
import 'community_author_projection.dart';
import 'community_announcement_write_port.dart';
import '../common/organization_announcement_management_session.dart';
import '../common/organization_announcement_management_port.dart';

final class CommunityAnnouncementsController extends ChangeNotifier {
  CommunityAnnouncementsController(
    this.port,
    this.targetRef, {
    DateTime Function()? now,
    this.management,
  }) : _now = now ?? DateTime.now {
    _subscription = port.invalidations.listen((_) => invalidate());
    management?.addListener(_managementChanged);
    if (port is CommunityAnnouncementAuthorProjectionPort) {
      _authorSubscription = (port as CommunityAnnouncementAuthorProjectionPort)
          .authorIdentityChanges
          .listen((_) => _retireAuthorProjection());
    }
  }
  final CommunityAnnouncementsPort port;
  final OrganizationAnnouncementManagementSession? management;
  bool _managementReadOnly = false;
  OrganizationAnnouncementEditor? _preparedEditor;
  bool get _editorAligned =>
      management?.editor != null &&
      page != null &&
      error == null &&
      management!.editor!.revision == page!.revision &&
      management!.editor!.current?.title == page!.current?.title &&
      management!.editor!.current?.content == page!.current?.content;
  bool get showManagementActions => management == null
      ? canManage
      : active && !_managementReadOnly && _editorAligned;

  /// Whether the viewer may manage announcements, as last answered. The actions
  /// follow [showManagementActions], which is false during every read; a page
  /// section must not vanish while that read runs (user 2026-10-31).
  bool get managementGranted => management == null
      ? canManage
      : active && !_managementReadOnly && _managementGranted;
  bool _managementGranted = false;
  void _managementChanged() {
    if (!active) {
      return;
    }
    final session = management;
    if (session?.editor != null) {
      _managementGranted = true;
    } else if (const {
      'notAllowed',
      'identityUnavailable',
    }.contains(session?.error)) {
      _managementGranted = false;
    }
    final original = session?.originalIntent, value = session?.outcome;
    if (!saving &&
        uncertain &&
        original != null &&
        value != null &&
        !value.unresolved) {
      _applyOutcome(
        original.action,
        CommunityAnnouncementOutcome(
          value.status,
          error: value.error,
          revision: value.revision,
        ),
      );
    }
    notifyListeners();
  }

  void setManagementReadOnly(bool value) {
    if (management == null || value == _managementReadOnly) {
      return;
    }
    _managementReadOnly = value;
    if (value) {
      management!.invalidate();
    }
    if (active) {
      notifyListeners();
    }
  }

  Future<void> prepareManagement() async {
    final session = management;
    if (session == null ||
        !active ||
        _managementReadOnly ||
        editing ||
        saving) {
      return;
    }
    await session.prepare();
    if (active) {
      writeError = session.error;
      notifyListeners();
    }
  }

  bool get editorAligned => _editorAligned;
  void answerManagement(bool allowed) {
    if (_managementGranted == allowed) return;
    _managementGranted = allowed;
    notifyListeners();
  }

  Future<bool> prepareEditing({bool create = true}) async {
    if (management != null) {
      await prepareManagement();
    }
    return startEditing(create: create);
  }

  Future<void> queryOriginalOutcome() async {
    final session = management, original = management?.originalIntent;
    if (session == null || original == null || !active || saving) {
      return;
    }
    final epoch = _epoch;
    await session.queryOriginal();
    if (!active || epoch != _epoch) {
      return;
    }
    final value = session.outcome;
    if (uncertain) {
      _applyOutcome(
        original.action,
        CommunityAnnouncementOutcome(
          value?.status ?? 'unknown',
          error: value?.error,
          revision: value?.revision,
        ),
      );
    }
    if (active) {
      notifyListeners();
    }
    if (active && success != null) {
      await refresh();
    }
  }

  final String targetRef;
  final DateTime Function() _now;
  StreamSubscription<void>? _authorSubscription;
  bool _authorSurfaceReadPending = false;
  late final _authorProjection = CommunityAnnouncementAuthorSurface(
    now: _now,
    probe: (reference, revision) => (
      active: active,
      available: _authorAvailable,
      retained: _retainedAuthorRecord(reference, revision) != null,
    ),
    detailProofs: _detailAuthorProofs,
    retireDetails: _retireDetailPeople,
    retireExpiredDetails: _retireExpiredDetailPeople,
    changed: notifyListeners,
  );
  bool get usesOfficialAuthorProjection =>
      port is CommunityAnnouncementAuthorProjectionPort;
  bool get _authorAvailable =>
      usesOfficialAuthorProjection &&
      (port as CommunityAnnouncementAuthorProjectionPort)
          .authorIdentitiesAvailable;
  CommunityAuthorProjection get _surfaceAuthor => _authorProjection.author;
  CommunityAuthorProjection get _surfaceEditor => _authorProjection.editor;

  int? beginAuthorSurface(Object owner, CommunityAnnouncement entry) {
    if (!usesOfficialAuthorProjection || !active) return null;
    final epoch = _authorProjection.begin(owner, entry);
    if (epoch != null) _authorSurfaceReadPending = false;
    return epoch;
  }

  void endAuthorSurface(Object owner) {
    if (_authorProjection.end(owner)) _authorSurfaceReadPending = false;
  }

  CommunityAnnouncement presentAnnouncement(
    CommunityAnnouncement entry,
    Object owner,
  ) => !usesOfficialAuthorProjection
      ? entry
      : _authorProjection.present(entry, owner);

  Future<void> refreshAuthorSurface(Object owner, int epoch) async {
    if (!active ||
        !_authorAvailable ||
        !_authorProjection.matches(owner, epoch)) {
      return;
    }
    if (loading || saving) {
      _authorSurfaceReadPending = true;
      return;
    }
    await refresh(background: true);
  }

  CommunityAnnouncement? _retainedAuthorRecord(String reference, int revision) {
    final current = page?.current;
    if (current?.announcementRef == reference &&
        current?.revision == revision) {
      return current;
    }
    for (final record in _history) {
      if (record.announcementRef == reference && record.revision == revision) {
        return record;
      }
    }
    return null;
  }

  CommunityAnnouncementAuthorSurfaceToken? get _authorSurface =>
      _authorProjection.capture();

  void _acceptAuthorRead(
    CommunityAnnouncementAuthorSurfaceToken? surface,
    CommunityAnnouncementsPage next,
  ) => _authorProjection.accept(surface, next);

  Iterable<CommunityAuthorProjection> _detailAuthorProofs() sync* {
    final reference = _authorProjection.reference;
    final detail = reference == null ? null : _details[reference];
    if (detail?.identityScope != null &&
        detail?.authorAvatarImageData != null) {
      yield detail!.authorObservation!;
    }
    if (detail?.identityScope != null &&
        detail?.editorAvatarImageData != null) {
      yield detail!.editorObservation!;
    }
  }

  void _retireAuthorProjection() {
    if (_closed) return;
    _authorSurfaceReadPending = false;
    _authorProjection.retire();
    if (active) notifyListeners();
  }

  void _forgetAuthorSurface() {
    _authorSurfaceReadPending = false;
    _authorProjection.forget();
  }

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
      (management != null &&
              (!identical(_preparedEditor, management!.editor) ||
                  !_editorAligned) ||
          editBaseline != null &&
              editBaseline!.announcementRef != page?.current?.announcementRef);
  bool get writable =>
      active &&
      !loading &&
      !saving &&
      !uncertain &&
      page != null &&
      (management != null
          ? !_managementReadOnly &&
                _editorAligned &&
                management!.canSubmit(editBaseline == null ? 'publish' : 'edit')
          : canManage &&
                port is CommunityAnnouncementWritePort &&
                (port as CommunityAnnouncementWritePort)
                    .announcementWritesAvailable);
  bool get canReviewUnknown =>
      management == null &&
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
    final authorSurface = _authorSurface;
    _authorSurfaceReadPending = false;
    _lastSuccessfulRead = null;
    _backgroundRead = background && previous != null;
    loading = true;
    error = null;
    if (!background) notifyListeners();
    try {
      if (!port.announcementsAvailable) {
        throw const CommunityFailure('unavailable');
      }
      final authorPort = port is CommunityAnnouncementAuthorProjectionPort
          ? port as CommunityAnnouncementAuthorProjectionPort
          : null;
      final next = authorPort == null
          ? await port.readAnnouncements(
              targetRef,
              offset: more ? previous!.next! : 0,
              expectedRevision: more ? previous!.revision : null,
            )
          : await authorPort.readAnnouncementAuthors(
              targetRef,
              offset: more ? previous!.next! : 0,
              expectedRevision: more ? previous!.revision : null,
              observeAnnouncementRefs: authorSurface == null
                  ? const []
                  : [authorSurface.reference],
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
      _acceptAuthorRead(authorSurface, next);
      canManage = next.canManage;
      _reads++;
      _lastSuccessfulRead = _now();
    } catch (e) {
      if (!active || epoch != _epoch) return;
      if (usesOfficialAuthorProjection) {
        _authorProjection.retire();
      }
      management?.invalidate();
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
        if (_authorSurfaceReadPending) {
          _authorSurfaceReadPending = false;
          if (_authorSurface != null) unawaited(refresh(background: true));
        }
      }
    }
  }

  Object _detailScope(CommunityAnnouncement entry, Object owner) =>
      _authorProjection.scope(entry, owner);

  bool _detailProofCurrent(
    CommunityAnnouncement entry,
    Object owner,
    Object scope,
    CommunityAuthorProjection proof,
    bool editor,
  ) => _authorProjection.proofCurrent(entry, owner, scope, proof, editor);

  ({Object? author, Object? editor}) announcementDetailIdentityKeys(
    CommunityAnnouncement entry,
    Object owner,
  ) => _authorProjection.detailIdentityKeys(entry, owner);

  bool detailPersonIsCurrent(
    CommunityAnnouncement entry,
    Object owner,
    CommunityAnnouncementDetail detail, {
    bool editor = false,
  }) =>
      !usesOfficialAuthorProjection ||
      _authorProjection.detailPersonIsCurrent(
        entry,
        owner,
        detail,
        editor: editor,
      );

  void _retireDetailPeople({required bool author, required bool editor}) {
    if (!author && !editor) return;
    _details.updateAll(
      (_, detail) => detail.identityScope == null
          ? detail
          : CommunityAnnouncementDetail.withoutPeople(
              detail,
              author: author,
              editor: editor,
            ),
    );
  }

  void _retireExpiredDetailPeople(DateTime now) {
    _details.updateAll(
      (_, detail) => detail.identityScope == null
          ? detail
          : CommunityAnnouncementDetail.withoutPeople(
              detail,
              author: detail.authorObservation?.admit(now).visible != true,
              editor: detail.editorObservation?.admit(now).visible != true,
            ),
    );
  }

  Future<CommunityAnnouncementDetail> detail(
    CommunityAnnouncement entry, {
    Object? authorSurfaceOwner,
  }) async {
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
    CommunityAnnouncementDetailIdentity? identity;
    if (usesOfficialAuthorProjection) {
      final owner = authorSurfaceOwner;
      if (owner == null ||
          port is! CommunityAnnouncementAuthorDetailPort ||
          !_authorAvailable) {
        return CommunityAnnouncementDetail(null, null, canManage);
      }
      final scope = _detailScope(entry, owner),
          author = _surfaceAuthor,
          editor = _surfaceEditor;
      bool firstCurrent() =>
          _detailProofCurrent(entry, owner, scope, author, false);
      bool secondCurrent() =>
          _detailProofCurrent(entry, owner, scope, editor, true);
      if (!(author.hasAvatar && firstCurrent()) &&
          !(editor.hasAvatar && secondCurrent())) {
        return CommunityAnnouncementDetail(null, null, canManage);
      }
      identity = CommunityAnnouncementDetailIdentity(
        scope: scope,
        author: author,
        editor: editor,
        now: _now,
        authorCurrent: firstCurrent,
        editorCurrent: secondCurrent,
        narrow: (first, second) => _authorProjection.narrow(
          first,
          second,
          authorCurrent: firstCurrent,
          editorCurrent: secondCurrent,
        ),
        read: (offset, byteVersion, first, second) =>
            (port as CommunityAnnouncementAuthorDetailPort)
                .readAnnouncementAuthorDetail(
                  targetRef,
                  entry.announcementRef,
                  offset,
                  byteVersion,
                  expectedAuthorIdentityVersion: first,
                  expectedEditorIdentityVersion: second,
                ),
      );
    }
    final cached = _details[entry.announcementRef];
    if (cached != null &&
        (identity == null ||
            cached.identityScope == identity.scope &&
                cached.authorIdentity?.sameObservationAs(identity.author) ==
                    true &&
                cached.editorIdentity?.sameObservationAs(identity.editor) ==
                    true)) {
      return cached;
    }
    try {
      final result = await assembleCommunityAnnouncementDetail(
        port,
        targetRef,
        entry,
        checkCurrent: check,
        identity: identity,
      );
      check();
      _details[entry.announcementRef] = result;
      if (identity != null) {
        _retireDetailPeople(
          author: !identity.wantsAuthor,
          editor: !identity.wantsEditor,
        );
        _authorProjection.schedule();
      }
      canManage = canManage && result.canManage;
      notifyListeners();
      return result;
    } on CommunityFailure catch (e) {
      if (active && epoch == _epoch && version == _readVersion) {
        if (e.code == 'notAllowed') _managementGranted = false;
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
    _preparedEditor = management?.editor;
    title = create
        ? ''
        : management?.editor?.current?.title ?? editBaseline?.title ?? '';
    content = create
        ? ''
        : management?.editor?.current?.content ?? editBaseline?.content ?? '';
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
    editing = false;
    uncertain = management != null && (uncertain || management!.unresolved);
    title = content = '';
    editBaseline = null;
    writeError = uncertain ? 'outcomeUnknown' : null;
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
    late CommunityAnnouncementIntent intent;
    if (management == null) {
      final random = Random.secure();
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
    }
    saving = true;
    writeError = success = null;
    notifyListeners();
    try {
      CommunityAnnouncementOutcome result;
      final session = management;
      if (session == null) {
        result = await (port as CommunityAnnouncementWritePort)
            .manageAnnouncement(intent);
      } else {
        final sending = session.submit(
          action,
          title: action == 'withdraw' ? null : title,
          content: action == 'withdraw' ? null : content,
        );
        final original = session.originalIntent;
        await sending;
        final value = session.outcome;
        result = CommunityAnnouncementOutcome(
          value?.status ?? (original == null ? 'rejected' : 'unknown'),
          error: value?.error,
          revision: value?.revision,
        );
      }
      if (!active || epoch != _epoch) return;
      _applyOutcome(action, result);
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

  void _applyOutcome(String action, CommunityAnnouncementOutcome result) {
    if (result.status == 'accepted' &&
        result.revision != null &&
        result.revision! > 0) {
      uncertain = false;
      writeError = null;
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
      uncertain = false;
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
  }

  void invalidate() {
    if (_closed || invalidated) return;
    _epoch++;
    _forgetAuthorSurface();
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
    _authorProjection.dispose();
    _closed = true;
    unawaited(_subscription.cancel());
    management?.removeListener(_managementChanged);
    final authorSubscription = _authorSubscription;
    if (authorSubscription != null) unawaited(authorSubscription.cancel());
    super.dispose();
  }
}
