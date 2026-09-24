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
  ~Impl() { *alive_ = false; Hide();
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    if (controller_) controller_->Close(); browser_.Reset(); controller_.Reset();
#endif
    if (gdiplus_) Gdiplus::GdiplusShutdown(gdiplus_);
  }
  void Hide() {
    browser_visible_ = false;
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    if (controller_) controller_->put_IsVisible(FALSE);
    ComPtr<ICoreWebView2_3> suspending;
    if (browser_ && SUCCEEDED(browser_.As(&suspending))) suspending->TrySuspend(Microsoft::WRL::Callback<ICoreWebView2TrySuspendCompletedHandler>([](HRESULT, BOOL) { return S_OK; }).Get());
#endif
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
    if (action == "browserOpen") { OpenBrowser(std::move(result)); return; }
    if (action == "browserState") {
      if (!browser_) { result->Error("menu.browser_unavailable", "Browser not ready"); return; }
      PWSTR source = nullptr; BOOL back = FALSE, forward = FALSE;
      browser_->get_Source(&source); browser_->get_CanGoBack(&back); browser_->get_CanGoForward(&forward);
      const auto url = Utf8(source); CoTaskMemFree(source);
      result->Success(Value(Map{{Value("url"), Value(url)}, {Value("back"), Value(back != FALSE)},
        {Value("forward"), Value(forward != FALSE)}, {Value("loading"), Value(navigating_)}, {Value("failed"), Value(navigation_failed_)}})); return;
    }
    if (action == "browserNavigate" || action == "browserBack" || action == "browserForward" || action == "browserReload" || action == "browserFocus") {
      if (!browser_ || !controller_) { result->Error("menu.browser_unavailable", "Browser not ready"); return; }
      HRESULT hr = E_INVALIDARG;
      if (action == "browserNavigate") { const auto url = Wide(Text(args,"url")); if (WebUrl(url)) hr = browser_->Navigate(url.c_str()); }
      if (action == "browserBack") hr = browser_->GoBack();
      if (action == "browserForward") hr = browser_->GoForward();
      if (action == "browserReload") hr = browser_->Reload();
      if (action == "browserFocus") hr = controller_->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
      if (FAILED(hr)) result->Error("menu.browser_failed", "Browser action failed"); else result->Success();
      return;
    }
#endif
    result->Error("menu.tool_unavailable", "Tool unavailable");
  }
 private:
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
  void SyncBrowser() {
    if (!controller_) return;
    controller_->put_Bounds(bounds_);
    controller_->put_IsVisible(browser_visible_ && current_());
    ComPtr<ICoreWebView2_3> suspension;
    if (browser_ && SUCCEEDED(browser_.As(&suspension))) {
      if (browser_visible_ && current_()) suspension->Resume();
      else suspension->TrySuspend(Microsoft::WRL::Callback<ICoreWebView2TrySuspendCompletedHandler>([](HRESULT, BOOL) { return S_OK; }).Get());
    }
  }
  void OpenBrowser(MenuLocalTools::Result result) {
    if (browser_) { SyncBrowser(); result->Success(); return; }
    if (opening_) { result->Error("menu.browser_busy", "Browser starting"); return; }
    PWSTR local = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) { result->Error("menu.browser_unavailable", "Profile unavailable"); return; }
    const std::wstring profile = std::wstring(local) + L"\\StarBridge\\MenuBrowser"; CoTaskMemFree(local);
    opening_ = true;
    const auto life = alive_;
    auto reply = std::shared_ptr<flutter::MethodResult<Value>>(std::move(result));
    const auto failed = [this, life, reply]() {
      if (*life) opening_ = false;
      reply->Error("menu.browser_unavailable", "WebView2 unavailable");
    };
    const HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(nullptr, profile.c_str(), nullptr,
      Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
        [this, life, reply, failed](HRESULT status, ICoreWebView2Environment* environment) -> HRESULT {
          if (!*life || FAILED(status) || !environment) { failed(); return S_OK; }
          const HRESULT created = environment->CreateCoreWebView2Controller(owner_,
            Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
              [this, life, reply, failed](HRESULT status2, ICoreWebView2Controller* controller) -> HRESULT {
                if (!*life || FAILED(status2) || !controller) { failed(); return S_OK; }
                opening_ = false; controller_ = controller; controller_->get_CoreWebView2(&browser_);
                if (!browser_) { controller_->Close(); controller_.Reset(); failed(); return S_OK; }
                ComPtr<ICoreWebView2Settings> settings; browser_->get_Settings(&settings);
                settings->put_IsWebMessageEnabled(FALSE); settings->put_AreHostObjectsAllowed(FALSE);
                settings->put_AreDevToolsEnabled(FALSE); settings->put_IsStatusBarEnabled(FALSE);
                settings->put_AreDefaultContextMenusEnabled(FALSE);
                EventRegistrationToken token{};
                browser_->add_NavigationStarting(Microsoft::WRL::Callback<ICoreWebView2NavigationStartingEventHandler>(
                  [this, life](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
                    PWSTR uri = nullptr; args->get_Uri(&uri); const bool allowed = uri && WebUrl(uri); CoTaskMemFree(uri);
                    if (!allowed) args->put_Cancel(TRUE);
                    if (*life) { navigating_ = allowed; navigation_failed_ = !allowed; }
                    return S_OK;
                  }).Get(), &token);
                browser_->add_NavigationCompleted(Microsoft::WRL::Callback<ICoreWebView2NavigationCompletedEventHandler>(
                  [this, life](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
                    BOOL success = FALSE; args->get_IsSuccess(&success);
                    if (*life) { navigating_ = false; navigation_failed_ = !success; }
                    return S_OK;
                  }).Get(), &token);
                browser_->add_NewWindowRequested(Microsoft::WRL::Callback<ICoreWebView2NewWindowRequestedEventHandler>(
                  [](ICoreWebView2* sender, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
                    args->put_Handled(TRUE); BOOL initiated = FALSE; args->get_IsUserInitiated(&initiated);
                    PWSTR uri = nullptr; args->get_Uri(&uri); if (initiated && uri && WebUrl(uri)) sender->Navigate(uri);
                    CoTaskMemFree(uri); return S_OK;
                  }).Get(), &token);
                browser_->add_PermissionRequested(Microsoft::WRL::Callback<ICoreWebView2PermissionRequestedEventHandler>(
                  [](ICoreWebView2*, ICoreWebView2PermissionRequestedEventArgs* args) -> HRESULT {
                    args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY); return S_OK;
                  }).Get(), &token);
                ComPtr<ICoreWebView2_4> downloads;
                if (SUCCEEDED(browser_.As(&downloads))) downloads->add_DownloadStarting(Microsoft::WRL::Callback<ICoreWebView2DownloadStartingEventHandler>(
                  [](ICoreWebView2*, ICoreWebView2DownloadStartingEventArgs* args) -> HRESULT { args->put_Cancel(TRUE); return S_OK; }).Get(), &token);
                controller_->add_AcceleratorKeyPressed(Microsoft::WRL::Callback<ICoreWebView2AcceleratorKeyPressedEventHandler>(
                  [this, life](ICoreWebView2Controller*, ICoreWebView2AcceleratorKeyPressedEventArgs* args) -> HRESULT {
                    UINT key = 0; COREWEBVIEW2_KEY_EVENT_KIND kind{}; args->get_VirtualKey(&key); args->get_KeyEventKind(&kind);
                    if (*life && key == VK_ESCAPE && kind == COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN) { args->put_Handled(TRUE); dismiss_(); }
                    return S_OK;
                  }).Get(), &token);
                browser_->Navigate(L"about:blank"); SyncBrowser(); reply->Success(); return S_OK;
              }).Get());
          if (FAILED(created)) failed(); return S_OK;
        }).Get());
    if (FAILED(hr)) failed();
  }
  ComPtr<ICoreWebView2Controller> controller_;
  ComPtr<ICoreWebView2> browser_;
  bool opening_ = false;
  bool navigating_ = false, navigation_failed_ = false;
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
