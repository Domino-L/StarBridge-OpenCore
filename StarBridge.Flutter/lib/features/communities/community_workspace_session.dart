import 'community_workspace_controller.dart';
import 'community_workspace_port.dart';

/// Recent account-scoped workspaces, independent of the lifetime of their pages.
/// Not a permissions cache: commands still use the Host's current authorization.
/// Least-recently-used eviction bounds retained lists and media across organizations.
final class CommunityWorkspaceSession {
  CommunityWorkspaceSession({DateTime Function()? now, this.capacity = 4})
    : assert(capacity > 0),
      _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final int capacity;
  // Dart maps preserve insertion order; successful obtain moves an entry last.
  final _recent = <String, CommunityWorkspaceController>{};
  CommunityWorkspacePort? _port;
  CommunityWorkspaceController? _current;
  String? _organizationKey;
  final _attemptedRoots = <(String, String)>{};

  CommunityWorkspaceController? _prepareController(
    CommunityWorkspacePort port,
    String targetRef,
    String organizationKey,
  ) {
    // Speculation never replaces an active account or evicts a user's page.
    if (_port != null && !identical(_port, port)) return null;
    _port = port;
    final existing = _recent[organizationKey];
    if (existing != null) {
      return existing.targetRef == targetRef ? existing : null;
    }
    if (_recent.length >= capacity) return null;
    return _recent[organizationKey] = CommunityWorkspaceController(
      port,
      targetRef,
      now: _now,
    );
  }

  Future<void> prefetch(
    CommunityWorkspacePort port,
    String targetRef,
    String organizationKey,
  ) async {
    final model = _prepareController(port, targetRef, organizationKey);
    if (model == null || !_attemptedRoots.add((organizationKey, targetRef))) {
      return;
    }
    await model.prefetch();
  }

  /// Returns after one existing controller batch; no page must be mounted.
  /// A full cache stops speculation instead of churning through memberships.
  Future<bool> prepareNext(
    CommunityWorkspacePort port,
    String targetRef,
    String organizationKey,
    String culture,
  ) async {
    final model = _prepareController(port, targetRef, organizationKey);
    if (model == null) return false;
    if (model.busy || model.renewingReference) return true;
    if (model.workspace == null) {
      if (_attemptedRoots.contains((organizationKey, targetRef))) return false;
      await prefetch(port, targetRef, organizationKey);
      return true;
    }
    // Editors are explicitly foreground-owned; resume when they are left.
    if (model.selectedSection == 'manage') return false;
    if (model.needsSectionPreparation) {
      await model.prepareNextSection(culture);
      return true;
    }
    if (model.needsMediaPreparation) {
      await model.prepareRemainingMedia();
      return true;
    }
    return false;
  }

  CommunityWorkspaceController obtain(
    CommunityWorkspacePort port,
    String targetRef,
    String? organizationKey,
  ) {
    // A different account adapter or an unverified stable identity must never
    // inherit cached private data, even when the display names happen to match.
    if (!identical(_port, port) || organizationKey == null) clear();
    if (_current != null && _organizationKey == null) {
      _current!.dispose();
      _current = null;
    }
    _port = port;
    _organizationKey = organizationKey;
    final current = organizationKey == null
        ? null
        : _recent.remove(organizationKey);
    final result =
        current ?? CommunityWorkspaceController(port, targetRef, now: _now);
    _current = result;
    if (organizationKey != null) {
      _recent[organizationKey] = result;
      while (_recent.length > capacity) {
        final evicted = _recent.keys.first;
        _recent.remove(evicted)!.dispose();
        _attemptedRoots.removeWhere((entry) => entry.$1 == evicted);
      }
    }
    return result;
  }

  void clear() {
    if (_organizationKey == null) _current?.dispose();
    for (final controller in _recent.values) {
      controller.dispose();
    }
    _recent.clear();
    _attemptedRoots.clear();
    _port = null;
    _current = null;
    _organizationKey = null;
  }
}
