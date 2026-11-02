import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../common/social_read_activity.dart';
import 'community_profile_controller.dart';
import 'community_profile_form_sections.dart';

/// Pure read/save/image activity presentation; the dialog owns every binding.
final class CommunityProfileDialogActivity {
  const CommunityProfileDialogActivity({
    required this.model,
    required this.reading,
    required this.saving,
    required this.text,
  });
  final CommunityProfileController model;
  final SocialReadActivityBinding reading, saving;
  final String Function(String) text;

  Widget readMarker(String key, {bool circular = false}) => KeyedSubtree(
    key: ValueKey(('profile-read', reading.revision)),
    child: SocialReadActivity(
      key: ValueKey(key),
      source: reading.source,
      opening: reading.opening,
      label: text('loading'),
      height: 4,
      circularStandard: circular,
    ),
  );
  Widget? footerActivity({
    required bool choosing,
    required bool dialogOpen,
    required ValueGetter<InteractionSource>? imageSource,
    required int imageRevision,
  }) {
    if (model.submitting) {
      return KeyedSubtree(
        key: ValueKey(('profile-save', saving.revision)),
        child: SocialReadActivity(
          key: const ValueKey('profile-save-activity'),
          source: saving.source,
          opening: false,
          label: text('saving'),
          height: 4,
        ),
      );
    }
    if (!choosing || dialogOpen) return null;
    final source = imageSource?.call() ?? InteractionSource.programmatic;
    return SocialReadActivity(
      key: ValueKey(('profile-image-activity', imageRevision, source)),
      source: source,
      opening: false,
      label: text('pickLogo'),
      height: 4,
    );
  }

  Widget? optionsActivity({
    required bool busy,
    required int revision,
    required bool dialogOpen,
    required InteractionSource source,
    required bool opening,
  }) => !busy || model.invalidated
      ? null
      : KeyedSubtree(
          key: ValueKey(('profile-options', revision, dialogOpen)),
          child: SocialReadActivity(
            key: const ValueKey('profile-options-activity'),
            source: !dialogOpen ? source : InteractionSource.programmatic,
            opening: !dialogOpen && opening,
            label: text('loadingOptions'),
            height: 4,
          ),
        );

  Widget logoActivity({
    required int epoch,
    required bool dialogOpen,
    required InteractionSource source,
    required bool opening,
  }) => KeyedSubtree(
    key: ValueKey(('profile-logo', epoch, dialogOpen)),
    child: SocialReadActivity(
      key: const ValueKey('profile-logo-activity'),
      source: !dialogOpen ? source : InteractionSource.programmatic,
      opening: !dialogOpen && opening,
      label: text('loadingLogo'),
      height: 2,
      circularStandard: true,
      circularSize: 24,
      circularStrokeWidth: 2,
    ),
  );
}

/// Builds the original confirmation contents; the caller retains route ownership.
Widget communityProfileConfirmation({
  required String Function(String) text,
  required String title,
  required String body,
  required String action,
}) => Builder(
  builder: (dialogContext) => AlertDialog(
    title: Text(text(title)),
    content: Text(text(body)),
    actions: [
      StarBridgeActionButton(
        kind: StarBridgeActionKind.quiet,
        controlKey: const Key('profile-confirm-cancel'),
        onActivate: (source) => dismissStarBridgeDialog(
          dialogContext,
          source: source,
          result: false,
        ),
        child: Text(text('continue')),
      ),
      StarBridgeActionButton(
        kind: StarBridgeActionKind.primary,
        controlKey: const Key('profile-confirm-accept'),
        onActivate: (source) => dismissStarBridgeDialog(
          dialogContext,
          source: source,
          result: true,
        ),
        child: Text(text(action)),
      ),
    ],
  ),
);

Widget communityProfileLeaveConfirmation({
  required String Function(String) text,
  required CommunityProfileController model,
}) => Builder(
  builder: (dialogContext) => AlertDialog(
    title: Text(text('leaveTitle')),
    content: Text(
      text(model.needsRefresh ? model.error ?? 'outcomeUnknown' : 'leaveBody'),
    ),
    actions: [
      StarBridgeActionButton(
        kind: StarBridgeActionKind.quiet,
        controlKey: const Key('profile-leave-stay'),
        onActivate: (source) => dismissStarBridgeDialog(
          dialogContext,
          source: source,
          result: 'stay',
        ),
        child: Text(text('continue')),
      ),
      StarBridgeActionButton(
        kind: StarBridgeActionKind.quiet,
        controlKey: const Key('profile-leave-discard'),
        onActivate: (source) => dismissStarBridgeDialog(
          dialogContext,
          source: source,
          result: 'discard',
        ),
        child: Text(text('discard')),
      ),
      if (!model.needsRefresh)
        StarBridgeActionButton(
          kind: StarBridgeActionKind.primary,
          controlKey: const Key('profile-leave-save'),
          onActivate: (source) => dismissStarBridgeDialog(
            dialogContext,
            source: source,
            result: 'save',
          ),
          child: Text(text('save')),
        ),
    ],
  ),
);

Widget communityProfileInitialRead({
  required bool loading,
  required Widget Function() loadingIndicator,
  required Future<void> Function() onRetry,
  required String Function(String) text,
}) => Expanded(
  child: Center(
    child: loading
        ? SizedBox(
            width: 160,
            height: 40,
            child: Center(child: loadingIndicator()),
          )
        : StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('profile-read-retry'),
            onActivate: (_) => onRetry(),
            child: Text(text('reload')),
          ),
  ),
);

/// Shares the original form layout without taking ownership of its draft.
List<Widget> communityProfileFormContent({
  required CommunityProfileFormSections sections,
  required bool embedded,
  required int section,
  required GlobalKey<FormState> form,
  required ScrollController scroll,
  required List<GlobalKey> anchors,
  required ValueChanged<int>? onSectionChanged,
}) {
  String t(String key) => sections.t(key);
  return [
    const SizedBox(height: 12),
    if (!embedded)
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < 4; i++)
            StarBridgeChoiceChip(
              controlKey: ValueKey('profile-tab-$i'),
              label: t(['basic', 'discovery', 'schedule', 'contacts'][i]),
              selected: section == i,
              onSelected: onSectionChanged == null
                  ? null
                  : (_) => onSectionChanged(i),
            ),
        ],
      ),
    const SizedBox(height: 16),
    Expanded(
      child: Form(
        key: form,
        child: SingleChildScrollView(
          controller: embedded ? scroll : null,
          // Desktop scrollbars paint over the viewport. Keep
          // their hit area clear of switches and dropdowns.
          padding: embedded ? const EdgeInsetsDirectional.only(end: 16) : null,
          key: embedded
              ? const ValueKey('profile-continuous-scroll')
              : ValueKey('profile-section-$section'),
          child: embedded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sections.continuousSection(0, anchors[0], sections.basic),
                    if (sections.model.profile!.canEditProfile) ...[
                      sections.continuousSection(
                        1,
                        anchors[1],
                        sections.discovery,
                      ),
                      sections.continuousSection(
                        2,
                        anchors[2],
                        sections.schedule,
                      ),
                      sections.continuousSection(
                        3,
                        anchors[3],
                        sections.contacts,
                      ),
                    ],
                  ],
                )
              : switch (section) {
                  0 => sections.basic,
                  1 => sections.discovery,
                  2 => sections.schedule,
                  _ => sections.contacts,
                },
        ),
      ),
    ),
  ];
}
