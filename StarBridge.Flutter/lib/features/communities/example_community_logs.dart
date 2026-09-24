import 'dart:math';

import 'communities_module.dart';
import 'community_logs_port.dart';
import 'community_workspace_port.dart';

/// Isolated example history; never reads or writes a real organization's logs.
final class ExampleCommunityLogs {
  final _histories = <String, List<CommunityLogEntry>>{};
  final _references = <String, (String, String)>{};
  final _random = Random.secure();
  bool _closed = false;
  String _ref() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  List<CommunityLogEntry> _history(String target) => _histories.putIfAbsent(
    target,
    () => List.generate(26, (index) {
      final time = DateTime.utc(
        2026,
        9,
        7,
        12,
      ).subtract(Duration(minutes: index * 9));
      return CommunityLogEntry(
        '$index',
        index.isEven ? '成员' : '公告',
        index.isEven ? '示例 · 成员加入' : '示例 · 更新公告',
        '示例记录 ${index + 1}，不影响真实组织。',
        index == 0 ? null : time,
        index == 0 ? null : time.add(Duration(minutes: index == 1 ? 3 : 0)),
        index == 1 ? 3 : 1,
      );
    }),
  );

  Future<CommunityLogPage> read(
    Future<CommunityWorkspace> Function(String, String, int) workspace,
    String target,
    String type,
    String query,
    int offset,
  ) async {
    if (_closed) throw const CommunityFailure('identityUnavailable');
    final current = await workspace(target, '', 0);
    if (current.access['canViewLogs'] != true) {
      throw const CommunityFailure('notAllowed');
    }
    if (!communityLogFilters.contains(type) ||
        query.length > 128 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(query)) {
      throw const CommunityFailure('dataInvalid');
    }
    final history = _history(target);
    final matches = history
        .where(
          (row) =>
              (type == 'All' || row.type == type) &&
              '${row.title} ${row.detail}'.toLowerCase().contains(
                query.trim().toLowerCase(),
              ),
        )
        .toList();
    if (offset < 0 || offset > matches.length) {
      throw const CommunityFailure('dataInvalid');
    }
    if (_references.length > 4000) _references.clear();
    final items = matches
        .skip(offset)
        .take(20)
        .map((row) {
          final ref = _ref();
          _references[ref] = (target, row.logRef);
          return CommunityLogEntry(
            ref,
            row.type,
            row.title,
            row.detail,
            row.timestamp,
            row.endTimestamp,
            row.occurrenceCount,
          );
        })
        .toList(growable: false);
    return CommunityLogPage(
      target,
      current.name,
      current.access['isOwner'] == true,
      type,
      query.trim(),
      offset,
      offset + items.length < matches.length ? offset + items.length : null,
      history.length,
      matches.length,
      List.unmodifiable(items),
      DateTime.now().toUtc(),
    );
  }

  Future<CommunityLogOutcome> delete(
    Future<CommunityWorkspace> Function(String, String, int) workspace,
    String target,
    String logRef,
  ) async {
    if (_closed) {
      return const CommunityLogOutcome(
        'rejected',
        error: 'identityUnavailable',
      );
    }
    final current = await workspace(target, '', 0);
    if (current.access['isOwner'] != true) {
      return const CommunityLogOutcome('rejected', error: 'refreshRequired');
    }
    final reference = _references[logRef];
    if (reference == null || reference.$1 != target) {
      return const CommunityLogOutcome('rejected', error: 'refreshRequired');
    }
    _references.remove(logRef);
    final rows = _history(target);
    final index = rows.indexWhere((row) => row.logRef == reference.$2);
    if (index < 0) {
      return const CommunityLogOutcome('rejected', error: 'refreshRequired');
    }
    rows.removeAt(index);
    final now = DateTime.now().toUtc();
    rows.insert(
      0,
      CommunityLogEntry(
        _ref(),
        '日志',
        '示例 · 删除日志记录',
        '已删除选中的示例记录。',
        now,
        now,
        1,
      ),
    );
    return const CommunityLogOutcome('accepted');
  }

  void close() {
    _closed = true;
    _histories.clear();
    _references.clear();
  }
}
