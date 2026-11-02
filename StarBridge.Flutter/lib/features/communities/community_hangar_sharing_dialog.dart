import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';

import 'community_hangar_sharing_port.dart';
import '../common/organization_hangar_sharing.dart';
import 'community_organization_sharing_adapter.dart';
import '../../design_system/interaction/starbridge_compact_select.dart';
import 'communities_module.dart';
import 'community_ships_copy.dart';

class CommunityHangarSharingDialog extends StatefulWidget {
  const CommunityHangarSharingDialog({required this.port, super.key})
    : editor = null,
      sourceRef = null;
  const CommunityHangarSharingDialog.editor({
    required this.editor,
    this.sourceRef,
    super.key,
  }) : port = null;
  final CommunityHangarSharingPort? port;
  final OrganizationHangarSharingPort? editor;
  final String? sourceRef;
  @override
  State<CommunityHangarSharingDialog> createState() => _SharingState();
}

class _SharingState extends State<CommunityHangarSharingDialog> {
  OrganizationSharingDraft? _draft;
  OrganizationSharingPage? _page;
  late final OrganizationHangarSharingPort _editor;
  String? _strategy;
  final _selected = <String>{};
  late final StreamSubscription<void> _subscription;
  bool _busy = false, _invalidated = false;
  bool _includeImages = false;
  String? _error;
  int _generation = 0;
  String t(String key) => communityShipsText(context, key);

