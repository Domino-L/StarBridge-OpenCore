import 'dart:async';

import 'community_announcements_port.dart';
import 'community_author_projection.dart';

typedef CommunityAnnouncementAuthorSurfaceToken = ({
  Object owner,
  String reference,
  int revision,
  int epoch,
});

typedef CommunityAnnouncementAuthorSurfaceProbe = ({
  bool active,
  bool available,
  bool retained,
});

/// One ephemeral author surface and its original publication deadline.
/// Content reads, retained records and detail bytes remain with the controller.
final class CommunityAnnouncementAuthorSurface {
  CommunityAnnouncementAuthorSurface({
    required this.now,
    required this.probe,
    required this.detailProofs,
    required this.retireDetails,
    required this.retireExpiredDetails,
    required this.changed,
  });

  final DateTime Function() now;
  final CommunityAnnouncementAuthorSurfaceProbe Function(String, int) probe;
  final Iterable<CommunityAuthorProjection> Function() detailProofs;
  final void Function({required bool author, required bool editor})
  retireDetails;
  final void Function(DateTime) retireExpiredDetails;
  final void Function() changed;
  Object? _owner;
  String? _reference;
  int _revision = 0, _epoch = 0;
  bool _verified = false, _disposed = false;
  CommunityAuthorProjection _author =
      const CommunityAuthorProjection.unavailable();
  CommunityAuthorProjection _editor =
      const CommunityAuthorProjection.unavailable();
  Timer? _expiry;
  int _expiryEpoch = 0;

  String? get reference => _reference;
  CommunityAuthorProjection get author => _author;
  CommunityAuthorProjection get editor => _editor;

  int? begin(Object owner, CommunityAnnouncement entry) {
    if (_disposed) return null;
    if (identical(owner, _owner) &&
        _reference == entry.announcementRef &&
        _revision == entry.revision) {
      return null;
    }
    forget();
    _owner = owner;
    _reference = entry.announcementRef;
    _revision = entry.revision;
    return _epoch;
  }

  bool end(Object owner) {
    if (!identical(owner, _owner)) return false;
    forget();
    return true;
  }

  bool matches(Object owner, int epoch) =>
      identical(owner, _owner) && epoch == _epoch;

  CommunityAnnouncement present(CommunityAnnouncement entry, Object owner) {
    final state = probe(entry.announcementRef, entry.revision);
    final allowed =
        state.active &&
        state.available &&
        _verified &&
        identical(owner, _owner) &&
        _reference == entry.announcementRef &&
        _revision == entry.revision &&
        state.retained;
    return CommunityAnnouncement.withPeople(
      entry,
      allowed
          ? _author.admit(now())
          : const CommunityAuthorProjection.unavailable(),
      allowed
          ? _editor.admit(now())
          : const CommunityAuthorProjection.unavailable(),
    );
  }

  CommunityAnnouncementAuthorSurfaceToken? capture() {
    final owner = _owner, reference = _reference;
    if (owner == null || reference == null) return null;
    final state = probe(reference, _revision);
    return !state.available || !state.retained
        ? null
        : (
            owner: owner,
            reference: reference,
            revision: _revision,
            epoch: _epoch,
          );
  }

  void accept(
    CommunityAnnouncementAuthorSurfaceToken? surface,
    CommunityAnnouncementsPage next,
  ) {
    if (surface == null ||
        !probe(surface.reference, surface.revision).available ||
        surface.epoch != _epoch ||
        !identical(surface.owner, _owner) ||
        surface.reference != _reference ||
        surface.revision != _revision) {
      return;
    }
    CommunityAnnouncement? record;
    for (final candidate in [?next.current, ...next.history]) {
      if (candidate.announcementRef == surface.reference &&
          candidate.revision == surface.revision) {
        record = candidate;
      }
    }
    final updates = next.authorUpdates.where(
      (value) =>
          value.announcementRef == surface.reference &&
          value.revision == surface.revision,
    );
    if (updates.isNotEmpty) {
      final update = updates.single;
      _verified = update.found;
      _author = update.author;
      _editor = update.editor;
    } else if (record != null) {
      _verified = true;
      _author =
          record.author.identity ??
          const CommunityAuthorProjection.unavailable();
      _editor =
          record.editor.identity ??
          const CommunityAuthorProjection.unavailable();
    } else {
      clearProof();
    }
    schedule();
  }

  void clearProof() {
    _cancelExpiry();
    _verified = false;
    _author = _editor = const CommunityAuthorProjection.unavailable();
    retireDetails(author: true, editor: true);
  }

