#include "menu_local_tools.h"
#include <dwmapi.h>
#include <gdiplus.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <filesystem>
#include <vector>
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
#include <WebView2.h>
#endif

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Microsoft::WRL::ComPtr;
constexpr size_t kMaxBytes = 32 * 1024 * 1024;
const Value* Field(const Map& m, const char* k) {
  const auto i = m.find(Value(k)); return i == m.end() ? nullptr : &i->second;
}
std::string Text(const Map& m, const char* k) {
  const auto* v = Field(m, k); const auto* s = v ? std::get_if<std::string>(v) : nullptr;
  return s && s->size() <= 4096 ? *s : "";
}
bool Flag(const Map& m, const char* k) {
  const auto* v = Field(m, k); const auto* b = v ? std::get_if<bool>(v) : nullptr; return b && *b;
}
double Number(const Map& m, const char* k) {
  const auto* v = Field(m, k);
  if (v) {
    if (const auto* n = std::get_if<double>(v)) return std::isfinite(*n) ? *n : 0;
    if (const auto* n = std::get_if<int32_t>(v)) return *n;
  }
  return 0;
}
std::wstring Wide(const std::string& s) {
  const auto count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring result(count, 0);
  if (count) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(), static_cast<int>(s.size()), result.data(), count);
  return result;
}
std::string Utf8(const wchar_t* value) {
  if (!value) return {};
  const auto size = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1 || size > 16385) return {};
  std::string result(size, 0);
  WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), size, nullptr, nullptr);
  result.pop_back(); return result;
}
bool WebUrl(const std::wstring& uri) {
  // Chromium remains the parser; restrict schemes before every navigation,
  // including redirects and window.open. Never dispatch external protocols.
  if (uri.size() > 4096 || uri.find_first_of(L"\r\n\t") != std::wstring::npos) return false;
  return uri.rfind(L"https://", 0) == 0 || uri.rfind(L"http://", 0) == 0 || uri == L"about:blank";
}
ComPtr<IStream> Stream(const std::vector<uint8_t>& bytes) {
  ComPtr<IStream> stream;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) return nullptr;
  ULONG written = 0;
  if (!bytes.empty() && (FAILED(stream->Write(bytes.data(), static_cast<ULONG>(bytes.size()), &written)) || written != bytes.size())) return nullptr;
  LARGE_INTEGER zero{}; stream->Seek(zero, STREAM_SEEK_SET, nullptr); return stream;
}
std::vector<uint8_t> Png(Gdiplus::Image& image) {
  if (image.GetLastStatus() != Gdiplus::Ok || image.GetWidth() == 0 || image.GetHeight() == 0 ||
      image.GetWidth() > 16384 || image.GetHeight() > 16384 ||
      static_cast<uint64_t>(image.GetWidth()) * image.GetHeight() > 64000000) return {};
  UINT count = 0, size = 0; Gdiplus::GetImageEncodersSize(&count, &size);
  if (!size) return {};
  std::vector<uint8_t> info(size);
  auto* codecs = reinterpret_cast<Gdiplus::ImageCodecInfo*>(info.data());
  if (Gdiplus::GetImageEncoders(count, size, codecs) != Gdiplus::Ok) return {};
  CLSID codec{}; bool found = false;
  for (UINT i = 0; i < count; ++i) if (wcscmp(codecs[i].MimeType, L"image/png") == 0) { codec = codecs[i].Clsid; found = true; break; }
  auto stream = Stream({}); if (!found || !stream || image.Save(stream.Get(), &codec) != Gdiplus::Ok) return {};
  STATSTG stat{}; if (FAILED(stream->Stat(&stat, STATFLAG_NONAME)) || stat.cbSize.QuadPart > kMaxBytes) return {};
  std::vector<uint8_t> bytes(static_cast<size_t>(stat.cbSize.QuadPart));
  LARGE_INTEGER zero{}; stream->Seek(zero, STREAM_SEEK_SET, nullptr);
  ULONG read = 0; if (FAILED(stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &read)) || read != bytes.size()) return {};
  return bytes;
}
std::vector<uint8_t> PickImage(HWND owner, bool& cancelled) {
  cancelled = false;
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) return {};
  const COMDLG_FILTERSPEC filters[] = {{L"图片 (PNG, JPEG, BMP)", L"*.png;*.jpg;*.jpeg;*.bmp"}};
  dialog->SetFileTypes(1, filters);
  dialog->SetOptions(FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST | FOS_FORCEFILESYSTEM | FOS_NOCHANGEDIR | FOS_DONTADDTORECENT);
  const HRESULT shown = dialog->Show(owner);
  if (FAILED(shown)) { cancelled = shown == HRESULT_FROM_WIN32(ERROR_CANCELLED); return {}; }
  ComPtr<IShellItem> item; PWSTR path = nullptr;
  if (FAILED(dialog->GetResult(&item)) || FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) return {};
  // Open only the file selected by this dialog; never accept a path from Dart.
  HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  CoTaskMemFree(path); if (file == INVALID_HANDLE_VALUE) return {};
  LARGE_INTEGER length{}; std::vector<uint8_t> bytes;
  if (GetFileSizeEx(file, &length) && length.QuadPart > 0 && length.QuadPart <= kMaxBytes) {
    bytes.resize(static_cast<size_t>(length.QuadPart)); DWORD read = 0;
    if (!ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr) || read != bytes.size()) bytes.clear();
  }
  CloseHandle(file); auto stream = Stream(bytes); if (!stream || bytes.empty()) return {};
  Gdiplus::Bitmap bitmap(stream.Get()); return Png(bitmap);
}
std::vector<uint8_t> Capture(HWND owner) {
  MONITORINFO info{sizeof(info)};
  if (!GetMonitorInfoW(MonitorFromWindow(owner, MONITOR_DEFAULTTONEAREST), &info)) return {};
  const int width = info.rcMonitor.right - info.rcMonitor.left, height = info.rcMonitor.bottom - info.rcMonitor.top;
  HDC screen = GetDC(nullptr), memory = CreateCompatibleDC(screen);
  HBITMAP bitmap = CreateCompatibleBitmap(screen, width, height);
  if (!memory || !bitmap) { if (memory) DeleteDC(memory); if (bitmap) DeleteObject(bitmap); ReleaseDC(nullptr, screen); return {}; }
  const auto previous = SelectObject(memory, bitmap);
  const BOOL ok = BitBlt(memory, 0, 0, width, height, screen, info.rcMonitor.left, info.rcMonitor.top, SRCCOPY | CAPTUREBLT);
  SelectObject(memory, previous); DeleteDC(memory); ReleaseDC(nullptr, screen);
  std::vector<uint8_t> bytes;
  if (ok) { Gdiplus::Bitmap image(bitmap, nullptr); bytes = Png(image); }
  DeleteObject(bitmap); return bytes;
}
bool SaveImage(HWND owner, const std::vector<uint8_t>& bytes) {
  if (bytes.empty()) return false;
  ComPtr<IFileSaveDialog> dialog;
  if (FAILED(CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) return false;
  const COMDLG_FILTERSPEC filters[] = {{L"PNG 图片", L"*.png"}};
  dialog->SetFileTypes(1, filters); dialog->SetDefaultExtension(L"png"); dialog->SetFileName(L"StarBridge-screenshot.png");
  dialog->SetOptions(FOS_OVERWRITEPROMPT | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR | FOS_DONTADDTORECENT);
  if (FAILED(dialog->Show(owner))) return false;
  ComPtr<IShellItem> item; PWSTR path = nullptr;
  if (FAILED(dialog->GetResult(&item)) || FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) return false;
  HANDLE file = CreateFileW(path, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  CoTaskMemFree(path); if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0; const bool ok = WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr) && written == bytes.size();
  CloseHandle(file); return ok;
}
}

