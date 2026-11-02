import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/brand/scm_success_motion.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import 'account_operation_motion.dart';
import 'account_models.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'account_details_readiness.dart';
import 'account_module.dart';
import 'account_visible_reads.dart';

// One route per module: repeated clicks must not create competing login flows.
final _openDialogs = Expando<bool>();
bool isAccountLoginDialogOpen(AccountModule module) =>
    _openDialogs[module] == true;

Future<void> showAccountLoginDialog(
  BuildContext context,
  AccountModule module, {
  InteractionSource? source,
}) async {
  if (_openDialogs[module] == true || !module.projection.value.canLogin) return;
  _openDialogs[module] = true;
  try {
    final openingSource =
        source ?? StarBridgeActivationOrigin.sourceOf(context);
    late StarBridgeDialogRoute<void> owned;
    await showStarBridgeDialog<void>(
      context,
      source: openingSource,
      barrierDismissible: false,
      onRouteCreated: (route) => owned = route,
      builder: (_) =>
          _LoginDialog(module: module, route: owned, source: openingSource),
    );
  } finally {
    _openDialogs[module] = null;
  }
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({
    required this.module,
    required this.route,
    required this.source,
  });
  final AccountModule module;
  final StarBridgeDialogRoute<void> route;
  final InteractionSource source;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

// Stage 2 waits for the details the account page shows after sign-in; it
// never holds the user longer than this (the page keeps reading afterwards).
const accountLoginDetailsLimit = Duration(seconds: 20);

class _LoginDialogState extends State<_LoginDialog> {
  // Three stages (user request 2026-10-22): authorize, load details, done.
  bool _authorized = false;
  bool _success = false;
  bool _closing = false;
  void Function()? _releaseReads;
  Timer? _loadingPoll, _loadingLimit;
  late InteractionSource _motionSource = widget.source;

  @override
  void initState() {
    super.initState();
    widget.module.projection.addListener(_changed);
    // Start only after the dialog is mounted, never on page entry.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) {
        unawaited(
          runAccountMotionCommand(
            widget.module,
            AccountOperation.signingIn,
            _motionSource,
            widget.module.beginLogin,
          ),
        );
      }
    });
  }

  void _changed() {
    final succeeded = widget.module.takeLoginSuccessFeedback();
    if (succeeded && !_authorized && mounted) {
      // Read the staged details now, as the account page would.
      _releaseReads = widget.module.holdVisibleReads();
      _loadingLimit = Timer(accountLoginDetailsLimit, _detailsLoaded);
      _loadingPoll = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => _checkDetails(),
      );
      _authorized = true;
    }
    // Every projection change rebuilds the dialog (waiting, cancelling, ...).
    if (mounted) setState(() {});
    _checkDetails();
  }

  void _checkDetails() {
    if (_authorized && !_success && widget.module.signedInDetailsSettled) {
      _detailsLoaded();
    }
  }

  void _detailsLoaded() {
    _loadingPoll?.cancel();
    _loadingLimit?.cancel();
    if (mounted && !_success) setState(() => _success = true);
  }

  Future<void> _close([
    InteractionSource source = InteractionSource.keyboard,
  ]) async {
    if (!mounted || _closing || !widget.route.isActive) return;
    setState(() {
      _closing = true;
      _motionSource = source;
    });
    if (widget.module.projection.value.operation ==
        AccountOperation.signingIn) {
      final result = await runAccountMotionCommand(
        widget.module,
        AccountOperation.cancellingLogin,
        source,
        widget.module.cancelLogin,
      );
      if (result.outcome != AccountActionOutcome.completed &&
          result.outcome != AccountActionOutcome.cancelled) {
        if (mounted) setState(() => _closing = false);
        return;
      }
    }
    if (!mounted) return;
    if (widget.module.projection.value.operation ==
        AccountOperation.cancellingLogin) {
      setState(() => _closing = false);
      return;
    }
    if (widget.route.isCurrent) {
      dismissStarBridgeDialog(context, source: source);
    } else {
      retireStarBridgeDialog(widget.route);
    }
  }

  @override
  void dispose() {
    _loadingPoll?.cancel();
    _loadingLimit?.cancel();
    _releaseReads?.call();
    widget.module.projection.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final state = widget.module.projection.value;
    final waiting = state.operation == AccountOperation.signingIn;
    final cancelling = state.operation == AccountOperation.cancellingLogin;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              unawaited(_close()),
        },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            key: const Key('account-login-dialog'),
            title: Text(strings.text('account.login.action')),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LoginStages(
                      stage: _success
                          ? 2
                          : _authorized
                          ? 1
                          : 0,
                    ),
                    const SizedBox(height: 16),
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        disableAnimations:
                            MediaQuery.disableAnimationsOf(context) ||
                            InteractionScope.of(context).reduceMotion ||
                            _motionSource == InteractionSource.keyboard,
                      ),
                      child: ScmSuccessMotion(
                        key: const Key('account-login-motion'),
                        play: _success,
                        loading:
                            !_success && (waiting || cancelling || _authorized),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      strings.text(
                        _success
                            ? 'account.login.success'
                            : _authorized
                            ? 'account.login.loading'
                            : cancelling
                            ? 'account.login.cancelling'
                            : state.failure?.messageKey ??
                                  (waiting
                                      ? 'account.login.waiting'
                                      : 'account.signedOut.body'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (!_success && !_authorized && !waiting && !cancelling)
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.primary,
                  controlKey: const Key('account-login-retry'),
                  onActivate: state.canLogin && !_closing
                      ? (source) {
                          if (!mounted ||
                              _closing ||
                              !widget.route.isCurrent ||
                              !widget.module.projection.value.canLogin) {
                            return;
                          }
                          setState(() => _motionSource = source);
                          unawaited(
                            runAccountMotionCommand(
                              widget.module,
                              AccountOperation.signingIn,
                              source,
                              widget.module.beginLogin,
                            ),
                          );
                        }
                      : null,
                  child: Text(strings.text('account.action.retry')),
                ),
              StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('account-cancel-login'),
                onActivate: _closing || cancelling ? null : _close,
                child: Text(
                  _success || !waiting
                      ? MaterialLocalizations.of(context).closeButtonLabel
                      : strings.text('account.login.cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Authorize · load details · signed in. Done steps carry a check.
class _LoginStages extends StatelessWidget {
  const _LoginStages({required this.stage});
  final int stage;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = context.tokens.colors;
    final style = Theme.of(context).textTheme.labelMedium;
    return Row(
      key: const Key('account-login-stages'),
      children: [
        for (final (i, key) in const [
          'account.login.stage.authorize',
          'account.login.stage.loading',
          'account.login.stage.done',
        ].indexed) ...[
          if (i > 0)
            Expanded(
              child: Divider(
                indent: 6,
                endIndent: 6,
                color: i <= stage ? colors.stateAccent : colors.textDisabled,
              ),
            ),
          Text(
            '${i < stage || stage == 2 ? '✓' : '${i + 1}'} ${strings.text(key)}',
            style: style?.copyWith(
              color: i < stage || stage == 2
                  ? colors.success
                  : i == stage
                  ? colors.stateAccent
                  : colors.textDisabled,
              fontWeight: i == stage ? FontWeight.w600 : null,
            ),
          ),
        ],
      ],
    );
  }
}
