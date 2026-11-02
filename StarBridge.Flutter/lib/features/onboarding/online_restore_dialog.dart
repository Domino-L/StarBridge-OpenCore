import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'onboarding_copy.dart';
import 'online_installation_port.dart';
import 'online_review_controller.dart';
import 'online_review_panel.dart';
import 'online_review_port.dart';

Future<bool> showOnlineRestoreDialog(
  BuildContext context, {
  required OnlineReviewPort review,
  required OnlineInstallationPort installation,
  required Future<bool> Function() onInstalled,
  int? installationRevision,
}) async =>
    await showStarBridgeDialog<bool>(
      context,
      source: StarBridgeActivationOrigin.sourceOf(context),
      barrierDismissible: false,
      builder: (_) => _OnlineRestoreDialog(
        review: review,
        installation: installation,
        onInstalled: onInstalled,
        installationRevision: installationRevision,
      ),
    ) ??
    false;

class _OnlineRestoreDialog extends StatefulWidget {
  const _OnlineRestoreDialog({
    required this.review,
    required this.installation,
    required this.onInstalled,
    this.installationRevision,
  });
  final OnlineReviewPort review;
  final OnlineInstallationPort installation;
  final Future<bool> Function() onInstalled;
  final int? installationRevision;
  @override
  State<_OnlineRestoreDialog> createState() => _OnlineRestoreDialogState();
}

class _OnlineRestoreDialogState extends State<_OnlineRestoreDialog> {
  late final _review = OnlineReviewController(widget.review);
  OnlineInstallationSnapshot? _observed;
  int? _revision;
  bool _busy = false, _error = false, _closing = false;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    _review.addListener(_changed);
    _revision = widget.installationRevision;
    if (_revision != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_request());
      });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  // A retained account confirmed after verifying here has no local Handle
  // review to pass; the Host still admits the install by its own receipt.
  bool get _readyToInstall {
    final snapshot = _review.value.snapshot;
    return snapshot.identityConfirmed ||
        snapshot.retainsSession &&
            snapshot.state == OnlineReviewState.accountConfirmedForHandoff;
  }

  Future<void> _install() async {
    if (_busy ||
        _revision != null ||
        _review.value.busy ||
        _review.value.error ||
        !_readyToInstall ||
        !widget.installation.supported) {
      return;
    }
    _revision = _review.value.snapshot.revision;
    await _request(write: true);
  }

  Future<void> _request({bool write = false}) async {
    if (_busy || _revision == null || !mounted) return;
    _poll?.cancel();
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final result = write
          ? await widget.installation.install(_revision!)
          : await widget.installation.read(_revision!);
      if (!mounted) return;
      _observed = result;
      if (result.online) {
        // Physical installation does not substitute the product's fresh account
        // and mode reads or trigger privacy choices/guide completion.
        if (await widget.onInstalled() && mounted) {
          _finish(true, InteractionSource.programmatic);
          return;
        }
        _error = true;
      } else if (result.phase == OnlineInstallationPhase.idle) {
        _revision = null;
        _observed = null;
        await _review
            .refresh(); // No installation replay after an uncertain wait.
      }
    } on Object {
      if (mounted) _error = true;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (!_error && _observed?.phase == OnlineInstallationPhase.running) {
          _poll = Timer(
            const Duration(seconds: 2),
            () => unawaited(_request()),
          );
        }
      }
    }
  }

  Future<void> _close([
    InteractionSource source = InteractionSource.programmatic,
  ]) async {
    if (_busy || _review.value.busy || _closing || !mounted) return;
    _closing = true;
    try {
      if (_revision == null && _review.value.snapshot.canCancel) {
        await _review.execute(OnlineReviewAction.cancel);
        if (_review.value.error || _review.value.snapshot.canCancel) return;
      }
      if (mounted) {
        _finish(false, source);
      }
    } finally {
      _closing = false;
    }
  }

  void _finish(bool result, InteractionSource source) {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (!route.isCurrent) {
      // Async cancellation/installation may finish beneath a newer draft.
      // Retire only this dialog, never whichever route is now on top.
      route.navigator?.removeRoute(route, result);
      return;
    }
    dismissStarBridgeDialog(context, source: source, result: result);
  }

  @override
  Widget build(BuildContext context) {
    final copy = OnboardingCopy(Localizations.localeOf(context));
    final installing = _revision != null;
    final status = _error
        ? 'unconfirmed'
        : _observed?.phase == OnlineInstallationPhase.completed
        ? switch (_observed!.modeState) {
            'local' || 'offline' => 'local',
            _ => 'recovery',
          }
        : 'working';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: AlertDialog(
        title: Text(copy.text('onlineRestore.title')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: installing
                ? Semantics(
                    liveRegion: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(copy.text('onlineRestore.$status')),
                        if (!_error && _observed?.failure != null) ...[
                          const SizedBox(height: 12),
                          SelectableText(
                            '${copy.text('onlineRestore.diagnostic')}: ${_observed!.failure!.code}',
                            key: const Key('online-restore-diagnostic'),
                          ),
                        ],
                      ],
                    ),
                  )
                : OnlineReviewPanel(
                    controller: _review,
                    copy: copy,
                    enabled: !_busy,
                  ),
          ),
        ),
        actions: [
          if (!installing && _readyToInstall)
            StarBridgeActionButton(
              controlKey: const Key('online-restore-install'),
              kind: StarBridgeActionKind.primary,
              onActivate: _tap(
                _busy ||
                        _review.value.busy ||
                        _review.value.error ||
                        !widget.installation.supported
                    ? null
                    : _install,
              ),
              child: Text(copy.text('onlineRestore.install')),
            ),
          if (installing)
            StarBridgeActionButton(
              controlKey: const Key('online-restore-recheck'),
              kind: StarBridgeActionKind.quiet,
              onActivate: _tap(_busy ? null : () => _request()),
              child: Text(copy.text('onlineRestore.recheck')),
            ),
          StarBridgeActionButton(
            controlKey: const Key('online-restore-close'),
            kind: StarBridgeActionKind.quiet,
            onActivate: _busy || _review.value.busy ? null : _close,
            child: Text(copy.text('onlineRestore.close')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _review.removeListener(_changed);
    _review.dispose();
    super.dispose();
  }
}

/// Native-style tap callback to a suite activation (source unused here).
ValueChanged<InteractionSource>? _tap(VoidCallback? onPressed) =>
    onPressed == null ? null : (_) => onPressed();
