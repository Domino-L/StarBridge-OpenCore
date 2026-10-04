import 'communities_module.dart';
import 'community_workspace_port.dart';

/// Account-owned read coordination, independent of a page's search or section.
/// Only the unfiltered first page is briefly reused; commands never use this.
final class CommunityWorkspaceReads {
  CommunityWorkspaceReads(this.now);
  final DateTime Function() now;
  final _snapshots = <String, ({CommunityWorkspace value, DateTime at})>{};
  final _pending = <(String, String, int), Future<CommunityWorkspace>>{};
  CommunityWorkspacePort? _owner;
  int _epoch = 0;

  CommunityWorkspace? peek(CommunityWorkspacePort port, String target) {
    if (!identical(_owner, port)) return null;
    final entry = _snapshots[target];
    if (entry == null) return null;
    final age = now().difference(entry.at);
    return !age.isNegative && age < const Duration(seconds: 10)
        ? entry.value
        : null;
  }

  Future<CommunityWorkspace> read(
    CommunityWorkspacePort port,
    String target,
    String query,
    int offset, {
    bool reuseFresh = false,
  }) {
    if (_owner != null && !identical(_owner, port)) {
      return Future.error(const CommunityFailure('identityUnavailable'));
    }
    _owner = port;
    query = query.trim();
    final key = (target, query, offset);
    final running = _pending[key];
    if (running != null) return running;
    if (reuseFresh && query.isEmpty && offset == 0) {
      final cached = peek(port, target);
      if (cached != null) return Future.value(cached);
    }
    final epoch = _epoch;
    late final Future<CommunityWorkspace> result;
    result = (() async {
      await Future<void>.value();
      try {
        final value = await port.readWorkspace(target, query, offset);
        if (epoch != _epoch) {
          throw const CommunityFailure('identityUnavailable');
        }
        if (value.targetRef != target ||
            value.query != query ||
            value.offset != offset) {
          throw const CommunityFailure('dataInvalid');
        }
        if (query.isEmpty && offset == 0) {
          _snapshots.remove(target);
          if (_snapshots.length >= 16) _snapshots.remove(_snapshots.keys.first);
          _snapshots[target] = (value: value, at: now());
        }
        return value;
      } catch (_) {
        if (epoch == _epoch) _snapshots.remove(target);
        rethrow;
      } finally {
        if (identical(_pending[key], result)) _pending.remove(key);
      }
    })();
    _pending[key] = result;
    return result;
  }

  void clear() {
    _epoch++;
    _owner = null;
    _pending.clear();
    _snapshots.clear();
  }
}
