abstract interface class CommunityProfilePort {
  Stream<void> get invalidations;
  Future<CommunityEditingProfile> readProfile({
    String? targetRef,
    String? editRef,
  });
  Future<CommunityProfileOutcome> saveProfile(
    String requestId,
    String editRef,
    Map<String, Object?> changes,
  );
}

const communityProfileTextLimits = <String, int>{
  'name': 512,
  'description': 8192,
  'type': 2048,
  'activeTime': 1024,
  'joinPolicy': 32,
  'logoText': 128,
  'activeDaysDescription': 1024,
  'activityCadence': 128,
  'timeZoneId': 128,
  'recruitingTarget': 512,
  'recruitingNote': 2048,
  'inviteCodeCreationPolicy': 32,
  'fleetInvitationCardPolicy': 32,
  'publicMemberScaleMode': 32,
  'publicShipScaleMode': 32,
  'language': 512,
  'websiteUrl': 2048,
};
const communityProfileFlags = <String>{
  'emailNotificationsEnabled',
  'recruitingEnabled',
  'publicListingEnabled',
  'publicShowDescription',
  'publicShowTags',
  'publicShowActiveSystems',
  'publicShowActivityTime',
  'publicShowExternalContacts',
};

final class CommunityEditingProfile {
  const CommunityEditingProfile._(
    this.targetRef,
    this.editRef,
    this.code,
    this.name,
    this.revision,
    this.hasLogo,
    this.hasBanner,
    this.canEditProfile,
    this.canEditLogo,
    this.canEditBanner,
    this.fields,
  );
  final String targetRef, editRef, code, name;
  final int revision;
  final bool hasLogo, hasBanner, canEditProfile, canEditLogo, canEditBanner;
  final Map<String, Object?> fields;

  bool permits(String field) => switch (field) {
    'logoText' || 'logoImageData' || 'clearLogoImage' => canEditLogo,
    'clearBannerImage' => canEditBanner,
    _ => canEditProfile,
  };

  factory CommunityEditingProfile.parse(Map<String, Object?> payload) {
    if (payload['schemaVersion'] != 1) throw const FormatException();
    final reference = RegExp(r'^[a-f0-9]{32}$');
    final targetRef = _text(payload, 'targetRef', 32);
    final editRef = _text(payload, 'editRef', 32);
    if (!reference.hasMatch(targetRef) || !reference.hasMatch(editRef)) {
      throw const FormatException();
    }
    final revision = payload['profileRevision'];
    if (revision is! int || revision < 0 || revision > 9007199254740991) {
      throw const FormatException();
    }
    final source = _map(payload['profile']);
    final fields = <String, Object?>{};
    for (final entry in communityProfileTextLimits.entries) {
      if (entry.key == 'name') {
        fields['name'] = _text(payload, 'name', 512);
        continue;
      }
      if (!source.containsKey(entry.key)) throw const FormatException();
      fields[entry.key] = source[entry.key] == null
          ? null
          : _text(source, entry.key, entry.value);
    }
    for (final key in communityProfileFlags) {
      fields[key] = _flag(source, key);
    }
    fields['activeSystemIds'] = _strings(source['activeSystemIds'], 32, 128);
    fields['activityWindows'] = List.unmodifiable(
      _rows(source['activityWindows'], 3).map(
        (r) => Map<String, Object?>.unmodifiable({
          'days': _strings(r['days'], 7, 16),
          'startTime': _text(r, 'startTime', 5),
          'endTime': _text(r, 'endTime', 5),
          'endsNextDay': _flag(r, 'endsNextDay'),
        }),
      ),
    );
    fields['externalContacts'] = List.unmodifiable(
      _rows(source['externalContacts'], 5).map(
        (r) => Map<String, Object?>.unmodifiable({
          'platform': _text(r, 'platform', 128),
          'value': _text(r, 'value', 2048),
        }),
      ),
    );
    final access = _map(payload['access']);
    final profile = _flag(access, 'canEditProfile');
    final logo = _flag(access, 'canEditLogo');
    final banner = _flag(access, 'canEditBanner');
    if (!profile && !logo && !banner) throw const FormatException();
    final code = _text(payload, 'code', 256);
    final name = _text(payload, 'name', 512);
    if (code.isEmpty || name.isEmpty) throw const FormatException();
    return CommunityEditingProfile._(
      targetRef,
      editRef,
      code,
      name,
      revision,
      _flag(payload, 'hasLogo'),
      _flag(payload, 'hasBanner'),
      profile,
      logo,
      banner,
      Map.unmodifiable(fields),
    );
  }
}

