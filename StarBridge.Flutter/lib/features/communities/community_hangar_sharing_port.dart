abstract interface class CommunityHangarSharingPort {
  Stream<void> get invalidations;
  bool get hangarSharingAvailable;
  Future<CommunityHangarSharing> readHangarSharing();
  Future<CommunityHangarSharingOutcome> saveHangarSharing(
    String editRef,
    List<String> selectedRefs,
  );
}

final class CommunityHangarSharingOutcome {
  const CommunityHangarSharingOutcome(this.status, {this.error});
  final String status;
  final String? error;
  factory CommunityHangarSharingOutcome.parse(Map<String, Object?> payload) {
    final status = payload['status'];
    final error = payload['error'];
    if (payload['schemaVersion'] != 1 ||
        !const {'accepted', 'rejected', 'unknown'}.contains(status) ||
        error != null && (error is! String || error.length > 128) ||
        status == 'accepted' && error != null) {
      throw const FormatException();
    }
    return CommunityHangarSharingOutcome(
      status as String,
      error: error as String?,
    );
  }
}

final class CommunityHangarOption {
  const CommunityHangarOption(this.targetRef, this.name, this.selected);
  final String targetRef, name;
  final bool selected;
}

/// Authorized audience editor. Host updates a complete local inventory automatically.
/// Uninitialized/partial inventory is retained remotely; withdrawal never requires a scan.
final class CommunityHangarSharing {
  const CommunityHangarSharing._(
    this.editRef,
    this.usesExplicitTargets,
    this.options,
  );
  static const maximumTargets = 64;
  final String editRef;
  final bool usesExplicitTargets;
  final List<CommunityHangarOption> options;

  factory CommunityHangarSharing.parse(Map<String, Object?> payload) {
    final explicit = payload['usesExplicitTargets'];
    final rows = payload['options'];
    final edit = payload['editRef'];
    if (payload['schemaVersion'] != 1 ||
        payload['maximumTargets'] != maximumTargets ||
        explicit is! bool ||
        rows is! List ||
        rows.length > 4000 ||
        !validReference(edit)) {
      throw const FormatException();
    }
    final seen = <String>{};
    final options = <CommunityHangarOption>[];
    var selectedCount = 0;
    for (final row in rows) {
      if (row is! Map) throw const FormatException();
      final reference = row['targetRef'];
      final name = row['name'];
      final selected = row['selected'];
      if (!validReference(reference) ||
          !seen.add(reference as String) ||
          name is! String ||
          name.length > 512 ||
          name.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
          selected is! bool) {
        throw const FormatException();
      }
      if (selected) selectedCount++;
      options.add(CommunityHangarOption(reference, name, selected));
    }
    if (selectedCount > maximumTargets || !explicit && selectedCount != 0) {
      throw const FormatException();
    }
    return CommunityHangarSharing._(
      edit as String,
      explicit,
      List.unmodifiable(options),
    );
  }

  static bool validReference(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
}
