import 'package:flutter/material.dart';

import 'official_fleet_governance_management.dart';
import 'official_fleet_governance_copy.dart';
import 'official_fleet_governance_writer.dart';

String fleetRoleName(BuildContext context, GovernanceRow role) {
  final metadata = role['metadata'];
  return metadata is Map && metadata['displayName'] is String
      ? metadata['displayName'] as String
      : fleetGovernanceText(context, 'unnamed');
}

Future<GovernanceRow> readFleetRoleTemplatePage(
  OfficialFleetGovernanceManagementPort port,
  String source,
  Object? roleKey,
) async {
  String? next;
  final seen = <String>{};
  do {
    final page = await port.read('readRoleTemplates', source, {
      'include': ['policyV2'],
      'pageRef': ?next,
    });
    if (roleKey == null ||
        governanceRows(page['roles']).any((r) => r['roleKey'] == roleKey)) {
      return page;
    }
    next = page['nextPageRef'] as String?;
    if (next != null && !seen.add(next)) throw const FormatException();
  } while (next != null && seen.length <= 410);
  throw const FormatException();
}

class OfficialFleetRoleEditor extends StatefulWidget {
  const OfficialFleetRoleEditor({
    required this.port,
    required this.source,
    required this.page,
    required this.onChanged,
    this.role,
    this.writer,
    super.key,
  });
  final OfficialFleetGovernanceManagementPort port;
  final String source;
  final GovernanceRow page;
  final GovernanceRow? role;
  final Future<void> Function() onChanged;

  /// Outlives this dialog when given, with any unconfirmed write it holds.
  final FleetGovernanceWriter? writer;
  @override
  State<OfficialFleetRoleEditor> createState() => _EditorState();
}

class _EditorState extends State<OfficialFleetRoleEditor> {
  late GovernanceRow _page = widget.page;
  late GovernanceRow? _role = widget.role;
  late final TextEditingController _name = TextEditingController(
    text: widget.role == null ? '' : fleetRoleName(context, widget.role!),
  );
  late final Set<String> _selected = {
    if (_role != null)
      for (final r in governanceRows(_role!['permissions']))
        if (r['canUse'] == true &&
            governancePermissions.contains(r['capability']))
          r['capability'] as String,
  };
  bool _permissionsDone = false;
  bool _permissionSaved = false;
  bool _ready = false;
  bool _opened = false;
  @override
  void initState() {
    super.initState();
    _writer.onChanged = _reread;
    _open();
  }

  Future<void> _open() async {
    try {
      final page = await readFleetRoleTemplatePage(
        widget.port,
        widget.source,
        _role?['roleKey'],
      );
      if (mounted) {
        setState(() {
          _page = page;
          if (_role != null) {
            _role = governanceRows(page['roles'])
                .firstWhere((r) => r['roleKey'] == _role!['roleKey']);
          }
          if (!_opened && _role != null) {
            _name.text = fleetRoleName(context, _role!);
            _selected.clear();
            _selected.addAll(
              governanceRows(_role!['permissions'])
                  .where(
                    (r) =>
                        r['canUse'] == true &&
                        governancePermissions.contains(r['capability']),
                  )
                  .map((r) => r['capability'] as String),
            );
          }
          _opened = true;
          _ready = true;
        });
      }
    } on Object {
      if (mounted) setState(() => _writer.result = 'unavailable');
    }
  }

  late final FleetGovernanceWriter _writer =
      widget.writer ??
      FleetGovernanceWriter(widget.port, widget.source, _reread);

  Future<void> _reread() async {
    _ready = false;
    try {
      // A write retires Host edit refs. Read this page again before metadata.
      final page = await readFleetRoleTemplatePage(
        widget.port,
        widget.source,
        _role?['roleKey'],
      );
      if (!mounted) return;
      final roles = governanceRows(page['roles']);
      _page = page;
      if (_role != null) {
        _role = roles
            .where((r) => r['roleKey'] == _role!['roleKey'])
            .firstOrNull;
      }
      _ready = true;
    } finally {
      await widget.onChanged();
    }
  }
  bool get _rallyClosed => governanceRows(_page['creationCapabilities']).any(
    (r) =>
        r['capability'] == 'rally.manage' &&
        r['reason'] == 'rankPolicyWritesDisabled',
  );

  List<GovernanceRow> get _permissions => [
    for (final key in governancePermissions)
      if (_selected.contains(key))
        {'capability': key, 'canUse': true, 'canDelegate': false},
    if (_role != null)
      for (final permission in governanceRows(_role!['permissions']))
        if (!governancePermissions.contains(permission['capability']))
          {...permission},
  ];

