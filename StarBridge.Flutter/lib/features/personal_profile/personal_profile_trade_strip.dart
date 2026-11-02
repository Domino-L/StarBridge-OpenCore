import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

/// What the profile's trade strip shows, already converted to the viewer's
/// local time by the composition layer (the strip never reads SCM itself).
///
/// The trade days and window are always public (user decision 2026-10-20);
/// [contact] and [reputation] are only set when the profile's visibility lets
/// this viewer see them, so a hidden field is simply absent here.
@immutable
class ProfileTradeStripData {
  const ProfileTradeStripData({
    required this.localDays,
    required this.localWindow,
    this.openNow,
    this.ownerWindow,
    this.contact,
    this.reputation,
  });

  /// Monday first, seven entries, in the viewer's local time.
  final List<bool> localDays;

  /// "19:30–23:00" in the viewer's local time.
  final String localWindow;

  /// Whether the window is open right now; null when unknown.
  final bool? openNow;

  /// "19:30–23:00 · UTC+08:00", the owner's own setting (visitors only).
  final String? ownerWindow;
  final String? contact;

  /// "★ 128 · 已成交 31".
  final String? reputation;
}

/// Who is looking at the owner's trade strip.
enum ProfileTradeStripView {
  /// The owner: 始终公开 marks and the edit action.
  owner,

  /// A visitor allowed to see the whole profile: contact channel and
  /// reputation follow the profile's visibility, so they are shown.
  visitor,

  /// A visitor outside the profile's visibility: only the always-public
  /// trade days and window (user rule, 2026-10-20).
  restrictedVisitor,
}

typedef ProfileTradeStripBuilder =
    Widget Function(BuildContext context, ProfileTradeStripView view);

/// Supplies the owner's trade strip to the profile page from the composition
/// layer, so the page itself only decides where it goes and for whom.
class ProfileTradeStripScope extends InheritedWidget {
  const ProfileTradeStripScope({
    required this.builder,
    required super.child,
    super.key,
  });
  final ProfileTradeStripBuilder builder;

  static Widget? build(
    BuildContext context, [
    ProfileTradeStripView view = ProfileTradeStripView.owner,
  ]) => context
      .dependOnInheritedWidgetOfExactType<ProfileTradeStripScope>()
      ?.builder(context, view);

  @override
  bool updateShouldNotify(ProfileTradeStripScope oldWidget) =>
      builder != oldWidget.builder;
}

/// The trade strip on the identity card's lower edge (layout a, chosen by
/// the user on 2026-10-20). It reuses the trade profile dialog's vocabulary:
/// weekday chips and the HH:mm window. Owners see "始终公开" beside the two
/// always-public fields and an edit action; a missing profile becomes one
/// prompt to fill it in.
class ProfileTradeStrip extends StatelessWidget {
  const ProfileTradeStrip({
    required this.data,
    required this.isSelf,
    this.onEdit,
    super.key,
  });

  /// Null when the owner has not set a trade profile yet.
  final ProfileTradeStripData? data;
  final bool isSelf;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final copy = _ProfileTradeCopy.of(context);
    final data = this.data;
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          copy.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: t.colors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        const _ScmBadge(),
      ],
    );
    final edit = isSelf && onEdit != null
        ? OutlinedButton(
            key: const Key('profile-trade-edit'),
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: t.colors.textPrimary,
              side: BorderSide(color: t.surfaces.panel.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(data == null ? copy.setUp : copy.edit),
          )
        : null;
    final children = <Widget>[
      title,
      if (data == null)
        Text(
          isSelf ? copy.missingSelf : copy.missingOther,
          key: const Key('profile-trade-missing'),
          style: TextStyle(color: t.colors.textSecondary, fontSize: 12.5),
        )
      else ...[
        _Field(
          label: copy.days,
          isPublic: isSelf,
          copy: copy,
          child: _Days(data.localDays, copy.weekdays),
        ),
        _Field(
          label: isSelf ? copy.windowSelf : copy.windowOther,
          isPublic: isSelf,
          copy: copy,
          child: _Window(data, copy),
        ),
        if (data.contact case final String contact)
          _Field(label: copy.contact, copy: copy, child: _Value(contact)),
        if (data.reputation case final String reputation)
          _Field(label: copy.reputation, copy: copy, child: _Value(reputation)),
      ],
    ];
    return Column(
      key: const Key('profile-trade-strip'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, color: t.surfaces.panel.border),
        Padding(
          padding: EdgeInsets.only(top: t.space.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 22,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: children,
                ),
              ),
              if (edit != null) ...[const SizedBox(width: 12), edit],
            ],
          ),
        ),
      ],
    );
  }
}

/// One labelled value in a [ProfileFactSection].
@immutable
class ProfileFact {
  const ProfileFact(this.label, this.value, {this.warning = false});
  final String label;
  final String value;
  final bool warning;
}

/// The trade strip's look with the title on its own line, for a visitor page
/// that shows more than the trade days and window. [title] defaults to the
/// trade profile's own title; [window] is left out when it is unset.
class ProfileFactSection extends StatelessWidget {
  const ProfileFactSection({
    this.title,
    this.window,
    this.facts = const [],
    super.key,
  });

