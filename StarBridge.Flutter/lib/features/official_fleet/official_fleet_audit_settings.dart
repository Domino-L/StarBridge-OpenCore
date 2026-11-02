import 'dart:async';

import 'package:flutter/material.dart';

import '../communities/communities_module.dart';
import 'official_fleet_governance_management.dart';
import 'official_fleet_governance_copy.dart';

class OfficialFleetAuditSettings extends StatefulWidget {
  const OfficialFleetAuditSettings({
    required this.port,
    required this.source,
    this.onAuthorityRead,
    super.key,
  });
  final OfficialFleetGovernanceManagementPort port;
  final String source;

  /// A refused read can mean rights were revoked: the section decides again.
  final Future<void> Function()? onAuthorityRead;
  @override
  State<OfficialFleetAuditSettings> createState() => _AuditState();
}

class _AuditState extends State<OfficialFleetAuditSettings> {
  final _items = <GovernanceRow>[];
  GovernanceRow? _page;
  bool _loading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read({bool next = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.port.read(
        'readGovernanceAudit',
        widget.source,
        {
          'offset': next ? _page!['nextOffset'] : 0,
          if (next) 'expectedPolicyRevision': _page!['policyRevision'],
        },
      );
      if (!mounted) return;
      setState(() {
        if (!next) _items.clear();
        _items.addAll(governanceRows(page['items']));
        _items.sort(
          (a, b) =>
              DateTime.parse(b['occurredAtUtc'] as String)
                  .compareTo(DateTime.parse(a['occurredAtUtc'] as String)),
        );
        _page = page;
      });
    } on Object catch (error) {
      if (!mounted) return;
      if (next &&
          error is CommunityFailure &&
          error.code == 'refreshRequired') {
        setState(() {
          _loading = false;
          _items.clear();
          _page = null;
        });
        await _read();
        if (mounted) setState(() => _error = 'conflict');
        return;
      }
      setState(() {
        _error = 'unavailable';
        _items.clear();
        _page = null;
      });
      unawaited(widget.onAuthorityRead?.call());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => fleetGovernanceText(context, key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error case final error?) Text(t(error)),
        if (!_loading && _error == null && _items.isEmpty) Text(t('empty')),
        for (final row in _items)
          ListTile(
            title: Text(fleetGovernanceAuditKind(context, row['kind'])),
            subtitle: Text(
              '${_display(row['actorDisplay'])} · ${_display(row['targetDisplay'])}\n'
              '${MaterialLocalizations.of(context).formatShortDate(DateTime.parse(row['occurredAtUtc'] as String).toLocal())} '
              '${TimeOfDay.fromDateTime(DateTime.parse(row['occurredAtUtc'] as String).toLocal()).format(context)}',
            ),
            isThreeLine: true,
          ),
        if (_page?['nextOffset'] != null)
          OutlinedButton(
            onPressed: _loading ? null : () => _read(next: true),
            child: Text(t('load')),
          ),
        if (_error != null)
          OutlinedButton(
            onPressed: _loading ? null : _read,
            child: Text(t('retry')),
          ),
      ],
    );
  }

  String _display(Object? value) => switch (value) {
    'Unavailable member' => fleetGovernanceText(context, 'member'),
    'Affected members' => fleetGovernanceText(context, 'members'),
    'Main fleet' => fleetGovernanceText(context, 'fleet'),
    _ => value as String,
  };
}
