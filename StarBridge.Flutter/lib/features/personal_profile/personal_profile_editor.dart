import 'dart:async';

import 'package:flutter/material.dart';

import '../common/user_avatar_menu.dart';

import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

import '../../app/legal/cig_fankit_notice.dart';
import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_avatar.dart';
import '../account/account_avatar_editor.dart';
import 'personal_profile_models.dart';
import 'personal_profile_draft.dart';
import 'personal_profile_playstyle_editor.dart';
import 'personal_profile_schedule_editor.dart';
import 'personal_profile_wallpaper_catalog.dart';
import '../common/callsign_rules.dart';

class PersonalProfileEditorPanel extends StatefulWidget {
  const PersonalProfileEditorPanel({
    required this.projection,
    required this.onSave,
    required this.onCancel,
    required this.onSaved,
    required this.moduleLayout,
    required this.onWallpaperChanged,
    this.initialDraft,
    this.ownerRequiresReload,
    this.achievementShowcase,
    super.key,
  });

  final PersonalProfileProjection projection;
  final Future<PersonalProfileActionResult> Function(PersonalProfileEdit edit)
  onSave;
  final VoidCallback onCancel;
  final VoidCallback onSaved;
  final List<PersonalProfileModuleLayoutItem> moduleLayout;
  final ValueChanged<String> onWallpaperChanged;
  final PersonalProfileEditorDraft? initialDraft;
  final bool? ownerRequiresReload;
  final List<String>? achievementShowcase; // The page's picks draft.

  @override
  State<PersonalProfileEditorPanel> createState() =>
      PersonalProfileEditorPanelState();
}

