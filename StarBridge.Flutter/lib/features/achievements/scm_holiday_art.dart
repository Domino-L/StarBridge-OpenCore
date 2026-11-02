import 'achievement_catalog.dart';

// Exact display titles verified against the SCM holiday collection screenshot.
// Do not guess SCM numeric IDs or use substring matching across other categories.
const _holidaySlugs = <String, String>{
  '新春快乐': 'spring-festival',
  '辞旧迎新': 'new-years-eve',
  '花灯初上': 'lantern-festival',
  '粽情端午': 'dragon-boat',
  '鹊桥相会': 'qixi',
  '月圆人团圆': 'mid-autumn',
  '腊八寒冬': 'laba',
  '新年新气象': 'new-year',
  '星际有情人': 'valentine',
  '星际整蛊师': 'april-fools',
  '星际劳模': 'labor-day',
  '童心未泯': 'childrens-day',
  '星际鬼才': 'halloween',
  '星际圣诞': 'christmas',
  // 10-29 补的两张（用户确认），标题取自用户的 SCM 截图。
  '登高望远': 'double-ninth',
  '国庆节': 'national-day',
};

// Daily and limited-event titles from the approved art delivery's category
// table (achievement_final_delivery_v1/分类对照.tsv), matched exactly.
const _dailySlugs = <String, String>{
  '萌新启航': 'account-rookie',
  '中登': 'account-regular',
  '纵横星海': 'account-veteran',
  '攻略新手': 'guide-beginner',
  '攻略达人': 'guide-adept',
  '攻略大师': 'guide-master',
  '初涉商海': 'trade-beginner',
  '商业精英': 'trade-adept',
  '商业大亨': 'trade-master',
  '猎头帮': 'bounty-beginner',
  '猎头帮首脑': 'bounty-leader',
};

const _limitedEventSlugs = <String, String>{
  '春节精英': 'spring-elite',
  '签到达人': 'checkin-streak',
  '春节欢庆': 'spring-participant',
};

/// One bundled SCM artwork: a raster WebP or a flat vector SVG.
typedef ScmArtAsset = ({String path, bool vector});

/// Artwork selection only; never changes ownership, progress, or unlock dates.
/// Hidden achievements never get artwork, so it cannot reveal them.
/// Unearned rows use the paired blue-grey locked artwork from the delivery,
/// never a runtime grayscale filter.
ScmArtAsset? scmAchievementArtAsset(
  AchievementDefinition definition, {
  required bool earned,
  required double logicalSize,
  required double devicePixelRatio,
}) {
  if (definition.source != AchievementSource.scm) return null;
  final title = definition.serverName?.trim();
  final state = earned ? '' : '-locked';
  switch (definition.groupId) {
    case 'scm-HOLIDAY':
      final slug = _holidaySlugs[title];
      if (slug == null) return null;
      // The delivery ships a 192 list image and a 512 detail image only.
      final resolution = logicalSize * devicePixelRatio <= 192 ? 192 : 512;
      return (
        path: 'assets/achievements/scm-holiday-$slug$state-$resolution.webp',
        vector: false,
      );
    case 'scm-NORMAL' || 'scm-SPECIAL':
      final slug = _dailySlugs[title];
      return slug == null
          ? null
          : (
              path: 'assets/achievements/scm-daily-$slug$state.svg',
              vector: true,
            );
    case 'scm-EVENT_LIMITED':
      final slug = _limitedEventSlugs[title];
      return slug == null
          ? null
          : (
              path: 'assets/achievements/scm-event-$slug$state.svg',
              vector: true,
            );
  }
  return null;
}
