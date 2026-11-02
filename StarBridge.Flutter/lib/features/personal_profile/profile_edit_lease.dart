import '../../platform/bridge/bridge_envelope.dart';
import 'personal_profile_presentation.dart';

/// A revision belongs to one successfully read account session, never to the
/// adapter globally. Reauthentication also invalidates the previous edit lease.
final class ProfileEditLease {
  const ProfileEditLease(
    this.context,
    this.generation,
    this.revision, [
    this.presentation,
  ]);

  final BridgeAccountContext context;
  final int generation;
  final int revision;
  final PersonalProfilePresentation? presentation;

  bool matches(BridgeEnvelope account) =>
      account.sessionGeneration == generation &&
      account.accountContext?.environment == context.environment &&
      account.accountContext?.authority == context.authority &&
      account.accountContext?.subject == context.subject;
}
