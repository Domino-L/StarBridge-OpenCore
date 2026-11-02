import '../../features/onboarding/onboarding_models.dart';
import '../../features/onboarding/onboarding_port.dart';
import 'startup_prompt_queue.dart';

/// First-use display policy only. Host classifies install/use history; this
/// Module never treats a missing Flutter marker or a new version as a new user.
/// Composition must bind isCurrent to its Host/account epoch and gate other
/// optional first-use prompts while blocksOptionalPrompts is true.
final class FirstUseOnboardingFlow {
  FirstUseOnboardingFlow({
    required this.port,
    required this.queue,
    required this.ready,
    required this.isCurrent,
    required this.show,
  });
  final OnboardingPort port;
  final StartupPromptQueue queue;
  final bool Function() ready, isCurrent;
  final Future<void> Function() show;
  final Object _key = Object();
  int _epoch = 0;
  bool _disposed = false, _shown = false, _pending = false, _showing = false;

  bool get blocksOptionalPrompts => _pending || _showing;

  /// Result of the latest Host eligibility read: null before the first read,
  /// false after a failed read. Startup/close choices defer to setup while true.
  bool? lastEligible;

  /// Retire stale automatic eligibility without consuming a manual choice or
  /// marking setup complete. A later healthy read can offer setup again.
  void deferAutomaticEntry() {
    if (_disposed) return;
    _epoch++;
    _pending = false;
    queue.cancel(_key);
  }

  void consumeManualEntry() {
    if (_disposed) return;
    _epoch++;
    _pending = false;
    _shown = true;
    queue.cancel(_key);
  }

  static bool eligible(OnboardingReply reply) =>
      reply.facts.available &&
      reply.facts.canSave &&
      reply.facts.eligibility == OnboardingEligibility.firstUse &&
      reply.completed == null;

  Future<void> check() async {
    if (_disposed || _shown || _showing) return;
    final epoch = ++_epoch;
    _pending = false;
    queue.cancel(_key);
    try {
      final reply = await port.read();
      if (_disposed || epoch != _epoch || !isCurrent()) return;
      lastEligible = eligible(reply);
      if (!lastEligible!) return;
      _pending = true;
      queue.enqueue(
        _key,
        priority: 50,
        eligible: () => !_disposed && epoch == _epoch && isCurrent() && ready(),
        show: () async {
          _pending = false;
          _showing = true;
          try {
            // Recheck after foreground/manual-route deferral. Nothing is written.
            final current = await port.read();
            if (_disposed ||
                epoch != _epoch ||
                !isCurrent() ||
                !ready() ||
                queue.hasBlockingRoute ||
                !eligible(current)) {
              return;
            }
            _shown = true;
            await show();
          } on Object {
            // Unknown/read failure does not become first-use eligibility.
          } finally {
            _showing = false;
          }
        },
      );
    } on Object {
      // Existing/unknown users are not forced into setup on a failed read.
      if (!_disposed && epoch == _epoch) lastEligible = false;
    }
  }

  void dispose() {
    _disposed = true;
    _epoch++;
    _pending = false;
    queue.cancel(_key);
  }
}