final class CommunityProfileOutcome {
  const CommunityProfileOutcome(this.status, {this.error, this.revision});
  final String status;
  final String? error;
  final int? revision;
  factory CommunityProfileOutcome.parse(Map<String, Object?> value) {
    if (value['schemaVersion'] != 1) throw const FormatException();
    final status = value['status'];
    if (!const {'accepted', 'rejected', 'unknown'}.contains(status)) {
      throw const FormatException();
    }
    final revision = value['profileRevision'];
    if (status == 'accepted' &&
        (revision is! int || revision < 1 || revision > 9007199254740991)) {
      throw const FormatException();
    }
    final error = value['error'];
    if (error != null && (error is! String || error.length > 128)) {
      throw const FormatException();
    }
    return CommunityProfileOutcome(
      status as String,
      error: error as String?,
      revision: status == 'accepted' ? revision as int : null,
    );
  }
}

// Validate and freeze only explicit changes. Unchanged legacy values stay intact;
// the Host and existing Relay handler remain authoritative for domain policy.
Object? communityProfileChange(String field, Object? value) {
  final max = communityProfileTextLimits[field];
  if (max != null) {
    if (value is! String || value.length > max) throw const FormatException();
    return value;
  }
  if (communityProfileFlags.contains(field) ||
      field == 'clearLogoImage' ||
      field == 'clearBannerImage') {
    if (value is! bool) throw const FormatException();
    return value;
  }
  if (field == 'logoImageData') {
    if (value is! String ||
        value.length > 700000 ||
        !RegExp(r'^data:image/(png|jpeg|bmp);base64,').hasMatch(value)) {
      throw const FormatException();
    }
    return value;
  }
  if (field == 'activeSystemIds') return _strings(value, 3, 32);
  if (field == 'externalContacts') {
    return List.unmodifiable(
      _rows(value, 5).map(
        (r) => Map<String, Object?>.unmodifiable({
          'platform': _text(r, 'platform', 128),
          'value': _text(r, 'value', 2048),
        }),
      ),
    );
  }
  if (field == 'activityWindows') {
    return List.unmodifiable(
      _rows(value, 3).map(
        (r) => Map<String, Object?>.unmodifiable({
          'days': _strings(r['days'], 7, 16),
          'startTime': _text(r, 'startTime', 5),
          'endTime': _text(r, 'endTime', 5),
          'endsNextDay': _flag(r, 'endsNextDay'),
        }),
      ),
    );
  }
  throw const FormatException();
}

bool communityProfileEqual(Object? a, Object? b) {
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (i) => communityProfileEqual(a[i], b[i]),
        ).every((e) => e);
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (k) => b.containsKey(k) && communityProfileEqual(a[k], b[k]),
        );
  }
  return a == b;
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException();
  return Map<String, Object?>.from(value);
}

String _text(Map<String, Object?> value, String key, int max) {
  final result = value[key];
  if (result is! String || result.length > max) throw const FormatException();
  return result;
}

bool _flag(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! bool) throw const FormatException();
  return result;
}

List<Map<String, Object?>> _rows(Object? value, int max) {
  if (value is! List || value.length > max) throw const FormatException();
  return value.map(_map).toList();
}

List<String> _strings(Object? value, int max, int textMax) {
  if (value is! List ||
      value.length > max ||
      value.any((v) => v is! String || v.length > textMax)) {
    throw const FormatException();
  }
  return List<String>.unmodifiable(value);
}
