import 'personal_profile_edit_groups.dart';
import 'personal_profile_models.dart';
import 'personal_profile_owner_lock.dart';
import 'personal_profile_port.dart';
import 'personal_profile_presentation.dart';

const staleProfileEdit = PersonalProfileActionResult(
  PersonalProfileActionOutcome.rejected,
  requiresReload: true,
  failureKey: 'profile.error.refreshBeforeSave',
);

const _retryProfileEdit = PersonalProfileActionResult(
  PersonalProfileActionOutcome.rejected,
  failureKey: 'profile.error.retryCurrentDraft',
);

const confirmProfileEditConflict = PersonalProfileActionResult(
  PersonalProfileActionOutcome.rejected,
  failureKey: 'profile.error.confirmConflictingGroups',
);

/// The visible draft stays based on the page opened by the user. Only groups
/// for which we showed a conflict can use the newly observed comparison point
/// on the next explicit Save.
final class VersionedProfileEditBaseline {
  VersionedProfileEditBaseline(this._opened) : _lastRevision = _opened.revision;

  final PersonalProfilePresentation _opened;
  final _reviewed = <String, PersonalProfilePresentation>{};
  final _confirmed =
      <
        String,
        ({PersonalProfileSnapshot snapshot, Map<String, Object?> fields})
      >{};
  int _lastRevision;

  bool get hasConfirmedGroups => _confirmed.isNotEmpty;

  Map<String, Map<String, Object?>> pendingGroups(
    PersonalProfileEdit edit,
    Map<String, Map<String, Object?>> openedGroups,
  ) {
    final pending = {...openedGroups};
    for (final entry in _confirmed.entries) {
      final group = entry.key;
      final (:snapshot, :fields) = entry.value;
      final changes = {...?openedGroups[group]};
      final sinceConfirmation = personalProfileEditGroups(
        snapshot,
        edit,
      )[group];
      for (final field in fields.entries) {
        if (!changes.containsKey(field.key)) {
          // The draft can be changed back to its opening value after a
          // partial save. Treat that as a new edit against the confirmed page.
          if (sinceConfirmation?.containsKey(field.key) == true) {
            changes[field.key] = sinceConfirmation![field.key];
          }
        } else if (group == 'playStyle'
            ? PersonalProfilePresentation.samePlayStyleField(
                changes[field.key],
                field.value,
              )
            : PersonalProfilePresentation.sameValue(
                changes[field.key],
                field.value,
              )) {
          changes.remove(field.key);
        }
      }
      if (changes.isEmpty) {
        pending.remove(group);
      } else {
        pending[group] = changes;
      }
    }
    return pending;
  }

  Future<PersonalProfileActionResult> save({
    required PersonalProfileOwnerLock owner,
    required PersonalProfilePresentationWriter writer,
    required Future<PersonalProfileSnapshot> Function() readLatest,
    required bool Function() current,
    required bool Function() sameOwner,
    required Map<String, Map<String, Object?>> groups,
  }) async {
    PersonalProfilePresentation? conflictedWrite;
    for (;;) {
      final latest = await readLatest();
      if (!current()) return staleProfileEdit;
      if (latest.availability == PersonalProfileAvailability.available &&
          !sameOwner()) {
        return staleProfileEdit;
      }
      final fresh = latest.presentation;
      if (!latest.allowEditing ||
          fresh == null ||
          fresh.revision < _lastRevision ||
          owner.confirmationNewerThan(fresh) != null) {
        return _retryProfileEdit;
      }
      _lastRevision = fresh.revision;
      final conflicts = groups.keys
          .where(
            (group) => !(_reviewed[group] ?? _opened).sameGroup(group, fresh),
          )
          .toList();
      if (conflicts.isNotEmpty) {
        for (final group in conflicts) {
          _reviewed[group] = fresh;
        }
        return confirmProfileEditConflict;
      }
      if (conflictedWrite?.revision == fresh.revision &&
          conflictedWrite?.sourceVersion == fresh.sourceVersion) {
        return _retryProfileEdit;
      }
      final result = await writer.savePresentation(fresh, groups);
      if (!current()) return staleProfileEdit;
      if (result.outcome == PersonalProfileActionOutcome.completed) {
        if (result.confirmedProfile case final saved?) {
          owner.confirm(saved);
          for (final entry in groups.entries) {
            _confirmed[entry.key] = (
              snapshot: saved,
              fields: {...?_confirmed[entry.key]?.fields, ...entry.value},
            );
            _reviewed[entry.key] = saved.presentation!;
          }
        }
        return result;
      }
      if (result.failureKey == 'profile.error.writeConflict') {
        if (conflictedWrite != null) return _retryProfileEdit;
        conflictedWrite = fresh;
        continue;
      }
      if (result.failureKey == staleProfileEdit.failureKey) {
        return PersonalProfileActionResult(
          result.outcome,
          requiresReload: true,
          failureKey: result.failureKey,
        );
      }
      // The next user-initiated attempt starts with a fresh, owner-checked
      // read even if this write's acknowledgement was lost.
      return PersonalProfileActionResult(
        result.outcome,
        failureKey: result.failureKey == 'profile.error.writeUnconfirmed'
            ? 'profile.error.draftSaveUnconfirmed'
            : result.failureKey,
      );
    }
  }
}
