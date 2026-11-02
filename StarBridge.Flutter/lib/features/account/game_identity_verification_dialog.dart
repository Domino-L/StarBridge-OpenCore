import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_dialog_owner.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'game_identity_verification.dart';

final _dialogs = Expando<StarBridgeDialogRoute<void>>();

/// The one verification panel, shared by account settings and first use.
/// [onVerified] runs once SCM accepted, or reported the account already verified.
Future<void> showGameIdentityVerificationDialog(
  BuildContext context,
  GameIdentityVerificationPort port, {
  String? initialHandle,
  VoidCallback? onVerified,
  InteractionSource? source,
  bool Function()? isCurrent,
  Listenable? ownerChanges,
}) async {
  if (!context.mounted ||
      !port.supportsGameIdentityVerification ||
      _dialogs[port] != null) {
    return;
  }
  // Capabilities are refreshed around every account event; only the owner
  // decides whether an open panel stays. The Host rejects a stale request.
  bool current() => context.mounted && (isCurrent?.call() ?? true);
  StarBridgeDialogRoute<void>? owned;
  try {
    await showStarBridgeDialog<void>(
      context,
      source: source ?? StarBridgeActivationOrigin.sourceOf(context),
      barrierDismissible: false,
      onRouteCreated: (route) {
        owned = route;
        _dialogs[port] = route;
      },
      builder: (_) {
        Widget panel() => GameIdentityVerificationPanel(
          key: ObjectKey(port),
          port: port,
          initialHandle: initialHandle,
          onVerified: onVerified,
          isCurrent: current,
        );
        return StarBridgeDialogOwnerGuard(
          isCurrent: current,
          child: ownerChanges == null
              ? panel()
              : AnimatedBuilder(
                  animation: ownerChanges,
                  builder: (_, _) => panel(),
                ),
        );
      },
    );
    await owned?.completed;
  } finally {
    if (identical(_dialogs[port], owned)) _dialogs[port] = null;
  }
}

enum _Tone { plain, success, problem }

class GameIdentityVerificationPanel extends StatefulWidget {
  const GameIdentityVerificationPanel({
    required this.port,
    this.initialHandle,
    this.onVerified,
    this.isCurrent,
    super.key,
  });
  final GameIdentityVerificationPort port;
  final String? initialHandle;
  final VoidCallback? onVerified;
  final bool Function()? isCurrent;
  @override
  State<GameIdentityVerificationPanel> createState() =>
      _GameIdentityVerificationPanelState();
}

