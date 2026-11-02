import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../features/settings/client_license.dart';
import 'startup_prompt_queue.dart';
import 'usage_terms_page.dart';

/// Device-level notice precedes optional account prompts; updates reuse the receipt.
final class TestBuildNoticeFlow {
  TestBuildNoticeFlow({
    required this.session,
    required this.queue,
    required this.ready,
    required this.onExit,
    required this.onChanged,
  });
  final BridgeClientSession session;
  final StartupPromptQueue queue;
  final bool Function() ready;
  final Future<void> Function() onExit;
  final VoidCallback onChanged;
  final _key = Object();
  bool _disposed = false, _reading = false, _checked = false, _required = true;
  Timer? _readRetry;
  int _readAttempts = 0;
  StarBridgeDialogRoute<bool>? _route;
  bool get blocksPrompts => !_disposed && (!_checked || _required);
  bool get ownsCurrentRoute =>
      !_disposed && _required && _route?.isCurrent == true;

  void wake() {
    if (_disposed || _reading || _readRetry != null || _route != null) return;
    if (!_checked) {
      unawaited(_read());
      return;
    }
    if (_required) {
      queue.enqueue(
        _key,
        priority: 0,
        eligible: () => !_disposed && ready(),
        show: _show,
      );
    }
  }

  Future<void> _read() async {
    _reading = true;
    _readAttempts++;
    bool? acknowledged;
    try {
      final response = await session.request(
        'legal.readTestBuildNotice',
        payload: const {'schemaVersion': 1},
      );
      acknowledged = _receipt(response.payload);
    } catch (_) {}
    if (_disposed) return;
    _reading = false;
    // Account restoration can invalidate the initial device read. An unknown
    // result is not a missing receipt: retry the read, never the consent write.
    if (acknowledged == null && _readAttempts < 3) {
      _readRetry = Timer(Duration(milliseconds: 300 * _readAttempts), () {
        _readRetry = null;
        wake();
      });
      return;
    }
    _required = acknowledged != true;
    _checked = true;
    onChanged();
    wake();
  }

  bool? _receipt(Map<String, Object?> p) =>
      p.length == 3 &&
          p['schemaVersion'] == 1 &&
          p['termsVersion'] == '2026-10-31-v4' &&
          p['acknowledged'] is bool
      ? p['acknowledged'] as bool
      : null;

  bool _valid(Map<String, Object?> p) => _receipt(p) == true;

  Future<void> _show() async {
    final nav = queue.navigator;
    if (nav == null || _disposed) return;
    final route = StarBridgeDialogRoute<bool>(
      data:
          InteractionScope.maybeOf(nav.context) ??
          resolveStarBridgeInteraction(nav.context),
      link: InteractionScope.linkOf(nav.context),
      barrierLabel: MaterialLocalizations.of(nav.context)
          .modalBarrierDismissLabel,
      dismissible: false,
      builder: (_) => TestBuildNoticeDialog(
        exitApplication: onExit,
        readLicense: BridgeClientLicense(session, available: true).read,
        acknowledge: () async {
          final response = await session.request(
            'legal.acceptTestBuildNotice',
            payload: const {
              'schemaVersion': 1,
              'termsVersion': '2026-10-31-v4',
            },
          );
          return !_disposed && _valid(response.payload);
        },
      ),
    );
    _route = route;
    final accepted = await nav.push(route);
    _route = null;
    if (_disposed) return;
    if (accepted == true) {
      _required = false;
      onChanged();
    } else if (accepted == false) {
      await onExit();
    }
  }

  void dispose() {
    _disposed = true;
    _readRetry?.cancel();
    queue.cancel(_key);
    final route = _route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
  }
}

class TestBuildNoticeDialog extends StatefulWidget {
  const TestBuildNoticeDialog({
    required this.acknowledge,
    required this.readLicense,
    this.exitApplication,
    super.key,
  });
  final Future<bool> Function() acknowledge;
  final ClientLicenseRead readLicense;
  final Future<void> Function()? exitApplication;
  @override
  State<TestBuildNoticeDialog> createState() => _TestBuildNoticeDialogState();
}

class _TestBuildNoticeDialogState extends State<TestBuildNoticeDialog> {
  bool _saving = false, _failed = false, _exiting = false;
  InteractionSource _savingSource = InteractionSource.programmatic;
  Future<void> _accept() async {
    if (_saving || _exiting) return;
    final source = captureStarBridgeActivationSource()();
    setState(() {
      _saving = true;
      _failed = false;
      _savingSource = source;
    });
    var accepted = false;
    try {
      accepted = await widget.acknowledge();
    } catch (_) {}
    if (!mounted) return;
    if (accepted) {
      dismissStarBridgeDialog(context, source: source, result: true);
      return;
    }
    setState(() {
      _saving = false;
      _failed = true;
    });
  }

  Future<void> _decline(InteractionSource source) async {
    if (_saving || _exiting) return;
    final exit = widget.exitApplication;
    if (exit == null) {
      dismissStarBridgeDialog(context, source: source, result: false);
      return;
    }
    setState(() {
      _exiting = true;
      _savingSource = source;
    });
    try {
      await exit();
    } catch (_) {
      // Keep the mandatory gate visible if the lifecycle cannot exit.
    } finally {
      if (mounted) setState(() => _exiting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: UsageTermsPage(
        readLicense: widget.readLicense,
        saving: _saving,
        exiting: _exiting,
        failed: _failed,
        savingSource: _savingSource,
        onAccept: () => unawaited(_accept()),
        onExit: (source) => unawaited(_decline(source)),
      ),
    );
  }
}
