import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'legacy_password_login.dart';
import 'password_recovery.dart';
import 'password_recovery_dialog.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_dialog_owner.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

final _loginDialogs = Expando<StarBridgeDialogRoute<void>>();

Future<void> showLegacyPasswordLoginDialog(
  BuildContext context,
  LegacyPasswordLoginPort port, {
  PasswordRecoveryPort? recovery,
  InteractionSource? source,
  bool Function()? isCurrent,
  Listenable? ownerChanges,
}) async {
  if (!context.mounted ||
      !port.supportsLegacyPasswordLogin ||
      _loginDialogs[port] != null) {
    return;
  }
  final opening = source ?? StarBridgeActivationOrigin.sourceOf(context);
  bool current() =>
      context.mounted &&
      port.supportsLegacyPasswordLogin &&
      (isCurrent?.call() ?? true);
  Future<void>? cleanupFuture;
  Future<void> cleanup() => cleanupFuture ??= () async {
    try {
      await port.cancelLegacyPasswordLogin();
    } catch (_) {}
  }();
  StarBridgeDialogRoute<void>? owned;
  try {
    await showStarBridgeDialog<void>(
      context,
      source: opening,
      barrierDismissible: false,
      onRouteCreated: (route) {
        owned = route;
        _loginDialogs[port] = route;
      },
      builder: (_) {
        Widget editor() => LegacyPasswordLoginDialog(
          key: ObjectKey(port),
          port: port,
          recovery: recovery,
          source: opening,
          isCurrent: current,
          cleanup: cleanup,
        );
        return StarBridgeDialogOwnerGuard(
          isCurrent: current,
          child: ownerChanges == null
              ? editor()
              : AnimatedBuilder(
                  animation: ownerChanges,
                  builder: (_, _) => editor(),
                ),
        );
      },
    );
    await owned?.completed;
    await cleanup();
  } finally {
    if (identical(_loginDialogs[port], owned)) _loginDialogs[port] = null;
  }
}

class LegacyPasswordLoginDialog extends StatefulWidget {
  const LegacyPasswordLoginDialog({
    required this.port,
    this.recovery,
    this.source = InteractionSource.pointer,
    this.isCurrent,
    this.cleanup,
    super.key,
  });
  final LegacyPasswordLoginPort port;
  final PasswordRecoveryPort? recovery;
  final InteractionSource source;
  final bool Function()? isCurrent;
  final Future<void> Function()? cleanup;
  @override
  State<LegacyPasswordLoginDialog> createState() =>
      _LegacyPasswordLoginDialogState();
}