class MenuLocalTools::Impl {
 public:
  Impl(HWND owner, std::function<bool()> current, std::function<void(bool)> modal, std::function<void()> dismiss)
    : owner_(owner), current_(std::move(current)), modal_(std::move(modal)), dismiss_(std::move(dismiss)), alive_(std::make_shared<std::atomic_bool>(true)) {
    Gdiplus::GdiplusStartupInput input; Gdiplus::GdiplusStartup(&gdiplus_, &input, nullptr);
  }
  ~Impl() { *alive_ = false; Reset();
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    environment_.Reset();
#endif
    if (gdiplus_) Gdiplus::GdiplusShutdown(gdiplus_);
  }
  void Hide() {
    browser_visible_ = false;
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    SyncBrowser();
#endif
  }
  void Reset() {
    Hide();
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    for (const auto& tab : tabs_) CloseController(tab);
    tabs_.clear(); active_tab_.clear();
    if (viewport_) { DestroyWindow(viewport_); viewport_ = nullptr; }
#endif
    screenshot_.clear();
  }
  void Handle(const Map& args, MenuLocalTools::Result result) {
    const auto action = Text(args, "action");
    if (!current_()) { result->Error("menu.closed", "Menu is closed"); return; }
    if (action == "image" || action == "capture" || action == "save") {
      modal_(true); Hide();
      if (action == "save") {
        const bool saved = SaveImage(owner_, screenshot_); modal_(false); result->Success(Value(saved)); return;
      }
      std::vector<uint8_t> bytes;
      bool cancelled = false;
      if (action == "capture") {
        // Only this overlay is hidden; no keys injected and no desktop raised.
        ShowWindow(owner_, SW_HIDE); DwmFlush(); bytes = Capture(owner_);
        if (current_()) ShowWindow(owner_, SW_SHOWNOACTIVATE);
      } else bytes = PickImage(owner_, cancelled);
      modal_(false);
      if (!current_()) { result->Error("menu.closed", "Menu was dismissed"); return; }
      if (bytes.empty()) {
        if (cancelled) result->Success(); else result->Error("menu.image_failed", "Image could not be read");
      } else {
        if (action == "capture") screenshot_ = bytes;
        result->Success(Value(bytes));
      }
      return;
    }
    if (action == "browserBounds") {
      RECT parent{}; GetClientRect(owner_, &parent);
      const double x = Number(args,"x"), y = Number(args,"y"), w = Number(args,"width"), h = Number(args,"height");
      // The child is clipped by its parent HWND; crossing an edge must not
      // blank the entire browser. Still reject unbounded/malformed geometry.
      const bool valid = std::isfinite(x) && std::isfinite(y) && std::isfinite(w) && std::isfinite(h) &&
          std::abs(x) <= 1000000 && std::abs(y) <= 1000000 && w >= 1 && h >= 1 && w <= 1000000 && h <= 1000000;
      browser_visible_ = Flag(args,"visible") && valid && x < parent.right && y < parent.bottom && x+w > 0 && y+h > 0;
      if (valid) bounds_ = RECT{static_cast<LONG>(x), static_cast<LONG>(y), static_cast<LONG>(x+w), static_cast<LONG>(y+h)};
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
      SyncBrowser();
#endif
      result->Success(); return;
    }
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
#ifdef STARBRIDGE_MENU_BROWSER_TEST
    if (action == "browserTestVisualState") {
      flutter::EncodableList visual;
      for (const auto& tab : tabs_) {
        RECT bounds{}; BOOL visible = FALSE, suspended = FALSE;
        if (tab->controller) { tab->controller->get_Bounds(&bounds); tab->controller->get_IsVisible(&visible); }
        ComPtr<ICoreWebView2_3> suspension;
        if (tab->browser && SUCCEEDED(tab->browser.As(&suspension))) suspension->get_IsSuspended(&suspended);
        visual.emplace_back(Map{{Value("id"), Value(tab->id)}, {Value("visible"), Value(visible != FALSE)},
          {Value("suspended"), Value(suspended != FALSE)}, {Value("left"), Value(static_cast<int32_t>(bounds.left))},
          {Value("top"), Value(static_cast<int32_t>(bounds.top))}, {Value("right"), Value(static_cast<int32_t>(bounds.right))}, {Value("bottom"), Value(static_cast<int32_t>(bounds.bottom))}});
      }
      flutter::EncodableList children;
      for (HWND child = GetWindow(owner_, GW_CHILD); child; child = GetWindow(child, GW_HWNDNEXT)) {
        wchar_t name[256]{}; GetClassNameW(child, name, 256);
        RECT bounds{}; GetWindowRect(child, &bounds);
        MapWindowPoints(nullptr, owner_, reinterpret_cast<POINT*>(&bounds), 2);
        children.emplace_back(Map{{Value("class"), Value(Utf8(name))},
          {Value("browserViewport"), Value(child == viewport_)},
          {Value("visibleStyle"), Value((GetWindowLongPtrW(child, GWL_STYLE) & WS_VISIBLE) != 0)},
          {Value("left"), Value(static_cast<int32_t>(bounds.left))}, {Value("top"), Value(static_cast<int32_t>(bounds.top))},
          {Value("right"), Value(static_cast<int32_t>(bounds.right))}, {Value("bottom"), Value(static_cast<int32_t>(bounds.bottom))}});
      }
      result->Success(Value(Map{{Value("requestedVisible"), Value(browser_visible_)},
        {Value("controllers"), Value(visual)}, {Value("children"), Value(children)}})); return;
    }
    // Exercise NavigationStarting itself, rather than only command validation.
    // The fixture can request one fixed inert URL; no script or arbitrary URI.
    if (action == "browserTestRejectedNavigation") {
      const auto tab = FindTab(active_tab_);
      if (tab && tab->browser) {
        tab->browser->Navigate(L"data:text/plain,blocked"); result->Success();
      } else result->Error("menu.browser_unavailable", "Browser not ready");
      return;
    }
#endif
    if (action == "browserOpen") {
      if (tabs_.empty()) NewTab(L"about:blank");
      SyncBrowser(); result->Success(); return;
    }
    if (action == "browserNewTab") {
      if (tabs_.size() >= kTabLimit) { result->Error("menu.browser_tab_limit", "Tab limit reached"); return; }
      NewTab(L"about:blank"); result->Success(); return;
    }
    if (action == "browserSelectTab" || action == "browserCloseTab") {
      const auto tab = FindTab(Text(args, "tabId"));
      if (!tab) { result->Error("menu.browser_tab_stale", "Tab no longer exists"); return; }
      if (action == "browserSelectTab") active_tab_ = tab->id;
      else {
        const auto index = static_cast<size_t>(std::find(tabs_.begin(), tabs_.end(), tab) - tabs_.begin());
        const bool active = active_tab_ == tab->id;
        CloseController(tab); tabs_.erase(tabs_.begin() + index);
        if (tabs_.empty()) NewTab(L"about:blank");
        else if (active) active_tab_ = tabs_[std::min(index, tabs_.size() - 1)]->id;
      }
      SyncBrowser(); result->Success(); return;
    }
    if (action == "browserState") {
      const auto active = FindTab(active_tab_);
      if (!active) { result->Error("menu.browser_unavailable", "Browser not ready"); return; }
      SyncBrowser();
      flutter::EncodableList entries;
      for (const auto& tab : tabs_) entries.emplace_back(TabState(tab));
      auto state = TabState(active);
      state.emplace(Value("tabs"), Value(entries));
      state.emplace(Value("activeTabId"), Value(active_tab_));
      state.emplace(Value("tabLimit"), Value(static_cast<int32_t>(kTabLimit)));
      result->Success(Value(state)); return;
    }
    if (action == "browserNavigate" || action == "browserBack" || action == "browserForward" || action == "browserReload" || action == "browserStop" || action == "browserFocus") {
      const auto tab = FindTab(Text(args, "tabId"));
      if (!tab || tab->id != active_tab_) { result->Error("menu.browser_tab_stale", "Active tab changed"); return; }
      if (action == "browserReload" && (!tab->browser || tab->broken) && !tab->opening) {
        if (tab->broken) CloseController(tab);
        StartTab(tab); result->Success(); return;
      }
      if (!tab->browser || !tab->controller || tab->broken) { result->Error("menu.browser_unavailable", "Browser not ready"); return; }
      HRESULT hr = E_INVALIDARG;
      if (action == "browserNavigate") { const auto url = Wide(Text(args,"url")); if (WebUrl(url)) hr = tab->browser->Navigate(url.c_str()); }
      if (action == "browserBack") hr = tab->browser->GoBack();
      if (action == "browserForward") hr = tab->browser->GoForward();
      if (action == "browserReload") hr = tab->browser->Reload();
      if (action == "browserStop") {
        hr = tab->browser->Stop();
        if (SUCCEEDED(hr)) { tab->stopped_navigation = tab->navigation; tab->navigating = false; tab->failed = false; }
      }
      if (action == "browserFocus" && browser_visible_) hr = tab->controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
      if (FAILED(hr)) result->Error("menu.browser_failed", "Browser action failed"); else result->Success();
      return;
    }
#endif
    result->Error("menu.tool_unavailable", "Tool unavailable");
  }
 private:
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
  // Match the existing WPF default; tab identities and controller ownership
  // remain native. Neither URLs nor the open-page collection are persisted.
  static constexpr size_t kTabLimit = 8;
  struct BrowserTab {
    std::string id;
    std::wstring resume_url;
    ComPtr<ICoreWebView2Controller> controller;
    ComPtr<ICoreWebView2> browser;
    bool opening = false, navigating = false, failed = false, broken = false;
    bool suspend_pending = false;
    uint64_t attempt = 0, navigation = 0, stopped_navigation = 0;
#ifdef STARBRIDGE_MENU_BROWSER_TEST
    int32_t rejected_navigation_count = 0;
#endif
  };
  std::shared_ptr<BrowserTab> FindTab(const std::string& id) const {
    const auto found = std::find_if(tabs_.begin(), tabs_.end(), [&id](const auto& tab) { return tab->id == id; });
    return found == tabs_.end() ? nullptr : *found;
  }
  bool Current(const std::shared_ptr<BrowserTab>& tab, uint64_t attempt) const {
    return tab && FindTab(tab->id) == tab && tab->attempt == attempt;
  }
  bool Visible(const std::shared_ptr<BrowserTab>& tab) const {
    return !tab->broken && tab->id == active_tab_ && browser_visible_ && current_();
  }
  static void RecordRejectedNavigation(const std::shared_ptr<BrowserTab>& tab) {
#ifdef STARBRIDGE_MENU_BROWSER_TEST
    ++tab->rejected_navigation_count;
#else
    (void)tab;
#endif
  }
  static void CloseController(const std::shared_ptr<BrowserTab>& tab) {
    ++tab->attempt;
    tab->opening = false; tab->suspend_pending = false;
    if (tab->controller) { tab->controller->put_IsVisible(FALSE); tab->controller->Close(); }
    tab->browser.Reset(); tab->controller.Reset();
  }
  Map TabState(const std::shared_ptr<BrowserTab>& tab) const {
    PWSTR source = nullptr, title = nullptr; BOOL back = FALSE, forward = FALSE;
    if (tab->browser) {
      tab->browser->get_Source(&source); tab->browser->get_DocumentTitle(&title);
      tab->browser->get_CanGoBack(&back); tab->browser->get_CanGoForward(&forward);
    }
    const auto url = source ? Utf8(source) : Utf8(tab->resume_url.c_str());
    if (source && WebUrl(source)) tab->resume_url = source;
    auto caption = Utf8(title);
    if (caption.size() > 1024) caption.clear();
    CoTaskMemFree(source); CoTaskMemFree(title);
    Map state{{Value("id"), Value(tab->id)}, {Value("title"), Value(caption)},
      {Value("url"), Value(url)}, {Value("back"), Value(back != FALSE)},
      {Value("forward"), Value(forward != FALSE)},
      {Value("loading"), Value(tab->opening || tab->navigating)}, {Value("failed"), Value(tab->failed)},
      {Value("unavailable"), Value(tab->failed && (!tab->browser || tab->broken))}};
#ifdef STARBRIDGE_MENU_BROWSER_TEST
    state.emplace(Value("rejectedNavigationCount"), Value(tab->rejected_navigation_count));
#endif
    return state;
  }
  void SyncBrowser() {
    const auto active = FindTab(active_tab_);
    const bool show = active && active->controller && Visible(active);
    const LONG width = std::max(0L, bounds_.right - bounds_.left);
    const LONG height = std::max(0L, bounds_.bottom - bounds_.top);
    if (viewport_) {
      // Reuse the hangar reader's bounded child viewport pattern. Only our
      // explicit child is raised: Flutter chrome and other panels keep their
      // own ordering, and the browser cannot cover outside its content rect.
      if (show) SetWindowPos(viewport_, HWND_TOP, bounds_.left, bounds_.top, width, height,
          SWP_NOACTIVATE | SWP_SHOWWINDOW);
      else ShowWindow(viewport_, SW_HIDE);
    }
    const RECT child_bounds{0, 0, width, height};
    for (const auto& tab : tabs_) {
      if (!tab->controller) continue;
      const bool visible = Visible(tab);
      tab->controller->put_Bounds(child_bounds);
      tab->controller->put_IsVisible(visible ? TRUE : FALSE);
      tab->controller->NotifyParentWindowPositionChanged();
      ComPtr<ICoreWebView2_3> suspension;
      if (!tab->browser || FAILED(tab->browser.As(&suspension))) continue;
      if (visible) { suspension->Resume(); continue; }
      if (tab->suspend_pending) continue;
      BOOL suspended = FALSE; suspension->get_IsSuspended(&suspended);
      if (suspended) continue;
      tab->suspend_pending = true;
      const auto life = alive_; const auto attempt = tab->attempt;
      const std::weak_ptr<BrowserTab> weak = tab;
      const HRESULT hr = suspension->TrySuspend(Microsoft::WRL::Callback<ICoreWebView2TrySuspendCompletedHandler>(
        [this, life, weak, attempt](HRESULT, BOOL) -> HRESULT {
          if (!*life) return S_OK;
          const auto live = weak.lock();
          if (!Current(live, attempt)) return S_OK;
          live->suspend_pending = false;
          // A tab can become active while TrySuspend is outstanding. Resume
          // after completion too, so a late suspension cannot freeze it.
          ComPtr<ICoreWebView2_3> resume;
          if (Visible(live) && SUCCEEDED(live->browser.As(&resume))) resume->Resume();
          return S_OK;
        }).Get());
      if (FAILED(hr)) tab->suspend_pending = false;
    }
  }
  void NewTab(const std::wstring& url) {
    if (tabs_.size() >= kTabLimit) return;
    auto tab = std::make_shared<BrowserTab>();
    tab->id = "t" + std::to_string(++next_tab_); tab->resume_url = url;
    tabs_.push_back(tab); active_tab_ = tab->id;
    // Hide the old page before beginning asynchronous controller creation.
    SyncBrowser(); StartTab(tab);
  }
  void StartTab(const std::shared_ptr<BrowserTab>& tab) {
    if (tab->opening || tab->browser) return;
    tab->opening = true; tab->failed = false; tab->broken = false;
    if (environment_) { CreateController(tab); return; }
    if (environment_opening_) return;
    PWSTR local = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) { tab->opening = false; tab->failed = true; return; }
#ifdef STARBRIDGE_MENU_BROWSER_TEST
    // Hidden native fixtures use their own disposable profile, never the
    // running acceptance browser's cookies or storage.
    const std::wstring profile = std::filesystem::absolute(L".artifacts/menu-browser-native-profile").wstring();
#else
    const std::wstring profile = std::wstring(local) + L"\\StarBridge\\MenuBrowser";
#endif
    CoTaskMemFree(local);
    environment_opening_ = true;
    const auto life = alive_;
    const auto failed = [this, life]() {
      if (!*life) return;
      environment_opening_ = false;
      for (const auto& pending : tabs_) if (pending->opening && !pending->controller) {
        pending->opening = false; pending->failed = true;
      }
    };
    const HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(nullptr, profile.c_str(), nullptr,
      Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
        [this, life, failed](HRESULT status, ICoreWebView2Environment* environment) -> HRESULT {
          if (!*life || FAILED(status) || !environment) { failed(); return S_OK; }
          environment_opening_ = false; environment_ = environment;
          for (const auto& pending : tabs_) if (pending->opening && !pending->controller) CreateController(pending);
          return S_OK;
        }).Get());
    if (FAILED(hr)) failed();
  }
  void CreateController(const std::shared_ptr<BrowserTab>& tab) {
    if (!viewport_) {
      viewport_ = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
          0, 0, 0, 0, owner_, nullptr, GetModuleHandleW(nullptr), nullptr);
      if (!viewport_) { tab->opening = false; tab->failed = true; return; }
    }
    const auto life = alive_; const auto attempt = ++tab->attempt;
    const std::weak_ptr<BrowserTab> weak = tab;
    const HRESULT hr = environment_->CreateCoreWebView2Controller(viewport_,
      Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
        [this, life, weak, attempt](HRESULT status, ICoreWebView2Controller* controller) -> HRESULT {
          const auto live = weak.lock();
          if (!*life || !Current(live, attempt)) { if (controller) controller->Close(); return S_OK; }
          live->opening = false;
          if (FAILED(status) || !controller) { live->failed = true; return S_OK; }
          live->controller = controller; controller->put_IsVisible(FALSE);
          controller->get_CoreWebView2(&live->browser);
          if (!live->browser || !ConfigureTab(live, attempt)) {
            CloseController(live); live->failed = true; return S_OK;
          }
          if (FAILED(live->browser->Navigate(live->resume_url.c_str()))) live->failed = true;
          SyncBrowser(); return S_OK;
        }).Get());
    if (FAILED(hr) && Current(tab, attempt)) { tab->opening = false; tab->failed = true; }
  }
  bool ConfigureTab(const std::shared_ptr<BrowserTab>& tab, uint64_t attempt) {
    const auto life = alive_; const std::weak_ptr<BrowserTab> weak = tab;
    ComPtr<ICoreWebView2Settings> settings;
    if (FAILED(tab->browser->get_Settings(&settings)) || !settings) return false;
    if (FAILED(settings->put_IsWebMessageEnabled(FALSE)) || FAILED(settings->put_AreHostObjectsAllowed(FALSE)) ||
        FAILED(settings->put_AreDevToolsEnabled(FALSE)) || FAILED(settings->put_IsStatusBarEnabled(FALSE)) ||
        FAILED(settings->put_AreDefaultContextMenusEnabled(FALSE))) return false;
    ComPtr<ICoreWebView2Settings4> form_settings;
    if (FAILED(settings.As(&form_settings)) || FAILED(form_settings->put_IsPasswordAutosaveEnabled(FALSE)) ||
        FAILED(form_settings->put_IsGeneralAutofillEnabled(FALSE))) return false;
    EventRegistrationToken token{};
    if (FAILED(tab->browser->add_NavigationStarting(Microsoft::WRL::Callback<ICoreWebView2NavigationStartingEventHandler>(
      [this, life, weak, attempt](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
        PWSTR uri = nullptr; args->get_Uri(&uri);
        const std::wstring url = uri ? uri : L""; const bool allowed = WebUrl(url); CoTaskMemFree(uri);
        const auto live = weak.lock();
        if (!*life || !Current(live, attempt)) { args->put_Cancel(TRUE); return S_OK; }
        // Rejecting an external protocol does not make the current web page
        // unavailable or stop a different, already-running navigation.
        if (!allowed) {
          args->put_Cancel(TRUE);
          RecordRejectedNavigation(live);
          return S_OK;
        }
        live->resume_url = url; args->get_NavigationId(&live->navigation);
        live->stopped_navigation = 0; live->navigating = true; live->failed = false; return S_OK;
      }).Get(), &token))) return false;
    if (FAILED(tab->browser->add_NavigationCompleted(Microsoft::WRL::Callback<ICoreWebView2NavigationCompletedEventHandler>(
      [this, life, weak, attempt](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
        if (!*life) return S_OK;
        const auto live = weak.lock(); if (!Current(live, attempt)) return S_OK;
        UINT64 navigation = 0; args->get_NavigationId(&navigation);
        if (navigation != live->navigation) return S_OK;
        BOOL success = FALSE; args->get_IsSuccess(&success);
        live->navigating = false; live->failed = !success && navigation != live->stopped_navigation; return S_OK;
      }).Get(), &token))) return false;
    if (FAILED(tab->browser->add_NewWindowRequested(Microsoft::WRL::Callback<ICoreWebView2NewWindowRequestedEventHandler>(
      [this, life, weak, attempt](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
        args->put_Handled(TRUE);
        if (!*life) return S_OK;
        const auto live = weak.lock(); if (!Current(live, attempt) || !Visible(live)) return S_OK;
        BOOL initiated = FALSE; args->get_IsUserInitiated(&initiated);
        PWSTR uri = nullptr; args->get_Uri(&uri);
        const std::wstring url = uri ? uri : L""; CoTaskMemFree(uri);
        if (initiated && WebUrl(url) && url != L"about:blank") NewTab(url);
        return S_OK;
      }).Get(), &token))) return false;
    if (FAILED(tab->browser->add_PermissionRequested(Microsoft::WRL::Callback<ICoreWebView2PermissionRequestedEventHandler>(
      [](ICoreWebView2*, ICoreWebView2PermissionRequestedEventArgs* args) -> HRESULT {
        args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY); return S_OK;
      }).Get(), &token))) return false;
    if (FAILED(tab->browser->add_ProcessFailed(Microsoft::WRL::Callback<ICoreWebView2ProcessFailedEventHandler>(
      [this, life, weak, attempt](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs*) -> HRESULT {
        if (!*life) return S_OK;
        const auto live = weak.lock(); if (!Current(live, attempt)) return S_OK;
        // Keep the native identity and let explicit Reload replace this failed
        // controller. Other pages and their history are not reset.
        live->broken = true; live->failed = true; live->navigating = false;
        if (live->controller) live->controller->put_IsVisible(FALSE);
        return S_OK;
      }).Get(), &token))) return false;
    ComPtr<ICoreWebView2_4> downloads;
    if (FAILED(tab->browser.As(&downloads)) || FAILED(downloads->add_DownloadStarting(Microsoft::WRL::Callback<ICoreWebView2DownloadStartingEventHandler>(
      [](ICoreWebView2*, ICoreWebView2DownloadStartingEventArgs* args) -> HRESULT { args->put_Cancel(TRUE); return S_OK; }).Get(), &token))) return false;
    if (FAILED(tab->controller->add_AcceleratorKeyPressed(Microsoft::WRL::Callback<ICoreWebView2AcceleratorKeyPressedEventHandler>(
      [this, life, weak, attempt](ICoreWebView2Controller*, ICoreWebView2AcceleratorKeyPressedEventArgs* args) -> HRESULT {
        if (!*life) return S_OK;
        const auto live = weak.lock(); if (!Current(live, attempt) || !Visible(live)) return S_OK;
        UINT key = 0; COREWEBVIEW2_KEY_EVENT_KIND kind{}; args->get_VirtualKey(&key); args->get_KeyEventKind(&kind);
        if (key == VK_ESCAPE && kind == COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN) { args->put_Handled(TRUE); dismiss_(); }
        return S_OK;
      }).Get(), &token))) return false;
    return true;
  }
  ComPtr<ICoreWebView2Environment> environment_;
  HWND viewport_ = nullptr;
  std::vector<std::shared_ptr<BrowserTab>> tabs_;
  std::string active_tab_;
  uint64_t next_tab_ = 0;
  bool environment_opening_ = false;
#endif
  HWND owner_;
  std::function<bool()> current_;
  std::function<void(bool)> modal_;
  std::function<void()> dismiss_;
  std::shared_ptr<std::atomic_bool> alive_;
  ULONG_PTR gdiplus_ = 0;
  bool browser_visible_ = false;
  RECT bounds_{};
  std::vector<uint8_t> screenshot_;
};

MenuLocalTools::MenuLocalTools(HWND owner, std::function<bool()> current, std::function<void(bool)> modal, std::function<void()> dismiss)
  : impl_(std::make_unique<Impl>(owner, std::move(current), std::move(modal), std::move(dismiss))) {}
MenuLocalTools::~MenuLocalTools() = default;
void MenuLocalTools::Handle(const Map& args, Result result) { impl_->Handle(args, std::move(result)); }
void MenuLocalTools::Hide() { impl_->Hide(); }
void MenuLocalTools::Reset() { impl_->Reset(); }
