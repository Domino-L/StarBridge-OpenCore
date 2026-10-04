#include "menu_local_tools.h"
#include "menu_browser_options.h"
#include "menu_image_native.h"
#include "menu_reference_identity.h"
#include "menu_reference_decode.h"
#include "menu_screenshot_export.h"
#include "menu_screenshot_storage.h"
#include "menu_screenshot_capture.h"
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
std::string Text(const Map& m, const char* k, size_t byte_limit = 4096) {
  const auto* v = Field(m, k); const auto* s = v ? std::get_if<std::string>(v) : nullptr;
  return s && s->size() <= byte_limit ? *s : "";
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
std::vector<uint8_t> Png(Gdiplus::Bitmap& image) { return MenuEncodeScreenshot(image); }
std::vector<uint8_t> PickImage(HWND owner, bool& cancelled, std::optional<menu_image::ReferenceFileKey>& identity) {
  cancelled = false;
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) return {};
  const COMDLG_FILTERSPEC filters[] = {{L"图片 (PNG, JPEG, BMP, GIF, TIFF)", kMenuReferenceFilter}};
  dialog->SetFileTypes(1, filters);
  dialog->SetOptions(FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST | FOS_FORCEFILESYSTEM | FOS_NOCHANGEDIR | FOS_DONTADDTORECENT);
  const HRESULT shown = dialog->Show(owner);
  if (FAILED(shown)) { cancelled = shown == HRESULT_FROM_WIN32(ERROR_CANCELLED); return {}; }
  ComPtr<IShellItem> item; PWSTR path = nullptr;
  if (FAILED(dialog->GetResult(&item)) || FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) return {};
  // Open only the file selected by this dialog; never accept a path from Dart.
  HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  CoTaskMemFree(path); if (file == INVALID_HANDLE_VALUE) return {};
  identity = menu_image::ReferenceKey(file);
  LARGE_INTEGER length{}; std::vector<uint8_t> bytes;
  if (GetFileSizeEx(file, &length) && length.QuadPart > 0 && length.QuadPart <= kMaxBytes) {
    bytes.resize(static_cast<size_t>(length.QuadPart)); DWORD read = 0;
    if (!ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr) || read != bytes.size()) bytes.clear();
  }
  CloseHandle(file); auto stream = Stream(bytes); if (!stream || bytes.empty()) return {};
  return MenuDecodeReference(stream.Get());
}
std::vector<uint8_t> Capture(HWND owner) {
  MONITORINFO info{sizeof(info)};
  if (!GetMonitorInfoW(MonitorFromWindow(owner, MONITOR_DEFAULTTONEAREST), &info)) return {};
  const int width = info.rcMonitor.right - info.rcMonitor.left, height = info.rcMonitor.bottom - info.rcMonitor.top;
  if (width <= 0 || height <= 0 || !menu_image::Bounded(static_cast<UINT>(width), static_cast<UINT>(height))) return {};
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
bool SaveImage(HWND owner, Gdiplus::Bitmap& image, MenuScreenshotExport options, bool& cancelled, bool& mismatch,
    const std::function<bool()>& current, const SYSTEMTIME& time) {
  cancelled = false;
  mismatch = false;
  ComPtr<IFileSaveDialog> dialog;
  if (FAILED(CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) return false;
  const COMDLG_FILTERSPEC filters[] = {{L"PNG (*.png)", L"*.png"}, {L"JPEG (*.jpg; *.jpeg)", L"*.jpg;*.jpeg"}};
  if (FAILED(dialog->SetFileTypes(2, filters)) || FAILED(dialog->SetFileTypeIndex(options.jpeg ? 2 : 1)) ||
      FAILED(dialog->SetDefaultExtension(options.Extension()))) return false;
  wchar_t name[80]{};
  swprintf_s(name, L"StarBridge_%04u%02u%02u_%02u%02u%02u_%03u.%ls", static_cast<unsigned>(time.wYear),
      static_cast<unsigned>(time.wMonth), static_cast<unsigned>(time.wDay), static_cast<unsigned>(time.wHour),
      static_cast<unsigned>(time.wMinute), static_cast<unsigned>(time.wSecond), static_cast<unsigned>(time.wMilliseconds), options.Extension());
  if (FAILED(dialog->SetFileName(name)) ||
      FAILED(dialog->SetOptions(FOS_OVERWRITEPROMPT | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR | FOS_DONTADDTORECENT))) return false;
  const HRESULT shown = dialog->Show(owner);
  if (FAILED(shown)) { cancelled = shown == HRESULT_FROM_WIN32(ERROR_CANCELLED); return false; }
  // A modal dialog pumps messages, so account reset can retire this operation
  // while it is open. Never export the retired account's retained image.
  if (!current()) return false;
  ComPtr<IShellItem> item; PWSTR path = nullptr;
  if (FAILED(dialog->GetResult(&item)) || FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) return false;
  const std::wstring destination(path); CoTaskMemFree(path);
  UINT selected = 0;
  if (FAILED(dialog->GetFileTypeIndex(&selected)) || (selected != 1 && selected != 2)) return false;
  options.jpeg = selected == 2;
  if (!options.MatchesExtension(std::filesystem::path(destination).extension().wstring())) {
    mismatch = true; return false;
  }
  const auto bytes = MenuEncodeScreenshot(image, options);
  if (bytes.empty() || !current()) return false;
  return menu_screenshot::WriteAtomic(destination, bytes, current, true);
}
bool StrictNumber(const Map& args, const char* key, double& number) {
  const auto* value = Field(args, key);
  if (!value) return false;
  if (const auto* n = std::get_if<double>(value)) number = *n;
  else if (const auto* integer = std::get_if<int32_t>(value)) number = *integer;
  else return false;
  return std::isfinite(number);
}
bool ParseEdit(const Map& args, menu_image::Edit& edit) {
  // Legacy Save without editing fields still means the complete screenshot.
  const char* keys[]{"cropLeft", "cropTop", "cropRight", "cropBottom", "turns"};
  bool any = false;
  for (const auto* key : keys) any = any || Field(args, key);
  if (!any) return true;
  double turns = 0;
  if (!StrictNumber(args, keys[0], edit.left) || !StrictNumber(args, keys[1], edit.top) ||
      !StrictNumber(args, keys[2], edit.right) || !StrictNumber(args, keys[3], edit.bottom) ||
      !StrictNumber(args, keys[4], turns) || turns < 0 || turns > 3 || std::floor(turns) != turns) return false;
  edit.turns = static_cast<int>(turns); return edit.Valid();
}
bool CopyImage(HWND owner, Gdiplus::Bitmap& image) {
  const auto bytes = menu_image::ClipboardDib(image);
  if (bytes.empty()) return false;
  HGLOBAL block = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  if (!block) return false;
  void* buffer = GlobalLock(block);
  if (!buffer) { GlobalFree(block); return false; }
  memcpy(buffer, bytes.data(), bytes.size()); GlobalUnlock(block);
  if (!OpenClipboard(owner)) { GlobalFree(block); return false; }
  const bool copied = EmptyClipboard() && SetClipboardData(CF_DIBV5, block);
  CloseClipboard(); if (!copied) GlobalFree(block); return copied;
}
class ReferencePin {
 public:
  explicit ReferencePin(std::function<bool()> menu) : menu_(std::move(menu)) {}
  ~ReferencePin() { Clear(); }
  void Clear() {
    if (window_) { KillTimer(window_, 1); DestroyWindow(window_); window_ = nullptr; }
    suppressed_ = false;
  }
  void Suppress(bool value) { suppressed_ = value; Sync(); }
  bool Set(HWND owner, const Map& args, bool enabled = true) {
    const auto* value = Field(args, "bytes");
    const auto* bytes = value ? std::get_if<std::vector<uint8_t>>(value) : nullptr;
    UINT image_width = 0, image_height = 0;
    double x = 0, y = 0, width = 0, height = 0;
    RECT client{}; GetClientRect(owner, &client);
    if (!bytes || !menu_image::PngSize(*bytes, image_width, image_height) ||
        !menu_image::Bounded(image_width, image_height, 4096, 16000000) ||
        !StrictNumber(args, "x", x) || !StrictNumber(args, "y", y) ||
        !StrictNumber(args, "width", width) || !StrictNumber(args, "height", height) ||
        x < 0 || y < 0 || width < 1 || height < 1 || width > 4096 || height > 4096 ||
        width*height > 16000000 || x+width > client.right+1 || y+height > client.bottom+1 ||
        std::abs(width-image_width) > 1 || std::abs(height-image_height) > 1) return false;
    auto stream = Stream(*bytes);
    if (!stream) return false;
    Gdiplus::Bitmap image(stream.Get());
    if (image.GetLastStatus() != Gdiplus::Ok || image.GetWidth() != image_width || image.GetHeight() != image_height) return false;
    const auto pixels = menu_image::Pixels(image, true);
    if (pixels.empty()) return false;
    WNDCLASSW cls{}; cls.hInstance = GetModuleHandleW(nullptr); cls.lpfnWndProc = Proc;
    cls.lpszClassName = L"StarBridgeMenuReferencePin";
    if (!RegisterClassW(&cls) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
    // Prepare a replacement completely before retiring the existing pin.
    // Decoder, GDI and timer failures must keep the last confirmed image.
    const HWND candidate = CreateWindowExW(menu_image::kPinStyle, cls.lpszClassName, L"", WS_POPUP,
        0, 0, 0, 0, nullptr, nullptr, cls.hInstance, this);
    if (!candidate) return false;
    BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = static_cast<LONG>(image_width); info.bmiHeader.biHeight = -static_cast<LONG>(image_height);
    info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
    HDC screen = GetDC(nullptr); HDC memory = screen ? CreateCompatibleDC(screen) : nullptr;
    void* target = nullptr;
    HBITMAP bitmap = memory ? CreateDIBSection(memory, &info, DIB_RGB_COLORS, &target, nullptr, 0) : nullptr;
    bool updated = false;
    if (bitmap && target) {
      memcpy(target, pixels.data(), pixels.size());
      const auto old = SelectObject(memory, bitmap);
      POINT location{static_cast<LONG>(std::lround(x)), static_cast<LONG>(std::lround(y))};
      ClientToScreen(owner, &location);
      SIZE size{static_cast<LONG>(image_width), static_cast<LONG>(image_height)}; POINT origin{};
      BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
      updated = UpdateLayeredWindow(candidate, screen, &location, &size, memory, &origin, 0, &blend, ULW_ALPHA) != FALSE;
      SelectObject(memory, old);
    }
    if (bitmap) DeleteObject(bitmap); if (memory) DeleteDC(memory); if (screen) ReleaseDC(nullptr, screen);
    if (!updated || !SetTimer(candidate, 1, 250, nullptr)) { DestroyWindow(candidate); return false; }
    Clear(); window_ = candidate; enabled_ = enabled;
    Sync(); return true;
  }
  bool active() const { return window_ && enabled_; }
  void Adopt(ReferencePin& prepared) {
    Clear();
    window_ = prepared.window_; prepared.window_ = nullptr;
    enabled_ = true;
    if (window_) SetWindowLongPtrW(window_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    Sync();
  }
  void Sync() {
    if (!window_) return;
    bool game = false;
    if (!menu_() && !suppressed_) {
      DWORD pid = 0; GetWindowThreadProcessId(GetForegroundWindow(), &pid);
      HANDLE process = pid ? OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid) : nullptr;
      if (process) {
        wchar_t path[32768]{}; DWORD size = static_cast<DWORD>(std::size(path));
        game = QueryFullProcessImageNameW(process, 0, path, &size) && menu_image::IsGame(std::wstring(path, size));
        CloseHandle(process);
      }
    }
    if (menu_image::PinVisible(enabled_, menu_(), suppressed_, game))
      SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    else ShowWindow(window_, SW_HIDE);
  }
 private:
  static LRESULT CALLBACK Proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_NCCREATE) {
      SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams));
    }
    const auto self = reinterpret_cast<ReferencePin*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_TIMER && self) { self->Sync(); return 0; }
    if (message == WM_NCHITTEST) return HTTRANSPARENT;
    if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (message == WM_NCDESTROY) SetWindowLongPtrW(window, GWLP_USERDATA, 0);
    return DefWindowProcW(window, message, wparam, lparam);
  }
  HWND window_ = nullptr;
  std::function<bool()> menu_;
  bool suppressed_ = false;
  bool enabled_ = true;
};
}

