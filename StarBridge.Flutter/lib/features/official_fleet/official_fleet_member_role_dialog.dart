import 'package:flutter/material.dart';

import 'official_fleet_governance_management.dart';
import 'official_fleet_governance_copy.dart';
import 'official_fleet_governance_writer.dart';
import 'official_fleet_role_editor.dart';

class OfficialFleetMemberRoleDialog extends StatefulWidget {
  const OfficialFleetMemberRoleDialog({
    required this.port,
    required this.source,
    required this.member,
    required this.roles,
    required this.onChanged,
    required this.onAuthorityRead,
    this.onReadFailed,
    this.onRoleRead,
    this.writer,
    super.key,
  });
  final OfficialFleetGovernanceManagementPort port;
  final String source;
  final GovernanceRow member;
  final List<GovernanceRow> roles;
  final Future<void> Function(GovernanceRow) onChanged;
  final Future<void> Function() onAuthorityRead;
  final VoidCallback? onReadFailed;

  /// A role reread after a conflict; null when it no longer exists.
  final void Function(Object? roleKey, GovernanceRow? role)? onRoleRead;

  /// Outlives this dialog when given, with any unconfirmed write it holds.
  final FleetGovernanceWriter? writer;
  @override
  State<OfficialFleetMemberRoleDialog> createState() => _MemberState();
}

class _MemberState extends State<OfficialFleetMemberRoleDialog> {
  GovernanceRow? _page;
  String? _selected, _error;
  bool _loading = true;
  late final List<GovernanceRow> _roles = [...widget.roles];
  late final FleetGovernanceWriter _writer =
      widget.writer ??
      FleetGovernanceWriter(widget.port, widget.source, _afterWrite);

  Future<void> _afterWrite() async {
    try {
      await _reload();
      if (_writer.result == 'conflict') await _rereadSelectedRole();
    } finally {
      await widget.onAuthorityRead();
    }
  }

  @override
  void initState() {
    super.initState();
    _writer.onChanged = _afterWrite;
    _reload();
  }

  Future<void> _reload() async {
    try {
      final page = await widget.port.read('readMemberRoles', widget.source, {
        'targetRef': widget.member['memberRef'],
      });
      if (page['targetRef'] != widget.member['memberRef']) {
        throw const FormatException();
      }
      if (mounted) {
        setState(() {
          _page = page;
          _error = null;
        });
      }
      await widget.onChanged(page);
    } on Object {
      widget.onReadFailed?.call();
      if (mounted) {
        setState(() {
          _page = null;
          _error = 'unavailable';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The role list was read when the page opened; a conflict can mean it moved.
  Future<void> _rereadSelectedRole() async {
    final key = _selected;
    if (key == null) return;
    GovernanceRow? fresh;
    try {
      final page = await readFleetRoleTemplatePage(
        widget.port,
        widget.source,
        key,
      );
      fresh = governanceRows(
        page['roles'],
      ).where((r) => r['roleKey'] == key).firstOrNull;
    } on FormatException {
      fresh = null;
    } on Object {
      return; // Nothing learned. The next try is refused again, never misapplied.
    }
    if (!mounted) return;
    setState(() {
      final at = _roles.indexWhere((r) => r['roleKey'] == key);
      if (at >= 0) {
        if (fresh == null) {
          _roles.removeAt(at);
        } else {
          _roles[at] = fresh;
        }
      }
      if (fresh == null || fresh['enabled'] != true) _selected = null;
    });
    widget.onRoleRead?.call(key, fresh);
  }

  Future<void> _assign() async {
    final page = _page;
    final role = _roles.where((r) => r['roleKey'] == _selected).firstOrNull;
    if (page == null || role == null) return;
    final permissions = governanceRows(role['permissions'])
        .where(
          (p) =>
              p['canUse'] == true &&
              governancePermissions.contains(p['capability']),
        )
        .map(
          (p) => {
            'capability': p['capability'],
            'canUse': true,
            'canDelegate': false,
          },
        )
        .toList();
    if (permissions.isEmpty) return;
    await _writer.submit('assignRole', {
      'expectedPolicyRevision': page['policyRevision'],
      'targetRef': widget.member['memberRef'],
      'expectedTargetMembershipEpoch': page['membershipEpoch'],
      'roleKey': role['roleKey'],
      'expectedRolePermissionVersion': role['permissionVersion'],
      'parts': [
        {
          'grantId': governanceOperationId(),
          'ceiling': permissions,
          'rootActivationId': page['rootActivationId'],
          'expectedRootVersion': page['rootActivationVersion'],
        },
      ],
    });
  }

  @override
  void dispose() {
    if (widget.writer == null) _writer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _writer,
    builder: (context, _) {
      String t(String key) => fleetGovernanceText(context, key);
      if (_writer.retired) {
        return AlertDialog(
          content: Text(t('identityUnavailable')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('discard')),
            ),
          ],
        );
      }
      final locked =
          _loading ||
          _writer.busy ||
          _writer.pending != null ||
          _writer.retired;
      return PopScope(
        canPop: !_writer.busy,
        child: AlertDialog(
          title: Text(widget.member['callsign'] as String? ?? t('member')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('additive')),
                  if (_loading || _writer.busy) const LinearProgressIndicator(),
                  if (_error case final error?) Text(t(error)),
                  if (_page case final page?) ...[
                    for (final grant in governanceRows(
                      page['grants'],
                    ).where((g) => g['revoked'] == false))
                      ListTile(
                        title: Text(_roleName(grant['roleKey'])),
                        trailing: TextButton(
                          onPressed:
                              locked || !widget.port.supports('revokeRole')
                              ? null
                              : () => _writer.submit('revokeRole', {
                                  'expectedPolicyRevision':
                                      page['policyRevision'],
                                  'grantId': grant['grantId'],
                                  'expectedGrantVersion': grant['version'],
                                }),
                          child: Text(t('revoke')),
                        ),
                      ),
                    DropdownButton<String>(
                      key: const Key('member-role-choice'),
                      isExpanded: true,
                      value: _selected,
                      hint: Text(t('assign')),
                      items: [
                        for (final role in _roles.where(
                          (r) => r['enabled'] == true,
                        ))
                          DropdownMenuItem(
                            value: role['roleKey'] as String,
                            child: Text(fleetRoleName(context, role)),
                          ),
                      ],
                      onChanged: locked
                          ? null
                          : (v) => setState(() => _selected = v),
                    ),
                    FilledButton(
                      key: const Key('member-role-assign'),
                      onPressed:
                          !locked &&
                              _selected != null &&
                              widget.port.supports('assignRole')
                          ? _assign
                          : null,
                      child: Text(t('assign')),
                    ),
                  ],
                  if (_writer.result case final result?) Text(t(result)),
                  if (_writer.pending != null)
                    FilledButton(
                      onPressed: _writer.busy
                          ? null
                          : () => _writer.submit('', {}),
                      child: Text(t('retry')),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _writer.busy
                  ? null
                  : () => Navigator.of(context).pop(),
              child: Text(t('discard')),
            ),
          ],
        ),
      );
    },
  );
  String _roleName(Object? key) {
    final role = _roles.where((r) => r['roleKey'] == key).firstOrNull;
    return role == null
        ? fleetGovernanceText(context, 'unnamed')
        : fleetRoleName(context, role);
  }
}
