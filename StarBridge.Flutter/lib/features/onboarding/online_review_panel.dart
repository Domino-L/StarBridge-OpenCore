import 'dart:async';

import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_action_button.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../account/game_identity_verification.dart';
import '../account/game_identity_verification_dialog.dart';
import 'onboarding_copy.dart';
import 'online_review_controller.dart';
import 'online_review_port.dart';

class OnlineReviewPanel extends StatefulWidget {
  const OnlineReviewPanel({
    required this.controller,
    required this.copy,
    required this.enabled,
    this.onChanged,
    super.key,
  });
  final OnlineReviewController controller;
  final OnboardingCopy copy;
  final bool enabled;
  final Future<void> Function()? onChanged;
  @override
  State<OnlineReviewPanel> createState() => _OnlineReviewPanelState();
}

class _OnlineReviewPanelState extends State<OnlineReviewPanel> {
  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(OnlineReviewPanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller || !old.enabled && widget.enabled) {
      _read();
    }
  }

  void _read() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.enabled) widget.controller.refresh();
  });
  Future<void> _run(Future<void> Function() work) async {
    await work();
    if (mounted) await widget.onChanged?.call();
  }

  /// Null unless SCM still needs this account verified and the Host can do it.
  GameIdentityVerificationPort? get _verification {
    final port = widget.controller.port;
    if (port is! OnlineReviewGameIdentitySource) return null;
    final verification = (port as OnlineReviewGameIdentitySource).gameIdentity;
    return verification.supportsGameIdentityVerification &&
            const {
              OnlineReviewState.verificationRequired,
              OnlineReviewState.reverifyRequired,
              OnlineReviewState.revoked,
            }.contains(widget.controller.value.snapshot.state)
        ? verification
        : null;
  }

  void _verify(GameIdentityVerificationPort port, InteractionSource source) {
    final snapshot = widget.controller.value.snapshot;
    final opened = snapshot.revision;
    unawaited(
      showGameIdentityVerificationDialog(
        context,
        port,
        initialHandle: snapshot.localHandle,
        source: source,
        // An account event blanks the revision until the next read: only a
        // different revision means this panel's owner is gone.
        isCurrent: () {
          final revision = widget.controller.value.snapshot.revision;
          return mounted && (revision == null || revision == opened);
        },
        ownerChanges: widget.controller,
        onVerified: () => unawaited(
          _run(() => widget.controller.execute(OnlineReviewAction.review)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.controller.value,
        snapshot = widget.controller.value.snapshot;
    final t = context.tokens, copy = widget.copy;
    final status = view.busy
        ? view.action == OnlineReviewAction.cancel
              ? snapshot.retainsSession
                    ? 'cancellingResume'
                    : 'cancelling'
              : view.action == OnlineReviewAction.resume
              ? 'restoring'
              : view.action == OnlineReviewAction.login ||
                    view.action == OnlineReviewAction.reauthorize
              ? 'authorizing'
              : 'checking'
        : view.error
        ? 'error'
        : switch (snapshot.state) {
            OnlineReviewState.unavailable ||
            OnlineReviewState.contextChanged => 'unavailable',
            OnlineReviewState.notStarted || OnlineReviewState.signInRequired =>
              snapshot.retainsSession ? 'resumeRequired' : 'signInRequired',
            OnlineReviewState.identityCheckRequired ||
            OnlineReviewState.reviewExpired => 'checkRequired',
            OnlineReviewState.verificationRequired ||
            OnlineReviewState.reverifyRequired ||
            OnlineReviewState.revoked => 'verificationRequired',
            OnlineReviewState.operationInProgress => 'checking',
            OnlineReviewState.sessionExpired ||
            OnlineReviewState.reauthorizationRequired =>
              'reauthorizationRequired',
            _ => snapshot.state.name,
          };
    final editable = widget.enabled && !view.busy && !view.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          copy.text('onlineReview.title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: t.space.sm),
        Semantics(
          liveRegion: true,
          child: Text(
            copy.text('onlineReview.$status'),
            style: TextStyle(color: t.colors.textSecondary),
          ),
        ),
        if (!view.busy && !view.error && snapshot.localHandle != null) ...[
          SizedBox(height: t.space.md),
          Text(
            copy.text('onlineReview.localHandle'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          SelectableText(snapshot.localHandle!),
        ],
        if (!view.busy &&
            !view.error &&
            snapshot.authoritativeHandle != null) ...[
          SizedBox(height: t.space.md),
          Text(
            copy.text('onlineReview.scmHandle'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          SelectableText(snapshot.authoritativeHandle!),
          if (snapshot.accountDisplayName != null)
            Text(snapshot.accountDisplayName!),
        ],
        SizedBox(height: t.space.md),
        Wrap(
          spacing: t.space.md,
          runSpacing: t.space.sm,
          children: [
            if (snapshot.canBegin || snapshot.canLogin || snapshot.canResume)
              StarBridgeActionButton(
                controlKey: const Key('online-review-login'),
                kind: StarBridgeActionKind.primary,
                onActivate: _tap(
                  editable ? () => _run(widget.controller.signIn) : null,
                ),
                child: Text(
                  copy.text(
                    snapshot.retainsSession ? 'onlineReview.resume' : 'login',
                  ),
                ),
              ),
            if (snapshot.canConfirm)
              StarBridgeActionButton(
                controlKey: const Key('online-review-confirm'),
                kind: StarBridgeActionKind.primary,
                onActivate: _tap(
                  editable
                      ? () => _run(
                          () => widget.controller.execute(
                            OnlineReviewAction.confirm,
                          ),
                        )
                      : null,
                ),
                child: Text(
                  copy.text(
                    snapshot.state == OnlineReviewState.accountReviewRequired
                        ? 'onlineReview.confirmAccount'
                        : 'onlineReview.confirm',
                  ),
                ),
              ),
            if (snapshot.canReauthorize)
              StarBridgeActionButton(
                controlKey: const Key('online-review-reauthorize'),
                kind: StarBridgeActionKind.primary,
                onActivate: _tap(
                  editable
                      ? () => _run(
                          () => widget.controller.execute(
                            OnlineReviewAction.reauthorize,
                          ),
                        )
                      : null,
                ),
                child: Text(copy.text('onlineReview.reauthorize')),
              ),
            if (_verification case final port?)
              StarBridgeActionButton(
                controlKey: const Key('online-review-verify'),
                kind: StarBridgeActionKind.primary,
                onActivate: editable ? (source) => _verify(port, source) : null,
                child: Text(copy.text('onlineReview.verifyGameIdentity')),
              ),
            if (snapshot.canReview &&
                !snapshot.canConfirm &&
                !snapshot.identityConfirmed)
              StarBridgeActionButton(
                controlKey: const Key('online-review-check'),
                kind: StarBridgeActionKind.secondary,
                onActivate: _tap(
                  editable
                      ? () => _run(
                          () => widget.controller.execute(
                            OnlineReviewAction.review,
                          ),
                        )
                      : null,
                ),
                child: Text(copy.text('onlineReview.check')),
              ),
            if (snapshot.canCancel || widget.controller.canCancelLogin)
              StarBridgeActionButton(
                controlKey: const Key('online-review-cancel'),
                kind: StarBridgeActionKind.quiet,
                onActivate: _tap(
                  widget.enabled &&
                          (widget.controller.canCancelLogin ||
                              editable && snapshot.canCancel)
                      ? () => _run(
                          () => widget.controller.execute(
                            OnlineReviewAction.cancel,
                          ),
                        )
                      : null,
                ),
                child: Text(
                  copy.text(
                    snapshot.retainsSession
                        ? 'onlineReview.cancelResume'
                        : 'onlineReview.cancel',
                  ),
                ),
              ),
            StarBridgeActionButton(
              controlKey: const Key('online-review-refresh'),
              kind: StarBridgeActionKind.quiet,
              onActivate: _tap(
                widget.enabled && !view.busy
                    ? () => _run(widget.controller.refresh)
                    : null,
              ),
              child: Text(copy.text('retry')),
            ),
          ],
        ),
      ],
    );
  }
}

/// Native-style tap callback to a suite activation (source unused here).
ValueChanged<InteractionSource>? _tap(VoidCallback? onPressed) =>
    onPressed == null ? null : (_) => onPressed();
