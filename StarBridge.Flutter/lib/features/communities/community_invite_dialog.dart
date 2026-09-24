import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../settings/local_privacy_port.dart';
import 'community_admission_controller.dart';
import 'community_invite_port.dart';
import 'community_invite_copy.dart';

class CommunityInviteDialog extends StatefulWidget {
  const CommunityInviteDialog({
    required this.port,
    this.privacy,
    this.example = false,
    this.initialCode,
    super.key,
  });
  final CommunityInvitePort port;
  final bool example;
  final String? initialCode;

  /// Owned by this dialog, never shared with the settings page's editing lease.
  final LocalPrivacyPort? privacy;
  @override
  State<CommunityInviteDialog> createState() => _CommunityInviteDialogState();
}

class _CommunityInviteDialogState extends State<CommunityInviteDialog> {
  late final model = CommunityAdmissionController(widget.port, widget.privacy);
  final code = TextEditingController();
  Timer? timer;
  String t(String key) => inviteText(context, key);
  String p(String key) => AppStrings.of(context).text('privacy.local.$key');
  @override
  void initState() {
    super.initState();
    model.addListener(changed);
    final initial = widget.initialCode;
    if (initial != null) {
      code.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !model.invalidated) unawaited(model.verify(initial));
      });
    }
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  void changed() {
    if (!mounted) return;
    if (model.invalidated) {
      code.clear();
      final route = ModalRoute.of(context);
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    } else {
      setState(() {});
    }
  }

  void close() {
    if (!model.busy) Navigator.pop(context, model.outcome);
  }

  Future<void> join() async {
    await model.join();
    if (mounted && !model.invalidated && model.outcome?.status == 'accepted') {
      Navigator.pop(context, model.outcome);
    }
  }

  Widget card(Widget child) => Material(
    color: context.tokens.surfaces.raised.fill,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(color: context.tokens.surfaces.panel.border),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
  Widget toggle(
    String label,
    bool value,
    ValueChanged<bool>? change, {
    Key? key,
  }) => SwitchListTile(
    key: key,
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
    value: value,
    onChanged: model.busy || model.outcome != null ? null : change,
  );

  @override
  Widget build(BuildContext context) {
    final preview = model.preview;
    final draft = model.draft;
    final unknown = model.outcome?.status == 'unknown';
    final error = unknown
        ? 'outcomeUnknown'
        : model.expired
        ? 'inviteInvalid'
        : model.error;
    final locale = MaterialLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 760,
          height: (MediaQuery.sizeOf(context).height - 72).clamp(300, 880),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('title'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (preview != null)
                            Text(
                              '${preview.name} · ${preview.code}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: t('close'),
                      onPressed: model.busy ? null : close,
                      icon: const StandardIcon(StandardIconSemantic.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.example)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              t('example'),
                              style: TextStyle(
                                color: context.tokens.colors.warning,
                              ),
                            ),
                          ),
                        TextField(
                          controller: code,
                          maxLength: 128,
                          enabled: !model.busy && !unknown,
                          decoration: InputDecoration(labelText: t('code')),
                          onChanged: (_) => model.clearPreview(),
                          onSubmitted: (_) => model.verify(code.text),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            onPressed: model.busy || unknown
                                ? null
                                : () => model.verify(code.text),
                            child: Text(t('verify')),
                          ),
                        ),
                        if (model.busy) const LinearProgressIndicator(),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              t(error),
                              style: TextStyle(
                                color: context.tokens.colors.warning,
                              ),
                            ),
                          ),
                        if (model.savedChoices)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(t('savedChoices')),
                          ),
                        if (model.error == 'privacySaveFailed')
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: model.busy
                                  ? null
                                  : model.reviewSharing,
                              child: Text(t('reloadPrivacy')),
                            ),
                          ),
                        if (preview != null) ...[
                          const SizedBox(height: 12),
                          card(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const StandardIcon(StandardIconSemantic.groups),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        '${preview.name} / ${preview.code}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text('${t('owner')}：${preview.commander}'),
                                Text('${t('members')}：${preview.memberCount}'),
                                Text(
                                  '${t('expires')}：${preview.expiresAt == null ? t('noExpiry') : '${locale.formatMediumDate(preview.expiresAt!.toLocal())} ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(preview.expiresAt!.toLocal()))}'}',
                                ),
                                Text(
                                  '${t('uses')}：${preview.remainingUses < 0 ? t('unlimited') : preview.remainingUses}',
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  t(
                                    preview.alreadyMember
                                        ? 'already'
                                        : preview.membershipConflict
                                        ? 'membershipConflict'
                                        : 'direct',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (model.sharing && draft != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            t('sharing'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(t('scopeWarning')),
                          const SizedBox(height: 8),
                          Text(
                            t('publicationWarning'),
                            style: TextStyle(
                              color: context.tokens.colors.warning,
                            ),
                          ),
                          const SizedBox(height: 12),
                          card(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                toggle(
                                  p('publication'),
                                  draft.publicationEnabled,
                                  (v) => model.edit(
                                    draft.copyWith(publicationEnabled: v),
                                  ),
                                ),
                                const Divider(),
                                Text(
                                  p('audience'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                toggle(
                                  p('allMembers'),
                                  draft.fleetAllMembersCanView,
                                  draft.publicationEnabled
                                      ? (v) => model.edit(
                                          draft.copyWith(
                                            fleetAllMembersCanView: v,
                                          ),
                                        )
                                      : null,
                                ),
                                toggle(
                                  t('administrators'),
                                  draft.fleetAdministratorsCanView,
                                  draft.publicationEnabled &&
                                          !draft.fleetAllMembersCanView
                                      ? (v) => model.edit(
                                          draft.copyWith(
                                            fleetAdministratorsCanView: v,
                                          ),
                                        )
                                      : null,
                                ),
                                Text(
                                  t('groups').replaceAll(
                                    '{count}',
                                    '${draft.fleetVisibilityGroupIds.length}',
                                  ),
                                ),
                                const Divider(),
                                Text(
                                  p('fields'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                for (final field in const {
                                  1: 'presence',
                                  2: 'ship',
                                  4: 'location',
                                  8: 'server',
                                  16: 'events',
                                  32: 'hangar',
                                }.entries)
                                  toggle(
                                    p(field.value),
                                    (draft.fleetFields & field.key) != 0,
                                    draft.publicationEnabled
                                        ? (v) => model.edit(
                                            draft.copyWith(
                                              fleetFields: v
                                                  ? draft.fleetFields |
                                                        field.key
                                                  : draft.fleetFields &
                                                        ~field.key,
                                            ),
                                          )
                                        : null,
                                    key: ValueKey(
                                      'admission-field-${field.key}',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: model.acknowledged,
                            title: Text(
                              t('acknowledge'),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            onChanged: model.busy || model.outcome != null
                                ? null
                                : (v) => model.acknowledge(v == true),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (model.busy) Text(t('working')),
                    TextButton(
                      onPressed: model.busy ? null : close,
                      child: Text(t(unknown ? 'close' : 'cancel')),
                    ),
                    if (preview != null &&
                        !preview.alreadyMember &&
                        !preview.membershipConflict &&
                        !unknown &&
                        model.outcome == null)
                      FilledButton(
                        onPressed: model.sharing
                            ? (model.canJoin ? join : null)
                            : model.busy || model.expired
                            ? null
                            : model.reviewSharing,
                        child: Text(t(model.sharing ? 'join' : 'review')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    code.dispose();
    model.removeListener(changed);
    model.dispose();
    super.dispose();
  }
}
