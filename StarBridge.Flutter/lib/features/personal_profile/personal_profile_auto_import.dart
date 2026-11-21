import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'personal_profile_collaboration.dart';
import 'personal_profile_auto_import_validation.dart';
import 'personal_profile_edit_groups.dart';
import 'personal_profile_local_projection.dart';
import 'personal_profile_models.dart';
import 'personal_profile_owner_lock.dart';
import 'personal_profile_port.dart';

typedef PersonalProfileAutoImportPlan = ({
  Map<String, Map<String, Object?>> edits,
  Set<String> unresolved,
});

/// Plans a write from an already validated local read and two views of the same
/// server page. Only groups never saved on the versioned page are eligible.
PersonalProfileAutoImportPlan planPersonalProfileAutoImport(
  PersonalProfileSnapshot displayed,
  PersonalProfileSnapshot local,
  Map<String, Object?> content,
) {
  final presentation = displayed.presentation;
  bool eligible(String group) => presentation?.canAutoImport(group) == true;
  bool explicitlyEmpty(String field) =>
      (content['fieldStates'] as Map?)?[field] == true;
  final unresolved = <String>{};

  final style = content['playStyle'] as Map?;
  final localRoles = ProfileCollaboration.ids(local.roles, 'roles');
  List<String>? changedTags(
    String field,
    List<PersonalProfileTagValue> from,
    List<PersonalProfileTagValue> shown,
  ) {
    final raw = style?[field];
    if (raw is! List || raw.isEmpty && !explicitlyEmpty(field)) return null;
    final ids = raw.isEmpty
        ? <String>[]
        : ProfileCollaboration.ids(from, field);
    return setEquals(
          ids.toSet(),
          ProfileCollaboration.ids(shown, field).toSet(),
        )
        ? null
        : ids;
  }

  final mainRole = content['mainRole'] as String?;
  final shownMainRole = displayed.roles
      .where((role) => role.isPrimary)
      .map((role) => ProfileCollaboration.idOf(role, 'roles'))
      .firstOrNull;
  final changeMainRole =
      mainRole != null &&
      mainRole.isNotEmpty &&
      localRoles.contains(mainRole) &&
      mainRole != shownMainRole;
  if (eligible('playStyle') &&
      changeMainRole &&
      presentation?.content.containsKey('mainRole') != true) {
    unresolved.add('playStyle');
  }
  PersonalProfilePlayStyle? playStyle;
  if (eligible('playStyle')) {
    final roles = changeMainRole
        ? localRoles
        : changedTags('roles', local.roles, displayed.roles);
    playStyle = PersonalProfilePlayStyle(
      roles: roles,
      interests: changedTags(
        'interests',
        local.participationInterests,
        displayed.participationInterests,
      ),
      support: changedTags(
        'support',
        local.supportCapabilities,
        displayed.supportCapabilities,
      ),
      mainRole: changeMainRole
          ? mainRole
          : shownMainRole != null &&
                roles != null &&
                !roles.contains(shownMainRole)
          ? ''
          : null,
    );
  }

  final schedule = PersonalProfileSchedule(
    timeZoneId: local.timeZoneLabel,
    rhythm: local.activityRhythm,
    windows: local.availabilityWindows,
  );

  // The legacy flat list has three slots. The layout group carries all the
  // per-module picks, including the existing UUID-based fourth slots.
  List<String>? codes;
  if (eligible('favorites')) {
    final ids = savedProfileFavoriteIds(content);
    if (ids != null && (ids.isNotEmpty || explicitlyEmpty('favoriteShipIds'))) {
      final choices = {
        for (final ship
            in local.local?.choices ?? const <PersonalProfileShipSummary>[])
          ship.identity.runtimeId: ship.identity.catalogId,
      };
      final selectedCodes = ids.map((id) => choices[id]?.trim());
      final distinct = <String>{};
      codes = [];
      for (final code in selectedCodes) {
        if (code == null || code.isEmpty) {
          unresolved.add('favorites');
          break;
        }
        if (distinct.add(code.toLowerCase())) codes.add(code);
        if (codes.length == 3) break;
      }
    }
  }

  final introduction = content['introduction'] as String?;
  final avatarStyle = content['avatarStyle'] as int?;
  final wallpaperId = content['wallpaperId'] as String?;
  final edit = PersonalProfileEdit(
    callSign: displayed.callSign,
    visibility: displayed.visibility,
    about:
        introduction != null &&
            (introduction.trim().isNotEmpty || explicitlyEmpty('introduction'))
        ? introduction
        : displayed.about,
    avatarStyle:
        avatarStyle != null &&
            (avatarStyle != 0 || explicitlyEmpty('avatarStyle'))
        ? avatarStyle
        : displayed.avatarStyle,
    wallpaperId:
        wallpaperId != null &&
            wallpaperId.isNotEmpty &&
            (wallpaperId != 'none' || explicitlyEmpty('wallpaperId'))
        ? wallpaperId
        : displayed.wallpaperId,
    moduleLayout: hasSavedProfileLayout(content)
        ? local.moduleLayout
        : explicitlyEmpty('modules')
        ? savedProfileLayout(content)
        : displayed.moduleLayout,
    achievementShowcase:
        (content['achievementShowcase'] as List?)?.isNotEmpty == true
        ? local.showcaseData.achievementShowcase
        : null,
    favoriteShipCodes: codes,
    playStyle: playStyle,
    schedule:
        eligible('schedule') &&
            content['schedule'] != null &&
            (!isDefaultProfileSchedule(schedule) ||
                explicitlyEmpty('schedule')) &&
            !_sameSchedule(displayed, local)
        ? schedule
        : null,
  );
  final differences = personalProfileEditGroups(
    displayed,
    edit,
    fromEditor: false,
  );
  final edits = <String, Map<String, Object?>>{};
  for (final entry in differences.entries) {
    if (!eligible(entry.key) || unresolved.contains(entry.key)) continue;
    if (isCanonicalProfileImportGroup(entry.key, entry.value)) {
      edits[entry.key] = entry.value;
    } else {
      unresolved.add(entry.key);
    }
  }
  return (edits: edits, unresolved: unresolved);
}

