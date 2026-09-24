import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// All targets are short-lived Host-issued references, never account IDs.
abstract interface class CommunityWorkspacePort {
  Stream<void> get invalidations;
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  );
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  });
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException();
  return Map<String, Object?>.from(value);
}

String _text(Map<String, Object?> map, String key, [int max = 512]) {
  final value = map[key];
  if (value is! String || value.length > max) throw const FormatException();
  return value;
}

String? _optional(Map<String, Object?> map, String key, [int max = 512]) =>
    map[key] == null ? null : _text(map, key, max);

bool _flag(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) throw const FormatException();
  return value;
}

int _number(Map<String, Object?> map, String key, [int max = 1000000]) {
  final value = map[key];
  if (value is! int || value < 0 || value > max) throw const FormatException();
  return value;
}

List<Object?> _rows(Map<String, Object?> map, String key, int max) {
  final value = map[key];
  if (value is! List || value.length > max) throw const FormatException();
  return value;
}

List<String> _strings(Map<String, Object?> map, String key) =>
    List.unmodifiable(
      _rows(map, key, 20).map((v) {
        if (v is! String || v.length > 128) throw const FormatException();
        return v;
      }),
    );

DateTime? _date(Map<String, Object?> map, String key) {
  final value = _optional(map, key, 64);
  if (value == null) return null;
  return DateTime.tryParse(value) ?? (throw const FormatException());
}

final class CommunityWorkspaceMember {
  CommunityWorkspaceMember.parse(Map<String, Object?> m)
    : memberRef = _text(m, 'memberRef', 32),
      gameName = _text(m, 'gameName'),
      callsign = _text(m, 'callsign'),
      roleTitle = _text(m, 'roleTitle', 128),
      roleColor = _text(m, 'roleColor', 7),
      isSelf = _flag(m, 'isSelf'),
      isOwner = _flag(m, 'isOwner'),
      online = _flag(m, 'online'),
      hasAvatar = _flag(m, 'hasAvatar'),
      avatarVersion = _optional(m, 'avatarVersion'),
      liveStatus = _text(m, 'liveStatus', 64),
      ship = _optional(m, 'ship'),
      location = _optional(m, 'location'),
      locationConfidence = _optional(m, 'locationConfidence'),
      serverRegion = _optional(m, 'serverRegion'),
      hasServerSession = m['hasServerSession'] == null
          ? null
          : m['hasServerSession'] is bool
          ? m['hasServerSession'] as bool
          : (throw const FormatException()),
      arrivalPendingConfirmation = _flag(m, 'arrivalPendingConfirmation'),
      arrivalTargetCode = _optional(m, 'arrivalTargetCode'),
      joinedAt = _date(m, 'joinedAt'),
      lastUpdated = _date(m, 'lastUpdated') {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(memberRef) ||
        avatarVersion != null &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(avatarVersion!) ||
        !RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(roleColor)) {
      throw const FormatException();
    }
  }
  final String memberRef, gameName, callsign, roleTitle, roleColor, liveStatus;
  final String? avatarVersion;
  final bool? hasServerSession;
  final bool isSelf, isOwner, online, hasAvatar, arrivalPendingConfirmation;
  final String? ship,
      location,
      locationConfidence,
      serverRegion,
      arrivalTargetCode;
  final DateTime? joinedAt, lastUpdated;
  String get displayName => callsign.isEmpty ? gameName : callsign;
}

final class CommunityActivityWindow {
  CommunityActivityWindow.parse(Map<String, Object?> m)
    : days = _strings(m, 'days'),
      startTime = _text(m, 'startTime', 5),
      endTime = _text(m, 'endTime', 5),
      endsNextDay = _flag(m, 'endsNextDay');
  final List<String> days;
  final String startTime, endTime;
  final bool endsNextDay;
}

