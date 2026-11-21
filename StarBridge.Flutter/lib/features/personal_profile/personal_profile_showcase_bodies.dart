import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/styles/profile_showcase_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../gameplay_time/gameplay_account_total.dart';
import '../gameplay_time/gameplay_time_controller.dart';
import 'personal_profile_affiliation_mark.dart';
import 'personal_profile_identity_header.dart';
import 'personal_profile_models.dart';
import 'personal_profile_public_facts.dart';
import 'personal_profile_public_header.dart';
import 'personal_profile_showcase_copy.dart';
import 'personal_profile_showcase_frame.dart';

String _tagLabel(BuildContext context, PersonalProfileTagValue tag) =>
    tag.displayLabel ?? AppStrings.of(context).text(tag.labelKey);

/// The owner's main role (the primary skilled role), or null.
PersonalProfileTagValue? profileMainRole(PersonalProfileProjection p) =>
    p.roles.where((role) => role.isPrimary).firstOrNull;

/// 游戏定位: the main role large, the rest as words. 支援能力 is merged into
/// 擅长岗位 (user, 2026-11-02).
class ProfileRolesShowcase extends StatelessWidget {
  const ProfileRolesShowcase({required this.projection, super.key});
  final PersonalProfileProjection projection;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final main = profileMainRole(projection);
    final skilled = [
      ...projection.roles.where((role) => !identical(role, main)),
      ...projection.supportCapabilities,
    ].map((tag) => _tagLabel(context, tag)).toSet().toList();
    final wants = [
      for (final tag in projection.participationInterests)
        _tagLabel(context, tag),
    ];
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileCaption(profileShowcaseCopy(context, 'mainRole')),
        Text(
          main == null ? '—' : _tagLabel(context, main),
          key: const Key('profile-showcase-main-role'),
          style: TextStyle(
            fontSize: 26,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: ProfileShowcasePalette.mainRole(
              Theme.of(context).brightness,
            ),
          ),
        ),
        SizedBox(height: tokens.space.sm),
        ProfileCaption(profileShowcaseCopy(context, 'rhythm')),
        Text(
          AppStrings.of(context)
              .text('profile.activity.${projection.activityRhythm.name}'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: tokens.colors.textPrimary,
          ),
        ),
      ],
    );
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TagLine(label: profileShowcaseCopy(context, 'skilled'), tags: skilled),
        SizedBox(height: tokens.space.sm),
        _TagLine(
          label: profileShowcaseCopy(context, 'wantsToJoin'),
          tags: wants,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 420
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                left,
                SizedBox(height: tokens.space.md),
                right,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 172, child: left),
                SizedBox(width: tokens.space.lg),
                Expanded(child: right),
              ],
            ),
    );
  }
}

class _TagLine extends StatelessWidget {
  const _TagLine({required this.label, required this.tags});
  final String label;
  final List<String> tags;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ProfileCaption(label),
      const SizedBox(height: 4),
      if (tags.isEmpty)
        const ProfileCaption('—')
      else
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [for (final tag in tags) ProfileFlatTag(tag)],
        ),
    ],
  );
}

/// 游戏时长 (renamed from 账号汇总): total hours large, usual hours as two
/// day bars in the owner's own time. Builds its own band, which disappears
/// when the owner keeps playtime off the profile.
class ProfileGameplayShowcase extends StatelessWidget {
  const ProfileGameplayShowcase({
    required this.projection,
    this.gameplayTime,
    this.includeLocalTime = false,
    this.controls,
    this.accountHours,
    super.key,
  });

  final PersonalProfileProjection projection;

  /// The rail's hours for this viewer (the owner's account total, a visitor's
  /// page total); null falls back to the page document.
  final int? accountHours;
  final GameplayTimeController? gameplayTime;
  final bool includeLocalTime;

  /// Edit controls in the band's title bar.
  final Widget? controls;

  @override
  Widget build(BuildContext context) {
    if (gameplayTime case final controller?) {
      return ValueListenableBuilder<GameplayTimeView>(
        valueListenable: controller,
        builder: (context, state, _) => _build(context, state),
      );
    }
    return _build(context, null);
  }

