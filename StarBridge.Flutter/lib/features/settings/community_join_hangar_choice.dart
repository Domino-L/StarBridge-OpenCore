import '../communities/community_hangar_sharing_port.dart';
import 'community_sharing.dart';

/// Reuses the existing account-bound editor, changing only this audience.
/// Each explicit retry obtains fresh authority; an uncertain PUT is not replayed.
Future<bool> saveJoinedCommunityHangarChoice({
  required CommunityHangarSharingPort port,
  required CommunitySharingTarget target,
  required bool share,
  required Future<bool> Function() membershipCurrent,
}) async {
  try {
    if (!port.hangarSharingAvailable || !await membershipCurrent()) {
      return false;
    }
    final editor = await port.readHangarSharing();
    if (!await membershipCurrent()) return false;
    final matches = editor.options
        .where(
          (row) =>
              row.communityCode?.toLowerCase() == target.code.toLowerCase(),
        )
        .toList();
    if (matches.length != 1) return false;
    final selected = editor.options
        .where((row) => row.selected)
        .map((row) => row.targetRef)
        .toSet();
    final reference = matches.single.targetRef;
    if (editor.usesExplicitTargets && selected.contains(reference) == share) {
      return true;
    }
    if (share) {
      selected.add(reference);
    } else {
      selected.remove(reference);
    }
    if (selected.length > CommunityHangarSharing.maximumTargets) return false;
    return (await port.saveHangarSharing(
              editor.editRef,
              selected.toList(),
            )).status ==
            'accepted' &&
        await membershipCurrent();
  } on Object {
    return false;
  }
}
