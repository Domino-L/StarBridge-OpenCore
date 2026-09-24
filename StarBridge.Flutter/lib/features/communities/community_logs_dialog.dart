import '../../design_system/icons/standard_icon.dart';
import 'dart:async';
import 'community_visible_refresh.dart';

import 'package:flutter/material.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../party_rooms/room_display.dart' show roomDate;
import 'community_logs_controller.dart';
import 'community_logs_copy.dart';
import 'community_logs_port.dart';
import 'community_editor_surface.dart';

class CommunityLogsDialog extends StatefulWidget {
  const CommunityLogsDialog({
    super.key,
    required this.port,
    required this.targetRef,
    this.contextInvalidations,
    this.embedded = false,
  });
  final CommunityLogsPort port;
  final String targetRef;
  final Stream<void>? contextInvalidations;
  final bool embedded;
  @override
  State<CommunityLogsDialog> createState() => CommunityLogsDialogState();
}

class CommunityLogsDialogState extends State<CommunityLogsDialog> with CommunityVisibleRefresh<CommunityLogsDialog> {
  @override
  Future<void> refreshVisibleCommunity() => model.snapshot == null ? Future<void>.value() : model.load(offset: model.snapshot!.offset, quiet: true);
  Future<bool> confirmLeave() async => !model.submitting;
  late final model = CommunityLogsController(widget.port, widget.targetRef);
  final search = TextEditingController();
  StreamSubscription<void>? _contextSubscription;
  String t(String key) => communityLogsText(context, key);
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
    if (model.invalidated) search.clear();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_contextSubscription?.cancel());
    model.removeListener(_changed);
    model.dispose();
    search.dispose();
    super.dispose();
  }

  String _time(CommunityLogEntry row) {
    final start = row.timestamp, end = row.endTimestamp;
    if (start == null && end == null) return t('unknownTime');
    if (start == null) {
      return '${t('unknownTime')} – ${roomDate(context, end!)}';
    }
    if (end == null || start.isAtSameMomentAs(end)) {
      return roomDate(context, start);
    }
    return '${roomDate(context, start)} – ${roomDate(context, end)}';
  }

  Widget _entry(CommunityLogEntry row, {bool confirmation = false}) =>
      Container(
        key: ValueKey('log-${row.logRef}'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.tokens.surfaces.raised.fill,
          border: Border.all(
            color: confirmation
                ? context.tokens.colors.danger
                : context.tokens.surfaces.panel.border,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  _time(row),
                  style: TextStyle(color: context.tokens.colors.textSecondary),
                ),
                if (row.occurrenceCount > 1)
                  Text(
                    t('repeated')
                        .replaceAll('{count}', '${row.occurrenceCount}'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(row.title, style: Theme.of(context).textTheme.titleMedium),
            if (row.detail.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(row.detail),
            ],
            if (!confirmation && model.canDelete)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: semanticActionStyle(context, ActionTone.danger),
                  onPressed: () => model.selectForDeletion(row),
                  icon: const StandardIcon(StandardIconSemantic.delete, size: 18),
                  label: Text(t('delete')),
                ),
              ),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) {
    final page = model.snapshot, selected = model.pendingDeletion;
    return PopScope(
      canPop: !model.submitting,
      child: CommunityEditorAlertSurface(
        embedded: widget.embedded,
        title: Text(t(selected == null ? 'title' : 'confirm')),
        content: SizedBox(
          width: widget.embedded ? null : 820,
          height: widget.embedded
              ? null
              : (MediaQuery.sizeOf(context).height * .68).clamp(240, 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((model.loading && model.snapshot == null) || model.submitting)
                const LinearProgressIndicator(),
              if (selected != null) ...[
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _entry(selected, confirmation: true),
                        const SizedBox(height: 16),
                        Text(t('consequence')),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                if (page != null) ...[
                  Text(
                    page.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                if (!model.invalidated) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in communityLogFilters)
                        ChoiceChip(
                          label: Text(t(type)),
                          selected: model.type == type,
                          onSelected: model.loading
                              ? null
                              : (_) => model.load(
                                  filter: type,
                                  search: search.text,
                                ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: search,
                    maxLength: 128,
                    enabled: !model.loading,
                    onSubmitted: (_) => model.load(search: search.text),
                    decoration: InputDecoration(
                      labelText: t('search'),
                      counterText: '',
                      suffixIcon: IconButton(
                        tooltip: t('search'),
                        onPressed: model.loading
                            ? null
                            : () => model.load(search: search.text),
                        icon: const StandardIcon(StandardIconSemantic.search),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (model.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      t(model.error!),
                      style: TextStyle(color: context.tokens.colors.warning),
                    ),
                  ),
                if (model.lastOutcome == 'accepted')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      t('deleted'),
                      style: TextStyle(color: context.tokens.colors.success),
                    ),
                  ),
                Expanded(
                  child: page == null
                      ? const SizedBox.shrink()
                      : page.items.isEmpty
                      ? Center(
                          child: Text(
                            t(page.totalCount == 0 ? 'empty' : 'noMatches'),
                          ),
                        )
                      : ListView.separated(
                          itemCount: page.items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) => _entry(page.items[index]),
                        ),
                ),
                if (page != null && page.matchedCount > 0)
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        t('page')
                            .replaceAll('{start}', '${page.offset + 1}')
                            .replaceAll(
                              '{end}',
                              '${page.offset + page.items.length}',
                            )
                            .replaceAll('{total}', '${page.matchedCount}'),
                      ),
                      TextButton(
                        onPressed: page.offset == 0 || model.loading
                            ? null
                            : () => model.load(
                                offset: (page.offset - 20).clamp(
                                  0,
                                  page.offset,
                                ),
                              ),
                        child: Text(t('previous')),
                      ),
                      TextButton(
                        onPressed: page.next == null || model.loading
                            ? null
                            : () => model.load(offset: page.next!),
                        child: Text(t('next')),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
        actions: [
          if (selected != null) ...[
            TextButton(
              onPressed: model.submitting ? null : model.cancelDeletion,
              child: Text(t('keep')),
            ),
            FilledButton(
              style: semanticActionStyle(
                context,
                ActionTone.danger,
                emphasis: ActionEmphasis.filled,
              ),
              onPressed: model.submitting ? null : model.confirmDeletion,
              child: Text(t('delete')),
            ),
          ] else ...[
            if (!model.invalidated)
              TextButton(
                onPressed: model.loading ? null : () => model.load(),
                child: Text(t('reload')),
              ),
            if (!widget.embedded)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('close')),
              ),
          ],
        ],
      ),
    );
  }
}
