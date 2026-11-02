import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'client_version_copy.dart';
import 'help_support_waiting.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

typedef ClientVersionRead = Future<String?> Function();

class ClientVersionButton extends StatefulWidget {
  const ClientVersionButton({this.open, super.key});
  final Future<void> Function(BuildContext)? open;
  @override
  State<ClientVersionButton> createState() => _ClientVersionButtonState();
}

class _ClientVersionButtonState extends State<ClientVersionButton> {
  bool _opening = false;
  final _source = ValueNotifier(InteractionSource.pointer);

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: StarBridgeActivationOrigin(
      source: _source,
      child: Builder(
        builder: (context) => StarBridgeActionButton(
          controlKey: const Key('client-version-open'),
          onActivate: _opening ? null : (source) => _open(context, source),
          child: Text(clientVersionText(context, 'open')),
        ),
      ),
    ),
  );

  Future<void> _open(BuildContext context, InteractionSource source) async {
    if (_opening) return;
    _source.value = source;
    setState(() => _opening = true);
    try {
      await (widget.open ?? showClientVersionDialog)(context);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}

Future<void> showClientVersionDialog(
  BuildContext context, {
  ClientVersionRead? read,
  InteractionSource? source,
}) => showStarBridgeDialog<void>(
  context,
  source: source,
  builder: (_) => ClientVersionDialog(read: read),
);

class ClientVersionDialog extends StatefulWidget {
  const ClientVersionDialog({this.read, super.key});
  final ClientVersionRead? read;
  @override
  State<ClientVersionDialog> createState() => _ClientVersionDialogState();
}

class _ClientVersionDialogState extends State<ClientVersionDialog> {
  bool _busy = false;
  bool _copying = false;
  InteractionSource _readWaitSource = InteractionSource.programmatic;
  InteractionSource _copyWaitSource = InteractionSource.programmatic;
  int _readWaitRevision = 0, _copyWaitRevision = 0;
  String? _version;
  String? _copyStatus;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([
    InteractionSource source = InteractionSource.programmatic,
  ]) async {
    if (_busy || _copying) return;
    setState(() {
      _busy = true;
      _readWaitSource = source;
      _readWaitRevision++;
      _version = null;
      _copyStatus = null;
    });
    String? value;
    try {
      value = await widget.read?.call().timeout(const Duration(seconds: 15));
    } on Object {
      value = null;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _version = value;
    });
  }

  Future<void> _copy([
    InteractionSource source = InteractionSource.programmatic,
  ]) async {
    final version = _version;
    if (_copying || _busy || version == null) return;
    setState(() {
      _copying = true;
      _copyWaitSource = source;
      _copyWaitRevision++;
      _copyStatus = null;
    });
    var status = 'copied';
    try {
      await Clipboard.setData(ClipboardData(text: version))
          .timeout(const Duration(seconds: 5));
    } on Object {
      status = 'copyFailed';
    }
    if (!mounted) return;
    setState(() {
      _copying = false;
      _copyStatus = status;
    });
    // QualityPass ②: the confirmation clears itself; a failure stays.
    _copiedTimer?.cancel();
    if (status == 'copied') {
      _copiedTimer = Timer(starBridgeTransientDuration, () {
        if (mounted && _copyStatus == 'copied') {
          setState(() => _copyStatus = null);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => clientVersionText(context, key);
    return AlertDialog(
      key: const Key('client-version-dialog'),
      scrollable: true,
      title: Text(t('title')),
      content: SizedBox(
        width: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy)
              HelpSupportWaiting(
                key: ValueKey(('version-read', _readWaitRevision)),
                source: _readWaitSource,
                label: t('loading'),
              )
            else if (_version case final version?)
              SelectableText(version)
            else
              Text(t('unavailable')),
            if (_copying)
              HelpSupportWaiting(
                key: ValueKey(('version-copy', _copyWaitRevision)),
                source: _copyWaitSource,
                label: t('copying'),
              )
            else if (_copyStatus case final status?)
              Semantics(liveRegion: true, child: Text(t(status))),
          ],
        ),
      ),
      actions: [
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('client-version-retry'),
          onActivate: _busy || _copying ? null : _load,
          child: Text(t('retry')),
        ),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('client-version-copy'),
          onActivate: _version == null || _busy || _copying ? null : _copy,
          child: Text(t('copy')),
        ),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('client-version-close'),
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source),
          child: Text(t('close')),
        ),
      ],
    );
  }
}