  final String? title;
  final ProfileTradeStripData? window;
  final List<ProfileFact> facts;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final copy = _ProfileTradeCopy.of(context);
    final window = this.window;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, color: t.surfaces.panel.border),
        SizedBox(height: t.space.lg),
        Row(
          children: [
            Text(
              title ?? copy.title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: t.colors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            const _ScmBadge(),
          ],
        ),
        if (window != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 22,
            runSpacing: 12,
            children: [
              _Field(
                label: copy.days,
                copy: copy,
                child: _Days(window.localDays, copy.weekdays),
              ),
              _Field(
                label: copy.windowOther,
                copy: copy,
                child: _Window(window, copy),
              ),
            ],
          ),
        ],
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              for (final fact in facts)
                _Field(
                  label: fact.label,
                  copy: copy,
                  child: _Value(
                    fact.value,
                    color: fact.warning ? t.colors.warning : null,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.child,
    required this.copy,
    this.isPublic = false,
  });
  final String label;
  final Widget child;
  final _ProfileTradeCopy copy;
  final bool isPublic;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
              ),
            ),
            if (isPublic) ...[
              const SizedBox(width: 6),
              Container(
                key: const Key('profile-trade-always-public'),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: t.colors.success.withValues(alpha: .55),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  copy.alwaysPublic,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: t.colors.success,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        child,
      ],
    );
  }
}

class _Days extends StatelessWidget {
  const _Days(this.days, this.labels);
  final List<bool> days;
  final List<String> labels;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          // The color alone would not tell a screen reader which days are on.
          Semantics(
            selected: i < days.length && days[i],
            child: Container(
              width: 26,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i < days.length && days[i]
                    ? t.colors.accent
                    : t.colors.textSecondary.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: i < days.length && days[i]
                      ? t.colors.onAccent
                      : t.colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Window extends StatelessWidget {
  const _Window(this.data, this.copy);
  final ProfileTradeStripData data;
  final _ProfileTradeCopy copy;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final open = data.openNow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wraps instead of overflowing in a narrow window or at large text.
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              data.localWindow,
              style: TextStyle(
                fontFamily: t.typography.monoFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.colors.textPrimary,
              ),
            ),
            if (open != null)
              Text(
                '● ${open ? copy.openNow : copy.closedNow}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: open ? t.colors.success : t.colors.textSecondary,
                ),
              ),
          ],
        ),
        if (data.ownerWindow case final String owner)
          Text(
            '${copy.ownerSetting} $owner',
            style: TextStyle(fontSize: 11.5, color: t.colors.textSecondary),
          ),
      ],
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.text, {this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: color ?? context.tokens.colors.textPrimary,
    ),
  );
}

class _ScmBadge extends StatelessWidget {
  const _ScmBadge();
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: t.surfaces.panel.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'SCM',
        style: TextStyle(
          fontFamily: t.typography.monoFamily,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: .5,
          color: t.colors.textSecondary,
        ),
      ),
    );
  }
}

class _ProfileTradeCopy {
  const _ProfileTradeCopy({
    required this.title,
    required this.days,
    required this.windowSelf,
    required this.windowOther,
    required this.alwaysPublic,
    required this.openNow,
    required this.closedNow,
    required this.ownerSetting,
    required this.contact,
    required this.reputation,
    required this.edit,
    required this.setUp,
    required this.missingSelf,
    required this.missingOther,
    required this.weekdays,
  });
  final String title, days, windowSelf, windowOther, alwaysPublic, openNow;
  final String closedNow, ownerSetting, contact, reputation, edit, setUp;
  final String missingSelf, missingOther;
  final List<String> weekdays;

  static _ProfileTradeCopy of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    if (locale?.languageCode == 'en') return _en;
    final hant =
        locale?.scriptCode == 'Hant' ||
        const {'TW', 'HK', 'MO'}.contains(locale?.countryCode);
    return hant ? _hant : _hans;
  }

  static const _hans = _ProfileTradeCopy(
    title: '交易资料',
    days: '交易日',
    windowSelf: '交易时段 · 本机时间',
    windowOther: '交易时段 · 你的本机时间',
    alwaysPublic: '始终公开',
    openNow: '现在可交易',
    closedNow: '不在交易时段',
    ownerSetting: '对方设置',
    contact: '联系方式',
    reputation: 'SCM 信誉',
    edit: '编辑交易资料',
    setUp: '设置交易资料',
    missingSelf: '还没有设置交易时段，别人看不到你什么时候能交易。',
    missingOther: '对方还没有设置交易时段。',
    weekdays: ['一', '二', '三', '四', '五', '六', '日'],
  );
  static const _hant = _ProfileTradeCopy(
    title: '交易資料',
    days: '交易日',
    windowSelf: '交易時段 · 本機時間',
    windowOther: '交易時段 · 你的本機時間',
    alwaysPublic: '始終公開',
    openNow: '現在可交易',
    closedNow: '不在交易時段',
    ownerSetting: '對方設定',
    contact: '聯絡方式',
    reputation: 'SCM 信譽',
    edit: '編輯交易資料',
    setUp: '設定交易資料',
    missingSelf: '還沒有設定交易時段，別人看不到你什麼時候能交易。',
    missingOther: '對方還沒有設定交易時段。',
    weekdays: ['一', '二', '三', '四', '五', '六', '日'],
  );
  static const _en = _ProfileTradeCopy(
    title: 'Trade profile',
    days: 'Trade days',
    windowSelf: 'Hours · local time',
    windowOther: 'Hours · your local time',
    alwaysPublic: 'Always public',
    openNow: 'Open now',
    closedNow: 'Closed now',
    ownerSetting: 'Their setting',
    contact: 'Contact',
    reputation: 'SCM reputation',
    edit: 'Edit trade profile',
    setUp: 'Set up trade profile',
    missingSelf: 'No trade hours yet, so others cannot see when you trade.',
    missingOther: 'No trade hours set yet.',
    weekdays: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
  );
}