final class CommunityWorkspace {
  CommunityWorkspace.parse(Map<String, Object?> m)
    : targetRef = _text(m, 'targetRef', 32),
      code = _text(m, 'code', 256),
      name = _text(m, 'name'),
      description = _text(m, 'description', 8192),
      tags = _text(m, 'tags', 2048),
      language = _text(m, 'language'),
      activeTime = _text(m, 'activeTime', 1024),
      query = _text(m, 'query', 128),
      timeZoneId = _optional(m, 'timeZoneId', 128),
      timeZoneStandardOffsetMinutes =
          m['timeZoneStandardOffsetMinutes'] is int &&
              (m['timeZoneStandardOffsetMinutes'] as int).abs() <= 840
          ? m['timeZoneStandardOffsetMinutes'] as int
          : null,
      timeZoneUsesDaylightSaving = m['timeZoneUsesDaylightSaving'] == true,
      websiteUrl = _optional(m, 'websiteUrl', 2048),
      offset = _number(m, 'offset'),
      totalCount = _number(m, 'totalCount'),
      matchedCount = _number(m, 'matchedCount'),
      next = m['next'] == null ? null : _number(m, 'next'),
      hasLogo = _flag(m, 'hasLogo'),
      hasBanner = _flag(m, 'hasBanner'),
      fetchedAt = _date(m, 'fetchedAt') ?? (throw const FormatException()),
      activeSystemIds = _strings(m, 'activeSystemIds'),
      activityWindows = List.unmodifiable(
        _rows(
          m,
          'activityWindows',
          3,
        ).map((v) => CommunityActivityWindow.parse(_map(v))),
      ),
      externalContacts = List.unmodifiable(
        _rows(m, 'externalContacts', 100).map((v) {
          final row = _map(v);
          return (_text(row, 'platform', 128), _text(row, 'value', 2048));
        }),
      ),
      access = Map.unmodifiable({
        for (final key in const [
          'isOwner',
          'canEditProfile',
          'canReviewApplications',
          'canRemoveMembers',
          'canCreateInvite',
          'canManageAnnouncements',
        ])
          key: _flag(_map(m['access']), key),
        for (final key in const ['canEditLogo', 'canEditBanner', 'canViewLogs'])
          key: _map(m['access']).containsKey(key)
              ? _flag(_map(m['access']), key)
              : false,
      }),
      members = List.unmodifiable(
        _rows(
          m,
          'members',
          20,
        ).map((v) => CommunityWorkspaceMember.parse(_map(v))),
      ) {
    if (m['schemaVersion'] != 1 ||
        targetRef.isEmpty ||
        matchedCount > totalCount ||
        offset > matchedCount ||
        members.length != (matchedCount - offset).clamp(0, 20) ||
        next !=
            (offset + members.length < matchedCount
                ? offset + members.length
                : null) ||
        members.map((v) => v.memberRef).toSet().length != members.length) {
      throw const FormatException();
    }
  }
  final String targetRef,
      code,
      name,
      description,
      tags,
      language,
      activeTime,
      query;
  final String? timeZoneId, websiteUrl;
  final int? timeZoneStandardOffsetMinutes;
  final bool timeZoneUsesDaylightSaving;
  final int offset, totalCount, matchedCount;
  final int? next;
  final bool hasLogo, hasBanner;
  final DateTime fetchedAt;
  final List<String> activeSystemIds;
  final List<CommunityActivityWindow> activityWindows;
  final List<(String, String)> externalContacts;
  final Map<String, bool> access;
  final List<CommunityWorkspaceMember> members;
}

/// No partially received image reaches a decoder. The caller guards account/org
/// generation between chunks and owns the lifetime of the completed bytes.
Future<Uint8List> assembleCommunityMedia(
  Future<Map<String, Object?>> Function(int offset, String? version) read,
  String kind, {
  String? memberRef,
  required void Function() checkCurrent,
}) async {
  if (!const {'logo', 'banner', 'avatar', 'applicant'}.contains(kind) ||
      (kind == 'avatar' || kind == 'applicant') != (memberRef != null)) {
    throw const FormatException();
  }
  final bytes = BytesBuilder(copy: false);
  String? hash, mime;
  int? total;
  var offset = 0;
  while (true) {
    checkCurrent();
    final row = await read(offset, hash);
    checkCurrent();
    final currentHash = _text(row, 'version', 64);
    final currentMime = _text(row, 'mimeType', 32);
    final currentTotal = _number(
      row,
      'totalBytes',
      kind == 'banner' ? 2 * 1024 * 1024 : 512 * 1024,
    );
    if (row['schemaVersion'] != 1 ||
        row['kind'] != kind ||
        row['memberRef'] != memberRef ||
        row['offset'] != offset ||
        currentTotal <= offset ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(currentHash) ||
        !const {
          'image/png',
          'image/jpeg',
          'image/bmp',
          'image/gif',
          'image/webp',
        }.contains(currentMime) ||
        hash != null &&
            (hash != currentHash ||
                mime != currentMime ||
                total != currentTotal)) {
      throw const FormatException();
    }
    hash = currentHash;
    mime = currentMime;
    total = currentTotal;
    final chunk = base64Decode(_text(row, 'data', 256 * 1024));
    if (chunk.length != (total - offset).clamp(0, 192 * 1024)) {
      throw const FormatException();
    }
    offset += chunk.length;
    if (row['next'] != (offset < total ? offset : null)) {
      throw const FormatException();
    }
    bytes.add(chunk);
    if (offset == total) break;
  }
  final result = bytes.takeBytes();
  if (sha256.convert(result).toString() != hash) throw const FormatException();
  checkCurrent();
  return result;
}
