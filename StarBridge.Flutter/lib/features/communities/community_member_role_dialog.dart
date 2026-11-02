import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../common/social_read_activity.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

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
  final confirmations = <StarBridgeDialogRoute<bool>>[];
  bool confirming = false;
  StreamSubscription<void>? _contextSubscription;
  late final SocialReadActivityBinding _reading, _sending;
  String t(String key) => memberRoleText(context, key);
  @override
  void initState() {
    super.initState();
    _reading = SocialReadActivityBinding(
      model,
      () => model.loading,
      initialRead: true,
    );
    _sending = SocialReadActivityBinding(
      model,
      () => model.submitting,
      initialRead: false,
    );
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
        retireStarBridgeDialog(route);
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _reading.dispose();
    _sending.dispose();
    for (final route in confirmations.toList()) {
      retireStarBridgeDialog(route);
    }
    unawaited(_contextSubscription?.cancel());
    model.removeListener(_changed);
    model.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String text, String action) async {
    if (confirming || model.invalidated) return false;
    setState(() => confirming = true);
    StarBridgeDialogRoute<bool>? route;
    try {
      return await showStarBridgeDialog<bool>(
                context,
                useRootNavigator: false,
                builder: (context) => AlertDialog(
                  title: Text(title),
                  content: SingleChildScrollView(child: Text(text)),
                  actions: [
                    StarBridgeActionButton(
                      controlKey: const Key('member-role-confirm-cancel'),
                      kind: StarBridgeActionKind.quiet,
                      onActivate: (source) => dismissStarBridgeDialog(
                        context,
                        source: source,
                        result: false,
                      ),
                      child: Text(memberRoleText(context, 'cancel')),
                    ),
                    StarBridgeActionButton(
                      controlKey: const Key('member-role-confirm-accept'),
                      kind: StarBridgeActionKind.primary,
                      onActivate: (source) => dismissStarBridgeDialog(
                        context,
                        source: source,
                        result: true,
                      ),
                      child: Text(action),
                    ),
                  ],
                ),
                onRouteCreated: (opened) {
                  route = opened;
                  confirmations.add(opened);
                },
              ) ==
              true &&
          mounted &&
          !model.invalidated;
    } finally {
      confirmations.remove(route);
      if (mounted) setState(() => confirming = false);
    }
  }

  Future<void> _close({InteractionSource? source}) async {
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
    if (mounted) {
      dismissStarBridgeDialog(
        context,
        source: source ?? currentStarBridgeActivationSource,
      );
    }
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
    if (mounted && model.saved) {
      dismissStarBridgeDialog(
        context,
        source: currentStarBridgeActivationSource,
        result: true,
      );
    }
  }

  Widget _option(String key, String name, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: StarBridgeActionRow(
      controlKey: ValueKey('assign-option-$key'),
      semanticLabel: name,
      semanticSelected: model.selectedKey == key,
      onActivate: !model.locked && !confirming && model.snapshot!.canAssign
          ? (_, _) => model.select(key)
          : null,
      child: ListTile(
        enabled: !model.locked && !confirming && model.snapshot!.canAssign,
        selected: model.selectedKey == key,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: context.tokens.surfaces.panel.border),
        ),
        leading: StandardIcon(StandardIconSemantic.badge, color: color),
        title: StarBridgeTooltip(
          message: name,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        trailing: StandardIcon(
          model.selectedKey == key
              ? StandardIconSemantic.radioButtonChecked
              : StandardIconSemantic.radioButtonUnchecked,
          size: 20,
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final activity = model.loading ? _reading : _sending;
    final snapshot = model.snapshot;
    return PopScope(
      canPop:
          !model.dirty &&
          !model.submitting &&
          !confirming &&
          !model.requiresRetryConfirmation,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close(source: InteractionSource.keyboard));
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
                    StarBridgeIconAction(
                      controlKey: const Key('member-role-close'),
                      onActivate: model.submitting || confirming
                          ? null
                          : (source) => _close(source: source),
                      label: t('close'),
                      icon: const StandardIcon(StandardIconSemantic.close),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: model.loading || model.submitting
                      ? Center(
                          child: KeyedSubtree(
                            key: ValueKey((model.loading, activity.revision)),
                            child: SocialReadActivity(
                              key: const ValueKey('role-activity'),
                              source: activity.source,
                              opening: activity.opening,
                              label: t(
                                model.loading
                                    ? 'activityLoading'
                                    : 'activitySending',
                              ),
                              height: 4,
                              circularStandard: true,
                            ),
                          ),
                        )
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
                    StarBridgeActionButton(
                      controlKey: const Key('member-role-reload'),
                      kind: StarBridgeActionKind.quiet,
                      onActivate:
                          model.loading ||
                              model.submitting ||
                              confirming ||
                              model.invalidated
                          ? null
                          : (_) => _reload(),
                      child: Text(t('reloadAssignment')),
                    ),
                    StarBridgeActionButton(
                      controlKey: const Key('member-role-save'),
                      kind: StarBridgeActionKind.primary,
                      onActivate: model.canSave && !confirming
                          ? (_) => _save()
                          : null,
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
