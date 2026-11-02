import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import 'community_sharing.dart';
import 'community_member_override.dart';
import 'community_member_sharing.dart';
import 'local_privacy_controller.dart';

Future<void> editCommunityMemberVisibility(
  BuildContext context,
  LocalPrivacyController controller,
  CommunitySharingTarget target,
  CommunitySharingScope scope, {
  InteractionSource? source,
}) async {
  final epoch = controller.scopeEpoch;
  final draft = controller.draft;
  final result = await showStarBridgeDialog<CommunitySharingScope>(
    context,
    source: source,
    builder: (_) => CommunityMemberVisibilityDialog(
      controller: controller,
      target: target,
      scope: scope,
    ),
  );
  if (result != null &&
      context.mounted &&
      controller.scopeEpoch == epoch &&
      identical(controller.draft, draft) &&
      controller.canEdit &&
      (controller.communityTargets?.communities.any(
            (row) => row.matches(scope),
          ) ??
          false)) {
    controller.editCommunity(result);
  }
}

class CommunityMemberVisibilityDialog extends StatefulWidget {
  const CommunityMemberVisibilityDialog({
    required this.controller,
    required this.target,
    required this.scope,
    super.key,
  });
  final LocalPrivacyController controller;
  final CommunitySharingTarget target;
  final CommunitySharingScope scope;
  @override
  State<CommunityMemberVisibilityDialog> createState() =>
      _CommunityMemberVisibilityDialogState();
}

