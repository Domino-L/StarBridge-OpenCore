#ifndef RUNNER_MENU_SCREENSHOT_EXPORT_H_
#define RUNNER_MENU_SCREENSHOT_EXPORT_H_
#include "menu_image_native.h"
#include <flutter/encodable_value.h>
#include <wrl.h>
#include <optional>

// Export policy and bounded in-memory encoding. No paths, files or clipboard.
struct MenuScreenshotExport {
  bool jpeg = false;
  int quality = 90;
  static std::optional<MenuScreenshotExport> Parse(const flutter::EncodableValue& value) {
    using V = flutter::EncodableValue;
    const auto map = std::get_if<flutter::EncodableMap>(&value);
    if (!map || map->size() != 2) return {};
    const auto f = map->find(V("format")), q = map->find(V("jpegQuality"));
    if (f == map->end() || q == map->end()) return {};
    const auto format = std::get_if<std::string>(&f->second);
    int64_t quality = 0;
    if (const auto number = std::get_if<int32_t>(&q->second)) quality = *number;
    else if (const auto wideNumber = std::get_if<int64_t>(&q->second)) quality = *wideNumber;
    if (!format || (*format != "png" && *format != "jpeg") || quality < 50 || quality > 100) return {};
    return MenuScreenshotExport{*format == "jpeg", static_cast<int>(quality)};
  }
  bool MatchesExtension(const std::wstring& extension) const {
    return jpeg ? _wcsicmp(extension.c_str(), L".jpg") == 0 || _wcsicmp(extension.c_str(), L".jpeg") == 0
                : _wcsicmp(extension.c_str(), L".png") == 0;
  }
  const wchar_t* Extension() const { return jpeg ? L"jpg" : L"png"; }
};
inline std::vector<uint8_t> MenuEncodeScreenshot(Gdiplus::Bitmap& image, MenuScreenshotExport options = {}) {
  if (image.GetLastStatus() != Gdiplus::Ok || !menu_image::Bounded(image.GetWidth(), image.GetHeight()) ||
      options.quality < 50 || options.quality > 100) return {};
  UINT count = 0, size = 0;
  if (Gdiplus::GetImageEncodersSize(&count, &size) != Gdiplus::Ok || !size) return {};
  std::vector<uint8_t> info(size);
  auto* codecs = reinterpret_cast<Gdiplus::ImageCodecInfo*>(info.data());
  if (Gdiplus::GetImageEncoders(count, size, codecs) != Gdiplus::Ok) return {};
  CLSID codec{}; bool found = false;
  for (UINT i = 0; i < count; ++i) {
    if (wcscmp(codecs[i].MimeType, options.jpeg ? L"image/jpeg" : L"image/png") == 0) {
      codec = codecs[i].Clsid; found = true; break;
    }
  }
  Microsoft::WRL::ComPtr<IStream> stream;
  if (!found || FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) return {};
  std::unique_ptr<Gdiplus::Bitmap> opaque;
  Gdiplus::Bitmap* output = &image;
  Gdiplus::EncoderParameters parameters{};
  ULONG quality = static_cast<ULONG>(options.quality);
  if (options.jpeg) {
    // JPEG has no alpha. Flatten to white explicitly; never mutate the preview.
    opaque = std::make_unique<Gdiplus::Bitmap>(image.GetWidth(), image.GetHeight(), PixelFormat32bppRGB);
    Gdiplus::Graphics graphics(opaque.get());
    if (opaque->GetLastStatus() != Gdiplus::Ok || graphics.Clear(Gdiplus::Color(255, 255, 255, 255)) != Gdiplus::Ok ||
        graphics.DrawImage(&image, 0, 0, static_cast<INT>(image.GetWidth()), static_cast<INT>(image.GetHeight())) != Gdiplus::Ok) return {};
    output = opaque.get();
    parameters.Count = 1; parameters.Parameter[0].Guid = Gdiplus::EncoderQuality;
    parameters.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
    parameters.Parameter[0].NumberOfValues = 1; parameters.Parameter[0].Value = &quality;
  }
  if (output->Save(stream.Get(), &codec, options.jpeg ? &parameters : nullptr) != Gdiplus::Ok) return {};
  STATSTG stat{};
  if (FAILED(stream->Stat(&stat, STATFLAG_NONAME)) || !stat.cbSize.QuadPart || stat.cbSize.QuadPart > 32 * 1024 * 1024) return {};
  std::vector<uint8_t> bytes(static_cast<size_t>(stat.cbSize.QuadPart));
  LARGE_INTEGER zero{}; if (FAILED(stream->Seek(zero, STREAM_SEEK_SET, nullptr))) return {};
  ULONG read = 0;
  if (FAILED(stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &read)) || read != bytes.size()) return {};
  return bytes;
}
#endif
