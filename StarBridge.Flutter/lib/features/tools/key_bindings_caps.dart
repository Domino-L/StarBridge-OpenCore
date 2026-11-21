import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';
import 'key_bindings_names.dart';

// Short labels for key caps only: action|简体|繁體|English. Each keeps the meaning
// of the full name, which stays one hover away. Used when the full name does not
// fit in two lines.
const _capRows = r'''
v_toggle_all_portlocks|装配端口锁|裝配端口鎖|Port locks
v_mfd_interact_cycle_forwards_short|MFD 下一页|MFD 下一頁|MFD next
v_mfd_interact_cycle_backwards_short|MFD 上一页|MFD 上一頁|MFD prev
v_ifcs_throttle_swap_mode|巡航模式|巡航模式|Cruise mode
v_strafe_trim_reset_long|释放调节|釋放調節|Release trim
v_strafe_trim_reset_short|释放调节|釋放調節|Release trim
v_ifcs_reset_gmeter_max|重置过载计|重置過載計|Reset G meter
v_target_toggle_lock_index_1|锁定目标 1|鎖定目標 1|Lock 1
v_target_toggle_lock_index_2|锁定目标 2|鎖定目標 2|Lock 2
v_target_toggle_lock_index_3|锁定目标 3|鎖定目標 3|Lock 3
v_target_toggle_pin_index_1|标记目标 1|標記目標 1|Pin 1
v_target_toggle_pin_index_2|标记目标 2|標記目標 2|Pin 2
v_target_toggle_pin_index_3|标记目标 3|標記目標 3|Pin 3
v_look_ahead_enable|前向视角|前向視角|Look ahead
v_target_cycle_in_view_reset|回瞄准目标|回瞄準目標|Back to aimed
v_target_cycle_attacker_reset|回最近攻击者|回最近攻擊者|Reset attacker
v_target_cycle_hostile_reset|回最近敌方|回最近敵方|Last hostile
v_target_cycle_friendly_reset|回最近友方|回最近友方|Last friendly
v_target_cycle_all_reset|回最近目标|回最近目標|Last target
v_target_cycle_subitem_reset|回主目标|回主目標|Main target
v_mining_use_permanent_modifier|激光高低|雷射高低|Beam mode
v_salvage_toggle_fire_fracture|碎裂工具|碎裂工具|Fracture
v_salvage_toggle_fire_disintegrate|分解工具|分解工具|Break up
v_salvage_reset_gimbal|重置万向节|重置萬向節|Reset gimbal
turret_toggle_mouse_mode|鼠标移动模式|滑鼠移動模式|Mouse mode
turret_mouse_mode_cycle|切换鼠标模式|切換滑鼠模式|Mouse next
v_weapon_gimbals_state_toggle|万向节锁定|萬向節鎖定|Gimbal lock
v_weapon_aim_type_cycle|瞄准模式|瞄準模式|Aim mode
v_weapon_bombing_toggle_desired_impact_point|预计撞击点|預計撞擊點|Impact point
v_power_throttle_min|供能最小|供能最小|Power min
v_power_throttle_max|供能最大|供能最大|Power max
v_engineering_assignment_engine_max|引擎最大|引擎最大|Engines max
v_engineering_assignment_engine_min|引擎最小|引擎最小|Engines min
v_engineering_assignment_shields_max|护盾最大|護盾最大|Shields max
v_engineering_assignment_shields_min|护盾最小|護盾最小|Shields min
v_engineering_assignment_weapons_max|武器最大|武器最大|Guns max
v_engineering_assignment_weapons_min|武器最小|武器最小|Guns min
jump_hold|推进器激活|推進器啟動|Jump thruster
jump_release|推进器释放|推進器釋放|Release jump
weapon_auxiliary_action|下挂附件|下掛附件|Under gun
weapon_zeroing_increase|归零增加|歸零增加|Zeroing up
v_mgv_switch_brake_on_idle|怠速制动|怠速制動|Idle brake
spectate_toggle_lock_target|摄像头锁定|攝影機鎖定|Camera lock
hmd_toggle|VR 开关|VR 開關|VR on/off
hmd_recenter|VR 回中|VR 回中|VR center
hmd_theater_mode_toggle|VR 影院|VR 影院|VR theater
headtrack_recenter_device|头追回中|頭追回中|Head reset
foip_cyclechannel|切换频道|切換頻道|Voice next
pc_pit_looting_toggle_weapon_attachments|武器附件|武器附件|Loot mods
pc_pit_miningmode_actions|采矿动作|採礦動作|Mining actions
view_enable_camview_mode|高级视角|進階視角|Adv. camera
view_switch_to_alternative|高级视角|進階視角|Adv. camera
view_move_target_Y_pos|Y 轴正向|Y 軸正向|Y plus
view_move_target_Y_neg|Y 轴负向|Y 軸負向|Y minus
v_target_cycle_all_fwd|下一目标|下一目標|Next target
v_target_cycle_attacker_fwd|下一攻击者|下一攻擊者|Next attacker
v_target_cycle_hostile_fwd|下一敌方|下一敵方|Next hostile
v_target_cycle_friendly_fwd|下一友方|下一友方|Next friend
v_target_cycle_in_view_fwd|下一视野内|下一視野內|Next in view
v_target_cycle_subitem_fwd|下一副目标|下一副目標|Next part
v_weapon_countermeasure_decoy_launch|发射诱饵|發射誘餌|Decoy
v_weapon_countermeasure_decoy_burst_decrease|诱饵减少|誘餌減少|Decoys -
v_weapon_countermeasure_decoy_burst_increase|诱饵增加|誘餌增加|Decoys +
v_salvage_toggle_gimbal_mode|万向模式|萬向模式|Gimbal mode
v_salvage_focus_fracture|选碎裂头|選碎裂頭|Fracture head
v_salvage_focus_all_heads|选全部头|選全部頭|All heads
v_salvage_focus_left|选左侧头|選左側頭|Left head
v_salvage_focus_right|选右侧头|選右側頭|Right head
v_atc_loading_area_request|呼叫装卸区|呼叫裝卸區|ATC loading
weapon_zeroing_decrease|归零减少|歸零減少|Zeroing -
eva_toggle_headlook_mode|头部视角|頭部視角|Head look
view_move_target_Z_pos|Z 轴正向|Z 軸正向|Z plus
view_move_target_Z_neg|Z 轴负向|Z 軸負向|Z minus
view_move_target_X_pos|X 轴正向|X 軸正向|X plus
view_move_target_X_neg|X 轴负向|X 軸負向|X minus
notification_accept|接受|接受|Accept
notification_decline|拒绝|拒絕|Decline
pc_qs_consumables|消耗品轮盘|消耗品輪盤|Items wheel
pc_qs_grenades|投掷物轮盘|投擲物輪盤|Throw wheel
pc_qs_weapons_pit_secondary|副武器|副武器|2nd gun
select_secondary_pit|选副武器|選副武器|2nd gun
spectate_gen_nextmode|摄像头模式|攝影機模式|Cam mode
spectate_toggle_hud|摄像头界面|攝影機介面|Cam HUD
turret_gyromode|炮塔稳定|砲塔穩定|Gyro
v_auto_targeting_toggle_long|自动锁定|自動鎖定|Auto target
v_engineering_assignment_engine_decrease|引擎减少|引擎減少|Engines -
v_engineering_assignment_engine_increase|引擎增加|引擎增加|Engines +
v_engineering_assignment_weapons_decrease|武器减少|武器減少|Guns -
v_engineering_assignment_weapons_increase|武器增加|武器增加|Guns +
v_engineering_assignment_shields_decrease|护盾减少|護盾減少|Shields -
v_engineering_assignment_shields_increase|护盾增加|護盾增加|Shields +
v_ifcs_vector_decoupling_toggle|解耦模式|解耦模式|De-couple
v_light_amplification_toggle|微光增强|微光增強|Light amp
v_power_toggle_thrusters|开关推进器|開關推進器|Thrust
v_power_toggle_weapons|开关武器|開關武器|Guns
v_power_toggle_shields|开关护盾|開關護盾|Shields
v_strafe_back|节流阀降低|節流閥降低|Throttle -
v_strafe_forward|节流阀提升|節流閥提升|Throttle +
v_toggle_mining_mode|采矿模式|採礦模式|Mining
v_toggle_refuel_mode|加油模式|加油模式|Refuel
v_toggle_salvage_mode|打捞模式|打撈模式|Salvage
v_toggle_scan_mode|扫描模式|掃描模式|Scan
v_weapon_increase_max_missiles|导弹数增加|飛彈數增加|Missiles +
v_weapon_reset_max_missiles|重置导弹数|重置飛彈數|Reset missiles
ammoRepool|整理弹药|整理彈藥|Repool
customize|改装武器|改裝武器|Modify
foip_recalibrate|面部校准|面部校準|Face cal
foip_viewownplayer|看自己画面|看自己畫面|My view
headtrack_enabled|头部追踪|頭部追蹤|Head track
melee_dodgeBack|向后闪避|向後閃避|Dodge back
melee_dodgeLeft|向左闪避|向左閃避|Dodge left
melee_dodgeRight|向右闪避|向右閃避|Dodge right
mobiglas|手环|手環|Mobi
pc_interaction_mode|交互模式|互動模式|Use mode
pc_pit_inventory|背包|背包|Items
pl_hud_open_scoreboard|计分板|計分板|Scores
v_hud_open_scoreboard|计分板|計分板|Scores
reloadSecondary|副武器换弹|副武器換彈|Reload 2nd
respawn|重生|重生|Respawn
selectUnarmedCombat|徒手|徒手|Fists
toggle_flashlight|手电|手電|Light
toggleAttachHelmet|装取头盔|裝取頭盔|Helmet
v_emergency_exit|紧急离座|緊急離座|Bail out
v_engineering_assignment_reset|重置分配|重置分配|Reset power
v_power_throttle_down|降低供能|降低供能|Power -
v_transform_cycle|切换形态|切換形態|Shape
view_fov_out|放大视野|放大視野|FoV -
view_fstop_out|减小景深|減小景深|DoF -
pc_personal_thought|个人内思|個人內思|My menu
turret_remote_cycle_prev|上一个炮塔|上一個砲塔|Prev turret
turret_recenter|炮塔回中|砲塔回中|Center
toggle_contact|联系人|聯絡人|Comms
v_power_throttle_up|提升供能|提升供能|Power +
turret_remote_cycle_next|下个炮塔|下個砲塔|Next turret
pc_qs_weapons_pit_primary|主武器|主武器|1st gun
pc_qs_weapons_pit_sidearm|手枪|手槍|Pistol
v_jettison_volatile_cargo|抛货物|拋貨物|Dump cargo
turret_change_position|换炮位|換砲位|Swap seat
pc_pit_looting_toggle_view|搜刮视图|搜刮視圖|Loot view
prone_rollleft|左翻滚|左翻滾|Roll left
prone_rollright|右翻滚|右翻滾|Roll right
pc_screen_focus_up|焦点上|焦點上|Focus up
pc_screen_focus_left|焦点左|焦點左|Focus left
pc_screen_focus_down|焦点下|焦點下|Focus down
pc_screen_focus_right|焦点右|焦點右|Focus right
free_thirdperson_camera|自由视角|自由視角|Free cam
toggle_lowered|放下武器|放下武器|Lower gun
eva_roll_left|向左滚转|向左滾轉|Roll left
eva_roll_right|向右滚转|向右滾轉|Roll right
focus_on_chat_textinput|聊天输入|聊天輸入|Chat
view_restore_defaults|恢复视角|恢復視角|Reset view
v_master_mode_cycle_long|主模式|主模式|Mode
v_mining_use_consumable1|模块 1|模組 1|Module 1
v_mining_use_consumable2|模块 2|模組 2|Module 2
v_mining_use_consumable3|模块 3|模組 3|Module 3
v_salvage_toggle_fire_right|右打捞头|右打撈頭|Right head
v_salvage_toggle_fire_left|左打捞头|左打撈頭|Left head
turret_remote_exit|退出炮塔|退出砲塔|Exit turret
thirdperson|第三人称|第三人稱|3rd person
select_primary_pit|主武器|主武器|1st gun
weapon_change_firemode|射击模式|射擊模式|Fire mode
toggleEquipHelmet|头盔|頭盔|Helmet
zgt_detach|脱离|脫離|Let go
''';

