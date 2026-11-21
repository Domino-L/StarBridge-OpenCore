import '../../app/localization/app_strings.dart';
import 'key_bindings_port.dart';

// Our own names for common game actions, written by hand: action|简体|繁體|English.
// No game or localization text is bundled. An action we were not sure about is
// left out on purpose, so the page shows its original name instead of a guess.
const _actionRows = r'''
v_toggle_all_doors|开关所有舱门|開關所有艙門|Toggle all doors
v_toggle_all_portlocks|锁定或解锁所有装配端口|鎖定或解鎖所有裝配端口|Lock or unlock all ports
v_flightready|准备起飞|準備起飛|Flight ready
v_self_destruct|自毁|自毀|Self destruct
v_emergency_exit|紧急离开座位|緊急離開座位|Emergency exit seat
v_eject|弹射|彈射|Eject
v_view_look_behind|向后看|向後看|Look behind
v_toggle_mining_mode|切换采矿模式|切換採礦模式|Toggle mining mode
v_toggle_salvage_mode|切换打捞模式|切換打撈模式|Toggle salvage mode
v_toggle_refuel_mode|切换加油模式|切換加油模式|Toggle refuel mode
v_toggle_scan_mode|切换扫描模式|切換掃描模式|Toggle scan mode
v_operator_mode_cycle_forward|切换操作模式|切換操作模式|Cycle operator mode
v_light_amplification_toggle|开关微光增强|開關微光增強|Toggle light amplification
v_view_yaw|视角左右转动|視角左右轉動|View yaw
v_view_yaw_mouse|视角左右转动（鼠标）|視角左右轉動（滑鼠）|View yaw (mouse)
v_view_pitch|视角上下转动|視角上下轉動|View pitch
v_view_pitch_mouse|视角上下转动（鼠标）|視角上下轉動（滑鼠）|View pitch (mouse)
v_view_cycle_fwd|切换视角|切換視角|Cycle view
v_view_zoom_in|视角拉近|視角拉近|Zoom in
v_view_zoom_out|视角拉远|視角拉遠|Zoom out
v_view_freelook_mode|自由视角|自由視角|Free look
v_ads_toggle|开关瞄准视角|開關瞄準視角|Toggle aim view
v_pitch_up|机头向上|機頭向上|Pitch up
v_pitch_down|机头向下|機頭向下|Pitch down
v_pitch|俯仰|俯仰|Pitch
v_pitch_mouse|俯仰（鼠标）|俯仰（滑鼠）|Pitch (mouse)
v_yaw_left|向左偏航|向左偏航|Yaw left
v_yaw_right|向右偏航|向右偏航|Yaw right
v_yaw|偏航|偏航|Yaw
v_yaw_mouse|偏航（鼠标）|偏航（滑鼠）|Yaw (mouse)
v_roll_left|向左滚转|向左滾轉|Roll left
v_roll_right|向右滚转|向右滾轉|Roll right
v_roll|滚转|滾轉|Roll
v_toggle_yaw_roll_swap|互换偏航和滚转|互換偏航和滾轉|Swap yaw and roll
v_strafe_up|向上平移|向上平移|Strafe up
v_strafe_down|向下平移|向下平移|Strafe down
v_strafe_vertical|上下平移|上下平移|Strafe vertical
v_strafe_left|向左平移|向左平移|Strafe left
v_strafe_right|向右平移|向右平移|Strafe right
v_strafe_lateral|左右平移|左右平移|Strafe lateral
v_strafe_forward|向前推进|向前推進|Strafe forward
v_strafe_back|向后推进|向後推進|Strafe back
v_strafe_longitudinal|前后推进|前後推進|Strafe longitudinal
v_ifcs_vector_decoupling_toggle|开关解耦模式|開關解耦模式|Toggle decoupled mode
v_afterburner|加力|加力|Afterburner
v_ifcs_speed_limiter_increment|提高速度限制|提高速度限制|Raise speed limit
v_ifcs_speed_limiter_decrement|降低速度限制|降低速度限制|Lower speed limit
v_space_brake|空间刹车|空間煞車|Space brake
v_lock_rotation|锁定旋转|鎖定旋轉|Lock rotation
v_toggle_landing_system|开关起落架|開關起落架|Toggle landing gear
v_vtol_toggle|开关垂直起降|開關垂直起降|Toggle VTOL
v_autoland|自动降落|自動降落|Auto land
v_atc_request|呼叫空管|呼叫航管|Call air traffic control
v_master_mode_cycle_long|切换主模式|切換主模式|Cycle master mode
v_toggle_jump_request|请求跃迁|請求躍遷|Request jump
v_toggle_qdrive_engagement|开关量子引擎|開關量子引擎|Toggle quantum drive
v_toggle_docking_request|请求对接|請求對接|Request docking
v_auto_targeting_toggle_long|开关自动锁定|開關自動鎖定|Toggle auto targeting
v_target_unlock|解除目标锁定|解除目標鎖定|Unlock target
v_target_cycle_in_view_fwd|切换视野内目标|切換視野內目標|Cycle targets in view
v_target_cycle_attacker_fwd|切换攻击者目标|切換攻擊者目標|Cycle attackers
v_target_cycle_hostile_fwd|切换敌对目标|切換敵對目標|Cycle hostile targets
v_target_cycle_friendly_fwd|切换友方目标|切換友方目標|Cycle friendly targets
v_target_cycle_all_fwd|切换全部目标|切換全部目標|Cycle all targets
v_target_cycle_subitem_fwd|切换目标部件|切換目標部件|Cycle target components
v_target_hail|呼叫目标|呼叫目標|Hail target
v_invoke_ping|雷达脉冲|雷達脈衝|Radar ping
v_scanning_trigger_scan|开始扫描|開始掃描|Scan
v_inc_scan_focus_level|增大扫描聚焦|增大掃描聚焦|Increase scan focus
v_dec_scan_focus_level|减小扫描聚焦|減小掃描聚焦|Decrease scan focus
v_toggle_mining_laser_fire|开关采矿激光|開關採礦雷射|Toggle mining laser
v_toggle_mining_laser_type|切换采矿激光类型|切換採礦雷射類型|Switch mining laser type
v_increase_mining_throttle|提高采矿功率|提高採礦功率|Increase mining power
v_decrease_mining_throttle|降低采矿功率|降低採礦功率|Decrease mining power
v_jettison_volatile_cargo|抛弃不稳定货物|拋棄不穩定貨物|Jettison volatile cargo
tractor_beam_vehicle_increase_distance|增大牵引距离|增大牽引距離|Increase tractor distance
tractor_beam_vehicle_decrease_distance|减小牵引距离|減小牽引距離|Decrease tractor distance
v_salvage_toggle_fire_focused|开关当前打捞头|開關目前打撈頭|Toggle focused salvage head
v_salvage_toggle_fire_left|开关左打捞头|開關左打撈頭|Toggle left salvage head
v_salvage_toggle_fire_right|开关右打捞头|開關右打撈頭|Toggle right salvage head
turret_pitch|炮塔俯仰|砲塔俯仰|Turret pitch
turret_pitch_mouse|炮塔俯仰（鼠标）|砲塔俯仰（滑鼠）|Turret pitch (mouse)
turret_yaw|炮塔偏航|砲塔偏航|Turret yaw
turret_yaw_mouse|炮塔偏航（鼠标）|砲塔偏航（滑鼠）|Turret yaw (mouse)
turret_remote_exit|退出远程炮塔|退出遙控砲塔|Exit remote turret
turret_remote_cycle_next|下一个远程炮塔|下一個遙控砲塔|Next remote turret
turret_remote_cycle_prev|上一个远程炮塔|上一個遙控砲塔|Previous remote turret
turret_recenter|炮塔回中|砲塔回中|Recenter turret
v_weapon_gimbals_state_toggle|切换武器万向模式|切換武器萬向模式|Toggle weapon gimbal mode
v_weapon_preset_next|下一个武器组|下一個武器組|Next weapon group
v_weapon_preset_prev|上一个武器组|上一個武器組|Previous weapon group
v_weapon_toggle_launch_missile|发射导弹|發射飛彈|Launch missile
v_weapon_launch_missile_cinematic_hold|发射导弹（按住）|發射飛彈（按住）|Launch missile (hold)
v_weapon_cycle_missile_fwd|切换导弹|切換飛彈|Cycle missile
v_weapon_cycle_missile_back|切回上一种导弹|切回上一種飛彈|Previous missile
v_weapon_increase_max_missiles|增加齐射导弹数|增加齊射飛彈數|More missiles per launch
v_weapon_reset_max_missiles|重置齐射导弹数|重置齊射飛彈數|Reset missiles per launch
v_weapon_countermeasure_decoy_launch|发射诱饵|發射誘餌|Launch decoy
v_weapon_countermeasure_decoy_burst_increase|增加诱饵连发数|增加誘餌連發數|More decoys per burst
v_weapon_countermeasure_decoy_burst_decrease|减少诱饵连发数|減少誘餌連發數|Fewer decoys per burst
v_weapon_countermeasure_noise_launch|发射干扰|發射干擾|Launch noise
v_power_toggle|开关电源|開關電源|Toggle power
v_power_toggle_thrusters|开关推进器|開關推進器|Toggle thrusters
v_power_toggle_shields|开关护盾|開關護盾|Toggle shields
v_power_toggle_weapons|开关武器|開關武器|Toggle weapons
v_engineering_assignment_engine_increase|增加引擎功率|增加引擎功率|More engine power
v_engineering_assignment_engine_decrease|减少引擎功率|減少引擎功率|Less engine power
v_engineering_assignment_shields_increase|增加护盾功率|增加護盾功率|More shield power
v_engineering_assignment_shields_decrease|减少护盾功率|減少護盾功率|Less shield power
v_engineering_assignment_weapons_increase|增加武器功率|增加武器功率|More weapon power
v_engineering_assignment_weapons_decrease|减少武器功率|減少武器功率|Less weapon power
v_engineering_assignment_reset|重置功率分配|重置功率分配|Reset power allocation
mobiglas|打开手环|開啟手環|Open mobiGlas
v_hud_open_scoreboard|打开计分板|開啟計分板|Open scoreboard
pl_hud_open_scoreboard|打开计分板|開啟計分板|Open scoreboard
v_starmap|打开星图|開啟星圖|Open star map
visor_wipe|擦拭面罩|擦拭面罩|Wipe visor
v_lights|开关灯光|開關燈光|Toggle lights
moveleft|向左移动|向左移動|Move left
moveright|向右移动|向右移動|Move right
moveforward|向前移动|向前移動|Move forward
moveback|向后移动|向後移動|Move back
jump|跳跃|跳躍|Jump
crouch|蹲下|蹲下|Crouch
prone|卧倒|臥倒|Prone
sprint|奔跑|奔跑|Sprint
leanleft|向左探身|向左探身|Lean left
leanright|向右探身|向右探身|Lean right
ledgegrab|攀爬|攀爬|Climb
attack1|攻击或开火|攻擊或開火|Attack or fire
attackSecondary|副攻击|副攻擊|Secondary attack
melee_block|近战格挡|近戰格擋|Melee block
weapon_melee|武器近战|武器近戰|Weapon melee
takedown_nonLethal|非致命制服|非致命制服|Non-lethal takedown
throw_overhand|上手投掷|上手投擲|Overhand throw
throw_underhand|下手投掷|下手投擲|Underhand throw
zoom|瞄准|瞄準|Aim
toggle_lowered|放下或举起武器|放下或舉起武器|Lower or raise weapon
select_primary_pit|选择主武器|選擇主武器|Select primary weapon
select_secondary_pit|选择副武器|選擇副武器|Select secondary weapon
select_sidearm_pit|选择手枪|選擇手槍|Select sidearm
select_meleeweapon_pit|选择近战武器|選擇近戰武器|Select melee weapon
select_gadget_pit|选择工具|選擇工具|Select gadget
selectUnarmedCombat|徒手战斗|徒手戰鬥|Unarmed combat
reload|换弹|換彈|Reload
holster|收起武器|收起武器|Holster
inspect|检视|檢視|Inspect
customize|改装武器|改裝武器|Customize weapon
stabilize|稳定瞄准|穩定瞄準|Steady aim
weapon_change_firemode|切换射击模式|切換射擊模式|Change fire mode
downedRevivalRequest|请求救援|請求救援|Request revival
toggle_flashlight|开关手电|開關手電|Toggle flashlight
toggleEquipHelmet|穿脱头盔|穿脫頭盔|Equip or remove helmet
thirdperson|切换第三人称|切換第三人稱|Toggle third person
free_thirdperson_camera|第三人称自由视角|第三人稱自由視角|Free third-person camera
zoom_out|视角拉远|視角拉遠|Zoom out
zoom_in|视角拉近|視角拉近|Zoom in
consume|使用物品|使用物品|Use item
force_respawn|强制重生|強制重生|Force respawn
prone_rollleft|卧倒时向左翻滚|臥倒時向左翻滾|Prone roll left
prone_rollright|卧倒时向右翻滚|臥倒時向右翻滾|Prone roll right
tractor_beam_increase_distance|增大牵引距离|增大牽引距離|Increase tractor distance
tractor_beam_decrease_distance|减小牵引距离|減小牽引距離|Decrease tractor distance
weapon_change_mining_throttle|调整采矿功率|調整採礦功率|Adjust mining power
incapacitatedRespawn|倒地后重生|倒地後重生|Respawn when down
eva_roll_left|太空行走向左滚转|太空漫步向左滾轉|EVA roll left
eva_roll_right|太空行走向右滚转|太空漫步向右滾轉|EVA roll right
eva_strafe_up|太空行走向上|太空漫步向上|EVA up
eva_strafe_down|太空行走向下|太空漫步向下|EVA down
eva_strafe_left|太空行走向左|太空漫步向左|EVA left
eva_strafe_right|太空行走向右|太空漫步向右|EVA right
eva_strafe_forward|太空行走向前|太空漫步向前|EVA forward
eva_strafe_back|太空行走向后|太空漫步向後|EVA back
eva_brake|太空行走刹车|太空漫步煞車|EVA brake
eva_boost|太空行走加速|太空漫步加速|EVA boost
v_horn|喇叭|喇叭|Horn
v_move_forward|载具前进|載具前進|Vehicle forward
v_move_back|载具后退|載具後退|Vehicle back
v_brake|载具刹车|載具煞車|Vehicle brake
v_boost|载具加速|載具加速|Vehicle boost
respawn|重生|重生|Respawn
pl_exit|退出|退出|Exit
notification_accept|接受通知|接受通知|Accept notification
notification_decline|拒绝通知|拒絕通知|Decline notification
ui_notification_accept|接受通知|接受通知|Accept notification
ui_notification_decline|拒绝通知|拒絕通知|Decline notification
ui_notification_ignore|忽略通知|忽略通知|Ignore notification
toggle_contact|打开联系人|開啟聯絡人|Open contacts
toggle_chat|开关聊天|開關聊天|Toggle chat
cycle_chat_lobby|切换聊天频道|切換聊天頻道|Cycle chat channel
focus_on_chat_textinput|打开聊天输入框|開啟聊天輸入框|Open chat input
emote_cs_forward|表情：向前|表情：向前|Emote: forward
emote_cs_left|表情：向左|表情：向左|Emote: left
emote_cs_right|表情：向右|表情：向右|Emote: right
emote_cs_stop|表情：停下|表情：停下|Emote: stop
emote_cs_yes|表情：同意|表情：同意|Emote: yes
emote_cs_no|表情：否定|表情：否定|Emote: no
foip_pushtotalk|按键说话|按鍵說話|Push to talk
foip_pushtotalk_proximity|按键说话（附近）|按鍵說話（附近）|Push to talk (nearby)
pc_interaction_mode|交互模式|互動模式|Interaction mode
pc_interaction_select|交互选择|互動選擇|Interaction select
pc_select|选择|選擇|Select
pc_zoom_in|交互拉近|互動拉近|Interaction zoom in
pc_zoom_out|交互拉远|互動拉遠|Interaction zoom out
pc_pit_inventory|打开背包|開啟背包|Open inventory
pc_pit_looting|搜刮|搜刮|Loot
pc_qs_weapons_pit_primary|快捷栏：主武器|快捷欄：主武器|Quick select: primary
pc_qs_weapons_pit_secondary|快捷栏：副武器|快捷欄：副武器|Quick select: secondary
pc_qs_weapons_pit_sidearm|快捷栏：手枪|快捷欄：手槍|Quick select: sidearm
pc_qs_grenades|快捷栏：手雷|快捷欄：手榴彈|Quick select: grenades
pc_qs_consumables|快捷栏：消耗品|快捷欄：消耗品|Quick select: consumables
spectate_next_target|观战下一个目标|觀戰下一個目標|Spectate next
spectate_prev_target|观战上一个目标|觀戰上一個目標|Spectate previous
v_target_toggle_lock_index_1|开关目标锁定 1|開關目標鎖定 1|Toggle target lock 1
v_mining_use_consumable1|使用采矿模块 1|使用採礦模組 1|Use mining module 1
v_target_toggle_lock_index_2|开关目标锁定 2|開關目標鎖定 2|Toggle target lock 2
v_mining_use_consumable2|使用采矿模块 2|使用採礦模組 2|Use mining module 2
v_target_toggle_lock_index_3|开关目标锁定 3|開關目標鎖定 3|Toggle target lock 3
v_mining_use_consumable3|使用采矿模块 3|使用採礦模組 3|Use mining module 3
view_save_view_1|保存视角 1|儲存視角 1|Save view 1
view_load_view_1|读取视角 1|讀取視角 1|Load view 1
view_save_view_2|保存视角 2|儲存視角 2|Save view 2
view_load_view_2|读取视角 2|讀取視角 2|Load view 2
view_save_view_3|保存视角 3|儲存視角 3|Save view 3
view_load_view_3|读取视角 3|讀取視角 3|Load view 3
view_save_view_4|保存视角 4|儲存視角 4|Save view 4
view_load_view_4|读取视角 4|讀取視角 4|Load view 4
view_save_view_5|保存视角 5|儲存視角 5|Save view 5
view_load_view_5|读取视角 5|讀取視角 5|Load view 5
view_save_view_6|保存视角 6|儲存視角 6|Save view 6
view_load_view_6|读取视角 6|讀取視角 6|Load view 6
view_save_view_7|保存视角 7|儲存視角 7|Save view 7
view_load_view_7|读取视角 7|讀取視角 7|Load view 7
view_save_view_8|保存视角 8|儲存視角 8|Save view 8
view_load_view_8|读取视角 8|讀取視角 8|Load view 8
view_save_view_9|保存视角 9|儲存視角 9|Save view 9
view_load_view_9|读取视角 9|讀取視角 9|Load view 9
''';

