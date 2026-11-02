import 'package:flutter/material.dart' hide LocalHistoryEntry;
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'bridge_local_event_history.dart';
import 'local_event_history.dart';
import 'local_event_history_copy.dart';
import 'local_event_export.dart';
import 'local_event_export_action.dart';
import 'local_event_clear.dart';
import 'local_event_clear_action.dart';

Future<void> showLocalEventHistory(
  BuildContext context, {
  BridgeClientSession? session,
  bool available = false,
  bool exportAvailable = false,
  bool clearAvailable = false,
}) async {
  final controller = LocalHistoryController(
    session == null || !available
        ? const LocalHistoryUnavailable()
        : BridgeLocalEventHistory(session),
  );
  final export = session != null && available && exportAvailable
      ? BridgeLocalEventExport(session)
      : null;
  final clear = session != null && available && clearAvailable
      ? BridgeLocalEventClear(session)
      : null;
  try {
    await showStarBridgeDialog<void>(
      context,
      builder: (_) => LocalEventHistoryDialog(
        controller: controller,
        exportPort: export,
        clearPort: clear,
      ),
    );
  } finally {
    controller.dispose();
    export?.cancel();
    clear?.cancel();
  }
}

class LocalEventHistoryDialog extends StatefulWidget {
  const LocalEventHistoryDialog({
    required this.controller,
    this.exportPort,
    this.clearPort,
    this.embedded = false,
    super.key,
  });
  final LocalHistoryController controller;
  final LocalEventExportPort? exportPort;
  final LocalEventClearPort? clearPort;
  final bool embedded;
  @override
  State<LocalEventHistoryDialog> createState() =>
      _LocalEventHistoryDialogState();
}

class _LocalEventHistoryDialogState extends State<LocalEventHistoryDialog> {
  int _lease = 0, _completed = 0;
  bool _reading = false;
  InteractionSource _source = InteractionSource.programmatic;

