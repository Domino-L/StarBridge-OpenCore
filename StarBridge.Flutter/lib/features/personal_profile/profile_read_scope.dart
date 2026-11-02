import '../account/account_models.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_request_operation.dart';

/// An observed domain-read owner, never an edit lease or authentication source.
final class ProfileReadScope {
  const ProfileReadScope(this.generation, this.route);
  factory ProfileReadScope.fromResponse(
    BridgeEnvelope root,
    BridgeEnvelope response,
    int activeGeneration,
  ) => _capture(root, response, activeGeneration, 'personalProfile.getSelf');
  factory ProfileReadScope.fromLocalResponse(
    BridgeEnvelope root,
    BridgeEnvelope response,
    int activeGeneration,
  ) => _capture(root, response, activeGeneration, 'personalProfile.localRead');
  static ProfileReadScope _capture(
    BridgeEnvelope root,
    BridgeEnvelope response,
    int activeGeneration,
    String responseName,
  ) {
    if (root.sessionGeneration != activeGeneration ||
        response.sessionGeneration != activeGeneration) {
      throw BridgeStaleGenerationException(
        root.sessionGeneration,
        activeGeneration,
      );
    }
    final owner = root.accountContext, observed = response.accountContext;
    if (root.payload['schemaVersion'] is! int ||
        root.payload['schemaVersion'] != 1 ||
        response.payload['schemaVersion'] is! int ||
        response.payload['schemaVersion'] != 1 ||
        root.name != 'account.getCurrent' ||
        response.name != responseName ||
        owner == null ||
        observed == null ||
        (owner.environment, owner.authority, owner.subject) !=
            (observed.environment, observed.authority, observed.subject)) {
      throw const BridgeFormatException(
        'Profile response ownership is not confirmed.',
      );
    }
    final route = AccountRoute(
      environment: owner.environment,
      authority: owner.authority,
      subject: owner.subject,
    );
    if (!route.isComplete) {
      throw const BridgeFormatException('Profile owner is incomplete.');
    }
    return ProfileReadScope(activeGeneration, route);
  }

  static void requireSchema(Map<String, Object?> payload) {
    if (payload['schemaVersion'] is! int || payload['schemaVersion'] != 1) {
      throw const BridgeFormatException(
        'Personal profile payload schema is incompatible.',
      );
    }
  }

  final int generation;
  final AccountRoute route;
  bool sameOwner(ProfileReadScope? other) =>
      other != null &&
      generation == other.generation &&
      (route.environment, route.authority, route.subject) ==
          (other.route.environment, other.route.authority, other.route.subject);
  bool matches(AccountDisplayHandoff handoff) =>
      generation == handoff.generation && handoff.matchesRoute(route);
}

abstract interface class ProfileReadScopeOwner {
  ProfileReadScope? get readScope;
}

/// Read scheduling evidence only; it conveys no identity or editing authority.
enum ProfileReadPhase {
  reading,
  available,
  transientFailure,
  unavailable,
  invalidated,
}

final class ProfileReadObservation {
  const ProfileReadObservation(
    this.generation,
    this.phase, {
    this.accountAdvance,
  });
  final int? generation;
  final ProfileReadPhase phase;
  final ProfileReadAccountAdvance? accountAdvance;
}

abstract interface class ProfileReadObservationOwner {
  ProfileReadObservation? get readObservation;
}

abstract interface class ProfileReadGenerationOwner {
  int get activeReadGeneration;
}

/// Cause of a retired read, not proof of identity, data or permission.
final class ProfileReadAccountAdvance {
  const ProfileReadAccountAdvance(this.sourceGeneration, this.generation);
  final int sourceGeneration, generation;
  static ProfileReadAccountAdvance? observe(
    BridgeEnvelope event,
    int previousGeneration,
    int activeGeneration,
  ) =>
      previousGeneration >= 0 &&
          event.messageType == 'event' &&
          event.name == 'account.changed' &&
          event.payload['schemaVersion'] is int &&
          event.payload['schemaVersion'] == 1 &&
          event.sequence != null &&
          event.sequence! >= 0 &&
          event.sessionGeneration == previousGeneration + 1 &&
          event.sessionGeneration == activeGeneration
      ? ProfileReadAccountAdvance(previousGeneration, activeGeneration)
      : null;
  bool matches(AccountDisplayHandoff proof) =>
      proof.sourceGeneration == sourceGeneration &&
      proof.generation == generation;
}

abstract interface class ProfileReadAccountAdvanceOwner {
  ProfileReadAccountAdvance? get readAccountAdvance;
}