const _mapRows = r'''
seat_general|座椅：通用|座椅：通用|Seat: general
spaceship_general|飞船：通用|飛船：通用|Ship: general
vehicle_mfd|飞船：多功能屏|飛船：多功能螢幕|Ship: displays
spaceship_view|飞船：视角|飛船：視角|Ship: view
spaceship_movement|飞船：飞行|飛船：飛行|Ship: flight
spaceship_quantum|飞船：量子引擎|飛船：量子引擎|Ship: quantum drive
spaceship_docking|飞船：对接|飛船：對接|Ship: docking
spaceship_targeting|飞船：目标|飛船：目標|Ship: targeting
spaceship_targeting_advanced|飞船：目标切换|飛船：目標切換|Ship: target cycling
spaceship_target_hailing|飞船：呼叫|飛船：呼叫|Ship: hailing
spaceship_radar|飞船：雷达|飛船：雷達|Ship: radar
spaceship_scanning|飞船：扫描|飛船：掃描|Ship: scanning
spaceship_mining|飞船：采矿|飛船：採礦|Ship: mining
spaceship_salvage|飞船：打捞|飛船：打撈|Ship: salvage
turret_movement|炮塔：移动|砲塔：移動|Turret: movement
turret_advanced|炮塔：进阶|砲塔：進階|Turret: advanced
spaceship_weapons|飞船：武器|飛船：武器|Ship: weapons
spaceship_missiles|飞船：导弹|飛船：飛彈|Ship: missiles
spaceship_defensive|飞船：防御|飛船：防禦|Ship: defense
spaceship_power|飞船：能源|飛船：能源|Ship: power
spaceship_hud|飞船：界面|飛船：介面|Ship: interface
lights_controller|灯光|燈光|Lights
stopwatch|秒表|碼錶|Stopwatch
player|步行|步行|On foot
prone|卧倒|臥倒|Prone
tractor_beam|牵引光束|牽引光束|Tractor beam
mining|手持采矿|手持採礦|Hand mining
incapacitated|倒地|倒地|Incapacitated
zero_gravity_eva|太空行走|太空漫步|EVA
zero_gravity_traversal|零重力攀移|零重力攀移|Zero-G traversal
vehicle_general|载具：通用|載具：通用|Vehicle: general
vehicle_driver|载具：驾驶|載具：駕駛|Vehicle: driving
spectator|观战|觀戰|Spectator
default|常用|常用|General
ui_notification|通知|通知|Notifications
player_emotes|表情|表情|Emotes
player_input_optical_tracking|头部追踪和语音|頭部追蹤和語音|Head tracking and voice
player_choice|交互和背包|互動和背包|Interaction and inventory
view_director_mode|导演视角|導演視角|Director view
''';

