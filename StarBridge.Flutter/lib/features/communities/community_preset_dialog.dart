import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'communities_module.dart';
import 'community_chat_copy.dart';
import 'community_preset_port.dart';

/// Selecting a share only attaches to the draft; importing requires a separate
/// explicit action and never retries an uncertain device write.
class CommunityPresetDialog extends StatefulWidget {
  const CommunityPresetDialog({required this.port, this.attachment, super.key});
  final CommunityPresetPort port;
  final Map<String, Object?>? attachment;
  @override
  State<CommunityPresetDialog> createState() => _CommunityPresetDialogState();
}

class _CommunityPresetDialogState extends State<CommunityPresetDialog> {
  late final StreamSubscription<void> _changes;
  CommunityPresetCatalog? _catalog;
  String? _error, _imported;
  bool _busy = false, _invalidated = false, _uncertain = false;
  int _epoch = 0;
  bool get _import => widget.attachment != null;
  String t(String key) => communityChatText(context, key);
  @override
  void initState() {
    super.initState();
    _changes = widget.port.invalidations.listen((_) {
      _epoch++;
      if (mounted) {
        setState(() {
          _invalidated = true;
          _busy = false;
          _catalog = null;
          _error = 'identityUnavailable';
        });
      }
    });
    unawaited(_load());
  }

  bool _current(int epoch) => mounted && !_invalidated && epoch == _epoch;
  Future<void> _load() async {
    if (_busy || _invalidated || _uncertain || _imported != null) return;
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _error = null;
      _catalog = null;
    });
    try {
      final value = await widget.port.readCommunityPresets();
      if (_current(epoch)) setState(() => _catalog = value);
    } catch (_) {
      if (_current(epoch)) setState(() => _error = 'presetReadFailed');
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _apply([CommunityPresetChoice? choice]) async {
    final catalog = _catalog;
    if (_busy ||
        _invalidated ||
        _uncertain ||
        catalog == null ||
        _imported != null) {
      return;
    }
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_import) {
        final result = await widget.port.importCommunityPreset(
          widget.attachment!,
          catalog.revision,
        );
        if (_current(epoch)) setState(() => _imported = result);
      } else if (choice != null) {
        final result = await widget.port.exportCommunityPreset(
          choice.id,
          catalog.revision,
        );
        if (mounted && _current(epoch)) Navigator.pop(context, result);
      }
    } catch (error) {
      if (_current(epoch)) {
        setState(() {
          _error = error is CommunityFailure
              ? error.code
              : _import
              ? 'presetImportUnknown'
              : 'presetReadFailed';
          _uncertain =
              _import && !{'presetChanged', 'presetInvalid'}.contains(_error);
          _catalog = null;
        });
      }
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _epoch++;
    unawaited(_changes.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(t(_import ? 'importPreset' : 'sharePreset')),
      content: SizedBox(
        width: 440,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t(_import ? 'importHint' : 'shareHint')),
                if (_import)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      widget.attachment!['title'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(t(_error!)),
                  ),
                if (_imported != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('${t('imported')}: $_imported'),
                  ),
                if (!_import && _catalog != null && !_busy) ...[
                  if (_catalog!.presets.isEmpty) Text(t('noPresets')),
                  for (final choice in _catalog!.presets)
                    ListTile(
                      title: Text(
                        choice.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const StandardIcon(StandardIconSemantic.attachFile),
                      onTap: () => _apply(choice),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t('close')),
        ),
        if (_catalog == null &&
            !_invalidated &&
            !_uncertain &&
            _imported == null)
          TextButton(onPressed: _busy ? null : _load, child: Text(t('retry'))),
        if (_import && _catalog != null && _imported == null)
          FilledButton(
            onPressed: _busy || _invalidated || _uncertain ? null : _apply,
            child: Text(t('importPreset')),
          ),
      ],
    ),
  );
}
