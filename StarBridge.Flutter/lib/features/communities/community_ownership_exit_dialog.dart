import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/chrome/presence_color.dart';
import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/user_avatar_menu.dart';
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
  String t(String key) => ownershipExitText(context, key);
  @override
  void initState() {
    super.initState();
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
    )..addListener(_changed);
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
    model.removeListener(_changed);
    model.dispose();
    confirmation = null;
    organizationName = null;
    unawaited(directory.load(search: search.text));
    setState(() {});
  }

  @override
  void dispose() {
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
        TextField(
          controller: search,
          maxLength: 128,
          enabled: !directory.busy && widget.port.ownershipExitAvailable,
          onSubmitted: (value) => directory.load(search: value),
          decoration: InputDecoration(
            labelText: t('search'),
            suffixIcon: IconButton(
              tooltip: t('search'),
              icon: const StandardIcon(StandardIconSemantic.search),
              onPressed: directory.busy || !widget.port.ownershipExitAvailable
                  ? null
                  : () => directory.load(search: search.text),
            ),
          ),
        ),
        if (directory.busy) const LinearProgressIndicator(),
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
              child: ListTile(
                onTap: () => _choose(page, member),
                leading: UserAvatarMenu(
                  name: member.displayName,
                  avatarBytes: directory.image(member.memberRef),
                  target: UserTarget.community(widget.targetRef, member.memberRef, query: member.gameName),
                  actions: [
                    AvatarMenuAction(t('choose'), () => _choose(page, member)),
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
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: _candidateDetails(member),
                trailing: const StandardIcon(StandardIconSemantic.chevronRight),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: directory.busy || page.offset == 0
                    ? null
                    : () => directory.load(
                        offset: (page.offset - 20).clamp(0, page.matchedCount),
                      ),
                child: Text(t('previous')),
              ),
              TextButton(
                onPressed: directory.busy || page.next == null
                    ? null
                    : () => directory.load(offset: page.next!),
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
          Text(member.gameName, maxLines: 1, overflow: TextOverflow.ellipsis),
        Wrap(
          spacing: 8,
          children: [
            if (member.roleTitle.isNotEmpty)
              Text(
                member.roleTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (model.loading || model.submitting) const LinearProgressIndicator(),
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
        icon: StandardIcon(StandardIconSemantic.logout, color: context.tokens.colors.warning),
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
          TextButton(
            onPressed: model?.submitting == true
                ? null
                : () => Navigator.pop(context, false),
            child: Text(t(closed ? 'close' : 'cancel')),
          ),
          if (!closed && model != null && !model.requiresRetryConfirmation)
            TextButton(
              onPressed: model.submitting ? null : _back,
              child: Text(t('back')),
            ),
          if (!closed &&
              (model?.error != null ||
                  directory.error != null ||
                  model?.requiresRetryConfirmation == true))
            TextButton(
              onPressed:
                  model?.loading == true ||
                      model?.submitting == true ||
                      directory.busy
                  ? null
                  : () => model != null
                        ? model.load()
                        : directory.load(search: search.text),
              child: Text(t('reload')),
            ),
          if (model != null)
            FilledButton(
              style: semanticActionStyle(
                context,
                ActionTone.warning,
                emphasis: ActionEmphasis.filled,
              ),
              onPressed: closed || !model.canLeave
                  ? null
                  : () async {
                      await model.leave(
                        confirmUncertainRetry: model.requiresRetryConfirmation,
                      );
                      if (mounted && !invalidated && model.left) {
                        Navigator.pop(this.context, true);
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
