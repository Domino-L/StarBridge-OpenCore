#include "application_lifecycle_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <shellapi.h>

#include <memory>
#include <string>

#include "resource.h"
#include "tray_surface_bridge.h"
#include "small_application_icon.h"

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 0x54;
constexpr UINT_PTR kStartupFallbackTimer = 0x5342;
constexpr UINT kStartupFallbackMilliseconds = 10000;
constexpr UINT kOpenCommand = 41001;
constexpr UINT kExitCommand = 41002;
constexpr UINT kTrayIconId = 1;
constexpr wchar_t kActivateInstanceMessage[] =
    L"StarBridge.Flutter.ActivateInstance.v1";

using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

const bool* ReadBool(const flutter::EncodableMap& values,
                     const char* name) {
  const auto iterator = values.find(flutter::EncodableValue(name));
  return iterator == values.end()
             ? nullptr
             : std::get_if<bool>(&iterator->second);
}

bool ReadNotificationText(const flutter::EncodableMap& values, const char* name,
                          size_t capacity, std::wstring& text) {
  const auto it = values.find(flutter::EncodableValue(name));
  if (it == values.end()) return false;
  const auto* value = std::get_if<std::string>(&it->second);
  if (!value || value->empty() || value->size() > 1024 ||
      value->find('\0') != std::string::npos) return false;
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      value->data(), static_cast<int>(value->size()), nullptr, 0);
  if (size <= 0 || static_cast<size_t>(size) >= capacity) return false;
  text.resize(size);
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value->data(),
      static_cast<int>(value->size()), text.data(), size) == size;
}

}  // namespace

