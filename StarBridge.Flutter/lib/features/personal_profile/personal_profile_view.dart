import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/chrome/shell_chrome_projection.dart';

import 'package:flutter/foundation.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'personal_profile_editor.dart';
import '../gameplay_time/gameplay_time_controller.dart';
import 'personal_profile_identity_header.dart';
import 'personal_profile_models.dart';
import 'personal_profile_read_status.dart';
import 'personal_profile_draft.dart';
import 'personal_profile_public_facts.dart';
import 'personal_profile_trade_strip.dart';
import 'personal_profile_module_grid.dart';
import 'personal_profile_summary.dart';

/// The available profile: banners, the identity card, the section heading
/// and the module grid. Split from personal_profile_page.dart (2026-10-20)
/// so the page stays under the 800-line limit.
class PersonalProfileView extends StatelessWidget {
  const PersonalProfileView({
    super.key,
    required this.readSource,
    required this.readPhase,
    required this.editorKey,
    this.initialDraft,
    this.ownerRequiresReload,
    required this.onVisibility,
    required this.projection,
    this.presence,
    this.gameplayTime,
    required this.visitorPreview,
    this.isVisitor = false,
    this.offline = false,
    required this.editing,
    required this.layout,
    required this.onPreview,
    required this.onExitPreview,
    required this.onEdit,
    required this.onEditPositions,
    required this.onCancelEdit,
    required this.onSaved,
    required this.onSave,
    required this.onRefresh,
    required this.onLayoutChanged,
    required this.onWallpaperChanged,
  });