  void _cancelExpiry() {
    ++_expiryEpoch;
    _expiry?.cancel();
    _expiry = null;
  }

  // The existing one-shot timer moves here; it never performs an IO read.
  void schedule() {
    _cancelExpiry();
    final surface = capture();
    if (surface == null ||
        !probe(surface.reference, surface.revision).active ||
        !_verified) {
      return;
    }
    final at = now();
    _author = _author.admit(at);
    _editor = _editor.admit(at);
    DateTime? earliest;
    retireExpiredDetails(at);
    for (final person in [_author, _editor, ...detailProofs()]) {
      final deadline = person.visible ? person.validUntil : null;
      if (deadline != null &&
          deadline.isAfter(at) &&
          (earliest == null || deadline.isBefore(earliest))) {
        earliest = deadline;
      }
    }
    if (earliest == null) return;
    final expiryEpoch = _expiryEpoch;
    _expiry = Timer(earliest.difference(at), () {
      if (!probe(surface.reference, surface.revision).active ||
          expiryEpoch != _expiryEpoch) {
        return;
      }
      _expiry = null;
      final current = capture();
      if (!_verified ||
          current == null ||
          !identical(current.owner, surface.owner) ||
          current.reference != surface.reference ||
          current.revision != surface.revision ||
          current.epoch != surface.epoch) {
        clearProof();
        changed();
        return;
      }
      final at = now();
      _author = _author.admit(at);
      _editor = _editor.admit(at);
      retireDetails(author: !_author.visible, editor: !_editor.visible);
      retireExpiredDetails(at);
      changed();
      if (expiryEpoch != _expiryEpoch) return;
      schedule();
    });
  }

  void retire() {
    ++_epoch;
    clearProof();
  }

  void forget() {
    ++_epoch;
    _owner = null;
    _reference = null;
    _revision = 0;
    clearProof();
  }

  Object scope(CommunityAnnouncement entry, Object owner) => (
    owner: owner,
    reference: entry.announcementRef,
    revision: entry.revision,
    epoch: _epoch,
  );

  bool proofCurrent(
    CommunityAnnouncement entry,
    Object owner,
    Object expectedScope,
    CommunityAuthorProjection proof,
    bool editor,
  ) {
    final state = probe(entry.announcementRef, entry.revision);
    return state.active &&
        state.available &&
        _verified &&
        identical(owner, _owner) &&
        _reference == entry.announcementRef &&
        _revision == entry.revision &&
        state.retained &&
        expectedScope == scope(entry, owner) &&
        proof.admit(now()).visible &&
        proof.sameObservationAs(editor ? _editor : _author);
  }

  ({Object? author, Object? editor}) detailIdentityKeys(
    CommunityAnnouncement entry,
    Object owner,
  ) {
    Object? key(CommunityAuthorProjection proof, bool editor) =>
        proof.hasAvatar &&
            proofCurrent(entry, owner, scope(entry, owner), proof, editor)
        ? (
            scope: scope(entry, owner),
            version: proof.version,
            avatar: proof.avatarVersion,
            observed: proof.observedAt,
            until: proof.validUntil,
          )
        : null;
    return (author: key(_author, false), editor: key(_editor, true));
  }

  bool detailPersonIsCurrent(
    CommunityAnnouncement entry,
    Object owner,
    CommunityAnnouncementDetail detail, {
    bool editor = false,
  }) {
    final proof = editor ? detail.editorIdentity : detail.authorIdentity;
    final observed = editor
        ? detail.editorObservation
        : detail.authorObservation;
    return proof != null &&
        observed != null &&
        detail.identityScope != null &&
        observed.admit(now()).visible &&
        observed.sameIdentityAs(proof) &&
        proofCurrent(entry, owner, detail.identityScope!, proof, editor);
  }

  void narrow(
    CommunityAuthorProjection first,
    CommunityAuthorProjection second, {
    required bool Function() authorCurrent,
    required bool Function() editorCurrent,
  }) {
    var updated = false;
    if (!first.visible && authorCurrent()) {
      _author = first;
      updated = true;
    }
    if (!second.visible && editorCurrent()) {
      _editor = second;
      updated = true;
    }
    if (updated) {
      retireDetails(author: !first.visible, editor: !second.visible);
      schedule();
      final reference = _reference;
      if (reference != null && probe(reference, _revision).active) changed();
    }
  }

  void dispose() {
    _disposed = true;
    _cancelExpiry();
  }
}
