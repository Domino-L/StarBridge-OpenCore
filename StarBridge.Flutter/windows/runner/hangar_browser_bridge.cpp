#include "hangar_browser_bridge.h"
#include "hangar_scan_lock.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <wrl.h>
#include <cmath>
#include <filesystem>
#include <functional>
#include <string>
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
#include <WebView2.h>
#include "hangar_browser_session.h"
#include "hangar_reader_assets.h"
#endif

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Result = flutter::MethodResult<Value>;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
[[maybe_unused]] int64_t Integer(const Map& map, const char* name) {
  auto it = map.find(Value(name)); if (it == map.end()) return -1;
  if (auto v = std::get_if<int32_t>(&it->second)) return *v;
  if (auto v = std::get_if<int64_t>(&it->second)) return *v;
  return -1;
}
[[maybe_unused]] double Number(const Map& map, const char* name) {
  auto it = map.find(Value(name)); if (it == map.end()) return -1;
  if (auto v = std::get_if<double>(&it->second)) return *v;
  return static_cast<double>(Integer(map, name));
}
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
std::string Utf8(const wchar_t* text) {
  if (!text) return {};
  const int n = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, -1, nullptr, 0, nullptr, nullptr);
  if (n < 2 || n > 600 * 1024) return {};
  std::string out(static_cast<size_t>(n), '\0');
  if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, -1, out.data(), n, nullptr, nullptr)) return {};
  out.pop_back(); return out;
}
bool Rsi(const std::wstring& source) { return source.rfind(L"https://robertsspaceindustries.com/", 0) == 0; }
int HangarPage(const std::wstring& source) {
  if (!Rsi(source)) return 0;
  auto tail = source.substr(std::wstring(L"https://robertsspaceindustries.com/").size());
  if (tail.rfind(L"en/", 0) == 0) tail = tail.substr(3);
  if (tail == L"account/pledges") return 1;
  const std::wstring prefix = L"account/pledges?page=";
  if (tail.rfind(prefix, 0) != 0) return 0;
  auto number = tail.substr(prefix.size());
  const std::wstring suffix = L"&product-type=";
  if (number.size() >= suffix.size() && number.substr(number.size() - suffix.size()) == suffix)
    number.resize(number.size() - suffix.size());
  if (number.empty() || number.size() > 3 || number[0] == L'0' || number.find_first_not_of(L"0123456789") != std::wstring::npos) return 0;
  const int page = std::stoi(number); return page <= 100 ? page : 0;
}