Map<String, List<String>> _parse(String rows) => {
  for (final row in rows.trim().split(RegExp(r'\r?\n')))
    row.substring(0, row.indexOf('|')): row.split('|').sublist(1),
};

final _actions = _parse(_actionRows);
final _maps = _parse(_mapRows);

String _pick(AppStrings strings, List<String> copy) {
  if (strings.locale.languageCode == 'en') return copy[2];
  if (strings.locale.countryCode == 'TW' ||
      strings.locale.scriptCode == 'Hant') {
    return copy[1];
  }
  return copy[0];
}

/// Which localization file the Host should look for.
String keyBindingLanguage(AppStrings strings) {
  if (strings.locale.languageCode == 'en') return 'en';
  return strings.locale.countryCode == 'TW' ||
          strings.locale.scriptCode == 'Hant'
      ? 'zh-Hant'
      : 'zh-Hans';
}

/// Display names for one category: the localized name the Host found for this
/// interface language, then our own, then null so the page says it has none and
/// shows the original. The game gives some actions in a category the same label,
/// such as firing and using an item, so a shared name would say nothing; those
/// prefer our own name when we have one.
Map<String, String?> keyBindingActionNames(
  AppStrings strings,
  List<KeyBindingAction> actions,
) {
  final uses = <String, int>{};
  for (final action in actions) {
    final name = action.localizedName;
    if (name != null) uses[name] = (uses[name] ?? 0) + 1;
  }
  return {
    for (final action in actions)
      action.name: _actionName(strings, action, uses),
  };
}

