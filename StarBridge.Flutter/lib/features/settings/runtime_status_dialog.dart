import '../../design_system/icons/standard_icon.dart';
import 'package:flutter/material.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'runtime_status_controller.dart';
import 'runtime_status_copy.dart';

/// The caller owns the read-only controller and disposes it after the dialog.
Future<void> showRuntimeStatusDialog(
  BuildContext context,
  RuntimeStatusController controller,
) => showDialog<void>(
  context: context,
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
  @override
  void initState() {
    super.initState();
    widget.controller.refresh();
  }

  @override
  void didUpdateWidget(RuntimeStatusDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) widget.controller.refresh();
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
                        LinearProgressIndicator(semanticsLabel: t('loading')),
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
                        TextButton.icon(
                          key: const Key('runtime-status-details'),
                          onPressed: () => setState(
                            () => _detailsExpanded = !_detailsExpanded,
                          ),
                          icon: StandardIcon(
                            _detailsExpanded
                                ? StandardIconSemantic.expandLess
                                : StandardIconSemantic.expandMore,
                          ),
                          label: Text(
                            t(_detailsExpanded ? 'hideDetails' : 'details'),
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
                  OutlinedButton(
                    key: const Key('runtime-status-refresh'),
                    onPressed: value.busy ? null : widget.controller.refresh,
                    child: Text(t('refresh')),
                  ),
                  if (!widget.embedded)
                    TextButton(
                      key: const Key('runtime-status-close'),
                      onPressed: () => Navigator.of(context).pop(),
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