struct Browser : std::enable_shared_from_this<Browser> {
  HWND parent;
  HWND viewport = nullptr;
  int64_t id;
  bool closed = false, ready = false, reading = false;
  HangarScanLock scan;
  std::string profile_key;
  uint64_t generation = 0, navigation = 0;
  ComPtr<ICoreWebView2Controller> controller;
  ComPtr<ICoreWebView2> webview;
  std::function<void(bool)> leave_focus;
  explicit Browser(HWND hwnd, int64_t view_id, const std::string& key)
      : parent(hwnd), id(view_id), profile_key(key) {}
  std::wstring Source() const {
    LPWSTR text = nullptr; if (!webview || FAILED(webview->get_Source(&text))) return {};
    std::wstring value = text ? text : L""; CoTaskMemFree(text); return value;
  }
  void Close() { closed = true; ready = false; ++generation;
    scan.End();
    if (webview) webview->Stop(); if (controller) controller->Close(); webview.Reset(); controller.Reset();
    if (viewport) { DestroyWindow(viewport); viewport = nullptr; } }
  void Unlock() {
    if (scan.Active() && !ready && webview) webview->Stop();
    scan.End();
    if (viewport) SetHangarInteraction(viewport, parent, false);
  }
  bool Configure() {
    ComPtr<ICoreWebView2Settings> settings;
    if (FAILED(controller->get_CoreWebView2(&webview)) || FAILED(webview->get_Settings(&settings)) ||
        FAILED(settings->put_AreHostObjectsAllowed(FALSE)) || FAILED(settings->put_IsWebMessageEnabled(FALSE)) ||
        FAILED(settings->put_AreDevToolsEnabled(FALSE)) || FAILED(settings->put_AreDefaultContextMenusEnabled(FALSE)) ||
        FAILED(settings->put_AreDefaultScriptDialogsEnabled(FALSE))) return false;
    // No password/autofill data is shared with the user's Edge profile.
    ComPtr<ICoreWebView2Settings4> settings4;
    if (FAILED(settings.As(&settings4)) || FAILED(settings4->put_IsPasswordAutosaveEnabled(FALSE)) ||
        FAILED(settings4->put_IsGeneralAutofillEnabled(FALSE))) return false;
    EventRegistrationToken token{};
    const auto weak = weak_from_this();
    if (FAILED(webview->add_NavigationStarting(Callback<ICoreWebView2NavigationStartingEventHandler>(
      [weak](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
        auto self = weak.lock(); LPWSTR uri = nullptr; args->get_Uri(&uri);
        BOOL user = FALSE, redirected = FALSE;
        args->get_IsUserInitiated(&user); args->get_IsRedirected(&redirected);
        const bool allowed = self && !self->closed && uri && Rsi(uri) &&
          self->scan.NavigationStarting(uri, user != FALSE, redirected != FALSE);
        CoTaskMemFree(uri);
        if (!allowed && self) self->scan.Invalidate();
        if (!allowed) { args->put_Cancel(TRUE); return S_OK; }
        self->ready = false;
        ++self->generation; args->get_NavigationId(&self->navigation); return S_OK;
      }).Get(), &token))) return false;
    if (FAILED(webview->add_NavigationCompleted(Callback<ICoreWebView2NavigationCompletedEventHandler>(
      [weak](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
        auto self = weak.lock(); if (!self || self->closed) return S_OK;
        UINT64 id = 0; BOOL success = FALSE; args->get_NavigationId(&id); args->get_IsSuccess(&success);
        if (id == self->navigation) { self->ready = success != FALSE; if (!success) self->scan.Invalidate(); } return S_OK;
      }).Get(), &token))) return false;
    if (FAILED(webview->add_NewWindowRequested(Callback<ICoreWebView2NewWindowRequestedEventHandler>(
      [](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT { return args->put_Handled(TRUE); }).Get(), &token)) ||
        FAILED(webview->add_PermissionRequested(Callback<ICoreWebView2PermissionRequestedEventHandler>(
      [](ICoreWebView2*, ICoreWebView2PermissionRequestedEventArgs* args) -> HRESULT { return args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY); }).Get(), &token))) return false;
    ComPtr<ICoreWebView2_4> downloads;
    if (FAILED(webview.As(&downloads)) || FAILED(downloads->add_DownloadStarting(Callback<ICoreWebView2DownloadStartingEventHandler>(
      [](ICoreWebView2*, ICoreWebView2DownloadStartingEventArgs* args) -> HRESULT { return args->put_Cancel(TRUE); }).Get(), &token))) return false;
    if (FAILED(controller->add_MoveFocusRequested(Callback<ICoreWebView2MoveFocusRequestedEventHandler>(
      [weak](ICoreWebView2Controller*, ICoreWebView2MoveFocusRequestedEventArgs* args) -> HRESULT {
        auto self = weak.lock(); if (!self || self->closed) return S_OK;
        COREWEBVIEW2_MOVE_FOCUS_REASON reason{}; args->get_Reason(&reason);
        SetFocus(self->parent);
        if (self->leave_focus) self->leave_focus(reason == COREWEBVIEW2_MOVE_FOCUS_REASON_PREVIOUS);
        return args->put_Handled(TRUE);
      }).Get(), &token))) return false;
    if (FAILED(controller->add_AcceleratorKeyPressed(Callback<ICoreWebView2AcceleratorKeyPressedEventHandler>(
      [weak](ICoreWebView2Controller*, ICoreWebView2AcceleratorKeyPressedEventArgs* args) -> HRESULT {
        auto self = weak.lock();
        if (self && self->scan.Active()) return args->put_Handled(TRUE);
        return S_OK;
      }).Get(), &token))) return false;
    controller->put_IsVisible(FALSE);
    return true;
  }
  void Open(std::shared_ptr<Result> result) {
    // A dedicated child host can be disabled without hiding the scan or locking Flutter's Cancel/Exit.
    viewport = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_CLIPCHILDREN,
      0, 0, 0, 0, parent, nullptr, GetModuleHandle(nullptr), nullptr);
    if (!viewport) { result->Error("runtime"); return; }
    PWSTR local = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) { result->Error("runtime"); return; }
    const auto folder = std::filesystem::path(local) / L"StarBridge" / L"HangarReader";
    CoTaskMemFree(local);
    std::error_code directory_error; std::filesystem::create_directories(folder, directory_error);
    if (directory_error) { result->Error("runtime"); return; }
    const auto weak = weak_from_this();
    const auto hr = CreateCoreWebView2EnvironmentWithOptions(nullptr, folder.c_str(), nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([weak, result](HRESULT status, ICoreWebView2Environment* environment) -> HRESULT {
        auto self = weak.lock(); if (!self || self->closed) { result->Error("closed"); return S_OK; }
        ComPtr<ICoreWebView2Environment10> env;
        ComPtr<ICoreWebView2ControllerOptions> options;
        if (FAILED(status) || !environment || FAILED(environment->QueryInterface(IID_PPV_ARGS(&env))) ||
            FAILED(env->CreateCoreWebView2ControllerOptions(&options)) || FAILED(ConfigureHangarProfile(options.Get(), self->profile_key)))
        { result->Error("runtime"); return S_OK; }
        const auto created = env->CreateCoreWebView2ControllerWithOptions(self->viewport, options.Get(),
          Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>([weak, result](HRESULT status2, ICoreWebView2Controller* controller) -> HRESULT {
            auto current = weak.lock();
            if (!current || current->closed) { if (controller) controller->Close(); result->Error("closed"); return S_OK; }
            if (FAILED(status2) || !controller) { result->Error("runtime"); return S_OK; }
            current->controller = controller;
            if (!current->Configure()) { current->Close(); result->Error("runtime"); return S_OK; }
            if (FAILED(current->webview->Navigate(L"https://robertsspaceindustries.com/en/account/pledges?page=1")))
            { current->Close(); result->Error("navigation"); return S_OK; }
            result->Success(Value(current->id)); return S_OK;
          }).Get());
        if (FAILED(created)) result->Error("runtime"); return S_OK;
      }).Get());
    if (FAILED(hr)) result->Error("runtime");
  }
  void Capture(std::shared_ptr<Result> result, bool initial = false) {
    if (!scan.Valid()) { result->Error("pageChanged"); return; }
    if (!ready || reading) { result->Error("loading"); return; }
    const auto source = Source();
    if (!HangarPage(source)) { result->Error("loginRequired"); return; }
    const auto document = generation; const auto scan_id = scan.Id(); reading = true;
    const auto weak = weak_from_this();
    const auto script = std::wstring(L"(() => {") + kHangarIdentityScript + kHangarPageScript + kHangarCaptureScript +
      L";return readRsiHangarCapture(document, location.href, " +
      (initial ? L"true" : L"false") + L");})()";
    const auto hr = webview->ExecuteScript(script.c_str(), Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
      [weak, result, document, source, scan_id](HRESULT status, LPCWSTR json) -> HRESULT {
        auto self = weak.lock(); if (!self || self->closed) { result->Error("closed"); return S_OK; }
        self->reading = false;
        if (FAILED(status) || !self->scan.Valid() || self->scan.Id() != scan_id ||
            document != self->generation || !self->ready || source != self->Source())
        { result->Error("pageChanged"); return S_OK; }
        auto body = Utf8(json); if (body.empty()) { result->Error("read"); return S_OK; }
        result->Success(Value(Map{{Value("source"), Value(Utf8(source.c_str()))},
          {Value("scanId"), Value(scan_id)}, {Value("locked"), Value(true)},
          {Value("documentGeneration"), Value(static_cast<int64_t>(document))}, {Value("json"), Value(body)}})); return S_OK;
      }).Get());
    if (FAILED(hr)) { reading = false; result->Error("read"); }
  }
};
#endif
}

