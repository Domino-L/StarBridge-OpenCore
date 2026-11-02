final class CommunityCard {
  const CommunityCard({
    required this.targetRef,
    required this.name,
    this.description = '',
    this.organizationRef,
    this.tags = '',
    this.recruiting = false,
    this.recruitingTarget = '',
    this.recruitingNote = '',
    this.memberScale = '',
    this.systems = const [],
    this.language = '',
    this.activeTime = '',
    this.memberCount,
    this.relationship = 'none',
    this.joinMode = 'unavailable',
    this.actions = const [],
    this.logo,
    this.logoDeferred = false,
    this.displayOnly = false,
  });
  final String targetRef,
      name,
      description,
      language,
      activeTime,
      relationship,
      joinMode;
  final String? organizationRef;
  String get key => organizationRef ?? targetRef;
  final String tags, recruitingTarget, recruitingNote, memberScale;
  final bool recruiting;
  final List<String> systems;
  final int? memberCount;
  final List<String> actions;
  final String? logo;
  final bool logoDeferred;
  final bool displayOnly;

  /// Presentation bytes only; keep the current metadata and command admission.
  CommunityCard withDownloadedLogo(String image) => CommunityCard(
    targetRef: targetRef,
    organizationRef: organizationRef,
    name: name,
    description: description,
    tags: tags,
    recruiting: recruiting,
    recruitingTarget: recruitingTarget,
    recruitingNote: recruitingNote,
    memberScale: memberScale,
    systems: systems,
    language: language,
    activeTime: activeTime,
    memberCount: memberCount,
    relationship: relationship,
    joinMode: joinMode,
    actions: actions,
    logo: image,
    logoDeferred: logoDeferred,
    displayOnly: displayOnly,
  );

  CommunityCard withCachedLogo(String image) =>
      !displayOnly ? this : asDisplayOnly(image: image);

  CommunityCard asDisplayOnly({String? image}) => CommunityCard(
    targetRef: '',
    organizationRef: organizationRef ?? 'display:$targetRef',
    name: name,
    description: description,
    tags: tags,
    recruiting: recruiting,
    recruitingTarget: recruitingTarget,
    recruitingNote: recruitingNote,
    memberScale: memberScale,
    systems: systems,
    language: language,
    activeTime: activeTime,
    logo: image ?? logo,
    displayOnly: true,
  );

  CommunityCard withName(String value) => CommunityCard(
    targetRef: targetRef,
    organizationRef: organizationRef,
    name: value,
    description: description,
    tags: tags,
    recruiting: recruiting,
    recruitingTarget: recruitingTarget,
    recruitingNote: recruitingNote,
    memberScale: memberScale,
    systems: systems,
    language: language,
    activeTime: activeTime,
    memberCount: memberCount,
    relationship: relationship,
    joinMode: joinMode,
    actions: actions,
    logo: logo,
    logoDeferred: logoDeferred,
    displayOnly: displayOnly,
  );

  CommunityCard withoutDownloadedLogo() => CommunityCard(
    targetRef: targetRef,
    organizationRef: organizationRef,
    name: name,
    description: description,
    tags: tags,
    recruiting: recruiting,
    recruitingTarget: recruitingTarget,
    recruitingNote: recruitingNote,
    memberScale: memberScale,
    systems: systems,
    language: language,
    activeTime: activeTime,
    memberCount: memberCount,
    relationship: relationship,
    joinMode: joinMode,
    actions: actions,
    logoDeferred: logoDeferred,
    displayOnly: displayOnly,
  );
}

List<CommunityCard> withCachedCommunityLogo(
  List<CommunityCard> rows,
  String key,
  String image,
) => rows.any((row) => row.displayOnly && row.key == key && row.logo != image)
    ? List.unmodifiable(
        rows.map(
          (row) => row.displayOnly && row.key == key
              ? row.withCachedLogo(image)
              : row,
        ),
      )
    : rows;

final class CommunityDirectory {
  const CommunityDirectory(
    this.view,
    this.query,
    this.items, {
    this.next,
    this.totalCount,
    this.cachedAtUtc,
    this.cacheComplete = true,
    this.displayVersion,
  });
  final String view, query;
  final List<CommunityCard> items;
  final String? next;
  final int? totalCount;
  final DateTime? cachedAtUtc;
  final bool cacheComplete;
  final String? displayVersion;

  CommunityDirectory mapItems(CommunityCard Function(CommunityCard) update) =>
      CommunityDirectory(
        view,
        query,
        List.unmodifiable(items.map(update)),
        next: next,
        totalCount: totalCount,
        cachedAtUtc: cachedAtUtc,
        cacheComplete: cacheComplete,
        displayVersion: displayVersion,
      );

  CommunityDirectory withoutDownloadedLogos() =>
      mapItems((row) => row.withoutDownloadedLogo());

  CommunityDirectory withCachedLogo(String key, String image) {
    final rows = withCachedCommunityLogo(items, key, image);
    return identical(rows, items)
        ? this
        : CommunityDirectory(
            view,
            query,
            rows,
            next: next,
            totalCount: totalCount,
            cachedAtUtc: cachedAtUtc,
            cacheComplete: cacheComplete,
            displayVersion: displayVersion,
          );
  }

  CommunityDirectory asDisplayOnly(DateTime? observedAt) => CommunityDirectory(
    view,
    query,
    List.unmodifiable(items.map((row) => row.asDisplayOnly())),
    cachedAtUtc: cachedAtUtc ?? observedAt?.toUtc(),
    cacheComplete: cacheComplete && next == null,
    displayVersion: displayVersion,
  );
}