class _CommunityMemberVisibilityDialogState
    extends State<CommunityMemberVisibilityDialog> {
  late CommunitySharingScope _draft = widget.scope;
  late int _epoch;
  late Object? _parentDraft;
  List<CommunitySharingMember>? _members;
  String _query = '';
  String? _error;
  bool _reading = false;
  bool _invalidated = false;
  Timer? _retry;
  int _readGeneration = 0, _searchEpoch = 0;
  bool _closing = false;
  StarBridgeDialogRoute<bool>? _conversion;
  bool get _editable => !_invalidated && !_closing && widget.controller.canEdit;
  void _retireConversion() {
    final route = _conversion;
    _conversion = null;
    retireStarBridgeDialog(route);
  }

  @override
  void initState() {
    super.initState();
    _epoch = widget.controller.scopeEpoch;
    _parentDraft = widget.controller.draft;
    widget.controller.addListener(_checkOwner);
    unawaited(_read());
  }

  @override
  void dispose() {
    _retry?.cancel();
    _readGeneration++;
    _retireConversion();
    widget.controller.removeListener(_checkOwner);
    super.dispose();
  }

  @override
  void didUpdateWidget(CommunityMemberVisibilityDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.scope.code.toLowerCase() != widget.scope.code.toLowerCase() ||
        oldWidget.scope.joinedAt != widget.scope.joinedAt) {
      oldWidget.controller.removeListener(_checkOwner);
      widget.controller.addListener(_checkOwner);
      _retry?.cancel();
      _retireConversion();
      _readGeneration++;
      _searchEpoch++;
      _draft = widget.scope;
      _epoch = widget.controller.scopeEpoch;
      _parentDraft = widget.controller.draft;
      _members = null;
      _query = '';
      _error = null;
      _reading = _invalidated = _closing = false;
      unawaited(_read());
    }
  }

  void _checkOwner() {
    if (_invalidated) return;
    final ownerChanged =
        widget.controller.scopeEpoch != _epoch ||
        !(widget.controller.communityTargets?.communities.any(
              (t) => t.matches(widget.scope),
            ) ??
            false);
    // Keep same-owner content through a normal handoff, but never suppress
    // account/membership invalidation just because an exit is in progress.
    if (_closing && !ownerChanged) return;
    if (ownerChanged || !identical(widget.controller.draft, _parentDraft)) {
      _retry?.cancel();
      _readGeneration++;
      _retireConversion();
      setState(() {
        _invalidated = true;
        _members = null;
        _error = 'changed';
        _reading = false;
        _query = '';
        _searchEpoch++;
      });
    } else {
      if (!_editable) _retireConversion();
      setState(() {});
    }
  }

  Future<void> _read() async {
    if (_reading || _invalidated || _closing || !mounted) return;
    final generation = ++_readGeneration;
    final owner = widget.controller, scope = widget.scope;
    setState(() {
      _reading = true;
    });
    try {
      final rows = await owner.readCommunityMembers(scope);
      if (!mounted ||
          _invalidated ||
          _closing ||
          generation != _readGeneration) {
        return;
      }
      setState(() {
        _members = rows;
        _error = null;
      });
    } catch (error) {
      if (!mounted ||
          _invalidated ||
          _closing ||
          generation != _readGeneration) {
        return;
      }
      final unavailable =
          error is BridgeClientException &&
          const {
            'host.capability_missing',
            'privacy_publication.member_scopes_unavailable',
          }.contains(error.code);
      setState(() => _error = unavailable ? 'unsupported' : 'retrying');
      if (!unavailable) _retry = Timer(const Duration(seconds: 5), _read);
    } finally {
      if (mounted && generation == _readGeneration) {
        setState(() => _reading = false);
      }
    }
  }

  void _set(CommunitySharingMember member, int fields) {
    if (!_editable) return;
    final overrides = [...?_draft.memberOverrides]
      ..removeWhere(
        (row) => row.accountId.toLowerCase() == member.accountId.toLowerCase(),
      );
    if (overrides.length >= 1000) {
      setState(() => _error = 'limit');
      return;
    }
    overrides.add(
      CommunityMemberOverride(
        accountId: member.accountId,
        joinedAt: member.joinedAt,
        fields: fields,
      ),
    );
    setState(() => _draft = _draft.copyWith(memberOverrides: overrides));
  }

  void _reset(CommunitySharingMember member) {
    if (!_editable) return;
    setState(() {
      _draft = _draft.copyWith(
        memberOverrides: [...?_draft.memberOverrides]
          ..removeWhere(
            (row) =>
                row.accountId.toLowerCase() == member.accountId.toLowerCase(),
          ),
      );
    });
  }

  Future<void> _convertGroups() async {
    if (!_editable || _members == null || _conversion != null) return;
    final generation = _readGeneration;
    final strings = AppStrings.of(context);
    late StarBridgeDialogRoute<bool> route;
    final accepted = await showStarBridgeDialog<bool>(
      context,
      source: currentStarBridgeActivationSource,
      onRouteCreated: (value) => _conversion = route = value,
      builder: (context) => AlertDialog(
        title: Text(strings.text('privacy.member.convert')),
        content: Text(strings.text('privacy.member.convertBody')),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('privacy-member-convert-cancel'),
            onActivate: (source) {
              if (!_editable ||
                  generation != _readGeneration ||
                  !route.isCurrent) {
                return;
              }
              dismissStarBridgeDialog(context, result: false, source: source);
            },
            child: Text(strings.text('privacy.scope.cancel')),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            controlKey: const Key('privacy-member-convert-confirm'),
            onActivate: (source) {
              if (!_editable ||
                  generation != _readGeneration ||
                  !route.isCurrent) {
                return;
              }
              dismissStarBridgeDialog(context, result: true, source: source);
            },
            child: Text(strings.text('privacy.member.convert')),
          ),
        ],
      ),
    );
    if (_conversion == route) _conversion = null;
    if (!mounted ||
        !_editable ||
        generation != _readGeneration ||
        accepted != true) {
      return;
    }
    final overrides = [...?_draft.memberOverrides];
    for (final member in _members!) {
      if (member.legacyGroupFields == 0 ||
          member.defaultCanView ||
          member.isSelf ||
          member.overrideIn(_draft) != null) {
        continue;
      }
      overrides.removeWhere(
        (row) => row.accountId.toLowerCase() == member.accountId.toLowerCase(),
      );
      overrides.add(
        CommunityMemberOverride(
          accountId: member.accountId,
          joinedAt: member.joinedAt,
          fields: member.legacyGroupFields,
        ),
      );
    }
    if (overrides.length > 1000) {
      setState(() => _error = 'limit');
      return;
    }
    setState(
      () => _draft = _draft.copyWith(
        memberOverrides: overrides,
        retireGroups: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String text(String key) => strings.text('privacy.member.$key');
    final rows = _members
        ?.where(
          (row) => '${row.name} ${row.handle}'.toLowerCase().contains(_query),
        )
        .toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.target.name} · ${text('title')}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(text('body')),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: ValueKey(_searchEpoch),
                child: StarBridgeFieldFrame(
                  enabled: _editable,
                  builder: (context, focus) => TextField(
                    key: const Key('privacy-member-search'),
                    decoration: InputDecoration(labelText: text('search')),
                    focusNode: focus,
                    enabled: _editable,
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(text(_error!)),
                ),
              if (_draft.visibilityGroupIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text('legacy')),
                      StarBridgeActionButton(
                        kind: StarBridgeActionKind.quiet,
                        controlKey: const Key('privacy-member-convert'),
                        onActivate: _members == null || !_editable
                            ? null
                            : (_) => unawaited(_convertGroups()),
                        child: Text(text('convert')),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: rows == null
                    ? Center(
                        child: _reading
                            ? _MemberWaiting(
                                source: resolveStarBridgeInitialReadSource(
                                  context,
                                  InteractionSource.programmatic,
                                ),
                              )
                            : Text(text(_error ?? 'retrying')),
                      )
                    : rows.isEmpty
                    ? Center(child: Text(text('empty')))
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _memberRow(context, rows[index]),
                      ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    controlKey: const Key('privacy-member-cancel'),
                    onActivate: (source) {
                      _closing = true;
                      dismissStarBridgeDialog(context, source: source);
                    },
                    child: Text(strings.text('privacy.scope.cancel')),
                  ),
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.primary,
                    controlKey: const Key('privacy-member-confirm'),
                    onActivate:
                        _members == null ||
                            !_editable ||
                            _draft.visibilityGroupIds.isNotEmpty
                        ? null
                        : (source) {
                            _closing = true;
                            dismissStarBridgeDialog(
                              context,
                              source: source,
                              result: _draft.copyWith(
                                memberOverrides: _draft.memberOverrides ?? [],
                                retireGroups: true,
                              ),
                            );
                          },
                    child: Text(text('confirm')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberRow(BuildContext context, CommunitySharingMember member) {
    final strings = AppStrings.of(context);
    final inherited = member.overrideIn(_draft) == null;
    final fields = member.effectiveFields(_draft);
    final requestedFields =
        member.overrideIn(_draft)?.fields ?? (member.defaultCanView ? 15 : 0);
    final controls = LayoutBuilder(
      builder: (context, constraints) {
        final minimum = 180 * MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = constraints.maxWidth >= minimum * 4 + 36
            ? 4
            : constraints.maxWidth >= minimum * 2 + 12
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          children: [
            for (final entry in const [
              (1, 'presence'),
              (2, 'ship'),
              (4, 'location'),
              (8, 'server'),
            ])
              SizedBox(
                width: width,
                child: StarBridgeSwitch.tile(
                  label: strings.text('privacy.scope.field.${entry.$2}'),
                  rowBuilder: (control) => Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.text('privacy.scope.field.${entry.$2}'),
                        ),
                      ),
                      control,
                    ],
                  ),
                  controlKey: Key(
                    'privacy-member-${member.accountId}-${entry.$2}',
                  ),
                  value: fields & entry.$1 != 0,
                  onChanged:
                      !_editable ||
                          member.isSelf ||
                          _draft.fields & entry.$1 == 0
                      ? null
                      : (value) => _set(
                          member,
                          value
                              ? requestedFields | entry.$1
                              : requestedFields & ~entry.$1,
                        ),
                ),
              ),
          ],
        );
      },
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${member.name}  @${member.handle}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (member.isSelf)
                Text(strings.text('privacy.member.self'))
              else
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: Key('privacy-member-${member.accountId}-reset'),
                  onActivate: inherited || !_editable
                      ? null
                      : (_) => _reset(member),
                  child: Text(
                    strings.text(
                      inherited
                          ? 'privacy.member.inherited'
                          : 'privacy.member.reset',
                    ),
                  ),
                ),
            ],
          ),
          controls,
        ],
      ),
    );
  }
}

class _MemberWaiting extends StatelessWidget {
  const _MemberWaiting({required this.source});
  final InteractionSource source;
  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        return InteractionScope(
          data: data.copyWith(
            reduceMotion:
                data.reduceMotion || source == InteractionSource.keyboard,
          ),
          child: const SuiteProgressBar(
            value: null,
            phase: ProgressPhase.running,
          ),
        );
      },
    ),
  );
}