class HangarBrowserBridge::Impl {
 public:
  Impl(HWND parent, flutter::BinaryMessenger* messenger) : parent_(parent), channel_(messenger,
      "starbridge/hangar-browser", &flutter::StandardMethodCodec::GetInstance()) {
    channel_.SetMethodCallHandler([this](const auto& call, auto result) { Handle(call, std::move(result)); });
  }
  ~Impl() { channel_.SetMethodCallHandler(nullptr);
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    if (browser_) browser_->Close();
#endif
  }
 private:
  void Handle(const flutter::MethodCall<Value>& call, std::unique_ptr<Result> result) {
    const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    if (!args) { result->Error("arguments"); return; }
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    if (call.method_name() == "open") {
      const auto profile = args->find(Value("profileKey"));
      const auto key = profile == args->end() ? nullptr : std::get_if<std::string>(&profile->second);
      if (!key || !IsHangarProfileKey(*key))
      { result->Error("accountChanged"); return; }
      if (browser_) browser_->Close();
      browser_ = std::make_shared<Browser>(parent_, ++last_id_, *key);
      const auto view_id = browser_->id;
      browser_->leave_focus = [this, view_id](bool previous) {
        channel_.InvokeMethod("leaveFocus", std::make_unique<Value>(Map{
          {Value("viewId"), Value(view_id)}, {Value("previous"), Value(previous)}}));
      };
      browser_->Open(std::move(result)); return;
    }
    const auto id = Integer(*args, "viewId");
    if (!browser_ || browser_->id != id || browser_->closed) { result->Error("closed"); return; }
    if (call.method_name() == "close") { browser_->Close(); browser_.reset(); result->Success(); return; }
    if (!browser_->controller) { result->Error("loading"); return; }
    if (call.method_name() == "bounds") {
      const auto x = Number(*args, "x"), y = Number(*args, "y"), w = Number(*args, "width"), h = Number(*args, "height");
      if (!std::isfinite(x+y+w+h) || x < 0 || y < 0 || w < 0 || h < 0 || x+w > 50000 || y+h > 50000)
      { result->Error("arguments"); return; }
      RECT client{}; GetClientRect(parent_, &client);
      RECT rect{static_cast<LONG>(x), static_cast<LONG>(y), static_cast<LONG>(x+w), static_cast<LONG>(y+h)};
      rect.right = std::min(rect.right, client.right); rect.bottom = std::min(rect.bottom, client.bottom);
      auto visible = args->find(Value("visible"));
      const bool show = visible != args->end() && std::get_if<bool>(&visible->second) && std::get<bool>(visible->second) && w > 0 && h > 0;
      MoveWindow(browser_->viewport, rect.left, rect.top, std::max(0L, rect.right-rect.left), std::max(0L, rect.bottom-rect.top), TRUE);
      RECT child{0, 0, std::max(0L, rect.right-rect.left), std::max(0L, rect.bottom-rect.top)};
      browser_->controller->put_Bounds(child); browser_->controller->put_IsVisible(show);
      ShowWindow(browser_->viewport, show ? SW_SHOWNOACTIVATE : SW_HIDE);
      browser_->controller->NotifyParentWindowPositionChanged(); result->Success(); return;
    }
    if (call.method_name() == "lock") {
      if (browser_->scan.Active()) { result->Error("pageChanged"); return; }
      if (!browser_->ready || browser_->reading) { result->Error("loading"); return; }
      if (!HangarPage(browser_->Source())) { result->Error("loginRequired"); return; }
      GUID guid{}; wchar_t text[40]{};
      if (FAILED(CoCreateGuid(&guid)) || !StringFromGUID2(guid, text, 40)) { result->Error("runtime"); return; }
      std::string nonce; for (wchar_t c : text) if ((c >= L'0' && c <= L'9') || (c >= L'a' && c <= L'f') || (c >= L'A' && c <= L'F')) nonce.push_back(static_cast<char>(c));
      if (!browser_->scan.Begin(nonce)) { result->Error("pageChanged"); return; }
      SetHangarInteraction(browser_->viewport, parent_, true);
      browser_->Capture(std::move(result), true); return;
    }
    if (call.method_name() == "unlock") { browser_->Unlock(); result->Success(); return; }
    if (call.method_name() == "page") {
      if (!browser_->scan.Valid()) { result->Error("pageChanged"); return; }
      const auto page = Integer(*args, "page"); const int current = HangarPage(browser_->Source());
      if (!browser_->ready) { result->Error("loading"); return; }
      if (current < 1) { result->Error("loginRequired"); return; }
      if (page < 1 || page > 100 || (page != 1 && page != current + 1))
      { result->Error("navigation"); return; }
      if (page != current) {
        browser_->ready = false;
        const auto url = L"https://robertsspaceindustries.com/en/account/pledges?page=" + std::to_wstring(page);
        if (!browser_->scan.ExpectNavigation(url) || FAILED(browser_->webview->Navigate(url.c_str())))
        { browser_->scan.Invalidate(); result->Error("navigation"); return; }
      }
      result->Success(); return;
    }
    if (call.method_name() == "capture") { browser_->Capture(std::move(result)); return; }
    if (call.method_name() == "focus") {
      if (browser_->scan.Active()) { result->Error("locked"); return; }
      browser_->controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC); result->Success(); return;
    }
    result->NotImplemented();
#else
    result->Error("runtime");
#endif
  }
  HWND parent_;
  flutter::MethodChannel<Value> channel_;
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
  int64_t last_id_ = 0;
  std::shared_ptr<Browser> browser_;
#endif
};
HangarBrowserBridge::HangarBrowserBridge(HWND parent, flutter::BinaryMessenger* messenger)
  : impl_(std::make_unique<Impl>(parent, messenger)) {}
HangarBrowserBridge::~HangarBrowserBridge() = default;
