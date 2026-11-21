// Server-confirmed station awards are progress evidence, never catalog entries.
const pyroMajorStationMarkers = <String>{
  'journey-station-rr-p2-l4',
  'journey-station-rr-p3-leo',
  'journey-station-rr-p6-leo',
};

const pyroStationMarkers = <String>{
  ...pyroMajorStationMarkers,
  'journey-station-rr-p1-l2',
  'journey-station-rr-p1-l3',
  'journey-station-rr-p1-l4',
  'journey-station-rr-p1-l5',
  'journey-station-rr-p2-l3',
  'journey-station-rr-p2-leo',
  'journey-station-rr-p3-l1',
  'journey-station-rr-p3-l2',
  'journey-station-rr-p3-l3',
  'journey-station-rr-p3-l5',
  'journey-station-rr-p5-l1',
  'journey-station-rr-p5-l2',
  'journey-station-rr-p5-l3',
  'journey-station-rr-p5-l4',
  'journey-station-rr-p5-l5',
  'journey-station-rr-p6-l1',
  'journey-station-rr-p6-l2',
  'journey-station-rr-p6-l3',
  'journey-station-rr-p6-l4',
  'journey-station-rr-p6-l5',
};

const journeyCollectionMarkers = <String, Set<String>>{
  'journey-pyro-majors': pyroMajorStationMarkers,
  'journey-pyro-all': pyroStationMarkers,
};

/// Station names from data/location-names/location-name-pack.json (zh, en).
/// Chinese is shown first; English only where Chinese is missing.
const journeyStationNames = <String, (String?, String)>{
  'journey-station-rr-p1-l2': ("焰联-远程站-1-2", "PYAM-FARSTAT-1-2"),
  'journey-station-rr-p1-l3': ("焰联-远程站-1-3", "PYAM-FARSTAT-1-3"),
  'journey-station-rr-p1-l4': ("派罗远程空间站 P1 L4", "RR P1 L4"),
  'journey-station-rr-p1-l5': ("焰联-远程站-1-5", "PYAM-FARSTAT-1-5"),
  'journey-station-rr-p2-l3': ("焰联-远程站-2-3", "PYAM-FARSTAT-2-3"),
  'journey-station-rr-p2-l4': ("死局空间站", "Checkmate"),
  'journey-station-rr-p2-leo': ("焰联-远程站-2-0", "PYAM-FARSTAT-2-0"),
  'journey-station-rr-p3-l1': ("星光服务站", "Starlight Service Station"),
  'journey-station-rr-p3-l2': ("派罗远程空间站 P3 L2", "RR P3 L2"),
  'journey-station-rr-p3-l3': ("补丁城", "Patch City"),
  'journey-station-rr-p3-l5': ("焰联-远程站-3-5", "PYAM-FARSTAT-3-5"),
  'journey-station-rr-p3-leo': ("轨道讣闻站", "Orbituary"),
  'journey-station-rr-p5-l1': ("焰联-远程站-5-1", "PYAM-FARSTAT-5-1"),
  'journey-station-rr-p5-l2': ("煤气灯空间站", "Gaslight"),
  'journey-station-rr-p5-l3': ("焰联-远程站-5-3", "PYAM-FARSTAT-5-3"),
  'journey-station-rr-p5-l4': ("路德补给站", "Rod's Fuel 'N Supplies"),
  'journey-station-rr-p5-l5': ("鼠巢空间站", "Rat's Nest"),
  'journey-station-rr-p6-l1': ("派罗远程空间站 P6 L1", "RR P6 L1"),
  'journey-station-rr-p6-l2': ("焰联-远程站-6-2", "PYAM-FARSTAT-6-2"),
  'journey-station-rr-p6-l3': ("终局空间站", "Endgame"),
  'journey-station-rr-p6-l4': ("达德利父女空间站", "Dudley & Daughters"),
  'journey-station-rr-p6-l5': ("恩惠加油站", "Megumi Refueling"),
  'journey-station-rr-p6-leo': ("废墟空间站", "Ruin Station"),
};

/// Names of the server-confirmed stations, in catalog order.
List<String> journeyReachedStationNames(
  Set<String> markers,
  bool Function(String id) confirmed, {
  Map<String, (String?, String)> names = journeyStationNames,
}) => [
  for (final id in markers)
    if (confirmed(id))
      switch (names[id]) {
        (final zh?, _) when zh.trim().isNotEmpty => zh,
        (_, final en) => en,
        null => id,
      },
];
