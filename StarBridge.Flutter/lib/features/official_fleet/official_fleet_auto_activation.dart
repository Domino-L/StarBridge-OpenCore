import 'dart:math' as math;

import '../common/organization_governance_port.dart';

/// Enables a rank 1 member's management on entering the main fleet (user
/// 2026-10-31: "改自动应该是最好的"), with no visible step. Only the relay's
/// explicit "never activated" answer starts it: someone who revoked, and any
/// answer this client cannot read, stays manual. The relay still decides.
final class OfficialFleetAutoActivation {
  OfficialFleetAutoActivation({
    required this.port,
    required this.context,
    required this.onActivated,
    String Function()? operationId,
  }) : _operationId = operationId ?? _newOperationId;

  static const neverActivated = 'rootNeverActivated';
  static const _maximumReads = 3;

  final OrganizationGovernancePort Function() port;

  /// The account context and fleet now on screen. A new account context is a
  /// new member: it gets its own check, and an older one may not write.
  final (int, String?) Function() context;

  /// The rights just changed: everything derived from them reads again.
  final void Function(OrganizationGovernanceContext authority) onActivated;
  final String Function() _operationId;
  final _reads = <(int, String), int>{};
  final _settled = <(int, String)>{};
  bool _busy = false, _closed = false;

  /// At most one write per member per fleet per run, whatever comes back. A
  /// failed read is tried again on a later visit, up to [_maximumReads].
  Future<void> enter() async {
    final (revision, source) = context();
    if (_closed || source == null || _busy) return;
    final key = (revision, source);
    final governance = port();
    if (_settled.contains(key) ||
        (_reads[key] ?? 0) >= _maximumReads ||
        !governance.available) {
      return;
    }
    bool current() => !_closed && context() == key;
    _busy = true;
    _reads[key] = (_reads[key] ?? 0) + 1;
    try {
      final read = await governance.read(source);
      if (!current()) return;
      _settled.add(key);
      final activate = read.rootControls
          .where((control) => control.key == 'activate')
          .firstOrNull;
      if (activate?.state != OrganizationDecisionState.allowed ||
          activate?.reason != neverActivated ||
          !governance.canActivate) {
        return;
      }
      final outcome = await governance.setActivation(
        source,
        active: true,
        operationId: _operationId(),
        expectedPolicyRevision: read.policyRevision,
      );
      if (!current()) return;
      if (outcome.state != 'accepted' && outcome.state != 'duplicate') return;
      final after = await governance.read(source);
      if (current()) onActivated(after);
    } on Object {
      // Quiet: the page keeps its manual button and this never blocks anything.
    } finally {
      _busy = false;
    }
  }

  void close() => _closed = true;

  static String _newOperationId() {
    final random = math.Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }
}
