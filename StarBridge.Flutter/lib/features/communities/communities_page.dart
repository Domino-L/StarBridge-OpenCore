import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'community_directory_presentation.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'communities_module.dart';
import 'community_directory_details.dart';
import 'example_communities.dart';
import 'community_filter_panel.dart';
import 'community_visible_refresh.dart';
import 'community_creation_dialog.dart';
import 'community_creation_port.dart';
import 'community_creation_copy.dart';
import 'community_workspace_port.dart';
import 'community_workspace_view.dart';
import 'community_invite_dialog.dart';
import 'community_invite_port.dart';
import 'community_invite_copy.dart';
import 'community_invitation_send_port.dart';
import 'community_invitation_send_copy.dart';
import 'community_invitation_outbox_dialog.dart';
import '../settings/local_privacy_port.dart';

class CommunitiesPage extends StatefulWidget {
  const CommunitiesPage({
    required this.createPort,
    this.module,
    this.createAdmissionPrivacy,
    super.key,
  });
  final CommunitiesPort Function() createPort;
  final CommunitiesModule? module;
  final LocalPrivacyPort Function()? createAdmissionPrivacy;
  @override
  State<CommunitiesPage> createState() => _CommunitiesPageState();
}

class _CommunitiesPageState extends State<CommunitiesPage>
    with CommunityVisibleRefresh<CommunitiesPage> {
  @override
  Future<void> refreshVisibleCommunity() async {
    if (!model.busy && model.selected == null && model.error != null) {
      await model.refresh();
    }
  }

  late final CommunitiesModule model;
  late final bool example;
  final search = TextEditingController();
  int revision = 0;
  final _workspaceKey = GlobalKey<CommunityWorkspaceViewState>();
  Future<bool> _confirmWorkspaceLeave() async =>
      await _workspaceKey.currentState?.confirmLeave() ?? true;
  DialogRoute<bool>? _confirmation;
  DialogRoute<String>? _filterDialog;
  DialogRoute<void>? _outboxDialog;
  DialogRoute<void>? _detailsDialog;
  bool _creating = false;
  bool _inviting = false;
  String t(String key) => AppStrings.of(context).text('communities.$key');
  @override
  void initState() {
    super.initState();
    final port = widget.module?.port ?? widget.createPort();
    example = port is ExampleCommunities;
    model = widget.module ?? CommunitiesModule(port);
    model.confirmWorkspaceLeave = _confirmWorkspaceLeave;
    revision = model.accountRevision;
    model.addListener(_changed);
    search.text = model.query;
    if (model.selected == null &&
        (model.directory == null || model.view != 'discover')) {
      scheduleMicrotask(() {
        if (mounted) unawaited(model.refresh(newView: 'discover'));
      });
    } else if (model.selected == null) {
      scheduleMicrotask(() {
        if (mounted) unawaited(model.refresh(silent: true, reuseFresh: true));
      });
    }
  }

  void _changed() {
    if (revision != model.accountRevision) {
      revision = model.accountRevision;
      search.clear();
      final route = _confirmation;
      if (route?.isActive == true) route!.navigator?.removeRoute(route, false);
      final filter = _filterDialog;
      if (filter?.isActive == true) filter!.navigator?.removeRoute(filter);
      final outbox = _outboxDialog;
      if (outbox?.isActive == true) outbox!.navigator?.removeRoute(outbox);
      final details = _detailsDialog;
      if (details?.isActive == true) details!.navigator?.removeRoute(details);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final details = _detailsDialog;
    if (details?.isActive == true) details!.navigator?.removeRoute(details);
    final outbox = _outboxDialog;
    if (outbox?.isActive == true) outbox!.navigator?.removeRoute(outbox);
    model.removeListener(_changed);
    if (model.confirmWorkspaceLeave == _confirmWorkspaceLeave) {
      model.confirmWorkspaceLeave = null;
    }
    if (widget.module == null) model.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> act(CommunityCard card, String action) async {
    final currentRevision = model.accountRevision;
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('action.$action')),
        content: Text('${card.name}\n\n${t('confirm.$action')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('action.$action')),
          ),
        ],
      ),
    );
    _confirmation = route;
    final confirmed = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    _confirmation = null;
    if (confirmed == true &&
        mounted &&
        currentRevision == model.accountRevision) {
      await model.execute(card, action);
    }
  }

  Future<void> _showDirectoryDetails(CommunityCard initial) async {
    if (_detailsDialog != null) return;
    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: model,
        builder: (_, _) {
          final row = model.directory?.items
              .where((r) => r.key == initial.key)
              .firstOrNull;
          return CommunityDirectoryDetails(
            row: row,
            text: t,
            message: model.message == null ? null : t(model.message!),
            onClose: () => Navigator.pop(dialogContext),
            onAction: row == null || !model.canExecute(row)
                ? null
                : (action) => act(row, action),
            onEnter: model.writing || row == null
                ? null
                : () {
                    Navigator.pop(dialogContext);
                    model.open(row);
                  },
          );
        },
      ),
    );
    _detailsDialog = route;
    await Navigator.of(context, rootNavigator: true).push(route);
    if (identical(_detailsDialog, route)) _detailsDialog = null;
  }

  Future<void> _openInvitationOutbox() async {
    final port = model.port;
    if (port is! CommunityInvitationSendPort || _outboxDialog != null) return;
    final route = DialogRoute<void>(
      context: context,
      builder: (_) => CommunityInvitationOutboxDialog(
        port: port as CommunityInvitationSendPort,
      ),
    );
    _outboxDialog = route;
    await Navigator.of(context).push(route);
    _outboxDialog = null;
  }

  Future<void> createOrganization() async {
    final port = model.port;
    if (_creating || model.writing || port is! CommunityCreationPort) return;
    final currentRevision = model.accountRevision;
    setState(() => _creating = true);
    final result = await showDialog<CommunityCreationOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommunityCreationDialog(
        example: example,
        port: port as CommunityCreationPort,
        invalidations: model.port.invalidations,
      ),
    );
    if (!mounted) return;
    setState(() => _creating = false);
    if (result == null || currentRevision != model.accountRevision) return;
    await model.refresh(newView: 'discover', force: true);
    if (!mounted || currentRevision != model.accountRevision) return;
    await model.refreshJoined();
    if (mounted &&
        currentRevision == model.accountRevision &&
        result.status == 'accepted') {
      model.open(result.organization);
    }
  }

  Future<void> enterInvite() async {
    final port = model.port;
    if (_inviting ||
        _creating ||
        model.writing ||
        port is! CommunityInvitePort) {
      return;
    }
    final currentRevision = model.accountRevision;
    final privacy = port is ExampleCommunities
        ? port.createAdmissionPrivacy()
        : widget.createAdmissionPrivacy?.call();
    setState(() => _inviting = true);
    await showDialog<CommunityInviteOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommunityInviteDialog(
        port: port as CommunityInvitePort,
        privacy: privacy,
        example: example,
      ),
    );
    if (!mounted) return;
    setState(() => _inviting = false);
    if (currentRevision != model.accountRevision) return;
    await model.refresh(newView: 'discover', force: true);
    if (mounted && currentRevision == model.accountRevision) {
      await model.refreshJoined();
    }
  }

  @override
  Widget build(BuildContext context) {
    final internal =
        model.selected != null &&
        const {'owner', 'member'}.contains(model.selected!.relationship);
    if (internal) {
      return Padding(padding: const EdgeInsets.all(20), child: _content());
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t('discover'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              TextButton(
                onPressed: model.busy ? null : () => model.refresh(),
                child: Text(t('refresh')),
              ),
              if (model.port is CommunityCreationPort)
                FilledButton(
                  onPressed: model.writing || _creating
                      ? null
                      : createOrganization,
                  child: Text(creationText(context, 'title')),
                ),
            ],
          ),
          Text(
            t('subtitle'),
            style: TextStyle(color: context.tokens.colors.textSecondary),
          ),
          if (example)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t('example'),
                style: TextStyle(color: context.tokens.colors.warning),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (model.port is CommunityInvitePort)
                OutlinedButton(
                  onPressed: model.writing || _creating || _inviting
                      ? null
                      : enterInvite,
                  child: Text(inviteText(context, 'title')),
                ),
              if (model.port is CommunityInvitationSendPort &&
                  (model.port as CommunityInvitationSendPort)
                      .invitationSendingAvailable)
                OutlinedButton.icon(
                  onPressed: _openInvitationOutbox,
                  icon: const StandardIcon(StandardIconSemantic.outbox),
                  label: Text(invitationSendText(context, 'records')),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wideFilters =
                    model.view == 'discover' &&
                    model.selected == null &&
                    constraints.maxWidth >= 1050;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wideFilters) ...[
                      SizedBox(
                        width: 290,
                        child: CommunityFilterPanel(
                          key: ValueKey(
                            'filters-${model.accountRevision}-${model.filters}',
                          ),
                          value: model.filters,
                          invalidations: model.port.invalidations,
                          onApply: (value) => model.refresh(newFilters: value),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(child: _content(showFilterButton: !wideFilters)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFilters() async {
    final revision = model.accountRevision;
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 400,
          height: 620,
          child: CommunityFilterPanel(
            value: model.filters,
            invalidations: model.port.invalidations,
            onApply: (value) => Navigator.pop(context, value),
          ),
        ),
      ),
    );
    _filterDialog = route;
    final value = await Navigator.of(context, rootNavigator: true).push(route);
    _filterDialog = null;
    if (mounted && revision == model.accountRevision && value != null) {
      await model.refresh(newFilters: value);
    }
  }

  Widget _content({bool showFilterButton = true}) {
    final selected = model.selected;
    return Card(
      color: context.tokens.surfaces.panel.fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: context.tokens.surfaces.panel.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selected != null) ...[
              if (!const {'owner', 'member'}.contains(selected.relationship))
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => model.open(null),
                    child: Text(t('back')),
                  ),
                ),
              Expanded(
                child:
                    model.port is CommunityWorkspacePort &&
                        const {
                          'owner',
                          'member',
                        }.contains(selected.relationship)
                    ? CommunityWorkspaceView(
                        key: _workspaceKey,
                        port: model.port as CommunityWorkspacePort,
                        targetRef: selected.targetRef,
                        organizationKey: selected.key,
                        session: model.workspaceSession,
                        onFocused: model.onWorkspaceFocused,
                        onGovernanceChanged: model.refreshCurrentMembership,
                        onNameConfirmed: (code, name) => model
                            .applyOrganizationName(selected.key, code, name),
                        actions: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final action in selected.actions)
                              OutlinedButton(
                                onPressed: !model.canExecute(selected)
                                    ? null
                                    : () => act(selected, action),
                                style: action == 'leave'
                                    ? OutlinedButton.styleFrom(
                                        foregroundColor:
                                            context.tokens.colors.warning,
                                      )
                                    : null,
                                child: Text(t('action.$action')),
                              ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        child: _card(selected, detail: true),
                      ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: search,
                      maxLength: 128,
                      decoration: InputDecoration(
                        labelText: t('search'),
                        counterText: '',
                      ),
                      enabled: !model.writing,
                      onSubmitted: (_) => model.refresh(newQuery: search.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: model.writing
                        ? null
                        : () => model.refresh(newQuery: search.text),
                    child: Text(t('searchButton')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (model.view == 'discover') ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showFilterButton)
                      OutlinedButton(
                        onPressed: model.writing ? null : _showFilters,
                        child: Text(t('filters')),
                      ),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: model.filters == null
                            ? 'recommended'
                            : (jsonDecode(model.filters!) as Map)['sort']
                                      as String? ??
                                  'recommended',
                        key: ValueKey('sort-${model.filters}'),
                        decoration: InputDecoration(labelText: t('sort')),
                        items: [
                          for (final sort in [
                            'recommended',
                            'recent',
                            'members',
                            'name',
                          ])
                            DropdownMenuItem(
                              value: sort,
                              child: Text(t('sort.$sort')),
                            ),
                        ],
                        onChanged: model.writing
                            ? null
                            : (sort) {
                                final filters = model.filters == null
                                    ? <String, dynamic>{}
                                    : Map<String, dynamic>.from(
                                        jsonDecode(model.filters!),
                                      );
                                filters['sort'] = sort;
                                unawaited(
                                  model.refresh(
                                    newFilters: jsonEncode(filters),
                                  ),
                                );
                              },
                      ),
                    ),
                    if (model.directory?.totalCount != null)
                      Text(
                        '${model.directory!.totalCount} ${t('resultCount')}',
                      ),
                    if (model.filters != null && model.filters != '{}')
                      TextButton(
                        onPressed: model.writing
                            ? null
                            : () => model.refresh(newFilters: '{}'),
                        child: Text(t('reset')),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (model.message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    t(model.message!),
                    style: TextStyle(
                      color: model.message!.startsWith('done.')
                          ? context.tokens.colors.success
                          : context.tokens.colors.warning,
                    ),
                  ),
                ),
              Expanded(
                child: model.busy && model.directory == null
                    ? Center(
                        child: Semantics(
                          label: t('loading'),
                          child: const CircularProgressIndicator(),
                        ),
                      )
                    : model.error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t(model.error!), textAlign: TextAlign.center),
                            TextButton(
                              onPressed: () => model.refresh(),
                              child: Text(t('retry')),
                            ),
                          ],
                        ),
                      )
                    : model.directory?.items.isEmpty != false
                    ? Center(
                        child: Text(
                          t(
                            model.query.isNotEmpty
                                ? 'emptySearch'
                                : 'empty.${model.view}',
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final textScale =
                              (MediaQuery.textScalerOf(context).scale(14) / 14)
                                  .clamp(1.0, 3.0);
                          final horizontal =
                              constraints.maxHeight < 464 * textScale &&
                              constraints.maxWidth >= 720 * textScale;
                          final columns =
                              ((constraints.maxWidth + 12) /
                                      (horizontal ? 1000 * textScale : 532))
                                  .floor()
                                  .clamp(1, 4);
                          final rows = model.directory!.items;
                          return ListView.separated(
                            key: PageStorageKey(
                              'community-directory-${model.view}-${model.query}-${model.filters}',
                            ),
                            itemCount: (rows.length / columns).ceil(),
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, rowIndex) => Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (
                                  var column = 0;
                                  column < columns;
                                  column++
                                ) ...[
                                  if (column > 0) const SizedBox(width: 12),
                                  Expanded(
                                    child:
                                        rowIndex * columns + column >=
                                            rows.length
                                        ? const SizedBox.shrink()
                                        : _card(
                                            rows[rowIndex * columns + column],
                                            horizontal: horizontal,
                                          ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (model.canPrevious || model.directory?.next != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: model.busy || !model.canPrevious
                          ? null
                          : model.previous,
                      child: Text(t('previous')),
                    ),
                    TextButton(
                      onPressed: model.busy || model.directory?.next == null
                          ? null
                          : model.next,
                      child: Text(t('next')),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(
    CommunityCard row, {
    bool detail = false,
    bool horizontal = false,
  }) => CommunityDirectoryPresentation(
    context: context,
    model: model,
    t: t,
    onDetails: _showDirectoryDetails,
    onAction: act,
  ).build(row, detail: detail, horizontal: horizontal);
}
