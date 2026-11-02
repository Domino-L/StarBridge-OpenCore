import 'dart:async';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_workspace_port.dart';

/// A bounded, independent read of the authorized directory, never the selected
/// member-search page and never presence inferred from messages/game details.
class CommunityOnlineMembersController extends ChangeNotifier {
  CommunityOnlineMembersController(this.port, this.targetRef) {
    _subscription = port.invalidations.listen((_) {
      invalidated = true;
      _epoch++;
      members = [];
      loading = false;
      error = 'identityUnavailable';
      notifyListeners();
    });
  }
  final CommunityWorkspacePort port;
  String targetRef;
  late final StreamSubscription<void> _subscription;

  /// The caller verified the same organization on the same port. Future
  /// reads use the new handle; the shown list stays until they land.
  void renewTarget(String next) {
    if (_closed || next == targetRef) return;
    targetRef = next;
    unawaited(refresh(silent: true));
  }

  List<CommunityWorkspaceMember> members = [];
  bool loading = false, invalidated = false, _closed = false;
  bool _loaded = false, _silentRead = false;
  bool get showProgress => loading && !_silentRead;
  String? error;
  int scanned = 0, total = 0, _epoch = 0;
  int? next;
  bool get partial => showProgress || next != null;

  static bool visibleOnline(CommunityWorkspaceMember member) =>
      member.publicOnline;

  Future<void> refresh({bool silent = false}) => _load(false, silent: silent);
  Future<void> loadMore() => _load(true);
  Future<void> _load(bool more, {bool silent = false}) async {
    if (_closed || invalidated || loading || more && next == null) return;
    final epoch = ++_epoch;
    // One round reads one reference; a renewal meanwhile is re-read after
    // it, never compared against this round's pages.
    final readTarget = targetRef;
    loading = true;
    _silentRead = silent && _loaded;
    error = null;
    var readScanned = more ? scanned : 0, readTotal = more ? total : 0;
    int? readNext = more ? next : 0;
    notifyListeners();
    try {
      var rows = more ? [...members] : <CommunityWorkspaceMember>[];
      for (var pageIndex = 0; pageIndex < 10; pageIndex++) {
        final offset = readNext ?? 0;
        final page = await port.readWorkspace(readTarget, '', offset);
        if (_closed || invalidated || epoch != _epoch) return;
        if (page.targetRef != readTarget ||
            page.query.isNotEmpty ||
            page.offset != offset ||
            page.matchedCount != page.totalCount ||
            offset > 0 && readTotal != page.totalCount ||
            page.next != null && page.next! <= offset) {
          throw const CommunityFailure('refreshRequired');
        }
        readTotal = page.totalCount;
        readScanned = offset + page.members.length;
        readNext = page.next;
        rows.addAll(page.members.where(visibleOnline));
        if (readNext == null) break;
      }
      if (targetRef != readTarget) return;
      rows.sort((a, b) {
        final gaming = (b.publicInGame ? 1 : 0).compareTo(
          a.publicInGame ? 1 : 0,
        );
        return gaming != 0 ? gaming : a.displayName.compareTo(b.displayName);
      });
      members = List.unmodifiable(rows);
      scanned = readScanned;
      total = readTotal;
      next = readNext;
      _loaded = true;
    } catch (e) {
      // A round overtaken by a renewal keeps nothing of its failure either;
      // the re-read below starts clean on the new reference.
      if (_closed ||
          invalidated ||
          epoch != _epoch ||
          targetRef != readTarget) {
        return;
      }
      error = e is CommunityFailure ? e.code : 'unavailable';
      if (error != 'unavailable') {
        members = [];
        next = null;
      }
    } finally {
      if (!_closed && epoch == _epoch) {
        loading = false;
        notifyListeners();
        if (targetRef != readTarget && !invalidated) {
          unawaited(refresh(silent: true));
        }
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    members = [];
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