  final PersonalProfileEditorDraft? initialDraft;
  final InteractionSource readSource;
  final int readPhase;
  final bool? ownerRequiresReload;
  final PersonalProfileProjection projection;
  final VoidCallback? onVisibility;
  final GameplayTimeController? gameplayTime;
  final ValueListenable<ShellChromeProjection>? presence;
  final bool visitorPreview;
  final bool isVisitor;
  final bool offline;
  final bool editing;
  final List<PersonalProfileModuleLayoutItem> layout;
  final VoidCallback onPreview;
  final VoidCallback onExitPreview;
  final VoidCallback onEdit;
  final VoidCallback onEditPositions;
  final GlobalKey<PersonalProfileEditorPanelState> editorKey;
  final VoidCallback onCancelEdit;
  final VoidCallback onSaved;
  final VoidCallback onRefresh;
  final Future<PersonalProfileActionResult> Function(PersonalProfileEdit edit)
  onSave;
  final ValueChanged<List<PersonalProfileModuleLayoutItem>> onLayoutChanged;
  final ValueChanged<String> onWallpaperChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (visitorPreview) ...[
          PersonalProfileVisitorPreviewBanner(onExit: onExitPreview),
          SizedBox(height: tokens.space.md),
        ],
        if (projection.operation == PersonalProfileOperation.refreshing) ...[
          PersonalProfileReadProgress(
            key: ValueKey(('profile-refresh-wait', readPhase)),
            label: AppStrings.of(context).text('profile.syncing'),
            source: readSource,
          ),
          SizedBox(height: tokens.space.sm),
        ],
        if ((projection.refreshFailed, projection.synchronizedAtUtc) case (
          true,
          final at?,
        )) ...[
          Text(
            AppStrings.of(context)
                .text('profile.syncFailedAt')
                .replaceAll(
                  '{time}',
                  '${MaterialLocalizations.of(context).formatShortDate(at.toLocal())} '
                      '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()))}',
                ),
            key: const Key('profile-sync-failed'),
            style: TextStyle(color: tokens.colors.warning),
          ),
          SizedBox(height: tokens.space.sm),
        ],
        if (projection.refreshFailed && !visitorPreview && !isVisitor) ...[
          StarBridgeActionButton(
            controlKey: const Key('profile-sync-retry'),
            onActivate:
                editing || projection.operation != PersonalProfileOperation.none
                ? null
                : (_) => onRefresh(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    AppStrings.of(context).text('profile.unavailable.retry'),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.space.sm),
        ],
        // Outside the visibility the page no longer goes blank: the
        // always-public header (avatar, name, trade days and window) stays
        // and only the content below is shielded (user rule, 2026-10-20).
        if (projection.restricted || visitorPreview && !projection.isPublic) ...[
          PersonalProfileIdentityHeader(
            projection: projection,
            isSelf: !isVisitor,
            publicOnly: true,
            // A real visitor gets the window from the profile service; the
            // owner's preview reads it from the trading hall as usual.
            // No synced window may only mean the owner never opened
            // StarBridge since setting it on SCM: show nothing rather than
            // claim "not set" (user decision 2026-10-21, conservative).
            trade: projection.restricted
                ? switch ((projection.publicFacts, projection.publicTradeWindow)) {
                    (final facts?, final window) =>
                      PersonalProfilePublicFactsBlock(
                        facts: facts,
                        window: window?.toStripData(),
                      ),
                    (null, final window?) => ProfileTradeStrip(
                      data: window.toStripData(),
                      isSelf: false,
                    ),
                    (null, null) => null,
                  }
                : ProfileTradeStripScope.build(
                    context,
                    ProfileTradeStripView.restrictedVisitor,
                  ),
          ),
          SizedBox(height: tokens.space.xl),
          PersonalProfileShield(
            visibility: projection.visibility,
            // Nobody chose this scope: naming one would say they had.
            showScope: !projection.defaultedPage,
          ),
        ] else ...[
          if (editing)
            PersonalProfileEditorPanel(
              key: editorKey,
              initialDraft: initialDraft,
              ownerRequiresReload: ownerRequiresReload,
              projection: projection,
              onSave: onSave,
              onCancel: onCancelEdit,
              onSaved: onSaved,
              moduleLayout: layout,
              onWallpaperChanged: onWallpaperChanged,
            )
          else
            PersonalProfileIdentityHeader(
              projection: projection,
              isSelf: !isVisitor,
              presence: visitorPreview || isVisitor ? null : presence,
              trade: isVisitor
                  ? null
                  : ProfileTradeStripScope.build(
                      context,
                      visitorPreview
                          ? ProfileTradeStripView.visitor
                          : ProfileTradeStripView.owner,
                    ),
            ),
          SizedBox(height: tokens.space.xl),
          PersonalProfileSectionHeading(
            projection: projection,
            showOwnerActions:
                !offline && !visitorPreview && !isVisitor && !editing,
            onPreview: onPreview,
            onEdit: onEdit,
            onRefresh: onRefresh,
            onVisibility: onVisibility,
          ),
          if (!projection.allowEditing && !visitorPreview && !isVisitor) ...[
            SizedBox(height: tokens.space.sm),
            Row(
              children: [
                StarBridgeIcon(
                  StarBridgeIconSemantic.privacy,
                  size: tokens.icons.small,
                  color: tokens.colors.textSecondary,
                ),
                SizedBox(width: tokens.space.xs),
                Expanded(
                  child: Text(
                    AppStrings.of(context).text(
                      offline
                          ? 'profile.offline.notice'
                          : 'profile.readOnly.notice',
                    ),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (!projection.isPublic &&
              !visitorPreview &&
              !isVisitor &&
              !editing &&
              !offline) ...[
            SizedBox(height: tokens.space.sm),
            PersonalProfilePublicHeaderNote(visibility: projection.visibility),
          ],
          if (offline &&
              projection.local?.remoteAvailable == true &&
              projection.local?.savedAt != null)
            Text(
              AppStrings.of(context)
                  .text('profile.offline.confirmedAt')
                  .replaceAll(
                    '{time}',
                    projection.local!.savedAt!.toLocal().toString(),
                  ),
              key: const Key('profile-offline-confirmed-at'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          SizedBox(height: tokens.space.md),
          if (projection.local?.needsCreation == true && !editing) ...[
            Text(
              AppStrings.of(context).text('profile.local.firstSteps'),
              key: const Key('profile-local-first-steps'),
            ),
            SizedBox(height: tokens.space.sm),
          ],
          if (projection.local?.remoteAvailable == false)
            Text(
              AppStrings.of(context).text('profile.local.remoteUnavailable'),
              key: const Key('profile-local-remote-unavailable'),
            ),
          PersonalProfileSummaryStrip(
            projection: projection,
            gameplayTime: isVisitor ? null : gameplayTime,
            includeLocalTime: !visitorPreview && !isVisitor,
          ),
          SizedBox(height: tokens.space.md),
          ExcludeFocus(
            excluding: projection.operation != PersonalProfileOperation.none,
            child: AbsorbPointer(
              absorbing: projection.operation != PersonalProfileOperation.none,
              child: PersonalProfileModuleGrid(
                projection: projection,
                visitorView: visitorPreview || isVisitor,
                editing: editing,
                layout: layout,
                onLayoutChanged: onLayoutChanged,
                onEditPositions:
                    projection.canEdit &&
                        editing &&
                        !visitorPreview &&
                        projection.local != null
                    ? onEditPositions
                    : null,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

String _copy(BuildContext context, String key) {
  final locale = AppStrings.of(context).locale;
  final i = locale.languageCode == 'en'
      ? 2
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? 1
      : 0;
  return const {
    'shieldTitle': [
      '其余内容未公开',
      '其餘內容未公開',
      'The rest of this profile is not public',
    ],
    'shieldBody': [
      '可见范围：{scope}。头像、名字和交易时段始终公开。',
      '可見範圍：{scope}。頭像、名字和交易時段始終公開。',
      'Visible to: {scope}. Avatar, name and trading hours are always public.',
    ],
    'note': [
      '访客始终能看到你的头像、名字和交易时段；其余内容按可见范围（{scope}）显示。',
      '訪客始終能看到你的頭像、名字和交易時段；其餘內容按可見範圍（{scope}）顯示。',
      'Visitors always see your avatar, name and trading hours; the rest follows your visibility ({scope}).',
    ],
  }[key]![i];
}

/// Replaces the content below the identity card for a visitor outside the
/// profile's visibility. The card above stays (avatar, name, trade strip).
class PersonalProfileShield extends StatelessWidget {
  const PersonalProfileShield({
    required this.visibility,
    this.showScope = true,
    super.key,
  });
  final PersonalProfileVisibility visibility;
  final bool showScope;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scope = AppStrings.of(context).text(visibility.labelKey);
    return StarBridgeSurface(
      key: const Key('profile-private-visitor-view'),
      role: SurfaceRole.raised,
      padding: EdgeInsets.all(tokens.space.xxl),
      child: Column(
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.privacy,
            size: tokens.icons.large,
            color: tokens.colors.textSecondary,
          ),
          SizedBox(height: tokens.space.md),
          Text(
            _copy(context, 'shieldTitle'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (showScope) ...[
            SizedBox(height: tokens.space.xs),
            Text(
              _copy(context, 'shieldBody').replaceAll('{scope}', scope),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tells an owner with a non-public profile what visitors still see.
class PersonalProfilePublicHeaderNote extends StatelessWidget {
  const PersonalProfilePublicHeaderNote({required this.visibility, super.key});
  final PersonalProfileVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      key: const Key('profile-public-header-note'),
      children: [
        StarBridgeIcon(
          StarBridgeIconSemantic.privacy,
          size: tokens.icons.small,
          color: tokens.colors.textSecondary,
        ),
        SizedBox(width: tokens.space.xs),
        Expanded(
          child: Text(
            _copy(context, 'note').replaceAll(
              '{scope}',
              AppStrings.of(context).text(visibility.labelKey),
            ),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
        ),
      ],
    );
  }
}
