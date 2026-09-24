import 'package:flutter/material.dart';

import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';

import 'room_action_dialogs.dart';
import 'room_chat_module.dart';
import 'room_preset_port.dart';

Future<void> roomPresetDialog(
  BuildContext context,
  RoomChatModule module, {
  RoomChatMessage? message,
}) async {
  if (!module.presetsAvailable) return;
  final revision = module.contextRevision;
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PresetDialog(
      module: module,
      message: message,
      contextRevision: revision,
    ),
  );
  if (context.mounted && result != null && message != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${roomActionText(context, 'presetImported')} $result'),
      ),
    );
  }
}

class _PresetDialog extends StatefulWidget {
  const _PresetDialog({
    required this.module,
    required this.contextRevision,
    this.message,
  });
  final RoomChatModule module;
  final int contextRevision;
  final RoomChatMessage? message;
  @override
  State<_PresetDialog> createState() => _PresetDialogState();
}

class _PresetDialogState extends State<_PresetDialog> {
  int get _context => widget.contextRevision;
  late final _catalog = widget.module.presets!.readPresets();
  bool _busy = false, _closing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.module.addListener(_changed);
  }

  void _changed() {
    if (!mounted || _closing || widget.module.isCurrentContext(_context)) {
      return;
    }
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    widget.module.removeListener(_changed);
    super.dispose();
  }

  Future<void> _act(
    RoomPresetCatalog catalog, [
    RoomPresetChoice? choice,
  ]) async {
    if (_busy || !widget.module.isCurrentContext(_context)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String? result;
      if (widget.message case final message?) {
        result = await widget.module.importPreset(
          message,
          catalog.revision,
          _context,
        );
      } else {
        result =
            await widget.module.preparePreset(
              choice!,
              catalog.revision,
              _context,
            )
            ? ''
            : null;
      }
      if (!mounted || _closing) return;
      if (result != null) {
        Navigator.of(context).pop(result);
        return;
      }
      setState(() => _error = widget.module.error ?? 'contextChanged');
    } on Object {
      if (mounted) {
        setState(
          () => _error = widget.message == null
              ? 'unavailable'
              : 'presetImportUnknown',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => roomActionText(context, key);
    if (!widget.module.isCurrentContext(_context)) {
      return AlertDialog(
        content: Text(t('contextChanged')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('cancel')),
          ),
        ],
      );
    }
    final importing = widget.message != null;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(t(importing ? 'importPreset' : 'sharePreset')),
        content: SizedBox(
          width: 420,
          child: FutureBuilder<RoomPresetCatalog>(
            future: _catalog,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  t(
                    snapshot.error is RoomChatFailure
                        ? (snapshot.error as RoomChatFailure).code
                        : 'unavailable',
                  ),
                );
              }
              final catalog = snapshot.data;
              if (catalog == null) return const LinearProgressIndicator();
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t(importing ? 'importPresetHint' : 'sharePresetHint')),
                    const SizedBox(height: 12),
                    if (importing) ...[
                      Text(
                        widget.message!.attachment?['title'] as String? ?? '',
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy || _error != null
                            ? null
                            : () => _act(catalog),
                        child: Text(t(_busy ? 'working' : 'importPreset')),
                      ),
                    ] else if (catalog.presets.isEmpty)
                      Text(t('noPresets'))
                    else
                      for (final choice in catalog.presets)
                        ListTile(
                          title: Text(choice.name),
                          trailing: const StarBridgeIcon(
                            StarBridgeIconSemantic.forward,
                          ),
                          onTap: _busy ? null : () => _act(catalog, choice),
                        ),
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null) Text(t(_error!)),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(t('cancel')),
          ),
        ],
      ),
    );
  }
}
