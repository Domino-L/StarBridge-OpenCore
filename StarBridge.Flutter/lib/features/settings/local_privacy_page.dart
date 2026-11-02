import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'help_support_action.dart';
import 'help_support_waiting.dart';

import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';

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
  InteractionSource _waitSource = InteractionSource.programmatic;
  int _waitPhase = 0;
  bool _wasSaving = false;
  bool _wasPublishing = false;
  LocalPrivacyStatus? _lastStatus;

  void _observeWait() {
    final c = widget.controller;
    if (c.saving && !_wasSaving ||
        c.publicationBusy && !_wasPublishing ||
        c.status == LocalPrivacyStatus.loading && _lastStatus != c.status) {
      _waitSource = captureStarBridgeActivationSource()();
      _waitPhase++;
    }
    _wasSaving = c.saving;
    _wasPublishing = c.publicationBusy;
    _lastStatus = c.status;
  }

  Future<void> _save(InteractionSource source) =>
      runStarBridgeActivation<void>(source, () async {
        await widget.controller.save();
      });

  @override
  void didUpdateWidget(LocalPrivacyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_observeWait);
      widget.controller.addListener(_observeWait);
      _waitSource = InteractionSource.programmatic;
      _waitPhase++;
      _wasSaving = false;
      _wasPublishing = false;
      _lastStatus = null;
      _observeWait();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_observeWait);
    widget.controller.closeEditor();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_observeWait);
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
      Widget measured(
        Widget child,
        LoadingContentStatus status, {
        int items = 0,
      }) => LoadingContentProbe(
        route: '/settings/privacy',
        status: status,
        items: items,
        child: child,
      );
      if (c.status == LocalPrivacyStatus.initial ||
          c.status == LocalPrivacyStatus.loading) {
        return measured(
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: HelpSupportWaiting(
                key: ValueKey(('privacy-loading', _waitPhase)),
                label: t('loading'),
                source: _waitSource,
              ),
            ),
          ),
          LoadingContentStatus.waiting,
        );
      }
      if (c.draft == null) {
        return measured(
          Center(
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
                  HelpSupportAction(
                    controlKey: const Key('privacy-read-retry'),
                    kind: StarBridgeActionKind.secondary,
                    onActivate: (source) =>
                        runStarBridgeActivation<void>(source, () async {
                          await c.refresh();
                        }),
                    child: Text(t('retry')),
                  ),
                ],
              ),
            ),
          ),
          LoadingContentStatus.unavailable,
        );
      }

      return measured(
        Column(
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
                          StarBridgeSwitch.tile(
                            key: const Key('privacy-location-confidence'),
                            preserveNativeTile: true,
                            rowBuilder: (control) => Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child:
                                    resolveStarBridgeInteraction(context)
                                            .suite ==
                                        InteractionSuite.standard
                                    ? control
                                    : ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        enabled: c.canEdit,
                                        title: Text(t('locationConfidence')),
                                        subtitle: Text(
                                          t('locationConfidenceDescription'),
                                        ),
                                        trailing: control,
                                      ),
                              ),
                            ),
                            label: t('locationConfidence'),
                            subtitle: t('locationConfidenceDescription'),
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
                            child: HelpSupportAction(
                              controlKey: const Key('privacy-reload'),
                              onActivate: c.saving
                                  ? null
                                  : (source) => runStarBridgeActivation<void>(
                                      source,
                                      () async {
                                        if (await confirmLocalPrivacyLeave(
                                          context,
                                          c,
                                        )) {
                                          await c.refresh();
                                        }
                                      },
                                    ),
                              child: Text(t('reload')),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        LocalPrivacyRoomSection(controller: c),
                        const SizedBox(height: 16),
                        LocalPrivacyMainFleetPlaceholder(controller: c),
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
                    if (c.saving || c.publicationBusy)
                      SizedBox(
                        width: 240,
                        child: HelpSupportWaiting(
                          key: ValueKey(('privacy-saving', _waitPhase)),
                          source: _waitSource,
                          label: c.saving
                              ? t('saving')
                              : strings.text('privacy.scope.live.publishing'),
                        ),
                      )
                    else
                      Text(
                        t(
                          c.saving
                              ? 'saving'
                              : c.dirty
                              ? 'dirty'
                              : c.hasSaved
                              ? (c.publicationSupported
                                    ? 'savedLocal'
                                    : 'saved')
                              : 'defaults',
                        ),
                      ),
                    HelpSupportAction(
                      controlKey: const Key('privacy-discard'),
                      onActivate: c.dirty && !c.saving
                          ? (_) => c.discard()
                          : null,
                      child: Text(t('discard')),
                    ),
                    HelpSupportAction(
                      controlKey: const Key('privacy-save'),
                      kind: StarBridgeActionKind.primary,
                      onActivate: c.canSave ? _save : null,
                      child: Text(t('save')),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        LoadingContentStatus.data,
        items: 1,
      );
    },
  );
}

Future<bool> confirmLocalPrivacyLeave(
  BuildContext context,
  LocalPrivacyController c,
) {
  final guard = privacyPageLeaveGuards[c];
  if (guard != null) return guard();
  final completeActivation = captureStarBridgeActivationCompletion();
  return runStarBridgeActivation<
    bool
  >(currentStarBridgeActivationSource, () async {
    if (c.saving || c.publicationBusy) return false;
    if (!c.dirty) return true;
    final draft = c.draft;
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('privacy.local.$key');
    final choice = await showStarBridgeDialog<String>(
      context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const Key('privacy-leave-dialog'),
        title: Text(t('leaveTitle')),
        content: Text(
          t(c.publicationSupported ? 'leaveLiveBody' : 'leaveBody'),
        ),
        actions: [
          HelpSupportAction(
            controlKey: const Key('privacy-leave-cancel'),
            onActivate: (source) => dismissStarBridgeDialog<String>(
              context,
              source: source,
              result: 'cancel',
            ),
            child: Text(t('stay')),
          ),
          HelpSupportAction(
            controlKey: const Key('privacy-leave-discard'),
            onActivate: (source) => dismissStarBridgeDialog<String>(
              context,
              source: source,
              result: 'discard',
            ),
            child: Text(t('discard')),
          ),
          if (c.canSave)
            HelpSupportAction(
              controlKey: const Key('privacy-leave-save'),
              kind: StarBridgeActionKind.primary,
              onActivate: (source) => dismissStarBridgeDialog<String>(
                context,
                source: source,
                result: 'save',
              ),
              child: Text(t('save')),
            ),
        ],
      ),
    );
    completeActivation(currentStarBridgeActivationSource);
    // An old confirmation must never save a newly signed-in account's defaults.
    if (!identical(draft, c.draft)) return false;
    if (choice == 'save') return c.save();
    if (choice == 'discard') {
      c.discard();
      return true;
    }
    return false;
  });
}
