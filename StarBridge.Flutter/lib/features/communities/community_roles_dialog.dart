import '../../design_system/icons/standard_icon.dart';
import '../../design_system/styles/member_role_style.dart';
import 'dart:async';
import 'community_visible_refresh.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_roles_controller.dart';
import 'community_roles_port.dart';
import 'community_roles_copy.dart';
import 'community_editor_surface.dart';

class CommunityRolesDialog extends StatefulWidget {
  const CommunityRolesDialog({
    required this.port,
    required this.targetRef,
    this.embedded = false,
    this.onSaved,
    super.key,
  });
  final CommunityRolesPort port;
  final String targetRef;
  final bool embedded;
  final VoidCallback? onSaved;
  @override
  State<CommunityRolesDialog> createState() => CommunityRolesDialogState();
}

class CommunityRolesDialogState extends State<CommunityRolesDialog> with CommunityVisibleRefresh<CommunityRolesDialog> {
  @override
  Future<void> refreshVisibleCommunity() => model.refreshLease();
  @override
  Duration get communityRefreshInterval => const Duration(minutes: 2);
  late final model = CommunityRolesController(widget.port, widget.targetRef);
  final name = TextEditingController(), description = TextEditingController();
  final confirmations = <Route<bool>>[];
  String? shownKey, shownEdit;
  bool confirming = false;
  String t(String key) => rolesText(context, key);
  bool get busy => model.locked || confirming;
  @override
  void initState() {
    super.initState();
    model.addListener(_changed);
    unawaited(model.load());
  }

  void _changed() {
    if (!mounted) return;
    if (model.invalidated) {
      for (final route in confirmations.toList()) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
      name.clear();
      description.clear();
    }
    final selected = model.selected;
    if (shownKey != selected?.key || shownEdit != model.snapshot?.editRef) {
      shownKey = selected?.key;
      shownEdit = model.snapshot?.editRef;
      if (name.text != (selected?.name ?? '')) name.text = selected?.name ?? '';
      if (description.text != (selected?.description ?? '')) description.text = selected?.description ?? '';
    }
    setState(() {});
  }

