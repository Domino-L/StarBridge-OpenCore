import 'package:flutter/material.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'client_license.dart';
import 'client_license_copy.dart';

/// This is document viewing, not an acceptance or entitlement action.
class ClientLicenseButton extends StatefulWidget {
  const ClientLicenseButton({this.open, super.key});
  final Future<void> Function(BuildContext)? open;
  @override
  State<ClientLicenseButton> createState() => _ClientLicenseButtonState();
}

class _ClientLicenseButtonState extends State<ClientLicenseButton> {
  bool _opening = false;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: const Key('client-license-open'),
    onPressed: _opening
        ? null
        : () async {
            if (_opening) return;
            setState(() => _opening = true);
            try {
              await (widget.open ??
                  (context) => showClientLicenseDialog(context))(context);
            } finally {
              if (mounted) setState(() => _opening = false);
            }
          },
    child: Text(clientLicenseText(context, 'open')),
  );
}

Future<void> showClientLicenseDialog(
  BuildContext context, {
  ClientLicenseRead? read,
}) => showDialog<void>(
  context: context,
  builder: (_) => ClientLicenseDialog(read: read),
);

class ClientLicenseDialog extends StatefulWidget {
  const ClientLicenseDialog({this.read, super.key});
  final ClientLicenseRead? read;
  @override
  State<ClientLicenseDialog> createState() => _ClientLicenseDialogState();
}

class _ClientLicenseDialogState extends State<ClientLicenseDialog> {
  bool _busy = false;
  ClientLicenseDocument _document = const ClientLicenseDocument(
    ClientLicenseState.unavailable,
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _document = const ClientLicenseDocument(ClientLicenseState.unavailable);
    });
    ClientLicenseDocument next;
    try {
      next =
          await widget.read?.call().timeout(const Duration(seconds: 15)) ??
          const ClientLicenseDocument(ClientLicenseState.unavailable);
    } on Object {
      next = const ClientLicenseDocument(ClientLicenseState.unavailable);
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _document = next;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String t(String key) => clientLicenseText(context, key);
    return Dialog(
      key: const Key('client-license-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: StarBridgeSurface(
        role: SurfaceRole.floating,
        child: SizedBox(
          width: 760,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('title'), style: Theme.of(context).textTheme.titleLarge),
              SizedBox(height: tokens.space.md),
              Flexible(
                child: SingleChildScrollView(
                  child: _busy
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LinearProgressIndicator(
                              semanticsLabel: t('loading'),
                            ),
                            Text(t('loading')),
                          ],
                        )
                      : _document.state == ClientLicenseState.ready
                      ? SelectableText(
                          _document.text!,
                          key: const Key('client-license-body'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : Text(
                          t(_document.state.name),
                          key: const Key('client-license-error'),
                        ),
                ),
              ),
              SizedBox(height: tokens.space.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: tokens.space.sm,
                children: [
                  if (_document.state != ClientLicenseState.ready)
                    OutlinedButton(
                      key: const Key('client-license-retry'),
                      onPressed: _busy ? null : _load,
                      child: Text(t('retry')),
                    ),
                  TextButton(
                    key: const Key('client-license-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t('close')),
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