class _GameIdentityVerificationPanelState
    extends State<GameIdentityVerificationPanel> {
  late final _handle = TextEditingController(text: widget.initialHandle ?? '');
  final _contact = TextEditingController();
  Timer? _timer;
  DateTime? _expiresAt;
  int _remaining = 0;
  String? _code;
  bool _busy = false;
  bool _closed = false;
  int _revision = 0;
  String? _notice;
  _Tone _tone = _Tone.plain;

  late final StreamSubscription<void> _support;
  bool get _supported => widget.port.supportsGameIdentityVerification;
  bool get _submitStep => _code != null;
  bool get _expired => _submitStep && _remaining == 0;
  bool get _current =>
      mounted && !_closed && (widget.isCurrent?.call() ?? true);

  // The first-use guide has its own copy and may not install AppStrings.
  String _text(String key) =>
      (Localizations.of<AppStrings>(context, AppStrings) ??
              AppStrings.resolve(Localizations.localeOf(context)))
          .text('account.gameIdentity.$key');

  @override
  void initState() {
    super.initState();
    widget.port.beginFlow();
    _support = widget.port.supportChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _forgetCode() {
    _code = null;
    _expiresAt = null;
    _remaining = 0;
  }

  @override
  void dispose() {
    unawaited(_support.cancel());
    _timer?.cancel();
    _closed = true;
    _revision++;
    _forgetCode();
    _contact.clear();
    _handle.dispose();
    _contact.dispose();
    super.dispose();
  }

  void _say(String? notice, [_Tone tone = _Tone.plain]) => setState(() {
    _notice = notice;
    _tone = tone;
  });

  void _tick() {
    if (!mounted || _expiresAt == null) return;
    final left = (_expiresAt!.difference(DateTime.now()).inMilliseconds / 1000)
        .ceil()
        .clamp(0, 86400);
    setState(() {
      _remaining = left;
      if (left == 0) {
        _notice = _text('expired');
        _tone = _Tone.problem;
      }
    });
    if (left == 0) _timer?.cancel();
  }

  Future<void> _copy({required bool announce}) async {
    final code = _code;
    if (code == null) return;
    var copied = true;
    try {
      await Clipboard.setData(ClipboardData(text: code));
    } catch (_) {
      copied = false;
    }
    if (!_current) return;
    if (announce || !copied) {
      _say(
        _text(copied ? 'copied' : 'copyFailed'),
        copied ? _Tone.success : _Tone.problem,
      );
    }
  }

  void _showFailure(GameIdentityResult result) {
    final key = switch (result.outcome) {
      GameIdentityOutcome.rejected => 'rejected',
      GameIdentityOutcome.reauthorizationRequired => 'reauthorize',
      GameIdentityOutcome.outcomeUnknown => 'outcomeUnknown',
      _ => 'unavailable',
    };
    final message = result.message?.trim();
    _say(
      message == null || message.isEmpty ? _text(key) : message,
      _Tone.problem,
    );
  }

  void _finishVerified() {
    if (!_current) return;
    widget.onVerified?.call();
    _close(InteractionSource.pointer);
  }

  Future<void> _requestCode() async {
    if (!_current || _busy) return;
    if (!isValidGameIdentityHandle(_handle.text)) {
      _say(_text('invalidHandle'), _Tone.problem);
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    final revision = ++_revision;
    GameIdentityResult result;
    try {
      result = await widget.port.requestVerificationCode(_handle.text);
    } catch (_) {
      result = const GameIdentityResult(GameIdentityOutcome.unavailable);
    }
    if (!_current || revision != _revision) return;
    setState(() => _busy = false);
    switch (result.outcome) {
      case GameIdentityOutcome.issued:
        setState(() {
          _code = result.verificationCode;
          _expiresAt = DateTime.now().add(
            Duration(seconds: result.expiresInSeconds),
          );
        });
        _timer?.cancel();
        _tick();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
        _say(_text('codeCopied'), _Tone.success);
        await _copy(announce: false);
      case GameIdentityOutcome.alreadyVerified:
        _finishVerified();
      default:
        _showFailure(result);
    }
  }

  Future<void> _submit() async {
    if (!_current || _busy || _expired) return;
    if (!isValidGameIdentityContact(_contact.text)) {
      _say(_text('invalidContact'), _Tone.problem);
      return;
    }
    setState(() {
      _busy = true;
      _notice = _text('checking');
      _tone = _Tone.plain;
    });
    final revision = ++_revision;
    GameIdentityResult result;
    try {
      result = await widget.port.submitVerification(
        _handle.text,
        _contact.text,
      );
    } catch (_) {
      result = const GameIdentityResult(GameIdentityOutcome.outcomeUnknown);
    }
    if (!_current || revision != _revision) return;
    setState(() => _busy = false);
    switch (result.outcome) {
      case GameIdentityOutcome.verified:
      case GameIdentityOutcome.alreadyVerified:
        _finishVerified();
      default:
        _showFailure(result);
    }
  }

  void _back() {
    if (_busy) return;
    _timer?.cancel();
    setState(() {
      _forgetCode();
      _notice = null;
    });
  }

  void _close(InteractionSource source) {
    if (!mounted || _closed || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _closed = true;
    _revision++;
    _timer?.cancel();
    _forgetCode();
    _contact.clear();
    dismissStarBridgeDialog<void>(context, source: source);
  }

  Widget _stepMark(String key, {required bool active, required bool done}) {
    final tokens = context.tokens;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: done
                  ? tokens.colors.success
                  : active
                  ? tokens.colors.accent
                  : tokens.surfaces.panel.border,
            ),
          ),
        ),
        child: Text(
          _text(key),
          style: TextStyle(
            fontSize: 13,
            color: active || done
                ? tokens.colors.textPrimary
                : tokens.colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _help(String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: context.tokens.colors.textSecondary,
      ),
    ),
  );

  List<Widget> _handleStep() => [
    StarBridgeFieldFrame(
      enabled: !_busy && _current,
      error: false,
      builder: (_, focus) => TextField(
        key: const Key('game-identity-handle'),
        controller: _handle,
        focusNode: focus,
        enabled: !_busy,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: [LengthLimitingTextInputFormatter(64)],
        decoration: InputDecoration(labelText: _text('handle')),
        onSubmitted: (_) => unawaited(_requestCode()),
      ),
    ),
    _help(
      _text(
        widget.initialHandle == null || widget.initialHandle!.isEmpty
            ? 'handleHelp'
            : 'handleHelpDetected',
      ),
    ),
  ];

  List<Widget> _submitPanel() {
    final tokens = context.tokens;
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border.all(color: tokens.surfaces.panel.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(
                _code!,
                key: const Key('game-identity-code'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            StarBridgeActionButton(
              controlKey: const Key('game-identity-copy'),
              onActivate: (_) => unawaited(_copy(announce: true)),
              child: Text(_text('copy')),
            ),
          ],
        ),
      ),
      SizedBox(height: tokens.space.xs),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: tokens.space.sm,
        children: [
          Text(
            _expired
                ? _text('expiredShort')
                : _text('remaining')
                      .replaceAll('{minutes}', '${_remaining ~/ 60}')
                      .replaceAll(
                        '{seconds}',
                        (_remaining % 60).toString().padLeft(2, '0'),
                      ),
            key: const Key('game-identity-remaining'),
            style: TextStyle(
              fontSize: 12,
              color: _expired
                  ? tokens.colors.warning
                  : tokens.colors.textSecondary,
            ),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('game-identity-open-rsi'),
            onActivate: (_) async {
              final opened = await widget.port.openRsiProfile();
              if (_current && !opened) {
                _say(_text('openFailed'), _Tone.problem);
              }
            },
            child: Text(_text('openRsi')),
          ),
        ],
      ),
      SizedBox(height: tokens.space.xs),
      Text(_text('instructions')),
      SizedBox(height: tokens.space.md),
      StarBridgeFieldFrame(
        enabled: !_busy && _current && !_expired,
        error: false,
        builder: (_, focus) => TextField(
          key: const Key('game-identity-contact'),
          controller: _contact,
          focusNode: focus,
          enabled: !_busy && !_expired,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [LengthLimitingTextInputFormatter(256)],
          decoration: InputDecoration(
            labelText: _text('contact'),
            hintText: _text('contactHint'),
          ),
          onSubmitted: (_) => unawaited(_submit()),
        ),
      ),
      _help(_text('contactHelp')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
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
                    key: const Key('game-identity-panel'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _text('title'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      SizedBox(height: tokens.space.xs),
                      Text(
                        _text('body'),
                        style: TextStyle(color: tokens.colors.textSecondary),
                      ),
                      SizedBox(height: tokens.space.md),
                      Row(
                        children: [
                          _stepMark(
                            'stepCode',
                            active: !_submitStep,
                            done: _submitStep,
                          ),
                          SizedBox(width: tokens.space.sm),
                          _stepMark(
                            'stepSubmit',
                            active: _submitStep,
                            done: false,
                          ),
                        ],
                      ),
                      SizedBox(height: tokens.space.md),
                      ...(_submitStep ? _submitPanel() : _handleStep()),
                      if (_notice != null) ...[
                        SizedBox(height: tokens.space.md),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _notice!,
                            key: const Key('game-identity-notice'),
                            style: TextStyle(
                              color: switch (_tone) {
                                _Tone.plain => tokens.colors.textSecondary,
                                _Tone.success => tokens.colors.success,
                                _Tone.problem => tokens.colors.warning,
                              },
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: tokens.space.md),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: tokens.space.sm,
                        runSpacing: tokens.space.sm,
                        children: [
                          StarBridgeActionButton(
                            kind: StarBridgeActionKind.quiet,
                            controlKey: const Key('game-identity-cancel'),
                            onActivate: _closed ? null : _close,
                            child: Text(_text('cancel')),
                          ),
                          if (_submitStep)
                            StarBridgeActionButton(
                              controlKey: const Key('game-identity-back'),
                              onActivate: _busy ? null : (_) => _back(),
                              child: Text(_text('back')),
                            ),
                          StarBridgeActionButton(
                            kind: StarBridgeActionKind.primary,
                            controlKey: const Key('game-identity-primary'),
                            onActivate:
                                !_current || _busy || _expired || !_supported
                                ? null
                                : (_) => unawaited(
                                    _submitStep ? _submit() : _requestCode(),
                                  ),
                            child: Text(
                              _text(_submitStep ? 'submit' : 'getCode'),
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
      ),
    );
  }
}
