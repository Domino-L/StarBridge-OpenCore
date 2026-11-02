import 'package:flutter/material.dart';

import '../../app/legal/usage_terms_sections.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'client_license.dart';
import 'client_license_copy.dart';
import 'help_support_waiting.dart';

/// This is document viewing, not an acceptance or entitlement action.
class ClientLicenseButton extends StatefulWidget {
  const ClientLicenseButton({this.open, super.key});
  final Future<void> Function(BuildContext)? open;
  @override
  State<ClientLicenseButton> createState() => _ClientLicenseButtonState();
}

class _ClientLicenseButtonState extends State<ClientLicenseButton> {
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
          controlKey: const Key('client-license-open'),
          onActivate: _opening ? null : (source) => _open(context, source),
          child: Text(clientLicenseText(context, 'open')),
        ),
      ),
    ),
  );

  Future<void> _open(BuildContext context, InteractionSource source) async {
    if (_opening) return;
    _source.value = source;
    setState(() => _opening = true);
    try {
      await (widget.open ?? showClientLicenseDialog)(context);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}

Future<void> showClientLicenseDialog(
  BuildContext context, {
  ClientLicenseRead? read,
  InteractionSource? source,
}) => showStarBridgeDialog<void>(
  context,
  source: source,
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
  InteractionSource _readWaitSource = InteractionSource.programmatic;
  int _readWaitRevision = 0;
  ClientLicenseDocument _document = const ClientLicenseDocument(
    ClientLicenseState.unavailable,
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([
    InteractionSource source = InteractionSource.programmatic,
  ]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _readWaitSource = source;
      _readWaitRevision++;
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
                  child: UsageTermsSections(
                    license: _busy
                        ? HelpSupportWaiting(
                            key: ValueKey(('license-read', _readWaitRevision)),
                            source: _readWaitSource,
                            label: t('loading'),
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
              ),
              SizedBox(height: tokens.space.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: tokens.space.sm,
                children: [
                  if (_document.state != ClientLicenseState.ready)
                    StarBridgeActionButton(
                      controlKey: const Key('client-license-retry'),
                      onActivate: _busy ? null : _load,
                      child: Text(t('retry')),
                    ),
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    controlKey: const Key('client-license-close'),
                    onActivate: (source) =>
                        dismissStarBridgeDialog(context, source: source),
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
