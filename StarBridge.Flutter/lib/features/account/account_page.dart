import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'account_models.dart';
import 'account_module.dart';
import 'account_session_views.dart';
import 'account_signed_in_view.dart';
import 'game_identity_verification.dart';
import 'account_view_components.dart';
import 'account_operation_motion.dart';
import 'account_visible_reads.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    required this.module,
    this.footer,
    this.localStatus,
    this.localRecognition,
    this.gameIdentity,
    super.key,
  });

  final AccountModule module;
  final Widget? footer;
  final Widget? localStatus;
  final Widget? localRecognition;
  final GameIdentityVerificationPort? gameIdentity;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final ScrollController _scrollController = ScrollController();
  // 2026-10-21: after a sign-in this page showed cached details for over a
  // minute while the warm-up queue yielded to the user's clicks. What the page
  // shows is read now and is not cancelled by clicks while it is open.
  late void Function() _releaseVisibleReads;

  @override
  void initState() {
    super.initState();
    _releaseVisibleReads = widget.module.holdVisibleReads();
  }

  @override
  void didUpdateWidget(AccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.module, widget.module)) {
      _releaseVisibleReads();
      _releaseVisibleReads = widget.module.holdVisibleReads();
    }
  }

  @override
  void dispose() {
    _releaseVisibleReads();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ValueListenableBuilder<AccountProjection>(
      valueListenable: widget.module.projection,
      builder: (context, projection, _) {
        final owner = widget.module;
        final content = Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsetsDirectional.fromSTEB(
              tokens.space.xl,
              tokens.space.lg,
              tokens.space.xl,
              tokens.space.xxl,
            ),
            child: Align(
              alignment: AlignmentDirectional.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: tokens.density.contentMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (projection.failure case final failure?) ...[
                      AccountMessagePanel(
                        kind: AccountNoticeKind.failure,
                        messageKey: failure.messageKey,
                        actionKey: failure.retryable
                            ? 'account.action.retry'
                            : null,
                        onActionSource: failure.retryable
                            ? (source) {
                                if (!mounted ||
                                    !identical(widget.module, owner) ||
                                    owner.projection.value.generation !=
                                        projection.generation ||
                                    !identical(
                                      owner.projection.value.failure,
                                      failure,
                                    )) {
                                  return;
                                }
                                unawaited(
                                  runAccountMotionCommand(
                                    owner,
                                    AccountOperation.refreshing,
                                    source,
                                    owner.refresh,
                                  ),
                                );
                              }
                            : null,
                      ),
                      SizedBox(height: tokens.space.md),
                    ] else if (projection.notice case final notice?) ...[
                      AccountMessagePanel(
                        kind: notice.kind,
                        messageKey: notice.messageKey,
                      ),
                      SizedBox(height: tokens.space.md),
                    ],
                    switch (projection.sessionState) {
                      AccountSessionState.loading => const AccountLoadingView(),
                      AccountSessionState.signedOut => AccountSignedOutView(
                        projection: projection,
                        module: widget.module,
                        reason: AccountSignedOutReason.noSession,
                      ),
                      AccountSessionState.credentialTemporarilyUnavailable =>
                        AccountSignedOutView(
                          projection: projection,
                          module: widget.module,
                          reason: AccountSignedOutReason
                              .credentialTemporarilyUnavailable,
                        ),
                      AccountSessionState.reauthorizationRequired =>
                        AccountSignedOutView(
                          projection: projection,
                          module: widget.module,
                          reason:
                              AccountSignedOutReason.reauthorizationRequired,
                        ),
                      AccountSessionState.signedIn => AccountSignedInView(
                        projection: projection,
                        module: widget.module,
                        localStatus: widget.localStatus,
                        localRecognition: widget.localRecognition,
                        gameIdentity: widget.gameIdentity,
                      ),
                      AccountSessionState.legacySignedIn ||
                      AccountSessionState.legacyUnavailable =>
                        AccountLegacySessionView(
                          projection: projection,
                          module: widget.module,
                        ),
                    },
                    if (projection.sessionState !=
                            AccountSessionState.signedIn &&
                        (widget.localStatus != null ||
                            widget.localRecognition != null)) ...[
                      SizedBox(height: tokens.space.md),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final status = widget.localStatus;
                          final recognition = widget.localRecognition;
                          final wide =
                              constraints.maxWidth >=
                              960 * MediaQuery.textScalerOf(context).scale(1);
                          if (wide && status != null && recognition != null) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: status),
                                SizedBox(width: tokens.space.md),
                                Expanded(child: recognition),
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ?status,
                              if (status != null && recognition != null)
                                SizedBox(height: tokens.space.md),
                              ?recognition,
                            ],
                          );
                        },
                      ),
                    ],
                    if (widget.footer case final footer?) ...[
                      SizedBox(height: tokens.space.md),
                      footer,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
        return LoadingContentProbe(
          route: '/settings/account',
          status: switch (projection.sessionState) {
            AccountSessionState.loading => LoadingContentStatus.waiting,
            AccountSessionState.signedIn ||
            AccountSessionState.legacySignedIn =>
              projection.isBusy
                  ? LoadingContentStatus.partial
                  : LoadingContentStatus.data,
            _ => LoadingContentStatus.unavailable,
          },
          items: projection.profile == null ? 0 : 1,
          child: content,
        );
      },
    );
  }
}
