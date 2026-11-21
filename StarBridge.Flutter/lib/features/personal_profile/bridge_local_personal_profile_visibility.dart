import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'personal_profile_models.dart';
import 'personal_profile_visibility.dart';

ProfileVisibilityState parseLocalProfileVisibility(
  Map<String, Object?> payload,
  PersonalProfileVisibility? visibility,
) {
  final revision = payload['revision'];
  final scope = payload['visibility'];
  final rawChoices = payload['availableVisibilities'];
  final List<PersonalProfileVisibility> choices;
  if (rawChoices == null) {
    choices = ProfileVisibilityState.legacyVisibilities;
  } else {
    if (rawChoices is! List ||
        rawChoices.isEmpty ||
        rawChoices.length > 5 ||
        rawChoices.toSet().length != rawChoices.length ||
        rawChoices.any(
          (v) => !PersonalProfileVisibility.values.any(
            (known) => known.bridgeValue == v,
          ),
        )) {
      throw const FormatException();
    }
    choices = List.unmodifiable(
      rawChoices.map(
        (v) => PersonalProfileVisibility.fromBridgeValue(v as String),
      ),
    );
  }
  if (revision is! int ||
      revision < 0 ||
      !const {
        'public',
        'friendsAndMainFleet',
        'friendsFleetAndOrganizations',
        'friendsOnly',
        'private',
      }.contains(scope) ||
      !choices.any((v) => v.bridgeValue == scope) ||
      visibility != null && scope != visibility.bridgeValue) {
    throw const FormatException();
  }
  return ProfileVisibilityState(
    revision,
    PersonalProfileVisibility.fromBridgeValue(scope as String),
    availableVisibilities: choices,
  );
}

Future<BridgeEnvelope> requestLocalProfileVisibility(
  BridgeClientSession session,
  BridgeAccountContext owner,
  Duration timeout,
  ProfileVisibilityState? expected,
  PersonalProfileVisibility? visibility,
) => session.request(
  expected == null
      ? 'personalProfile.readVisibility'
      : 'personalProfile.saveVisibility',
  accountContext: owner,
  timeout: timeout,
  payload: {
    'schemaVersion': 1,
    if (expected != null) 'expectedRevision': expected.revision,
    if (visibility != null) 'visibility': visibility.bridgeValue,
  },
);
