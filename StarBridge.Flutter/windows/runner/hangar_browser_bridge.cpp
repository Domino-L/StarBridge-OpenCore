#include "hangar_browser_bridge.h"
#include "hangar_scan_lock.h"
#include "hangar_browser_data.h"
#include "hangar_browser_choice.h"
#include "hangar_browser_clear.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <wrl.h>
#include <cmath>
#include <algorithm>
#include <filesystem>
#include <functional>
#include <memory>
#include <string>
#include <vector>
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
void ReplyClear(Result& result, hangar_data::ClearResult cleared) {
  switch (cleared) {
    case hangar_data::ClearResult::success: result.Success(); break;
    case hangar_data::ClearResult::unsafe_path: result.Error("clear_unsafe"); break;
    case hangar_data::ClearResult::busy: result.Error("clear_busy"); break;
    default: result.Error("clear_failed"); break;
  }
}
std::filesystem::path BrowserFolder(bool resolve_local = false) {
  PWSTR local = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) return {};
  std::filesystem::path base(local);
  CoTaskMemFree(local);
  if (resolve_local) {
    // Follow LocalAppData's configured redirection deliberately; never infer
    // trust from the spelling of its ancestors. The deletion root is checked
    // separately with OPEN_REPARSE_POINT and held until deletion completes.
    const auto handle = CreateFileW(base.c_str(), FILE_READ_ATTRIBUTES | SYNCHRONIZE,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (handle == INVALID_HANDLE_VALUE) return {};
    const bool resolved = hangar_data::FinalPath(handle, base);
    CloseHandle(handle);
    if (!resolved) return {};
  }
  return base / L"StarBridge" / L"HangarReader";
}
std::filesystem::path ChoiceFile() {
  const auto folder = BrowserFolder();
  return folder.empty() ? folder : folder.parent_path() / L"HangarReaderChoice";
}
// The handle-resolved folder that must hold the choice file.
std::filesystem::path ChoiceFolder() {
  const auto folder = BrowserFolder(true);
  return folder.empty() ? folder : folder.parent_path();
}
// Passes a clear's reply through and notes whether the data is really gone.
class ClearOutcome : public Result {
 public:
  ClearOutcome(std::unique_ptr<Result> inner, std::function<void(bool)> done)
      : inner_(std::move(inner)), done_(std::move(done)) {}
 protected:
  void SuccessInternal(const Value* value) override {
    done_(true);
    value ? inner_->Success(*value) : inner_->Success();
  }
  void ErrorInternal(const std::string& code, const std::string& message, const Value* details) override {
    done_(false);
    details ? inner_->Error(code, message, *details) : inner_->Error(code, message);
  }
  void NotImplementedInternal() override { done_(false); inner_->NotImplemented(); }
 private:
  std::unique_ptr<Result> inner_;
  std::function<void(bool)> done_;
};
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
// The Bridge owns the pending operation; the event handler only holds a weak
// reference. This keeps the environment alive without a COM callback cycle or
// a callback that can access a destroyed Bridge. All access is on the UI thread.
struct PendingClear {
  std::unique_ptr<Result> result;
  ComPtr<ICoreWebView2Environment5> environment;
  EventRegistrationToken token{};
  bool subscribed = false;
  hangar_data::ClearWait wait;
  // Once the browser process has exited (or the wait timed out): takes the
  // reply and starts deleting off the UI thread. It may release this object.
  std::function<void(std::unique_ptr<Result>)> exited;
  std::function<void()> finished;