bool _sameSchedule(PersonalProfileSnapshot a, PersonalProfileSnapshot b) {
  if (a.timeZoneLabel != b.timeZoneLabel ||
      a.activityRhythm != b.activityRhythm ||
      a.availabilityWindows.length != b.availabilityWindows.length) {
    return false;
  }
  for (var i = 0; i < a.availabilityWindows.length; i++) {
    final left = a.availabilityWindows[i], right = b.availabilityWindows[i];
    if (left.startTime != right.startTime ||
        left.endTime != right.endTime ||
        !setEquals(left.days.toSet(), right.days.toSet())) {
      return false;
    }
  }
  return true;
}

/// One batch per read, with a single replan after an explicit write conflict.
/// An uncertain write keeps the attempted groups visible. A verified write
/// response sets the minimum revision an additional readback may display.
Future<PersonalProfileSnapshot> autoImportPersonalProfile({
  required PersonalProfileSnapshot remote,
  required Map<String, Object?> content,
  required PersonalProfilePresentationWriter? writer,
  required PersonalProfileSnapshot Function(
    PersonalProfileSnapshot remote,
    Set<String> preferLocalGroups,
    bool pending,
  )
  project,
  required Future<PersonalProfileSnapshot?> Function() refresh,
  required bool Function() current,
  required bool Function() sameOwner,
  required PersonalProfileOwnerLock owner,
  required int? readStamp,
  void Function(PersonalProfileSnapshot)? onPending,
  void Function()? onCommitted,
}) async {
  PersonalProfileOwnerOperation? operation;
  var committed = false;
  Future<PersonalProfileSnapshot> run() async {
    for (var attempt = 0; ; attempt++) {
      final displayed = project(remote, const {}, false);
      final presentation = displayed.presentation;
      if (presentation == null || !current()) return displayed;
      final confirmed = owner.confirmationNewerThan(presentation);
      if (confirmed != null) {
        // The read's adapter lease is still tied to the observed revision.
        remote = confirmed;
      }
      final defaults = {
        for (final group in remote.presentation!.origins.keys)
          if (remote.presentation!.canAutoImport(group)) group,
      };
      final baseline = confirmed == null
          ? displayed
          : project(confirmed, const {}, false);
      if (defaults.isEmpty) return baseline;
      final plan = planPersonalProfileAutoImport(
        baseline,
        project(remote, defaults, false),
        content,
      );
      if (plan.unresolved.isNotEmpty) _logImport(plan.unresolved, 'pending');
      final pending = {...plan.edits.keys, ...plan.unresolved};
      if (pending.isEmpty) return baseline;
      if (plan.edits.isEmpty ||
          writer == null ||
          !baseline.allowEditing ||
          confirmed != null ||
          operation == null &&
              (operation = owner.tryImport(readStamp)) == null) {
        return project(remote, pending, true);
      }
      final edits = owner.importEdits(presentation, plan.edits);
      if (edits.isEmpty) return project(remote, pending, true);
      if (attempt == 0) onPending?.call(project(remote, pending, true));

      PersonalProfileActionResult? result;
      try {
        result = await writer.savePresentation(presentation, edits);
      } on Object {
        // A thrown transport error gives no proof that the write was accepted.
      }
      final completed =
          result?.outcome == PersonalProfileActionOutcome.completed;
      final conflict = result?.failureKey == 'profile.error.writeConflict';
      final saved = result?.confirmedProfile;
      final dispatched = result?.presentationDispatched != false;
      final uncertain =
          completed ||
          result == null ||
          result.failureKey == 'profile.error.writeUnconfirmed';
      if (completed && saved != null && sameOwner()) {
        owner.confirm(saved);
        committed = true;
      }
      if (!current()) {
        if (dispatched && !completed && !conflict && sameOwner()) {
          owner.defer(edits, uncertain: uncertain);
        }
        return displayed;
      }
      if (completed || conflict && attempt == 0) {
        final latest = await refresh();
        if (!current()) return displayed;
        if (completed) {
          final readback =
              latest != null &&
                  latest.presentation!.revision > presentation.revision &&
                  edits.keys.every(
                    (group) => latest.presentation!.origins[group] == 'custom',
                  )
              ? latest
              : saved;
          if (readback != null) {
            final remaining = pending
                .where(
                  (group) =>
                      !edits.containsKey(group) &&
                      readback.presentation!.canAutoImport(group),
                )
                .toSet();
            return project(readback, remaining, remaining.isNotEmpty);
          }
        } else if (latest != null &&
            latest.presentation!.revision >= presentation.revision) {
          remote = latest;
          continue;
        }
      }
      if (dispatched && !conflict) owner.defer(edits, uncertain: uncertain);
      _logImport(
        edits.keys,
        conflict
            ? 'conflict'
            : uncertain
            ? 'unconfirmed'
            : 'rejected',
      );
      return project(remote, pending, true);
    }
  }

  try {
    return await run();
  } finally {
    operation?.finish();
    if (committed && sameOwner()) onCommitted?.call();
  }
}

void _logImport(Iterable<String> groups, String status) {
  // Never include page values or exception details.
  developer.log('${groups.join(',')}: $status', name: 'profile.autoImport');
}
