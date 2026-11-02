import '../communities/community_hangar_sharing_port.dart';
import 'organization_ship_image_features.dart';

/// Shared editor contract. Organization audience refs and private ship-instance
/// refs have distinct modes and limits; neither is an authorization credential.
enum OrganizationSharingMode { audiences, instances }

abstract interface class OrganizationHangarImageConsentPort {
  Future<CommunityHangarSharingOutcome> clearImages(
    String editRef,
    String sourceRef,
  );
}

abstract interface class OrganizationHangarSharingPort {
  Stream<void> get invalidations;
  bool get available;
  Future<OrganizationSharingDraft> read(String? sourceRef, {String? scopeRef});
  Future<OrganizationSharingPage> page(
    String editRef,
    String sourceRef,
    int offset,
  );
  Future<CommunityHangarSharingOutcome> save(
    String editRef,
    String? sourceRef,
    String? strategy,
    List<String> selectedRefs, {
    bool includeImages = false,
  });
  Future<void> close();
}

final class OrganizationSharingScope {
  const OrganizationSharingScope(this.reference, this.name, this.isCurrent);
  final String reference, name;
  final bool isCurrent;
}

final class OrganizationSharingOption {
  const OrganizationSharingOption(
    this.reference,
    this.name, {
    this.missing = false,
    this.grantable = true,
  });
  final String reference;
  final String? name;
  final bool missing, grantable;
}

final class OrganizationSharingPage {
  const OrganizationSharingPage(
    this.editRef,
    this.offset,
    this.totalOptions,
    this.next,
    this.options,
  );
  final String editRef;
  final int offset, totalOptions;
  final int? next;
  final List<OrganizationSharingOption> options;
  factory OrganizationSharingPage.parse(Map<String, Object?> value) {
    _only(value, {
      'schemaVersion',
      'editRef',
      'offset',
      'totalOptions',
      // Retained V1 Host editors may omit a null continuation. The count/row
      // checks below still prove terminal; omission on a partial page fails.
      if (value.containsKey('next')) 'next',
      'options',
    });
    final edit = value['editRef'],
        offset = value['offset'],
        total = value['totalOptions'],
        next = value['next'],
        rows = value['options'];
    if (value['schemaVersion'] != 1 ||
        !_ref(edit) ||
        offset is! int ||
        offset < 0 ||
        offset % 100 != 0 ||
        total is! int ||
        total < 0 ||
        total > 20000 ||
        offset > total ||
        rows is! List ||
        rows.length > 100 ||
        rows.length != (total - offset).clamp(0, 100) ||
        next != (offset + rows.length < total ? offset + rows.length : null)) {
      throw const FormatException('Invalid instance selection page.');
    }
    final seen = <String>{};
    final options = <OrganizationSharingOption>[];
    for (final raw in rows) {
      if (raw is! Map) throw const FormatException();
      final row = raw.cast<String, Object?>();
      _only(row, {'shipRef', 'name', 'missing', 'grantable'});
      final reference = row['shipRef'],
          name = row['name'],
          missing = row['missing'],
          grantable = row['grantable'];
      if (!_ref(reference) ||
          !seen.add(reference as String) ||
          missing is! bool ||
          grantable is! bool ||
          missing == grantable ||
          name != null && !_label(name, 512) ||
          !missing && name == null) {
        throw const FormatException();
      }
      options.add(
        OrganizationSharingOption(
          reference,
          name as String?,
          missing: missing,
          grantable: grantable,
        ),
      );
    }
    return OrganizationSharingPage(
      edit as String,
      offset,
      total,
      next as int?,
      List.unmodifiable(options),
    );
  }
}

final class OrganizationSharingDraft {
  const OrganizationSharingDraft({
    required this.mode,
    required this.editRef,
    required this.state,
    required this.page,
    required this.selectedRefs,
    required this.maximumSelected,
    this.sourceRef,
    this.strategy,
    this.scopes = const [],
    this.scopeRef,
    this.inventoryState = 'complete',
    this.canGrant = true,
    this.canPublish = true,
    this.canReduce = true,
    this.selectionKnown = true,
    this.selectedCount = 0,
    this.explicit = true,
    this.allowImages = false,
    this.imageFeatures,
    this.imageCount = 0,
    this.canClearImages = false,
  });
  final OrganizationSharingMode mode;
  final String editRef, state, inventoryState;
  final String? sourceRef, strategy, scopeRef;
  final OrganizationSharingPage page;
  final List<String> selectedRefs;
  final List<OrganizationSharingScope> scopes;
  final int maximumSelected, selectedCount;
  final bool canGrant,
      canPublish,
      canReduce,
      selectionKnown,
      explicit,
      allowImages;
  final OrganizationShipImageFeatures? imageFeatures;
  final int imageCount;
  final bool canClearImages;

