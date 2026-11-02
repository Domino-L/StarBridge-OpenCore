import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../common/social_read_activity.dart';

import 'communities_module.dart';
import 'community_chat_copy.dart';
import 'community_preset_port.dart';
import '../overlay_settings/overlay_preset_inspection_port.dart';
import '../overlay_settings/overlay_preset_import_preview.dart';

Future<Map<String, Object?>?> showCommunityPresetDialog(
  BuildContext context, {
  required CommunityPresetPort port,
  Map<String, Object?>? attachment,
  InteractionSource? source,
}) => showStarBridgeDialog<Map<String, Object?>>(
  context,
  source: source,
  barrierDismissible: false,
  builder: (_) => CommunityPresetDialog(port: port, attachment: attachment),
);

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
  ModalRoute<dynamic>? _inspectionRoute;
  InteractionSource _activitySource = InteractionSource.programmatic;
  String _activityStage = 'preset-read';
  int _activityRevision = 0;
  bool _activityOpening = false, _firstRead = true, _activityCovered = false;

  void _beginActivity(
    String stage, {
    InteractionSource? source,
    bool opening = false,
  }) {
    _activityStage = stage;
    _activitySource = source ?? captureStarBridgeActivationSource()();
    _activityRevision++;
    _activityOpening = opening;
    _activityCovered = false;
  }

  bool get _import => widget.attachment != null;
  String t(String key) => communityChatText(context, key);
  @override
  void initState() {
    super.initState();
    _changes = widget.port.invalidations.listen((_) {
      _epoch++;
      final inspection = _inspectionRoute;
      if (inspection != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && inspection.isActive) {
            inspection.navigator?.removeRoute(inspection);
          }
        });
      }
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
      _beginActivity('preset-read', opening: _firstRead);
      _firstRead = false;
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

  Future<void> _apply(
    InteractionSource source, [
    CommunityPresetChoice? choice,
  ]) async {
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
      _beginActivity(
        _import
            ? widget.port is OverlayPresetInspectionPort
                  ? 'preset-inspect'
                  : 'preset-import'
            : 'preset-export',
        source: source,
      );
      _busy = true;
      _error = null;
    });
    var writeStarted = false;
    try {
      if (_import) {
        final inspector = widget.port;
        if (inspector is OverlayPresetInspectionPort) {
          final preview = await (inspector as OverlayPresetInspectionPort)
              .inspectPreset(
                widget.attachment!['overlayPresetPackage'] as String,
                catalog.revision,
              );
          if (!mounted || !_current(epoch)) return;
          setState(() => _activityCovered = true);
          final confirmed = await showStarBridgeDialog<bool>(
            context,
            source: source,
            builder: (previewContext) {
              _inspectionRoute = ModalRoute.of(previewContext);
              return OverlayPresetImportPreview(
                onConfirmSource: (source) {
                  if (_current(epoch)) _activitySource = source;
                },
                name: preview.name,
                settings: preview.settings,
                layout: preview.layout,
                currentSettings: null,
                sources: preview.sources,
                removedOrganizationBindings:
                    preview.removedOrganizationBindings,
              );
            },
          );
          _inspectionRoute = null;
          if (!_current(epoch) || confirmed != true) return;
          setState(
            () => _beginActivity('preset-import', source: _activitySource),
          );
        }
        writeStarted = true;
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
        if (mounted && _current(epoch)) {
          dismissStarBridgeDialog(context, source: source, result: result);
        }
      }
    } catch (error) {
      if (_current(epoch)) {
        setState(() {
          _error = error is CommunityFailure
              ? error.code
              : _import && writeStarted
              ? 'presetImportUnknown'
              : 'presetReadFailed';
          _uncertain =
              _import &&
              writeStarted &&
              !{'presetChanged', 'presetInvalid'}.contains(_error);
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
                if (_busy && !_activityCovered)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: KeyedSubtree(
                      key: ValueKey(_activityRevision),
                      child: SocialReadActivity(
                        key: ValueKey('$_activityStage-activity'),
                        source: _activitySource,
                        opening: _activityOpening,
                        label: t(switch (_activityStage) {
                          'preset-inspect' => 'presetActivityInspect',
                          'preset-export' => 'presetActivityExport',
                          'preset-import' => 'presetActivityImport',
                          _ => 'presetActivityRead',
                        }),
                        height: 4,
                      ),
                    ),
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
                    StarBridgeActionRow(
                      controlKey: ValueKey(
                        'community-preset-choice-${choice.id}',
                      ),
                      semanticLabel: choice.name,
                      onActivate: (_, source) => _apply(source, choice),
                      child: ExcludeFocus(
                        child: ExcludeSemantics(
                          child: ListTile(
                            title: Text(
                              choice.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const StandardIcon(
                              StandardIconSemantic.attachFile,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          onActivate: _busy
              ? null
              : (source) => dismissStarBridgeDialog(context, source: source),
          child: Text(t('close')),
        ),
        if (_catalog == null &&
            !_invalidated &&
            !_uncertain &&
            _imported == null)
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            onActivate: _busy ? null : (_) => _load(),
            child: Text(t('retry')),
          ),
        if (_import && _catalog != null && _imported == null)
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            onActivate: _busy || _invalidated || _uncertain ? null : _apply,
            child: Text(t('importPreset')),
          ),
      ],
    ),
  );
}
