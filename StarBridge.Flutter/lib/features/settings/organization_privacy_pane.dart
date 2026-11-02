import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'help_support_action.dart';
import 'local_privacy_controller.dart';
import 'local_privacy_scope_sections.dart';

/// One organization's complete privacy on its own settings page: the same
/// shared controller, draft and save as the privacy settings page, so the two
/// cannot disagree. [communityCode] is null for the main fleet. The page around
/// it scrolls.
class OrganizationPrivacyPane extends StatefulWidget {
  const OrganizationPrivacyPane({
    required this.controller,
    this.communityCode,
    super.key,
  });

  final LocalPrivacyController controller;
  final String? communityCode;

  @override
  State<OrganizationPrivacyPane> createState() =>
      _OrganizationPrivacyPaneState();
}

class _OrganizationPrivacyPaneState extends State<OrganizationPrivacyPane> {
  @override
  void initState() {
    super.initState();
    widget.controller.open();
  }

  @override
  void didUpdateWidget(OrganizationPrivacyPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.closeEditor();
      widget.controller.open();
    }
  }

  @override
  void dispose() {
    widget.controller.closeEditor();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final strings = AppStrings.of(context);
      String t(String key) => strings.text('privacy.local.$key');
      if (c.status == LocalPrivacyStatus.initial ||
          c.status == LocalPrivacyStatus.loading) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (c.draft == null) {
        return Padding(
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
              HelpSupportAction(
                controlKey: const Key('organization-privacy-retry'),
                kind: StarBridgeActionKind.secondary,
                onActivate: (_) async => c.refresh(),
                child: Text(t('retry')),
              ),
            ],
          ),
        );
      }
      final code = widget.communityCode;
      return Column(
        key: const Key('organization-privacy-pane'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: code == null
                ? LocalPrivacyMainFleetPlaceholder(controller: c)
                : LocalPrivacyOrganizationsSection(
                    controller: c,
                    onlyCode: code,
                  ),
          ),
          if (c.errorKey != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                strings.text(c.errorKey!),
                style: TextStyle(color: context.tokens.colors.warning),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (c.dirty) Text(strings.text('privacy.scope.saveTogether')),
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
                HelpSupportAction(
                  controlKey: const Key('organization-privacy-discard'),
                  onActivate: c.dirty && !c.saving ? (_) => c.discard() : null,
                  child: Text(t('discard')),
                ),
                HelpSupportAction(
                  controlKey: const Key('organization-privacy-save'),
                  kind: StarBridgeActionKind.primary,
                  onActivate: c.canSave ? (_) async => c.save() : null,
                  child: Text(t('save')),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