  @override
  void dispose() {
    model.removeListener(_changed);
    model.dispose();
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String detail, String action) async {
    if (confirming) return false;
    setState(() => confirming = true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    confirmations.add(route);
    try {
      return await Navigator.of(context).push(route) == true &&
          mounted &&
          !model.invalidated;
    } finally {
      confirmations.remove(route);
      if (mounted) setState(() => confirming = false);
    }
  }

  Future<bool> confirmLeave() async {
    if (model.submitting || confirming) return false;
    if (model.invalidated) return true;
    if (model.dirty &&
        !await _confirm(
          t('rolesLeave'),
          t('rolesLeaveHelp'),
          t('leaveRoles'),
        )) {
      return false;
    }
    return mounted;
  }

  Future<void> _close() async {
    if (await confirmLeave() && mounted && !widget.embedded) {
      Navigator.pop(context);
    }
  }

  Future<void> _reload() async {
    if (model.dirty &&
        !await _confirm(t('reloadRoles'), t('rolesReload'), t('reloadRoles'))) {
      return;
    }
    await model.load(discardChanges: true);
  }

  Future<void> _save() async {
    final confirm = model.requiresRetryConfirmation;
    if (confirm &&
        !await _confirm(t('rolesRetry'), t('rolesRetryHelp'), t('save'))) {
      return;
    }
    await model.save(confirmUncertainRetry: confirm);
    if (mounted && model.outcome?.status == 'accepted') widget.onSaved?.call();
  }

  Future<void> _delete() async {
    final role = model.selected;
    if (role == null || role.system || role.owner || busy) return;
    if (await _confirm(
      '${t('deleteRole')} · ${role.name}',
      '${t('memberCount')}: ${role.memberCount}\n${t('deleteHelp')}',
      t('deleteRole'),
    )) {
      if (model.selected?.key == role.key) model.removeSelected();
    }
  }

  Color _roleColor(String raw) {
    return memberRoleColor(raw, fallback: context.tokens.colors.textSecondary);
  }

  Widget _list() => ListView(
    children: [
      for (final role in model.roles)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            key: ValueKey('role-${role.key}'),
            selected: role.key == model.selectedKey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: context.tokens.surfaces.panel.border),
            ),
            leading: StandardIcon(
              role.system ? StandardIconSemantic.verifiedUser : StandardIconSemantic.badge,
              color: _roleColor(role.color),
            ),
            title: Text(
              role.name,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${role.system ? '${t('systemRole')} · ' : ''}${t('memberCount')}: ${role.memberCount}',
            ),
            onTap: busy ? null : () => model.select(role.key),
          ),
        ),
    ],
  );
  Widget _editor() {
    final role = model.selected;
    if (role == null) return const SizedBox.shrink();
    return ListView(
      children: [
        TextField(
          key: const ValueKey('role-name'),
          style: Theme.of(context).textTheme.bodyMedium,
          controller: name,
          enabled: !busy,
          maxLength: communityRoleNameLimit,
          decoration: InputDecoration(labelText: t('roleName')),
          onChanged: (value) => model.update(name: value),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('role-description'),
          style: Theme.of(context).textTheme.bodyMedium,
          controller: description,
          enabled: !busy,
          maxLines: 2,
          maxLength: communityRoleDescriptionLimit,
          decoration: InputDecoration(labelText: t('roleDescription')),
          onChanged: (value) => model.update(description: value),
        ),
        Text(t('roleColor')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in {
              '#49B5F8',
              '#32D296',
              '#FFC34D',
              '#FF535D',
              '#9B7BFF',
              '#DB83C6',
              '#C5D3DE',
              role.color,
            })
              Semantics(
                label: '${t('roleColor')} $color',
                selected: role.color == color,
                child: Tooltip(
                  message: color,
                  child: IconButton(
                    onPressed: busy ? null : () => model.update(color: color),
                    icon: StandardIcon(
                      role.color == color ? StandardIconSemantic.checkCircle : StandardIconSemantic.circle,
                      color: _roleColor(color),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (role.owner)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(t('ownerHelp')),
          ),
        for (final group in communityRolePermissions.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              t(group.key),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final id in group.value)
            SwitchListTile(
              key: ValueKey(id),
              contentPadding: EdgeInsets.zero,
              title: Text(t(id), style: Theme.of(context).textTheme.bodyMedium),
              subtitle: id == 'broadcasts.publish'
                  ? Text(t('broadcastUnavailable'))
                  : null,
              value:
                  role.owner ||
                  role.permissions.any((value) => value.toLowerCase() == id),
              onChanged: busy || role.owner || id == 'broadcasts.publish'
                  ? null
                  : (value) => model.setPermission(id, value),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: widget.embedded,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: CommunityEditorSurface(
      embedded: widget.embedded,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t('rolesTitle'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (!widget.embedded)
                    IconButton(
                      onPressed: model.submitting || confirming ? null : _close,
                      tooltip: t('close'),
                      icon: const StandardIcon(StandardIconSemantic.close),
                    ),
                ],
              ),
              if (model.snapshot != null) Text(model.snapshot!.name),
              Text(
                t('rolesHelp'),
                style: TextStyle(color: context.tokens.colors.textSecondary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        busy ||
                            model.snapshot == null ||
                            model.roles.length >= 512
                        ? null
                        : () => model.add(
                            '${t('newName').characters.take(communityRoleNameLimit - '${model.roles.length + 1}'.length - 1)} ${model.roles.length + 1}',
                          ),
                    icon: const StandardIcon(StandardIconSemantic.add),
                    label: Text(t('newRole')),
                  ),
                  OutlinedButton(
                    onPressed:
                        busy || model.selected == null || model.selected!.owner
                        ? null
                        : () => model.add(
                            '${model.selected!.name.characters.take(communityRoleNameLimit - t('copySuffix').characters.length - 1)} ${t('copySuffix')}',
                            copySelected: true,
                          ),
                    child: Text(t('copyRole')),
                  ),
                  OutlinedButton(
                    onPressed:
                        busy ||
                            model.selected == null ||
                            model.selected!.system ||
                            model.selected!.owner
                        ? null
                        : _delete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    child: Text(t('deleteRole')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (model.loading || model.submitting)
                const LinearProgressIndicator(),
              Expanded(
                child: model.snapshot == null
                    ? Center(
                        child: Text(
                          model.error == null ? t('loading') : t(model.error!),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth >= 620
                            ? Row(
                                children: [
                                  SizedBox(
                                    width: widget.embedded ? 210 : 260,
                                    child: _list(),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(child: _editor()),
                                ],
                              )
                            : Column(
                                children: [
                                  SizedBox(height: 140, child: _list()),
                                  const Divider(),
                                  Expanded(child: _editor()),
                                ],
                              ),
                      ),
              ),
              if (model.error != null && model.snapshot != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    t(model.error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const Divider(),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    t(
                      model.dirty
                          ? 'dirty'
                          : model.outcome?.status == 'accepted'
                          ? 'saved'
                          : 'clean',
                    ),
                  ),
                  TextButton(
                    onPressed:
                        model.loading ||
                            model.submitting ||
                            confirming ||
                            model.invalidated
                        ? null
                        : _reload,
                    child: Text(t('reloadRoles')),
                  ),
                  TextButton(
                    onPressed: busy || !model.dirty
                        ? null
                        : () {
                            model.discard();
                            shownKey = null;
                            _changed();
                          },
                    child: Text(t('discard')),
                  ),
                  FilledButton(
                    onPressed: confirming || !model.canSave ? null : _save,
                    child: Text(t('save')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
