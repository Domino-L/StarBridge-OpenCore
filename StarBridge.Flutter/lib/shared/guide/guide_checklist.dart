import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'guide_copy.dart';
import 'guide_scope.dart';
import 'guide_state.dart';
import 'guide_windows_notice.dart';

/// (done id, destination route or null). Buttons only navigate.
const _online = [
  ('recognize', null),
  ('hangar', '/hangar'),
  ('fleet', '/fleet'),
  ('overlay', '/overlay'),
  ('market', '/marketplace'),
  ('friend', '/friends'),
  (guideWindowsNoticeId, '/notifications'),
];
const _local = [
  ('recognize', null),
  ('hangar', '/hangar'),
  ('overlay', '/overlay'),
  ('tools', '/tools'),
  ('achievements', '/achievements'),
];

/// Home "Getting started" card, for profiles that finished first-use setup.
/// Shows [fallback] whenever there is no checklist to show.
Widget guideChecklist(BuildContext context, {required Widget fallback}) {
  final hub = GuideScope.maybeOf(context);
  if (hub == null) return fallback;
  return _Checklist(hub: hub, fallback: fallback);
}

class _Checklist extends StatefulWidget {
  const _Checklist({required this.hub, required this.fallback});
  final GuideHub hub;
  final Widget fallback;
  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  /// The celebration shows for this session only; it is recorded at once.
  bool _celebrating = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.hub.controller,
        widget.hub.online,
        ?widget.hub.windowsNotice?.state,
      ]),
      builder: (context, _) {
        final state = widget.hub.controller.value;
        final notice = widget.hub.windowsNotice?.state.value;
        final items = [
          for (final item in widget.hub.online.value ? _online : _local)
            // Only where this device can show Windows notifications.
            if (item.$1 != guideWindowsNoticeId ||
                notice == GuideWindowsNoticeState.off ||
                notice == GuideWindowsNoticeState.on)
              item,
        ];
        // Already on (here or in Settings) counts as handled too.
        bool isDone(String id) =>
            state.done.contains(id) ||
            id == guideWindowsNoticeId && notice == GuideWindowsNoticeState.on;
        final done = items.where((i) => isDone(i.$1)).length;
        if (!state.available || !state.eligible || state.dismissed) {
          return widget.fallback;
        }
        // Finished once is finished: an item added later never reopens it.
        if (state.celebrated && !_celebrating) return widget.fallback;
        if (done == items.length &&
            !_celebrating &&
            notice != GuideWindowsNoticeState.loading) {
          _celebrating = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => widget.hub.controller.setChecklist(celebrated: true),
          );
        }
        return _card(context, state, items, done, isDone);
      },
    );
  }

  Widget _card(
    BuildContext context,
    GuideState state,
    List<(String, String?)> items,
    int done,
    bool Function(String id) isDone,
  ) {
    final t = context.tokens;
    final copy = GuideCopy.of(context);
    final text = Theme.of(context).textTheme;
    final controller = widget.hub.controller;
    final local = !widget.hub.online.value;
    Widget link(String key, String label, VoidCallback onTap) =>
        StarBridgeActionButton(
          controlKey: Key(key),
          kind: StarBridgeActionKind.quiet,
          onActivate: (_) => onTap(),
          child: Text(label),
        );
    final decoration = BoxDecoration(
      color: t.surfaces.panel.fill,
      borderRadius: BorderRadius.circular(t.shape.radiusLarge),
      border: Border.all(
        color: _celebrating ? t.colors.success : t.surfaces.panel.border,
      ),
    );
    if (_celebrating) {
      return DecoratedBox(
        key: const Key('guide-checklist-done'),
        decoration: decoration,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: t.space.lg,
            vertical: t.space.sm,
          ),
          child: Row(
            children: [
              Text(
                '✓ ${copy.text('checklist.doneTitle')}',
                style: text.titleMedium?.copyWith(color: t.colors.success),
              ),
              SizedBox(width: t.space.md),
              Expanded(child: Text(copy.text('checklist.doneBody'))),
              link(
                'guide-checklist-close',
                copy.text('checklist.close'),
                () => controller.setChecklist(dismissed: true),
              ),
            ],
          ),
        ),
      );
    }
    final header = Row(
      children: [
        Text(copy.text('checklist.title'), style: text.titleMedium),
        SizedBox(width: t.space.sm),
        Text(
          copy
              .text('checklist.progress')
              .replaceAll('{done}', '$done')
              .replaceAll('{total}', '${items.length}'),
          style: text.bodySmall?.copyWith(color: t.colors.textSecondary),
        ),
        SizedBox(width: t.space.sm),
        SizedBox(
          width: 140,
          child: LinearProgressIndicator(
            value: done / items.length,
            minHeight: 4,
            color: t.colors.accent,
            backgroundColor: t.surfaces.raised.fill,
          ),
        ),
        const Spacer(),
        link(
          'guide-checklist-toggle',
          copy.text(
            state.collapsed ? 'checklist.expand' : 'checklist.collapse',
          ),
          () => controller.setChecklist(collapsed: !state.collapsed),
        ),
        link(
          'guide-checklist-dismiss',
          copy.text('checklist.dismiss'),
          () => controller.setChecklist(dismissed: true),
        ),
      ],
    );
    return DecoratedBox(
      key: const Key('guide-checklist'),
      decoration: decoration,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          t.space.lg,
          t.space.sm,
          t.space.sm,
          t.space.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (!state.collapsed) ...[
              SizedBox(height: t.space.sm),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 840 ? 3 : 2;
                  final width =
                      (constraints.maxWidth -
                          t.space.sm * (columns - 1) -
                          t.space.sm) /
                      columns;
                  return Wrap(
                    spacing: t.space.sm,
                    runSpacing: t.space.sm,
                    children: [
                      for (final (id, route) in items)
                        SizedBox(
                          width: width,
                          child: _Item(
                            id: id,
                            done: isDone(id),
                            bodyKey: id == 'overlay' && local
                                ? 'checklist.overlay.localBody'
                                : 'checklist.$id.body',
                            onGo: route == null
                                ? null
                                : () {
                                    if (id == guideWindowsNoticeId) {
                                      widget.hub.windowsNoticeRequested.value =
                                          true;
                                    }
                                    widget.hub.navigate(route);
                                  },
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (local) ...[
                SizedBox(height: t.space.sm),
                Text(
                  copy.text('checklist.localFoot'),
                  style: text.bodySmall?.copyWith(color: t.colors.textDisabled),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.id,
    required this.done,
    required this.bodyKey,
    this.onGo,
  });
  final String id;
  final bool done;
  final String bodyKey;
  final VoidCallback? onGo;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final copy = GuideCopy.of(context);
    final text = Theme.of(context).textTheme;
    final go = copy.maybe('checklist.$id.go');
    return DecoratedBox(
      key: Key('guide-checklist-$id'),
      decoration: BoxDecoration(
        color: done ? null : t.surfaces.raised.fill,
        borderRadius: BorderRadius.circular(t.shape.radiusMedium),
        border: Border.all(color: t.surfaces.raised.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(t.space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drawn, not an icon font, so it renders the same everywhere.
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? t.colors.success : null,
                border: Border.all(
                  color: done ? t.colors.success : t.colors.textDisabled,
                  width: 2,
                ),
              ),
              child: SizedBox.square(
                dimension: 20,
                child: done
                    ? Center(
                        child: Text(
                          '✓',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            color: t.colors.onAccent,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            SizedBox(width: t.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.text('checklist.$id.title'),
                    style: text.titleSmall?.copyWith(
                      color: done ? t.colors.textSecondary : null,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  SizedBox(height: t.space.xxs),
                  Text(
                    copy.text(bodyKey),
                    style: text.bodySmall?.copyWith(
                      color: done
                          ? t.colors.textDisabled
                          : t.colors.textSecondary,
                    ),
                  ),
                  if (!done && go != null && onGo != null)
                    StarBridgeActionButton(
                      controlKey: Key('guide-checklist-$id-go'),
                      kind: StarBridgeActionKind.quiet,
                      onActivate: (_) => onGo!(),
                      child: Text(go),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
