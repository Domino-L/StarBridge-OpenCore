import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../onboarding/bridge_onboarding_adapter.dart';
import '../onboarding/onboarding_models.dart';
import '../onboarding/onboarding_copy.dart';
import '../onboarding/game_log_search_panel.dart';

/// The device-local settings entry borrows the same Host selection/evidence
/// owner as setup. Completing setup is never used as identity authority.
class LocalGameLogSetupPanel extends StatefulWidget {
  const LocalGameLogSetupPanel({
    required this.session,
    this.onConfirmed,
    this.allowOnlineSetup = false,
    super.key,
  });
  final BridgeClientSession session;
  final Future<void> Function()? onConfirmed;
  final bool allowOnlineSetup;
  @override
  State<LocalGameLogSetupPanel> createState() => _LocalGameLogSetupPanelState();
}

class _LocalGameLogSetupPanelState extends State<LocalGameLogSetupPanel> {
  late final _port = BridgeOnboardingAdapter(widget.session);
  OnboardingReply? _reply;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_run(OnboardingAction.locateLogs));
  }

  OnboardingCheckpoint _checkpoint(OnboardingStep step) => OnboardingCheckpoint(
    step: step,
    mode: widget.allowOnlineSetup && _reply!.facts.onlineSetupPending
        ? OnboardingMode.online
        : OnboardingMode.local,
    sourceKey: _reply!.facts.sourceKey,
    evidenceKey: _reply!.facts.evidenceKey,
  );

  Future<void> _run([OnboardingAction? action, int? candidateIndex]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (candidateIndex == null) _reply = await _port.read();
      if (action != null &&
          _reply!.facts.activeMode == OnboardingMode.local &&
          _reply!.facts.publicationSuspended &&
          (widget.allowOnlineSetup || !_reply!.facts.onlineSetupPending)) {
        final checkpoint = _checkpoint(
          action == OnboardingAction.selectLog ||
                  action == OnboardingAction.locateLogs
              ? OnboardingStep.log
              : OnboardingStep.identity,
        );
        _reply = candidateIndex == null
            ? await _port.execute(action, checkpoint)
            : await _port.selectLogCandidate(candidateIndex, checkpoint);
        if (action == OnboardingAction.selectLog &&
            _reply!.facts.sourceKey != null) {
          _reply = await _port.execute(
            OnboardingAction.refresh,
            _checkpoint(OnboardingStep.identity),
          );
        }
        if (action == OnboardingAction.confirmHandle ||
            action == OnboardingAction.finishLogSetup) {
          await widget.onConfirmed?.call();
        }
      }
    } on Object catch (error) {
      // Confirmation may have committed identity before a later save failed.
      // Reread the durable pending state so recovery is visible immediately.
      try {
        _reply = await _port.read();
      } on Object {
        // Keep the last observation if the Host cannot be reached.
      }
      _error = switch (error) {
        BridgeClientException(code: 'firstUse.source_invalid') =>
          'sourceInvalid',
        BridgeClientException(code: 'firstUse.storage_unavailable') =>
          'storageUnavailable',
        _ => 'error',
      };
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = OnboardingCopy(Localizations.localeOf(context));
    final f = _reply?.facts;
    final enabled =
        !_busy &&
        f?.activeMode == OnboardingMode.local &&
        f?.publicationSuspended == true &&
        (widget.allowOnlineSetup || f?.onlineSetupPending == false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          copy.text('step.log'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(copy.text('description.log')),
        if (_error != null) Text(copy.text(_error!)),
        if (_busy) Text(copy.text('busy')),
        if (f?.logDeferred == true)
          Text(copy.text('summary.detail.log.deferred')),
        if (f?.handle != null) SelectableText(f!.handle!),
        if (f?.version != null) Text(f!.version!),
        if (f?.localIdentityConfirmed == true)
          Text(copy.text('summary.detail.identity.confirmed')),
        if (f?.logSetupPending == true) Text(copy.text('logSetupPending')),
        SizedBox(height: context.tokens.space.md),
        GameLogSearchPanel(
          copy: copy,
          candidates: f?.logCandidates,
          blocked: f?.logSearchBlocked ?? false,
          busy: _busy,
          enabled: enabled,
          onSelect: (index) => _run(OnboardingAction.selectLog, index),
          onManual: () => _run(OnboardingAction.selectLog),
          onSearch: () => _run(OnboardingAction.locateLogs),
          manualKey: const Key('local-settings-select-log'),
          searchKey: const Key('local-settings-refresh-log'),
        ),
        Wrap(
          spacing: context.tokens.space.md,
          children: [
            if (f?.hasCandidate == true && f?.localIdentityConfirmed != true)
              StarBridgeActionButton(
                controlKey: const Key('local-settings-confirm-handle'),
                onActivate: enabled
                    ? (_) => unawaited(_run(OnboardingAction.confirmHandle))
                    : null,
                child: Text(copy.text('confirm')),
              ),
            if (f?.logSetupPending == true)
              StarBridgeActionButton(
                controlKey: const Key('local-settings-finish-log-setup'),
                onActivate: enabled
                    ? (_) => unawaited(_run(OnboardingAction.finishLogSetup))
                    : null,
                child: Text(copy.text('finishLogSetup')),
              ),
          ],
        ),
      ],
    );
  }
}
