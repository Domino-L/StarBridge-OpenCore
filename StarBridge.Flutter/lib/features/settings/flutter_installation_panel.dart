import 'package:flutter/material.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'flutter_installation_text.dart';

class FlutterInstallationPanel extends StatefulWidget {
  const FlutterInstallationPanel({this.session, super.key});
  final BridgeClientSession? session;

  @override
  State<FlutterInstallationPanel> createState() =>
      _FlutterInstallationPanelState();
}

class _FlutterInstallationPanelState extends State<FlutterInstallationPanel> {
  Map<String, dynamic>? _plan;
  bool _busy = false;
  bool _confirming = false;
  String? _message;

  Future<void> _scan() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _plan = null;
      _message = null;
    });
    try {
      final session = widget.session!;
      final response = await session.request(
        'diagnostics.flutterInstallation',
        payload: {'schemaVersion': 1},
      );
      final p = response.payload;
      if (p['schemaVersion'] != 1 ||
          p['ticket'] is! String ||
          p['directory'] is! String ||
          p['canUninstall'] is! bool ||
          p['canClean'] is! bool ||
          ![
            'portable',
            'installed',
            'other',
            'orphaned',
            'damaged',
            'unverified',
          ].contains(p['mode'])) {
        throw StateError('Invalid installation response');
      }
      if (mounted && session == widget.session) {
        setState(() => _plan = Map<String, dynamic>.from(p));
      }
    } on Object {
      if (mounted) setState(() => _message = 'failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _execute(String action) async {
    if (_busy || _plan == null) return;
    final plan = _plan!;
    final session = widget.session;
    setState(() {
      _busy = true;
      _confirming = true;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(flutterInstallationText(context, action)),
          content: Text(
            '${flutterInstallationText(context, '${action}Confirm')}\n\n${plan['directory']}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(flutterInstallationText(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(flutterInstallationText(context, action)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || session != widget.session) return;
      setState(() {
        _confirming = false;
        _plan = null;
        _message = null;
      });
      final response = await session!.request(
        'diagnostics.flutterInstallationExecute',
        payload: {
          'schemaVersion': 1,
          'ticket': plan['ticket'],
          'action': action,
        },
      );
      if (response.payload['schemaVersion'] != 1 ||
          response.payload['completed'] != true) {
        throw StateError('Unconfirmed');
      }
      if (mounted) {
        setState(() => _message = action == 'clean' ? 'cleaned' : 'started');
      }
    } on Object {
      if (mounted) {
        setState(() {
          _plan = null;
          _message = 'failed';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(FlutterInstallationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _plan = null;
      _message = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => flutterInstallationText(context, key);
    final tokens = context.tokens;
    final available =
        widget.session?.hostCapabilities.contains(
          'diagnostics.flutterInstallation',
        ) ??
        false;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('title'), style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: tokens.space.sm),
          Text(t('scope')),
          if (!available) Text(t('unavailable')),
          if (_busy && !_confirming) const LinearProgressIndicator(),
          if (_plan case final plan?) ...[
            SizedBox(height: tokens.space.md),
            Text(
              t(plan['mode'] as String),
              style: TextStyle(
                color: plan['mode'] == 'installed'
                    ? tokens.colors.success
                    : tokens.colors.info,
              ),
            ),
            if ((plan['directory'] as String).isNotEmpty)
              SelectableText(plan['directory'] as String),
            if (plan['mode'] == 'portable') ...[
              SizedBox(height: tokens.space.xs),
              Text(
                t('noRemnants'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
          SizedBox(height: tokens.space.md),
          Wrap(
            spacing: tokens.space.sm,
            runSpacing: tokens.space.sm,
            children: [
              OutlinedButton(
                key: const Key('flutter-installation-scan'),
                onPressed: available && !_busy ? _scan : null,
                child: Text(t('scan')),
              ),
              if (_plan?['canUninstall'] == true)
                OutlinedButton(
                  key: const Key('flutter-installation-uninstall'),
                  onPressed: !_busy && _plan?['canUninstall'] == true
                      ? () => _execute('uninstall')
                      : null,
                  child: Text(t('uninstall')),
                ),
              if (_plan?['canClean'] == true)
                OutlinedButton(
                  key: const Key('flutter-installation-clean'),
                  onPressed: !_busy && _plan?['canClean'] == true
                      ? () => _execute('clean')
                      : null,
                  child: Text(t('clean')),
                ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: EdgeInsets.only(top: tokens.space.sm),
              child: Text(
                t(_message!),
                style: TextStyle(
                  color: _message == 'failed'
                      ? tokens.colors.warning
                      : tokens.colors.success,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
