#ifndef RUNNER_MENU_IMAGE_NATIVE_H_
#define RUNNER_MENU_IMAGE_NATIVE_H_
#include <windows.h>
#include <gdiplus.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

// Pure bounded image transforms and visibility policy shared by the native
// tool and hidden synthetic fixtures. No files, capture or clipboard writes.
namespace menu_image {
struct Edit {
  double left = 0, top = 0, right = 1, bottom = 1;
  int turns = 0;
  bool Valid() const {
    return std::isfinite(left) && std::isfinite(top) && std::isfinite(right) &&
      std::isfinite(bottom) && left >= 0 && top >= 0 && right <= 1 && bottom <= 1 &&
      left < right && top < bottom && turns >= 0 && turns <= 3;
  }
};
inline bool Bounded(UINT width, UINT height, UINT edge = 16384, uint64_t pixels = 64000000) {
  return width && height && width <= edge && height <= edge &&
    static_cast<uint64_t>(width) * height <= pixels;
}
inline bool PngSize(const std::vector<uint8_t>& bytes, UINT& width, UINT& height) {
  static constexpr uint8_t signature[]{137,80,78,71,13,10,26,10};
  if (bytes.size() < 33 || bytes.size() > 32 * 1024 * 1024 ||
      memcmp(bytes.data(), signature, sizeof(signature)) ||
      bytes[8] || bytes[9] || bytes[10] || bytes[11] != 13 ||
      memcmp(bytes.data() + 12, "IHDR", 4)) return false;
  const auto number = [&bytes](size_t offset) {
    return static_cast<UINT>((static_cast<uint32_t>(bytes[offset]) << 24) |
      (static_cast<uint32_t>(bytes[offset+1]) << 16) |
      (static_cast<uint32_t>(bytes[offset+2]) << 8) | bytes[offset+3]);
  };
  width = number(16); height = number(20); return Bounded(width, height);
}
inline std::unique_ptr<Gdiplus::Bitmap> Edited(Gdiplus::Bitmap& source, const Edit& edit) {
  if (!edit.Valid() || source.GetLastStatus() != Gdiplus::Ok ||
      !Bounded(source.GetWidth(), source.GetHeight())) return nullptr;
  std::unique_ptr<Gdiplus::Bitmap> rotated(source.Clone(0, 0,
      static_cast<INT>(source.GetWidth()), static_cast<INT>(source.GetHeight()), PixelFormat32bppARGB));
  if (!rotated || rotated->GetLastStatus() != Gdiplus::Ok) return nullptr;
  const Gdiplus::RotateFlipType rotations[]{Gdiplus::RotateNoneFlipNone,
    Gdiplus::Rotate90FlipNone, Gdiplus::Rotate180FlipNone, Gdiplus::Rotate270FlipNone};
  if (rotated->RotateFlip(rotations[edit.turns]) != Gdiplus::Ok) return nullptr;
  const int width = static_cast<int>(rotated->GetWidth()), height = static_cast<int>(rotated->GetHeight());
  const int left = static_cast<int>(std::floor(edit.left * width));
  const int top = static_cast<int>(std::floor(edit.top * height));
  const int right = std::min(width, static_cast<int>(std::ceil(edit.right * width)));
  const int bottom = std::min(height, static_cast<int>(std::ceil(edit.bottom * height)));
  if (left >= right || top >= bottom) return nullptr;
  return std::unique_ptr<Gdiplus::Bitmap>(rotated->Clone(left, top, right-left, bottom-top, PixelFormat32bppARGB));
}
inline bool IsGame(const std::wstring& path) {
  const auto slash = path.find_last_of(L"\\/");
  return _wcsicmp(path.substr(slash == std::wstring::npos ? 0 : slash+1).c_str(), L"StarCitizen.exe") == 0;
}
inline bool PinVisible(bool pinned, bool menu, bool capturing, bool game) {
  return pinned && !menu && !capturing && game;
}
constexpr DWORD kPinStyle = WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
// CF_DIBV5 stores straight BGRA; UpdateLayeredWindow uses premultiplied BGRA.
inline std::vector<uint8_t> Pixels(Gdiplus::Bitmap& image, bool premultiplied) {
  if (!Bounded(image.GetWidth(), image.GetHeight())) return {};
  const UINT width = image.GetWidth(), height = image.GetHeight();
  Gdiplus::Rect rect(0, 0, static_cast<INT>(width), static_cast<INT>(height));
  Gdiplus::BitmapData data{};
  if (image.LockBits(&rect, Gdiplus::ImageLockModeRead,
      premultiplied ? PixelFormat32bppPARGB : PixelFormat32bppARGB, &data) != Gdiplus::Ok) return {};
  std::vector<uint8_t> result(static_cast<size_t>(width) * height * 4);
  for (UINT y = 0; y < height; ++y)
    memcpy(result.data() + static_cast<size_t>(y) * width * 4,
      static_cast<const uint8_t*>(data.Scan0) + static_cast<ptrdiff_t>(y) * data.Stride, static_cast<size_t>(width) * 4);
  image.UnlockBits(&data); return result;
}
inline std::vector<uint8_t> ClipboardDib(Gdiplus::Bitmap& image) {
  const auto pixels = Pixels(image, false);
  if (pixels.empty()) return {};
  BITMAPV5HEADER header{};
  header.bV5Size = sizeof(header); header.bV5Width = static_cast<LONG>(image.GetWidth());
  header.bV5Height = -static_cast<LONG>(image.GetHeight()); header.bV5Planes = 1;
  header.bV5BitCount = 32; header.bV5Compression = BI_BITFIELDS;
  header.bV5SizeImage = static_cast<DWORD>(pixels.size());
  header.bV5RedMask = 0x00ff0000; header.bV5GreenMask = 0x0000ff00;
  header.bV5BlueMask = 0x000000ff; header.bV5AlphaMask = 0xff000000;
  header.bV5CSType = LCS_sRGB; header.bV5Intent = LCS_GM_IMAGES;
  std::vector<uint8_t> result(sizeof(header) + pixels.size());
  memcpy(result.data(), &header, sizeof(header));
  memcpy(result.data() + sizeof(header), pixels.data(), pixels.size()); return result;
}
}
#endif
