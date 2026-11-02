import '../../platform/bridge/bridge_client_session.dart';
import 'onboarding_models.dart';

/// Display classification only. No file path, account context or write route.
final class FirstUseStartupObservation {
  const FirstUseStartupObservation(
    this.scope,
    this.eligibility,
    this.reason,
    this.hasProgress,
  );
  final int scope;
  final OnboardingEligibility eligibility;
  final String reason;
  final bool hasProgress;
}

final class BridgeFirstUseStartup {
  BridgeFirstUseStartup(this.session);
  static const capability = 'onboarding.startup.v1';
  final BridgeClientSession session;
  bool get supported => session.hostCapabilities.contains(capability);
  Future<FirstUseStartupObservation?> read() async {
    if (!supported) return null;
    final generation = session.activeGeneration;
    final reply = await session.request(
      'onboarding.startup.read',
      payload: const {'schemaVersion': 1},
    );
    if (!supported ||
        generation != session.activeGeneration ||
        reply.sessionGeneration != generation ||
        reply.accountContext != null) {
      throw StateError('Startup observation is no longer current.');
    }
    return parse(reply.payload, generation);
  }

  static FirstUseStartupObservation parse(Map<String, Object?> raw, int scope) {
    const names = {'schemaVersion', 'eligibility', 'reason', 'hasProgress'};
    final eligibility = OnboardingEligibility.values
        .where((e) => e.name == raw['eligibility'])
        .singleOrNull;
    final reason = raw['reason'], progress = raw['hasProgress'];
    const pairs = {
      OnboardingEligibility.firstUse: {'freshInstallation', 'resume'},
      OnboardingEligibility.returning: {
        'previousUse',
        'completedSetup',
        'updateInstallation',
      },
      OnboardingEligibility.unknown: {
        'unreadableHistory',
        'unreadableProgress',
        'installationUnknown',
      },
    };
    if (scope < 0 ||
        raw.length != names.length ||
        !names.every(raw.containsKey) ||
        raw['schemaVersion'] is! int ||
        raw['schemaVersion'] != 1 ||
        eligibility == null ||
        reason is! String ||
        progress is! bool ||
        !pairs[eligibility]!.contains(reason) ||
        progress != (reason == 'resume')) {
      throw const FormatException('Invalid startup observation.');
    }
    return FirstUseStartupObservation(scope, eligibility, reason, progress);
  }
}
