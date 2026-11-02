import '../communities/community_announcement_write_port.dart';

/// Optional official management protocol. Capability admission is not authority.
/// Native Host owns durable attempts; these types contain no raw authority/CAS.
abstract interface class OrganizationAnnouncementManagementPort {
  bool get managementAvailable;
  bool get outcomesAvailable;

  /// Account/generation/mode and outcome-capability retirement.
  Stream<void> get invalidations;

  /// Positive editor/manage retirement; does not retire valid own queries.
  Stream<void> get managementInvalidations;

  /// Releases only this borrowed facade lifetime, never the shared transport.
  Future<void> close();
  Future<OrganizationAnnouncementEditor> readEditor(String sourceRef);
  Future<OrganizationAnnouncementOutcome> manage(
    OrganizationAnnouncementIntent intent,
  );
  Future<OrganizationAnnouncementPendingPage> readPending({int offset = 0});
  Future<OrganizationAnnouncementOutcome> query(
    String requestId, {
    String? expectedSourceRef,
    String? expectedAction,
  });
}

final class OrganizationAnnouncementEditor {
  OrganizationAnnouncementEditor._(
    this.sourceRef,
    this.editRef,
    this.revision,
    this.allowedActions,
    this.current,
  );
  factory OrganizationAnnouncementEditor.parse(
    Map<String, Object?> row,
    String expectedSourceRef,
  ) {
    _keys(row, const {
      'schemaVersion',
      'state',
      'sourceRef',
      'editRef',
      'revision',
      'allowedActions',
      'current',
    });
    _schema(row);
    final source = _source(row['sourceRef']);
    if (source != _source(expectedSourceRef) || row['state'] != 'available') {
      throw const FormatException();
    }
    final current = row['current'] == null
        ? null
        : OrganizationAnnouncementEditorItem.parse(_object(row['current']));
    final actions = row['allowedActions'];
    final expected = current == null
        ? const ['publish']
        : const ['publish', 'edit', 'withdraw'];
    if (actions is! List || actions.length != expected.length) {
      throw const FormatException();
    }
    for (var i = 0; i < expected.length; i++) {
      if (actions[i] != expected[i]) throw const FormatException();
    }
    return OrganizationAnnouncementEditor._(
      source,
      _reference(row['editRef']),
      _revision(row['revision']),
      Set.unmodifiable(expected),
      current,
    );
  }
  final String sourceRef, editRef;
  final int revision;
  final Set<String> allowedActions;
  final OrganizationAnnouncementEditorItem? current;
}

final class OrganizationAnnouncementEditorItem {
  const OrganizationAnnouncementEditorItem._(
    this.announcementRef,
    this.title,
    this.content,
  );
  factory OrganizationAnnouncementEditorItem.parse(Map<String, Object?> row) {
    _keys(row, const {'announcementRef', 'title', 'content'});
    final reference = _reference(row['announcementRef']);
    final title = _text(row['title'], 48),
        content = _text(row['content'], 1200);
    // Preserve the accepted community normalization/limits, without a second
    // copy of the announcement policy. Editor text must already be canonical.
    final normalized = CommunityAnnouncementIntent(
      targetRef: reference,
      requestId: reference,
      action: 'publish',
      title: title,
      content: content,
    );
    if (title != normalized.title || content != normalized.content) {
      throw const FormatException();
    }
    return OrganizationAnnouncementEditorItem._(reference, title, content);
  }
  final String announcementRef, title, content;
}

