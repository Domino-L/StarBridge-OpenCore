#ifndef RUNNER_SMALL_APPLICATION_ICON_H_
#define RUNNER_SMALL_APPLICATION_ICON_H_

#include <windows.h>
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

// Caller owns the returned non-shared HICON and must DestroyIcon it.
inline HICON LoadSmallApplicationIcon(int pixel_size, bool dark_foreground) noexcept {
  const int resource = dark_foreground
      ? IDI_APP_ICON_LIGHT_SURFACE : IDI_APP_ICON_DARK_SURFACE;
  auto icon = reinterpret_cast<HICON>(LoadImageW(
      GetModuleHandleW(nullptr), MAKEINTRESOURCEW(resource), IMAGE_ICON,
      pixel_size, pixel_size, LR_DEFAULTCOLOR));
  if (!icon) {
    icon = reinterpret_cast<HICON>(LoadImageW(
        GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
        pixel_size, pixel_size, LR_DEFAULTCOLOR));
  }
  return icon;
}

inline HICON LoadSmallApplicationIcon(int pixel_size) noexcept {
  return LoadSmallApplicationIcon(pixel_size, SmallIconUsesDarkForeground());
}

inline bool IsSmallIconThemeMessage(UINT message) noexcept {
  return message == WM_SETTINGCHANGE || message == WM_THEMECHANGED ||
         message == WM_DWMCOLORIZATIONCOLORCHANGED;
}

#endif
