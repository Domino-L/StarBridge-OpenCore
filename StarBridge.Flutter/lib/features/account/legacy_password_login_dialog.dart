import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'legacy_password_login.dart';
import 'password_recovery.dart';
import 'password_recovery_dialog.dart';

Future<void> showLegacyPasswordLoginDialog(
  BuildContext context,
  LegacyPasswordLoginPort port, {
  PasswordRecoveryPort? recovery,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => LegacyPasswordLoginDialog(port: port, recovery: recovery),
);

class LegacyPasswordLoginDialog extends StatefulWidget {
  const LegacyPasswordLoginDialog({
    required this.port,
    this.recovery,
    super.key,
  });
  final LegacyPasswordLoginPort port;
  final PasswordRecoveryPort? recovery;
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
  @override
  void dispose() {
    unawaited(widget.port.cancelLegacyPasswordLogin());
    _timer?.cancel();
    _email.clear();
    _email.dispose();
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy || _remaining > 0 || _outcome == 'verified') return;
    if (_email.text.trim().isEmpty ||
        _email.text.trim().length > 320 ||
        _password.text.trim().isEmpty ||
        _password.text.length > 1024) {
      setState(() => _outcome = 'invalidInput');
      return;
    }
    setState(() {
      _busy = true;
      _outcome = null;
    });
    LegacyPasswordLoginResult result;
    try {
      result = await widget.port.loginLegacy(_email.text, _password.text);
    } catch (_) {
      result = const LegacyPasswordLoginResult('unavailable');
    }
    if (!mounted) return;
    _password.clear();
    if (result.outcome == 'verified') {
      Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String text(String key) => strings.text('account.legacyLogin.$key');
    final tokens = context.tokens;
    final verified = _outcome == 'verified';
    return Dialog(
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
              TextField(
                key: const Key('legacy-login-email'),
                controller: _email,
                enabled: !_busy && !verified,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: strings.text('account.recovery.email'),
                ),
              ),
              SizedBox(height: tokens.space.sm),
              TextField(
                key: const Key('legacy-login-password'),
                controller: _password,
                enabled: !_busy && !verified,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => unawaited(_login()),
                decoration: InputDecoration(labelText: text('password')),
              ),
              if (widget.recovery case final recovery?)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: _busy || verified
                        ? null
                        : () => unawaited(
                            showPasswordRecoveryDialog(context, recovery),
                          ),
                    child: Text(strings.text('account.recovery.title')),
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
                  TextButton(
                    key: const Key('legacy-login-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.text('account.recovery.close')),
                  ),
                  TextButton(
                    key: const Key('legacy-login-skip'),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(text('skip')),
                  ),
                  if (!verified)
                    FilledButton(
                      key: const Key('legacy-login-submit'),
                      onPressed: _busy || _remaining > 0
                          ? null
                          : () => unawaited(_login()),
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
    );
  }
}
