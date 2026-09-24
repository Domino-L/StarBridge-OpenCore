import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'client_version_copy.dart';

typedef ClientVersionRead = Future<String?> Function();

class ClientVersionButton extends StatefulWidget {
  const ClientVersionButton({this.open, super.key});
  final Future<void> Function(BuildContext)? open;
  @override
  State<ClientVersionButton> createState() => _ClientVersionButtonState();
}

class _ClientVersionButtonState extends State<ClientVersionButton> {
  bool _opening = false;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: const Key('client-version-open'),
    onPressed: _opening
        ? null
        : () async {
            if (_opening) return;
            setState(() => _opening = true);
            try {
              await (widget.open ??
                  (context) => showClientVersionDialog(context))(context);
            } finally {
              if (mounted) setState(() => _opening = false);
            }
          },
    child: Text(clientVersionText(context, 'open')),
  );
}

Future<void> showClientVersionDialog(
  BuildContext context, {
  ClientVersionRead? read,
}) => showDialog<void>(
  context: context,
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
  String? _version;
  String? _copyStatus;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy || _copying) return;
    setState(() {
      _busy = true;
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

  Future<void> _copy() async {
    final version = _version;
    if (_copying || _busy || version == null) return;
    setState(() {
      _copying = true;
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
              Text(t('loading'))
            else if (_version case final version?)
              SelectableText(version)
            else
              Text(t('unavailable')),
            if (_copyStatus case final status?) Text(t(status)),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('client-version-retry'),
          onPressed: _busy || _copying ? null : _load,
          child: Text(t('retry')),
        ),
        TextButton(
          key: const Key('client-version-copy'),
          onPressed: _version == null || _busy || _copying ? null : _copy,
          child: Text(t('copy')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('close')),
        ),
      ],
    );
  }
}
