import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'password_recovery.dart';

Future<void> showPasswordRecoveryDialog(
  BuildContext context,
  PasswordRecoveryPort port,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => PasswordRecoveryDialog(port: port),
);

class PasswordRecoveryDialog extends StatefulWidget {
  const PasswordRecoveryDialog({required this.port, super.key});
  final PasswordRecoveryPort port;
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

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(widget.port.cancelPasswordRecovery());
    for (final controller in [_email, _code, _password, _confirm]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  bool _validEmail() =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim()) &&
      _email.text.trim().length <= 320;
  Future<void> _execute(bool confirm) async {
    if (_busy || (_remaining > 0 && (!confirm || _throttled))) return;
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
      _outcome = null;
    });
    PasswordRecoveryResult result;
    try {
      result = confirm
          ? await widget.port.confirmPasswordReset(
              _email.text,
              _code.text,
              _password.text,
            )
          : await widget.port.sendPasswordResetCode(_email.text);
    } catch (_) {
      result = const PasswordRecoveryResult('unavailable');
    }
    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    String text(String key) => strings.text('account.recovery.$key');
    return Dialog(
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
                TextField(
                  key: const Key('recovery-email'),
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: text('email')),
                ),
                SizedBox(height: tokens.space.sm),
                OutlinedButton(
                  key: const Key('recovery-send'),
                  onPressed: _busy || _remaining > 0
                      ? null
                      : () => unawaited(_execute(false)),
                  child: Text(
                    _remaining > 0
                        ? '${text('resend')} · ${_remaining}s'
                        : text('send'),
                  ),
                ),
                SizedBox(height: tokens.space.sm),
                TextField(
                  key: const Key('recovery-code'),
                  controller: _code,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(labelText: text('code')),
                ),
                SizedBox(height: tokens.space.sm),
                TextField(
                  key: const Key('recovery-password'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: text('password'),
                    helperText: text('passwordHint'),
                  ),
                ),
                SizedBox(height: tokens.space.sm),
                TextField(
                  key: const Key('recovery-confirm-password'),
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: text('confirmPassword'),
                  ),
                ),
                if (_busy) ...[
                  SizedBox(height: tokens.space.md),
                  const LinearProgressIndicator(),
                ],
                if (_outcome != null) ...[
                  SizedBox(height: tokens.space.md),
                  Text(
                    text(_outcome!),
                    key: const Key('recovery-result'),
                    style: TextStyle(
                      color: _outcome == 'reset' || _outcome == 'codeRequested'
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
                    TextButton(
                      key: const Key('recovery-close'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(text('close')),
                    ),
                    FilledButton(
                      key: const Key('recovery-submit'),
                      onPressed: _busy || (_throttled && _remaining > 0)
                          ? null
                          : () => unawaited(_execute(true)),
                      child: Text(text('submit')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
