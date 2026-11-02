import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/chrome/presence_color.dart';
import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../common/user_avatar_menu.dart';
import '../common/social_read_activity.dart';
import 'community_ownership_exit_controller.dart';
import 'community_ownership_exit_copy.dart';
import 'community_ownership_exit_port.dart';
import 'community_workspace_controller.dart';
import 'community_workspace_image.dart';
import 'community_workspace_port.dart';
import 'community_workspace_copy.dart';

/// Uses the same current member directory and exit command as the workspace.
/// Candidate selection is read-only; only the explicit confirmation can write.
class CommunityOwnershipExitDialog extends StatefulWidget {
  const CommunityOwnershipExitDialog({
    super.key,
    required this.port,
    required this.workspacePort,
    required this.targetRef,
    this.contextInvalidations,
  });
  final CommunityOwnershipExitPort port;
  final CommunityWorkspacePort workspacePort;
  final String targetRef;
  final Stream<void>? contextInvalidations;
  @override
  State<CommunityOwnershipExitDialog> createState() =>
      _CommunityOwnershipExitDialogState();
}

class _CommunityOwnershipExitDialogState
    extends State<CommunityOwnershipExitDialog> {
  late final directory = CommunityWorkspaceController(
    widget.workspacePort,
    widget.targetRef,
  );
  final search = TextEditingController();
  final subscriptions = <StreamSubscription<void>>[];
  CommunityOwnershipExitController? confirmation;
  String? organizationName;
  bool invalidated = false;
  String invalidationError = 'identityUnavailable';
  late final SocialReadActivityBinding _directoryActivity;
  SocialReadActivityBinding? _previewActivity, _submitActivity;
  String t(String key) => ownershipExitText(context, key);
  @override
  void initState() {
    super.initState();
    _directoryActivity = SocialReadActivityBinding(
      directory,
      () => directory.busy,
      initialRead: true,
      phaseIdentity: () => directory.readEpoch,
    );
    directory.addListener(_changed);
    subscriptions.add(widget.port.invalidations.listen((_) => _invalidate()));
    subscriptions.add(
      widget.workspacePort.invalidations.listen((_) => _invalidate()),
    );
    if (widget.contextInvalidations != null) {
      subscriptions.add(
        widget.contextInvalidations!.listen((_) => _invalidate()),
      );
    }
    if (widget.port.ownershipExitAvailable) unawaited(directory.load());
  }

  @override
  void didUpdateWidget(covariant CommunityOwnershipExitDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.workspacePort != widget.workspacePort ||
        oldWidget.targetRef != widget.targetRef) {
      _invalidate();
    }
  }

  void _invalidate([String reason = 'identityUnavailable']) {
    if (!mounted || invalidated) return;
    invalidated = true;
    invalidationError = reason;
    organizationName = null;
    search.clear();
    directory.invalidate();
    confirmation?.invalidate();
    setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    if (const {
      'identityUnavailable',
      'notAllowed',
      'refreshRequired',
    }.contains(directory.error)) {
      _invalidate(directory.error!);
      return;
    }
    setState(() {});
  }

  void _choose(CommunityWorkspace page, CommunityWorkspaceMember member) {
    if (invalidated ||
        confirmation != null ||
        directory.workspace != page ||
        directory.busy ||
        page.targetRef != widget.targetRef ||
        page.access['isOwner'] != true ||
        member.isSelf ||
        member.isOwner ||
        !widget.port.ownershipExitAvailable) {
      return;
    }
    organizationName = page.name;
    confirmation = CommunityOwnershipExitController(
      widget.port,
      widget.targetRef,
      member.memberRef,
    );
    final next = confirmation!;
    _previewActivity = SocialReadActivityBinding(
      next,
      () => next.loading,
      initialRead: false,
    );
    _submitActivity = SocialReadActivityBinding(
      next,
      () => next.submitting,
      initialRead: false,
    );
    next.addListener(_changed);
    unawaited(confirmation!.load());
    setState(() {});
  }

  void _back() {
    final model = confirmation;
    if (model == null ||
        model.submitting ||
        model.requiresRetryConfirmation ||
        model.invalidated ||
        invalidated) {
      return;
    }
    _clearConfirmationActivity();
    model.removeListener(_changed);
    model.dispose();
    confirmation = null;
    organizationName = null;
    unawaited(directory.load(search: search.text));
    setState(() {});
  }

  @override
  void dispose() {
    _directoryActivity.dispose();
    _clearConfirmationActivity();
    for (final sub in subscriptions) {
      unawaited(sub.cancel());
    }
    directory.removeListener(_changed);
    directory.dispose();
    confirmation?.removeListener(_changed);
    confirmation?.dispose();
    search.dispose();
    super.dispose();
  }

  void _clearConfirmationActivity() {
    _previewActivity?.dispose();
    _submitActivity?.dispose();
    _previewActivity = _submitActivity = null;
  }

  Widget _candidates() {
    final page = directory.workspace;
    if (page != null && page.targetRef != widget.targetRef) {
      return Text(t('dataInvalid'));
    }
    final members =
        page?.members.where((m) => !m.isSelf && !m.isOwner).toList() ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(t('help')),
        const SizedBox(height: 12),
        StarBridgeFieldFrame(
          builder: (_, focus) => TextField(
            key: const Key('ownership-exit-search'),
            focusNode: focus,
            controller: search,
            maxLength: 128,
            enabled: !directory.busy && widget.port.ownershipExitAvailable,
            onSubmitted: (value) => unawaited(
              runStarBridgeActivation<void>(
                InteractionSource.keyboard,
                () => directory.load(search: value),
              ),
            ),
            decoration: InputDecoration(
              labelText: t('search'),
              suffixIcon: StarBridgeIconAction(
                controlKey: const Key('ownership-exit-search-submit'),
                label: t('search'),
                icon: const StandardIcon(StandardIconSemantic.search),
                onActivate:
                    directory.busy || !widget.port.ownershipExitAvailable
                    ? null
                    : (_) => directory.load(search: search.text),
              ),
            ),
          ),
        ),
        if (directory.busy)
          KeyedSubtree(
            key: ValueKey(_directoryActivity.revision),
            child: SocialReadActivity(
              key: const ValueKey('exit-directory-activity'),
              source: _directoryActivity.source,
              opening: _directoryActivity.opening,
              label: t('activityDirectory'),
              height: 4,
            ),
          ),
        if (directory.error != null)
          Text(
            t(directory.error!),
            style: TextStyle(color: context.tokens.colors.warning),
          ),
        if (!widget.port.ownershipExitAvailable) Text(t('unavailable')),
        if (page != null && page.access['isOwner'] != true)
          Text(t('notAllowed')),
        if (page != null && page.access['isOwner'] == true) ...[
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                t(
                  page.totalCount <= 1 && directory.query.isEmpty
                      ? 'empty'
                      : 'noMatch',
                ),
              ),
            ),
          for (final member in members)
            Container(
              key: ValueKey('successor-${member.memberRef}'),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                border: Border.all(color: context.tokens.surfaces.panel.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: StarBridgeActionRow(
                controlKey: ValueKey('successor-action-${member.memberRef}'),
                semanticLabel: '${t('choose')} · ${member.displayName}',
                onActivate: (_, _) => _choose(page, member),
                child: ListTile(
                  leading: UserAvatarMenu(
                    name: member.displayName,
                    avatarBytes: directory.image(member.memberRef),
                    target: UserTarget.community(
                      widget.targetRef,
                      member.memberRef,
                      query: member.gameName,
                    ),
                    actions: [
                      AvatarMenuAction(
                        t('choose'),
                        () => _choose(page, member),
                      ),
                    ],
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CommunityWorkspaceImage(
                        bytes: directory.image(member.memberRef),
                        loading: directory.imageLoading(member.memberRef),
                        loadFailed: directory.imageFailed(member.memberRef),
                        icon: StandardIconSemantic.person,
                      ),
                    ),
                  ),
                  title: Text(
                    member.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                  subtitle: _candidateDetails(member),
                  trailing: const StandardIcon(
                    StandardIconSemantic.chevronRight,
                  ),
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              StarBridgeActionButton(
                controlKey: const Key('ownership-exit-previous'),
                kind: StarBridgeActionKind.quiet,
                onActivate: directory.busy || page.offset == 0
                    ? null
                    : (_) => directory.load(
                        offset: (page.offset - 20).clamp(0, page.matchedCount),
                      ),
                child: Text(t('previous')),
              ),
              StarBridgeActionButton(
                controlKey: const Key('ownership-exit-next'),
                kind: StarBridgeActionKind.quiet,
                onActivate: directory.busy || page.next == null
                    ? null
                    : (_) => directory.load(offset: page.next!),
                child: Text(t('next')),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _candidateDetails(CommunityWorkspaceMember member) {
    final key = switch (member.liveStatus.toLowerCase()) {
      'paused' => 'paused',
      _ when !member.online => 'presence.offline',
      'ingame' => 'presence.inGame',
      'away' => 'presence.away',
      _ => 'presence.online',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (member.gameName.isNotEmpty && member.gameName != member.displayName)
          Text(member.gameName, maxLines: 1, overflow: TextOverflow.fade,
          softWrap: false),
        Wrap(
          spacing: 8,
          children: [
            if (member.roleTitle.isNotEmpty)
              Text(
                member.roleTitle,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
              ),
            Text(
              key == 'paused'
                  ? workspaceText(context, 'paused')
                  : AppStrings.of(context).text(key),
              style: TextStyle(
                color: presenceColor(context.tokens.colors, key),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _confirm(CommunityOwnershipExitController model) {
    final successor = model.snapshot?.successor;
    final activity = model.loading ? _previewActivity! : _submitActivity!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (model.loading || model.submitting)
          KeyedSubtree(
            key: ValueKey((model, model.loading, activity.revision)),
            child: SocialReadActivity(
              key: ValueKey(
                model.loading ? 'exit-preview-activity' : 'exit-write-activity',
              ),
              source: activity.source,
              opening: false,
              label: t(model.loading ? 'activityPreview' : 'activitySending'),
              height: 4,
            ),
          ),
        if (successor != null) ...[
          Text(
            successor.displayName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (successor.gameName.isNotEmpty &&
              successor.gameName != successor.displayName)
            Text(successor.gameName),
          Text(organizationName ?? ''),
          const SizedBox(height: 16),
          Text(t(successor.canTransfer ? 'consequence' : 'protected')),
        ],
        if (model.requiresRetryConfirmation) ...[
          const SizedBox(height: 12),
          Text(
            t('retryHelp'),
            style: TextStyle(color: context.tokens.colors.warning),
          ),
        ],
        if (model.error != null) ...[
          const SizedBox(height: 12),
          Text(
            t(model.error!),
            style: TextStyle(color: context.tokens.colors.warning),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = confirmation;
    final closed = invalidated || model?.invalidated == true;
    return PopScope(
      canPop: model?.submitting != true,
      child: AlertDialog(
        icon: StandardIcon(
          StandardIconSemantic.logout,
          color: context.tokens.colors.warning,
        ),
        title: Text(t(model == null ? 'choose' : 'title')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: invalidated
                ? Text(t(invalidationError))
                : model == null
                ? _candidates()
                : _confirm(model),
          ),
        ),
        actions: [
          StarBridgeActionButton(
            controlKey: const Key('ownership-exit-cancel'),
            kind: StarBridgeActionKind.quiet,
            onActivate: model?.submitting == true
                ? null
                : (source) => dismissStarBridgeDialog(
                    context,
                    source: source,
                    result: false,
                  ),
            child: Text(t(closed ? 'close' : 'cancel')),
          ),
          if (!closed && model != null && !model.requiresRetryConfirmation)
            StarBridgeActionButton(
              controlKey: const Key('ownership-exit-back'),
              kind: StarBridgeActionKind.quiet,
              onActivate: model.submitting ? null : (_) => _back(),
              child: Text(t('back')),
            ),
          if (!closed &&
              (model?.error != null ||
                  directory.error != null ||
                  model?.requiresRetryConfirmation == true))
            StarBridgeActionButton(
              controlKey: const Key('ownership-exit-reload'),
              kind: StarBridgeActionKind.quiet,
              onActivate:
                  model?.loading == true ||
                      model?.submitting == true ||
                      directory.busy
                  ? null
                  : (_) => model != null
                        ? model.load()
                        : directory.load(search: search.text),
              child: Text(t('reload')),
            ),
          if (model != null)
            StarBridgeActionButton(
              controlKey: const Key('ownership-exit-confirm'),
              kind: StarBridgeActionKind.primary,
              tone: ActionTone.warning,
              onActivate: closed || !model.canLeave
                  ? null
                  : (source) async {
                      await model.leave(
                        confirmUncertainRetry: model.requiresRetryConfirmation,
                      );
                      if (mounted && !invalidated && model.left) {
                        dismissStarBridgeDialog(
                          this.context,
                          source: source,
                          result: true,
                        );
                      }
                    },
              child: Text(
                t(model.requiresRetryConfirmation ? 'retry' : 'title'),
              ),
            ),
        ],
      ),
    );
  }
}
