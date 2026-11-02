import '../../design_system/icons/standard_icon.dart';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/social_read_activity.dart';
import 'runtime_status_controller.dart';
import 'runtime_status_copy.dart';

/// The caller owns the read-only controller and disposes it after the dialog.
Future<void> showRuntimeStatusDialog(
  BuildContext context,
  RuntimeStatusController controller,
) => showStarBridgeDialog<void>(
  context,
  builder: (_) => RuntimeStatusDialog(controller: controller),
);

class RuntimeStatusDialog extends StatefulWidget {
  const RuntimeStatusDialog({
    required this.controller,
    this.embedded = false,
    super.key,
  });
  final bool embedded;
  final RuntimeStatusController controller;
  @override
  State<RuntimeStatusDialog> createState() => _RuntimeStatusDialogState();
}

class _RuntimeStatusDialogState extends State<RuntimeStatusDialog> {
  bool _detailsExpanded = false;
  late SocialReadActivityBinding _readActivity;
  int? _attachedBusyRevision;

  void _bindReadActivity({required bool initialAttachment}) {
    final controller = widget.controller;
    final alreadyBusy = controller.value.busy;
    _readActivity = SocialReadActivityBinding(
      controller,
      () => controller.value.busy,
      initialRead: initialAttachment && !alreadyBusy,
    );
    // Borrowing an in-flight read does not reveal who started it. Do not
    // relabel that existing phase from this dialog's opening command.
    _attachedBusyRevision = alreadyBusy ? _readActivity.revision : null;
  }

  @override
  void initState() {
    super.initState();
    _bindReadActivity(initialAttachment: true);
    widget.controller.refresh();
  }

  @override
  void didUpdateWidget(RuntimeStatusDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _readActivity.dispose();
      _bindReadActivity(initialAttachment: false);
      widget.controller.refresh();
    }
  }

  @override
  void dispose() {
    _readActivity.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<RuntimeStatusView>(
    valueListenable: widget.controller,
    builder: (context, value, _) {
      String t(String key) => runtimeStatusText(context, key);
      final tokens = context.tokens;
      final facts = value.installation, overlay = value.overlay;
      String known(String? text) =>
          text == null || text.isEmpty ? t('unknown') : text;
      final rows = <(String, String)>[
        ('overlay', t(overlay?.windowState ?? 'unknown')),
        (
          'hotkey',
          '${known(overlay?.hotkeyBinding)}\n${t(overlay?.hotkeyState ?? 'unknown')}',
        ),
      ];
      final details = <(String, String)>[
        ('version', known(facts?.applicationVersion)),
        ('data', known(facts?.dataDirectory)),
        (
          'images',
          facts == null
              ? t('unknown')
              : '${facts.imageCacheDirectory}${facts.imageCacheExists ? '' : '\n${t('cacheMissing')}'}',
        ),
        ('server', known(facts?.serverOrigin)),
      ];
      final hotkeyNeedsAttention = const {
        'gameCompatibleOnly',
        'desktopOnly',
        'conflict',
        'invalid',
        'failed',
      }.contains(overlay?.hotkeyState);
      final content = StarBridgeSurface(
        role: widget.embedded ? SurfaceRole.panel : SurfaceRole.floating,
        child: SizedBox(
          width: 760,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('title'), style: Theme.of(context).textTheme.titleLarge),
              SizedBox(height: tokens.space.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (value.busy) ...[
                        ExcludeSemantics(
                          child: SocialReadActivity(
                            key: ValueKey<Object>((
                              _readActivity,
                              _readActivity.revision,
                            )),
                            source:
                                _attachedBusyRevision == _readActivity.revision
                                ? InteractionSource.programmatic
                                : _readActivity.source,
                            opening:
                                _attachedBusyRevision !=
                                    _readActivity.revision &&
                                _readActivity.opening,
                            height:
                                ProgressIndicatorTheme.of(context)
                                    .linearMinHeight ??
                                4,
                            label: '',
                          ),
                        ),
                        SizedBox(height: tokens.space.sm),
                        Text(t('loading')),
                      ] else ...[
                        if (value.incomplete)
                          Text(
                            t('partial'),
                            key: const Key('runtime-status-partial'),
                            style: TextStyle(color: tokens.colors.warning),
                          ),
                        LayoutBuilder(
                          builder: (context, constraints) => Wrap(
                            spacing: tokens.space.lg,
                            children: [
                              for (final row in [
                                ...rows,
                                if (_detailsExpanded) ...details,
                              ])
                                SizedBox(
                                  width: constraints.maxWidth >= 650
                                      ? (constraints.maxWidth -
                                                tokens.space.lg) /
                                            2
                                      : constraints.maxWidth,
                                  child: Padding(
                                    key: Key('runtime-status-${row.$1}'),
                                    padding: EdgeInsets.symmetric(
                                      vertical: tokens.space.sm,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          t(row.$1),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color:
                                                    tokens.colors.textSecondary,
                                              ),
                                        ),
                                        SizedBox(height: tokens.space.xxs),
                                        SelectableText(
                                          row.$2,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color:
                                                    row.$1 == 'hotkey' &&
                                                        hotkeyNeedsAttention
                                                    ? tokens.colors.warning
                                                    : null,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        StarBridgeActionButton(
                          kind: StarBridgeActionKind.quiet,
                          controlKey: const Key('runtime-status-details'),
                          onActivate: (_) => setState(
                            () => _detailsExpanded = !_detailsExpanded,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StandardIcon(
                                _detailsExpanded
                                    ? StandardIconSemantic.expandLess
                                    : StandardIconSemantic.expandMore,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                t(_detailsExpanded ? 'hideDetails' : 'details'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: tokens.space.sm),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: tokens.space.sm,
                children: [
                  StarBridgeActionButton(
                    controlKey: const Key('runtime-status-refresh'),
                    onActivate: value.busy
                        ? null
                        : (_) => widget.controller.refresh(),
                    child: Text(t('refresh')),
                  ),
                  if (!widget.embedded)
                    StarBridgeActionButton(
                      kind: StarBridgeActionKind.quiet,
                      controlKey: const Key('runtime-status-close'),
                      onActivate: (source) =>
                          dismissStarBridgeDialog(context, source: source),
                      child: Text(t('close')),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
      return widget.embedded
          ? content
          : Dialog(
              key: const Key('settings-entry-runtime-status'),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: content,
            );
    },
  );
}
