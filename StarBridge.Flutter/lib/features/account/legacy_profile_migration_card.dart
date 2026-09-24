import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import 'account_view_components.dart';
import 'account_compatibility_card.dart';
import 'legacy_profile_migration.dart';

class LegacyProfileMigrationCard extends StatefulWidget {
  const LegacyProfileMigrationCard({required this.port, super.key});
  final LegacyProfileMigrationPort port;
  @override
  State<LegacyProfileMigrationCard> createState() =>
      _LegacyProfileMigrationCardState();
}

class _LegacyProfileMigrationCardState
    extends State<LegacyProfileMigrationCard> {
  LegacyProfileMigrationView _view = const LegacyProfileMigrationView(
    'notStarted',
  );
  LegacyProfileMigrationView? _preview;
  bool _busy = true;
  bool _ownerConfirmed = false;
  bool _replaceExisting = false;
  String _operation = 'loading';

  @override
  void initState() {
    super.initState();
    unawaited(_run(widget.port.migrationStatus, 'loading'));
  }

  Future<void> _run(
    Future<LegacyProfileMigrationView> Function() action,
    String operation,
  ) async {
    setState(() {
      _busy = true;
      _operation = operation;
    });
    LegacyProfileMigrationView view;
    try {
      view = await action();
    } on Object {
      view = const LegacyProfileMigrationView('sourceUnavailable');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _view = view;
      if (view.state == 'previewed') {
        _preview = view;
        _ownerConfirmed = false;
        _replaceExisting = false;
      } else if (view.state != 'sourceUnavailable') {
        _preview = null;
      }
    });
  }

  Future<void> _confirm() => _run(
    () => widget.port.confirmMigration(
      _preview!.previewId!,
      replaceExisting: _replaceExisting,
    ),
    'importing',
  );

  Future<void> _requestPreview() async {
    final credential = await showLegacyAccountCredentialDialog(
      context,
      forMigration: true,
    );
    if (!mounted || credential == null) return;
    await _run(
      () => widget.port.previewMigration(credential: credential),
      'previewLoading',
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    String text(String key) => strings.text('migration.$key');
    final completed = _view.state == 'completed';
    final preview = _preview;
    final failure = !{
      'notStarted',
      'previewed',
      'completed',
      'credentialRequired',
    }.contains(_view.state);
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountCardHeading(
              semantic: StarBridgeIconSemantic.account,
              titleKey: 'migration.title',
              bodyKey: completed
                  ? 'migration.completedBody'
                  : 'migration.scope',
              color: completed ? tokens.colors.success : tokens.colors.accent,
            ),
            SizedBox(height: tokens.space.sm),
            Text(
              text('organizationPending'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
            SizedBox(height: tokens.space.md),
            if (_busy) ...[
              const LinearProgressIndicator(),
              SizedBox(height: tokens.space.sm),
              Text(text(_operation), semanticsLabel: text(_operation)),
            ] else ...[
              Text(
                text(_view.state),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: completed
                      ? tokens.colors.success
                      : failure
                      ? tokens.colors.warning
                      : tokens.colors.textSecondary,
                ),
              ),
              if (preview != null && !completed) ...[
                SizedBox(height: tokens.space.md),
                _summary(
                  context,
                  text('oldProfile'),
                  preview.source!,
                  preview.sourceGameId,
                ),
                if (preview.conflict) ...[
                  const Divider(),
                  _summary(context, text('newProfile'), preview.target!, null),
                  CheckboxListTile(
                    key: const Key('migration-replace'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(text('replaceConsent')),
                    value: _replaceExisting,
                    onChanged: (value) =>
                        setState(() => _replaceExisting = value == true),
                  ),
                ],
                CheckboxListTile(
                  key: const Key('migration-owner'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(text('ownerConsent')),
                  value: _ownerConfirmed,
                  onChanged: (value) =>
                      setState(() => _ownerConfirmed = value == true),
                ),
                Text(
                  text('preserved'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: tokens.space.md),
                Wrap(
                  spacing: tokens.space.sm,
                  runSpacing: tokens.space.sm,
                  children: [
                    FilledButton(
                      key: const Key('migration-confirm'),
                      onPressed:
                          _ownerConfirmed &&
                              (!preview.conflict || _replaceExisting)
                          ? _confirm
                          : null,
                      child: Text(text('confirm')),
                    ),
                    if (failure)
                      OutlinedButton(
                        onPressed: () =>
                            _run(widget.port.migrationStatus, 'loading'),
                        child: Text(text('retryStatus')),
                      ),
                    TextButton(
                      onPressed: () => setState(() {
                        _view = const LegacyProfileMigrationView(
                          'previewRequired',
                        );
                        _preview = null;
                        _ownerConfirmed = false;
                        _replaceExisting = false;
                      }),
                      child: Text(text('cancel')),
                    ),
                  ],
                ),
              ] else if (!completed) ...[
                SizedBox(height: tokens.space.md),
                Wrap(
                  spacing: tokens.space.sm,
                  runSpacing: tokens.space.sm,
                  children: [
                    FilledButton(
                      key: const Key('migration-preview'),
                      onPressed: _view.state == 'sourceNotConfigured'
                          ? null
                          : _requestPreview,
                      child: Text(text('preview')),
                    ),
                    if (failure)
                      OutlinedButton(
                        onPressed: () =>
                            _run(widget.port.migrationStatus, 'loading'),
                        child: Text(text('retryStatus')),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _summary(
    BuildContext context,
    String label,
    LegacyProfileMigrationSummary summary,
    String? handle,
  ) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          '${summary.callSign}${handle?.isNotEmpty == true ? ' · @$handle' : ''}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (summary.introduction.isNotEmpty) Text(summary.introduction),
        Text(
          strings
              .text('migration.counts')
              .replaceAll('{modules}', '${summary.modules}')
              .replaceAll('{favorites}', '${summary.favorites}')
              .replaceAll(
                '{hours}',
                summary.playTimeSeconds == null
                    ? '—'
                    : (summary.playTimeSeconds! / 3600).toStringAsFixed(1),
              ),
        ),
      ],
    );
  }
}
