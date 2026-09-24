import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'application_support_copy.dart';
import 'application_support_models.dart';
import 'application_support_module.dart';
import 'installation_check_copy.dart';

/// Borrows the existing diagnostics module; it never owns its lifetime.
Future<void> showInstallationCheckDialog(
  BuildContext context,
  ApplicationSupportModule module,
) => showDialog<void>(
  context: context,
  builder: (_) => InstallationCheckDialog(module: module),
);

class InstallationCheckDialog extends StatefulWidget {
  const InstallationCheckDialog({required this.module, super.key});
  final ApplicationSupportModule module;

  @override
  State<InstallationCheckDialog> createState() =>
      _InstallationCheckDialogState();
}

class _InstallationCheckDialogState extends State<InstallationCheckDialog> {
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String t(String key) => installationCheckText(context, key);
    String support(String key) => applicationSupportCopy(context, key);
    return ValueListenableBuilder<ApplicationSupportProjection>(
      valueListenable: widget.module.projection,
      builder: (context, projection, _) {
        final loading = _requested && projection.loading;
        final check = _requested && !loading
            ? projection.snapshot?.installation
            : null;
        return AlertDialog(
          key: const Key('installation-check-dialog'),
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          title: Text(t('title')),
          content: SizedBox(
            width: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('intro')),
                SizedBox(height: tokens.space.md),
                if (loading)
                  Text(t('loading'), semanticsLabel: t('loading'))
                else if (check != null)
                  _InstallationResult(check: check)
                else if (_requested)
                  Text(
                    support(
                      'error.${(projection.failure ?? ApplicationSupportFailure.inspectionFailed).name}',
                    ),
                  ),
                SizedBox(height: tokens.space.md),
                FilledButton(
                  key: const Key('installation-check-scan'),
                  onPressed: loading
                      ? null
                      : () {
                          setState(() => _requested = true);
                          widget.module.refresh();
                        },
                  child: Text(
                    _requested ? support('action.refresh') : t('scan'),
                  ),
                ),
                SizedBox(height: tokens.space.lg),
                Text(
                  t('pending'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                for (final action in ['repair', 'uninstall', 'clean'])
                  Padding(
                    padding: EdgeInsets.only(top: tokens.space.sm),
                    child: OutlinedButton(
                      key: Key('installation-check-$action'),
                      onPressed: null,
                      child: Text(t(action)),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('close')),
            ),
          ],
        );
      },
    );
  }
}

class _InstallationResult extends StatelessWidget {
  const _InstallationResult({required this.check});
  final ApplicationInstallationCheck check;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String t(String key) => installationCheckText(context, key);
    String support(String key) => applicationSupportCopy(context, key);
    final state = check.state;
    final detail = switch (check.detail) {
      'portable' ||
      'installed' ||
      'scanPartial' ||
      'duplicateInstallations' ||
      'staleRegistrations' ||
      'currentInstallationMissing' => check.detail,
      _ => 'readFailed',
    };
    final color = switch (state) {
      ApplicationSupportCheckState.healthy => tokens.colors.success,
      ApplicationSupportCheckState.actionRequired => tokens.colors.warning,
      ApplicationSupportCheckState.unavailable => tokens.colors.textSecondary,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(support('state.${state.name}'), style: TextStyle(color: color)),
        SizedBox(height: tokens.space.xs),
        Text(support('detail.$detail')),
        if (state != ApplicationSupportCheckState.healthy) ...[
          SizedBox(height: tokens.space.xs),
          Text(t('next')),
        ],
        if (check.scanWarnings > 0) ...[
          SizedBox(height: tokens.space.sm),
          Text(t('partial'), style: TextStyle(color: tokens.colors.warning)),
        ],
        // An unavailable scan is not evidence of zero installations.
        if (state != ApplicationSupportCheckState.unavailable) ...[
          SizedBox(height: tokens.space.md),
          Text(t('observed'), style: Theme.of(context).textTheme.labelLarge),
          for (final row in [
            (t('current'), check.currentInstallations),
            (support('count.otherInstallations'), check.otherInstallations),
            (
              support('count.orphanedRegistrations'),
              check.orphanedRegistrations,
            ),
            (support('count.scanWarnings'), check.scanWarnings),
          ])
            Padding(
              padding: EdgeInsets.only(top: tokens.space.xs),
              child: Text('${row.$1}：${row.$2}'),
            ),
        ],
      ],
    );
  }
}
