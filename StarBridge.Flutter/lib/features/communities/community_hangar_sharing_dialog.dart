import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'community_hangar_sharing_port.dart';
import 'communities_module.dart';
import 'community_ships_copy.dart';

class CommunityHangarSharingDialog extends StatefulWidget {
  const CommunityHangarSharingDialog({required this.port, super.key});
  final CommunityHangarSharingPort port;
  @override
  State<CommunityHangarSharingDialog> createState() => _SharingState();
}

class _SharingState extends State<CommunityHangarSharingDialog> {
  CommunityHangarSharing? _draft;
  final _selected = <String>{};
  late final StreamSubscription<void> _subscription;
  bool _busy = false, _invalidated = false;
  String? _error;
  int _generation = 0;
  String t(String key) => communityShipsText(context, key);

  @override
  void initState() {
    super.initState();
    _subscription = widget.port.invalidations.listen((_) {
      if (!mounted) return;
      _generation++;
      setState(() {
        _draft = null;
        _selected.clear();
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

  Future<void> _load() async {
    if (_busy || _invalidated) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _draft = null;
      _selected.clear();
    });
    try {
      final draft = await widget.port.readHangarSharing();
      if (!mounted || generation != _generation) return;
      setState(() {
        _draft = draft;
        _selected.addAll(
          draft.options.where((r) => r.selected).map((r) => r.targetRef),
        );
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
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    CommunityHangarSharingOutcome result;
    try {
      result = await widget.port.saveHangarSharing(
        draft.editRef,
        _selected.toList(),
      );
    } catch (_) {
      result = const CommunityHangarSharingOutcome('unknown');
    }
    if (!mounted || generation != _generation) return;
    if (result.status == 'accepted') {
      Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(t('sharingTitle')),
        content: SizedBox(
          width: 560,
          height: math.min(
            MediaQuery.sizeOf(context).height * .5,
            MediaQuery.sizeOf(context).width < 600
                ? 420.0
                : 128.0 + math.min(draft?.options.length ?? 2, 6) * 64,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('sharingScope')),
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    t(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (draft != null && !draft.usesExplicitTargets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(t('sharingLegacy')),
                ),
              Expanded(
                child: draft == null
                    ? const SizedBox.shrink()
                    : draft.options.isEmpty
                    ? Center(child: Text(t('sharingEmpty')))
                    : ListView.separated(
                        itemCount: draft.options.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final row = draft.options[index];
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _selected.contains(row.targetRef)
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).dividerColor,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: CheckboxListTile(
                              title: Text(
                                row.name,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              value: _selected.contains(row.targetRef),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged:
                                  _busy ||
                                      (!_selected.contains(row.targetRef) &&
                                          _selected.length >=
                                              CommunityHangarSharing
                                                  .maximumTargets)
                                  ? null
                                  : (value) => setState(() {
                                      if (value == true) {
                                        _selected.add(row.targetRef);
                                      } else {
                                        _selected.remove(row.targetRef);
                                      }
                                    }),
                            ),
                          );
                        },
                      ),
              ),
              if (draft != null)
                Text(
                  '${t('sharingSelected')} ${_selected.length} / ${CommunityHangarSharing.maximumTargets}',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(t('close')),
          ),
          if (draft == null && !_invalidated && _error != 'sharingUpgrade')
            OutlinedButton(
              onPressed: _busy ? null : _load,
              child: Text(t('refresh')),
            ),
          if (draft != null)
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(
                t(_selected.isEmpty ? 'sharingRevoke' : 'sharingSave'),
              ),
            ),
        ],
      ),
    );
  }
}
