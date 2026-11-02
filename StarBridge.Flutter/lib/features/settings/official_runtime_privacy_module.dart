import '../../platform/bridge/bridge_client_session.dart';
import 'official_runtime_privacy_port.dart';
import 'local_privacy_port.dart';
import 'privacy_publication_port.dart';

enum OfficialPrivacyRefreshResult { ready, conflict, unavailable, retired }

/// The optional audience's draft and opaque scope lifecycle. Publication and
/// the common revision transaction remain owned by LocalPrivacyController.
final class OfficialRuntimePrivacyModule {
  OfficialRuntimePrivacyModule(LocalPrivacyPort port)
    : _port = port is OfficialRuntimePrivacyPort
          ? port as OfficialRuntimePrivacyPort
          : null;

  final OfficialRuntimePrivacyPort? _port;
  OfficialRuntimePrivacySnapshot? scope;
  int? draftFields;

  /// The audience draft; only meaningful when the scope supports audiences.
  int? draftAudience;
  bool cancelSavedScope = false, failed = false, reading = false;
  bool _explicitChoice = false;
  int epoch = 0;
  OfficialPrivacySaveStage stage = OfficialPrivacySaveStage.idle;

  bool get supported => _port?.officialRuntimePrivacySupported == true;
  bool get dirty =>
      scope != null &&
      (cancelSavedScope ||
          _explicitChoice && (scope!.choiceRequired || scope!.fleetChanged) ||
          draftFields != null && draftFields != scope!.fields ||
          scope!.audienceRankSupported &&
              draftAudience != scope!.maximumRankValue);
  bool get canEdit => !reading && !failed && scope?.canSave == true;
  bool get canCancel => !reading && !failed && scope?.canCancel == true;

  void retire({required bool saving}) {
    ++epoch;
    scope = null;
    draftFields = draftAudience = null;
    cancelSavedScope = failed = reading = false;
    _explicitChoice = false;
    stage = saving
        ? OfficialPrivacySaveStage.unknown
        : OfficialPrivacySaveStage.idle;
  }

  Future<OfficialPrivacyRefreshResult> refresh(int expectedRevision) async {
    final ownerEpoch = epoch, prior = scope;
    reading = true;
    try {
      final next = await _port!.readOfficialRuntimePrivacy();
      if (ownerEpoch != epoch) return OfficialPrivacyRefreshResult.retired;
      if (next.revision != expectedRevision) {
        _clearFailed();
        return OfficialPrivacyRefreshResult.conflict;
      }
      final same =
          prior?.scopeRef == next.scopeRef &&
          prior?.sourceRef == next.sourceRef;
      // An unchanged scope may renew without discarding a new local draft.
      // A new opaque epoch never inherits the previous audience's fields.
      if (!same || !dirty) {
        draftFields = next.fields;
        draftAudience = next.maximumRankValue;
        cancelSavedScope = false;
        _explicitChoice = false;
      }
      scope = next;
      failed = false;
      return OfficialPrivacyRefreshResult.ready;
    } catch (_) {
      if (ownerEpoch != epoch) return OfficialPrivacyRefreshResult.retired;
      _clearFailed();
      return OfficialPrivacyRefreshResult.unavailable;
    } finally {
      if (ownerEpoch == epoch) reading = false;
    }
  }

  void _clearFailed() {
    scope = null;
    draftFields = draftAudience = null;
    cancelSavedScope = false;
    failed = true;
  }

  void edit(int fields) {
    _explicitChoice = true;
    draftFields = fields;
    cancelSavedScope = false;
    stage = OfficialPrivacySaveStage.idle;
  }

  void editAudience(int? maximumRankValue) {
    if (!OfficialFleetAudience.valid(maximumRankValue)) return;
    _explicitChoice = true;
    draftAudience = maximumRankValue;
    cancelSavedScope = false;
    stage = OfficialPrivacySaveStage.idle;
  }

  /// What a save sends: the draft when this scope stores audiences.
  OfficialFleetAudience? get submitAudience =>
      scope?.audienceRankSupported == true && !cancelSavedScope
      ? OfficialFleetAudience(draftAudience)
      : null;

  void chooseCancel() {
    draftFields = 0;
    cancelSavedScope = true;
    stage = OfficialPrivacySaveStage.idle;
  }

  void discard() {
    _explicitChoice = false;
    draftFields = scope?.fields;
    draftAudience = scope?.maximumRankValue;
    cancelSavedScope = false;
    stage = OfficialPrivacySaveStage.idle;
  }

  void acceptSaved(OfficialRuntimePrivacySnapshot next) {
    _explicitChoice = false;
    scope = next;
    draftFields = next.fields;
    draftAudience = next.maximumRankValue;
    cancelSavedScope = failed = false;
  }

  void completeSave(PrivacyPublicationView? confirmed, int revision) {
    stage =
        confirmed?.revision == revision &&
            const {'applied', 'withdrawn'}.contains(confirmed?.state)
        ? OfficialPrivacySaveStage.applied
        : OfficialPrivacySaveStage.localSaved;
  }

  void failSave(
    Object error, {
    required bool committedOfficial,
    required bool committedOrdinary,
    required bool sentOfficial,
  }) {
    final rejected =
        error is BridgeClientException &&
        const {
          'privacy_local.conflict',
          'privacy_local.changed',
          'privacy_local.refresh_required',
          'privacy_local.invalid_request',
          'host.capability_missing',
        }.contains(error.code);
    stage = committedOfficial
        ? OfficialPrivacySaveStage.localSaved
        : sentOfficial && !rejected
        ? OfficialPrivacySaveStage.unknown
        : committedOrdinary
        ? OfficialPrivacySaveStage.partial
        : OfficialPrivacySaveStage.rejected;
  }
}
