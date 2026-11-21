import 'dart:async';
import 'dart:convert';

import '../../features/tools/catalog_recent.dart';
import '../../platform/bridge/bridge_client_session.dart';

/// Resolves the same Host-owned local account context as mission records.
/// No UI profile field is used as an owner; no OAuth or SCM request is added.
final class CatalogRecentSession {
  CatalogRecentSession(this.session, this.recent) {
    recent.prepare = resolve;
    _remove = session.observeGenerationChanges((_, _) {
      _resolvedGeneration = null;
      _pending = null;
      unawaited(recent.switchOwner(null, retireScope: true));
    });
  }
  final BridgeClientSession session;
  final CatalogRecent recent;
  late final void Function() _remove;
  int? _resolvedGeneration;
  Future<void>? _pending;
  bool _disposed = false;
  Future<void> resolve() {
    if (_disposed || _resolvedGeneration == session.activeGeneration) {
      return Future.value();
    }
    return _pending ??= Future<void>.microtask(_resolve);
  }

  Future<void> _resolve() async {
    final generation = session.activeGeneration;
    try {
      final response = await session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      if (_disposed ||
          generation != session.activeGeneration ||
          generation != response.sessionGeneration) {
        return;
      }
      if (response.status != 'ok' || response.payload['schemaVersion'] != 1) {
        await recent.switchOwner(null);
        return;
      }
      final owner = response.accountContext;
      await recent.switchOwner(
        owner == null
            ? null
            : jsonEncode([owner.environment, owner.authority, owner.subject]),
      );
      if (!_disposed && generation == session.activeGeneration) {
        _resolvedGeneration = generation;
      }
    } catch (_) {
      if (!_disposed && generation == session.activeGeneration) {
        await recent.switchOwner(null);
      }
    } finally {
      if (!_disposed && generation == session.activeGeneration) _pending = null;
    }
  }

  void dispose() {
    _disposed = true;
    _remove();
    recent.prepare = null;
    recent.dispose();
  }
}
