import 'dart:convert';

import '../../platform/bridge/bridge_client_session.dart';
import 'community_member_sharing.dart';
import 'community_sharing.dart';
import 'local_privacy_settings.dart';

bool privacySettingsDiffer(
  LocalPrivacySettings? draft,
  LocalPrivacySettings? saved,
) =>
    draft != null &&
    jsonEncode(draft.toJson()) !=
        jsonEncode((saved ?? LocalPrivacySettings.editorDefaults).toJson());

bool hasPendingCommunityChoices(
  LocalPrivacySettings? saved,
  CommunitySharingTargets? targets, {
  required bool supported,
  required bool failed,
}) {
  if (!supported || saved == null || targets == null || failed) return false;
  return targets.communities.any(
    (target) => !(saved.communities?.any(target.matches) ?? false),
  );
}

/// Reads one coherent roster. The controller retains authority and lifecycle.
Future<List<CommunitySharingMember>> readCommunityMemberSnapshot(
  CommunityMemberSharingPort port,
  CommunitySharingScope scope, {
  required void Function() requireCurrent,
}) async {
  // A revision race restarts the whole snapshot once; never mix two rosters.
  for (var attempt = 0; attempt < 2; attempt++) {
    final rows = <CommunitySharingMember>[];
    String? revision;
    try {
      do {
        requireCurrent();
        final page = await port.readCommunityMembers(
          scope,
          offset: rows.length,
          revision: revision,
        );
        requireCurrent();
        revision = page.revision;
        rows.addAll(page.members);
        if (rows.length == page.total) {
          if (rows.map((row) => row.accountId.toLowerCase()).toSet().length !=
              rows.length) {
            throw const FormatException('Duplicate members across pages.');
          }
          return List.unmodifiable(rows);
        }
      } while (rows.length < 100000);
      throw const FormatException('Member directory exceeds limit.');
    } on BridgeClientException catch (error) {
      if (error.code != 'privacy_publication.members_changed' || attempt == 1) {
        rethrow;
      }
    }
  }
  throw const FormatException('Member directory changed.');
}

bool _sameCode(CommunitySharingScope scope, String code) =>
    scope.code.toLowerCase() == code.toLowerCase();

CommunitySharingScope? privacyScopeIn(
  LocalPrivacySettings? settings,
  String code,
) => settings?.communities?.where((s) => _sameCode(s, code)).firstOrNull;

List<CommunitySharingScope> privacyScopesReplacing(
  List<CommunitySharingScope>? scopes,
  String code,
  CommunitySharingScope? value,
) => [
  for (final scope in scopes ?? const <CommunitySharingScope>[])
    if (!_sameCode(scope, code)) scope,
  ?value,
];

/// An absent record has no consent or grants, regardless of editor suggestions.
LocalPrivacySettings get emptyPrivacySettings => LocalPrivacySettings(
  publicationEnabled: false,
  fleetFields: 0,
  fleetAdministratorsCanView: false,
  fleetAllMembersCanView: false,
  fleetVisibilityGroupIds: const [],
  roomFields: 0,
  roomAllMembersCanView: false,
  communities: const [],
);

/// Save one organization's choice over the saved (or zero-grant) baseline.
LocalPrivacySettings scopedPrivacySubmission(
  LocalPrivacySettings draft,
  LocalPrivacySettings? saved,
  String? code,
) {
  if (code == null) return draft;
  final base = saved ?? emptyPrivacySettings;
  final choice = privacyScopeIn(draft, code);
  return base.copyWith(
    communities: privacyScopesReplacing(base.communities, code, choice),
  );
}

/// On the first scoped save, replace untouched editor suggestions with the
/// actual saved baseline. Only values changed by the viewer remain pending.
/// Once a saved baseline exists, the other draft fields already represent it.
LocalPrivacySettings rebaseFirstPrivacyEdits(
  LocalPrivacySettings result,
  LocalPrivacySettings kept,
  LocalPrivacySettings? previouslySaved,
) {
  if (previouslySaved != null) return kept;
  Map<String, Object?> keepChanged(
    Map<String, Object?> actual,
    Map<String, Object?> edited,
    Map<String, Object?> baseline,
  ) => {
    ...actual,
    for (final entry in edited.entries)
      if (entry.value is Map && baseline[entry.key] is Map)
        entry.key: keepChanged(
          (actual[entry.key] as Map).cast<String, Object?>(),
          (entry.value as Map).cast<String, Object?>(),
          (baseline[entry.key] as Map).cast<String, Object?>(),
        )
      else if (jsonEncode(entry.value) != jsonEncode(baseline[entry.key]))
        entry.key: entry.value,
  };
  return LocalPrivacySettings.fromJson(
    keepChanged(
      result.toJson(),
      kept.toJson(),
      LocalPrivacySettings.editorDefaults.toJson(),
    ),
  );
}

/// After that save: the confirmed organization and only real remaining edits.
LocalPrivacySettings? keepEdits(
  LocalPrivacySettings? result,
  LocalPrivacySettings kept,
  LocalPrivacySettings? previouslySaved,
  String? code,
) {
  if (code == null || result == null) return result;
  final rebased = rebaseFirstPrivacyEdits(result, kept, previouslySaved);
  return rebased.copyWith(
    communities: privacyScopesReplacing(
      rebased.communities,
      code,
      privacyScopeIn(result, code),
    ),
  );
}

/// Replays names changed while a target read was in flight onto its result.
CommunitySharingTargets withTargetNames(
  CommunitySharingTargets targets,
  Map<String, String> names,
) => names.entries.fold(
  targets,
  (all, name) => all.renamed(name.key, name.value),
);

bool communityScopesUnavailable(Object error) =>
    error is BridgeClientException &&
    error.code == 'privacy_publication.community_scopes_unavailable';