final class OrganizationAnnouncementIntent {
  factory OrganizationAnnouncementIntent({
    required String sourceRef,
    required String editRef,
    required String requestId,
    required String action,
    String? announcementRef,
    String? title,
    String? content,
  }) {
    final value = CommunityAnnouncementIntent(
      targetRef: _reference(editRef),
      requestId: _reference(requestId),
      action: action,
      announcementRef: announcementRef,
      title: title,
      content: content,
    );
    return OrganizationAnnouncementIntent._(_source(sourceRef), value);
  }
  const OrganizationAnnouncementIntent._(this.sourceRef, this._value);
  factory OrganizationAnnouncementIntent.parse(Map<String, Object?> row) {
    final action = _action(row['action']);
    _keys(row, {
      'schemaVersion',
      'sourceRef',
      'editRef',
      'requestId',
      'action',
      if (action != 'publish') 'announcementRef',
      if (action != 'withdraw') ...['title', 'content'],
    });
    _schema(row);
    return OrganizationAnnouncementIntent(
      sourceRef: _source(row['sourceRef']),
      editRef: _reference(row['editRef']),
      requestId: _reference(row['requestId']),
      action: action,
      announcementRef: action == 'publish'
          ? null
          : _reference(row['announcementRef']),
      title: action == 'withdraw' ? null : _text(row['title'], 48),
      content: action == 'withdraw' ? null : _text(row['content'], 1200),
    );
  }
  final String sourceRef;
  final CommunityAnnouncementIntent _value;
  String get editRef => _value.targetRef;
  String get requestId => _value.requestId;
  String get action => _value.action;
  String? get announcementRef => _value.announcementRef;
  String? get title => _value.title;
  String? get content => _value.content;
  Map<String, Object?> toPayload() => {
    'schemaVersion': 1,
    'sourceRef': sourceRef,
    'editRef': editRef,
    'requestId': requestId,
    'action': action,
    if (action != 'publish') 'announcementRef': announcementRef,
    if (action != 'withdraw') ...{'title': title, 'content': content},
  };
}

final class OrganizationAnnouncementOutcome {
  const OrganizationAnnouncementOutcome._(
    this.requestId,
    this.status, {
    this.sourceRef,
    this.action,
    this.error,
    this.revision,
  });
  factory OrganizationAnnouncementOutcome.parseManage(
    Map<String, Object?> row,
    OrganizationAnnouncementIntent intent,
  ) {
    _keys(
      row,
      const {
        'schemaVersion',
        'sourceRef',
        'editRef',
        'requestId',
        'action',
        'status',
      },
      optional: const {'revision', 'error'},
    );
    _schema(row);
    if (row['sourceRef'] != intent.sourceRef ||
        row['editRef'] != intent.editRef ||
        row['requestId'] != intent.requestId ||
        row['action'] != intent.action) {
      throw const FormatException();
    }
    return _result(row, intent.requestId, intent.sourceRef, intent.action);
  }
  factory OrganizationAnnouncementOutcome.parseQuery(
    Map<String, Object?> row,
    String expectedRequestId, {
    String? expectedSourceRef,
    String? expectedAction,
  }) {
    _keys(
      row,
      const {'schemaVersion', 'kind', 'requestId', 'status'},
      optional: const {'sourceRef', 'action', 'revision', 'error'},
    );
    _schema(row);
    if (row['kind'] != 'query' ||
        row['requestId'] != _reference(expectedRequestId)) {
      throw const FormatException();
    }
    final absent = !row.containsKey('sourceRef') && !row.containsKey('action');
    if (absent) {
      if (row['status'] != 'unknown' || row['error'] != 'notFound') {
        throw const FormatException();
      }
      return _result(row, expectedRequestId, null, null);
    }
    final source = _source(row['sourceRef']), action = _action(row['action']);
    if (expectedSourceRef != null && source != expectedSourceRef ||
        expectedAction != null && action != expectedAction) {
      throw const FormatException();
    }
    return _result(row, expectedRequestId, source, action);
  }
  static OrganizationAnnouncementOutcome _result(
    Map<String, Object?> row,
    String id,
    String? source,
    String? action,
  ) {
    final status = row['status'], error = row['error'];
    if (!const {'accepted', 'rejected', 'unknown'}.contains(status) ||
        error != null &&
            (error is! String ||
                error.isEmpty ||
                error.length > 64 ||
                RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(error))) {
      throw const FormatException();
    }
    final revision = row['revision'];
    if (status == 'accepted') {
      if (error != null || _revision(revision) <= 0) {
        throw const FormatException();
      }
    } else if (revision != null) {
      throw const FormatException();
    }
    return OrganizationAnnouncementOutcome._(
      id,
      status as String,
      sourceRef: source,
      action: action,
      error: error as String?,
      revision: revision as int?,
    );
  }

