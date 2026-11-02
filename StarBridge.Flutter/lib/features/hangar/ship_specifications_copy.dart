import 'local_hangar_copy.dart';

/// The wire uses stable keys; user-visible labels stay with the client locale.
extension ShipSpecificationsCopy on LocalHangarCopy {
  String get specsTitle => pick('型号参数', '型號參數', 'Model specifications');
  String get specsLoading =>
      pick('正在加载型号参数…', '正在載入型號參數…', 'Loading specifications…');
  String get specsFailure => pick(
    '暂时无法获取参数，请稍后重试。',
    '暫時無法取得參數，請稍後重試。',
    'Specifications are unavailable. Try again shortly.',
  );
  String get specsOffline => pick(
    '联网后可查看 SCM 型号参数。',
    '連線後可檢視 SCM 型號參數。',
    'Connect to view SCM specifications.',
  );
  String get specsMissing => pick(
    '暂未匹配到此型号的 SCM 参数，可刷新重试。',
    '暫未配對到此型號的 SCM 參數，可重新整理再試。',
    'No matching SCM specifications were found. Refresh to try again.',
  );
  String get specsAmbiguous => pick(
    '此型号有多条同名记录，尚未确认对应版本。',
    '此型號有多筆同名記錄，尚未確認對應版本。',
    'Several records share this name. The exact variant could not be confirmed.',
  );
  String get specsStale => pick(
    '刷新失败，正在显示此前获取的参数。',
    '重新整理失敗，正在顯示先前取得的參數。',
    'Refresh failed. Showing previously retrieved specifications.',
  );
  String get specsConceptMissing => pick(
    '概念舰暂无公开参数。',
    '概念艦暫無公開參數。',
    'Public specifications are not yet available for this concept ship.',
  );
  String specsMatched(String model) =>
      pick('已匹配型号：$model', '已配對型號：$model', 'Matched model: $model');
  String specComponentLabel(String key) => switch (key) {
    'missiles' => pick('导弹与导弹架', '飛彈與飛彈架', 'Missiles and racks'),
    'missileRacks' => pick('导弹架', '飛彈架', 'Missile racks'),
    _ => specLabel(key),
  };
  String get specsRefresh => pick('刷新参数', '重新整理參數', 'Refresh specifications');
  String get specsRetry => pick('重试', '重試', 'Try again');
  String get specsBasis => pick(
    'SCM 参考数据 · 组件为默认配置，未列出的参数暂无数据。',
    'SCM 參考資料 · 組件為預設配置，未列出的參數暫無資料。',
    'SCM reference data · Default components. Unlisted specifications are unavailable.',
  );
  String specsVersion(String version) =>
      pick('数据版本 $version', '資料版本 $version', 'Data version $version');
  String specsPaintBase(String model) => pick(
    '涂装特别版：使用 $model 的默认型号参数。',
    '塗裝特別版：使用 $model 的預設型號參數。',
    'Cosmetic edition · Using default $model specifications.',
  );
  String specsFetched(String time) =>
      pick('获取于 $time', '取得於 $time', 'Retrieved $time');
  String specsBundleBase(String model) => pick(
    '含 C8X 套装：以下为 $model 母舰的默认参数，不包含附带 C8X 的参数。',
    '含 C8X 套裝：以下為 $model 母艦的預設參數，不包含隨附 C8X 的參數。',
    'Includes C8X · Specifications below are for the $model carrier only, with its default loadout.',
  );
  String specsGrade(String grade) =>
      pick('$grade 级', '$grade 級', 'Grade $grade');
  String get specsFixed => pick('固定组件', '固定組件', 'Fixed component');
  String specLabel(String key) {
    final label = _specLabels[key];
    return label == null ? '' : pick(label.$1, label.$2, label.$3);
  }
}

