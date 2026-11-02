import 'dart:async';

import 'package:flutter/material.dart';

import 'official_fleet_governance_management.dart';
import 'official_fleet_governance_copy.dart';
import 'official_fleet_governance_writer.dart';
import 'official_fleet_role_editor.dart';
import 'official_fleet_member_role_dialog.dart';

class OfficialFleetRoleSettings extends StatefulWidget {
  const OfficialFleetRoleSettings({
    required this.port,
    required this.source,
    required this.viewerIsLeader,
    required this.onAuthorityRead,
    this.onWritePending,
    super.key,
  });
  final OfficialFleetGovernanceManagementPort port;
  final String source;
  final bool viewerIsLeader;
  final Future<void> Function() onAuthorityRead;
  final ValueChanged<bool>? onWritePending;
  @override
  State<OfficialFleetRoleSettings> createState() => _RolesState();
}

class _RolesState extends State<OfficialFleetRoleSettings> {
  GovernanceRow? _templates, _directory;
  final _roles = <GovernanceRow>[], _members = <GovernanceRow>[];
  final _observed = <Object?, GovernanceRow>{};
  final _reading = <Object?>{};
  bool _loading = false;
  String? _error;
  int _memberPage = 1;

  /// One per thing being edited, kept past its dialog: closing on an unconfirmed
  /// write must not forget it, or the same edit would go out as a new operation.
  final _writers = <Object, FleetGovernanceWriter>{};

  FleetGovernanceWriter _writerFor(Object key) {
    final existing = _writers[key];
    if (existing != null && !existing.retired) return existing;
    existing?.dispose();
    return _writers[key] = FleetGovernanceWriter(
      widget.port,
      widget.source,
      widget.onAuthorityRead,
    )..addListener(_reportPending);
  }

  void _reportPending() => widget.onWritePending?.call(
    _writers.values.any((writer) => writer.pending != null),
  );

