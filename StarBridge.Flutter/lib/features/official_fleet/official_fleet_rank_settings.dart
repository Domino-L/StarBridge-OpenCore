import 'package:flutter/material.dart';

import 'official_fleet_governance_management.dart';
import 'official_fleet_governance_copy.dart';
import 'official_fleet_governance_writer.dart';

class OfficialFleetRankSettings extends StatefulWidget {
  const OfficialFleetRankSettings({
    required this.port,
    required this.source,
    required this.initial,
    required this.onAuthorityRead,
    this.onWritePending,
    super.key,
  });
  final OfficialFleetGovernanceManagementPort port;
  final String source;
  final GovernanceRow initial;
  final Future<void> Function() onAuthorityRead;
  final ValueChanged<bool>? onWritePending;
  @override
  State<OfficialFleetRankSettings> createState() => _RankState();
}

class _RankState extends State<OfficialFleetRankSettings> {
  late GovernanceRow _page = widget.initial;
  late List<GovernanceRow> _draft = _rows();
  bool _readFailed = false;
  bool _dirty = false;
  @override
  void initState() {
    super.initState();
    _writer.addListener(_reportPending);
  }

  void _reportPending() => widget.onWritePending?.call(_writer.pending != null);

  @override
  void didUpdateWidget(covariant OfficialFleetRankSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.initial, widget.initial) ||
        _writer.busy ||
        _writer.pending != null) {
      return;
    }
    // An unsaved edit waits for its save, unless saving has since been closed.
    if (!_dirty || !governanceAllowed(widget.initial['write'])) {
      _page = widget.initial;
      _draft = _rows();
      _dirty = false;
      _readFailed = false;
    }
  }

  late final FleetGovernanceWriter _writer = FleetGovernanceWriter(
    widget.port,
    widget.source,
    _reload,
  );
  Future<void> _reload() async {
    try {
      final page = await widget.port.read('readRankPolicy', widget.source);
      if (mounted) {
        setState(() {
          _page = page;
          _draft = _rows();
          _dirty = false;
          _readFailed = false;
        });
      }
    } on Object {
      if (mounted) setState(() => _readFailed = true);
    } finally {
      await widget.onAuthorityRead();
    }
  }

  List<GovernanceRow> _rows() => [
    for (final row in governanceRows(_page['rows'])) {...row},
  ]..sort((a, b) => (a['rankValue'] as int).compareTo(b['rankValue'] as int));
  @override
  void dispose() {
    _writer.removeListener(_reportPending);
    widget.onWritePending?.call(false);
    _writer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _writer,
    builder: (context, _) {
      String t(String key) => fleetGovernanceText(context, key);
      final editable =
          governanceAllowed(_page['write']) &&
          widget.port.supports('writeRankPolicy') &&
          !_writer.busy &&
          _writer.pending == null &&
          !_writer.retired;
      final writable = editable && !_readFailed;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((_page['write'] as Map)['reason'] == 'rankPolicyWritesDisabled')
            Text(t('closed')),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(t('ranks'))),
                for (final key in governancePermissions)
                  DataColumn(label: Text(t(key))),
              ],
              rows: [
                DataRow(
                  key: const ValueKey('governance-rank-1'),
                  cells: [
                    const DataCell(Text('5★')),
                    DataCell(Text(t('fixed'))),
                    const DataCell(SizedBox.shrink()),
                    const DataCell(SizedBox.shrink()),
                  ],
                ),
                for (final row in _draft)
                  DataRow(
                    cells: [
                      DataCell(Text('${6 - (row['rankValue'] as int)}★')),
                      for (final key in ['announcements', 'rally', 'audit'])
                        DataCell(
                          Checkbox(
                            key: ValueKey('rank-${row['rankValue']}-$key'),
                            value: row[key] as bool,
                            onChanged: writable
                                ? (v) => setState(() {
                                    _dirty = true;
                                    row[key] = v!;
                                  })
                                : null,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_writer.busy) const LinearProgressIndicator(),
          if (_writer.result case final result?) Text(t(result)),
          if (_readFailed) ...[
            Text(t('unavailable')),
            TextButton(
              onPressed: _writer.busy ? null : _reload,
              child: Text(t('refresh')),
            ),
          ],
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const Key('rank-save'),
                onPressed: writable || _writer.pending != null && !_writer.busy
                    ? () => _writer.submit('writeRankPolicy', {
                        'expectedPolicyRevision': _page['policyRevision'],
                        'rows': _draft,
                      })
                    : null,
                child: Text(t(_writer.pending == null ? 'save' : 'retry')),
              ),
              OutlinedButton(
                key: const Key('rank-discard'),
                onPressed: writable
                    ? () => setState(() {
                        _dirty = false;
                        _draft = _rows();
                      })
                    : null,
                child: Text(t('discard')),
              ),
            ],
          ),
        ],
      );
    },
  );
}
