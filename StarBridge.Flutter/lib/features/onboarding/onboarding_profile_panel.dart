import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_action_button.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/embedded_avatar.dart';
import 'onboarding_copy.dart';
import 'onboarding_profile_controller.dart';

/// "你的资料" on the completed online finish page: the RSI avatar (read-only,
/// changed on the RSI website) and an optional nickname rename.
class OnboardingProfilePanel extends StatefulWidget {
  const OnboardingProfilePanel({
    required this.copy,
    required this.controller,
    this.handle,
    super.key,
  });
  final OnboardingCopy copy;
  final OnboardingProfileController controller;
  final String? handle;

  @override
  State<OnboardingProfilePanel> createState() => _OnboardingProfilePanelState();
}

class _OnboardingProfilePanelState extends State<OnboardingProfilePanel> {
  late final _field = TextEditingController(
    text: widget.controller.value.draft,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Widget _chip(String key, Color color) => Container(
    key: Key('profile-status-$key'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      widget.copy.text('profile.status.$key'),
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final copy = widget.copy;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: t.colors.textSecondary,
    );
    final view = widget.controller.value;
    final snapshot = view.snapshot!;
    if (_field.text != view.draft) {
      _field.value = TextEditingValue(
        text: view.draft,
        selection: TextSelection.collapsed(offset: view.draft.length),
      );
    }
    final failed = view.failureKey != null;
    final status = failed
        ? _chip('failed', t.colors.danger)
        : view.saved
        ? _chip('saved', t.colors.success)
        : view.dirty
        ? _chip('unsaved', t.colors.warning)
        : null;
    final note = failed
        ? '${copy.text(view.failureKey!)} ${copy.text('profile.keptName').replaceAll('{name}', snapshot.callSign)}'
        : !snapshot.canRename
        ? copy.text('profile.renameUnavailable')
        : view.saved
        ? copy.text('profile.savedNote')
        : view.dirty
        ? copy.text('profile.unsavedNote')
        : copy.text('profile.nameNote');
    final avatar = Column(
      children: [
        SizedBox.square(
          dimension: 88,
          child: Container(
            key: const Key('onboarding-profile-avatar'),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: t.surfaces.raised.fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.surfaces.raised.border, width: 2),
            ),
            child: EmbeddedAvatar(
              source: snapshot.avatarImageData,
              fallback: Center(
                child: Text(
                  snapshot.callSign.characters.first.toUpperCase(),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: t.colors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: t.space.xs),
        Text(copy.text('profile.avatarSource'), style: small),
        if (snapshot.canOpenRsi)
          StarBridgeActionButton(
            controlKey: const Key('onboarding-profile-open-rsi'),
            kind: StarBridgeActionKind.quiet,
            onActivate: _tap(widget.controller.openRsi),
            child: Text(copy.text('profile.avatarChange')),
          ),
      ],
    );
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(copy.text('profile.name'), style: small),
            if (status != null) ...[SizedBox(width: t.space.sm), status],
          ],
        ),
        SizedBox(height: t.space.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('onboarding-profile-name'),
                controller: _field,
                enabled: snapshot.canRename && !view.saving,
                maxLength: 32,
                onChanged: widget.controller.edit,
                onSubmitted: (_) => widget.controller.save(),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  border: const OutlineInputBorder(),
                  errorText: failed ? '' : null,
                  errorStyle: const TextStyle(height: 0, fontSize: 0),
                ),
              ),
            ),
            SizedBox(width: t.space.sm),
            if (failed)
              StarBridgeActionButton(
                controlKey: const Key('onboarding-profile-save'),
                kind: StarBridgeActionKind.primary,
                onActivate: _tap(view.canSave ? widget.controller.save : null),
                child: Text(copy.text('profile.retry')),
              )
            else
              StarBridgeActionButton(
                controlKey: const Key('onboarding-profile-save'),
                kind: StarBridgeActionKind.secondary,
                onActivate: _tap(view.canSave ? widget.controller.save : null),
                child: Text(
                  copy.text(view.saving ? 'profile.saving' : 'profile.save'),
                ),
              ),
          ],
        ),
        SizedBox(height: t.space.xs),
        Text(
          note,
          key: const Key('onboarding-profile-note'),
          style: failed ? small?.copyWith(color: t.colors.danger) : small,
        ),
        if (view.rsiFailed)
          Text(
            copy.text('profile.rsiOpenFailed'),
            style: small?.copyWith(color: t.colors.warning),
          ),
        if (widget.handle != null) ...[
          SizedBox(height: t.space.md),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${copy.text('profile.handle')}  ',
                  style: small,
                ),
                TextSpan(
                  text: widget.handle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    return Container(
      key: const Key('onboarding-profile-panel'),
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.surfaces.raised.fill,
        borderRadius: BorderRadius.circular(t.shape.radiusSmall),
        border: Border.all(color: t.surfaces.raised.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: t.space.sm,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Semantics(
                header: true,
                child: Text(
                  copy.text('profile.title'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(copy.text('profile.intro'), style: small),
            ],
          ),
          SizedBox(height: t.space.md),
          LayoutBuilder(
            builder: (context, box) => box.maxWidth < 420
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      avatar,
                      SizedBox(height: t.space.md),
                      name,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      SizedBox(width: t.space.lg),
                      Expanded(child: name),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Native-style tap callback to a suite activation (source unused here).
ValueChanged<InteractionSource>? _tap(VoidCallback? onPressed) =>
    onPressed == null ? null : (_) => onPressed();