  /// Only an unconfirmed write has a reason to outlive its dialog.
  void _release(Object key) {
    if (_writers[key]?.pending != null) return;
    _writers.remove(key)?.dispose();
  }

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    widget.onWritePending?.call(false);
    for (final writer in _writers.values) {
      writer.dispose();
    }
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Exactly two reads, no roles/member fan-out on entry.
      await _readTemplates();
      await _readMembers();
    } on Object {
      _readFailed();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A refused read can mean rights were revoked: the section decides again.
  void _readFailed() {
    if (!mounted) return;
    setState(() => _error = 'unavailable');
    unawaited(widget.onAuthorityRead());
  }

  Future<void> _readTemplates({bool next = false}) async {
    final page = await widget.port.read('readRoleTemplates', widget.source, {
      'include': ['policyV2'],
      if (next) 'pageRef': _templates!['nextPageRef'],
    });
    if (mounted) {
      setState(() {
        if (!next) _roles.clear();
        _roles.addAll(governanceRows(page['roles']));
        _templates = page;
      });
    }
  }

  Future<void> _readMembers({bool next = false}) async {
    final number = next ? _memberPage + 1 : 1;
    final page = await widget.port.read('getMembers', widget.source, {
      'search': '',
      'filter': 'all',
      'pageNumber': number,
      'pageSize': 25,
    });
    if (mounted) {
      setState(() {
        if (!next) _members.clear();
        _members.addAll(governanceRows(page['members']));
        _directory = page;
        _memberPage = number;
      });
    }
  }

  Future<void> _more(Future<void> Function() read) async {
    setState(() => _loading = true);
    try {
      await read();
    } on Object {
      _readFailed();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _fixed(GovernanceRow member) =>
      member['officialRankValue'] == 1 ||
      widget.viewerIsLeader && member['isSelf'] == true;
  Future<void> _observe(GovernanceRow member) async {
    final ref = member['memberRef'];
    if (_reading.length >= 3 || _reading.contains(ref)) return;
    setState(() => _reading.add(ref));
    try {
      final page = await widget.port.read('readMemberRoles', widget.source, {
        'targetRef': ref,
      });
      if (page['targetRef'] != ref) throw const FormatException();
      if (mounted) setState(() => _observed[ref] = page);
    } on Object {
      if (mounted) setState(() => _observed.remove(ref));
      _readFailed();
    } finally {
      if (mounted) setState(() => _reading.remove(ref));
    }
  }

  Future<void> _editor([GovernanceRow? role]) async {
    final key = ('role', role?['roleKey']);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OfficialFleetRoleEditor(
        port: widget.port,
        source: widget.source,
        page: _templates!,
        role: role,
        writer: _writerFor(key),
        onChanged: widget.onAuthorityRead,
      ),
    );
    if (!mounted) return;
    _release(key);
    await _more(() => _readTemplates());
  }

  Future<void> _memberEditor(GovernanceRow member) async {
    final key = ('member', member['memberRef']);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OfficialFleetMemberRoleDialog(
        port: widget.port,
        source: widget.source,
        member: member,
        roles: _roles,
        writer: _writerFor(key),
        onAuthorityRead: widget.onAuthorityRead,
        onReadFailed: () {
          if (mounted) setState(() => _observed.remove(member['memberRef']));
        },
        onChanged: (page) async {
          if (mounted) setState(() => _observed[member['memberRef']] = page);
        },
        onRoleRead: _roleRead,
      ),
    );
    if (mounted) _release(key);
  }

  void _roleRead(Object? roleKey, GovernanceRow? role) {
    if (!mounted) return;
    setState(() {
      final at = _roles.indexWhere((r) => r['roleKey'] == roleKey);
      if (at < 0) return;
      if (role == null) {
        _roles.removeAt(at);
      } else {
        _roles[at] = role;
      }
    });
  }

  String _current(GovernanceRow page) {
    final grants = governanceRows(page['grants'])
        .where((g) => g['revoked'] == false);
    final names = <String>[];
    for (final grant in grants) {
      if (!_roles.any((r) => r['roleKey'] == grant['roleKey'])) {
        names.add(fleetGovernanceText(context, 'unnamed'));
        continue;
      }
      final role = _roles
          .where(
            (r) =>
                r['roleKey'] == grant['roleKey'] &&
                r['enabled'] == true &&
                r['permissionVersion'] == grant['permissionVersion'],
          )
          .firstOrNull;
      if (role != null) names.add(fleetRoleName(context, role));
    }
    return names.isEmpty
        ? fleetGovernanceText(context, 'none')
        : names.toSet().join('、');
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => fleetGovernanceText(context, key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('additive')),
        Text(t('onDemand')),
        if (_loading) const LinearProgressIndicator(),
        if (_error case final error?) Text(t(error)),
        Text(t('members'), style: Theme.of(context).textTheme.titleMedium),
        for (final member in _members)
          ListTile(
            title: Text(member['callsign'] as String? ?? t('member')),
            subtitle: _fixed(member)
                ? Text(t('fixed'))
                : switch (_observed[member['memberRef']]) {
                    final page? => Text(_current(page)),
                    _ => null,
                  },
            trailing: _fixed(member)
                ? null
                : Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed:
                            _reading.length >= 3 ||
                                _reading.contains(member['memberRef'])
                            ? null
                            : () => _observe(member),
                        child: Text(t('read')),
                      ),
                      if (widget.port.supports('assignRole') ||
                          widget.port.supports('revokeRole'))
                        TextButton(
                          onPressed: _loading || _reading.isNotEmpty
                              ? null
                              : () => _memberEditor(member),
                          child: Text(t('assign')),
                        ),
                      if (widget.port.supports('revokeRole') &&
                          _observed[member['memberRef']] != null &&
                          governanceRows(
                            _observed[member['memberRef']]!['grants'],
                          ).any((g) => g['revoked'] == false))
                        TextButton(
                          onPressed: _loading || _reading.isNotEmpty
                              ? null
                              : () => _memberEditor(member),
                          child: Text(t('revoke')),
                        ),
                    ],
                  ),
          ),
        if ((_directory?['totalPages'] as int? ?? 1) > _memberPage)
          OutlinedButton(
            onPressed: _loading
                ? null
                : () => _more(() => _readMembers(next: true)),
            child: Text(t('load')),
          ),
        const Divider(),
        Text(t('templates'), style: Theme.of(context).textTheme.titleMedium),
        if (_templates != null && widget.port.supports('manageRoleTemplates'))
          FilledButton(
            onPressed: _loading ? null : _editor,
            child: Text(t('create')),
          ),
        for (final role in _roles)
          ListTile(
            title: Text(fleetRoleName(context, role)),
            subtitle: Text(
              [
                for (final p in governanceRows(role['permissions']))
                  if (p['canUse'] == true &&
                      governancePermissions.contains(p['capability']))
                    t(p['capability'] as String),
              ].join('、'),
            ),
            trailing:
                widget.port.supports('updateRolePermissions') ||
                    widget.port.supports('manageRoleTemplates')
                ? TextButton(
                    onPressed: _loading ? null : () => _editor(role),
                    child: Text(t('edit')),
                  )
                : null,
          ),
        if (_templates?['nextPageRef'] != null)
          OutlinedButton(
            onPressed: _loading
                ? null
                : () => _more(() => _readTemplates(next: true)),
            child: Text(t('load')),
          ),
        if (_error != null)
          OutlinedButton(
            onPressed: _loading ? null : _open,
            child: Text(t('retry')),
          ),
      ],
    );
  }
}
