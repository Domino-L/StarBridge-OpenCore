#ifndef RUNNER_SMALL_APPLICATION_ICON_H_
#define RUNNER_SMALL_APPLICATION_ICON_H_

#include <windows.h>
#include <atomic>
#include <string>
#include "resource.h"

// Taskbar/tray follow Windows mode, not the independently selectable app mode.
inline bool SmallIconUsesDarkForeground() noexcept {
  HIGHCONTRASTW contrast{};
  contrast.cbSize = sizeof(contrast);
  const auto light_system_background = []() {
    const COLORREF color = GetSysColor(COLOR_WINDOW);
    return 299 * GetRValue(color) + 587 * GetGValue(color) +
               114 * GetBValue(color) >= 128000;
  };
  if (SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0) &&
      (contrast.dwFlags & HCF_HIGHCONTRASTON)) {
    return light_system_background();
  }
  DWORD light = 1, bytes = sizeof(light);
  const auto result = RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &bytes);
  return result == ERROR_SUCCESS ? light != 0 : light_system_background();
}

// Runtime icon variant for the window, taskbar and tray only. The EXE
// resource, desktop shortcuts and the installer keep the default icon.
// 0 = default, 1 = xmas, 2 = halloween. Set from the Flutter side
// ("setIconVariant").
enum class SmallIconVariant : int { kDefault = 0, kXmas = 1, kHalloween = 2 };

inline std::atomic<int>& SmallIconVariantSlot() noexcept {
  static std::atomic<int> slot{0};
  return slot;
}

inline SmallIconVariant CurrentSmallIconVariant() noexcept {
  return static_cast<SmallIconVariant>(SmallIconVariantSlot().load());
}

// Unknown names fall back to the default icon rather than failing.
inline SmallIconVariant ParseSmallIconVariant(const std::string& name) noexcept {
  if (name == "xmas") return SmallIconVariant::kXmas;
  if (name == "halloween") return SmallIconVariant::kHalloween;
  return SmallIconVariant::kDefault;
}

// Returns true when the variant actually changed.
inline bool SetSmallIconVariant(SmallIconVariant variant) noexcept {
  return SmallIconVariantSlot().exchange(static_cast<int>(variant)) !=
         static_cast<int>(variant);
}

// Posted to the main window after a variant change so the taskbar icon
// (Win32Window) and the tray icon (ApplicationLifecycleBridge) both reload,
// exactly as they do after a Windows theme change.
inline UINT SmallIconVariantChangedMessage() noexcept {
  static const UINT message =
      RegisterWindowMessageW(L"StarBridge.SmallIconVariantChanged");
  return message;
}

inline int SmallIconResource(SmallIconVariant variant, bool dark_foreground) noexcept {
  switch (variant) {
    case SmallIconVariant::kXmas:
      return dark_foreground ? IDI_APP_ICON_XMAS_LIGHT_SURFACE
                             : IDI_APP_ICON_XMAS_DARK_SURFACE;
    case SmallIconVariant::kHalloween:
      return dark_foreground ? IDI_APP_ICON_HALLOWEEN_LIGHT_SURFACE
                             : IDI_APP_ICON_HALLOWEEN_DARK_SURFACE;
    case SmallIconVariant::kDefault:
    default:
      return dark_foreground ? IDI_APP_ICON_LIGHT_SURFACE
                             : IDI_APP_ICON_DARK_SURFACE;
  }
}

// Caller owns the returned non-shared HICON and must DestroyIcon it.
inline HICON LoadSmallApplicationIcon(int pixel_size, bool dark_foreground,
                                      SmallIconVariant variant) noexcept {
  auto load = [&](int resource) {
    return reinterpret_cast<HICON>(LoadImageW(
        GetModuleHandleW(nullptr), MAKEINTRESOURCEW(resource), IMAGE_ICON,
        pixel_size, pixel_size, LR_DEFAULTCOLOR));
  };
  auto icon = load(SmallIconResource(variant, dark_foreground));
  if (!icon && variant != SmallIconVariant::kDefault) {
    icon = load(SmallIconResource(SmallIconVariant::kDefault, dark_foreground));
  }
  if (!icon) icon = load(IDI_APP_ICON);
  return icon;
}

inline HICON LoadSmallApplicationIcon(int pixel_size, bool dark_foreground) noexcept {
  return LoadSmallApplicationIcon(pixel_size, dark_foreground,
                                  CurrentSmallIconVariant());
}

inline HICON LoadSmallApplicationIcon(int pixel_size) noexcept {
  return LoadSmallApplicationIcon(pixel_size, SmallIconUsesDarkForeground());
}

inline bool IsSmallIconThemeMessage(UINT message) noexcept {
  return message == WM_SETTINGCHANGE || message == WM_THEMECHANGED ||
         message == WM_DWMCOLORIZATIONCOLORCHANGED ||
         message == SmallIconVariantChangedMessage();
}

#endif
