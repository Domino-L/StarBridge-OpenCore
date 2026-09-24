import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'community_sharing.dart';
import 'community_member_override.dart';
import 'community_member_sharing.dart';
import 'local_privacy_controller.dart';

Future<void> editCommunityMemberVisibility(
  BuildContext context,
  LocalPrivacyController controller,
  CommunitySharingTarget target,
  CommunitySharingScope scope,
) async {
  final epoch = controller.scopeEpoch;
  final draft = controller.draft;
  final result = await showDialog<CommunitySharingScope>(
    context: context,
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
  late final int _epoch = widget.controller.scopeEpoch;
  List<CommunitySharingMember>? _members;
  String _query = '';
  String? _error;
  bool _reading = false;
  bool _invalidated = false;
  Timer? _retry;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_checkOwner);
    unawaited(_read());
  }

  @override
  void dispose() {
    _retry?.cancel();
    widget.controller.removeListener(_checkOwner);
    super.dispose();
  }

  void _checkOwner() {
    if (_invalidated) return;
    if (widget.controller.scopeEpoch != _epoch ||
        !(widget.controller.communityTargets?.communities.any(
              (t) => t.matches(widget.scope),
            ) ??
            false)) {
      _retry?.cancel();
      setState(() {
        _invalidated = true;
        _members = null;
        _error = 'changed';
      });
    }
  }

  Future<void> _read() async {
    if (_reading || _invalidated || !mounted) return;
    setState(() {
      _reading = true;
    });
    try {
      final rows = await widget.controller.readCommunityMembers(widget.scope);
      if (!mounted || _invalidated) return;
      setState(() {
        _members = rows;
        _error = null;
      });
    } catch (error) {
      if (!mounted || _invalidated) return;
      final unavailable =
          error is BridgeClientException &&
          const {
            'host.capability_missing',
            'privacy_publication.member_scopes_unavailable',
          }.contains(error.code);
      setState(() => _error = unavailable ? 'unsupported' : 'retrying');
      if (!unavailable) _retry = Timer(const Duration(seconds: 5), _read);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _set(CommunitySharingMember member, int fields) {
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

  void _reset(CommunitySharingMember member) => setState(() {
    _draft = _draft.copyWith(
      memberOverrides: [...?_draft.memberOverrides]
        ..removeWhere(
          (row) =>
              row.accountId.toLowerCase() == member.accountId.toLowerCase(),
        ),
    );
  });

  Future<void> _convertGroups() async {
    final strings = AppStrings.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('privacy.member.convert')),
        content: Text(strings.text('privacy.member.convertBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.text('privacy.scope.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.text('privacy.member.convert')),
          ),
        ],
      ),
    );
    if (!mounted || _invalidated || accepted != true) return;
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
              TextField(
                key: const Key('privacy-member-search'),
                decoration: InputDecoration(labelText: text('search')),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
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
                      TextButton(
                        onPressed: _members == null || _invalidated
                            ? null
                            : _convertGroups,
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
                            ? const CircularProgressIndicator()
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
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(strings.text('privacy.scope.cancel')),
                  ),
                  FilledButton(
                    key: const Key('privacy-member-confirm'),
                    onPressed:
                        _members == null ||
                            _invalidated ||
                            _draft.visibilityGroupIds.isNotEmpty
                        ? null
                        : () => Navigator.pop(
                            context,
                            _draft.copyWith(
                              memberOverrides: _draft.memberOverrides ?? [],
                              retireGroups: true,
                            ),
                          ),
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
                child: MergeSemantics(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.text('privacy.scope.field.${entry.$2}'),
                        ),
                      ),
                      Switch(
                        key: Key(
                          'privacy-member-${member.accountId}-${entry.$2}',
                        ),
                        value: fields & entry.$1 != 0,
                        onChanged:
                            member.isSelf || _draft.fields & entry.$1 == 0
                            ? null
                            : (value) => _set(
                                member,
                                value
                                    ? requestedFields | entry.$1
                                    : requestedFields & ~entry.$1,
                              ),
                      ),
                    ],
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
                TextButton(
                  onPressed: inherited ? null : () => _reset(member),
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
