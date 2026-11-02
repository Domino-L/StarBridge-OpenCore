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
