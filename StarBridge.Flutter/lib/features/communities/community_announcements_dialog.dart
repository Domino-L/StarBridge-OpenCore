import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'community_announcement_details.dart';

import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../direct_messages/communication_time_formatter.dart';
import 'community_announcements_controller.dart';
import 'community_announcements_copy.dart';
import 'community_announcements_port.dart';
import 'community_announcements_refresh.dart';
import 'community_editor_surface.dart';

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

  void _start() {
    model =
        widget.controller ??
        CommunityAnnouncementsController(widget.port, widget.targetRef);
    unawaited(model.enter());
  }

  @override
  void didUpdateWidget(covariant CommunityAnnouncementEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.targetRef != widget.targetRef ||
        oldWidget.controller != widget.controller) {
      final previous = model;
      if (oldWidget.controller == null) scheduleMicrotask(previous.dispose);
      _start();
    }
  }

  @override
  void dispose() {
    final previous = model;
    if (widget.controller == null) scheduleMicrotask(previous.dispose);
    super.dispose();
  }

  Future<void> _open() async {
    final current = model;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommunityAnnouncementsDialog(model: current),
    );
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
                TextButton(
                  key: const ValueKey('community-announcement-history-entry'),
                  onPressed: model.active ? _open : null,
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
                  child: TextButton(
                    onPressed: model.loading ? null : () => model.refresh(),
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
      return OutlinedButton.icon(
        key: const ValueKey('community-announcement-entry'),
        onPressed: model.active ? _open : null,
        icon: const StandardIcon(StandardIconSemantic.campaign),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${communityAnnouncementText(context, 'current')} · $title',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    },
  );
}

class CommunityAnnouncementsDialog extends StatefulWidget {
  const CommunityAnnouncementsDialog({
    required this.model,
    this.embedded = false,
    super.key,
  });
  final CommunityAnnouncementsController model;
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
  final dialogs = <Route<dynamic>>[];
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
      if (mounted && model.active) unawaited(model.refresh());
    });
  }

  void _changed() {
    if (!mounted) return;
    if (model.invalidated) {
      title.clear();
      content.clear();
      selected = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final route in dialogs.toList().reversed) {
          if (route.isActive) route.navigator?.removeRoute(route);
        }
        if (!widget.embedded) {
          final route = ModalRoute.of(context);
          if (route?.isActive == true) route!.navigator?.removeRoute(route);
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
    model.removeListener(_changed);
    title.dispose();
    content.dispose();
    super.dispose();
  }

  Future<bool> _confirm(
    String heading,
    String body,
    String action, {
    bool danger = false,
  }) async {
    if (confirming || model.saving || !model.active) return false;
    setState(() => confirming = true);
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(heading),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel')),
          ),
          TextButton(
            style: danger
                ? semanticActionStyle(context, ActionTone.danger)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    dialogs.add(route);
    try {
      return await Navigator.of(context).push(route) == true &&
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
      Navigator.of(context).pop();
    }
  }

  Future<bool> confirmLeave() async => !model.active ? true : _discard();

  void _edit(bool create) {
    if (model.startEditing(create: create)) {
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
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.tokens.surfaces.raised.fill,
          border: Border.all(color: context.tokens.surfaces.panel.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
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
            const SizedBox(height: 8),
            Text(item.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              item.content.isEmpty ? t('emptyBody') : item.content,
              maxLines: current ? 4 : 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => selected = item),
                  child: Text(t('details')),
                ),
                if (current && model.canManage && !model.editing) ...[
                  OutlinedButton(
                    onPressed: model.writable && !confirming
                        ? () => _edit(false)
                        : null,
                    child: Text(t('edit')),
                  ),
                  OutlinedButton(
                    style: semanticActionStyle(
                      context,
                      ActionTone.danger,
                      emphasis: ActionEmphasis.outlined,
                    ),
                    onPressed: model.writable && !confirming
                        ? () => _withdraw(item)
                        : null,
                    child: Text(t('withdraw')),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
  Widget _editor() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        t(model.editBaseline == null ? 'create' : 'edit'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (model.editBaseline == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(t('publishBody')),
        ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('announcement-title'),
        controller: title,
        style: Theme.of(context).textTheme.bodyMedium,
        enabled: !model.saving && !confirming,
        maxLength: 48,
        decoration: InputDecoration(labelText: t('title')),
        onChanged: (_) => model.updateDraft(title.text, content.text),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('announcement-content'),
        controller: content,
        style: Theme.of(context).textTheme.bodyMedium,
        enabled: !model.saving && !confirming,
        minLines: 7,
        maxLines: 14,
        maxLength: 1200,
        decoration: InputDecoration(labelText: t('content')),
        onChanged: (_) => model.updateDraft(title.text, content.text),
      ),
      if (model.staleDraft) _status('announcementsChanged'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: model.writable && !model.staleDraft && !confirming
                ? model.save
                : null,
            child: Text(
              t(
                model.saving
                    ? 'saving'
                    : model.editBaseline == null
                    ? 'publish'
                    : 'save',
              ),
            ),
          ),
          OutlinedButton(
            onPressed: !model.saving && !confirming ? _discard : null,
            child: Text(t('discard')),
          ),
        ],
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
          TextButton(
            onPressed: model.loading ? null : model.loadMore,
            child: Text(t('more')),
          ),
      ],
    ],
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: widget.embedded,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
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
                  TextButton.icon(
                    onPressed: model.loading || model.saving || confirming
                        ? null
                        : model.refresh,
                    icon: const StandardIcon(StandardIconSemantic.refresh, size: 18),
                    label: Text(t('refresh')),
                  ),
                  if (model.canManage && !model.editing)
                    FilledButton.icon(
                      onPressed: model.writable && !confirming
                          ? () => _edit(true)
                          : null,
                      icon: const StandardIcon(StandardIconSemantic.add, size: 18),
                      label: Text(t('create')),
                    ),
                ],
              ),
              if (model.showProgress) const LinearProgressIndicator(),
              if (model.error != null) _status(model.error!),
              if (model.writeError != null) _status(model.writeError!),
              if (model.success != null) _status(model.success!, success: true),
              if (model.uncertain)
                TextButton(
                  onPressed: model.canReviewUnknown && !confirming
                      ? () async {
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
                        child: TextButton.icon(
                          onPressed: () => setState(() => selected = null),
                          icon: const StandardIcon(StandardIconSemantic.arrowBack, size: 18),
                          label: Text(t('back')),
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
                          child: OutlinedButton(
                            onPressed: model.loading ? null : model.loadMore,
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
                  child: TextButton(
                    onPressed: model.saving || confirming ? null : _close,
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
