/// Presentation only. These switches never change sharing or authorization.
class MenuDisplayPreferences {
  const MenuDisplayPreferences({
    this.showClock = true,
    this.showContext = true,
    this.showDate = true,
    this.clockFormat = 'system',
    this.showScene = true,
    this.showMembers = true,
    this.showShip = true,
    this.showLocation = true,
    this.showServer = true,
    this.showPresence = true,
    this.streamerPrivacy = false,
    this.showRoomCode = true,
    this.textScalePercent = 100,
    this.interfaceScalePercent = 0,
    this.reduceMotion = false,
    this.highContrast = false,
    this.tooltipDelayMilliseconds = 500,
  });
  final bool showClock,
      showContext,
      showDate,
      showScene,
      showMembers,
      showShip,
      showLocation,
      showServer,
      showPresence,
      streamerPrivacy,
      showRoomCode;
  final bool reduceMotion;
  final bool highContrast;
  final int tooltipDelayMilliseconds;
  final String clockFormat;
  final int textScalePercent;
  final int interfaceScalePercent;
  static const interfaceScales = [0, 85, 100, 115, 125];
  static const textScales = [100, 110, 125];
  bool get effectiveShowLocation => showLocation && !streamerPrivacy;
  bool get roomCodeVisible => showRoomCode && !streamerPrivacy;
  bool get hasContext =>
      showContext &&
      (showScene ||
          showMembers ||
          showShip ||
          effectiveShowLocation ||
          showServer);
  static MenuDisplayPreferences? fromSettings(Map settings) {
    final raw = settings['display'];
    if (raw != null && (raw is! Map || !valid(raw))) return null;
    if (settings.containsKey('display') && raw == null) return null;
    final data = raw as Map?;
    return MenuDisplayPreferences(
      showClock: settings['showClock'] != false,
      showContext: settings['showContext'] != false,
      showDate: data?['showDate'] ?? true,
      clockFormat: data?['clockFormat'] ?? 'system',
      showScene: data?['showScene'] ?? true,
      showMembers: data?['showMembers'] ?? true,
      showShip: data?['showShip'] ?? true,
      showLocation: data?['showLocation'] ?? true,
      showServer: data?['showServer'] ?? true,
      showPresence: data?['showPresence'] ?? true,
      streamerPrivacy: data?['streamerPrivacy'] ?? false,
      showRoomCode: data?['showRoomCode'] ?? true,
      textScalePercent: data?['textScalePercent'] ?? 100,
      interfaceScalePercent: data?['interfaceScalePercent'] ?? 0,
      reduceMotion: data?['reduceMotion'] ?? false,
      highContrast: data?['highContrast'] ?? false,
      tooltipDelayMilliseconds: data?['tooltipDelayMilliseconds'] ?? 500,
    );
  }

  static bool valid(Map raw) =>
      raw.keys.every(
        (key) => const {
          'showDate',
          'showScene',
          'showMembers',
          'showShip',
          'showLocation',
          'showServer',
          'showPresence',
          'clockFormat',
          'streamerPrivacy',
          'showRoomCode',
          'textScalePercent',
          'interfaceScalePercent',
          'reduceMotion',
          'highContrast',
          'tooltipDelayMilliseconds',
        }.contains(key),
      ) &&
      (!raw.containsKey('tooltipDelayMilliseconds') ||
          (raw['tooltipDelayMilliseconds'] is int &&
              raw['tooltipDelayMilliseconds'] >= 100 &&
              raw['tooltipDelayMilliseconds'] <= 1500)) &&
      (!raw.containsKey('textScalePercent') ||
          (raw['textScalePercent'] is int &&
              textScales.contains(raw['textScalePercent']))) &&
      (!raw.containsKey('interfaceScalePercent') ||
          (raw['interfaceScalePercent'] is int &&
              interfaceScales.contains(raw['interfaceScalePercent']))) &&
      const [
        'streamerPrivacy',
        'showRoomCode',
        'reduceMotion',
        'highContrast',
      ].every((key) => !raw.containsKey(key) || raw[key] is bool) &&
      const [
        'showDate',
        'showScene',
        'showMembers',
        'showShip',
        'showLocation',
        'showServer',
        'showPresence',
      ].every((key) => raw[key] is bool) &&
      const [
        'system',
        'twelveHour',
        'twentyFourHour',
      ].contains(raw['clockFormat']);
  Map<String, Object?> toSettingsPatch() => {
    'showClock': showClock,
    'showContext': showContext,
    'display': {
      'showDate': showDate,
      'clockFormat': clockFormat,
      'showScene': showScene,
      'showMembers': showMembers,
      'showShip': showShip,
      'showLocation': showLocation,
      'showServer': showServer,
      'showPresence': showPresence,
      'streamerPrivacy': streamerPrivacy,
      'showRoomCode': showRoomCode,
      'textScalePercent': textScalePercent,
      'interfaceScalePercent': interfaceScalePercent,
      'reduceMotion': reduceMotion,
      'highContrast': highContrast,
      'tooltipDelayMilliseconds': tooltipDelayMilliseconds,
    },
  };
  MenuDisplayPreferences change(String key, Object value) {
    final data = toSettingsPatch();
    if (key == 'showClock' || key == 'showContext') {
      data[key] = value;
    } else {
      (data['display'] as Map)[key] = value;
    }
    return fromSettings(data)!;
  }
}