  Future<void> _save() async {
    if (_name.text.trim().isEmpty && _writer.pending == null) return;
    if (_role == null && widget.role == null) {
      final result = await _writer.submit('manageRoleTemplates', {
        'editRef': _page['editRef'],
        'action': 'create',
        'metadata': {
          'displayName': _name.text.trim(),
          'description': '',
          'color': '#123456',
          'sortOrder': 0,
        },
        'permissions': _permissions,
      });
      if (mounted && const {'accepted', 'duplicate'}.contains(result)) {
        Navigator.of(context).pop();
      }
      return;
    }
    final role = _role;
    if (role == null) return;
    if (!_permissionsDone) {
      final previous = governanceRows(role['permissions'])
          .where(
            (r) =>
                r['canUse'] == true &&
                governancePermissions.contains(r['capability']),
          )
          .map((r) => r['capability'])
          .toSet();
      if (previous.length != _selected.length ||
          !previous.containsAll(_selected) ||
          _writer.pending?.command == 'updateRolePermissions') {
        final result = await _writer.submit('updateRolePermissions', {
          'expectedPolicyRevision': _page['revision'],
          'roleKey': role['roleKey'],
          'expectedPermissionVersion': role['permissionVersion'],
          'enabled': role['enabled'],
          'permissions': _permissions,
        });
        if (!mounted ||
            !_ready ||
            !const {'accepted', 'duplicate'}.contains(result)) {
          return;
        }
        _permissionSaved = true;
      }
      _permissionsDone = true;
    }
    final fresh = _role;
    if (fresh == null) return;
    if (_name.text.trim() != fleetRoleName(context, fresh) ||
        _writer.pending?.command == 'manageRoleTemplates') {
      final metadata = fresh['metadata'] as Map?;
      await _writer.submit('manageRoleTemplates', {
        'editRef': _page['editRef'],
        'action': 'metadata',
        'roleRef': fresh['roleRef'],
        'metadata': {
          'displayName': _name.text.trim(),
          'description': metadata?['description'] ?? '',
          'color': metadata?['color'] ?? '#123456',
          'sortOrder': metadata?['sortOrder'] ?? 0,
        },
      });
    }
    if (mounted &&
        _writer.pending == null &&
        (_writer.result == null ||
            const {'accepted', 'duplicate'}.contains(_writer.result))) {
      Navigator.of(context).pop();
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _name.dispose();
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
          !_ready || _writer.busy || _writer.pending != null || _writer.retired;
      final canSave =
          _ready &&
          !_writer.busy &&
          !_writer.retired &&
          (_writer.pending != null ||
              _name.text.trim().isNotEmpty &&
                  !(_rallyClosed && _selected.contains('rally.manage')));
      // Leaving with an unconfirmed write is allowed: the role page keeps the
      // writer, so opening this again continues the same operation.
      return PopScope(
        canPop: !_writer.busy,
        child: AlertDialog(
          title: Text(t(widget.role == null ? 'create' : 'edit')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('additive')),
                  if (widget.role != null) Text(t('roleChange')),
                  TextField(
                    key: const Key('role-name'),
                    controller: _name,
                    enabled:
                        !locked && widget.port.supports('manageRoleTemplates'),
                    onChanged: (_) => setState(() {}),
                    maxLength: 64,
                    decoration: InputDecoration(labelText: t('name')),
                  ),
                  Text(t('extra')),
                  for (final key in governancePermissions)
                    CheckboxListTile(
                      key: ValueKey('role-$key'),
                      title: Text(t(key)),
                      value: _selected.contains(key),
                      onChanged:
                          locked ||
                              !widget.port.supports(
                                widget.role == null
                                    ? 'manageRoleTemplates'
                                    : 'updateRolePermissions',
                              ) ||
                              key == 'rally.manage' && _rallyClosed
                          ? null
                          : (v) {
                              setState(() {
                                _permissionsDone = false;
                                v! ? _selected.add(key) : _selected.remove(key);
                              });
                            },
                    ),
                  if (_rallyClosed) Text(t('closed')),
                  if (_writer.busy || !_ready) const LinearProgressIndicator(),
                  if (_permissionSaved &&
                      _role != null &&
                      _name.text.trim() != fleetRoleName(context, _role!))
                    Text(t('permissionsSaved')),
                  if (_writer.result case final result?) Text(t(result)),
                  if (!_ready && !_writer.busy)
                    TextButton(onPressed: _open, child: Text(t('retry'))),
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
            FilledButton(
              key: const Key('role-save'),
              onPressed: canSave ? _save : null,
              child: Text(t(_writer.pending == null ? 'save' : 'retry')),
            ),
          ],
        ),
      );
    },
  );
}
