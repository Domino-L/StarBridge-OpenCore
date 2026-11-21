import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:starbridge_flutter/features/tools/catalog_port.dart';
import 'package:starbridge_flutter/features/tools/mission_records_port.dart';

import 'catalog_samples.dart';

CatalogRow record({
  String key = missionGuid,
  String? definitionId = missionGuid,
  String? code = 'delivery_contract_073',
  int count = 3,
  int? fastest = 3900,
  String date = '2026-11-09T10:00:00Z',
  int? solo,
  int? team,
  int? joinedFull,
  int? joinedPartial,
}) => {
  'key': key,
  'definitionId': definitionId,
  'contractCode': code,
  'count': count,
  'fastestSeconds': fastest,
  'lastCompletedAt': date,
  'soloFastestSeconds': ?solo,
  'teamFastestSeconds': ?team,
  'joinedFullFastestSeconds': ?joinedFull,
  'joinedPartialFastestSeconds': ?joinedPartial,
};

final class RecordsPort extends ChangeNotifier implements MissionRecordsPort {
  @override
  bool supported = true;
  bool online = true;
  @override
  bool get readable => supported && online;
  @override
  bool importSupported = true;
  final calls = <String>[];
  CatalogRow summary = {
    'schemaVersion': 1,
    'groups': [record()],
    'total': 3,
    'importAvailable': true,
  };
  CatalogRow progress = {
    'schemaVersion': 1,
    'phase': 'scanning',
    'filesTotal': 5,
    'filesDone': 2,
    'bytesTotal': 100,
    'bytesDone': 40,
  };
  Completer<CatalogRow>? heldStart, heldSummary, heldRead;
  MissionRecordsFailure? failure, startFailure;
  @override
  Future<CatalogRow> request(
    String operation, [
    CatalogRow input = const {},
  ]) async {
    calls.add(operation);
    if (failure != null) throw failure!;
    if (operation == 'importStart' && startFailure != null) throw startFailure!;
    switch (operation) {
      case 'summary':
        return await (heldSummary?.future ?? Future<CatalogRow>.value(summary));
      case 'importStart':
        return await (heldStart?.future ??
            Future<CatalogRow>.value({
              'scanId': '07307307307307307307307307307307',
            }));
      case 'importRead':
        return await (heldRead?.future ?? Future<CatalogRow>.value(progress));
      case 'importCancel':
        progress = {'schemaVersion': 1, 'phase': 'cancelled'};
        return {'schemaVersion': 1, 'cancelled': true};
    }
    throw StateError(operation);
  }

  void retire({bool offline = true}) {
    online = !offline;
    notifyListeners();
  }

  void completeImport({int skipped = 1}) {
    progress = {
      'schemaVersion': 1,
      'phase': 'done',
      'result': {
        'filesScanned': 5,
        'filesSkipped': skipped,
        'completedFound': 7,
        'added': 4,
        'alreadyKnown': 3,
      },
    };
  }
}

class RecordCatalog extends SampleCatalogPort {
  CatalogRow? response = missionSample;
  Completer<CatalogRow>? held;
  @override
  Future<CatalogRow> read(
    String operation,
    CatalogRow parameters, {
    bool refresh = false,
  }) async {
    if (operation != 'missions.detail') {
      return super.read(operation, parameters, refresh: refresh);
    }
    calls.add((operation: operation, parameters: parameters, refresh: refresh));
    if (held != null) return held!.future;
    if (response == null) throw const CatalogFailure();
    return response!;
  }
}