class PersonalProfileEditorPanelState
    extends State<PersonalProfileEditorPanel> {
  final _positionsKey = GlobalKey<PersonalProfilePlayStyleEditorState>();
  void editPositions() {
    if (_saving) return;
    _positionsKey.currentState?.openAll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _positionsKey.currentContext;
      if (mounted && target != null) Scrollable.ensureVisible(target);
    });
  }

  late final TextEditingController _callSignController;

  // An account callsign is the one SCM callsign (11-15): legacy rules, at most 10.
  // Only a changed name must follow them; an existing longer name may stay.
  bool get _callSignTooLong =>
      widget.projection.local?.accountCallSign == true &&
      _callSignController.text.trim() != widget.projection.callSign.trim() &&
      !CallsignRules.valid(_callSignController.text);
  late final TextEditingController _aboutController;
  late int _avatarStyle;
  // The current editor retains avatar styles from restored drafts.
  void restoreAvatarStyle(int style) => setState(() => _avatarStyle = style);

  late String _wallpaperId;
  late PersonalProfileVisibility _visibility;
  bool _sending = false;
  bool get _saving =>
      _sending ||
      widget.projection.operation == PersonalProfileOperation.saving;
  bool _requiresReload = false;
  final _formKey = GlobalKey<FormState>();
  PersonalProfilePlayStyle? _playStyle;
  PersonalProfileSchedule? _schedule;
  bool _validationError = false;
  StarBridgeDialogRoute<String>? _backgroundRoute;

  @override
  void initState() {
    super.initState();
    _callSignController = TextEditingController(
      text: widget.projection.callSign,
    );
    _aboutController = TextEditingController(text: widget.projection.about);
    _avatarStyle = widget.projection.avatarStyle;
    _wallpaperId = widget.projection.wallpaperId;
    _visibility = widget.projection.visibility;
    if (widget.initialDraft case final draft?) {
      final edit = draft.edit;
      _callSignController.text = edit.callSign;
      _aboutController.text = edit.about;
      restoreAvatarStyle(edit.avatarStyle);
      _wallpaperId = edit.wallpaperId;
      _visibility = edit.visibility;
      _playStyle = edit.playStyle;
      _schedule = edit.schedule;
      _requiresReload = draft.requiresReload;
      _validationError = draft.validationError;
    }
  }

  PersonalProfileEditorDraft captureDraft() => PersonalProfileEditorDraft(
    PersonalProfileEdit(
      callSign: _callSignController.text,
      about: _aboutController.text,
      avatarStyle: _avatarStyle,
      wallpaperId: _wallpaperId,
      visibility: _visibility,
      moduleLayout: List.unmodifiable(widget.moduleLayout),
      playStyle: _playStyle,
      schedule: _schedule,
      achievementShowcase: widget.achievementShowcase,
    ),
    requiresReload: _requiresReload || _saving,
    validationError: _validationError,
  );
  @override
  void dispose() {
    retireStarBridgeDialog(_backgroundRoute, includeClosing: true);
    _callSignController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Plan A (11-05): avatar and background share one line, and their
          // notes are one sentence. Every control is still shown.
          Wrap(
            spacing: tokens.space.xl,
            runSpacing: tokens.space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: tokens.space.sm,
                runSpacing: tokens.space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    strings.text('profile.edit.avatar'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  UserAvatarMenu(
                    name: widget.projection.callSign,
                    isSelf: true,
                    child: PersonalProfileAvatar(
                      key: const Key('profile-current-avatar'),
                      callSign: widget.projection.callSign,
                      styleIndex: _avatarStyle,
                      imageData: widget.projection.avatarImageData,
                      size: tokens.density.controlHeight,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: const AccountAvatarEditor(),
                  ),
                ],
              ),
              Wrap(
                spacing: tokens.space.sm,
                runSpacing: tokens.space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    strings.text('profile.edit.wallpaper'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  _CurrentBackgroundSelection(
                    preset: PersonalProfileWallpaperCatalog.resolve(
                      _wallpaperId,
                    ),
                    onChoose: _saving ? null : _chooseBackground,
                  ),
                  const CigFankitNoticeButton(
                    key: Key('profile-editor-cig-fankit-notice'),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            [
              strings.text('profile.edit.wallpaperDescription'),
              strings.text('profile.edit.wallpaperFankitNotice'),
            ].join(strings.locale.languageCode == 'en' ? ' ' : ''),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.lg),
          if (widget.projection.local == null)
            Container(
              padding: EdgeInsetsDirectional.fromSTEB(
                tokens.space.md,
                tokens.space.sm,
                tokens.space.sm,
                tokens.space.sm,
              ),
              decoration: BoxDecoration(
                color: tokens.surfaces.status.fill,
                borderRadius: tokens.shape.small,
                border: Border.all(
                  color: tokens.surfaces.status.border,
                  width: tokens.stroke.hairline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    strings.text('profile.edit.visibility'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  SizedBox(height: tokens.space.xs),
                  StarBridgeSelectFormField<PersonalProfileVisibility>(
                    identity: 'profile-visibility',
                    controlKey: const Key('profile-visibility-trigger'),
                    semanticLabel: strings.text('profile.edit.visibility'),
                    key: const Key('profile-visibility-selector'),
                    initialValue: _visibility,
                    isExpanded: true,
                    items: [
                      for (final visibility
                          in PersonalProfileVisibility.values.where(
                            (v) =>
                                v !=
                                PersonalProfileVisibility
                                    .friendsFleetAndOrganizations,
                          ))
                        DropdownMenuItem(
                          key: Key(_visibilityKey(visibility)),
                          value: visibility,
                          child: Text(strings.text(visibility.labelKey)),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (visibility) {
                            if (visibility != null) {
                              setState(() => _visibility = visibility);
                            }
                          },
                  ),
                  SizedBox(height: tokens.space.xs),
                  Text(
                    strings.text(_visibilityDescriptionKey(_visibility)),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ],
              ),
            ),
          SizedBox(height: tokens.space.lg),
          StarBridgeFieldFrame(
            enabled: !_saving,
            builder: (_, focus) => TextField(
              key: const Key('profile-call-sign-field'),
              focusNode: focus,
              controller: _callSignController,
              maxLength: 32,
              decoration: InputDecoration(
                labelText: strings.text('profile.edit.callSign'),
                // The game ID line joins the call sign note (plan A).
                helperText: [
                  if (widget.projection.local?.accountCallSign == true)
                    strings.text('profile.callsign.hint'),
                  '${strings.text('profile.edit.gameHandle')} '
                      '@${widget.projection.gameHandle}',
                ].join(' · '),
                helperMaxLines: 3,
                errorText: _callSignTooLong
                    ? strings.text('profile.callsign.tooLong')
                    : null,
                // Account callsigns count with the legacy rule (CJK counts 2).
                counterText: widget.projection.local?.accountCallSign == true
                    ? '${CallsignRules.weight(_callSignController.text.trim())}'
                          '/${CallsignRules.maxWeight}'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(height: tokens.space.sm),
          StarBridgeFieldFrame(
            enabled: !_saving,
            builder: (_, focus) => TextField(
              key: const Key('profile-about-field'),
              focusNode: focus,
              controller: _aboutController,
              minLines: 2,
              maxLines: 7,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: strings.text('profile.edit.about'),
              ),
            ),
          ),
          if (widget.projection.local case final local?) ...[
            SizedBox(height: tokens.space.lg),
            PersonalProfilePlayStyleEditor(
              key: _positionsKey,
              initial: _playStyle,
              projection: widget.projection,
              enabled: !_saving,
              onChanged: (value) => _playStyle = value,
            ),
            PersonalProfileScheduleEditor(
              initiallyChanged: _schedule != null,
              initial:
                  _schedule ??
                  PersonalProfileSchedule(
                    timeZoneId: widget.projection.timeZoneLabel,
                    rhythm: widget.projection.activityRhythm,
                    windows: widget.projection.availabilityWindows,
                  ),
              timeZones: local.timeZones,
              enabled: !_saving,
              onChanged: (value) => _schedule = value,
            ),
          ],
        ],
      ),
    );
    final actions = Wrap(
      spacing: tokens.space.sm,
      runSpacing: tokens.space.sm,
      children: [
        StarBridgeActionButton(
          controlKey: const Key('profile-edit-cancel'),
          onActivate: _saving ? null : (_) => widget.onCancel(),
          child: Text(strings.text('common.cancel')),
        ),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.primary,
          controlKey: const Key('profile-save'),
          onActivate:
              _saving ||
                  (widget.ownerRequiresReload ?? _requiresReload) ||
                  _callSignController.text.trim().isEmpty ||
                  _callSignTooLong
              ? null
              : (_) => _save(),
          child: Text(
            strings.text(
              _saving
                  ? 'profile.edit.saving'
                  : widget.projection.local != null
                  ? 'profile.local.save'
                  : 'common.save',
            ),
          ),
        ),
      ],
    );
    return StarBridgeSurface(
      key: const Key('profile-editor-panel'),
      role: SurfaceRole.raised,
      padding: EdgeInsets.all(tokens.space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Plan A: the note sits on the title line.
              final title = Wrap(
                spacing: tokens.space.md,
                runSpacing: tokens.space.xxs,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text(
                    strings.text('profile.edit.title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    strings.text(
                      widget.projection.local?.localOnlyEdits == true
                          ? 'profile.local.onlySaved'
                          : widget.projection.local != null
                          ? widget.projection.local!.accountCallSign
                                ? 'profile.local.accountDescription'
                                : 'profile.local.description'
                          : 'profile.edit.description',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ],
              );
              if (constraints.maxWidth < 680) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    SizedBox(height: tokens.space.md),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: actions,
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  SizedBox(width: tokens.space.lg),
                  actions,
                ],
              );
            },
          ),
          SizedBox(height: tokens.space.lg),
          Divider(
            height: tokens.stroke.hairline,
            color: tokens.surfaces.raised.border,
          ),
          SizedBox(height: tokens.space.lg),
          if (widget.projection.failureKey case final failure?) ...[
            Text(
              strings.text(failure),
              key: const Key('profile-save-error'),
              style: TextStyle(color: tokens.colors.warning),
            ),
            SizedBox(height: tokens.space.md),
          ],
          if (_validationError) ...[
            Text(
              strings.text('profile.collab.invalid'),
              key: const Key('profile-validation-error'),
              style: TextStyle(color: tokens.colors.warning),
            ),
            SizedBox(height: tokens.space.md),
          ],
          ExcludeFocus(
            excluding: _saving,
            child: AbsorbPointer(
              absorbing: _saving,
              child: Form(key: _formKey, child: form),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || (widget.ownerRequiresReload ?? _requiresReload)) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _validationError = true);
      return;
    }
    setState(() {
      _sending = true;
      _validationError = false;
    });
    final result = await widget.onSave(
      PersonalProfileEdit(
        callSign: _callSignController.text,
        about: _aboutController.text,
        avatarStyle: _avatarStyle,
        wallpaperId: _wallpaperId,
        visibility: _visibility,
        moduleLayout: widget.moduleLayout,
        playStyle: _playStyle,
        schedule: _schedule,
        achievementShowcase: widget.achievementShowcase,
      ),
    );
    if (!mounted) {
      return;
    }
    if (result.outcome == PersonalProfileActionOutcome.completed) {
      widget.onSaved();
      return;
    }
    setState(() {
      _sending = false;
      _requiresReload = result.requiresReload;
    });
  }

  Future<void> _chooseBackground(InteractionSource source) async {
    final selectedId = await showStarBridgeDialog<String>(
      context,
      source: source,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      onRouteCreated: (route) {
        _backgroundRoute = route;
        unawaited(
          route.completed.then((_) {
            if (identical(_backgroundRoute, route)) _backgroundRoute = null;
          }),
        );
      },
      builder: (context) => Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: SafeArea(
          child: _BackgroundPickerDialog(selectedId: _wallpaperId),
        ),
      ),
    );
    if (!mounted || selectedId == null || selectedId == _wallpaperId) {
      return;
    }
    setState(() => _wallpaperId = selectedId);
    widget.onWallpaperChanged(selectedId);
  }
}

class _CurrentBackgroundSelection extends StatelessWidget {
  const _CurrentBackgroundSelection({
    required this.preset,
    required this.onChoose,
  });

  final PersonalProfileWallpaperPreset preset;
  final ValueChanged<InteractionSource>? onChoose;

  /// A small thumbnail, the background's name and the button (plan A).
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Wrap(
      spacing: tokens.space.sm,
      runSpacing: tokens.space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(width: 72, child: _BackgroundPreview(preset: preset)),
        Text(
          preset.hasImage
              ? preset.displayNumber
              : strings.text(preset.labelKey),
          key: const Key('profile-background-current-name'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        StarBridgeActionButton(
          controlKey: const Key('profile-background-picker-open'),
          onActivate: onChoose,
          child: Text(strings.text('profile.edit.backgroundChoose')),
        ),
      ],
    );
  }
}

class _BackgroundPickerDialog extends StatelessWidget {
  const _BackgroundPickerDialog({required this.selectedId});

  final String selectedId;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        child: Padding(
          padding: EdgeInsets.all(tokens.space.lg),
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
                          strings.text('profile.edit.backgroundPickerTitle'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        SizedBox(height: tokens.space.xxs),
                        Text(
                          strings.text(
                            'profile.edit.backgroundPickerDescription',
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: tokens.colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  StarBridgeIconAction(
                    controlKey: const Key('profile-background-picker-close'),
                    label: strings.text('common.cancel'),
                    consumeHintEscape: false,
                    onActivate: (source) =>
                        dismissStarBridgeDialog(context, source: source),
                    icon: const StarBridgeIcon(
                      StarBridgeIconSemantic.windowClose,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.space.md),
              Expanded(
                child: GridView.builder(
                  key: const Key('profile-background-picker-grid'),
                  itemCount: PersonalProfileWallpaperCatalog.presets.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.28,
                  ),
                  itemBuilder: (context, index) {
                    final preset =
                        PersonalProfileWallpaperCatalog.presets[index];
                    return _BackgroundChoice(
                      key: Key('profile-wallpaper-choice-${preset.id}'),
                      preset: preset,
                      selected: selectedId == preset.id,
                      onPressed: (source) => dismissStarBridgeDialog(
                        context,
                        source: source,
                        result: preset.id,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackgroundChoice extends StatelessWidget {
  const _BackgroundChoice({
    required this.preset,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final PersonalProfileWallpaperPreset preset;
  final bool selected;
  final ValueChanged<InteractionSource> onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return DecoratedBox(
      // Static fill belongs below the feedback layer. An opaque child would
      // hide Rail/Glow's pointer press while its animation still runs.
      decoration: BoxDecoration(
        color: tokens.surfaces.status.fill,
        borderRadius: tokens.shape.small,
      ),
      child: StarBridgeActionRow(
        controlKey: Key('profile-wallpaper-target-${preset.id}'),
        semanticSelected: selected,
        semanticLabel: preset.hasImage
            ? preset.displayNumber
            : strings.text(preset.labelKey),
        baseRadius: tokens.shape.radiusSmall,
        onActivate: (_, source) => onPressed(source),
        child: DefaultTextStyle.merge(
          style: DefaultTextStyle.of(context).style,
          child: ExcludeSemantics(
            child: Container(
              padding: EdgeInsets.all(tokens.space.xxs),
              decoration: BoxDecoration(
                borderRadius: tokens.shape.small,
                border: Border.all(
                  color: selected
                      ? tokens.colors.focusRing
                      : tokens.surfaces.status.border,
                  width: selected
                      ? tokens.stroke.focusWidth
                      : tokens.stroke.hairline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(child: _BackgroundPreview(preset: preset)),
                  SizedBox(height: tokens.space.xs),
                  Text(
                    preset.hasImage
                        ? preset.displayNumber
                        : strings.text(preset.labelKey),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundPreview extends StatelessWidget {
  const _BackgroundPreview({required this.preset});

  final PersonalProfileWallpaperPreset preset;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: tokens.shape.small,
        child: preset.assetPath == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      tokens.domainColors.ship.soft,
                      tokens.surfaces.raised.fill,
                    ],
                  ),
                ),
              )
            : Image.asset(
                preset.assetPath!,
                cacheWidth: 640,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    ColoredBox(color: tokens.surfaces.raised.fill),
              ),
      ),
    );
  }
}

String _visibilityKey(PersonalProfileVisibility visibility) =>
    switch (visibility) {
      PersonalProfileVisibility.everyone => 'profile-visibility-public',
      PersonalProfileVisibility.friendsFleetAndOrganizations ||
      PersonalProfileVisibility.friendsAndMainFleet =>
        'profile-visibility-friends-and-main-fleet',
      PersonalProfileVisibility.friendsOnly =>
        'profile-visibility-friends-only',
      PersonalProfileVisibility.onlyMe => 'profile-visibility-private',
    };

String _visibilityDescriptionKey(
  PersonalProfileVisibility visibility,
) => switch (visibility) {
  PersonalProfileVisibility.everyone => 'profile.visibility.publicDescription',
  PersonalProfileVisibility.friendsAndMainFleet =>
    'profile.visibility.friendsAndMainFleetDescription',
  PersonalProfileVisibility.friendsFleetAndOrganizations =>
    'profile.visibility.related',
  PersonalProfileVisibility.friendsOnly =>
    'profile.visibility.friendsOnlyDescription',
  PersonalProfileVisibility.onlyMe => 'profile.visibility.privateDescription',
};
