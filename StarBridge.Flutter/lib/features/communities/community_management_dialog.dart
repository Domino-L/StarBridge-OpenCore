import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'community_visible_refresh.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/user_avatar_menu.dart';
import '../party_rooms/room_display.dart' show roomDate;
import 'community_admissions_port.dart';
import 'community_management_controller.dart';
import 'community_management_copy.dart';
import 'community_workspace_image.dart';
import 'community_editor_surface.dart';

class CommunityManagementDialog extends StatefulWidget {
  const CommunityManagementDialog({
    required this.port,
    required this.targetRef,
    required this.name,
    this.initialSection = 'applications',
    this.embedded = false,
    this.onMembersChanged,
    super.key,
  });
  final CommunityAdmissionsPort port;
  final String targetRef, name, initialSection;
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
  final confirmations = <Route<bool>>[];
  int days = 7, uses = 1;
  bool confirming = false;
  String? copyStatus;
  Timer? _clock;
  String t(String key) => managementText(context, key);
  bool get locked => model.locked || confirming;
  @override
  void initState() {
    super.initState();
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
        if (route.isActive) route.navigator?.removeRoute(route);
      }
      if (!widget.embedded) {
        final route = ModalRoute.of(context);
        if (route?.isActive == true) route!.navigator?.removeRoute(route);
      } else {
        setState(() {});
      }
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _clock?.cancel();
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
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(t(action.name)),
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
            Text(t('${action.name}Confirm')),
            if (retry)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  t('retryWarning'),
                  style: TextStyle(color: context.tokens.colors.warning),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: context.tokens.colors.danger,
                    foregroundColor: context.tokens.colors.onAccent,
                  )
                : null,
            child: Text(t(action.name)),
          ),
        ],
      ),
    );
    confirmations.add(route);
    final approved = await Navigator.of(context).push(route);
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
              OutlinedButton(
                onPressed: allowed
                    ? () => act(CommunityAdmissionAction.approve, row: row)
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.tokens.colors.success,
                ),
                child: Text(t('approve')),
              ),
              OutlinedButton(
                onPressed: allowed
                    ? () => act(CommunityAdmissionAction.decline, row: row)
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.tokens.colors.danger,
                ),
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
              OutlinedButton.icon(
                onPressed: !locked && active ? () => copy(row) : null,
                icon: const StandardIcon(StandardIconSemantic.copy),
                label: Text(t('copy')),
              ),
              OutlinedButton(
                onPressed: !locked && active && row['canRevoke'] == true
                    ? () => act(CommunityAdmissionAction.revokeInvite, row: row)
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.tokens.colors.danger,
                ),
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
                    for (final section in const ['applications', 'invites'])
                      ChoiceChip(
                        label: Text(t(section)),
                        selected: model.section == section,
                        onSelected: locked
                            ? null
                            : (_) {
                                copyStatus = null;
                                model.load(section: section);
                              },
                      ),
                    TextButton.icon(
                      onPressed: locked
                          ? null
                          : () {
                              copyStatus = null;
                              model.load();
                            },
                      icon: const StandardIcon(StandardIconSemantic.refresh),
                      label: Text(t('refresh')),
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
                  child: model.busy
                      ? const Center(child: CircularProgressIndicator())
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
                                      child: DropdownButtonFormField<int>(
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
                                      child: DropdownButtonFormField<int>(
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
                                    FilledButton.icon(
                                      onPressed: locked
                                          ? null
                                          : () => act(
                                              CommunityAdmissionAction
                                                  .generateInvite,
                                            ),
                                      icon: const StandardIcon(StandardIconSemantic.add),
                                      label: Text(t('generateInvite')),
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
                      TextButton(
                        onPressed: locked || page.offset == 0
                            ? null
                            : () => model.load(
                                offset: (page.offset - 20).clamp(0, 1000000),
                              ),
                        child: Text(t('previous')),
                      ),
                      TextButton(
                        onPressed: locked || page.next == null
                            ? null
                            : () => model.load(offset: page.next!),
                        child: Text(t('next')),
                      ),
                    ],
                    if (model.submitting)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (!widget.embedded)
                      TextButton(
                        onPressed: model.submitting || confirming
                            ? null
                            : () => Navigator.pop(context),
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
