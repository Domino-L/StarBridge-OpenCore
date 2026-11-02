import 'local_hangar_port.dart';

/// Public model specifications are independent of ownership and custom artwork.
abstract interface class ShipSpecificationsProvider {
  bool get specificationsAvailable;
  Future<ShipSpecifications> specificationsFor(
    LocalHangarShip ship, {
    bool refresh = false,
  });
}

class ShipSpecificationField {
  const ShipSpecificationField(this.key, this.value, this.unit);
  final String key, value, unit;
}

class ShipSpecificationGroup {
  const ShipSpecificationGroup(this.key, this.fields);
  final String key;
  final List<ShipSpecificationField> fields;
}

class ShipSpecificationComponent {
  const ShipSpecificationComponent({
    required this.group,
    required this.name,
    this.chineseName,
    this.size,
    this.grade,
    this.editable,
  });
  final String group, name;
  final String? chineseName, size, grade;
  final bool? editable;
}

class ShipSpecifications {
  const ShipSpecifications({
    required this.state,
    required this.modelName,
    this.dataVersion,
    this.fetchedAt,
    this.stale = false,
    this.paintBaseModel,
    this.bundleBaseModel,
    this.groups = const [],
    this.components = const [],
  });
  final String state, modelName;
  final String? dataVersion, paintBaseModel, bundleBaseModel;
  final DateTime? fetchedAt;
  final bool stale;
  final List<ShipSpecificationGroup> groups;
  final List<ShipSpecificationComponent> components;

  factory ShipSpecifications.fromJson(Map<String, Object?> json) {
    String text(Map<String, Object?> row, String key) {
      final value = row[key];
      if (value is! String || value.length > 240) {
        throw const FormatException('Invalid specification field');
      }
      return value;
    }

    List<Map<String, Object?>> rows(Object? value, int maximum) {
      if (value == null) return const [];
      if (value is! List || value.length > maximum) {
        throw const FormatException('Invalid specification list');
      }
      return value.map((v) => Map<String, Object?>.from(v as Map)).toList();
    }

    final state = text(json, 'state');
    if (!const {'ready', 'notFound', 'ambiguous'}.contains(state)) {
      throw const FormatException('Invalid specification state');
    }
    return ShipSpecifications(
      state: state,
      modelName: text(json, 'modelName'),
      dataVersion: json['dataVersion'] as String?,
      fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? ''),
      stale: json['stale'] == true,
      paintBaseModel: json['paintBaseModel'] == null
          ? null
          : text(json, 'paintBaseModel'),
      bundleBaseModel: json['bundleBaseModel'] == null
          ? null
          : text(json, 'bundleBaseModel'),
      groups: rows(json['groups'], 12)
          .map(
            (g) => ShipSpecificationGroup(
              text(g, 'key'),
              rows(g['fields'], 100)
                  .map(
                    (f) => ShipSpecificationField(
                      text(f, 'key'),
                      text(f, 'value'),
                      text(f, 'unit'),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
      components: rows(json['components'], 240)
          .map(
            (c) => ShipSpecificationComponent(
              group: text(c, 'group'),
              name: text(c, 'name'),
              chineseName: c['chineseName'] as String?,
              size: c['size'] as String?,
              grade: c['grade'] as String?,
              editable: c['editable'] as bool?,
            ),
          )
          .toList(),
    );
  }
}
