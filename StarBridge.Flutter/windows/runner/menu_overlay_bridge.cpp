#include "menu_overlay_bridge.h"
#include "menu_overlay_window.h"
#include "menu_local_tools.h"
#include "menu_screenshot_settings_intent.h"
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <atomic>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Channel = flutter::MethodChannel<Value>;
constexpr UINT kFrameReady = WM_APP + 0x73;
const Value* Field(const Map& map, const char* name) {
  const auto item = map.find(Value(name));
  return item == map.end() ? nullptr : &item->second;
}
bool ReadText(const Map& map, const char* name, Map& output) {
  const auto* field = Field(map, name);
  const auto* text = field ? std::get_if<std::string>(field) : nullptr;
  if (!text || text->empty() || text->size() > 512) return false;
  output[Value(name)] = *field;
  return true;
}
int64_t Integer(const Map& map, const char* name) {
  const auto* value = Field(map, name);
  if (!value) return -1;
  if (const auto* wide = std::get_if<int64_t>(value)) return *wide;
  if (const auto* narrow = std::get_if<int32_t>(value)) return *narrow;
  return -1;
}
}

class MenuOverlayBridge::Impl {
 public:
  explicit Impl(flutter::BinaryMessenger* messenger, HWND client)
      : primary_(messenger, "starbridge/menu-primary", &flutter::StandardMethodCodec::GetInstance()),
        alive_(std::make_shared<std::atomic_bool>(true)), client_(client) {
    primary_.SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "configure" || call.method_name() == "preview") {
        const bool preview = call.method_name() == "preview";
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        Map next;
        const auto* version = args ? Field(*args, "schemaVersion") : nullptr;
        const auto* schema = version ? std::get_if<int32_t>(version) : nullptr;
        if (!schema || *schema != 1 ||
            (Field(*args, "request") && (Integer(*args, "request") <= 0 || Integer(*args, "request") > 9007199254740991LL)) ||
            !ReadText(*args, "contextLabel", next) || !ReadText(*args, "returnLabel", next) ||
            !ReadText(*args, "settingsLabel", next)) {
          result->Error("menu.invalid_configuration", "Invalid menu configuration."); return;
        }
        // Only presentation labels and explicitly selected live mode cross here. Never forward arbitrary
        // account/Host snapshots or credentials through a generic map.
        HWND target = nullptr;
        DWORD target_pid = 0;
        if (Field(*args, "targetWindow") || Field(*args, "targetProcessId")) {
          const auto handle = Integer(*args, "targetWindow"), pid = Integer(*args, "targetProcessId");
          if (!preview || handle <= 0 || handle > 9007199254740991LL || pid <= 0 || pid > MAXDWORD) {
            result->Error("menu.invalid_configuration", "Invalid foreground target."); return;
          }
          target = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
          target_pid = static_cast<DWORD>(pid);
          if (!TargetIsForeground(target, target_pid)) {
            result->Error("menu.foreground_changed", "Foreground target changed."); return;
          }
        }
        window_.Hide();
        request_ = Field(*args, "request") ? Integer(*args, "request") : 0;
        const auto* live = Field(*args, "liveFriends");
        live_friends_ = preview && live && std::get_if<bool>(live) && std::get<bool>(*live);
        next[Value("liveFriends")] = Value(live_friends_);
        next[Value("nativeTools")] = Value(live_friends_);
        const auto* screenshot_directory = Field(*args, "screenshotDirectory");
        next[Value("screenshotDirectory")] = Value(live_friends_ && screenshot_directory &&
            std::get_if<bool>(screenshot_directory) && std::get<bool>(*screenshot_directory));
        // Read the user's Windows 12/24-hour preference rather than inferring it
        // from the application language. No user locale data is persisted.
        wchar_t clock_format[2]{};
        if (GetLocaleInfoEx(LOCALE_NAME_USER_DEFAULT, LOCALE_ITIME, clock_format, 2) == 2)
          next[Value("system24Hour")] = Value(clock_format[0] == L'1');
        const auto* shortcut = Field(*args, "shortcutSettings");
        next[Value("shortcutSettings")] = Value(live_friends_ && shortcut && std::get_if<bool>(shortcut) && std::get<bool>(*shortcut));
        const auto* resume = Field(*args, "browserResume");
        next[Value("browserResume")] = Value(live_friends_ && resume && std::get_if<bool>(resume) && std::get<bool>(*resume));
        const auto* prefs_raw = Field(*args, "preferences");
        const auto* prefs = prefs_raw ? std::get_if<std::string>(prefs_raw) : nullptr;
        if (prefs && prefs->size() <= 32768) next[Value("preferences")] = Value(*prefs);
        const auto* prefs_failed = Field(*args, "preferencesFailed");
        next[Value("preferencesFailed")] = Value(prefs_failed && std::get_if<bool>(prefs_failed) && std::get<bool>(*prefs_failed));
        const auto* startup_raw = Field(*args, "startupMode");
        const auto* startup = startup_raw ? std::get_if<std::string>(startup_raw) : nullptr;
        if (startup && (*startup == "normal" || *startup == "safe" || *startup == "unverified"))
          next[Value("startupMode")] = Value(*startup);
        const auto* recovery = Field(*args, "recoveryPending");
        next[Value("recoveryPending")] = Value(live_friends_ && recovery && std::get_if<bool>(recovery) && std::get<bool>(*recovery));
        const auto* comms = Field(*args, "liveComms");
        live_comms_ = live_friends_ && comms && std::get_if<bool>(comms) && std::get<bool>(*comms);
        next[Value("liveComms")] = Value(live_comms_);
        const auto* features = Field(*args, "liveFeatures");
        next[Value("liveFeatures")] = Value(live_friends_ && features && std::get_if<bool>(features) && std::get<bool>(*features));
        snapshot_ = std::move(next);
        workspace_preview_ = preview;
        configured_ = true;
        if (preview) {
          const auto opening = Open(target, target_pid);
          if (!opening) result->Error("menu.unavailable", "Menu could not prepare a frame.");
          else result->Success(Value(static_cast<int64_t>(opening)));
        } else result->Success();
      } else if (call.method_name() == "friendsView" || call.method_name() == "commsView" || call.method_name() == "profileView" || call.method_name() == "featureView" || call.method_name() == "preferencesState" || call.method_name() == "contextView" || call.method_name() == "attentionView" || call.method_name() == "noticeView") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* raw = args ? Field(*args, "payload") : nullptr;
        const auto* payload = raw ? std::get_if<std::string>(raw) : nullptr;
        if (!args || !payload || payload->size() > 1048576 ||
            (call.method_name() == "attentionView" && payload->size() > 256) ||
            (call.method_name() == "noticeView" && payload->size() > 65536) ||
            (call.method_name() != "preferencesState" && !(call.method_name() == "commsView" ? live_comms_ : live_friends_)) || !window_.session().wanted() ||
            Integer(*args, "opening") != static_cast<int64_t>(window_.session().generation()) ||
            Integer(*args, "revision") < 0) {
          result->Success(); return;
        }
        // Narrow display envelope only; never an account or Host snapshot.
        if (dart_ready_ && secondary_) secondary_->InvokeMethod(call.method_name(), std::make_unique<Value>(Map{
          {Value("opening"), Value(Integer(*args, "opening"))},
          {Value("revision"), Value(Integer(*args, "revision"))},
          {Value("payload"), Value(*payload)}}));
        result->Success();
      } else if (call.method_name() == "handoffProfile") {
        // Retired: profile tools stay inside the menu workspace.
        result->Success(Value(false));
      } else if (call.method_name() == "open") {
        const auto opening = Open();
        if (!opening) result->Error("menu.unavailable", "Menu could not prepare a frame.");
        else result->Success(Value(static_cast<int64_t>(opening)));
      } else if (call.method_name() == "close") {
        if (!OwnsRequest(call.arguments())) { result->Success(); return; }
        window_.Hide(true); result->Success();
      } else if (call.method_name() == "status") {
        result->Success(Value(Map{
          {Value("configured"), Value(configured_)},
          {Value("dartReady"), Value(dart_ready_)},
          {Value("wanted"), Value(window_.session().wanted())}}));
      } else if (call.method_name() == "detach") {
        if (!OwnsRequest(call.arguments())) { result->Success(); return; }
        configured_ = false;
        window_.UnregisterShortcut();
        window_.Hide();
        live_friends_ = live_comms_ = workspace_preview_ = false;
        if (local_tools_) local_tools_->Reset();
        ++local_tools_epoch_;
        snapshot_.clear();
        Update();
        result->Success();
      } else if (call.method_name() == "shortcut") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* mods = args && Field(*args,"modifiers") ? std::get_if<int32_t>(Field(*args,"modifiers")) : nullptr;
        const auto* key = args && Field(*args,"key") ? std::get_if<int32_t>(Field(*args,"key")) : nullptr;
        if (live_friends_ || !configured_ || !mods || !key || !window_.Create() ||
            !window_.RegisterShortcut(static_cast<UINT>(*mods), static_cast<UINT>(*key))) {
          result->Error("menu.shortcut_unavailable", "Shortcut is invalid or already in use."); return;
        }
        result->Success();
      } else { result->NotImplemented(); }
    });
    window_.on_shortcut = [this]() {
      if (window_.session().wanted()) window_.Hide(true);
      else if (!Open()) NotifyState("unavailable");
    };
    window_.on_hidden = [this]() {
      if (local_tools_) local_tools_->Hide();
      Update();
      NotifyState("hidden");
    };
    window_.on_message = [this](HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) -> std::optional<LRESULT> {
      if (msg == kFrameReady) {
        if (window_.Reveal(static_cast<uint64_t>(wp)))
          NotifyState("visible");
        return 0;
      }
      if (controller_) return controller_->HandleTopLevelWindowProc(hwnd, msg, wp, lp);
      return std::nullopt;
    };
  }
  ~Impl() {
    *alive_ = false;
    primary_.SetMethodCallHandler(nullptr);
    window_.on_hidden = nullptr;
    window_.on_shortcut = nullptr;
    window_.on_message = nullptr;
    window_.Hide();
    window_.UnregisterShortcut();
    if (secondary_) secondary_->SetMethodCallHandler(nullptr);
    secondary_.reset();
    local_tools_.reset();
    controller_.reset();
  }

 private:
  int64_t request_ = 0;
  bool OwnsRequest(const Value* value) const {
    const auto* args = value ? std::get_if<Map>(value) : nullptr;
    // Unscoped control is reserved for the internal configure-only fixture.
    return request_ == 0 ? !args || !Field(*args, "request")
                         : args && Integer(*args, "request") == request_;
  }
  void NotifyState(const char* state) {
    primary_.InvokeMethod("state", std::make_unique<Value>(Map{
      {Value("request"), Value(request_)}, {Value("state"), Value(state)},
      {Value("window"), Value(static_cast<int64_t>(reinterpret_cast<intptr_t>(window_.handle())))}}));
  }
  static bool TargetIsForeground(HWND target, DWORD pid) {
    DWORD actual = 0;
    if (!target || !IsWindow(target) || GetForegroundWindow() != target) return false;
    GetWindowThreadProcessId(target, &actual);
    return actual == pid && GetForegroundWindow() == target;
  }
  uint64_t Open(HWND target = nullptr, DWORD target_pid = 0) {
    if (!configured_) return 0;
    if (window_.session().wanted()) return window_.session().generation();
    const HWND foreground = GetForegroundWindow();
    if (!foreground) return 0;
    if (target && !TargetIsForeground(target, target_pid)) return 0;
    if (!window_.Create() || !EnsureEngine()) return 0;
    if (target && !TargetIsForeground(target, target_pid)) return 0;
    const auto opening = window_.Begin(foreground);
    if (opening) Update();
    return opening;
  }
  bool EnsureEngine() {
    if (controller_) return true;
    flutter::DartProject project(L"data");
#ifdef STARBRIDGE_MENU_PREVIEW
    project.set_dart_entrypoint("menuPreviewMain");
#else
    project.set_dart_entrypoint("menuMain");
#endif
    controller_ = std::make_unique<flutter::FlutterViewController>(1, 1, project);
    if (!controller_->engine() || !controller_->view() ||
        !window_.Attach(controller_->view()->GetNativeWindow())) {
      controller_.reset(); return false;
    }
    local_tools_ = std::make_unique<MenuLocalTools>(window_.handle(),
        [this]() { return window_.session().wanted(); },
        [this](bool modal) { window_.SetLocalModal(modal); },
        [this]() { window_.Hide(true); });
    secondary_ = std::make_unique<Channel>(controller_->engine()->messenger(),
        "starbridge/menu-surface", &flutter::StandardMethodCodec::GetInstance());
    secondary_->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "ready") {
        dart_ready_ = true;
        result->Success(Value(Snapshot()));
      } else if (call.method_name() == "shortcutSettings" || call.method_name() == "recoveryAction" || call.method_name() == "browserResume" || call.method_name() == "screenshotDirectory") {
        const bool recovery = call.method_name() == "recoveryAction";
        const bool resume = call.method_name() == "browserResume";
        const bool directory = call.method_name() == "screenshotDirectory";
        const std::string prefix = directory ? "menuScreenshotDirectory" : recovery ? "menuRecovery" : resume ? "menuBrowserResume" : "menuHotkey";
        const std::string unavailable = prefix + ".session_unavailable";
        const std::string failed = prefix + ".unavailable";
        const size_t reply_limit = directory ? 262144 : recovery ? 32768 : resume ? 24576 : 1024;
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* action_raw = args ? Field(*args, "action") : nullptr;
        const auto* action = action_raw ? std::get_if<std::string>(action_raw) : nullptr;
        const auto* payload_raw = args ? Field(*args, "payload") : nullptr;
        const auto* payload = payload_raw ? std::get_if<std::string>(payload_raw) : nullptr;
        const auto opening = window_.session().generation();
        const auto* directory_capability = Field(snapshot_, "screenshotDirectory");
        const bool directory_allowed = directory_capability && std::get_if<bool>(directory_capability) && std::get<bool>(*directory_capability);
        if (!args || !action || !live_friends_ || !window_.session().wanted() ||
            Integer(*args, "opening") != static_cast<int64_t>(opening) ||
            !(directory ? (directory_allowed && !window_.local_modal() && ValidScreenshotSettingsIntent(*args)) :
              recovery ? (args->size() == 2 && (*action == "restore" || *action == "startClean")) :
              ((*action == "get" && args->size() == 2) ||
              ((*action == "update" || (resume && *action == "remember")) && args->size() == 3 && payload && payload->size() <= reply_limit)))) {
          result->Error(unavailable, "Menu settings unavailable"); return;
        }
        const auto life = alive_;
        const auto owner = request_;
        auto pending = std::shared_ptr<flutter::MethodResult<Value>>(std::move(result));
        auto current = [this, life, opening, owner]() {
          return *life && request_ == owner && live_friends_ && window_.session().wanted() &&
              window_.session().generation() == opening;
        };
        const bool choosing = directory && *action == "choose";
        if (choosing) window_.SetLocalModal(true);
        auto finish_modal = [this, current, choosing]() {
          if (choosing && current()) window_.SetLocalModal(false);
        };
        primary_.InvokeMethod(call.method_name(), std::make_unique<Value>(*args),
          std::make_unique<flutter::MethodResultFunctions<Value>>(
            [pending, current, life, unavailable, failed, reply_limit, finish_modal](const Value* value) {
              if (!*life) return;
              finish_modal();
              const auto* text = value ? std::get_if<std::string>(value) : nullptr;
              if (!current()) pending->Error(unavailable, "Menu session changed");
              else if (!text || text->size() > reply_limit) pending->Error(failed, "Invalid settings reply");
              else pending->Success(*value);
            },
            [pending, current, life, unavailable, finish_modal](const std::string& code, const std::string&, const Value*) {
              if (!*life) return;
              finish_modal();
              pending->Error(current() ? code : unavailable, "Menu settings unavailable");
            },
            [pending, life, failed, finish_modal]() { if (*life) { finish_modal(); pending->Error(failed, "Menu settings unavailable"); } }));
      } else if (call.method_name() == "localTool") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
          if (!args || !local_tools_ || !live_friends_ || window_.local_modal() || !window_.session().wanted() ||
            Integer(*args, "opening") != static_cast<int64_t>(window_.session().generation())) {
          result->Error("menu.closed", "Menu is closed"); return;
        }
        const auto* action_raw = Field(*args, "action");
        const auto* action = action_raw ? std::get_if<std::string>(action_raw) : nullptr;
        if (action && *action == "screenshotDestination") {
          local_tools_->AuthorizeScreenshotDirectory("");
          const auto* capability = Field(snapshot_, "screenshotDirectory");
          if (args->size() != 2 || !capability || !std::get_if<bool>(capability) || !std::get<bool>(*capability)) {
            result->Error("menu.screenshot_directory_unavailable", "Screenshot directory unavailable"); return;
          }
          const auto life = alive_;
          const auto opening = window_.session().generation();
          const auto epoch = local_tools_epoch_;
          const auto owner = request_;
          auto pending = std::shared_ptr<flutter::MethodResult<Value>>(std::move(result));
          auto current = [this, life, opening, epoch, owner]() {
            return *life && local_tools_ && local_tools_epoch_ == epoch && request_ == owner &&
                live_friends_ && window_.session().wanted() && window_.session().generation() == opening;
          };
          primary_.InvokeMethod("screenshotDestination", std::make_unique<Value>(Map{
              {Value("opening"), Value(static_cast<int64_t>(opening))}}),
            std::make_unique<flutter::MethodResultFunctions<Value>>(
              [this, pending, current, life](const Value* value) {
                if (!*life) return;
                const auto* directory = value ? std::get_if<std::string>(value) : nullptr;
                if (!current()) pending->Error("menu.closed", "Menu session changed");
                else if (!directory || !local_tools_->AuthorizeScreenshotDirectory(*directory))
                  pending->Error("menu.screenshot_directory_unavailable", "Screenshot directory unavailable");
                else pending->Success(Value(true)); // The surface receives no path.
              },
              [pending, current, life](const std::string&, const std::string&, const Value*) {
                if (*life) pending->Error(current() ? "menu.screenshot_directory_unavailable" : "menu.closed", "Screenshot directory unavailable");
              },
              [pending, life]() { if (*life) pending->Error("menu.screenshot_directory_unavailable", "Screenshot directory unavailable"); }));
          return;
        }
        local_tools_->Handle(*args, std::move(result));
      } else if (call.method_name() == "preferencesChanged") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* raw = args ? Field(*args, "payload") : nullptr;
        const auto* payload = raw ? std::get_if<std::string>(raw) : nullptr;
        if (args && payload && payload->size() <= 32768 && window_.session().wanted() && Integer(*args, "opening") == static_cast<int64_t>(window_.session().generation()))
          primary_.InvokeMethod("preferencesChanged", std::make_unique<Value>(Map{{Value("opening"), Value(Integer(*args, "opening"))}, {Value("payload"), Value(*payload)}}));
        result->Success();
      } else if (call.method_name() == "painted") {
        const auto* value = call.arguments();
        int64_t generation = 0;
        if (value) {
          if (const auto* large = std::get_if<int64_t>(value)) generation = *large;
          else if (const auto* narrow_value = std::get_if<int32_t>(value)) generation = *narrow_value;
        }
        if (generation > 0 && static_cast<uint64_t>(generation) == window_.session().generation() &&
            window_.session().phase() == MenuOverlaySession::Phase::awaiting_frame) {
          const auto life = alive_;
          const auto hwnd = window_.handle();
          controller_->engine()->SetNextFrameCallback([life, hwnd, generation]() {
            if (*life) PostMessageW(hwnd, kFrameReady, static_cast<WPARAM>(generation), 0);
          });
          controller_->ForceRedraw();
        }
        result->Success();
      } else if (call.method_name() == "friendsVisible" || call.method_name() == "commsVisible") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* raw = args ? Field(*args, "visible") : nullptr;
        const auto* visible = raw ? std::get_if<bool>(raw) : nullptr;
        if (args && visible && (call.method_name() == "friendsVisible" ? live_friends_ : live_comms_) && window_.session().wanted() &&
            Integer(*args, "opening") == static_cast<int64_t>(window_.session().generation())) {
          primary_.InvokeMethod(call.method_name(), std::make_unique<Value>(Map{
            {Value("opening"), Value(Integer(*args, "opening"))},
            {Value("visible"), Value(*visible)}}));
        }
        result->Success();
      } else if (call.method_name() == "featureVisible" || call.method_name() == "featureAction") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* tool_raw = args ? Field(*args, "tool") : nullptr;
        const auto* tool = tool_raw ? std::get_if<std::string>(tool_raw) : nullptr;
        const auto* enabled_raw = Field(snapshot_, "liveFeatures");
        const bool enabled = enabled_raw && std::get_if<bool>(enabled_raw) && std::get<bool>(*enabled_raw);
        if (!args || !tool || (*tool != "organizations" && *tool != "rooms" && *tool != "hud" && *tool != "organizationChat" && *tool != "roomChat") || !enabled || !live_friends_ ||
            !window_.session().wanted() || Integer(*args, "opening") != static_cast<int64_t>(window_.session().generation())) {
          result->Error("menu.unavailable", "Tool unavailable"); return;
        }
        Map next{{Value("opening"), Value(Integer(*args, "opening"))}, {Value("tool"), Value(*tool)}};
        if (call.method_name() == "featureVisible") {
          const auto* raw = Field(*args, "visible");
          const auto* visible = raw ? std::get_if<bool>(raw) : nullptr;
          if (!visible) { result->Error("menu.invalid_intent", "Invalid visibility"); return; }
          next[Value("visible")] = Value(*visible);
        } else {
          const auto* key_raw = Field(*args, "key"), *value_raw = Field(*args, "value");
          const auto* key = key_raw ? std::get_if<std::string>(key_raw) : nullptr;
          const auto* value = value_raw ? std::get_if<std::string>(value_raw) : nullptr;
          if (!key || key->size() > 64 || !value || value->size() > 8192) {
            result->Error("menu.invalid_intent", "Invalid intent"); return;
          }
          next[Value("key")] = Value(*key); next[Value("value")] = Value(*value);
        }
        primary_.InvokeMethod(call.method_name(), std::make_unique<Value>(std::move(next)));
        result->Success();
      } else if (call.method_name() == "profileAction") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* source_raw = args ? Field(*args, "source") : nullptr;
        const auto* key_raw = args ? Field(*args, "key") : nullptr;
        const auto* source = source_raw ? std::get_if<std::string>(source_raw) : nullptr;
        const auto* key = key_raw ? std::get_if<std::string>(key_raw) : nullptr;
        const auto* action_raw = args ? Field(*args, "action") : nullptr;
        const auto* window_raw = args ? Field(*args, "window") : nullptr;
        const auto* action = action_raw ? std::get_if<std::string>(action_raw) : nullptr;
        const auto* tool = window_raw ? std::get_if<std::string>(window_raw) : nullptr;
        const bool valid_tool = tool && tool->size() >= 2 && tool->size() <= 10 &&
            (*tool)[0] == 'p' && (*tool)[1] >= '1' && (*tool)[1] <= '9' &&
            tool->find_first_not_of("0123456789", 1) == std::string::npos;
        const bool valid_action = action && ((*action == "open" && source && key && !key->empty() && key->size() <= 64 &&
            ((*source == "friends" && live_friends_) || (*source == "comms" && live_comms_) ||
             (*source == "organizations" && live_friends_) ||
             (*source == "organizationChat" && live_comms_))) ||
            (*action == "refresh" || *action == "close"));
        if (args && live_friends_ && valid_tool && valid_action &&
            window_.session().wanted() &&
            Integer(*args, "opening") == static_cast<int64_t>(window_.session().generation())) {
          primary_.InvokeMethod("profileAction", std::make_unique<Value>(Map{
            {Value("opening"), Value(Integer(*args, "opening"))},
            {Value("action"), Value(*action)}, {Value("window"), Value(*tool)},
            {Value("source"), Value(source ? *source : "")}, {Value("key"), Value(key ? *key : "")}}));
        }
        result->Success();
      } else if (call.method_name() == "friendsAction") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* action_raw = args ? Field(*args, "action") : nullptr;
        const auto* key_raw = args ? Field(*args, "key") : nullptr;
        const auto* value_raw = args ? Field(*args, "value") : nullptr;
        const auto* action = action_raw ? std::get_if<std::string>(action_raw) : nullptr;
        const auto* key = key_raw ? std::get_if<std::string>(key_raw) : nullptr;
        const auto* value = value_raw ? std::get_if<std::string>(value_raw) : nullptr;
        if (args && action && key && key->size() <= 64 && value && value->size() <= 512 &&
            live_friends_ && window_.session().wanted() &&
            Integer(*args, "opening") == static_cast<int64_t>(window_.session().generation()) &&
            (*action == "prepare" || *action == "confirm" || *action == "dismiss" ||
             *action == "refresh" || *action == "section" || *action == "search" || *action == "presence")) {
          primary_.InvokeMethod("friendsAction", std::make_unique<Value>(Map{
            {Value("opening"), Value(Integer(*args, "opening"))},
            {Value("action"), Value(*action)}, {Value("key"), Value(*key)}, {Value("value"), Value(*value)}}));
          result->Success();
        } else { result->Error("menu.invalid_friend_action", "Friend action is no longer available"); }
      } else if (call.method_name() == "commsCompose") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* action_raw = args ? Field(*args, "action") : nullptr;
        const auto* key_raw = args ? Field(*args, "key") : nullptr;
        const auto* text_raw = args ? Field(*args, "text") : nullptr;
        const auto* action = action_raw ? std::get_if<std::string>(action_raw) : nullptr;
        const auto* key = key_raw ? std::get_if<std::string>(key_raw) : nullptr;
        const auto* text = text_raw ? std::get_if<std::string>(text_raw) : nullptr;
        if (args && action && key && !key->empty() && key->size() <= 64 && text && text->size() <= 4000 &&
            live_comms_ && window_.session().wanted() &&
            Integer(*args, "opening") == static_cast<int64_t>(window_.session().generation()) &&
            Integer(*args, "revision") >= 0 && Integer(*args, "revision") <= 1000000000 &&
            (*action == "edit" || *action == "send" || *action == "check")) {
          primary_.InvokeMethod("commsCompose", std::make_unique<Value>(Map{
            {Value("opening"), Value(Integer(*args, "opening"))},
            {Value("action"), Value(*action)}, {Value("key"), Value(*key)},
            {Value("text"), Value(*text)}, {Value("revision"), Value(Integer(*args, "revision"))}}));
        }
        result->Success();
      } else if (call.method_name() == "commsAction") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* action_raw = args ? Field(*args, "action") : nullptr;
        const auto* key_raw = args ? Field(*args, "key") : nullptr;
        const auto* action = action_raw ? std::get_if<std::string>(action_raw) : nullptr;
        const auto* key = key_raw ? std::get_if<std::string>(key_raw) : nullptr;
        if (args && action && key && key->size() <= 64 && live_comms_ && window_.session().wanted() &&
            Integer(*args, "opening") == static_cast<int64_t>(window_.session().generation()) &&
            (*action == "select" || *action == "back" || *action == "retry" || *action == "older" || *action == "latest" || *action == "friend" || *action == "read" ||
             *action == "attachment" || *action == "inviteSend" || *action == "inviteRecords" || *action == "inviteAction" || *action == "inviteClose" || *action == "clearLocal")) {
          primary_.InvokeMethod("commsAction", std::make_unique<Value>(Map{
            {Value("opening"), Value(Integer(*args, "opening"))},
            {Value("action"), Value(*action)}, {Value("key"), Value(*key)}}));
        }
        result->Success();
      } else if (call.method_name() == "dismiss") {
        window_.Hide(true); result->Success();
      } else { result->NotImplemented(); }
    });
    return true;
  }
  Map Snapshot() const {
    Map value = window_.session().wanted() ? snapshot_ : Map{};
    value[Value("opening")] = Value(static_cast<int64_t>(window_.session().generation()));
    value[Value("wanted")] = Value(window_.session().wanted());
    value[Value("workspacePreview")] = Value(workspace_preview_);
    value[Value("localToolsEpoch")] = Value(local_tools_epoch_);
    return value;
  }
  void Update() {
    if (dart_ready_ && secondary_) secondary_->InvokeMethod("snapshot", std::make_unique<Value>(Snapshot()));
  }
  Channel primary_;
  std::shared_ptr<std::atomic_bool> alive_;
  HWND client_ = nullptr;
  MenuOverlayWindow window_;
  Map snapshot_;
  bool configured_ = false;
  bool dart_ready_ = false;
  bool workspace_preview_ = false;
  bool live_friends_ = false;
  bool live_comms_ = false;
  int64_t local_tools_epoch_ = 0;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<Channel> secondary_;
  std::unique_ptr<MenuLocalTools> local_tools_;
};

MenuOverlayBridge::MenuOverlayBridge(flutter::BinaryMessenger* messenger, HWND client)
    : impl_(std::make_unique<Impl>(messenger, client)) {}
MenuOverlayBridge::~MenuOverlayBridge() = default;
