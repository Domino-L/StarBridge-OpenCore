import 'dart:async';

import 'package:flutter/material.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../features/settings/client_license.dart';
import '../../features/settings/client_license_dialog.dart';
import 'startup_prompt_queue.dart';
import 'test_build_notice_copy.dart';

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
  DialogRoute<bool>? _route;
  bool get blocksPrompts => !_disposed && (!_checked || _required);

  void wake() {
    if (_disposed || _reading || _route != null) return;
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
    try {
      final response = await session.request(
        'legal.readTestBuildNotice',
        payload: const {'schemaVersion': 1},
      );
      _required = !_valid(response.payload);
    } catch (_) {
      _required = true;
    }
    if (_disposed) return;
    _checked = true;
    _reading = false;
    onChanged();
    wake();
  }

  bool _valid(Map<String, Object?> p) =>
      p.length == 3 &&
      p['schemaVersion'] == 1 &&
      p['termsVersion'] == '2026-08-01-v3' &&
      p['acknowledged'] == true;

  Future<void> _show() async {
    final nav = queue.navigator;
    if (nav == null || _disposed) return;
    final route = DialogRoute<bool>(
      context: nav.context,
      barrierDismissible: false,
      builder: (_) => TestBuildNoticeDialog(
        readLicense: BridgeClientLicense(session, available: true).read,
        acknowledge: () async {
          final response = await session.request(
            'legal.acceptTestBuildNotice',
            payload: const {
              'schemaVersion': 1,
              'termsVersion': '2026-08-01-v3',
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
    super.key,
  });
  final Future<bool> Function() acknowledge;
  final ClientLicenseRead readLicense;
  @override
  State<TestBuildNoticeDialog> createState() => _TestBuildNoticeDialogState();
}

class _TestBuildNoticeDialogState extends State<TestBuildNoticeDialog> {
  bool _saving = false, _failed = false;
  Future<void> _accept() async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    var accepted = false;
    try {
      accepted = await widget.acknowledge();
    } catch (_) {}
    if (!mounted) return;
    if (accepted) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _saving = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final en = locale.languageCode == 'en';
    final tw = locale.countryCode == 'TW' || locale.scriptCode == 'Hant';
    String t(String cn, String traditional, String english) => en
        ? english
        : tw
        ? traditional
        : cn;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('test-build-notice'),
        title: Text(t('测试版使用须知', '測試版使用須知', 'Before using this test version')),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(testBuildNoticeBody(locale)),
                const SizedBox(height: 16),
                ClientLicenseButton(
                  open: (context) => showClientLicenseDialog(
                    context,
                    read: widget.readLicense,
                  ),
                ),
                if (_failed)
                  Text(
                    t(
                      '暂时无法继续，请重试。若仍无法进入，请重启应用或联系支持。',
                      '暫時無法繼續，請重試。若仍無法進入，請重新啟動應用程式或聯絡支援。',
                      'Unable to continue. Please try again. If the problem persists, restart the app or contact support.',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(t('退出应用', '結束應用程式', 'Exit application')),
          ),
          FilledButton(
            key: const Key('test-build-accept'),
            onPressed: _saving ? null : _accept,
            child: Text(
              t(
                '我已阅读并理解，继续',
                '我已閱讀並理解，繼續',
                'I have read and understood, continue',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
