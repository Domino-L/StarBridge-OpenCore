import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../communities/communities_module.dart';
import '../common/organization_governance_port.dart';
import '../common/organization_governance_settings.dart';
import 'official_fleet_governance_management.dart';
import 'official_fleet_rank_settings.dart';
import 'official_fleet_role_settings.dart';
import 'official_fleet_audit_settings.dart';

class OfficialFleetGovernanceWorkspace extends StatefulWidget {
  const OfficialFleetGovernanceWorkspace({
    required this.port,
    required this.source,
    required this.onAuthorityRead,
    required this.builder,
    super.key,
  });
  final OrganizationGovernancePort port;
  final String source;
  final ValueChanged<OrganizationGovernanceContext> onAuthorityRead;
  final Widget Function(
    List<OrganizationGovernancePane>,
    ValueChanged<OrganizationGovernanceContext>,
    ValueChanged<String>,
  )
  builder;
  @override
  State<OfficialFleetGovernanceWorkspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<OfficialFleetGovernanceWorkspace> {
  OrganizationGovernanceContext? _authority;
  GovernanceRow? _ranks;
  StreamSubscription<void>? _subscription;
  int _epoch = 0;

  /// A section holds an uncertain write: only its unmounting would lose it.
  bool _rankWritePending = false, _roleWritePending = false;
  bool get _writePending => _rankWritePending || _roleWritePending;

  /// What is on screen outlived a failed read, and has not been read since.
  bool _authorityStale = false;

  /// One more read once a held write settles. It may fail too: the sections
  /// stay, and the relay still refuses whatever is no longer allowed.
  void _writeSettled() {
    if (_writePending || !_authorityStale) return;
    _authorityStale = false;
    // Not from inside a section's own notification or disposal.
    scheduleMicrotask(() {
      if (mounted) unawaited(_refreshAuthority());
    });
  }
  OfficialFleetGovernanceManagementPort? get _port =>
      widget.port is OfficialFleetGovernanceManagementProvider
      ? (widget.port as OfficialFleetGovernanceManagementProvider).management
      : null;
  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _subscription = widget.port.invalidations.listen((_) {
      ++_epoch;
      if (mounted) {
        setState(() {
          _authority = null;
          _ranks = null;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant OfficialFleetGovernanceWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port || oldWidget.source != widget.source) {
      ++_epoch;
      unawaited(_subscription?.cancel());
      _authority = null;
      _ranks = null;
      _bind();
    }
  }

  void _accept(OrganizationGovernanceContext authority) {
    widget.onAuthorityRead(authority);
    setState(() => _authority = authority);
    unawaited(_readRanks());
  }

  Future<void> _readRanks() async {
    final port = _port;
    final epoch = ++_epoch;
    if (port == null || !port.supports('readRankPolicy')) return;
    try {
      final page = await port.read('readRankPolicy', widget.source);
      if (mounted && epoch == _epoch) setState(() => _ranks = page);
    } on Object catch (error) {
      if (mounted && epoch == _epoch && _denied(error)) {
        setState(() => _ranks = null);
      }
    }
  }

  bool _denied(Object error) =>
      error is CommunityFailure && _deniedCode(error.code);

  static bool _deniedCode(String code) =>
      const {'notAllowed', 'identityUnavailable'}.contains(code);

  /// A confirmed loss of rights hides the sections. A failed read says nothing
  /// about them, so what was last read stays until a read answers: a section
  /// holds unsaved edits and unconfirmed writes that unmounting would lose.
  Future<void> _refreshAuthority() async {
    final epoch = _epoch;
    try {
      final authority = await widget.port.read(widget.source);
      if (mounted && epoch == _epoch) {
        _authorityStale = false;
        _accept(authority);
      }
    } on Object catch (error) {
      if (!mounted || epoch != _epoch) return;
      if (!_denied(error)) {
        _authorityStale = true;
        return;
      }
      setState(() {
        _authority = null;
        _ranks = null;
      });
    }
  }

  @override
  void dispose() {
    ++_epoch;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _unavailable(String code) {
    ++_epoch;
    if (!_deniedCode(code)) {
      _authorityStale = true;
      return;
    }
    setState(() {
      _authority = null;
      _ranks = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final port = _port, authority = _authority, ranks = _ranks;
    final delegate =
        authority?.rootControls.any(
          (d) =>
              d.key == 'delegate' &&
              d.state == OrganizationDecisionState.allowed,
        ) ==
        true;
    final audit =
        authority?.capabilities.any(
          (d) =>
              d.key == 'audit.view' &&
              d.state == OrganizationDecisionState.allowed,
        ) ==
        true;
    final rankVisible =
        ranks != null &&
        (governanceAllowed(ranks['write']) ||
            (ranks['write'] as Map)['reason'] == 'rankPolicyWritesDisabled');
    // A new Host can be connected to an older relay. A successful ranks read
    // or the negotiated fourth capability confirms the management protocol.
    final relayConfirmed =
        ranks != null ||
        authority?.capabilities.any((d) => d.key == 'rally.manage') == true;
    return widget.builder(
      [
        if (port != null &&
            relayConfirmed &&
            delegate &&
            port.supports('readMemberRoles'))
          OrganizationGovernancePane(
            id: 'roles',
            retainState: true,
            group: 'teamGroup',
            icon: StandardIconSemantic.adminPanelSettings,
            builder: (_) => Padding(
              padding: const EdgeInsets.all(24),
              child: OfficialFleetRoleSettings(
                key: ValueKey((port, widget.source, 'roles')),
                port: port,
                source: widget.source,
                viewerIsLeader: true,
                onAuthorityRead: _refreshAuthority,
                onWritePending: (pending) {
                  _roleWritePending = pending;
                  _writeSettled();
                },
              ),
            ),
          ),
        if (port != null && port.supports('readRankPolicy') && rankVisible)
          OrganizationGovernancePane(
            id: 'ranks',
            retainState: true,
            group: 'teamGroup',
            icon: StandardIconSemantic.adminPanelSettings,
            builder: (_) => Padding(
              padding: const EdgeInsets.all(24),
              child: OfficialFleetRankSettings(
                key: ValueKey((port, widget.source, 'ranks')),
                port: port,
                source: widget.source,
                initial: ranks,
                onAuthorityRead: _refreshAuthority,
                onWritePending: (pending) {
                  _rankWritePending = pending;
                  _writeSettled();
                },
              ),
            ),
          ),
        if (port != null &&
            relayConfirmed &&
            audit &&
            port.supports('readGovernanceAudit'))
          OrganizationGovernancePane(
            id: 'audit',
            retainState: true,
            group: 'teamGroup',
            icon: StandardIconSemantic.history,
            builder: (_) => Padding(
              padding: const EdgeInsets.all(24),
              child: OfficialFleetAuditSettings(
                key: ValueKey((port, widget.source, 'audit')),
                port: port,
                source: widget.source,
                onAuthorityRead: _refreshAuthority,
              ),
            ),
          ),
      ],
      _accept,
      _unavailable,
    );
  }
}