final _caps = {
  for (final row in _capRows.trim().split(RegExp(r'\r?\n')))
    row.substring(0, row.indexOf('|')): row.split('|').sublist(1),
};

String? keyBindingCapLabel(AppStrings strings, String action) {
  final copy = _caps[action];
  if (copy == null) return null;
  if (strings.locale.languageCode == 'en') return copy[2];
  if (strings.locale.countryCode == 'TW' ||
      strings.locale.scriptCode == 'Hant') {
    return copy[1];
  }
  return copy[0];
}

/// How the action reads on a key. The bracket says how a key is pressed, and the
/// opened key shows it in full.
final _bracket = RegExp(r'（[^）]*）|\([^)]*\)');
String keyCapShortened(String name) {
  final short = name
      .replaceAll(_bracket, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return short.isEmpty ? name : short;
}

final class KeyCapText {
  const KeyCapText(this.text, {this.small = false, this.fits = true});
  final String text;

  /// One size down, on three lines: the last step before a name could not show.
  final bool small;

  /// False only if even that does not fit. Tests watch this.
  final bool fits;
}

/// Chooses what a key says, and never cuts it: the full name, then the short key
/// label, then our own name, then the same again one size smaller.
final class KeyCapFitter {
  KeyCapFitter({
    required this.style,
    required this.smallStyle,
    required this.width,
    required this.height,
    required this.textDirection,
    required this.textScaler,
  });
  final TextStyle style, smallStyle;
  final double width, height;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final _cache = <String, KeyCapText>{};

  static final _word = RegExp(r"[A-Za-z0-9][A-Za-z0-9.']*");

  double _measure(String text, TextStyle style, {int? lines}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: lines,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: lines == null ? double.infinity : width);
    final result =
        lines != null &&
            (painter.didExceedMaxLines || painter.height > height + 0.5)
        ? double.infinity
        : painter.width;
    painter.dispose();
    return result;
  }

  /// Fits in [lines] lines and the height under the key's letter, and no Latin
  /// word is split across two lines.
  bool _fits(String text, TextStyle style, int lines) {
    if (_measure(text, style, lines: lines) > width + 0.5) return false;
    for (final word in _word.allMatches(text)) {
      if (_measure(word[0]!, style) > width + 0.5) return false;
    }
    return true;
  }

  /// [prefix] is a tag that shares the lines with the name, in the small size.
  KeyCapText resolve(
    AppStrings strings,
    String action,
    String? name, {
    String? prefix,
  }) {
    return _cache.putIfAbsent('$action|$name|$prefix', () {
      final full = keyCapShortened(name ?? action);
      final cap = keyBindingCapLabel(strings, action);
      final own = keyBindingOwnName(strings, action);
      final candidates = [full, ?cap, if (own != null) keyCapShortened(own)];
      if (prefix == null) {
        for (final text in candidates) {
          if (_fits(text, style, 2)) return KeyCapText(text);
        }
      }
      for (final text in candidates) {
        final shown = prefix == null ? text : '$prefix $text';
        if (_fits(shown, smallStyle, 3)) return KeyCapText(text, small: true);
      }
      return KeyCapText(full, small: true, fits: false);
    });
  }
}
