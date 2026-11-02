import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'password_recovery.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_dialog_owner.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

final _recoveryDialogs = Expando<StarBridgeDialogRoute<void>>();

Future<void> showPasswordRecoveryDialog(
  BuildContext context,
  PasswordRecoveryPort port, {
  InteractionSource? source,
  bool Function()? isCurrent,
  Listenable? ownerChanges,
}) async {
  if (!context.mounted ||
      !port.supportsPasswordRecovery ||
      _recoveryDialogs[port] != null) {
    return;
  }
  final opening = source ?? StarBridgeActivationOrigin.sourceOf(context);
  bool current() =>
      context.mounted &&
      port.supportsPasswordRecovery &&
      (isCurrent?.call() ?? true);
  Future<void>? cleanupFuture;
  Future<void> cleanup() => cleanupFuture ??= () async {
    try {
      await port.cancelPasswordRecovery();
    } catch (_) {
      /* Cleanup cannot manufacture a recovery result. */
    }
  }();
  StarBridgeDialogRoute<void>? owned;
  try {
    await showStarBridgeDialog<void>(
      context,
      source: opening,
      barrierDismissible: false,
      onRouteCreated: (route) {
        owned = route;
        _recoveryDialogs[port] = route;
      },
      builder: (_) {
        Widget editor() => PasswordRecoveryDialog(
          key: ObjectKey(port),
          port: port,
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
    if (identical(_recoveryDialogs[port], owned)) _recoveryDialogs[port] = null;
  }
}

class PasswordRecoveryDialog extends StatefulWidget {
  const PasswordRecoveryDialog({
    required this.port,
    this.source = InteractionSource.pointer,
    this.isCurrent,
    this.cleanup,
    super.key,
  });
  final PasswordRecoveryPort port;
  final InteractionSource source;
  final bool Function()? isCurrent;
  final Future<void> Function()? cleanup;
  @override
  State<PasswordRecoveryDialog> createState() => _PasswordRecoveryDialogState();
}

class _PasswordRecoveryDialogState extends State<PasswordRecoveryDialog> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  Timer? _timer;
  DateTime? _nextSend;
  int _remaining = 0;
  bool _busy = false;
  bool _throttled = false;
  String? _outcome;
  bool _closed = false;
  int _requestRevision = 0;
  late InteractionSource _source = widget.source;
  Future<void>? _cleanupFuture;

  Future<void> _cleanup() => _cleanupFuture ??=
      (widget.cleanup?.call() ??
      () async {
        try {
          await widget.port.cancelPasswordRecovery();
        } catch (_) {}
      }());

  bool get _current =>
      mounted &&
      !_closed &&
      widget.port.supportsPasswordRecovery &&
      (widget.isCurrent?.call() ?? true);

  @override
  void dispose() {
    _timer?.cancel();
    _closed = true;
    _requestRevision++;
    unawaited(_cleanup());
    for (final controller in [_email, _code, _password, _confirm]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  bool _validEmail() =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim()) &&
      _email.text.trim().length <= 320;
  Future<void> _execute(bool confirm, InteractionSource source) async {
    if (!_current ||
        ModalRoute.of(context)?.isCurrent != true ||
        _busy ||
        (_remaining > 0 && (!confirm || _throttled))) {
      return;
    }
    String? invalid;
    if (!_validEmail()) {
      invalid = 'invalidEmail';
    } else if (confirm && !RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      invalid = 'invalidCode';
    } else if (confirm &&
        (_password.text.length < 8 || _password.text.length > 128)) {
      invalid = 'invalidPassword';
    } else if (confirm && _password.text != _confirm.text) {
      invalid = 'mismatch';
    }
    if (invalid != null) {
      setState(() => _outcome = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _source = source;
      _outcome = null;
    });
    final owner = widget.port, revision = ++_requestRevision;
    PasswordRecoveryResult result;
    try {
      result = confirm
          ? await owner.confirmPasswordReset(
              _email.text,
              _code.text,
              _password.text,
            )
          : await owner.sendPasswordResetCode(_email.text);
    } catch (_) {
      result = const PasswordRecoveryResult('unavailable');
    }
    if (!_current ||
        revision != _requestRevision ||
        !identical(widget.port, owner)) {
      return;
    }
    setState(() {
      _busy = false;
      _outcome = result.outcome;
      if (confirm) {
        _password.clear();
        _confirm.clear();
      }
      if (result.outcome == 'reset') _code.clear();
    });
    if (result.retryAfterSeconds > 0) {
      _throttled = result.outcome == 'throttled';
      _nextSend = DateTime.now().add(
        Duration(seconds: result.retryAfterSeconds),
      );
      _timer?.cancel();
      void tick() {
        if (!mounted) return;
        final remaining =
            (_nextSend!.difference(DateTime.now()).inMilliseconds / 1000)
                .ceil()
                .clamp(0, 3600);
        setState(() => _remaining = remaining);
        if (remaining == 0) _timer?.cancel();
      }

      tick();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    }
  }

  void _close(InteractionSource source) {
    if (!mounted || _closed || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _closed = true;
    _requestRevision++;
    _timer?.cancel();
    for (final controller in [_email, _code, _password, _confirm]) {
      controller.clear();
    }
    unawaited(_cleanup());
    dismissStarBridgeDialog<void>(context, source: source);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    String text(String key) => strings.text('account.recovery.$key');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(InteractionSource.keyboard);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _close(InteractionSource.keyboard),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: StarBridgeSurface(
                role: SurfaceRole.floating,
                child: SingleChildScrollView(
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
                        enabled: !_busy && _current,
                        error: _outcome == 'invalidEmail',
                        builder: (_, focus) => TextField(
                          key: const Key('recovery-email'),
                          controller: _email,
                          focusNode: focus,
                          enabled: !_busy,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: InputDecoration(labelText: text('email')),
                        ),
                      ),
                      SizedBox(height: tokens.space.sm),
                      StarBridgeActionButton(
                        controlKey: const Key('recovery-send'),
                        onActivate: !_current || _busy || _remaining > 0
                            ? null
                            : (source) => unawaited(_execute(false, source)),
                        child: Text(
                          _remaining > 0
                              ? '${text('resend')} · ${_remaining}s'
                              : text('send'),
                        ),
                      ),
                      SizedBox(height: tokens.space.sm),
                      StarBridgeFieldFrame(
                        enabled: !_busy && _current,
                        error: _outcome == 'invalidCode',
                        builder: (_, focus) => TextField(
                          key: const Key('recovery-code'),
                          controller: _code,
                          focusNode: focus,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: InputDecoration(labelText: text('code')),
                        ),
                      ),
                      SizedBox(height: tokens.space.sm),
                      StarBridgeFieldFrame(
                        enabled: !_busy && _current,
                        error:
                            _outcome == 'invalidPassword' ||
                            _outcome == 'commonPassword',
                        builder: (_, focus) => TextField(
                          key: const Key('recovery-password'),
                          controller: _password,
                          focusNode: focus,
                          enabled: !_busy,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: text('password'),
                            helperText: text('passwordHint'),
                          ),
                        ),
                      ),
                      SizedBox(height: tokens.space.sm),
                      StarBridgeFieldFrame(
                        enabled: !_busy && _current,
                        error: _outcome == 'mismatch',
                        builder: (_, focus) => TextField(
                          key: const Key('recovery-confirm-password'),
                          controller: _confirm,
                          focusNode: focus,
                          enabled: !_busy,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: text('confirmPassword'),
                          ),
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
                          key: const Key('recovery-result'),
                          style: TextStyle(
                            color:
                                _outcome == 'reset' ||
                                    _outcome == 'codeRequested'
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
                            controlKey: const Key('recovery-close'),
                            onActivate: _closed ? null : _close,
                            child: Text(text('close')),
                          ),
                          StarBridgeActionButton(
                            kind: StarBridgeActionKind.primary,
                            controlKey: const Key('recovery-submit'),
                            onActivate:
                                !_current ||
                                    _busy ||
                                    (_throttled && _remaining > 0)
                                ? null
                                : (source) => unawaited(_execute(true, source)),
                            child: Text(text('submit')),
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
      ),
    );
  }
}