class MenuLocalTools::Impl {
 public:
  Impl(HWND owner, std::function<bool()> current, std::function<void(bool)> modal, std::function<void()> dismiss)
    : owner_(owner), current_(std::move(current)), modal_(std::move(modal)), dismiss_(std::move(dismiss)), alive_(std::make_shared<std::atomic_bool>(true)), pin_(current_) {
    Gdiplus::GdiplusStartupInput input; Gdiplus::GdiplusStartup(&gdiplus_, &input, nullptr);
  }
  ~Impl() { *alive_ = false; Reset();
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    environment_.Reset();
#endif
    if (gdiplus_) Gdiplus::GdiplusShutdown(gdiplus_);
  }
  void Hide() {
    screenshot_directory_.clear();
    browser_visible_ = false;
    if (!current_() && prepared_pin_) {
      pin_.Adopt(*prepared_pin_);
      prepared_pin_.reset();
    }
    pin_.Sync();
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    SyncBrowser();
#endif
  }
  void Reset() {
    ++image_epoch_;
    prepared_pin_.reset();
    pin_.Clear();
    Hide();
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    for (const auto& tab : tabs_) CloseController(tab);
    tabs_.clear(); active_tab_.clear();
    if (viewport_) { DestroyWindow(viewport_); viewport_ = nullptr; }
#endif
    screenshot_.clear();
    screenshot_time_ = {};
    reference_.clear();
    reference_identities_.Clear();
  }
  bool AuthorizeScreenshotDirectory(const std::string& value) {
    screenshot_directory_.clear();
    if (!current_() || value.size() > 131068) return false;
    const auto directory = Wide(value);
    if (!menu_screenshot::ValidDirectory(directory)) return false;
    screenshot_directory_ = directory;
    return true;
  }
  void Handle(const Map& args, MenuLocalTools::Result result) {
    const auto action = Text(args, "action");
    if (!current_()) { result->Error("menu.closed", "Menu is closed"); return; }
    pin_.Sync();
#ifdef STARBRIDGE_MENU_IMAGE_TEST
    // Synthetic hidden fixture only; production never accepts a screenshot
    // from Flutter or exposes the captured/selected source through this seam.
    if (action == "imageTestLoad") {
      const auto* data = Field(args, "bytes");
      const auto* bytes = data ? std::get_if<std::vector<uint8_t>>(data) : nullptr;
      UINT width = 0, height = 0;
      if (!bytes || !menu_image::PngSize(*bytes, width, height)) { result->Error("fixture.invalid", "Invalid fixture"); return; }
      reference_ = *bytes; screenshot_ = *bytes; GetLocalTime(&screenshot_time_); result->Success(); return;
    }
    if (action == "imageTestSelect") {
      const auto* data = Field(args, "bytes"), *file = Field(args, "fixtureFile");
      const auto* bytes = data ? std::get_if<std::vector<uint8_t>>(data) : nullptr;
      const auto* id = file ? std::get_if<int32_t>(file) : nullptr;
      UINT width = 0, height = 0;
      if (!bytes || !menu_image::PngSize(*bytes, width, height) || !id || *id < 1 || *id > 1000) {
        result->Error("fixture.invalid", "Invalid fixture"); return;
      }
      ReplyReference(*bytes, menu_image::ReferenceFileKey{1,0,static_cast<DWORD>(*id),0,1,0,1,0,1}, std::move(result));
      return;
    }
#endif
    if (action == "imageClear" || action == "imageUnpin" || action == "screenshotClear") {
      if (action != "screenshotClear") prepared_pin_.reset();
      if (action != "imageUnpin") ++image_epoch_;
      if (action == "screenshotClear") { screenshot_.clear(); screenshot_time_ = {}; }
      else { pin_.Clear(); if (action == "imageClear") reference_.clear(); }
      result->Success(); return;
    }
    if (action == "imagePreparePin") {
      auto next = std::make_unique<ReferencePin>(current_);
      if (reference_.empty() || !next->Set(owner_, args, false)) {
        prepared_pin_.reset();
        result->Error("menu.image_pin_failed", "Reference image could not be prepared");
      } else { prepared_pin_ = std::move(next); result->Success(Value(true)); }
      return;
    }
    if (action == "imageCancelPreparedPin") { prepared_pin_.reset(); result->Success(); return; }
    if (action == "imagePinState") { result->Success(Value(pin_.active())); return; }
    if (action == "imagePin") {
      prepared_pin_.reset();
      if (reference_.empty() || !pin_.Set(owner_, args)) result->Error("menu.image_pin_failed", "Reference image could not be pinned");
      else result->Success(Value(true));
      return;
    }
    if (action == "save" || action == "saveToDirectory" || action == "screenshotCopy" || action == "screenshotEdit" || action == "imageEdit") {
      std::wstring directory;
      if (action == "saveToDirectory") {
        directory = std::move(screenshot_directory_); screenshot_directory_.clear();
        // Never permit a surface-selected path, bytes or extra native intent.
        for (const auto& field : args) {
          const auto* key = std::get_if<std::string>(&field.first);
          if (!key || (*key != "action" && *key != "opening" && *key != "export" && *key != "cropLeft" &&
              *key != "cropTop" && *key != "cropRight" && *key != "cropBottom" && *key != "turns")) {
            result->Error("menu.screenshot_export_invalid", "Invalid direct save intent"); return;
          }
        }
        if (directory.empty()) { result->Error("menu.screenshot_directory_unavailable", "Screenshot directory unavailable"); return; }
      }
      MenuScreenshotExport options;
      if (action == "save" || action == "saveToDirectory") {
        if (const auto value = Field(args, "export")) {
          const auto parsed = MenuScreenshotExport::Parse(*value);
          if (!parsed) { result->Error("menu.screenshot_export_invalid", "Invalid export options"); return; }
          options = *parsed;
        }
      }
      const bool reference = action == "imageEdit";
      const auto& source = reference ? reference_ : screenshot_;
      const auto error = reference ? "menu.image_edit_failed" : "menu.screenshot_edit_failed";
      menu_image::Edit edit;
      if (source.empty() || !ParseEdit(args, edit)) {
        result->Error(error, "Image or edit is invalid"); return;
      }
      auto stream = Stream(source);
      if (!stream) { result->Error(error, "Image could not be read"); return; }
      Gdiplus::Bitmap original(stream.Get());
      auto edited = menu_image::Edited(original, edit);
      if (!edited || edited->GetLastStatus() != Gdiplus::Ok) { result->Error(error, "Image could not be edited"); return; }
      if (action == "screenshotCopy") {
        if (CopyImage(owner_, *edited)) result->Success(Value(true));
        else result->Error("menu.screenshot_copy_failed", "Clipboard is unavailable");
      } else {
        if (action == "screenshotEdit" || reference) {
          const auto bytes = Png(*edited);
          if (bytes.empty()) result->Error(error, "Image could not be encoded");
          else result->Success(Value(bytes));
        }
        else if (action == "saveToDirectory") {
          const auto epoch = image_epoch_;
          const auto bytes = MenuEncodeScreenshot(*edited, options);
          const auto saved = menu_screenshot::SaveUnique(directory, bytes, options.jpeg, screenshot_time_,
              [this, epoch] { return current_() && epoch == image_epoch_; });
          if (!current_() || epoch != image_epoch_) result->Error("menu.closed", "Menu session was retired");
          else if (saved.empty()) result->Error("menu.screenshot_save_failed", "Screenshot could not be saved");
          else result->Success(Value(true)); // No filename or path leaves native ownership.
        } else {
          const auto epoch = image_epoch_;
          modal_(true); Hide(); bool cancelled = false, mismatch = false;
          const bool saved = SaveImage(owner_, *edited, options, cancelled, mismatch,
              [this, epoch] { return current_() && epoch == image_epoch_; }, screenshot_time_);
          modal_(false);
          if (!current_() || epoch != image_epoch_) { result->Error("menu.closed", "Menu session was retired"); return; }
          if (saved || cancelled) result->Success(Value(saved));
          else if (mismatch) result->Error("menu.screenshot_extension_mismatch", "Extension does not match selected format");
          else result->Error("menu.screenshot_save_failed", "Screenshot could not be saved");
        }
      }
      return;
    }
    if (action == "image" || action == "capture") {
      const auto epoch = image_epoch_;
      std::vector<uint8_t> bytes;
      bool cancelled = false;
      std::optional<menu_image::ReferenceFileKey> identity;
      if (action == "capture") {
        const auto hide = MenuCaptureHidesMenu(args);
        if (!hide) { result->Error("menu.screenshot_preferences_invalid", "Invalid screenshot preferences"); return; }
        bytes = RunMenuCapture(*hide, [this](bool hidden) {
          modal_(true);
          if (hidden) {
            Hide(); pin_.Suppress(true);
            ShowWindow(owner_, SW_HIDE); DwmFlush();
          }
        }, [this, epoch, hidden = *hide]() {
          if (epoch != image_epoch_) return;
          if (hidden) {
            if (current_()) ShowWindow(owner_, SW_SHOWNOACTIVATE);
            pin_.Suppress(false);
          }
          if (current_()) modal_(false);
        }, [this] { return Capture(owner_); });
      } else {
        modal_(true); Hide();
        bytes = PickImage(owner_, cancelled, identity);
        modal_(false);
      }
      if (!current_() || epoch != image_epoch_) { result->Error("menu.closed", "Menu session was retired"); return; }
      if (bytes.empty()) {
        if (cancelled) result->Success(); else result->Error("menu.image_failed", "Image could not be read");
      } else {
        if (action == "capture") { screenshot_ = bytes; GetLocalTime(&screenshot_time_); result->Success(Value(bytes)); }
        else ReplyReference(bytes, identity, std::move(result));
      }
      return;
    }
    if (action == "browserBounds") {
      browser_opacity_ = Field(args, "opacity") ? Number(args, "opacity") : 1.0;
      if (!std::isfinite(browser_opacity_) || browser_opacity_ < 0.7 || browser_opacity_ > 1.0) browser_opacity_ = 1.0;
      RECT parent{}; GetClientRect(owner_, &parent);
      const double x = Number(args,"x"), y = Number(args,"y"), w = Number(args,"width"), h = Number(args,"height");
      // The child is clipped by its parent HWND; crossing an edge must not
      // blank the entire browser. Still reject unbounded/malformed geometry.
      const bool valid = std::isfinite(x) && std::isfinite(y) && std::isfinite(w) && std::isfinite(h) &&
          std::abs(x) <= 1000000 && std::abs(y) <= 1000000 && w >= 1 && h >= 1 && w <= 1000000 && h <= 1000000;
      browser_visible_ = Flag(args,"visible") && valid && x < parent.right && y < parent.bottom && x+w > 0 && y+h > 0;
      if (valid) bounds_ = RECT{static_cast<LONG>(x), static_cast<LONG>(y), static_cast<LONG>(x+w), static_cast<LONG>(y+h)};
      browser_occlusions_.clear();
      if (const auto* occlusions_value = Field(args, "occlusions")) {
        const auto* rects = std::get_if<flutter::EncodableList>(occlusions_value);
        bool clips_valid = rects && rects->size() <= 32;
        if (clips_valid) for (const auto& value : *rects) {
          const auto* rect = std::get_if<Map>(&value);
          if (!rect) { clips_valid = false; break; }
          const auto finite_number = [](const Map& rect, const char* key) {
            const auto* value = Field(rect, key);
            if (!value) return false;
            if (const auto* number = std::get_if<double>(value)) return std::isfinite(*number);
            return std::get_if<int32_t>(value) != nullptr;
          };
          if (!finite_number(*rect, "x") || !finite_number(*rect, "y") ||
              !finite_number(*rect, "width") || !finite_number(*rect, "height")) { clips_valid = false; break; }
          const double cx = Number(*rect, "x"), cy = Number(*rect, "y"),
              cw = Number(*rect, "width"), ch = Number(*rect, "height");
          if (std::abs(cx) > 1000000 || std::abs(cy) > 1000000 || cw < 0 || ch < 0 || cw > 1000000 || ch > 1000000) {
            clips_valid = false; break;
          }
          // Outward rounding avoids a one-physical-pixel browser strip over
          // Flutter chrome at fractional scale/DPI. Region is viewport-local.
          browser_occlusions_.push_back(RECT{
            static_cast<LONG>(std::floor(cx)) - bounds_.left,
            static_cast<LONG>(std::floor(cy)) - bounds_.top,
            static_cast<LONG>(std::ceil(cx + cw)) - bounds_.left,
            static_cast<LONG>(std::ceil(cy + ch)) - bounds_.top});
        }
        // A malformed clipping message must not expose the child over Flutter.
        if (!clips_valid) { browser_visible_ = false; browser_occlusions_.clear(); }
      }
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
      SyncBrowser();
#endif
      result->Success(); return;
    }
#ifdef STARBRIDGE_HAS_HANGAR_WEBVIEW
    if (action == "browserConfigure") {
      const auto it = args.find(Value("preferences"));
      const auto options = it == args.end() ? std::nullopt : MenuBrowserOptions::Parse(it->second);
      if (!options) { result->Error("menu.browser_preferences_invalid", "Invalid browser preferences"); return; }
      browser_options_ = *options; SyncBrowser(); result->Success(); return;
    }
#ifdef STARBRIDGE_MENU_BROWSER_TEST
    if (action == "browserTestVisualState") {
      BYTE alpha = 255; DWORD alpha_flags = 0; COLORREF alpha_key = 0;
      if (viewport_) GetLayeredWindowAttributes(viewport_, &alpha_key, &alpha, &alpha_flags);
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
        {Value("alpha"), Value(static_cast<int32_t>(alpha))},
        {Value("controllers"), Value(visual)}, {Value("children"), Value(children)}})); return;
    }
    if (action == "browserTestInteraction") {
      POINT point{static_cast<LONG>(Number(args, "x")), static_cast<LONG>(Number(args, "y"))};
      ClientToScreen(viewport_, &point);
      result->Success(Value(BrowserInteractionAt(point, viewport_, Flag(args, "focused") ? viewport_ : nullptr)));
      return;
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
    // Fixed inert inputs exercise the exact new-window event consumer, never
    // expose arbitrary scripts/URLs to the production surface.
    if (action == "browserTestNewWindow" || action == "browserTestPopup" || action == "browserTestUnsafeWindow") {
      const auto tab = FindTab(active_tab_);
      if (tab) RequestNewWindow(tab, action != "browserTestPopup",
          action == "browserTestUnsafeWindow" ? L"data:text/plain,blocked" : L"http://127.0.0.1:9/menu-fixture");
      result->Success(); return;
    }
#endif
    std::wstring initial_url = L"about:blank";
    if (action == "browserOpen" || action == "browserNewTab" || action == "browserCloseTab") {
      const auto requested = Text(args, "url", 16384);
      if (!requested.empty()) {
        initial_url = Wide(requested);
        if (!WebUrl(initial_url)) { result->Error("menu.browser_failed", "Invalid initial page"); return; }
      }
    }
    if (action == "browserOpen") {
      if (tabs_.empty()) NewTab(initial_url);
      SyncBrowser(); result->Success(); return;
    }
    if (action == "browserNewTab") {
      if (tabs_.size() >= static_cast<size_t>(browser_options_.limit)) { result->Error("menu.browser_tab_limit", "Tab limit reached"); return; }
      NewTab(initial_url); result->Success(); return;
    }
    if (action == "browserSelectTab" || action == "browserCloseTab") {
      const auto tab = FindTab(Text(args, "tabId"));
      if (!tab) { result->Error("menu.browser_tab_stale", "Tab no longer exists"); return; }
      if (action == "browserSelectTab") active_tab_ = tab->id;
      else {
        const auto index = static_cast<size_t>(std::find(tabs_.begin(), tabs_.end(), tab) - tabs_.begin());
        const bool active = active_tab_ == tab->id;
        CloseController(tab); tabs_.erase(tabs_.begin() + index);
        if (tabs_.empty()) NewTab(initial_url);
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
      state.emplace(Value("tabLimit"), Value(browser_options_.limit));
      POINT pointer{};
      const HWND hovered = GetCursorPos(&pointer) ? WindowFromPoint(pointer) : nullptr;
      state.emplace(Value("interactionActive"), Value(BrowserInteractionAt(pointer, hovered, GetFocus())));
      state.emplace(Value("opacitySupported"), Value(browser_opacity_supported_));
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
      // A bounded UTF-8 transport can use several bytes per UTF-16 character.
      // Keep WebUrl's existing 4096-character cap after strict conversion.
      if (action == "browserNavigate") { const auto url = Wide(Text(args,"url", 16384)); if (WebUrl(url)) hr = tab->browser->Navigate(url.c_str()); }
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
  MenuBrowserOptions browser_options_;
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
  bool BrowserInteractionAt(POINT screen_point, HWND hovered, HWND focused) const {
    if (!viewport_ || !browser_visible_ || !current_()) return false;
    // WebView's focus crosses a native child boundary. Conservatively keep it
    // readable while that subtree owns keyboard focus; never inspect page DOM.
    if (focused && (focused == viewport_ || IsChild(viewport_, focused))) return true;
    if (!hovered || (hovered != viewport_ && !IsChild(viewport_, hovered))) return false;
    ScreenToClient(viewport_, &screen_point);
    RECT client{};
    if (!GetClientRect(viewport_, &client) || !PtInRect(&client, screen_point)) return false;
    HRGN region = CreateRectRgn(0, 0, 0, 0);
    if (!region) return false;
    const int complexity = GetWindowRgn(viewport_, region);
    const bool inside = complexity != ERROR && PtInRegion(region, screen_point.x, screen_point.y);
    DeleteObject(region);
    return inside;
  }
  void SyncBrowser() {
    const auto active = FindTab(active_tab_);
    bool show = active && active->controller && Visible(active);
    const LONG width = std::max(0L, bounds_.right - bounds_.left);
    const LONG height = std::max(0L, bounds_.bottom - bounds_.top);
    if (viewport_) {
      const auto style = GetWindowLongPtrW(viewport_, GWL_EXSTYLE);
      if ((style & WS_EX_LAYERED) == 0) SetWindowLongPtrW(viewport_, GWL_EXSTYLE, style | WS_EX_LAYERED);
      browser_opacity_supported_ = SetLayeredWindowAttributes(viewport_, 0,
          static_cast<BYTE>(std::lround(browser_opacity_ * 255)), LWA_ALPHA) != FALSE;
      // An unsupported compositor stays readable; Dart keeps its chrome opaque
      // too after the next existing status reply, rather than a half-faded panel.
      if (!browser_opacity_supported_) SetWindowLongPtrW(viewport_, GWL_EXSTYLE, style & ~WS_EX_LAYERED);
      HRGN region = CreateRectRgn(0, 0, width, height);
      bool clipped = region != nullptr;
      int complexity = width > 0 && height > 0 ? SIMPLEREGION : NULLREGION;
      for (const auto& rect : browser_occlusions_) {
        HRGN hole = CreateRectRgn(rect.left, rect.top, rect.right, rect.bottom);
        if (!hole || !region) { clipped = false; if (hole) DeleteObject(hole); break; }
        complexity = CombineRgn(region, region, hole, RGN_DIFF);
        DeleteObject(hole);
        if (complexity == ERROR) { clipped = false; break; }
      }
      if (clipped && SetWindowRgn(viewport_, region, TRUE)) {
        // Windows owns the region after a successful SetWindowRgn.
        region = nullptr;
      } else { clipped = false; }
      if (region) DeleteObject(region);
      show = show && clipped && complexity != NULLREGION;
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
      const bool visible = show && Visible(tab);
      tab->controller->put_Bounds(child_bounds);
      tab->controller->put_IsVisible(visible ? TRUE : FALSE);
      tab->controller->NotifyParentWindowPositionChanged();
      ComPtr<ICoreWebView2_3> suspension;
      if (!tab->browser || FAILED(tab->browser.As(&suspension))) continue;
      if (visible || (!browser_options_.pause_hidden && current_())) { suspension->Resume(); continue; }
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
          if ((Visible(live) || (!browser_options_.pause_hidden && current_())) &&
              SUCCEEDED(live->browser.As(&resume))) resume->Resume();
          return S_OK;
        }).Get());
      if (FAILED(hr)) tab->suspend_pending = false;
    }
  }
  void NewTab(const std::wstring& url) {
    if (tabs_.size() >= static_cast<size_t>(browser_options_.limit)) return;
    auto tab = std::make_shared<BrowserTab>();
    tab->id = "t" + std::to_string(++next_tab_); tab->resume_url = url;
    tabs_.push_back(tab); active_tab_ = tab->id;
    // Hide the old page before beginning asynchronous controller creation.
    SyncBrowser(); StartTab(tab);
  }
  void RequestNewWindow(const std::shared_ptr<BrowserTab>& tab, bool initiated, const std::wstring& url) {
    if (!Visible(tab) || !initiated || !WebUrl(url) || url == L"about:blank") return;
    if (browser_options_.new_tab) NewTab(url);
    else tab->browser->Navigate(url.c_str());
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
        RequestNewWindow(live, initiated != FALSE, url);
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
  double browser_opacity_ = 1.0;
  bool browser_opacity_supported_ = true;
  std::vector<RECT> browser_occlusions_;
  RECT bounds_{};
  std::vector<uint8_t> screenshot_;
  SYSTEMTIME screenshot_time_{};
  std::wstring screenshot_directory_;
  std::vector<uint8_t> reference_;
  ReferencePin pin_;
  std::unique_ptr<ReferencePin> prepared_pin_;
  uint64_t image_epoch_ = 0;
  menu_image::ReferenceIdentityCache reference_identities_;
  void ReplyReference(const std::vector<uint8_t>& bytes,
      const std::optional<menu_image::ReferenceFileKey>& identity, MenuLocalTools::Result result) {
    reference_ = bytes; prepared_pin_.reset(); pin_.Clear();
    const auto id = reference_identities_.Resolve(identity);
    result->Success(Value(Map{{Value("bytes"), Value(bytes)},
      {Value("imageId"), id ? Value(*id) : Value()}}));
  }
};

MenuLocalTools::MenuLocalTools(HWND owner, std::function<bool()> current, std::function<void(bool)> modal, std::function<void()> dismiss)
  : impl_(std::make_unique<Impl>(owner, std::move(current), std::move(modal), std::move(dismiss))) {}
MenuLocalTools::~MenuLocalTools() = default;
void MenuLocalTools::Handle(const Map& args, Result result) { impl_->Handle(args, std::move(result)); }
bool MenuLocalTools::AuthorizeScreenshotDirectory(const std::string& directory) { return impl_->AuthorizeScreenshotDirectory(directory); }
void MenuLocalTools::Hide() { impl_->Hide(); }
void MenuLocalTools::Reset() { impl_->Reset(); }
