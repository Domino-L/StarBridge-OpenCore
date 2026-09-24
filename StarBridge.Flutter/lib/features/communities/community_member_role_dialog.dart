import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_member_role_port.dart';
import 'community_member_role_controller.dart';
import 'community_member_role_copy.dart';

class CommunityMemberRoleDialog extends StatefulWidget {
  const CommunityMemberRoleDialog({
    required this.port,
    required this.targetRef,
    required this.memberRef,
    this.contextInvalidations,
    super.key,
  });
  final CommunityMemberRolePort port;
  final String targetRef, memberRef;
  final Stream<void>? contextInvalidations;
  @override
  State<CommunityMemberRoleDialog> createState() =>
      _CommunityMemberRoleDialogState();
}

class _CommunityMemberRoleDialogState extends State<CommunityMemberRoleDialog> {
  late final model = CommunityMemberRoleController(
    widget.port,
    widget.targetRef,
    widget.memberRef,
  );
  final confirmations = <Route<bool>>[];
  bool confirming = false;
  StreamSubscription<void>? _contextSubscription;
  String t(String key) => memberRoleText(context, key);
  @override
  void initState() {
    super.initState();
    model.addListener(_changed);
    _contextSubscription = widget.contextInvalidations?.listen(
      (_) => model.invalidate(),
    );
    unawaited(model.load());
  }

  void _changed() {
    if (!mounted) return;
    if (model.invalidated) {
      for (final route in confirmations.toList()) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    unawaited(_contextSubscription?.cancel());
    model.removeListener(_changed);
    model.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String text, String action) async {
    if (confirming || model.invalidated) return false;
    setState(() => confirming = true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(text)),
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

  Future<void> _close() async {
    if (model.submitting || confirming) return;
    if (!model.invalidated &&
        (model.dirty || model.requiresRetryConfirmation) &&
        !await _confirm(
          t('leaveAssignment'),
          t('reloadAssignmentHelp'),
          t('close'),
        )) {
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reload() async {
    if ((model.dirty || model.requiresRetryConfirmation) &&
        !await _confirm(
          t('reloadAssignment'),
          t('reloadAssignmentHelp'),
          t('reloadAssignment'),
        )) {
      return;
    }
    await model.load(discardChanges: true);
  }

  Future<void> _save() async {
    if (!model.canSave || confirming) return;
    final snapshot = model.snapshot!, chosen = model.selectedKey!;
    final newName = chosen.isEmpty
        ? t('baseMember')
        : snapshot.roles.firstWhere((role) => role.key == chosen).name;
    final oldName = snapshot.roleKey.isEmpty
        ? t('baseMember')
        : snapshot.roleTitle;
    final retry = model.requiresRetryConfirmation;
    final detail =
        '${snapshot.displayName}\n$oldName → $newName\n\n${t('assignmentHelp')}${retry ? '\n\n${t('retryAssignmentHelp')}' : ''}';
    if (!await _confirm(t('confirmAssignment'), detail, t('assignRole'))) {
      return;
    }
    if (model.snapshot != snapshot || model.selectedKey != chosen) return;
    await model.save(confirmUncertainRetry: retry);
    if (mounted && model.saved) Navigator.pop(context, true);
  }

  Widget _option(String key, String name, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      key: ValueKey('assign-option-$key'),
      enabled: !model.locked && !confirming && model.snapshot!.canAssign,
      selected: model.selectedKey == key,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: context.tokens.surfaces.panel.border),
      ),
      leading: StandardIcon(StandardIconSemantic.badge, color: color),
      title: Tooltip(
        message: name,
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      trailing: StandardIcon(
        model.selectedKey == key
            ? StandardIconSemantic.radioButtonChecked
            : StandardIconSemantic.radioButtonUnchecked,
        size: 20,
      ),
      onTap: () => model.select(key),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final snapshot = model.snapshot;
    return PopScope(
      canPop:
          !model.dirty &&
          !model.submitting &&
          !confirming &&
          !model.requiresRetryConfirmation,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 560,
          height:
              (snapshot == null
                      ? 400.0
                      : 320.0 + (snapshot.roles.length + 1) * 66)
                  .clamp(
                    200,
                    (MediaQuery.sizeOf(context).height - 64).clamp(200, 620),
                  ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('assignRole'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: model.submitting || confirming ? null : _close,
                      tooltip: t('close'),
                      icon: const StandardIcon(StandardIconSemantic.close),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: model.loading || model.submitting
                      ? const Center(child: CircularProgressIndicator())
                      : snapshot == null
                      ? Center(
                          child: Text(
                            t(model.error ?? 'assignmentUnavailable'),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView(
                          children: [
                            Text(
                              snapshot.displayName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${t('currentRole')}: ${snapshot.roleKey.isEmpty ? t('baseMember') : snapshot.roleTitle}',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              t(
                                snapshot.canAssign
                                    ? 'assignmentHelp'
                                    : 'assignmentProtected',
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              t('chooseRole'),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            _option(
                              '',
                              t('baseMember'),
                              context.tokens.colors.textSecondary,
                            ),
                            for (final role in snapshot.roles)
                              _option(
                                role.key,
                                role.name,
                                Color(
                                  0xff000000 |
                                      int.parse(
                                        role.color.substring(1),
                                        radix: 16,
                                      ),
                                ),
                              ),
                            if (model.error != null)
                              Text(
                                t(model.error!),
                                style: TextStyle(
                                  color: context.tokens.colors.warning,
                                ),
                              ),
                          ],
                        ),
                ),
                const Divider(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          model.loading ||
                              model.submitting ||
                              confirming ||
                              model.invalidated
                          ? null
                          : _reload,
                      child: Text(t('reloadAssignment')),
                    ),
                    FilledButton(
                      onPressed: model.canSave && !confirming ? _save : null,
                      child: Text(t('assignRole')),
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
}
