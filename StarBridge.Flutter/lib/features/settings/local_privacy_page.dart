import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'local_privacy_controller.dart';
import 'local_privacy_scope_sections.dart';
import 'privacy_live_sharing_panel.dart';

final privacyPageLeaveGuards = Expando<Future<bool> Function()>();

class LocalPrivacyPage extends StatefulWidget {
  const LocalPrivacyPage({
    required this.controller,
    this.showSaveBar = true,
    super.key,
  });
  final LocalPrivacyController controller;
  final bool showSaveBar;
  @override
  State<LocalPrivacyPage> createState() => _LocalPrivacyPageState();
}

class _LocalPrivacyPageState extends State<LocalPrivacyPage> {
  @override
  void dispose() {
    widget.controller.closeEditor();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.open();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final strings = AppStrings.of(context);
      String t(String key) => strings.text('privacy.local.$key');
      final tokens = context.tokens;
      if (c.status == LocalPrivacyStatus.initial ||
          c.status == LocalPrivacyStatus.loading) {
        return Center(
          child: Semantics(
            label: t('loading'),
            child: const CircularProgressIndicator(),
          ),
        );
      }
      if (c.draft == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t(
                    c.status == LocalPrivacyStatus.signedOut
                        ? 'accountChanged'
                        : 'readFailed',
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(onPressed: c.refresh, child: Text(t('retry'))),
              ],
            ),
          ),
        );
      }

      return Column(
        key: const Key('local-privacy-page'),
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(tokens.space.lg),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: tokens.density.contentMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t('title'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(strings.text('privacy.scope.description')),
                      const SizedBox(height: 16),
                      PrivacyLiveSharingPanel(controller: c),
                      if (c.locationConfidenceSupported) ...[
                        const SizedBox(height: 12),
                        SwitchListTile.adaptive(
                          key: const Key('privacy-location-confidence'),
                          title: Text(t('locationConfidence')),
                          subtitle: Text(t('locationConfidenceDescription')),
                          value: c.draft!.effectiveHideLowConfidenceLocation,
                          onChanged: c.canEdit
                              ? (value) => c.edit(
                                  c.draft!.copyWith(
                                    hideLowConfidenceLocation: value,
                                  ),
                                )
                              : null,
                        ),
                      ],
                      if (c.errorKey != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          strings.text(c.errorKey!),
                          style: TextStyle(color: tokens.colors.warning),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: const Key('privacy-reload'),
                            onPressed: c.saving
                                ? null
                                : () async {
                                    if (await confirmLocalPrivacyLeave(
                                      context,
                                      c,
                                    )) {
                                      await c.refresh();
                                    }
                                  },
                            child: Text(t('reload')),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      LocalPrivacyRoomSection(controller: c),
                      const SizedBox(height: 16),
                      const LocalPrivacyMainFleetPlaceholder(),
                      const SizedBox(height: 24),
                      LocalPrivacyOrganizationsSection(controller: c),
                      const SizedBox(height: 16),
                      Text(
                        strings.text('privacy.scope.separate'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.showSaveBar) ...[
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.all(tokens.space.md),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    t(
                      c.saving
                          ? 'saving'
                          : c.dirty
                          ? 'dirty'
                          : c.hasSaved
                          ? (c.publicationSupported ? 'savedLocal' : 'saved')
                          : 'defaults',
                    ),
                  ),
                  TextButton(
                    key: const Key('privacy-discard'),
                    onPressed: c.dirty && !c.saving ? c.discard : null,
                    child: Text(t('discard')),
                  ),
                  FilledButton(
                    key: const Key('privacy-save'),
                    onPressed: c.canSave ? c.save : null,
                    child: Text(t('save')),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

Future<bool> confirmLocalPrivacyLeave(
  BuildContext context,
  LocalPrivacyController c,
) async {
  final guard = privacyPageLeaveGuards[c];
  if (guard != null) return guard();
  if (c.saving || c.publicationBusy) return false;
  if (!c.dirty) return true;
  final draft = c.draft;
  final strings = AppStrings.of(context);
  String t(String key) => strings.text('privacy.local.$key');
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      key: const Key('privacy-leave-dialog'),
      title: Text(t('leaveTitle')),
      content: Text(t(c.publicationSupported ? 'leaveLiveBody' : 'leaveBody')),
      actions: [
        TextButton(
          key: const Key('privacy-leave-cancel'),
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(t('stay')),
        ),
        TextButton(
          key: const Key('privacy-leave-discard'),
          onPressed: () => Navigator.pop(context, 'discard'),
          child: Text(t('discard')),
        ),
        if (c.canSave)
          FilledButton(
            key: const Key('privacy-leave-save'),
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(t('save')),
          ),
      ],
    ),
  );
  // An old confirmation must never save a newly signed-in account's defaults.
  if (!identical(draft, c.draft)) return false;
  if (choice == 'save') return c.save();
  if (choice == 'discard') {
    c.discard();
    return true;
  }
  return false;
}
