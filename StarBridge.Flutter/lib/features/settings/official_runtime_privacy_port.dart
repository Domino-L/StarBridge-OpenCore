/// One optional audience of the existing local privacy editor and publisher.
/// References are Host-issued addresses, never remote authority or consent.
abstract interface class OfficialRuntimePrivacyPort {
  bool get officialRuntimePrivacySupported;
  Stream<void> get officialRuntimePrivacyInvalidations;
  Future<OfficialRuntimePrivacySnapshot> readOfficialRuntimePrivacy();
  Future<OfficialRuntimePrivacySaveReceipt> saveOfficialRuntimePrivacy({
    required OfficialRuntimePrivacySnapshot scope,
    required int expectedRevision,
    required int fields,
    required bool cancelSavedScope,
    OfficialFleetAudience? audience,
  });
}

/// Who may see the main-fleet fields: null is every current member, otherwise
/// the viewer's verified SCM rank value must be at most [maximumRankValue]
/// (1 is the leader; stars = 6 - value). Sent only when the Host supports it.
final class OfficialFleetAudience {
  const OfficialFleetAudience(this.maximumRankValue);
  final int? maximumRankValue;

  static bool valid(Object? value) =>
      value == null || value is int && value >= 1 && value <= 4;
}

enum OfficialPrivacySaveStage {
  idle,
  savingSettings,
  savingOfficial,
  localSaved,
  renewingLease,
  applying,
  applied,
  rejected,
  partial,
  unknown,
}

final class OfficialRuntimePrivacySnapshot {
  const OfficialRuntimePrivacySnapshot({
    required this.state,
    required this.revision,
    required this.fields,
    required this.savedFields,
    required this.savedForCurrentSource,
    required this.canSave,
    required this.canCancel,
    this.choiceRequired = false,
    this.maximumRankValue,
    this.audienceRankSupported = false,
    this.sourceRef,
    this.scopeRef,
    this.contextRef,
    this.cancelContextRef,
  });
  final String state;
  final int revision, fields, savedFields;
  final bool savedForCurrentSource, canSave, canCancel;
  final bool choiceRequired;
  final String? sourceRef, scopeRef, contextRef, cancelContextRef;

  /// The member shared with an earlier main fleet and has not chosen for the
  /// current one. That choice never carries over (it is another audience), so
  /// the fleet page asks again, prefilled (user report 2026-10-29: a member
  /// who switched fleets silently stopped sharing).
  bool get fleetChanged =>
      state == 'available' &&
      canSave &&
      !choiceRequired &&
      !savedForCurrentSource &&
      savedFields != 0 &&
      // An earlier star limit this Host cannot keep is never dropped
      // silently; the settings page asks for an explicit choice instead.
      (maximumRankValue == null || audienceRankSupported);

  /// The saved audience (see [OfficialFleetAudience]) and whether this Host
  /// and relay can store one; older Hosts send neither.
  final int? maximumRankValue;
  final bool audienceRankSupported;

  static OfficialRuntimePrivacySnapshot parse(Map<String, Object?> body) {
    const keys = {
      'schemaVersion',
      'state',
      'sourceRef',
      'scopeRef',
      'contextRef',
      'cancelContextRef',
      'revision',
      'fields',
      'savedFields',
      'savedForCurrentSource',
      'canSave',
      'canCancel',
      'publicationApplied',
      'choiceRequired',
      'maximumRankValue',
      'audienceRankSupported',
    };
    final state = body['state'], revision = body['revision'];
    final source = body['sourceRef'], scope = body['scopeRef'];
    final edit = body['contextRef'], cancel = body['cancelContextRef'];
    bool ref(Object? value) =>
        value == null ||
        value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
    bool mask(Object? value) => value is int && value >= 0 && value <= 15;
    if (body.keys.any((key) => !keys.contains(key)) ||
        body['schemaVersion'] != 1 ||
        state != 'available' && state != 'unavailable' ||
        revision is! int ||
        revision < 0 ||
        !mask(body['fields']) ||
        !mask(body['savedFields']) ||
        body['savedForCurrentSource'] is! bool ||
        body['canSave'] is! bool ||
        body['canCancel'] is! bool ||
        body['publicationApplied'] != false ||
        !ref(scope) ||
        !ref(edit) ||
        !ref(cancel) ||
        (state == 'available'
            ? source is! String ||
                  !RegExp(r'^officialFleet:[1-9][0-9]{0,18}$')
                      .hasMatch(source) ||
                  scope == null ||
                  edit == null
            : source != null ||
                  scope != null ||
                  edit != null ||
                  body['canSave'] == true ||
                  body['savedForCurrentSource'] == true) ||
        body.containsKey('choiceRequired') && body['choiceRequired'] is! bool ||
        !OfficialFleetAudience.valid(body['maximumRankValue']) ||
        body.containsKey('audienceRankSupported') &&
            body['audienceRankSupported'] is! bool ||
        body['choiceRequired'] == true &&
            (state != 'available' ||
                body['canSave'] != true ||
                body['savedForCurrentSource'] != false ||
                body['savedFields'] != 0 ||
                body['canCancel'] != false ||
                body['fields'] != 15) ||
        body['savedForCurrentSource'] == false &&
            body['fields'] != 0 &&
            body['choiceRequired'] != true ||
        body['savedForCurrentSource'] == true &&
            body['fields'] != body['savedFields'] ||
        body['canCancel'] == true &&
            (cancel == null || body['savedFields'] == 0)) {
      throw const FormatException('Invalid official privacy scope.');
    }
    return OfficialRuntimePrivacySnapshot(
      state: state as String,
      revision: revision,
      fields: body['fields'] as int,
      savedFields: body['savedFields'] as int,
      savedForCurrentSource: body['savedForCurrentSource'] as bool,
      canSave: body['canSave'] as bool,
      canCancel: body['canCancel'] as bool,
      choiceRequired: body['choiceRequired'] == true,
      maximumRankValue: body['maximumRankValue'] as int?,
      audienceRankSupported: body['audienceRankSupported'] == true,
      sourceRef: source as String?,
      scopeRef: scope as String?,
      contextRef: edit as String?,
      cancelContextRef: cancel as String?,
    );
  }
}

final class OfficialRuntimePrivacySaveReceipt {
  const OfficialRuntimePrivacySaveReceipt(
    this.revision,
    this.fields, [
    this.maximumRankValue,
  ]);
  final int revision, fields;
  final int? maximumRankValue;
}
