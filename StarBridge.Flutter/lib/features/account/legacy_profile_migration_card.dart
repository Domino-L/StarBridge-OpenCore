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
import 'legacy_profile_import_dialog.dart';
import '../personal_profile/personal_profile_collaboration.dart';

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
    // A pre-selection migration ticket can contain a whole-profile replacement.
    // Never label or confirm it as a selected module import.
    if ((view.state == 'previewed' || view.state == 'localApplyRequired') &&
        (view.choices == null ||
            (view.choices?.version == 2
                ? view.presentation == null
                : view.selectedContent == null))) {
      view = const LegacyProfileMigrationView('previewRequired');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _view = view;
      if (view.state == 'previewed' || view.state == 'localApplyRequired') {
        _preview = view;
        _ownerConfirmed = false;
        _replaceExisting = false;
      } else if (view.state != 'sourceUnavailable' &&
          view.state != 'localSaveUnavailable') {
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
    final previous = _view.state == 'completed' ? _view.previewId : null;
    final credential = await showLegacyAccountCredentialDialog(
      context,
      forMigration: true,
    );
    if (!mounted || credential == null) return;
    final selection = await showLegacyProfileImportDialog(context);
    if (!mounted || selection == null) return;
    await _run(
      () => widget.port.previewMigration(
        credential: credential,
        selection: LegacyProfileImportSelection(
          modules: selection.modules,
          replaceModules: selection.replaceModules,
          useLegacyCallSign: selection.useLegacyCallSign,
          useLegacyAvatar: selection.useLegacyAvatar,
          previousCompletedPreviewId: previous,
          replaceAllDisplayContent: selection.replaceAllDisplayContent,
        ),
      ),
      'previewLoading',
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    String text(String key) => strings.text('migration.$key');
    String tags(List<String> values, String group) => values.isEmpty
        ? text('emptySelection')
        : values
              .map((value) {
                final known = ProfileCollaboration.options[group]?[value];
                return known == null ? value : strings.text(known.labelKey);
              })
              .join(' · ');
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
                if (preview.choices case final choices?) ...[
                  if (choices.version == 2) ...[
                    Text(text('selectFull')),
                    Text(text('fullScope')),
                    Text(
                      '${text('selectCallSign')}：${preview.presentation!['callSign']}',
                    ),
                    Text(
                      '${preview.presentation!['content'] is Map ? (preview.presentation!['content'] as Map)['introduction'] ?? '' : ''}',
                    ),
                  ],
                  if (choices.selection.useLegacyCallSign)
                    Text(
                      '${text('selectCallSign')}：${preview.selectedContent!.callSign}',
                    ),
                  if (choices.selection.useLegacyAvatar ||
                      choices.version == 2 && preview.avatarPreview != null)
                    Text(text('selectAvatar')),
                  if ((choices.selection.useLegacyAvatar ||
                          choices.version == 2) &&
                      preview.avatarPreview != null)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
                      child: Image.memory(
                        preview.avatarPreview!,
                        key: const Key('migration-avatar-preview'),
                        width: 96,
                        height: 96,
                        fit: BoxFit.contain,
                        semanticLabel: text('selectAvatar'),
                        errorBuilder: (context, error, stack) =>
                            Text(text('sourceAvatarUnavailable')),
                      ),
                    ),
                  for (final id in choices.selection.modules)
                    Text(
                      '${text('module.$id')} · ${text('moduleSpan').replaceAll('{span}', '${preview.selectedContent!.modules[id]}')}${choices.selection.replaceModules.contains(id) ? ' · ${text('replaceModule')}' : ''}',
                    ),
                  if (preview.selectedContent?.skilledRoles
                      case final roles?) ...[
                    Text('${text('roles')}：${tags(roles, 'roles')}'),
                    Text(
                      '${text('support')}：${tags(preview.selectedContent!.supportCapabilities!, 'support')}',
                    ),
                    Text(
                      '${text('interests')}：${tags(preview.selectedContent!.participationInterests!, 'interests')}',
                    ),
                  ],
                  if (choices.needsReselection.isNotEmpty)
                    Text(text('moduleSafety')),
                  SizedBox(height: tokens.space.sm),
                ],
                if (preview.conflict) ...[
                  const Divider(),
                  CheckboxListTile(
                    key: const Key('migration-replace'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      text(
                        preview.choices?.version == 2
                            ? 'fullReplaceConsent'
                            : 'replaceConsent',
                      ),
                    ),
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
                      child: Text(
                        text(
                          _view.state == 'localApplyRequired'
                              ? 'applyLocal'
                              : 'confirm',
                        ),
                      ),
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
              ] else if (!completed ||
                  (_view.choices != null && _view.previewId != null)) ...[
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
}
