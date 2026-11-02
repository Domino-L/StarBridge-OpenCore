import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'community_visible_refresh.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/user_avatar_menu.dart';
import '../common/social_read_activity.dart';
import '../party_rooms/room_display.dart' show roomDate;
import 'community_admissions_port.dart';
import 'community_management_controller.dart';
import 'community_management_copy.dart';
import 'community_workspace_image.dart';
import 'community_editor_surface.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

class CommunityManagementDialog extends StatefulWidget {
  const CommunityManagementDialog({
    required this.port,
    required this.targetRef,
    required this.name,
    this.initialSection = 'applications',
    this.sections = const ['applications', 'invites'],
    this.embedded = false,
    this.onMembersChanged,
    super.key,
  });
  final CommunityAdmissionsPort port;
  final String targetRef, name, initialSection;

  /// The pages offered; an invite-only member gets only the invite page.
  final List<String> sections;
  final bool embedded;
  final VoidCallback? onMembersChanged;
  @override
  State<CommunityManagementDialog> createState() =>
      CommunityManagementDialogState();
}

class CommunityManagementDialogState extends State<CommunityManagementDialog>
    with CommunityVisibleRefresh<CommunityManagementDialog> {
  @override
  Future<void> refreshVisibleCommunity() => confirming || model.page == null
      ? Future<void>.value()
      : model.load(offset: model.page!.offset, quiet: true);
  Future<bool> confirmLeave() async => !model.submitting && !confirming;
  late final model = CommunityManagementController(
    widget.port,
    widget.targetRef,
    section: widget.initialSection,
  );
  final confirmations = <StarBridgeDialogRoute<bool>>[];
  int days = 7, uses = 1;
  bool confirming = false;
  String? copyStatus;
  Timer? _copiedTimer;
  Timer? _clock;
  late final SocialReadActivityBinding _reading, _sending;
  String t(String key) => managementText(context, key);
  bool get locked => model.locked || confirming;
  @override
  void initState() {
    super.initState();
    _reading = SocialReadActivityBinding(
      model,
      () => model.busy && !model.invalidated,
      initialRead: true,
    );
    _sending = SocialReadActivityBinding(
      model,
      () => model.submitting && !model.invalidated,
      initialRead: false,
    );
    model.addListener(changed);
    unawaited(model.load());
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && !model.invalidated) setState(() {});
    });
  }

  void changed() {
    if (!mounted) return;
    if (model.invalidated) {
      for (final route in confirmations.toList().reversed) {
        retireStarBridgeDialog(route);
      }
      if (!widget.embedded) {
        final route = ModalRoute.of(context);
        if (route is StarBridgeDialogRoute) {
          retireStarBridgeDialog(route);
        } else if (route?.isActive == true) {
          route!.navigator?.removeRoute(route);
        }
      } else {
        setState(() {});
      }
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _reading.dispose();
    _sending.dispose();
    _clock?.cancel();
    for (final route in confirmations.toList()) {
      retireStarBridgeDialog(route);
    }
    model.removeListener(changed);
    model.dispose();
    super.dispose();
  }

  Future<void> act(
    CommunityAdmissionAction action, {
    Map<String, Object?>? row,
  }) async {
    if (locked) return;
    setState(() => confirming = true);
    final retry = model.outcome?.status == 'unknown';
    final danger =
        action == CommunityAdmissionAction.decline ||
        action == CommunityAdmissionAction.revokeInvite;
    StarBridgeDialogRoute<bool>? route;
    final approved = await showStarBridgeDialog<bool>(
      context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(managementText(dialogContext, action.name)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name),
            if (row != null)
              Text(
                (row['callsign'] ?? row['code'] ?? row['gameName'] ?? '')
                    as String,
              ),
            const SizedBox(height: 12),
            Text(managementText(dialogContext, '${action.name}Confirm')),
            if (retry)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  managementText(dialogContext, 'retryWarning'),
                  style: TextStyle(color: dialogContext.tokens.colors.warning),
                ),
              ),
          ],
        ),
        actions: [
          StarBridgeActionButton(
            controlKey: const Key('management-confirm-cancel'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) => dismissStarBridgeDialog(
              dialogContext,
              source: source,
              result: false,
            ),
            child: Text(managementText(dialogContext, 'cancel')),
          ),
          StarBridgeActionButton(
            controlKey: const Key('management-confirm-accept'),
            kind: StarBridgeActionKind.primary,
            tone: danger ? ActionTone.danger : null,
            onActivate: (source) => dismissStarBridgeDialog(
              dialogContext,
              source: source,
              result: true,
            ),
            child: Text(managementText(dialogContext, action.name)),
          ),
        ],
      ),
      onRouteCreated: (opened) {
        route = opened;
        confirmations.add(opened);
      },
    );
    confirmations.remove(route);
    if (!mounted || model.invalidated) return;
    setState(() => confirming = false);
    if (approved != true) return;
    setState(() => copyStatus = null);
    await model.execute(
      action,
      entryRef: row?['entryRef'] as String?,
      days: action == CommunityAdmissionAction.generateInvite ? days : null,
      uses: action == CommunityAdmissionAction.generateInvite ? uses : null,
      confirmUncertainRetry: retry,
    );
    if (mounted &&
        model.outcome?.status == 'accepted' &&
        action == CommunityAdmissionAction.approve) {
      widget.onMembersChanged?.call();
    }
  }

  Future<void> copy(Map<String, Object?> row) async {
    if (locked) return;
    final page = model.page;
    try {
      await Clipboard.setData(ClipboardData(text: row['code'] as String));
      if (mounted && !model.invalidated && identical(page, model.page)) {
        setState(() => copyStatus = 'copied');
        // QualityPass ②: the confirmation clears itself; a failure stays.
        _copiedTimer?.cancel();
        _copiedTimer = Timer(starBridgeTransientDuration, () {
          if (mounted && copyStatus == 'copied') {
            setState(() => copyStatus = null);
          }
        });
      }
    } catch (_) {
      if (mounted && !model.invalidated && identical(page, model.page)) {
        setState(() => copyStatus = 'copyFailed');
      }
    }
  }

  Widget box(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.tokens.surfaces.raised.fill,
      border: Border.all(color: context.tokens.surfaces.panel.border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: child,
  );
  Widget application(Map<String, Object?> row) {
    final searchHint = (row['callsign'] as String).isNotEmpty
        ? row['callsign'] as String
        : row['gameName'] as String;
    final name = [
      row['callsign'],
      row['gameName'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final allowed =
        model.page!.access['canDecideApplications'] == true && !locked;
    return box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatarMenu(
                name: name,
                target: UserTarget(
                  'communityApplicant',
                  row['entryRef'] as String,
                  contextRef: widget.targetRef,
                  query: searchHint.length <= 128
                      ? searchHint
                      : searchHint.substring(0, 128),
                ),
                avatarBytes: model.images[row['entryRef']],
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: CommunityWorkspaceImage(
                    bytes: model.images[row['entryRef']],
                    loading: model.pendingImages.contains(row['entryRef']),
                    icon: StandardIconSemantic.person,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (row['createdAt'] is DateTime)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                roomDate(context, row['createdAt'] as DateTime),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if ((row['message'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(row['message'] as String),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StarBridgeActionButton(
                controlKey: ValueKey('management-approve-${row['entryRef']}'),
                tone: ActionTone.success,
                onActivate: allowed
                    ? (_) => act(CommunityAdmissionAction.approve, row: row)
                    : null,
                child: Text(t('approve')),
              ),
              StarBridgeActionButton(
                controlKey: ValueKey('management-decline-${row['entryRef']}'),
                tone: ActionTone.danger,
                onActivate: allowed
                    ? (_) => act(CommunityAdmissionAction.decline, row: row)
                    : null,
                child: Text(t('decline')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget invitation(Map<String, Object?> row, {bool current = false}) {
    final expires = row['expiresAt'] as DateTime?;
    final remaining = expires?.difference(model.serverNow);
    final expired = remaining != null && remaining <= Duration.zero;
    final active = row['status'] == 'Active' && !expired;
    return box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (current)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                t('currentInvite'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SelectableText(
                row['code'] as String,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (row['isOwn'] == true) Text(t('own')),
              Text(
                t(
                  row['status'] == 'Active' && expired
                      ? 'Expired'
                      : row['status'] as String,
                ),
                style: TextStyle(
                  color: active
                      ? context.tokens.colors.success
                      : context.tokens.colors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(row['createdBy'] as String),
          if (row['createdAt'] is DateTime)
            Text(
              '${t('created')}: ${roomDate(context, row['createdAt'] as DateTime)}',
            ),
          if (row['expiresAt'] is DateTime)
            Text(
              '${t('expires')}: ${roomDate(context, row['expiresAt'] as DateTime)}',
            ),
          if (active && remaining != null)
            Text(managementRemainingText(context, remaining)),
          Text(
            '${t('used')}: ${row['usedCount']} / ${row['maxUses'] == 0 ? t('unlimited') : row['maxUses']}',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StarBridgeActionButton(
                controlKey: ValueKey('management-copy-${row['entryRef']}'),
                onActivate: !locked && active ? (_) => copy(row) : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const StandardIcon(StandardIconSemantic.copy),
                    const SizedBox(width: 8),
                    Text(t('copy')),
                  ],
                ),
              ),
              StarBridgeActionButton(
                controlKey: ValueKey('management-revoke-${row['entryRef']}'),
                tone: ActionTone.danger,
                onActivate: !locked && active && row['canRevoke'] == true
                    ? (_) =>
                          act(CommunityAdmissionAction.revokeInvite, row: row)
                    : null,
                child: Text(t('revokeInvite')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = model.page;
    return PopScope(
      canPop: !model.submitting && !confirming,
      child: CommunityEditorSurface(
        embedded: widget.embedded,
        child: SizedBox(
          width: widget.embedded ? null : 860,
          height: widget.embedded
              ? null
              : MediaQuery.sizeOf(context).height * .86,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('title'), style: Theme.of(context).textTheme.titleLarge),
                Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final section in widget.sections)
                      StarBridgeChoiceChip(
                        controlKey: ValueKey('management-section-$section'),
                        label: t(section),
                        selected: model.section == section,
                        onSelected: locked
                            ? null
                            : (_) {
                                copyStatus = null;
                                model.load(section: section);
                              },
                      ),
                    StarBridgeActionButton(
                      controlKey: const Key('management-refresh'),
                      kind: StarBridgeActionKind.quiet,
                      onActivate: locked
                          ? null
                          : (_) {
                              copyStatus = null;
                              model.load();
                            },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const StandardIcon(StandardIconSemantic.refresh),
                          const SizedBox(width: 8),
                          Text(t('refresh')),
                        ],
                      ),
                    ),
                  ],
                ),
                if (model.outcome != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      t(
                        model.outcome!.status == 'rejected'
                            ? model.outcome!.error ?? 'unavailable'
                            : model.outcome!.status,
                      ),
                      style: TextStyle(
                        color: model.outcome!.status == 'accepted'
                            ? context.tokens.colors.success
                            : context.tokens.colors.warning,
                      ),
                    ),
                  ),
                if (copyStatus != null) Text(t(copyStatus!)),
                if (model.mediaFailed) Text(t('mediaFailed')),
                if (model.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(t(model.error!)),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: model.invalidated
                      ? Center(child: Text(t('identityUnavailable')))
                      : model.busy
                      ? Center(
                          child: KeyedSubtree(
                            key: ValueKey(_reading.revision),
                            child: SocialReadActivity(
                              key: const ValueKey('management-read-activity'),
                              source: _reading.source,
                              opening: _reading.opening,
                              label: t(
                                model.section == 'applications'
                                    ? 'activityApplications'
                                    : 'activityInvites',
                              ),
                              height: 4,
                              circularStandard: true,
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            if (page != null && page.section == 'invites') ...[
                              if (page.currentInvite != null)
                                invitation(page.currentInvite!, current: true)
                              else
                                box(
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t('currentInvite'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        t(
                                          page.currentInviteAvailable
                                              ? 'noCurrentInvite'
                                              : 'currentInviteUnavailable',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            if (page != null &&
                                page.section == 'invites' &&
                                page.access['canCreateInvite'] == true)
                              box(
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 150,
                                      child: StarBridgeSelectFormField<int>(
                                        identity: 'community-invite-days',
                                        isExpanded: true,
                                        controlKey: const ValueKey(
                                          'community-invite-days-control',
                                        ),
                                        initialValue: days,
                                        decoration: InputDecoration(
                                          labelText: t('days'),
                                        ),
                                        items: [
                                          for (final day in [1, 7, 30])
                                            DropdownMenuItem(
                                              value: day,
                                              child: Text('$day'),
                                            ),
                                        ],
                                        onChanged: locked
                                            ? null
                                            : (value) =>
                                                  setState(() => days = value!),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 150,
                                      child: StarBridgeSelectFormField<int>(
                                        identity: 'community-invite-uses',
                                        isExpanded: true,
                                        controlKey: const ValueKey(
                                          'community-invite-uses-control',
                                        ),
                                        initialValue: uses,
                                        decoration: InputDecoration(
                                          labelText: t('uses'),
                                        ),
                                        items: [
                                          for (final use in [1, 5, 10, 0])
                                            DropdownMenuItem(
                                              value: use,
                                              child: Text(
                                                use == 0
                                                    ? t('unlimited')
                                                    : '$use',
                                              ),
                                            ),
                                        ],
                                        onChanged: locked
                                            ? null
                                            : (value) =>
                                                  setState(() => uses = value!),
                                      ),
                                    ),
                                    StarBridgeActionButton(
                                      controlKey: const Key(
                                        'management-generate',
                                      ),
                                      kind: StarBridgeActionKind.primary,
                                      onActivate: locked
                                          ? null
                                          : (_) => act(
                                              CommunityAdmissionAction
                                                  .generateInvite,
                                            ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const StandardIcon(
                                            StandardIconSemantic.add,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(t('generateInvite')),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (page != null &&
                                page.section == 'applications' &&
                                page.access['canDecideApplications'] != true)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(t('readOnly')),
                              ),
                            if (page != null && page.items.isEmpty)
                              Text(
                                t(
                                  page.section == 'applications'
                                      ? 'emptyApplications'
                                      : 'emptyInvites',
                                ),
                              ),
                            if (page != null &&
                                page.section == 'invites' &&
                                page.items.any(
                                  (row) =>
                                      row['entryRef'] !=
                                      page.currentInvite?['entryRef'],
                                ))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  t('inviteList'),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            if (page != null)
                              for (final row in page.items)
                                if (page.section == 'applications')
                                  application(row)
                                else if (row['entryRef'] !=
                                    page.currentInvite?['entryRef'])
                                  invitation(row),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (page != null) ...[
                      Text(
                        '${page.offset + (page.items.isEmpty ? 0 : 1)}–${page.offset + page.items.length} / ${page.totalCount}',
                      ),
                      StarBridgeActionButton(
                        controlKey: const Key('management-previous'),
                        kind: StarBridgeActionKind.quiet,
                        onActivate: locked || page.offset == 0
                            ? null
                            : (_) => model.load(
                                offset: (page.offset - 20).clamp(0, 1000000),
                              ),
                        child: Text(t('previous')),
                      ),
                      StarBridgeActionButton(
                        controlKey: const Key('management-next'),
                        kind: StarBridgeActionKind.quiet,
                        onActivate: locked || page.next == null
                            ? null
                            : (_) => model.load(offset: page.next!),
                        child: Text(t('next')),
                      ),
                    ],
                    if (model.submitting && !model.invalidated)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Center(
                          child: KeyedSubtree(
                            key: ValueKey(_sending.revision),
                            child: SocialReadActivity(
                              key: const ValueKey('management-write-activity'),
                              source: _sending.source,
                              opening: false,
                              label: t('activitySending'),
                              height: 4,
                              circularStandard: true,
                              circularSize: 20,
                              circularStrokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                    if (!widget.embedded)
                      StarBridgeActionButton(
                        controlKey: const Key('management-close'),
                        kind: StarBridgeActionKind.quiet,
                        onActivate: model.submitting || confirming
                            ? null
                            : (source) => dismissStarBridgeDialog(
                                context,
                                source: source,
                              ),
                        child: Text(t('close')),
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