const _specLabels = <String, (String, String, String)>{
  'overview': ('基础规格', '基礎規格', 'Overview'),
  'flight': ('飞行性能', '飛行性能', 'Flight performance'),
  'defense': ('船体与防护', '船體與防護', 'Hull & defense'),
  'weapons': ('武器', '武器', 'Weapons'),
  'propulsion': ('推进与燃料', '推進與燃料', 'Propulsion & fuel'),
  'quantum': ('量子跃迁', '量子躍遷', 'Quantum travel'),
  'signal': ('信号特征', '訊號特徵', 'Signatures'),
  'radar': ('雷达', '雷達', 'Radar'),
  'insurance': ('保险参考', '保險參考', 'Insurance reference'),
  'components': ('默认组件与挂点', '預設組件與掛點', 'Default components & hardpoints'),
  'crew': ('乘员', '乘員', 'Crew'),
  'seats': ('座位', '座位', 'Seats'),
  'weaponCrew': ('武器操作员', '武器操作員', 'Weapon crew'),
  'mass': ('质量', '質量', 'Mass'),
  'cargo': ('货舱容量', '貨艙容量', 'Cargo capacity'),
  'length': ('长度', '長度', 'Length'),
  'width': ('宽度', '寬度', 'Width'),
  'height': ('高度', '高度', 'Height'),
  'flight.speed.scm': ('SCM 速度', 'SCM 速度', 'SCM speed'),
  'flight.speed.max': ('最大速度', '最大速度', 'Maximum speed'),
  'flight.speed.boostForward': ('前向加力速度', '前向加力速度', 'Forward boost speed'),
  'flight.speed.boostBackward': ('后向加力速度', '後向加力速度', 'Reverse boost speed'),
  'flight.maneuvering.pitch': ('俯仰速率', '俯仰速率', 'Pitch rate'),
  'flight.maneuvering.yaw': ('偏航速率', '偏航速率', 'Yaw rate'),
  'flight.maneuvering.roll': ('滚转速率', '滾轉速率', 'Roll rate'),
  'flight.maneuvering.pitchBoosted': ('加力俯仰', '加力俯仰', 'Boosted pitch'),
  'flight.maneuvering.yawBoosted': ('加力偏航', '加力偏航', 'Boosted yaw'),
  'flight.maneuvering.rollBoosted': ('加力滚转', '加力滾轉', 'Boosted roll'),
  'flight.timing.zeroToScm': ('静止至 SCM', '靜止至 SCM', 'Zero to SCM'),
  'flight.timing.zeroToMax': ('静止至最大速度', '靜止至最大速度', 'Zero to maximum'),
  'flight.timing.scmToZero': ('SCM 至静止', 'SCM 至靜止', 'SCM to zero'),
  'flight.timing.maxToZero': ('最大速度至静止', '最大速度至靜止', 'Maximum to zero'),
  'flight.acceleration.forward': ('前向加速度', '前向加速度', 'Forward acceleration'),
  'flight.acceleration.backward': ('后向加速度', '後向加速度', 'Reverse acceleration'),
  'flight.acceleration.up': ('上升加速度', '上升加速度', 'Upward acceleration'),
  'flight.acceleration.down': ('下降加速度', '下降加速度', 'Downward acceleration'),
  'flight.acceleration.strafe': ('平移加速度', '平移加速度', 'Strafe acceleration'),
  'hullHealth': ('船体生命值', '船體生命值', 'Hull health'),
  'shield.hp': ('护盾容量', '護盾容量', 'Shield capacity'),
  'shield.regen': ('护盾恢复速率', '護盾恢復速率', 'Shield regeneration'),
  'armor.health': ('装甲生命值', '裝甲生命值', 'Armor health'),
  'armor.damageMultipliers.energy': (
    '能量伤害倍率',
    '能量傷害倍率',
    'Energy damage multiplier',
  ),
  'armor.damageMultipliers.physical': (
    '实弹伤害倍率',
    '實彈傷害倍率',
    'Physical damage multiplier',
  ),
  'distortionPool': ('畸变耐受池', '畸變耐受池', 'Distortion pool'),
  'dps.pilotDps': ('驾驶员武器 DPS', '駕駛員武器 DPS', 'Pilot weapon DPS'),
  'dps.turretDps': ('炮塔 DPS', '炮塔 DPS', 'Turret DPS'),
  'missiles': ('导弹数量', '飛彈數量', 'Missile count'),
  'torpedoes': ('鱼雷数量', '魚雷數量', 'Torpedo count'),
  'countermeasures.decoy.ammo': ('诱饵弹', '誘餌彈', 'Decoy ammunition'),
  'countermeasures.noise.ammo': ('噪声弹', '雜訊彈', 'Noise ammunition'),
  'hydrogenFuel': ('氢燃料容量', '氫燃料容量', 'Hydrogen capacity'),
  'propulsion.fuelIntakeRate': ('燃料收集速率', '燃料收集速率', 'Fuel intake rate'),
  'propulsion.maneuveringTimeTillEmpty': (
    '机动燃料续航',
    '機動燃料續航',
    'Maneuvering fuel duration',
  ),
  'quantum.fuelCapacity': ('量子燃料容量', '量子燃料容量', 'Quantum fuel capacity'),
  'quantum.speed': ('量子速度', '量子速度', 'Quantum speed'),
  'quantum.range': ('量子航程', '量子航程', 'Quantum range'),
  'quantum.spoolTime': ('量子充能时间', '量子充能時間', 'Quantum spool time'),
  'quantum.cooldown': ('量子冷却时间', '量子冷卻時間', 'Quantum cooldown'),
  'signal.emission.emQuantum': ('量子模式电磁信号', '量子模式電磁訊號', 'Quantum EM signature'),
  'signal.emission.emShields': ('护盾模式电磁信号', '護盾模式電磁訊號', 'Shield EM signature'),
  'signal.emission.irQuantum': ('量子模式红外信号', '量子模式紅外訊號', 'Quantum IR signature'),
  'signal.emission.irShields': ('护盾模式红外信号', '護盾模式紅外訊號', 'Shield IR signature'),
  'signal.crossSection.x': ('X 轴截面', 'X 軸截面', 'X cross section'),
  'signal.crossSection.y': ('Y 轴截面', 'Y 軸截面', 'Y cross section'),
  'signal.crossSection.z': ('Z 轴截面', 'Z 軸截面', 'Z cross section'),
  'radar.size': ('雷达尺寸', '雷達尺寸', 'Radar size'),
  'radar.count': ('雷达数量', '雷達數量', 'Radar count'),
  'radar.cooldown': ('雷达冷却', '雷達冷卻', 'Radar cooldown'),
  'insurance.expeditedCost': ('加急索赔费用', '加急索賠費用', 'Expedited claim cost'),
  'turrets': ('炮塔与武器架', '炮塔與武器架', 'Turrets & mounts'),
  'missileRacks': ('导弹架', '飛彈架', 'Missile racks'),
  'shields': ('护盾发生器', '護盾產生器', 'Shield generators'),
  'shieldGenerators': ('护盾发生器', '護盾產生器', 'Shield generators'),
  'coolers': ('冷却器', '冷卻器', 'Coolers'),
  'powerPlants': ('发电机', '發電機', 'Power plants'),
  'powerplants': ('发电机', '發電機', 'Power plants'),
  'quantumDrives': ('量子引擎', '量子引擎', 'Quantum drives'),
  'quantumDrive': ('量子引擎', '量子引擎', 'Quantum drives'),
  'radars': ('雷达', '雷達', 'Radars'),
  'thrusters': ('推进器', '推進器', 'Thrusters'),
  'flightControllers': ('飞行控制器', '飛行控制器', 'Flight controllers'),
  'lifeSupportGenerators': ('生命维持', '生命維持', 'Life support'),
};