  factory OrganizationAnnouncementOutcome.unknown(
    OrganizationAnnouncementIntent intent,
  ) => OrganizationAnnouncementOutcome._(
    intent.requestId,
    'unknown',
    sourceRef: intent.sourceRef,
    action: intent.action,
    error: 'outcomeUnknown',
  );
  factory OrganizationAnnouncementOutcome.unavailable(
    OrganizationAnnouncementIntent intent,
  ) => OrganizationAnnouncementOutcome._(
    intent.requestId,
    'rejected',
    sourceRef: intent.sourceRef,
    action: intent.action,
    error: 'unavailable',
  );
  final String requestId, status;
  final String? sourceRef, action, error;
  final int? revision;
  bool get unresolved => status == 'unknown';
}

final class OrganizationAnnouncementPending {
  const OrganizationAnnouncementPending._(
    this.requestId,
    this.sourceRef,
    this.action,
    this.requestedAt,
  );
  factory OrganizationAnnouncementPending.parse(Map<String, Object?> row) {
    _keys(row, const {
      'requestId',
      'sourceRef',
      'action',
      'requestedAt',
      'status',
    });
    final time = row['requestedAt'];
    if (row['status'] != 'unknown' ||
        time is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?(Z|\+00:00)$')
            .hasMatch(time)) {
      throw const FormatException();
    }
    final instant = DateTime.tryParse(time);
    if (instant == null ||
        !instant.isUtc ||
        instant.toIso8601String().substring(0, 19) != time.substring(0, 19)) {
      throw const FormatException();
    }
    return OrganizationAnnouncementPending._(
      _reference(row['requestId']),
      _source(row['sourceRef']),
      _action(row['action']),
      instant,
    );
  }
  final String requestId, sourceRef, action;
  final DateTime requestedAt;
}

final class OrganizationAnnouncementPendingPage {
  const OrganizationAnnouncementPendingPage._(
    this.offset,
    this.totalCount,
    this.next,
    this.items,
  );
  factory OrganizationAnnouncementPendingPage.parse(
    Map<String, Object?> row, {
    required int expectedOffset,
  }) {
    _keys(
      row,
      const {'schemaVersion', 'kind', 'offset', 'totalCount', 'items'},
      optional: const {'next'},
    );
    _schema(row);
    final offset = _revision(row['offset']),
        total = _revision(row['totalCount']);
    final values = row['items'];
    if (row['kind'] != 'pending' ||
        offset != expectedOffset ||
        offset % 20 != 0 ||
        offset > 127 ||
        total > 128 ||
        offset > total ||
        values is! List ||
        values.length != (total - offset).clamp(0, 20)) {
      throw const FormatException();
    }
    final terminal = offset + values.length == total;
    if (terminal
        ? row['next'] != null
        : row['next'] is! int || row['next'] != offset + 20) {
      throw const FormatException();
    }
    final items = values
        .map((v) => OrganizationAnnouncementPending.parse(_object(v)))
        .toList();
    if (items.map((v) => v.requestId).toSet().length != items.length) {
      throw const FormatException();
    }
    return OrganizationAnnouncementPendingPage._(
      offset,
      total,
      terminal ? null : offset + 20,
      List.unmodifiable(items),
    );
  }
  final int offset, totalCount;
  final int? next;
  final List<OrganizationAnnouncementPending> items;
}

void _keys(
  Map<String, Object?> row,
  Set<String> required, {
  Set<String> optional = const {},
}) {
  if (!row.keys.toSet().containsAll(required) ||
      row.keys.any((k) => !required.contains(k) && !optional.contains(k))) {
    throw const FormatException();
  }
}

void _schema(Map<String, Object?> row) {
  if (row['schemaVersion'] is! int || row['schemaVersion'] != 1) {
    throw const FormatException();
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) throw const FormatException();
  return value;
}

String _reference(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) {
    throw const FormatException();
  }
  return value;
}

String _source(Object? value) {
  if (value is! String ||
      !RegExp(r'^officialFleet:[1-9][0-9]{0,18}$').hasMatch(value) ||
      int.tryParse(value.substring(14)) == null) {
    throw const FormatException();
  }
  return value;
}

String _action(Object? value) {
  if (value is! String ||
      !const {'publish', 'edit', 'withdraw'}.contains(value)) {
    throw const FormatException();
  }
  return value;
}

int _revision(Object? value) {
  if (value is! int || value < 0 || value > 0x7fffffffffffffff) {
    throw const FormatException();
  }
  return value;
}

String _text(Object? value, int maximum) {
  if (value is! String || value.length > maximum) throw const FormatException();
  return value;
}