  @override
  void initState() {
    super.initState();
    _editor =
        widget.editor ?? CommunityOrganizationSharingAdapter(widget.port!);
    _subscription = _editor.invalidations.listen((_) {
      if (!mounted) return;
      _generation++;
      setState(() {
        _draft = null;
        _selected.clear();
        _includeImages = false;
        _invalidated = true;
        _busy = false;
        _error = 'sharingChanged';
      });
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_subscription.cancel());
    super.dispose();
  }

  Future<void> _load({String? scopeRef}) async {
    if (_busy || _invalidated) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _draft = null;
      _selected.clear();
      _includeImages = false;
    });
    try {
      final draft = await _editor.read(widget.sourceRef, scopeRef: scopeRef);
      if (!mounted || generation != _generation) return;
      setState(() {
        _draft = draft;
        _page = draft.page;
        _strategy = draft.strategy;
        _selected.addAll(draft.selectedRefs);
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error =
              error is CommunityFailure && error.code == 'upgradeRequired'
              ? 'sharingUpgrade'
              : 'sharingUnavailable',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (_busy || draft == null || _invalidated) return;
    if (!_canSave(draft)) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    CommunityHangarSharingOutcome result;
    try {
      result = await _editor.save(
        draft.editRef,
        draft.sourceRef,
        _strategy,
        _strategy != null && _strategy != 'organizationPool'
            ? []
            : _selected.toList(),
        includeImages:
            _includeImages &&
            draft.allowImages &&
            _selected.isNotEmpty &&
            (!_official(draft) ||
                _strategy == 'organizationPool' && draft.canPublish),
      );
    } catch (_) {
      result = const CommunityHangarSharingOutcome('unknown');
    }
    _finishSave(result, generation);
  }

  Future<void> _clearImages() async {
    final draft = _draft, editor = _editor;
    if (_busy ||
        _invalidated ||
        draft?.canClearImages != true ||
        draft?.sourceRef == null ||
        editor is! OrganizationHangarImageConsentPort) {
      return;
    }
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    CommunityHangarSharingOutcome result;
    try {
      result = await (editor as OrganizationHangarImageConsentPort).clearImages(
        draft!.editRef,
        draft.sourceRef!,
      );
    } catch (_) {
      result = const CommunityHangarSharingOutcome('unknown');
    }
    _finishSave(result, generation);
  }

  void _finishSave(CommunityHangarSharingOutcome result, int generation) {
    if (!mounted || generation != _generation) return;
    if (result.status == 'accepted') {
      dismissStarBridgeDialog(
        context,
        source: currentStarBridgeActivationSource,
        result: true,
      );
      return;
    }
    setState(() {
      _busy = false;
      // Every failed/uncertain write requires a fresh authorized read.
      _draft = null;
      _selected.clear();
      _error = result.status == 'unknown'
          ? 'sharingUnknown'
          : switch (result.error) {
              'localHangarRequired' => 'sharingScanRequired',
              'upgradeRequired' => 'sharingUpgrade',
              _ => 'sharingSaveFailed',
            };
    });
  }

  bool _official(OrganizationSharingDraft draft) =>
      draft.mode == OrganizationSharingMode.instances;
  bool _alreadyUnshared(OrganizationSharingDraft draft) =>
      !_official(draft) &&
      draft.explicit &&
      draft.selectedRefs.isEmpty &&
      _selected.isEmpty;
  bool _canSave(OrganizationSharingDraft draft) {
    if (!_official(draft)) return !_alreadyUnshared(draft);
    if (_strategy == null) return false;
    if (_strategy == 'notShared') return draft.canReduce || draft.canGrant;
    if (_strategy == 'operationOnly') return draft.canGrant;
    if (_selected.isEmpty) return false;
    final previous = draft.selectedRefs.toSet();
    final pureReduction =
        draft.selectionKnown &&
        draft.strategy == 'organizationPool' &&
        _selected.length < previous.length &&
        _selected.every(previous.contains);
    return pureReduction ? draft.canReduce : draft.canPublish;
  }

  Future<void> _loadPage(int offset) async {
    final draft = _draft;
    if (_busy || draft == null || draft.sourceRef == null) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await _editor.page(draft.editRef, draft.sourceRef!, offset);
      if (mounted && generation == _generation) setState(() => _page = page);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _draft = null;
          _selected.clear();
          _error = 'sharingUnavailable';
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final official = draft != null ? _official(draft) : widget.editor != null;
    final rows = _page?.options ?? const <OrganizationSharingOption>[];
    final heading = <Widget>[
      Text(t(official ? 'ownSharingScope' : 'sharingScope')),
      const SizedBox(height: 12),
      if (draft != null && !official)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            !draft.explicit
                ? t('sharingCurrentLegacy')
                : draft.selectedRefs.isEmpty
                ? t('sharingCurrentNone')
                : '${t('sharingCurrentSelected')} ${draft.selectedRefs.length}',
          ),
        ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            t(_error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (draft != null && !official && !draft.explicit)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(t('sharingLegacy')),
        ),
      if (draft != null && official) ...[
        if (draft.scopes.length == 1)
          Text('${t('ownSharingFleet')}: ${draft.scopes.single.name}'),
        if (draft.scopes.length > 1)
          StarBridgeCompactSelect<String>(
            identity: 'hangar-sharing-scope',
            isExpanded: true,
            selectedMaxLines: 1,
            selectedOverflow: TextOverflow.ellipsis,
            controlKey: const ValueKey('hangar-sharing-scope'),
            semanticLabel: t('ownSharingFleet'),
            options: [
              for (final scope in draft.scopes)
                StarBridgeSelectOption(
                  value: scope.reference,
                  label: scope.name,
                ),
            ],
            value: draft.scopeRef,
            onSelected: _busy ? null : (value, _) => _load(scopeRef: value),
          ),
        StarBridgeCompactSelect<String>(
          identity: 'hangar-sharing-strategy',
          isExpanded: true,
          selectedMaxLines: 1,
          selectedOverflow: TextOverflow.ellipsis,
          controlKey: const ValueKey('hangar-sharing-strategy'),
          semanticLabel: t('ownSharingStrategy'),
          options: [
            for (final value in const [
              'notShared',
              'organizationPool',
              'operationOnly',
            ])
              StarBridgeSelectOption(
                value: value,
                label: t(value),
                enabled: value == 'notShared'
                    ? draft.canGrant || draft.canReduce
                    : value == 'organizationPool'
                    ? draft.canPublish ||
                          draft.canReduce && draft.selectionKnown
                    : draft.canGrant,
              ),
          ],
          value: _strategy,
          placeholder: t('ownSharingChoose'),
          onSelected: _busy
              ? null
              : (value, _) => setState(() {
                  _strategy = value;
                  _includeImages = false;
                }),
        ),
        Text(
          t(switch (draft.state) {
            'selectionRequired' => 'ownSharingSelectionRequired',
            'stale' => 'ownSharingStale',
            'forbidden' => 'ownSharingForbidden',
            'unavailable' => 'ownSharingUnavailable',
            _ => 'ownSharingCurrent',
          }),
        ),
        if (draft.canGrant && !draft.canPublish) Text(t('sharingScanRequired')),
        if (!draft.selectionKnown && draft.selectedCount > 0)
          Text('${t('ownSharingPreviousSelected')} ${draft.selectedCount}'),
        if (_strategy == 'operationOnly') Text(t('ownSharingOperationHint')),
      ],
    ];
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(t(official ? 'ownSharingTitle' : 'sharingTitle')),
        content: SizedBox(
          width: 560,
          height: math.min(
            MediaQuery.sizeOf(context).height * .5,
            official
                ? 600.0
                : MediaQuery.sizeOf(context).width < 600
                ? 420.0
                : 176.0 + math.min(_page?.options.length ?? 2, 6) * 64,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (official)
                Expanded(
                  flex: _strategy == 'organizationPool' ? 2 : 5,
                  child: SingleChildScrollView(
                    key: const ValueKey('hangar-sharing-description-scroll'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: heading,
                    ),
                  ),
                )
              else
                ...heading,
              if (!official || _strategy == 'organizationPool')
                Expanded(
                  flex: official ? 3 : 1,
                  child: draft == null
                      ? const SizedBox.shrink()
                      : official && _strategy != 'organizationPool'
                      ? const SizedBox.shrink()
                      : rows.isEmpty
                      ? Center(
                          child: Text(
                            t(official ? 'ownSharingEmpty' : 'sharingEmpty'),
                          ),
                        )
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            final name = row.name ?? t('ownSharingMissing');
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _selected.contains(row.reference)
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).dividerColor,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: StarBridgeCheckboxTile(
                                controlKey: ValueKey(
                                  'hangar-share-target-${row.reference}',
                                ),
                                label: name,
                                titleWidget: Text(
                                  name,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                dense: false,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                value: _selected.contains(row.reference),
                                onChanged:
                                    _busy ||
                                        (!_selected.contains(row.reference) &&
                                            (_selected.length >=
                                                    draft.maximumSelected ||
                                                official &&
                                                    (!draft.canPublish ||
                                                        !row.grantable)))
                                    ? null
                                    : (value) => setState(() {
                                        if (value == true) {
                                          _selected.add(row.reference);
                                        } else {
                                          _selected.remove(row.reference);
                                        }
                                      }),
                              ),
                            );
                          },
                        ),
                ),
              if (draft != null &&
                  draft.allowImages &&
                  _selected.isNotEmpty &&
                  (!official ||
                      _strategy == 'organizationPool' && draft.canPublish))
                StarBridgeCheckboxTile(
                  controlKey: const ValueKey('hangar-share-images'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  label: t('sharingImages'),
                  subtitle: t('sharingImagesHint'),
                  value: _includeImages,
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _includeImages = value == true),
                ),
              if (draft != null && official && draft.imageCount > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    t('sharedImageCount')
                        .replaceAll('{count}', '${draft.imageCount}'),
                  ),
                ),
              if (draft != null &&
                  draft.canClearImages &&
                  _editor is OrganizationHangarImageConsentPort)
                StarBridgeActionButton(
                  controlKey: const Key('hangar-sharing-clear-images'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: _busy ? null : (_) => _clearImages(),
                  child: Text(t('clearSharedImages')),
                ),
              if (draft != null &&
                  official &&
                  _strategy == 'organizationPool' &&
                  (_page?.totalOptions ?? 0) > 100)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StarBridgeActionButton(
                      controlKey: const ValueKey('hangar-sharing-previous'),
                      kind: StarBridgeActionKind.quiet,
                      onActivate: _busy || _page!.offset == 0
                          ? null
                          : (_) => _loadPage(_page!.offset - 100),
                      child: Text(t('previous')),
                    ),
                    Text(
                      '${_page!.offset + 1}Ã¢â‚¬â€œ${_page!.offset + rows.length} / ${_page!.totalOptions}',
                    ),
                    StarBridgeActionButton(
                      controlKey: const ValueKey('hangar-sharing-next'),
                      kind: StarBridgeActionKind.quiet,
                      onActivate: _busy || _page!.next == null
                          ? null
                          : (_) => _loadPage(_page!.next!),
                      child: Text(t('next')),
                    ),
                  ],
                ),
              if (draft != null &&
                  (!official || _strategy == 'organizationPool') &&
                  draft.selectionKnown)
                Text(
                  '${t('sharingSelected')} ${_selected.length} / ${draft.maximumSelected}',
                ),
            ],
          ),
        ),
        actions: [
          StarBridgeActionButton(
            controlKey: const Key('hangar-sharing-close'),
            kind: StarBridgeActionKind.quiet,
            onActivate: _busy
                ? null
                : (source) => dismissStarBridgeDialog(
                    context,
                    source: source,
                    result: false,
                  ),
            child: Text(t('close')),
          ),
          if (draft == null && !_invalidated && _error != 'sharingUpgrade')
            StarBridgeActionButton(
              controlKey: const Key('hangar-sharing-refresh'),
              onActivate: _busy ? null : (_) => _load(),
              child: Text(t('refresh')),
            ),
          if (draft != null)
            StarBridgeActionButton(
              controlKey: const Key('hangar-sharing-save'),
              kind: StarBridgeActionKind.primary,
              onActivate: _busy || !_canSave(draft) ? null : (_) => _save(),
              child: Text(
                t(
                  official
                      ? (_strategy == 'notShared'
                            ? 'ownSharingRevoke'
                            : 'ownSharingSave')
                      : _selected.isNotEmpty || _alreadyUnshared(draft)
                      ? 'sharingSave'
                      : draft.explicit
                      ? 'sharingRevoke'
                      : 'sharingSetNone',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