  Widget _build(BuildContext context, GameplayTimeView? gameplay) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final numbers = MaterialLocalizations.of(context);
    // Local accounting is an owner-only observation, never evidence of upload.
    // Imported history is already included in seconds; do not add it again.
    final localSeconds = includeLocalTime && gameplay?.visible == true
        ? gameplay?.seconds
        : null;
    final documentMinutes = projection.local?.remoteAvailable == false
        ? null
        : projection.gameplayMinutes;
    // The owner's account total is the one the gameplay controller read, as
    // in the side rail (ownerAccountMinutes).
    final accountMinutes = includeLocalTime
        ? ownerAccountMinutes(gameplay, documentMinutes)
        : documentMinutes;
    final accountLabel = accountMinutes == null
        ? strings.text(
            includeLocalTime
                ? 'gameplay.remoteUnavailable'
                : 'gameplay.visitorUnavailable',
          )
        : profileShowcaseCopy(
            context,
            'hoursUnit',
          ).replaceAll('{n}', numbers.formatDecimal(accountMinutes ~/ 60));
    final hours = localSeconds != null
        ? localSeconds ~/ 3600
        : accountHours ??
              (accountMinutes == null ? null : accountMinutes ~/ 60);
    final total = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hours == null ? '—' : numbers.formatDecimal(hours),
          key: const Key('profile-showcase-hours'),
          style: TextStyle(
            fontSize: 46,
            height: 1,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: tokens.colors.textPrimary,
          ),
        ),
        SizedBox(height: tokens.space.xs),
        ProfileCaption(
          strings.text(
            localSeconds != null
                ? 'gameplay.localTotal'
                : 'gameplay.remoteTotal',
          ),
        ),
        if (localSeconds != null) ...[
          if (gameplay!.historicalSeconds > 0)
            ProfileCaption(
              '${strings.text('gameplay.importedTotal')}: '
              '${profileShowcaseCopy(context, 'hoursUnit').replaceAll('{n}', numbers.formatDecimal(gameplay.historicalSeconds ~/ 3600))}',
            ),
          ProfileCaption(strings.text('gameplay.deviceStorage')),
          ProfileCaption(
            '${strings.text('gameplay.remoteTotal')}: $accountLabel',
          ),
        ] else if (accountMinutes == null && accountHours == null)
          ProfileCaption(accountLabel),
      ],
    );
    final windows = projection.availabilityWindows;
    final bars = windows.isEmpty
        ? ProfileCaption(profileShowcaseCopy(context, 'noWindow'))
        : _WeekBars(windows: windows);
    return ProfileShowcaseBand(
      key: const Key('profile-showcase-gameplay'),
      title: profileShowcaseCopy(context, 'gameplayTitle'),
      trailing: controls,
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 420
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  total,
                  SizedBox(height: tokens.space.md),
                  bars,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 170, child: total),
                  SizedBox(width: tokens.space.lg),
                  Expanded(child: bars),
                ],
              ),
      ),
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.windows});
  final List<PersonalProfileAvailabilityWindow> windows;

  static double _hour(String hhmm) {
    final parts = hhmm.split(':');
    return (int.tryParse(parts.first) ?? 0) +
        (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0) / 60;
  }

  /// [start, end) spans in hours for windows touching the given days.
  List<(double, double)> _spans(bool Function(int day) on) => [
    for (final window in windows)
      if (window.days.any(on))
        ...(window.endsNextDay
            ? [(_hour(window.startTime), 24.0), (0.0, _hour(window.endTime))]
            : [(_hour(window.startTime), _hour(window.endTime))]),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget row(String label, List<(double, double)> spans) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 46, child: ProfileCaption(label)),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Container(
                height: 12,
                color: tokens.colors.textPrimary.withValues(alpha: 0.05),
                child: Stack(
                  children: [
                    for (final (start, end) in spans)
                      if (end > start)
                        PositionedDirectional(
                          start: constraints.maxWidth * start / 24,
                          width: constraints.maxWidth * (end - start) / 24,
                          top: 0,
                          bottom: 0,
                          child: ColoredBox(
                            color: ProfileShowcasePalette.timeBar.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      key: const Key('profile-showcase-week-bars'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          profileShowcaseCopy(context, 'weekdays'),
          _spans((day) => day >= 1 && day <= 5),
        ),
        row(
          profileShowcaseCopy(context, 'weekends'),
          _spans((day) => day == 0 || day == 6),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 54),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final labels = [
                profileShowcaseCopy(context, 'hour0'),
                '6',
                '12',
                '18',
                profileShowcaseCopy(context, 'hour24'),
              ];
              final painter = TextPainter(
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              );
              final widths = <double>[];
              for (final label in labels) {
                painter.text = TextSpan(
                  text: label,
                  style: DefaultTextStyle.of(context).style
                      .copyWith(fontSize: 12),
                );
                painter.layout();
                widths.add(painter.width);
              }
              painter.dispose();
              // Keep as many ticks as fit, never fewer than the two ends: all
              // five, then the ends and noon, then the ends only (the side
              // rail is narrow, user 11-11). Captions keep their typography.
              double need(List<int> shown) =>
                  shown.fold(0.0, (sum, i) => sum + widths[i]) +
                  8.0 * (shown.length - 1);
              final shown = [
                for (final candidate in const [
                  [0, 1, 2, 3, 4],
                  [0, 2, 4],
                ])
                  if (need(candidate) <= constraints.maxWidth) candidate,
                const [0, 4],
              ].first;
              final row = Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [for (final i in shown) ProfileCaption(labels[i])],
              );
              return need(shown) <= constraints.maxWidth
                  ? row
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: SizedBox(width: need(shown), child: row),
                    );
            },
          ),
        ),
      ],
    );
  }
}

