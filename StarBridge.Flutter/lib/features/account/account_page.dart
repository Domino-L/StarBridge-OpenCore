import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'account_models.dart';
import 'account_module.dart';
import 'account_session_views.dart';
import 'account_signed_in_view.dart';
import 'account_view_components.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    required this.module,
    this.footer,
    this.localStatus,
    this.localRecognition,
    super.key,
  });

  final AccountModule module;
  final Widget? footer;
  final Widget? localStatus;
  final Widget? localRecognition;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ValueListenableBuilder<AccountProjection>(
      valueListenable: widget.module.projection,
      builder: (context, projection, _) {
        return Scrollbar(
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
                        onAction: failure.retryable
                            ? () => unawaited(widget.module.refresh())
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
                      ),
                      AccountSessionState.legacySignedIn ||
                      AccountSessionState.legacyUnavailable =>
                        AccountLegacySessionView(
                          projection: projection,
                          module: widget.module,
                        ),
                    },
                    if (widget.localStatus != null ||
                        widget.localRecognition != null) ...[
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
      },
    );
  }
}