class _LegacyPasswordLoginDialogState extends State<LegacyPasswordLoginDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _outcome;
  Timer? _timer;
  DateTime? _retryAt;
  int _remaining = 0;
  bool _closed = false;
  int _revision = 0;
  late InteractionSource _source = widget.source;
  Future<void>? _cleanupFuture;
  Future<void> _cleanup() => _cleanupFuture ??=
      (widget.cleanup?.call() ??
      () async {
        try {
          await widget.port.cancelLegacyPasswordLogin();
        } catch (_) {}
      }());
  bool get _current =>
      mounted &&
      !_closed &&
      widget.port.supportsLegacyPasswordLogin &&
      (widget.isCurrent?.call() ?? true);
  @override
  void dispose() {
    _closed = true;
    _revision++;
    unawaited(_cleanup());
    _timer?.cancel();
    _email.clear();
    _email.dispose();
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login(InteractionSource source) async {
    if (!_current ||
        ModalRoute.of(context)?.isCurrent != true ||
        _busy ||
        _remaining > 0 ||
        _outcome == 'verified') {
      return;
    }
    if (_email.text.trim().isEmpty ||
        _email.text.trim().length > 320 ||
        _password.text.trim().isEmpty ||
        _password.text.length > 1024) {
      setState(() => _outcome = 'invalidInput');
      return;
    }
    setState(() {
      _busy = true;
      _source = source;
      _outcome = null;
    });
    LegacyPasswordLoginResult result;
    final owner = widget.port, request = ++_revision;
    try {
      result = await owner.loginLegacy(_email.text, _password.text);
    } catch (_) {
      result = const LegacyPasswordLoginResult('unavailable');
    }
    if (!_current || request != _revision || !identical(owner, widget.port)) {
      return;
    }
    _password.clear();
    if (result.outcome == 'verified') {
      _finish(source, verified: true);
      return;
    }
    setState(() {
      _busy = false;
      _outcome = result.outcome;
    });
    if (result.outcome == 'throttled') {
      _remaining = result.retryAfterSeconds.clamp(1, 3600);
      _retryAt = DateTime.now().add(Duration(seconds: _remaining));
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(
          () => _remaining =
              ((_retryAt!.difference(DateTime.now()).inMilliseconds / 1000)
                      .ceil())
                  .clamp(0, 3600),
        );
        if (_remaining == 0) _timer?.cancel();
      });
    }
  }

  void _finish(InteractionSource source, {bool verified = false}) {
    if (!mounted || _closed) return;
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true && !verified) return;
    _closed = true;
    _revision++;
    _timer?.cancel();
    _email.clear();
    _password.clear();
    unawaited(_cleanup());
    if (route?.isCurrent == true) {
      dismissStarBridgeDialog<void>(context, source: source);
    } else if (route is StarBridgeDialogRoute) {
      retireStarBridgeDialog(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String text(String key) => strings.text('account.legacyLogin.$key');
    final tokens = context.tokens;
    final verified = _outcome == 'verified';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(InteractionSource.keyboard);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _finish(InteractionSource.keyboard),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(tokens.space.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      text('title'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    SizedBox(height: tokens.space.sm),
                    Text(text('body')),
                    SizedBox(height: tokens.space.md),
                    StarBridgeFieldFrame(
                      enabled: _current && !_busy && !verified,
                      error:
                          _outcome == 'invalidInput' &&
                          _email.text.trim().isEmpty,
                      builder: (_, focus) => TextField(
                        key: const Key('legacy-login-email'),
                        controller: _email,
                        focusNode: focus,
                        enabled: !_busy && !verified,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: strings.text('account.recovery.email'),
                        ),
                      ),
                    ),
                    SizedBox(height: tokens.space.sm),
                    StarBridgeFieldFrame(
                      enabled: _current && !_busy && !verified,
                      error:
                          _outcome == 'invalidInput' &&
                          _password.text.trim().isEmpty,
                      builder: (_, focus) => TextField(
                        key: const Key('legacy-login-password'),
                        controller: _password,
                        focusNode: focus,
                        enabled: !_busy && !verified,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        onSubmitted: (_) =>
                            unawaited(_login(InteractionSource.keyboard)),
                        decoration: InputDecoration(
                          labelText: text('password'),
                        ),
                      ),
                    ),
                    if (widget.recovery case final recovery?)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: StarBridgeActionButton(
                          kind: StarBridgeActionKind.quiet,
                          controlKey: const Key('legacy-login-recovery'),
                          onActivate: !_current || _busy || verified
                              ? null
                              : (source) {
                                  bool current() =>
                                      _current &&
                                      identical(widget.recovery, recovery);
                                  if (!current() || _busy) return;
                                  unawaited(
                                    showPasswordRecoveryDialog(
                                      context,
                                      recovery,
                                      source: source,
                                      isCurrent: current,
                                    ),
                                  );
                                },
                          child: Text(strings.text('account.recovery.title')),
                        ),
                      ),
                    if (_busy) ...[
                      SizedBox(height: tokens.space.md),
                      StarBridgeInteractionRegion(
                        child: Builder(
                          builder: (context) {
                            final data = InteractionScope.of(context);
                            return InteractionScope(
                              data: data.copyWith(
                                reduceMotion:
                                    data.reduceMotion ||
                                    _source == InteractionSource.keyboard ||
                                    _closed,
                              ),
                              child: const SuiteProgressBar(
                                value: null,
                                phase: ProgressPhase.running,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (_outcome != null) ...[
                      SizedBox(height: tokens.space.md),
                      Text(
                        text(_outcome!),
                        key: const Key('legacy-login-result'),
                        style: TextStyle(
                          color: verified
                              ? tokens.colors.success
                              : tokens.colors.warning,
                        ),
                      ),
                    ],
                    SizedBox(height: tokens.space.md),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: tokens.space.sm,
                      children: [
                        StarBridgeActionButton(
                          kind: StarBridgeActionKind.quiet,
                          controlKey: const Key('legacy-login-close'),
                          onActivate: _closed ? null : _finish,
                          child: Text(strings.text('account.recovery.close')),
                        ),
                        StarBridgeActionButton(
                          kind: StarBridgeActionKind.quiet,
                          controlKey: const Key('legacy-login-skip'),
                          onActivate: !_current || _busy ? null : _finish,
                          child: Text(text('skip')),
                        ),
                        if (!verified)
                          StarBridgeActionButton(
                            kind: StarBridgeActionKind.primary,
                            controlKey: const Key('legacy-login-submit'),
                            onActivate: !_current || _busy || _remaining > 0
                                ? null
                                : (source) => unawaited(_login(source)),
                            child: Text(
                              _remaining > 0
                                  ? '${text('retry')} · ${_remaining}s'
                                  : text('submit'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
