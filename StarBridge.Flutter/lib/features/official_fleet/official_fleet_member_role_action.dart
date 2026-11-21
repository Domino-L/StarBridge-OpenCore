import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';
import '../common/organization_governance_port.dart';
import '../common/organization_member_copy.dart';
import '../communities/communities_module.dart';
import 'official_fleet_governance_copy.dart';
import 'official_fleet_governance_management.dart';
import 'official_fleet_governance_writer.dart';
import 'official_fleet_member_role_dialog.dart';
import 'official_fleet_members_models.dart';
import '../../design_system/interaction/panel_dialog_scope.dart';

/// Whether a member row offers 设置角色: the roles pane's own decisions, read
/// once per source. Every write is still decided by the relay.
class OfficialFleetMemberRoleActions extends ChangeNotifier {
  OfficialFleetMemberRoleActions(this.governance, this.source) {
    _invalidations = governance.invalidations.listen((_) {
      _set(false);
      unawaited(read());
    });
    unawaited(read());
  }

  static const _maxRolePages = 10;
  final OrganizationGovernancePort governance;
  final String source;
  late final StreamSubscription<void> _invalidations;
  bool _allowed = false, _opening = false, _disposed = false;
  int _epoch = 0;

  /// One per member, kept past its dialog: closing on an unconfirmed write must
  /// not forget it, or the same edit would go out as a new operation.
  final _writers = <Object?, FleetGovernanceWriter>{};

  OfficialFleetGovernanceManagementPort? get _port =>
      governance is OfficialFleetGovernanceManagementProvider
      ? (governance as OfficialFleetGovernanceManagementProvider).management
      : null;

  bool get _supported {
    final port = _port;
    return port != null &&
        governance.available &&
        port.supports('readMemberRoles') &&
        port.supports('readRoleTemplates') &&
        (port.supports('assignRole') || port.supports('revokeRole'));
  }

  /// The same fixed rows as the roles pane: other leaders and the viewer.
  bool offeredFor(OfficialFleetMember member) =>
      _allowed && member.officialRankValue != 1 && !member.isSelf;

  void _set(bool allowed) {
    if (_disposed || _allowed == allowed) return;
    _allowed = allowed;
    notifyListeners();
  }

  Future<void> read() async {
    final epoch = ++_epoch;
    if (!_supported) return _set(false);
    try {
      final authority = await governance.read(source);
      if (_disposed || epoch != _epoch) return;
      _set(
        // A new Host can be connected to an older relay: the fourth capability
        // confirms the management protocol, as it does for the roles pane.
        authority.capabilities.any((d) => d.key == 'rally.manage') &&
            authority.rootControls.any(
              (d) =>
                  d.key == 'delegate' &&
                  d.state == OrganizationDecisionState.allowed,
            ),
      );
    } on CommunityFailure catch (error) {
      if (error.code == 'notAllowed' || error.code == 'identityUnavailable') {
        if (epoch == _epoch) _set(false);
      }
    } on Object {
      // A failed read says nothing about rights; the relay refuses writes anyway.
    }
  }

  Future<List<GovernanceRow>> _readRoles() async {
    final roles = <GovernanceRow>[];
    Object? next;
    for (var i = 0; i < _maxRolePages; i++) {
      final page = await _port!.read('readRoleTemplates', source, {
        'include': ['policyV2'],
        'pageRef': ?next,
      });
      roles.addAll(governanceRows(page['roles']));
      next = page['nextPageRef'];
      if (next == null) break;
    }
    return roles;
  }

  Future<void> open(BuildContext context, OfficialFleetMember member) async {
    final port = _port;
    if (port == null || _opening) return;
    _opening = true;
    try {
      final List<GovernanceRow> roles;
      try {
        roles = await _readRoles();
      } on Object {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(fleetGovernanceText(context, 'unavailable')),
            ),
          );
        }
        unawaited(read());
        return;
      }
      if (_disposed || !context.mounted) return;
      final key = member.memberRef;
      final existing = _writers[key];
      if (existing == null || existing.retired) {
        existing?.dispose();
        _writers[key] = FleetGovernanceWriter(port, source, read);
      }
      await showDialog<void>(
        context: context,
        useRootNavigator: PanelDialogScope.allowsRoot(context),
        barrierDismissible: false,
        builder: (_) => OfficialFleetMemberRoleDialog(
          port: port,
          source: source,
          member: {
            'memberRef': member.memberRef,
            if (member.identityState !=
                OfficialFleetMemberIdentityState.restricted)
              'callsign': member.callsign,
          },
          roles: roles,
          writer: _writers[key],
          onAuthorityRead: read,
          onChanged: (_) async {},
        ),
      );
      // Only an unconfirmed write has a reason to outlive its dialog.
      if (!_disposed && _writers[key]?.pending == null) {
        _writers.remove(key)?.dispose();
      }
    } finally {
      _opening = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    unawaited(_invalidations.cancel());
    for (final writer in _writers.values) {
      writer.dispose();
    }
    super.dispose();
  }
}

/// The community member row's menu; the row itself still opens the profile.
Widget officialFleetMemberRoleMenu(
  BuildContext context,
  OfficialFleetMember member,
  OfficialFleetMemberRoleActions actions,
) {
  final label = memberBoardText(context, 'actions');
  final assign = fleetGovernanceText(context, 'assign');
  return StarBridgeMenuAnchor(
    semanticLabel: label,
    entries: [
      StarBridgeMenuEntry(
        id: 'assign-fleet-member-${member.memberRef}',
        label: assign,
        onActivate: (source) => unawaited(
          runStarBridgeActivation<void>(
            source,
            () => actions.open(context, member),
          ),
        ),
        child: Text(assign),
      ),
    ],
    builder: (context, controller, focus, toggle) => StarBridgeIconAction(
      controlKey: ValueKey('member-actions-${member.memberRef}'),
      focusNode: focus,
      label: label,
      icon: const StandardIcon(StandardIconSemantic.moreHoriz),
      onActivate: toggle,
    ),
  );
}
