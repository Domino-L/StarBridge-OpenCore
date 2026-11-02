import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'community_announcement_details.dart';
import 'community_announcement_card.dart';

import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../direct_messages/communication_time_formatter.dart';
import 'community_announcements_controller.dart';
import 'community_announcements_copy.dart';
import 'community_announcements_port.dart';
import 'community_announcements_refresh.dart';
import 'community_editor_surface.dart';
import 'community_announcements_form.dart';
import '../common/organization_announcement_outcomes_dialog.dart';

class CommunityAnnouncementEntry extends StatefulWidget {
  const CommunityAnnouncementEntry({
    required this.port,
    required this.targetRef,
    this.onChanged,
    this.expanded = false,
    this.embedded = false,
    this.controller,
    super.key,
  });
  final CommunityAnnouncementsPort port;
  final String targetRef;
  final Future<void> Function()? onChanged;
  final bool expanded;
  final bool embedded;
  final CommunityAnnouncementsController? controller;
  @override
  State<CommunityAnnouncementEntry> createState() =>
      CommunityAnnouncementEntryState();
}

class CommunityAnnouncementEntryState extends State<CommunityAnnouncementEntry>
    with CommunityAnnouncementsRefresh<CommunityAnnouncementEntry> {
  late CommunityAnnouncementsController model;
  StarBridgeDialogRoute<void>? _route;
  void _retireInactiveRoute() {
    if (!model.active) retireStarBridgeDialog(_route);
  }

  final _editorKey = GlobalKey<CommunityAnnouncementsDialogState>();
  Future<bool> confirmLeave() async =>
      await _editorKey.currentState?.confirmLeave() ?? true;
  @override
  CommunityAnnouncementsController get announcementModel => model;
  @override
  void initState() {
    super.initState();
    _start();
  }

  Timer? _deferredEnter;

  void _start() {
    model =
        widget.controller ??
        CommunityAnnouncementsController(widget.port, widget.targetRef);
    model.addListener(_retireInactiveRoute);
    _deferredEnter?.cancel();
    _deferredEnter = null;
    // A shared controller that already shows a page is re-entered after the
    // screen switch has played, so the switch never rebuilds the workspace
    // mid-animation (loading line 2026-10-29: 切到上屏卡顿).
    if (widget.controller != null && model.page != null) {
      _deferredEnter = Timer(enterDelay, () {
        _deferredEnter = null;
        if (mounted && identical(model, widget.controller)) {
          unawaited(model.enter());
        }
      });
    } else {
      unawaited(model.enter());
    }
  }

  /// Longer than the screen switch (520 ms).
  static const enterDelay = Duration(milliseconds: 700);

  @override
  void didUpdateWidget(covariant CommunityAnnouncementEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.targetRef != widget.targetRef ||
        oldWidget.controller != widget.controller) {
      final previous = model;
      previous.removeListener(_retireInactiveRoute);
      retireStarBridgeDialog(_route);
      if (oldWidget.controller == null) scheduleMicrotask(previous.dispose);
      _start();
    }
  }

  @override
  void dispose() {
    _deferredEnter?.cancel();
    final previous = model;
    previous.removeListener(_retireInactiveRoute);
    retireStarBridgeDialog(_route);
    if (widget.controller == null) scheduleMicrotask(previous.dispose);
    super.dispose();
  }

  Future<void> _open({bool create = false}) async {
    final current = model;
    if (_route != null || !current.active) return;
    StarBridgeDialogRoute<void>? opened;
    await showStarBridgeDialog<void>(
      context,
      barrierDismissible: false,
      builder: (_) =>
          CommunityAnnouncementsDialog(model: current, startCreating: create),
      onRouteCreated: (route) => _route = opened = route,
    );
    if (identical(_route, opened)) _route = null;
    if (mounted &&
        current == model &&
        current.active &&
        current.success != null) {
      await widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      if (widget.embedded) {
        return CommunityAnnouncementsDialog(
          key: _editorKey,
          model: model,
          embedded: true,
        );
      }
      if (widget.expanded) {
        String t(String key) => communityAnnouncementText(context, key);
        final current = model.page?.current;
        return Column(
          key: const ValueKey('community-announcement-expanded'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('current'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (model.showManagementActions) ...[
                  StarBridgeActionButton(
                    controlKey: const ValueKey(
                      'community-announcement-create-entry',
                    ),
                    kind: StarBridgeActionKind.primary,
                    onActivate: model.active
                        ? (_) => _open(create: true)
                        : null,
                    child: Text(t('create')),
                  ),
                  const SizedBox(width: 8),
                ],
                StarBridgeActionButton(
                  controlKey: const ValueKey(
                    'community-announcement-history-entry',
                  ),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: model.active ? (_) => _open() : null,
                  child: Text(t('history')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (model.error != null) ...[
              Text(
                t(model.error!),
                style: TextStyle(color: context.tokens.colors.warning),
              ),
              if (model.active)
                Align(
                  alignment: Alignment.centerLeft,
                  child: StarBridgeActionButton(
                    controlKey: const Key('announcement-entry-refresh'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate: model.loading ? null : (_) => model.refresh(),
                    child: Text(t('refresh')),
                  ),
                ),
            ],
            if (current != null)
              CommunityAnnouncementDetails(
                key: ValueKey('inline-announcement:${current.announcementRef}'),
                model: model,
                entry: current,
              )
            else if (model.error == null)
              Text(t(model.loading ? 'loading' : 'empty')),
          ],
        );
      }
      final title =
          model.page?.current?.title ??
          communityAnnouncementText(
            context,
            model.loading ? 'loading' : model.error ?? 'empty',
          );
      return StarBridgeActionButton(
        controlKey: const ValueKey('community-announcement-entry'),
        onActivate: model.active ? (_) => _open() : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StandardIcon(StandardIconSemantic.campaign),
            const SizedBox(width: 8),
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${communityAnnouncementText(context, 'current')} · $title',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class CommunityAnnouncementsDialog extends StatefulWidget {
  const CommunityAnnouncementsDialog({
    required this.model,
    this.embedded = false,
    this.startCreating = false,
    super.key,
  });
  final CommunityAnnouncementsController model;
  final bool startCreating; // Open straight into a new announcement.
  final bool embedded;
  @override
  State<CommunityAnnouncementsDialog> createState() =>
      CommunityAnnouncementsDialogState();
}

class CommunityAnnouncementsDialogState
    extends State<CommunityAnnouncementsDialog>
    with CommunityAnnouncementsRefresh<CommunityAnnouncementsDialog> {
  CommunityAnnouncementsController get model => widget.model;
  @override
  CommunityAnnouncementsController get announcementModel => model;
  final title = TextEditingController(), content = TextEditingController();
  final dialogs = <StarBridgeDialogRoute<bool>>[];
  CommunityAnnouncement? selected;
  bool confirming = false;
  String t(String key) => communityAnnouncementText(context, key);
  @override
  void initState() {
    super.initState();
    title.text = model.title;
    content.text = model.content;
    model.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && model.active) {
        unawaited(() async {
          await model.refresh();
          if (mounted && model.active) await model.prepareManagement();
          if (mounted &&
              model.active &&
              widget.startCreating &&
              model.showManagementActions &&
              model.writable) {
            await _edit(true);
          }
        }());
      }
    });
  }

  void _changed() {
    if (!mounted) return;
    if (model.page == null &&
        const {
          'notAllowed',
          'notFound',
          'refreshRequired',
        }.contains(model.error)) {
      for (final route in dialogs.toList()) {
        retireStarBridgeDialog(route);
      }
    }
    if (model.invalidated) {
      title.clear();
      content.clear();
      selected = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final route in dialogs.toList().reversed) {
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
      });
      WidgetsBinding.instance.ensureVisualUpdate();
      return;
    }
    if (selected != null) {
      selected =
          [
                if (model.page?.current != null) model.page!.current!,
                ...model.history,
              ]
              .where((v) => v.announcementRef == selected!.announcementRef)
              .firstOrNull;
    }
    if (!model.editing) {
      title.clear();
      content.clear();
    }
    setState(() {});
  }

  @override
  void dispose() {
    for (final route in dialogs.toList()) {
      retireStarBridgeDialog(route);
    }
    model.removeListener(_changed);
    title.dispose();
    content.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CommunityAnnouncementsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      oldWidget.model.removeListener(_changed);
      for (final route in dialogs.toList()) {
        retireStarBridgeDialog(route);
      }
      title.text = model.title;
      content.text = model.content;
      selected = null;
      model.addListener(_changed);
    }
  }

  Future<void> _refresh() async {
    await model.refresh();
    if (mounted && model.active) await model.prepareManagement();
  }

  Future<bool> _confirm(
    String heading,
    String body,
    String action, {
    bool danger = false,
  }) async {
    if (confirming || model.saving || !model.active) return false;
    setState(() => confirming = true);
    StarBridgeDialogRoute<bool>? route;
    try {
      return await showStarBridgeDialog<bool>(
                context,
                useRootNavigator: false,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  title: Text(heading),
                  content: Text(body),
                  actions: [
                    StarBridgeActionButton(
                      controlKey: const Key('announcement-confirm-cancel'),
                      kind: StarBridgeActionKind.quiet,
                      onActivate: (source) => dismissStarBridgeDialog(
                        context,
                        source: source,
                        result: false,
                      ),
                      child: Text(communityAnnouncementText(context, 'cancel')),
                    ),
                    StarBridgeActionButton(
                      controlKey: const Key('announcement-confirm-accept'),
                      kind: StarBridgeActionKind.quiet,
                      tone: danger ? ActionTone.danger : null,
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
                  dialogs.add(opened);
                },
              ) ==
              true &&
          mounted &&
          model.active;
    } finally {
      dialogs.remove(route);
      if (mounted) setState(() => confirming = false);
    }
  }

  Future<bool> _discard() async {
    if (model.saving || confirming) return false;
    if (model.dirty &&
        !await _confirm(
          t('leaveTitle'),
          t('leaveBody'),
          t('discard'),
          danger: true,
        )) {
      return false;
    }
    if (!mounted || !model.active) return false;
    model.discardDraft();
    return true;
  }

  Future<void> _close() async {
    if (await confirmLeave() && mounted && !widget.embedded) {
      dismissStarBridgeDialog(
        context,
        source: currentStarBridgeActivationSource,
      );
    }
  }

  Future<bool> confirmLeave() async => !model.active ? true : _discard();

  Future<void> _edit(bool create) async {
    if (await model.prepareEditing(create: create) && mounted) {
      title.text = model.title;
      content.text = model.content;
      setState(() => selected = null);
    }
  }

  Future<void> _withdraw(CommunityAnnouncement current) async {
    if (await _confirm(
      t('withdraw'),
      '${current.title}\n\n${t('withdrawBody')}',
      t('withdraw'),
      danger: true,
    )) {
      await model.withdraw(current);
    }
  }

  Widget _status(String key, {bool success = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      t(key),
      style: TextStyle(
        color: success
            ? context.tokens.colors.success
            : context.tokens.colors.warning,
      ),
    ),
  );
  Widget _state(CommunityAnnouncement item) {
    final colors = context.tokens.colors;
    final color = item.state == 'published'
        ? colors.success
        : item.state == 'withdrawn'
        ? colors.warning
        : colors.textSecondary;
    return Text(
      t(item.state),
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }

  Widget _summary(CommunityAnnouncement item, {bool current = false}) =>
      CommunityAnnouncementCard(
        title: item.title,
        content: item.content.isEmpty ? t('emptyBody') : item.content,
        maxLines: current ? 4 : 2,
        metadata: Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _state(item),
            Text(
              communicationTime(
                current ? item.publishedAt : item.updatedAt,
                AppStrings.of(context).locale,
              ),
              style: TextStyle(color: context.tokens.colors.textSecondary),
            ),
          ],
        ),
        actions: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StarBridgeActionButton(
              controlKey: ValueKey(
                'announcement-details-${item.announcementRef}',
              ),
              onActivate: (_) => setState(() => selected = item),
              child: Text(t('details')),
            ),
            if (current && model.showManagementActions && !model.editing) ...[
              StarBridgeActionButton(
                controlKey: const Key('announcement-edit'),
                onActivate: model.writable && !confirming
                    ? (_) => _edit(false)
                    : null,
                child: Text(t('edit')),
              ),
              StarBridgeActionButton(
                controlKey: const Key('announcement-withdraw'),
                tone: ActionTone.danger,
                onActivate: model.writable && !confirming
                    ? (_) => _withdraw(item)
                    : null,
                child: Text(t('withdraw')),
              ),
            ],
          ],
        ),
      );
  Widget _editor() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CommunityAnnouncementsForm(
        title: title,
        content: content,
        creating: model.editBaseline == null,
        saving: model.saving,
        confirming: confirming,
        stale: model.staleDraft,
        canSave: model.writable,
        onChanged: () => model.updateDraft(title.text, content.text),
        onSave: model.save,
        onDiscard: _discard,
      ),
      if (model.uncertain && model.page != null) ...[
        const Divider(height: 28),
        Text(t('current'), style: Theme.of(context).textTheme.titleMedium),
        if (model.page!.current != null)
          _summary(model.page!.current!, current: true)
        else
          Text(t('empty')),
        for (final item in model.history) _summary(item),
        if (model.page!.next != null)
          StarBridgeActionButton(
            controlKey: const Key('announcement-more'),
            kind: StarBridgeActionKind.quiet,
            onActivate: model.loading ? null : (_) => model.loadMore(),
            child: Text(t('more')),
          ),
      ],
    ],
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: widget.embedded,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        unawaited(
          runStarBridgeActivation<void>(InteractionSource.keyboard, _close),
        );
      }
    },
    child: CommunityEditorSurface(
      embedded: widget.embedded,
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: widget.embedded ? null : 980,
        height: widget.embedded
            ? null
            : max(200, min(760, MediaQuery.sizeOf(context).height - 80)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    t('center'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  StarBridgeActionButton(
                    controlKey: const Key('announcement-refresh'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate: model.loading || model.saving || confirming
                        ? null
                        : (_) => _refresh(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const StandardIcon(
                          StandardIconSemantic.refresh,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(t('refresh')),
                      ],
                    ),
                  ),
                  if (model.management?.port.outcomesAvailable == true)
                    StarBridgeActionButton(
                      controlKey: const Key('announcement-own-outcomes'),
                      kind: StarBridgeActionKind.quiet,
                      onActivate: (_) => showOrganizationAnnouncementOutcomes(
                        context,
                        model.management!.outcomes,
                      ),
                      child: Text(t('ownOutcomes')),
                    ),
                  if (model.showManagementActions && !model.editing)
                    StarBridgeActionButton(
                      controlKey: const Key('announcement-create'),
                      kind: StarBridgeActionKind.primary,
                      onActivate: model.writable && !confirming
                          ? (_) => _edit(true)
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const StandardIcon(
                            StandardIconSemantic.add,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(t('create')),
                        ],
                      ),
                    ),
                ],
              ),
              if (model.showProgress) const LinearProgressIndicator(),
              if (model.error != null) _status(model.error!),
              if (model.writeError != null)
                _status(
                  model.writeError == 'outcomeUnknown' &&
                          model.management != null
                      ? 'officialOutcomeUnknown'
                      : model.writeError!,
                ),
              if (model.success != null) _status(model.success!, success: true),
              if (model.uncertain && model.management != null)
                StarBridgeActionButton(
                  controlKey: const Key('announcement-query-original'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: !model.saving && !confirming
                      ? (_) => model.management!.originalIntent == null
                            ? showOrganizationAnnouncementOutcomes(
                                context,
                                model.management!.outcomes,
                              )
                            : model.queryOriginalOutcome()
                      : null,
                  child: Text(t('queryOriginal')),
                ),
              if (model.uncertain && model.management == null)
                StarBridgeActionButton(
                  controlKey: const Key('announcement-review-unknown'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: model.canReviewUnknown && !confirming
                      ? (_) async {
                          if (await _confirm(
                            t('reviewed'),
                            t('reviewBody'),
                            t('reviewed'),
                          )) {
                            model.reviewedUnknown();
                          }
                        }
                      : null,
                  child: Text(t('reviewed')),
                ),
              const Divider(height: 20),
              Expanded(
                child: ListView(
                  children: [
                    if (selected != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StarBridgeActionButton(
                          controlKey: const Key('announcement-back'),
                          kind: StarBridgeActionKind.quiet,
                          onActivate: (_) => setState(() => selected = null),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const StandardIcon(
                                StandardIconSemantic.arrowBack,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(t('back')),
                            ],
                          ),
                        ),
                      ),
                      CommunityAnnouncementDetails(
                        key: ValueKey(selected!.announcementRef),
                        model: model,
                        entry: selected!,
                      ),
                    ] else if (model.editing)
                      _editor()
                    else ...[
                      Text(
                        t('current'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      if (model.page?.current != null)
                        _summary(model.page!.current!, current: true)
                      else if (model.page != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(t('empty')),
                        ),
                      const Divider(height: 28),
                      Text(
                        '${t('history')} · ${model.page?.totalHistoryCount ?? '—'}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      for (final item in model.history) _summary(item),
                      if (model.page != null && model.history.isEmpty)
                        Text(t('emptyHistory')),
                      if (model.page?.next != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: StarBridgeActionButton(
                            controlKey: const Key('announcement-more'),
                            onActivate: model.loading
                                ? null
                                : (_) => model.loadMore(),
                            child: Text(t('more')),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (!widget.embedded) const Divider(height: 20),
              if (!widget.embedded)
                Align(
                  alignment: Alignment.centerRight,
                  child: StarBridgeActionButton(
                    controlKey: const Key('announcement-close'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate: model.saving || confirming
                        ? null
                        : (_) => _close(),
                    child: Text(t('close')),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