/// 交易名片 from SCM's public facts: reputation large, then trades and
/// orders, then the dates. Anything SCM did not answer is left out.
class ProfileTradeCardShowcase extends StatelessWidget {
  const ProfileTradeCardShowcase({required this.facts, super.key});
  final PersonalProfilePublicFacts facts;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final numbers = MaterialLocalizations.of(context);
    final labels = personalProfilePublicFactLabels(context);
    final cells = <Widget>[
      if (facts.reputation case final value?)
        ProfileBigNumber(
          value: numbers.formatDecimal(value),
          label: labels.reputation,
          size: 46,
          color: ProfileShowcasePalette.reputationFor(
            Theme.of(context).brightness,
          ),
        ),
      if (facts.completedTrades case final value?)
        ProfileBigNumber(
          value: numbers.formatDecimal(value),
          label: labels.completedTrades,
          size: 30,
        ),
      if (facts.sellOrders case final value?)
        ProfileBigNumber(
          value: numbers.formatDecimal(value),
          label: labels.sellOrders,
          size: 30,
        ),
      if (facts.buyOrders case final value?)
        ProfileBigNumber(
          value: numbers.formatDecimal(value),
          label: labels.buyOrders,
          size: 30,
        ),
    ];
    final dates = personalProfilePublicFactDates(context, facts);
    return Column(
      key: const Key('profile-showcase-trade-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cells.isNotEmpty)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < cells.length; index++) ...[
                  if (index > 0) ...[
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: profileHairline(context),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(flex: index == 0 ? 5 : 4, child: cells[index]),
                ],
              ],
            ),
          ),
        if (dates.isNotEmpty) ...[
          SizedBox(height: tokens.space.sm),
          Container(
            padding: EdgeInsets.only(top: tokens.space.sm),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: profileHairline(context))),
            ),
            child: Wrap(
              spacing: 22,
              runSpacing: 6,
              children: [
                for (final (label, value) in dates)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$label  ',
                          style: TextStyle(color: tokens.colors.textSecondary),
                        ),
                        TextSpan(text: value),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: tokens.colors.textPrimary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 组织展柜 / rail 组织: each affiliation with its mark and position.
class ProfileOrganizationList extends StatelessWidget {
  const ProfileOrganizationList({
    required this.projection,
    required this.isSelf,
    this.wide = false,
    super.key,
  });

  final PersonalProfileProjection projection;
  final bool isSelf;

  /// Two columns of larger tiles (showcase) instead of rail rows.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final rows = projection.affiliations;
    if (rows.isEmpty) {
      return ProfileCaption(
        strings.text(
          personalProfileAffiliationEmptyKey(projection, isSelf: isSelf),
        ),
      );
    }
    Widget tile(PersonalProfileAffiliationSummary row) {
      final tileChild = Row(
        children: [
          PersonalProfileAffiliationMark(
            affiliation: row,
            size: wide ? 46 : 30,
          ),
          SizedBox(width: tokens.space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: wide ? 14 : 13,
                    fontWeight: wide ? FontWeight.w600 : FontWeight.w500,
                    color: tokens.colors.textPrimary,
                  ),
                ),
                if (row.positionLabelKey.isNotEmpty || row.code.isNotEmpty)
                  ProfileCaption(
                    [
                      if (row.positionLabelKey.isNotEmpty)
                        strings.text(row.positionLabelKey),
                      if (row.code.isNotEmpty) row.code,
                    ].join(' · '),
                  ),
              ],
            ),
          ),
        ],
      );
      return wide
          ? Container(
              padding: const EdgeInsets.all(10),
              color: tokens.colors.textPrimary.withValues(alpha: 0.04),
              child: tileChild,
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: tileChild,
            );
    }

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final row in rows) tile(row)],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 420
            ? constraints.maxWidth
            : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final row in rows) SizedBox(width: width, child: tile(row)),
          ],
        );
      },
    );
  }
}
