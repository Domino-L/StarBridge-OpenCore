import 'package:flutter/material.dart';
import '../common/user_avatar_menu.dart';

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
import 'personal_profile_playstyle_editor.dart';
import 'personal_profile_schedule_editor.dart';
import 'personal_profile_wallpaper_catalog.dart';

class PersonalProfileEditorPanel extends StatefulWidget {
  const PersonalProfileEditorPanel({
    required this.projection,
    required this.onSave,
    required this.onCancel,
    required this.onSaved,
    required this.moduleLayout,
    required this.onWallpaperChanged,
    super.key,
  });

  final PersonalProfileProjection projection;
  final Future<PersonalProfileActionResult> Function(PersonalProfileEdit edit)
  onSave;
  final VoidCallback onCancel;
  final VoidCallback onSaved;
  final List<PersonalProfileModuleLayoutItem> moduleLayout;
  final ValueChanged<String> onWallpaperChanged;

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
  late final TextEditingController _aboutController;
  late int _avatarStyle;
  late String _wallpaperId;
  late PersonalProfileVisibility _visibility;
  bool _saving = false;
  final _formKey = GlobalKey<FormState>();
  PersonalProfilePlayStyle? _playStyle;
  PersonalProfileSchedule? _schedule;
  bool _validationError = false;

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
  }

  @override
  void dispose() {
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
          Text(
            strings.text('profile.edit.avatar'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          SizedBox(height: tokens.space.sm),
          Row(
            children: [
              UserAvatarMenu(name: widget.projection.callSign, isSelf: true, child: PersonalProfileAvatar(
                key: const Key('profile-current-avatar'),
                callSign: widget.projection.callSign,
                styleIndex: _avatarStyle,
                imageData: widget.projection.avatarImageData,
                size: tokens.density.controlHeight * 1.5,
              )),
              SizedBox(width: tokens.space.md),
              Expanded(child: const AccountAvatarEditor()),
            ],
          ),
          SizedBox(height: tokens.space.lg),
          Text(
            strings.text('profile.edit.wallpaper'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          SizedBox(height: tokens.space.xxs),
          Text(
            strings.text('profile.edit.wallpaperDescription'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.sm),
          _CurrentBackgroundSelection(
            preset: PersonalProfileWallpaperCatalog.resolve(_wallpaperId),
            onChoose: _saving ? null : _chooseBackground,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            strings.text('profile.edit.wallpaperFankitNotice'),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.xs),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: CigFankitNoticeButton(
              key: Key('profile-editor-cig-fankit-notice'),
            ),
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
                  DropdownButtonFormField<PersonalProfileVisibility>(
                    key: const Key('profile-visibility-selector'),
                    initialValue: _visibility,
                    isExpanded: true,
                    items: [
                      for (final visibility in PersonalProfileVisibility.values.where(
                        (v) => v != PersonalProfileVisibility.friendsFleetAndOrganizations))
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
          TextField(
            key: const Key('profile-call-sign-field'),
            controller: _callSignController,
            maxLength: 32,
            decoration: InputDecoration(
              labelText: strings.text('profile.edit.callSign'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: tokens.space.sm),
          TextField(
            key: const Key('profile-about-field'),
            controller: _aboutController,
            minLines: 4,
            maxLines: 7,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: strings.text('profile.edit.about'),
            ),
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            '${strings.text('profile.edit.gameHandle')} '
            '@${widget.projection.gameHandle}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          if (widget.projection.local case final local?) ...[
            SizedBox(height: tokens.space.lg),
            PersonalProfilePlayStyleEditor(
              key: _positionsKey,
              projection: widget.projection,
              enabled: !_saving,
              onChanged: (value) => _playStyle = value,
            ),
            PersonalProfileScheduleEditor(
              initial: PersonalProfileSchedule(
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
        OutlinedButton(
          key: const Key('profile-edit-cancel'),
          onPressed: _saving ? null : widget.onCancel,
          child: Text(strings.text('common.cancel')),
        ),
        FilledButton(
          key: const Key('profile-save'),
          onPressed: _saving || _callSignController.text.trim().isEmpty
              ? null
              : _save,
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
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text('profile.edit.title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: tokens.space.xxs),
                  Text(
                    strings.text(
                      widget.projection.local != null
                          ? 'profile.local.description'
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
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _validationError = true);
      return;
    }
    setState(() {
      _saving = true;
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
      ),
    );
    if (!mounted) {
      return;
    }
    if (result.outcome == PersonalProfileActionOutcome.completed) {
      widget.onSaved();
      return;
    }
    setState(() => _saving = false);
  }

  Future<void> _chooseBackground() async {
    final selectedId = await showDialog<String>(
      context: context,
      builder: (context) => _BackgroundPickerDialog(selectedId: _wallpaperId),
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
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.all(tokens.space.sm),
      decoration: BoxDecoration(
        color: tokens.surfaces.status.fill,
        borderRadius: tokens.shape.small,
        border: Border.all(
          color: tokens.surfaces.status.border,
          width: tokens.stroke.hairline,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final preview = SizedBox(
            width: constraints.maxWidth < 500 ? constraints.maxWidth : 192,
            child: _BackgroundPreview(preset: preset),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('profile.edit.backgroundCurrent'),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
              SizedBox(height: tokens.space.xxs),
              Text(
                preset.hasImage
                    ? preset.displayNumber
                    : strings.text(preset.labelKey),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: tokens.space.sm),
              OutlinedButton(
                key: const Key('profile-background-picker-open'),
                onPressed: onChoose,
                child: Text(strings.text('profile.edit.backgroundChoose')),
              ),
            ],
          );
          if (constraints.maxWidth < 500) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                preview,
                SizedBox(height: tokens.space.sm),
                details,
              ],
            );
          }
          return Row(
            children: [
              preview,
              SizedBox(width: tokens.space.md),
              Expanded(child: details),
            ],
          );
        },
      ),
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
                  IconButton(
                    key: const Key('profile-background-picker-close'),
                    tooltip: strings.text('common.cancel'),
                    onPressed: () => Navigator.of(context).pop(),
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
                      onPressed: () => Navigator.of(context).pop(preset.id),
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
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: preset.hasImage
          ? preset.displayNumber
          : strings.text(preset.labelKey),
      child: InkWell(
        onTap: onPressed,
        borderRadius: tokens.shape.small,
        child: Container(
          padding: EdgeInsets.all(tokens.space.xxs),
          decoration: BoxDecoration(
            color: tokens.surfaces.status.fill,
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
              _BackgroundPreview(preset: preset),
              SizedBox(height: tokens.space.xs),
              Text(
                preset.hasImage
                    ? preset.displayNumber
                    : strings.text(preset.labelKey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
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
  PersonalProfileVisibility.friendsFleetAndOrganizations => 'profile.visibility.related',
  PersonalProfileVisibility.friendsOnly =>
    'profile.visibility.friendsOnlyDescription',
  PersonalProfileVisibility.onlyMe => 'profile.visibility.privateDescription',
};