  void _attach() {
    _reading = widget.controller.value.busy;
    widget.controller.addListener(_changed);
    widget.controller.refresh();
    if (widget.embedded) widget.controller.startWatching();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      final busy = widget.controller.value.busy;
      if (_reading && !busy) _completed++;
      _reading = busy;
    });
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(LocalEventHistoryDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      _lease++;
      _completed = 0;
      _source = InteractionSource.programmatic;
      _attach();
    } else if (!oldWidget.embedded && widget.embedded) {
      widget.controller.startWatching();
    }
  }

  @override
  void dispose() {
    _lease++;
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Future<void> _operate(
    InteractionSource source,
    LocalHistoryController owner,
    int lease,
    Future<void> Function() command,
  ) async {
    if (!mounted ||
        lease != _lease ||
        !identical(owner, widget.controller) ||
        owner.value.busy) {
      return;
    }
    setState(() => _source = source);
    await runStarBridgeActivation(source, command);
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) => ValueListenableBuilder<LocalHistoryView>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          String t(String key) => localHistoryText(context, key);
          final tokens = context.tokens, page = value.page;
          final c = widget.controller, lease = _lease;
          final data = InteractionScope.of(context);
          final effective = data.copyWith(
            reduceMotion:
                data.reduceMotion ||
                resolveStarBridgeInitialReadSource(context, _source) ==
                    InteractionSource.keyboard,
          );
          final rows = page?.entries ?? const <LocalHistoryEntry>[];
          final content = StarBridgeSurface(
            role: widget.embedded ? SurfaceRole.panel : SurfaceRole.floating,
            child: SizedBox(
              width: 920,
              height: 690,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t('title'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        t('scope'),
                        style: TextStyle(color: tokens.colors.textSecondary),
                      ),
                      SizedBox(height: tokens.space.md),
                      Wrap(
                        spacing: tokens.space.sm,
                        runSpacing: tokens.space.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 180,
                            child: StarBridgeSelectFormField<String>(
                              identity: ('history-category', c, lease),
                              controlKey: const Key('history-category-control'),
                              key: const Key('history-category'),
                              initialValue: value.category,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: t('category'),
                              ),
                              items: [
                                for (final category in localEventCategories)
                                  DropdownMenuItem(
                                    value: category,
                                    child: Text(t(category)),
                                  ),
                              ],
                              onChanged: value.busy
                                  ? null
                                  : (category) {
                                      if (category != null &&
                                          category != c.value.category) {
                                        _operate(
                                          StarBridgeActivationOrigin.sourceOf(
                                            context,
                                          ),
                                          c,
                                          lease,
                                          () => c.select(category),
                                        );
                                      }
                                    },
                            ),
                          ),
                          StarBridgeActionButton(
                            controlKey: const Key('history-refresh'),
                            onActivate: value.busy
                                ? null
                                : (source) =>
                                      _operate(source, c, lease, c.refresh),
                            child: Text(t('refresh')),
                          ),
                          if (widget.exportPort case final port?)
                            LocalEventExportAction(
                              port: port,
                              enabled:
                                  !value.busy &&
                                  value.failure == null &&
                                  page != null &&
                                  page.state != 'unavailable' &&
                                  page.totalCount > 0,
                            )
                          else
                            StarBridgeTooltip(
                              message: t('notAvailable'),
                              consumeEscape: false,
                              child: StarBridgeActionButton(
                                controlKey: const Key('history-export'),
                                onActivate: null,
                                child: Text(t('export')),
                              ),
                            ),
                          if (widget.clearPort case final port?)
                            LocalEventClearAction(
                              port: port,
                              refresh: c.refresh,
                              enabled:
                                  !value.busy &&
                                  page != null &&
                                  page.state != 'unavailable' &&
                                  page.totalCount > 0,
                            )
                          else
                            StarBridgeTooltip(
                              message: t('notAvailable'),
                              consumeEscape: false,
                              child: StarBridgeActionButton(
                                controlKey: const Key('history-clear'),
                                kind: StarBridgeActionKind.quiet,
                                onActivate: null,
                                child: Text(t('clear')),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: tokens.space.sm),
                      if (page?.state == 'recovered')
                        Text(
                          t('recovered'),
                          key: const Key('history-backup'),
                          style: TextStyle(color: tokens.colors.warning),
                        ),
                      if (value.changed)
                        Text(t('changed'), key: const Key('history-changed')),
                      if (value.hasUpdates)
                        StarBridgeActionButton(
                          controlKey: const Key('history-new-events'),
                          kind: StarBridgeActionKind.quiet,
                          onActivate: value.busy
                              ? null
                              : (source) =>
                                    _operate(source, c, lease, c.refresh),
                          child: Text(t('newEvents')),
                        ),
                      if (page != null && value.busy)
                        InteractionScope(
                          data: effective,
                          child: SuiteBusyLabel(t('loading')),
                        ),
                      if (page != null && value.failure != null)
                        Text(
                          t('stale'),
                          style: TextStyle(color: tokens.colors.warning),
                        ),
                      Expanded(
                        child: value.busy && page == null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InteractionScope(
                                      data: effective,
                                      child: SuiteBusyLabel(t('loading')),
                                    ),
                                  ],
                                ),
                              )
                            : (value.failure != null && page == null) ||
                                  page?.state == 'unavailable'
                            ? Center(
                                child: Text(
                                  t(
                                    page?.state == 'unavailable'
                                        ? 'unavailable'
                                        : 'readFailed',
                                  ),
                                  key: const Key('history-failure'),
                                ),
                              )
                            : rows.isEmpty
                            ? Center(
                                child: Text(
                                  t(
                                    page?.totalCount == 0
                                        ? 'empty'
                                        : 'filteredEmpty',
                                  ),
                                  key: const Key('history-empty'),
                                ),
                              )
                            : ListView.separated(
                                key: ValueKey(
                                  'history-list-${value.category}-${page?.offset}',
                                ),
                                itemCount: rows.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) =>
                                    _HistoryRow(entry: rows[index]),
                              ),
                      ),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: tokens.space.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (page != null &&
                              page.state != 'unavailable' &&
                              page.filteredCount > 0)
                            Text(
                              '${page.offset + 1}–${page.offset + rows.length} / ${page.filteredCount}',
                              key: const Key('history-range'),
                            ),
                          StarBridgeActionButton(
                            controlKey: const Key('history-previous'),
                            kind: StarBridgeActionKind.quiet,
                            onActivate:
                                value.busy || page == null || page.offset == 0
                                ? null
                                : (source) =>
                                      _operate(source, c, lease, c.previous),
                            child: Text(t('previous')),
                          ),
                          StarBridgeActionButton(
                            controlKey: const Key('history-next'),
                            kind: StarBridgeActionKind.quiet,
                            onActivate:
                                value.busy || page == null || !page.hasMore
                                ? null
                                : (source) =>
                                      _operate(source, c, lease, c.next),
                            child: Text(t('next')),
                          ),
                          if (!widget.embedded)
                            StarBridgeActionButton(
                              controlKey: const Key('history-close'),
                              kind: StarBridgeActionKind.quiet,
                              onActivate: (source) {
                                if (!mounted ||
                                    lease != _lease ||
                                    !identical(c, widget.controller) ||
                                    ModalRoute.of(context)?.isCurrent != true) {
                                  return;
                                }
                                dismissStarBridgeDialog(
                                  context,
                                  source: source,
                                );
                              },
                              child: Text(t('close')),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: InteractionScope(
                          data: effective,
                          child: SuiteBusyFrame(
                            key: ValueKey(lease),
                            busy: value.busy,
                            doneToken: _completed,
                            doneOutcome:
                                value.failure != null ||
                                    page?.state == 'unavailable'
                                ? TaskOutcome.failure
                                : TaskOutcome.success,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          return widget.embedded
              ? content
              : Dialog(
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: content,
                );
        },
      ),
    ),
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});
  final LocalHistoryEntry entry;
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = switch (entry.category) {
      'session' => tokens.colors.success,
      'identity' || 'server' => tokens.colors.info,
      'ship' => tokens.domainColors.ship.foreground,
      'location' => tokens.colors.warning,
      'life' => tokens.colors.danger,
      _ => tokens.colors.textSecondary,
    };
    final at = entry.at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final time =
        '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
    return Container(
      key: ValueKey('history-entry-${entry.id}'),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
        color: color.withValues(alpha: .035),
      ),
      padding: EdgeInsets.all(tokens.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: tokens.space.md,
            children: [
              Text(time, style: TextStyle(color: tokens.colors.textSecondary)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: tokens.space.sm,
                  vertical: tokens.space.xxs,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: tokens.shape.small,
                ),
                child: Text(
                  localHistoryText(context, entry.category),
                  style: TextStyle(color: color),
                ),
              ),
            ],
          ),
          SelectableText(
            entry.title,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          if (entry.detail.isNotEmpty)
            SelectableText(
              entry.detail,
              style: TextStyle(color: tokens.colors.textSecondary),
            ),
        ],
      ),
    );
  }
}