String? _actionName(
  AppStrings strings,
  KeyBindingAction action,
  Map<String, int> uses,
) {
  final copy = _actions[action.name];
  final own = copy == null ? null : _pick(strings, copy);
  final localized = action.localizedName;
  if (localized == null) return own;
  return (uses[localized] ?? 0) > 1 ? own ?? localized : localized;
}

// Folder names the game uses, shown in their own language. Others show as named.
const _localizationNames = <String, String>{
  'chinese_(simplified)': '简体中文',
  'chinese_(traditional)': '繁體中文',
  'english': 'English',
  'french_(france)': 'Français',
  'german_(germany)': 'Deutsch',
  'italian_(italy)': 'Italiano',
  'japanese_(japan)': '日本語',
  'korean_(south_korea)': '한국어',
  'polish_(poland)': 'Polski',
  'portuguese_(brazil)': 'Português (Brasil)',
  'spanish_(latin_america)': 'Español (Latinoamérica)',
  'spanish_(spain)': 'Español (España)',
};

String keyBindingLocalizationName(String folder) =>
    _localizationNames[folder.toLowerCase()] ?? folder;

/// Our own name, whatever the player's files say.
String? keyBindingOwnName(AppStrings strings, String action) {
  final copy = _actions[action];
  return copy == null ? null : _pick(strings, copy);
}

String keyBindingMapName(AppStrings strings, KeyBindingMap map) {
  if (map.localizedName != null) return map.localizedName!;
  final copy = _maps[map.name];
  return copy == null ? map.name : _pick(strings, copy);
}
