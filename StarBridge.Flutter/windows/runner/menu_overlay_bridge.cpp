#include "menu_overlay_bridge.h"
#include "menu_overlay_window.h"
#include "menu_local_tools.h"
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
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
            !ReadText(*args, "contextLabel", next) || !ReadText(*args, "returnLabel", next) ||
            !ReadText(*args, "settingsLabel", next)) {
          result->Error("menu.invalid_configuration", "Invalid menu configuration."); return;
        }
        // Only presentation labels and explicitly selected live mode cross here. Never forward arbitrary
        // account/Host snapshots or credentials through a generic map.
        window_.Hide();
        const auto* live = Field(*args, "liveFriends");
        live_friends_ = preview && live && std::get_if<bool>(live) && std::get<bool>(*live);
        next[Value("liveFriends")] = Value(live_friends_);
        next[Value("nativeTools")] = Value(live_friends_);
        const auto* prefs_raw = Field(*args, "preferences");
        const auto* prefs = prefs_raw ? std::get_if<std::string>(prefs_raw) : nullptr;
        if (prefs && prefs->size() <= 32768) next[Value("preferences")] = Value(*prefs);
        const auto* prefs_failed = Field(*args, "preferencesFailed");
        next[Value("preferencesFailed")] = Value(prefs_failed && std::get_if<bool>(prefs_failed) && std::get<bool>(*prefs_failed));
        const auto* comms = Field(*args, "liveComms");
        live_comms_ = live_friends_ && comms && std::get_if<bool>(comms) && std::get<bool>(*comms);
        next[Value("liveComms")] = Value(live_comms_);
        const auto* features = Field(*args, "liveFeatures");
        next[Value("liveFeatures")] = Value(live_friends_ && features && std::get_if<bool>(features) && std::get<bool>(*features));
        snapshot_ = std::move(next);
        workspace_preview_ = preview;
        configured_ = true;
        if (preview) {
          const auto opening = Open();
          if (!opening) result->Error("menu.unavailable", "Menu could not prepare a frame.");
          else result->Success(Value(static_cast<int64_t>(opening)));
        } else result->Success();
      } else if (call.method_name() == "friendsView" || call.method_name() == "commsView" || call.method_name() == "profileView" || call.method_name() == "featureView" || call.method_name() == "preferencesState" || call.method_name() == "contextView") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* raw = args ? Field(*args, "payload") : nullptr;
        const auto* payload = raw ? std::get_if<std::string>(raw) : nullptr;
        if (!args || !payload || payload->size() > 1048576 ||
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
        window_.Hide(true); result->Success();
      } else if (call.method_name() == "status") {
        result->Success(Value(Map{
          {Value("configured"), Value(configured_)},
          {Value("dartReady"), Value(dart_ready_)},
          {Value("wanted"), Value(window_.session().wanted())}}));
      } else if (call.method_name() == "detach") {
        configured_ = false;
        window_.UnregisterShortcut();
        window_.Hide();
        snapshot_.clear();
        Update();
        result->Success();
      } else if (call.method_name() == "shortcut") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* mods = args && Field(*args,"modifiers") ? std::get_if<int32_t>(Field(*args,"modifiers")) : nullptr;
        const auto* key = args && Field(*args,"key") ? std::get_if<int32_t>(Field(*args,"key")) : nullptr;
        if (!configured_ || !mods || !key || !window_.Create() ||
            !window_.RegisterShortcut(static_cast<UINT>(*mods), static_cast<UINT>(*key))) {
          result->Error("menu.shortcut_unavailable", "Shortcut is invalid or already in use."); return;
        }
        result->Success();
      } else { result->NotImplemented(); }
    });
    window_.on_shortcut = [this]() {
      if (window_.session().wanted()) window_.Hide(true);
      else if (!Open()) primary_.InvokeMethod("state", std::make_unique<Value>("unavailable"));
    };
    window_.on_hidden = [this]() {
      if (local_tools_) local_tools_->Hide();
      Update();
      primary_.InvokeMethod("state", std::make_unique<Value>("hidden"));
    };
    window_.on_message = [this](HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) -> std::optional<LRESULT> {
      if (msg == kFrameReady) {
        if (window_.Reveal(static_cast<uint64_t>(wp)))
          primary_.InvokeMethod("state", std::make_unique<Value>("visible"));
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
  uint64_t Open() {
    if (!configured_) return 0;
    if (window_.session().wanted()) return window_.session().generation();
    const HWND foreground = GetForegroundWindow();
    if (!foreground) return 0;
    if (!window_.Create() || !EnsureEngine()) return 0;
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
      } else if (call.method_name() == "localTool") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
          if (!args || !local_tools_ || !live_friends_ || !window_.session().wanted() ||
            Integer(*args, "opening") != static_cast<int64_t>(window_.session().generation())) {
          result->Error("menu.closed", "Menu is closed"); return;
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
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<Channel> secondary_;
  std::unique_ptr<MenuLocalTools> local_tools_;
};

MenuOverlayBridge::MenuOverlayBridge(flutter::BinaryMessenger* messenger, HWND client)
    : impl_(std::make_unique<Impl>(messenger, client)) {}
MenuOverlayBridge::~MenuOverlayBridge() = default;
