#ifndef RUNNER_MENU_REFERENCE_DECODE_H_
#define RUNNER_MENU_REFERENCE_DECODE_H_
#include "menu_screenshot_export.h"

inline constexpr wchar_t kMenuReferenceFilter[] = L"*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff";
// Reference images are static, as in the WPF BitmapImage consumer. Flatten the
// initial frame/page through the existing bounded PNG encoder before Dart sees it.
inline std::vector<uint8_t> MenuDecodeReference(IStream* stream) {
  if (!stream) return {};
  Gdiplus::Bitmap bitmap(stream);
  return MenuEncodeScreenshot(bitmap);
}
#endif