  factory OrganizationSharingDraft.parseOfficial(
    Map<String, Object?> value, {
    bool imageProtocolSupported = false,
  }) {
    final images = value.containsKey('imageFeatures');
    _only(value, {
      'schemaVersion',
      'editRef',
      // The Bridge writes no key for a null value; the checks below decide
      // whether these may be absent, exactly as if they were null.
      if (value.containsKey('sourceRef')) 'sourceRef',
      'state',
      if (value.containsKey('strategy')) 'strategy',
      'inventoryState',
      'canGrant',
      'canPublish',
      'canReduce',
      'selectionKnown',
      'selectedCount',
      'maximumSelected',
      'selectedRefs',
      'scopes',
      if (value.containsKey('scopeRef')) 'scopeRef',
      'page',
      if (images) ...{'imageFeatures', 'imageCount', 'canClearImages'},
    });
    final edit = value['editRef'],
        source = value['sourceRef'],
        state = value['state'],
        strategy = value['strategy'],
        inventory = value['inventoryState'];
    final selected = value['selectedRefs'],
        scopes = value['scopes'],
        scope = value['scopeRef'],
        count = value['selectedCount'];
    if (value['schemaVersion'] != 1 ||
        !_ref(edit) ||
        source != null && !_source(source) ||
        !const {
          'available',
          'selectionRequired',
          'stale',
          'unavailable',
          'forbidden',
        }.contains(state) ||
        !const {
          null,
          'notShared',
          'organizationPool',
          'operationOnly',
        }.contains(strategy) ||
        !const {
          'complete',
          'missing',
          'partial',
          'unavailable',
        }.contains(inventory) ||
        value['maximumSelected'] != 10000 ||
        count is! int ||
        count < 0 ||
        count > 10000 ||
        selected is! List ||
        selected.length > 10000 ||
        selected.any((entry) => !_ref(entry)) ||
        selected.toSet().length != selected.length ||
        scopes is! List ||
        scopes.length > 101 ||
        scope != null && !_ref(scope) ||
        [
          'canGrant',
          'canPublish',
          'canReduce',
          'selectionKnown',
        ].any((key) => value[key] is! bool)) {
      throw const FormatException();
    }
    final canGrant = value['canGrant'] as bool,
        canPublish = value['canPublish'] as bool,
        canReduce = value['canReduce'] as bool;
    final known = value['selectionKnown'] as bool;
    final features = images
        ? OrganizationShipImageFeatures.parse(value['imageFeatures'])
        : null;
    final imageCount = images ? value['imageCount'] : 0;
    final canClearImages = images ? value['canClearImages'] : false;
    if (imageCount is! int ||
        imageCount < 0 ||
        imageCount > 10000 ||
        canClearImages is! bool ||
        canClearImages &&
            (!canReduce || features?.reduce != true || imageCount == 0)) {
      throw const FormatException('Invalid image consent facts.');
    }
    if (canPublish && (!canGrant || inventory != 'complete') ||
        (canGrant || canReduce) && (scope == null || source == null) ||
        known && selected.length != count ||
        !known && selected.isNotEmpty ||
        strategy != 'organizationPool' && count != 0) {
      throw const FormatException();
    }
    final seen = <String>{}, entries = <OrganizationSharingScope>[];
    for (final raw in scopes) {
      if (raw is! Map) throw const FormatException();
      final row = raw.cast<String, Object?>();
      _only(row, {'scopeRef', 'name', 'isCurrent'});
      final reference = row['scopeRef'],
          name = row['name'],
          current = row['isCurrent'];
      if (!_ref(reference) ||
          !seen.add(reference as String) ||
          !_label(name, 10) ||
          current is! bool) {
        throw const FormatException();
      }
      entries.add(OrganizationSharingScope(reference, name as String, current));
    }
    if (scope != null && !seen.contains(scope)) throw const FormatException();
    final rawPage = value['page'];
    if (rawPage is! Map) throw const FormatException();
    final page = OrganizationSharingPage.parse(rawPage.cast<String, Object?>());
    if (page.editRef != edit || page.offset != 0) throw const FormatException();
    return OrganizationSharingDraft(
      mode: OrganizationSharingMode.instances,
      editRef: edit as String,
      sourceRef: source as String?,
      state: state as String,
      strategy: strategy as String?,
      inventoryState: inventory as String,
      canGrant: canGrant,
      canPublish: canPublish,
      canReduce: canReduce,
      selectionKnown: known,
      selectedCount: count,
      maximumSelected: 10000,
      selectedRefs: List.unmodifiable(selected.cast<String>()),
      scopes: List.unmodifiable(entries),
      scopeRef: scope as String?,
      page: page,
      explicit: strategy != null,
      imageFeatures: features,
      imageCount: imageCount,
      allowImages:
          imageProtocolSupported && features?.complete == true && canPublish,
      canClearImages: imageProtocolSupported && canClearImages,
    );
  }
}

bool validOrganizationSharingReference(Object? value) => _ref(value);
bool _ref(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
bool _source(Object? value) =>
    value is String &&
    RegExp(r'^officialFleet:[1-9][0-9]{0,18}$').hasMatch(value);
bool _label(Object? value, int maximum) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= maximum &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
void _only(Map<String, Object?> value, Set<String> keys) {
  if (value.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(value.keys.toSet()).isNotEmpty) {
    throw const FormatException();
  }
}