class ApplicationLifecycleBridge::Impl {
 public:
  Impl(HWND window,
       flutter::BinaryMessenger* messenger,
       bool startup_launch)
      : window_(window),
        startup_launch_(startup_launch),
        taskbar_created_message_(RegisterWindowMessageW(L"TaskbarCreated")),
        activate_instance_message_(
            RegisterWindowMessageW(kActivateInstanceMessage)),
        channel_(std::make_unique<
                 flutter::MethodChannel<flutter::EncodableValue>>(
            messenger, "starbridge/application-lifecycle",
            &flutter::StandardMethodCodec::GetInstance())) {
    channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandleMethodCall(call, std::move(result));
        });
    tray_surface_ = std::make_unique<TraySurfaceBridge>(window_, messenger,
        [this]() { ShowMainWindow(); }, [this]() { ExitApplication(); },
        [this]() { ShowSystemTrayMenu(); });
  }

  ~Impl() { Shutdown(); }

  void OnFirstFrameReady() {
    if (startup_resolved_) {
      return;
    }
    if (startup_launch_ && !configured_) {
      SetTimer(window_, kStartupFallbackTimer, kStartupFallbackMilliseconds,
               nullptr);
      return;
    }
    startup_resolved_ = true;
    ShowMainWindow();
  }

  bool HandleCloseRequest() noexcept {
    if (allow_exit_ || !configured_ || shutting_down_) {
      return false;
    }
    if (!close_request_pending_) {
      close_request_pending_ = true;
      channel_->InvokeMethod(
          "closeRequested",
          std::make_unique<flutter::EncodableValue>());
    }
    return true;
  }

  bool HandleWindowMessage(UINT message,
                           WPARAM wparam,
                           LPARAM lparam) noexcept {
    if ((IsSmallIconThemeMessage(message) || message == WM_DPICHANGED ||
         message == WM_DISPLAYCHANGE) && tray_icon_added_) {
      RefreshTrayIcon();
    }
    if (message == taskbar_created_message_) {
      tray_icon_added_ = false;
      desktop_notification_active_ = false;
      if (keep_running_in_background_ || hidden_) {
        EnsureTrayIcon();
      }
      return true;
    }
    if (message == activate_instance_message_) {
      ShowMainWindow();
      return true;
    }
    if (message == WM_TIMER && wparam == kStartupFallbackTimer) {
      // Only one runner-owned timer exists. A delayed Host must never leave
      // the application invisible forever.
      KillTimer(window_, kStartupFallbackTimer);
      startup_resolved_ = true;
      ShowMainWindow();
      return true;
    }
    if (message != kTrayCallbackMessage) {
      return false;
    }

    switch (static_cast<UINT>(lparam)) {
      case WM_LBUTTONUP:
      case WM_RBUTTONUP:
      case WM_CONTEXTMENU:
        ShowTrayMenu();
        break;
      case NIN_BALLOONUSERCLICK:
        ShowMainWindow();
        break;
    }
    return true;
  }

  void Shutdown() noexcept {
    if (shutting_down_) {
      return;
    }
    shutting_down_ = true;
    tray_surface_.reset();
    KillTimer(window_, kStartupFallbackTimer);
    RemoveTrayIcon();
    if (channel_) {
      channel_->SetMethodCallHandler(nullptr);
      channel_.reset();
    }
  }

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<MethodResult> result) {
    const auto& method = call.method_name();
    if (method == "clearDesktopNotification") {
      ClearDesktopNotification();
      result->Success();
      return;
    }
    if (method == "showDesktopNotification") {
      const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
      std::wstring title, message;
      const bool* test = arguments ? ReadBool(*arguments, "test") : nullptr;
      if (!arguments || arguments->size() != 3 || !test ||
          !ReadNotificationText(*arguments, "title", 64, title) ||
          !ReadNotificationText(*arguments, "message", 256, message)) {
        result->Error("notification.invalid_arguments", "Invalid notification");
        return;
      }
      const auto now = GetTickCount64();
      if (shutting_down_ || (!*test && (GetForegroundWindow() == window_ ||
          (last_notification_tick_ != 0 && now - last_notification_tick_ < 10000)))) {
        result->Success(flutter::EncodableValue(false));
        return;
      }
      EnsureTrayIcon();
      NOTIFYICONDATAW data{};
      data.cbSize = sizeof(data);
      data.hWnd = window_;
      data.uID = kTrayIconId;
      // Do not queue stale notifications or play a second Windows sound.
      data.uFlags = NIF_INFO | NIF_REALTIME;
      data.dwInfoFlags = NIIF_INFO | NIIF_NOSOUND | NIIF_RESPECT_QUIET_TIME;
      wcscpy_s(data.szInfoTitle, title.c_str());
      wcscpy_s(data.szInfo, message.c_str());
      const bool submitted = tray_icon_added_ && Shell_NotifyIconW(NIM_MODIFY, &data) == TRUE;
      desktop_notification_active_ = submitted;
      if (submitted) last_notification_tick_ = now;
      else if (!keep_running_in_background_ && !hidden_) RemoveTrayIcon();
      result->Success(flutter::EncodableValue(submitted));
      return;
    }
    if (method == "configure") {
      const auto* arguments =
          std::get_if<flutter::EncodableMap>(call.arguments());
      if (!arguments) {
        result->Error("lifecycle.invalid_arguments",
                      "configure requires a map");
        return;
      }
      const bool* keep_running =
          ReadBool(*arguments, "keepRunningInBackground");
      const bool* start_minimized = ReadBool(*arguments, "startMinimized");
      if (!keep_running || !start_minimized) {
        result->Error("lifecycle.invalid_arguments",
                      "application behavior is incomplete");
        return;
      }
      keep_running_in_background_ = *keep_running;
      start_minimized_ = *start_minimized;
      configured_ = true;
      KillTimer(window_, kStartupFallbackTimer);
      if (startup_launch_ && start_minimized_ && !startup_resolved_) {
        HideToTray(false);
      } else if (!startup_resolved_) {
        ShowMainWindow();
      }
      startup_resolved_ = true;
      if (keep_running_in_background_ || hidden_) {
        EnsureTrayIcon();
      } else {
        RemoveTrayIcon();
      }
      result->Success();
      return;
    }
    if (method == "hideToTray") {
      bool show_hint = false;
      if (const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments())) {
        if (const bool* value = ReadBool(*arguments, "showHint")) {
          show_hint = *value;
        }
      }
      HideToTray(show_hint);
      result->Success();
      return;
    }
    if (method == "cancelCloseRequest") {
      close_request_pending_ = false;
      result->Success();
      return;
    }
    if (method == "exitApplication") {
      allow_exit_ = true;
      close_request_pending_ = false;
      result->Success();
      PostMessageW(window_, WM_CLOSE, 0, 0);
      return;
    }
    result->NotImplemented();
  }

  void HideToTray(bool show_hint) {
    EnsureTrayIcon();
    hidden_ = true;
    close_request_pending_ = false;
    ShowWindow(window_, SW_HIDE);
    if (show_hint) {
      NOTIFYICONDATAW data{};
      data.cbSize = sizeof(data);
      data.hWnd = window_;
      data.uID = kTrayIconId;
      data.uFlags = NIF_INFO;
      wcscpy_s(data.szInfoTitle, L"星海舰桥仍在运行");
      wcscpy_s(data.szInfo,
               L"应用已进入系统托盘。需要停止后台运行时，请选择“完全退出”。");
      data.dwInfoFlags = NIIF_INFO;
      Shell_NotifyIconW(NIM_MODIFY, &data);
    }
  }

  void ShowMainWindow() {
    if (tray_surface_) tray_surface_->Hide();
    ClearDesktopNotification();
    KillTimer(window_, kStartupFallbackTimer);
    hidden_ = false;
    close_request_pending_ = false;
    if (IsIconic(window_)) {
      ShowWindow(window_, SW_RESTORE);
    } else {
      ShowWindow(window_, SW_SHOW);
    }
    SetForegroundWindow(window_);
    if (!keep_running_in_background_) {
      RemoveTrayIcon();
    }
  }

  void EnsureTrayIcon() {
    if (tray_icon_added_) {
      return;
    }
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = window_;
    data.uID = kTrayIconId;
    data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    data.uCallbackMessage = kTrayCallbackMessage;
    const auto next_icon = LoadTrayIcon();
    if (!next_icon) return;
    data.hIcon = next_icon;
    wcscpy_s(data.szTip, L"星海舰桥");
    tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &data) == TRUE;
    if (tray_icon_added_) {
      if (tray_icon_) DestroyIcon(tray_icon_);
      tray_icon_ = next_icon;
    } else {
      DestroyIcon(next_icon);
    }
  }

  HICON LoadTrayIcon() const noexcept {
    const HWND taskbar = FindWindowW(L"Shell_TrayWnd", nullptr);
    UINT dpi = taskbar ? GetDpiForWindow(taskbar) : GetDpiForSystem();
    if (dpi == 0) dpi = 96;
    return LoadSmallApplicationIcon(GetSystemMetricsForDpi(SM_CXSMICON, dpi));
  }

  void RefreshTrayIcon() noexcept {
    const auto next_icon = LoadTrayIcon();
    if (!next_icon) return;
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = window_;
    data.uID = kTrayIconId;
    data.uFlags = NIF_ICON;
    data.hIcon = next_icon;
    if (Shell_NotifyIconW(NIM_MODIFY, &data)) {
      if (tray_icon_) DestroyIcon(tray_icon_);
      tray_icon_ = next_icon;
    } else {
      DestroyIcon(next_icon);
    }
  }

  void ClearDesktopNotification() {
    if (!desktop_notification_active_) return;
    desktop_notification_active_ = false;
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = window_;
    data.uID = kTrayIconId;
    data.uFlags = NIF_INFO;
    Shell_NotifyIconW(NIM_MODIFY, &data);
    if (!keep_running_in_background_ && !hidden_) RemoveTrayIcon();
  }

  void RemoveTrayIcon() {
    if (!tray_icon_added_) {
      if (tray_icon_) DestroyIcon(tray_icon_);
      tray_icon_ = nullptr;
      return;
    }
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = window_;
    data.uID = kTrayIconId;
    Shell_NotifyIconW(NIM_DELETE, &data);
    tray_icon_added_ = false;
    desktop_notification_active_ = false;
    if (tray_icon_) DestroyIcon(tray_icon_);
    tray_icon_ = nullptr;
  }

  void ShowTrayMenu() {
    POINT point{};
    if (!GetCursorPos(&point)) return;
    const bool keyboard = (GetKeyState(VK_APPS) & 0x8000) != 0 ||
        ((GetKeyState(VK_SHIFT) & 0x8000) != 0 && (GetKeyState(VK_F10) & 0x8000) != 0);
    if (tray_surface_ && tray_surface_->Show(point, keyboard)) return;
    ShowSystemTrayMenu();
  }
  void ExitApplication() {
    allow_exit_ = true; close_request_pending_ = false;
    PostMessageW(window_, WM_CLOSE, 0, 0);
  }
  void ShowSystemTrayMenu() {
    POINT point{};
    if (!GetCursorPos(&point)) {
      return;
    }
    HMENU menu = CreatePopupMenu();
    if (!menu) {
      return;
    }
    AppendMenuW(menu, MF_STRING, kOpenCommand, L"打开星海舰桥");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kExitCommand, L"完全退出");
    SetForegroundWindow(window_);
    const UINT command = TrackPopupMenu(
        menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0, window_,
        nullptr);
    DestroyMenu(menu);
    if (command == kOpenCommand) {
      ShowMainWindow();
    } else if (command == kExitCommand) {
      ExitApplication();
    }
  }

  HWND window_ = nullptr;
  bool startup_launch_ = false;
  bool configured_ = false;
  bool startup_resolved_ = false;
  bool keep_running_in_background_ = false;
  bool start_minimized_ = false;
  bool hidden_ = false;
  bool close_request_pending_ = false;
  bool allow_exit_ = false;
  bool tray_icon_added_ = false;
  HICON tray_icon_ = nullptr;
  bool desktop_notification_active_ = false;
  ULONGLONG last_notification_tick_ = 0;
  bool shutting_down_ = false;
  UINT taskbar_created_message_ = 0;
  UINT activate_instance_message_ = 0;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<TraySurfaceBridge> tray_surface_;
};

ApplicationLifecycleBridge::ApplicationLifecycleBridge(
    HWND window,
    flutter::BinaryMessenger* messenger,
    bool startup_launch)
    : impl_(std::make_unique<Impl>(window, messenger, startup_launch)) {}

ApplicationLifecycleBridge::~ApplicationLifecycleBridge() = default;

void ApplicationLifecycleBridge::OnFirstFrameReady() {
  impl_->OnFirstFrameReady();
}

bool ApplicationLifecycleBridge::HandleCloseRequest() noexcept {
  return impl_->HandleCloseRequest();
}

bool ApplicationLifecycleBridge::HandleWindowMessage(
    UINT message,
    WPARAM wparam,
    LPARAM lparam) noexcept {
  return impl_->HandleWindowMessage(message, wparam, lparam);
}

void ApplicationLifecycleBridge::Shutdown() noexcept { impl_->Shutdown(); }