  void Unsubscribe() {
    if (subscribed) {
      subscribed = false;
      environment->remove_BrowserProcessExited(token);
    }
    environment.Reset();
  }
  void Complete() {
    if (!wait.Finish()) return;
    // Release the event/environment before both the exit and timeout attempt.
    Unsubscribe();
    auto reply = std::move(result);
    auto next = std::move(exited);
    finished = {};
    if (next) next(std::move(reply));
    else reply->Error("clear_failed");
  }
  void Fail(const char* error) {
    if (!wait.Finish()) return;
    Unsubscribe();
    auto reply = std::move(result);
    auto done = std::move(finished);
    if (done) done();
    reply->Error(error);
  }
};

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
  bool closed = false, ready = false, reading = false, remember = false;
  bool clear_on_close = false;
  HangarScanLock scan;
  std::string profile_key;
  uint64_t generation = 0, navigation = 0;
  ComPtr<ICoreWebView2Controller> controller;
  ComPtr<ICoreWebView2> webview;
  ComPtr<ICoreWebView2Environment> browser_environment;
  std::shared_ptr<bool> opening = std::make_shared<bool>(false);
  std::function<void(bool)> leave_focus;
  explicit Browser(HWND hwnd, int64_t view_id, const std::string& key, bool keep)
      : parent(hwnd), id(view_id), remember(keep), profile_key(key) {}
  std::wstring Source() const {
    LPWSTR text = nullptr; if (!webview || FAILED(webview->get_Source(&text))) return {};
    std::wstring value = text ? text : L""; CoTaskMemFree(text); return value;
  }
  void Close() { closed = true; ready = false; ++generation;
    scan.End();
    if (webview) webview->Stop(); if (controller) controller->Close(); webview.Reset(); controller.Reset();
    browser_environment.Reset();
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
    const auto folder = BrowserFolder();
    if (folder.empty()) { result->Error("runtime"); return; }
    std::error_code directory_error; std::filesystem::create_directories(folder, directory_error);
    if (directory_error) { result->Error("runtime"); return; }
    const auto weak = weak_from_this();
    const auto pending = opening;
    *pending = true;
    const auto hr = CreateCoreWebView2EnvironmentWithOptions(nullptr, folder.c_str(), nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([weak, result, pending](HRESULT status, ICoreWebView2Environment* environment) -> HRESULT {
        auto self = weak.lock(); if (!self || self->closed) { *pending = false; result->Error("closed"); return S_OK; }
        ComPtr<ICoreWebView2Environment10> env;
        ComPtr<ICoreWebView2ControllerOptions> options;
        if (FAILED(status) || !environment || FAILED(environment->QueryInterface(IID_PPV_ARGS(&env))) ||
            FAILED(env->CreateCoreWebView2ControllerOptions(&options)) || FAILED(ConfigureHangarProfile(options.Get(), self->profile_key, self->remember)))
        { *pending = false; result->Error("runtime"); return S_OK; }
        self->browser_environment = environment;
        const auto created = env->CreateCoreWebView2ControllerWithOptions(self->viewport, options.Get(),
          Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>([weak, result, pending](HRESULT status2, ICoreWebView2Controller* controller) -> HRESULT {
            *pending = false;
            auto current = weak.lock();
            if (!current || current->closed) { if (controller) controller->Close(); result->Error("closed"); return S_OK; }
            if (FAILED(status2) || !controller) { result->Error("runtime"); return S_OK; }
            current->controller = controller;
            if (!current->Configure()) { current->Close(); result->Error("runtime"); return S_OK; }
            if (FAILED(current->webview->Navigate(L"https://robertsspaceindustries.com/en/account/pledges?page=1")))
            { current->Close(); result->Error("navigation"); return S_OK; }
            result->Success(Value(current->id)); return S_OK;
          }).Get());
        if (FAILED(created)) { *pending = false; result->Error("runtime"); } return S_OK;
      }).Get());
    if (FAILED(hr)) { *pending = false; result->Error("runtime"); }
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
    const auto choice = hangar_choice::ReadChoice(ChoiceFile(), ChoiceFolder());
    remember_ = choice == hangar_choice::Choice::remember;
    choice_known_ = choice != hangar_choice::Choice::unreadable;
    // Not remembering: whatever a crash, a forced exit or an older version left
    // behind is removed at start, off the UI thread. Opening reports
    // "clear_busy" until it is done, and the reader retries.
    // A choice that could not be read is never taken as "don't remember":
    // nothing is cleared, and this run's pages stay InPrivate.
    if (choice == hangar_choice::Choice::forget) {
      const auto folder = BrowserFolder();
      const auto expected_root = BrowserFolder(true);
      if (!folder.empty() && !expected_root.empty())
        // A failed start-up clear is reported, never silently assumed done.
        // Success also lifts a warning noted while it ran: no page can open
        // during it, so it removed everything a skipped clear left.
        clear_.Start(folder, expected_root, [this](hangar_data::ClearResult cleared) {
          uncleared_ = cleared != hangar_data::ClearResult::success;
        });
    }
  }
  ~Impl() { channel_.SetMethodCallHandler(nullptr);
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    const auto pending = std::move(clearing_);
    if (pending) pending->Fail("clear_failed");
    if (browser_) browser_->Close();
#endif
  }
 private:
  // Deletes the reader's folder through the verified, link-refusing path on a
  // worker thread, and replies on the UI thread once it is done.
  void Delete(const std::filesystem::path& folder, const std::filesystem::path& expected_root,
              std::unique_ptr<Result> reply) {
    std::shared_ptr<Result> result(std::move(reply));
    if (!clear_.Start(folder, expected_root,
            [result](hangar_data::ClearResult cleared) { ReplyClear(*result, cleared); }))
      result->Error("clear_busy");
  }
  // Closes any browser, waits for its process to exit, then deletes the
  // reader's folder. Neither the wait nor the deletion blocks the UI thread.
  void Clear(std::unique_ptr<Result> reply) {
    auto result = std::make_unique<ClearOutcome>(std::move(reply),
        [this](bool cleared) { uncleared_ = !cleared; });
    // One clear at a time: the start-up clear or an earlier one is still deleting.
    if (clear_.Busy()) { result->Error("clear_busy"); return; }
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
      if (clearing_ && !clearing_->wait.Finished()) { result->Error("clear_busy"); return; }
      // A late environment/controller creation can recreate files after deletion.
      // Let its callback drain before allowing a clear to report success.
      for (const auto& pending : openings_) {
        if (*pending) { result->Error("clear_busy"); return; }
      }
      openings_.clear();
#endif
      const auto folder = BrowserFolder();
      const auto expected_root = BrowserFolder(true);
      if (folder.empty() || expected_root.empty()) { result->Error("clear_failed"); return; }
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
      if (browser_ && browser_->browser_environment) {
        const auto pending = std::make_shared<PendingClear>();
        if (FAILED(browser_->browser_environment.As(&pending->environment)))
        { result->Error("clear_busy"); return; }
        pending->result = std::move(result);
        pending->finished = [this] { clearing_.reset(); };
        pending->exited = [this, folder, expected_root](std::unique_ptr<Result> exited) {
          clearing_.reset();
          Delete(folder, expected_root, std::move(exited));
        };
        clearing_ = pending;
        const std::weak_ptr<PendingClear> weak = pending;
        if (!pending->wait.Start([weak] {
              if (auto current = weak.lock()) current->Complete();
            })) { pending->Fail("clear_failed"); return; }
        const auto status = pending->environment->add_BrowserProcessExited(
          Callback<ICoreWebView2BrowserProcessExitedEventHandler>(
            [weak](ICoreWebView2Environment*, ICoreWebView2BrowserProcessExitedEventArgs*) -> HRESULT {
              if (auto current = weak.lock()) current->Complete();
              return S_OK;
            }).Get(), &pending->token);
        if (FAILED(status)) { pending->Fail("clear_busy"); return; }
        pending->subscribed = true;
        // Subscribe before Close. The UI timer also covers an exit that already
        // occurred before subscription; either path claims the same one-shot gate.
        browser_->Close(); browser_.reset();
        return;
      }
      if (browser_) { browser_->Close(); browser_.reset(); }
#endif
      Delete(folder, expected_root, std::move(result));
  }
  void Handle(const flutter::MethodCall<Value>& call, std::unique_ptr<Result> result) {
    const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    if (!args) { result->Error("arguments"); return; }
    if (call.method_name() == "clearData") { Clear(std::move(result)); return; }
    if (call.method_name() == "readChoice") {
      // uncleared: a clear did not finish, so sign-in data may remain.
      // unknown: the saved choice could not be read, so nothing is cleared.
      result->Success(Value(Map{{Value("remember"), Value(remember_)},
          {Value("uncleared"), Value(uncleared_)}, {Value("unknown"), Value(!choice_known_)}}));
      return;
    }
    if (call.method_name() == "setChoice") {
      const auto value = args->find(Value("remember"));
      const auto keep = value == args->end() ? nullptr : std::get_if<bool>(&value->second);
      if (!keep) { result->Error("arguments"); return; }
      // On failure nothing changes: the open page stays open and closable.
      if (!hangar_choice::WriteRemember(ChoiceFile(), ChoiceFolder(), *keep)) { result->Error("choice_failed"); return; }
      remember_ = *keep;
      choice_known_ = true;
      // Either way the open page belongs to the old choice. Not remembering
      // also removes what was remembered until now.
      if (!remember_) { Clear(std::move(result)); return; }
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
      if (browser_) { browser_->Close(); browser_.reset(); }
#endif
      result->Success(); return;
    }
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    if (call.method_name() == "open") {
      // Reopening would create a new browser process and lock the folder again
      // before the pending BrowserProcessExited handler, or the deletion that
      // follows it, is done. The reader retries "clear_busy" for a while.
      if ((clearing_ && !clearing_->wait.Finished()) || clear_.Busy())
      { result->Error("clear_busy"); return; }
      const auto profile = args->find(Value("profileKey"));
      const auto key = profile == args->end() ? nullptr : std::get_if<std::string>(&profile->second);
      if (!key || !IsHangarProfileKey(*key))
      { result->Error("accountChanged"); return; }
      if (browser_) browser_->Close();
      browser_ = std::make_shared<Browser>(parent_, ++last_id_, *key, remember_);
      // An unreadable choice keeps this page InPrivate but never deletes what
      // may be a remembered sign-in.
      browser_->clear_on_close = !remember_ && choice_known_;
      openings_.erase(std::remove_if(openings_.begin(), openings_.end(),
          [](const auto& pending) { return !*pending; }), openings_.end());
      openings_.push_back(browser_->opening);
      const auto view_id = browser_->id;
      browser_->leave_focus = [this, view_id](bool previous) {
        channel_.InvokeMethod("leaveFocus", std::make_unique<Value>(Map{
          {Value("viewId"), Value(view_id)}, {Value("previous"), Value(previous)}}));
      };
      browser_->Open(std::move(result)); return;
    }
    const auto id = Integer(*args, "viewId");
    if (!browser_ || browser_->id != id || browser_->closed) { result->Error("closed"); return; }
    if (call.method_name() == "close") {
      // Not remembering: closing the reader also removes its sign-in data.
      if (browser_->clear_on_close) {
        // A clear already under way, or a view still being created, is left to
        // finish; the next start removes anything that survives.
        bool busy = (clearing_ && !clearing_->wait.Finished()) || clear_.Busy();
        for (const auto& pending : openings_) busy = busy || *pending;
        if (!busy) { Clear(std::move(result)); return; }
        // Not cleared now: reported until a later clear succeeds.
        uncleared_ = true;
      }
      browser_->Close(); browser_.reset(); result->Success(); return;
    }
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
  bool remember_ = false;
  // False while the saved choice could not be read: nothing is cleared then.
  bool choice_known_ = true;
  bool uncleared_ = false;
  // Deletes off the UI thread; at most one deletion runs at a time.
  hangar_data::BackgroundClear clear_;
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
  int64_t last_id_ = 0;
  std::shared_ptr<Browser> browser_;
  std::vector<std::shared_ptr<bool>> openings_;
  std::shared_ptr<PendingClear> clearing_;
#endif
};
HangarBrowserBridge::HangarBrowserBridge(HWND parent, flutter::BinaryMessenger* messenger)
  : impl_(std::make_unique<Impl>(parent, messenger)) {}
HangarBrowserBridge::~HangarBrowserBridge() = default;
