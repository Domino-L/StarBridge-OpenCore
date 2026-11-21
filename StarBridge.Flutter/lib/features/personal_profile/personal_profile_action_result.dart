import 'package:flutter/foundation.dart';

import 'personal_profile_models.dart' show PersonalProfileSnapshot;

enum PersonalProfileActionOutcome { completed, rejected, failed }

@immutable
final class PersonalProfileActionResult {
  const PersonalProfileActionResult(
    this.outcome, {
    this.failureKey,
    this.requiresReload = false,
    this.messageKey,
    this.confirmedProfile,
    this.presentationDispatched,
  });

  final PersonalProfileActionOutcome outcome;
  final String? failureKey;

  /// Lease consumed or stale: keep the draft, never resubmit it until re-edited.
  final bool requiresReload;
  final String? messageKey;

  /// The versioned writer's verified response, scoped to the completed write.
  final PersonalProfileSnapshot? confirmedProfile;

  /// A definite preflight stop does not consume an automatic import attempt.
  final bool? presentationDispatched;
}
