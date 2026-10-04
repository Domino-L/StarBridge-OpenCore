#include "menu_local_tools.h"
#include "menu_image_native.h"
#include "menu_reference_identity.h"
#include "menu_reference_decode.h"
#include "menu_screenshot_export.h"
#include "menu_screenshot_storage.h"
#include "menu_screenshot_capture.h"
#include <wrl.h>
#include <fstream>
#include <cstdio>
#include <limits>
#include <stdexcept>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
struct Response { Value value; std::string error; int replies = 0; };
class Result : public flutter::MethodResult<Value> {
 public:
  explicit Result(Response& response) : response_(response) {}
 protected:
  void SuccessInternal(const Value* value) override { ++response_.replies; if (value) response_.value = *value; }
  void ErrorInternal(const std::string& error, const std::string&, const Value*) override { ++response_.replies; response_.error = error; }
  void NotImplementedInternal() override { ++response_.replies; response_.error = "notImplemented"; }
 private:
  Response& response_;
};
Response Call(MenuLocalTools& tools, const std::string& action, Map args = {}) {
  Response response; args[Value("action")] = Value(action);
  tools.Handle(args, std::make_unique<Result>(response)); return response;
}
std::vector<uint8_t> Encode(Gdiplus::Bitmap& image, const wchar_t* mime = L"image/png") {
  UINT count = 0, size = 0; Gdiplus::GetImageEncodersSize(&count, &size);
  std::vector<uint8_t> codecs(size);
  auto* info = reinterpret_cast<Gdiplus::ImageCodecInfo*>(codecs.data());
  Gdiplus::GetImageEncoders(count, size, info);
  CLSID png{};
  for (UINT i = 0; i < count; ++i) if (wcscmp(info[i].MimeType, mime) == 0) png = info[i].Clsid;
  Microsoft::WRL::ComPtr<IStream> stream; CreateStreamOnHGlobal(nullptr, TRUE, &stream);
  image.Save(stream.Get(), &png);
  STATSTG stat{}; stream->Stat(&stat, STATFLAG_NONAME);
  std::vector<uint8_t> bytes(static_cast<size_t>(stat.cbSize.QuadPart));
  LARGE_INTEGER zero{}; stream->Seek(zero, STREAM_SEEK_SET, nullptr);
  ULONG read = 0; stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &read); return bytes;
}
Map Edit(double left = 0, double top = 0, double right = 1, double bottom = 1, int turns = 0) {
  return Map{{Value("cropLeft"), Value(left)}, {Value("cropTop"), Value(top)},
    {Value("cropRight"), Value(right)}, {Value("cropBottom"), Value(bottom)}, {Value("turns"), Value(turns)}};
}
bool ExportPixel(const std::vector<uint8_t>& bytes, bool jpeg, UINT width, UINT height, Gdiplus::Color& pixel) {
  Microsoft::WRL::ComPtr<IStream> stream;
  if (bytes.empty() || FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) return false;
  ULONG written = 0;
  if (FAILED(stream->Write(bytes.data(), static_cast<ULONG>(bytes.size()), &written)) || written != bytes.size()) return false;
  LARGE_INTEGER zero{}; stream->Seek(zero, STREAM_SEEK_SET, nullptr);
  Gdiplus::Bitmap decoded(stream.Get()); GUID format{};
  return decoded.GetLastStatus() == Gdiplus::Ok && decoded.GetWidth() == width && decoded.GetHeight() == height &&
      decoded.GetRawFormat(&format) == Gdiplus::Ok && IsEqualGUID(format, jpeg ? Gdiplus::ImageFormatJPEG : Gdiplus::ImageFormatPNG) &&
      decoded.GetPixel(0, 0, &pixel) == Gdiplus::Ok;
}
bool Size(const Response& response, UINT width, UINT height) {
  const auto* bytes = std::get_if<std::vector<uint8_t>>(&response.value);
  UINT w = 0, h = 0;
  return response.error.empty() && bytes && menu_image::PngSize(*bytes, w, h) && w == width && h == height;
}
std::vector<uint8_t> ReadFileBytes(const std::wstring& path) {
  std::ifstream file(std::filesystem::path(path), std::ios::binary);
  return {std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
}
HWND FixturePin() {
  HWND candidate = nullptr;
  while ((candidate = FindWindowExW(nullptr, candidate, L"StarBridgeMenuReferencePin", nullptr))) {
    DWORD process = 0; GetWindowThreadProcessId(candidate, &process);
    if (process == GetCurrentProcessId()) return candidate;
  }
  return nullptr;
}
}
int main() {
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  ULONG_PTR token = 0; Gdiplus::GdiplusStartupInput input; Gdiplus::GdiplusStartup(&token, &input, nullptr);
  int failed = 0, total = 0;
  const auto check = [&](bool pass, const char* label) { ++total; printf("%s|%s\n", pass ? "PASS" : "FAIL", label); if (!pass) ++failed; };
  {
    check(std::wstring(kMenuReferenceFilter) == L"*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff", "picker exposes all WPF reference formats");
    Gdiplus::Bitmap reference(4, 2, PixelFormat32bppARGB);
    { Gdiplus::Graphics graphics(&reference); graphics.Clear(Gdiplus::Color(255, 255, 0, 0)); }
    for (const auto* mime : {L"image/png", L"image/jpeg", L"image/bmp", L"image/gif", L"image/tiff"}) {
      const auto encoded = Encode(reference, mime);
      Microsoft::WRL::ComPtr<IStream> stream;
      CreateStreamOnHGlobal(nullptr, TRUE, &stream);
      ULONG written = 0; stream->Write(encoded.data(), static_cast<ULONG>(encoded.size()), &written);
      LARGE_INTEGER zero{}; stream->Seek(zero, STREAM_SEEK_SET, nullptr);
      Gdiplus::Color pixel;
      check(!encoded.empty() && ExportPixel(MenuDecodeReference(stream.Get()), false, 4, 2, pixel) &&
          pixel.GetR() > 240 && pixel.GetG() < 16 && pixel.GetB() < 16,
          "selected reference format decodes to bounded PNG with expected pixels");
    }
    check(MenuDecodeReference(nullptr).empty(), "missing reference stream fails closed");
    Microsoft::WRL::ComPtr<IStream> emptyReference; CreateStreamOnHGlobal(nullptr, TRUE, &emptyReference);
    check(MenuDecodeReference(emptyReference.Get()).empty(), "corrupt reference stream fails closed");
    check(MenuCaptureHidesMenu(Map{}).value_or(false), "legacy captures hide menu by default");
    for (bool hide : {false, true}) {
      check(MenuCaptureHidesMenu(Map{{Value("hideMenu"), Value(hide)}}) == hide, "capture accepts explicit visibility");
      std::vector<std::string> events;
      const auto bytes = RunMenuCapture(hide,
          [&](bool hidden) { events.push_back(hidden ? "hide" : "keep"); },
          [&] { events.push_back("release"); },
          [&] { events.push_back("capture"); return std::vector<uint8_t>{1, 2}; });
      check(bytes.size() == 2 && events == std::vector<std::string>{hide ? "hide" : "keep", "capture", "release"},
          "capture visibility uses one capture and releases presentation");
    }
    for (const auto& bad : {Value(), Value(0), Value("false"), Value(1.0)})
      check(!MenuCaptureHidesMenu(Map{{Value("hideMenu"), bad}}), "invalid capture visibility rejected");
    check(!MenuCaptureHidesMenu(Map{{Value("path"), Value("forbidden")}}), "capture rejects extra fields");
    bool released = false;
    try {
      RunMenuCapture(true, [](bool) {}, [&] { released = true; }, []() -> int { throw std::runtime_error("synthetic capture failure"); });
    } catch (const std::runtime_error&) { }
    check(released, "capture failure releases presentation lease");
  }
  {
    const auto temp = std::filesystem::canonical(std::filesystem::temp_directory_path());
    GUID id{}; CoCreateGuid(&id); wchar_t suffix[40]{}; StringFromGUID2(id, suffix, 40);
    const auto root = temp / (std::wstring(L"starbridge-screenshot-fixture-") + suffix);
    // Cleanup is confined to a fresh fixture-owned child of the system temp.
    if (root.parent_path() != temp || root.filename().wstring().rfind(L"starbridge-screenshot-fixture-", 0) != 0 || std::filesystem::exists(root)) return 2;
    const auto directory = (root / L"screenshots").wstring();
    Gdiplus::Bitmap image(4, 2, PixelFormat32bppARGB); image.SetPixel(0, 0, Gdiplus::Color(255, 20, 80, 140));
    const auto png = MenuEncodeScreenshot(image), jpeg = MenuEncodeScreenshot(image, {true, 75});
    SYSTEMTIME time{2026,10,0,4,12,34,56,789};
    const auto first = menu_screenshot::SaveUnique(directory, png, false, time, [] { return true; });
    const auto second = menu_screenshot::SaveUnique(directory, png, false, time, [] { return true; });
    check(!first.empty() && std::filesystem::path(first).filename() == L"StarBridge_20261004_123456_789.png", "direct export creates explicit destination with capture-time filename");
    check(!second.empty() && std::filesystem::path(second).filename() == L"StarBridge_20261004_123456_789_02.png" && ReadFileBytes(first) == png,
        "filename collision produces suffix without replacing original");
    const auto jpg = menu_screenshot::SaveUnique(directory, jpeg, true, time, [] { return true; });
    Gdiplus::Color decoded;
    check(!jpg.empty() && std::filesystem::path(jpg).extension() == L".jpg" && ExportPixel(ReadFileBytes(jpg), true, 4, 2, decoded), "direct JPEG file contains the actual JPEG encoding");
    check(!menu_screenshot::WriteAtomic(first, jpeg, [] { return true; }, false) && ReadFileBytes(first) == png, "atomic no-replace protects an existing screenshot");
    check(menu_screenshot::WriteAtomic(first, jpeg, [] { return true; }, true) && ReadFileBytes(first) == jpeg, "explicit save-as reuses atomic replacement implementation");
    const auto cancelled = (root / L"cancelled").wstring();
    check(menu_screenshot::SaveUnique(cancelled, png, false, time, [] { return false; }).empty() && !std::filesystem::exists(cancelled), "retired export creates no destination");
    int checks = 0;
    check(menu_screenshot::SaveUnique(cancelled, png, false, time, [&] { return ++checks < 5; }).empty() && std::filesystem::is_empty(cancelled), "retired commit preserves empty destination and removes only its temporary file");
    check(menu_screenshot::SaveUnique(L"relative", png, false, time, [] { return true; }).empty(), "relative direct destination denied");
    check(!menu_screenshot::ValidDirectory(L"\\\\?\\C:\\fixture") && !menu_screenshot::ValidDirectory(L"C:\\fixture\\..\\elsewhere"), "device and traversal destinations denied");
    const auto blocked = (root / L"blocked").wstring();
    check(menu_screenshot::WriteAtomic(blocked, png, [] { return true; }, false) &&
        menu_screenshot::SaveUnique(blocked, png, false, time, [] { return true; }).empty() && ReadFileBytes(blocked) == png, "unwritable non-directory never replaces original or falls back elsewhere");
    std::filesystem::remove_all(root);
  }
  {
    const auto policy = [](Value format, Value quality) { return Map{{Value("format"), format}, {Value("jpegQuality"), quality}}; };
    for (const auto& format : {"png", "jpeg"}) for (const int quality : {50, 90, 100}) {
      const auto parsed = MenuScreenshotExport::Parse(Value(policy(Value(format), Value(quality))));
      check(parsed && parsed->quality == quality && parsed->jpeg == (std::string(format) == "jpeg"), "strict export options accept bounded formats and quality");
    }
    check(MenuScreenshotExport::Parse(Value(policy(Value("jpeg"), Value(int64_t(75))))).has_value(), "codec accepts native int64 quality");
    for (const auto& value : {Value(49), Value(101), Value(90.0), Value(true), Value("90"), Value()})
      check(!MenuScreenshotExport::Parse(Value(policy(Value("png"), value))), "invalid quality rejected before native dialog");
    auto extra = policy(Value("png"), Value(90)); extra[Value("path")] = Value("synthetic.png");
    check(!MenuScreenshotExport::Parse(Value(extra)) && !MenuScreenshotExport::Parse(Value(Map{})) &&
        !MenuScreenshotExport::Parse(Value(policy(Value("gif"), Value(90)))), "unknown export keys formats and partial policies fail closed");
    check(MenuScreenshotExport{}.MatchesExtension(L".PNG") && !MenuScreenshotExport{}.MatchesExtension(L".jpg") &&
        MenuScreenshotExport{true, 90}.MatchesExtension(L".JPEG") && MenuScreenshotExport{true, 90}.MatchesExtension(L".jpg") &&
        !MenuScreenshotExport{true, 90}.MatchesExtension(L".png"), "extension must agree with actual encoding");
    Gdiplus::Bitmap alpha(16, 16, PixelFormat32bppARGB);
    Gdiplus::Graphics transparent(&alpha); transparent.Clear(Gdiplus::Color(0, 0, 0, 0));
    const auto png = MenuEncodeScreenshot(alpha), jpeg = MenuEncodeScreenshot(alpha, {true, 75});
    Gdiplus::Color pixel;
    check(ExportPixel(png, false, 16, 16, pixel) && pixel.GetA() == 0, "PNG retains original alpha and dimensions");
    check(jpeg.size() > 2 && jpeg[0] == 0xff && jpeg[1] == 0xd8 && ExportPixel(jpeg, true, 16, 16, pixel) &&
        pixel.GetA() == 255 && pixel.GetR() > 250 && pixel.GetG() > 250 && pixel.GetB() > 250, "JPEG is real JPEG with transparent pixels flattened to white");
    alpha.GetPixel(0, 0, &pixel);
    check(pixel.GetA() == 0 && MenuEncodeScreenshot(alpha, {true, 49}).empty(), "encoding neither mutates original nor accepts invalid quality");
    Gdiplus::Bitmap noise(64, 64, PixelFormat32bppARGB);
    for (int y = 0; y < 64; ++y) for (int x = 0; x < 64; ++x)
      noise.SetPixel(x, y, Gdiplus::Color(255, static_cast<BYTE>((x*37+y*17)%256), static_cast<BYTE>((x*11+y*43)%256), static_cast<BYTE>((x*53+y*7)%256)));
    const auto low = MenuEncodeScreenshot(noise, {true, 50}), high = MenuEncodeScreenshot(noise, {true, 100});
    check(!low.empty() && high.size() > low.size() && high != low, "JPEG quality actually changes encoded output");
  }
  {
    wchar_t directory[MAX_PATH]{}, first[MAX_PATH]{}, second[MAX_PATH]{};
    const bool allocated = GetTempPathW(MAX_PATH, directory) &&
        GetTempFileNameW(directory, L"sbr", 0, first) && GetTempFileNameW(directory, L"sbr", 0, second);
    HANDLE a = allocated ? CreateFileW(first, GENERIC_READ|GENERIC_WRITE, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr) : INVALID_HANDLE_VALUE;
    HANDLE b = allocated ? CreateFileW(second, GENERIC_READ|GENERIC_WRITE, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr) : INVALID_HANDLE_VALUE;
    DWORD written = 0; const char data[]{1,2,3};
    if (a != INVALID_HANDLE_VALUE) { WriteFile(a,data,3,&written,nullptr); FlushFileBuffers(a); }
    if (b != INVALID_HANDLE_VALUE) { WriteFile(b,data,3,&written,nullptr); FlushFileBuffers(b); }
    const auto keyA = menu_image::ReferenceKey(a), keyB = menu_image::ReferenceKey(b);
    check(allocated && keyA && keyB && *keyA != *keyB, "identical bytes in separate real files keep different native identities");
    if (a != INVALID_HANDLE_VALUE) { CloseHandle(a); a = CreateFileW(first,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr); }
    const auto reopened = menu_image::ReferenceKey(a);
    if (a != INVALID_HANDLE_VALUE) { CloseHandle(a); a = CreateFileW(first,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr); }
    check(reopened && menu_image::ReferenceKey(a) == reopened, "reopening the unchanged file yields stable version metadata");
    if (a != INVALID_HANDLE_VALUE) { CloseHandle(a); a = CreateFileW(first,GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr); }
    if (a != INVALID_HANDLE_VALUE) { SetFilePointer(a,0,nullptr,FILE_END); WriteFile(a,data,3,&written,nullptr); FlushFileBuffers(a); }
    check(reopened && menu_image::ReferenceKey(a) != reopened, "modified file is not mistaken for the remembered version");
    if (a != INVALID_HANDLE_VALUE) CloseHandle(a);
    if (b != INVALID_HANDLE_VALUE) CloseHandle(b);
    if (*first) DeleteFileW(first); if (*second) DeleteFileW(second);
    menu_image::ReferenceIdentityCache ids;
    check(!ids.Resolve(std::nullopt) && !menu_image::ReferenceKey(INVALID_HANDLE_VALUE), "unknown handle never invents a stable identity");
    if (reopened) {
      const auto tokenA = ids.Resolve(reopened), tokenB = ids.Resolve(keyB);
      check(tokenA && tokenB && *tokenA != *tokenB && tokenA->size() == 38 && ids.Resolve(reopened) == tokenA,
          "opaque random tokens distinguish files while reselecting restores identity");
      for (DWORD n = 1; n <= 32; ++n) { auto key = *reopened; key[2] += n; ids.Resolve(key); }
      check(ids.Size() == 32 && ids.Resolve(reopened) != tokenA, "identity retention is bounded and evicted entries get a new token");
      const auto before = ids.Resolve(reopened); ids.Clear();
      check(ids.Size() == 0 && ids.Resolve(reopened) != before, "account reset cannot reissue a previous image identity");
    }
  }
  {
    Gdiplus::Bitmap image(4, 2, PixelFormat32bppARGB);
    for (int y = 0; y < 2; ++y) for (int x = 0; x < 4; ++x)
      image.SetPixel(x, y, Gdiplus::Color(128, static_cast<BYTE>(40*x), static_cast<BYTE>(100*y), 10));
    auto bytes = Encode(image);
    UINT width = 0, height = 0;
    check(menu_image::PngSize(bytes, width, height) && width == 4 && height == 2, "bounded synthetic PNG header");
    check(!menu_image::PngSize({}, width, height), "empty PNG rejected");
    auto corrupt = bytes; corrupt[16] = 127;
    check(!menu_image::PngSize(corrupt, width, height), "oversized decoder dimensions rejected before decode");
    check(!menu_image::Bounded(4096,4096,4096,16000000) && menu_image::Bounded(4000,4000,4096,16000000), "pin edge and pixel limits");
    menu_image::Edit edit; edit.turns = 1; edit.left = .5;
    auto crop = menu_image::Edited(image, edit);
    check(crop && crop->GetWidth() == 1 && crop->GetHeight() == 4, "crop coordinates are applied after clockwise rotation");
    Gdiplus::Color color;
    if (crop) crop->GetPixel(0, 0, &color);
    check(color.GetA() == 128 && color.GetG() == 0, "rotated crop preserves alpha and expected pixel");
    check(image.GetWidth() == 4 && image.GetHeight() == 2, "original screenshot not mutated");
    const auto dib = menu_image::ClipboardDib(image);
    BITMAPV5HEADER header{}; memcpy(&header, dib.data(), sizeof(header));
    check(header.bV5Width == 4 && header.bV5Height == -2 && header.bV5AlphaMask == 0xff000000 && dib.size() == sizeof(header)+32, "clipboard payload is top-down alpha DIBV5 without touching clipboard");
    const auto straight = menu_image::Pixels(image, false), premultiplied = menu_image::Pixels(image, true);
    check(straight[6] == 40 && premultiplied[6] == 20, "layered window gets premultiplied rather than clipboard straight alpha");
    check(menu_image::IsGame(L"C:\\Game\\StarCitizen.exe") && menu_image::IsGame(L"starcitizen.EXE") &&
      !menu_image::IsGame(L"C:\\StarCitizen.exe\\other.exe") && !menu_image::IsGame(L"FakeStarCitizen.exe"), "foreground process exact basename");
    check(menu_image::PinVisible(true,false,false,true) && !menu_image::PinVisible(true,true,false,true) &&
      !menu_image::PinVisible(true,false,true,true) && !menu_image::PinVisible(true,false,false,false) &&
      !menu_image::PinVisible(false,false,false,true), "pin only game foreground outside menu and capture");
    check((menu_image::kPinStyle & (WS_EX_NOACTIVATE|WS_EX_TRANSPARENT|WS_EX_LAYERED|WS_EX_TOPMOST|WS_EX_TOOLWINDOW)) == menu_image::kPinStyle, "pin input and activation policy");
    HWND owner = CreateWindowExW(0, L"STATIC", L"Hidden synthetic image fixture", WS_OVERLAPPED,
        0, 0, 800, 600, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    bool current = true;
    {
      MenuLocalTools tools(owner, [&] { return current; }, [](bool) {}, [] {});
      check(Call(tools, "capture", Map{{Value("hideMenu"), Value("false")}}).error == "menu.screenshot_preferences_invalid",
          "production capture rejects invalid visibility before desktop access");
      Map pin{{Value("bytes"), Value(bytes)}, {Value("x"), Value(10)}, {Value("y"), Value(20)},
        {Value("width"), Value(4)}, {Value("height"), Value(2)}};
      check(Call(tools,"imagePin",pin).error == "menu.image_pin_failed", "pin requires a native selected reference");
      check(Call(tools,"screenshotEdit").error == "menu.screenshot_edit_failed", "editing requires native captured screenshot");
      Call(tools,"imageTestLoad",Map{{Value("bytes"),Value(bytes)}});
      check(Call(tools,"imagePreparePin",pin).error.empty(), "reference frame can be staged without activating pin");
      check(Call(tools,"imagePinState").value == Value(false), "staged reference does not claim fixed state");
      tools.Hide();
      check(Call(tools,"imagePinState").value == Value(false), "temporary capture hide does not activate reference");
      Call(tools,"imageCancelPreparedPin");
      current = false; tools.Hide(); current = true;
      check(Call(tools,"imagePinState").value == Value(false), "closing reference window cancels auto pin");
      Call(tools,"imagePreparePin",pin);
      current = false; tools.Hide(); current = true;
      check(Call(tools,"imagePinState").value == Value(true), "closing whole menu activates staged reference");
      Call(tools,"imageUnpin");
      Call(tools,"imagePreparePin",pin); tools.Reset();
      current = false; tools.Hide(); current = true;
      check(Call(tools,"imagePinState").value == Value(false), "account reset retires staged reference before hide");
      Call(tools,"imageTestLoad",Map{{Value("bytes"),Value(bytes)}});
      {
        const auto temp = std::filesystem::canonical(std::filesystem::temp_directory_path());
        GUID id{}; CoCreateGuid(&id); wchar_t suffix[40]{}; StringFromGUID2(id, suffix, 40);
        const auto root = temp / (std::wstring(L"starbridge-screenshot-native-") + suffix);
        if (root.parent_path() != temp || root.filename().wstring().rfind(L"starbridge-screenshot-native-", 0) != 0 || std::filesystem::exists(root)) return 2;
        const auto name = root.u8string();
        check(Call(tools,"saveToDirectory",Edit()).error == "menu.screenshot_directory_unavailable", "direct save cannot reuse an absent Host authorization");
        check(tools.AuthorizeScreenshotDirectory(name), "trusted primary can authorize a destination without writing files");
        auto direct = Edit(.5,0,1,1,1); direct[Value("export")] = Value(Map{{Value("format"),Value("jpeg")},{Value("jpegQuality"),Value(75)}});
        const auto saved = Call(tools,"saveToDirectory",direct);
        check(saved.error.empty() && std::get_if<bool>(&saved.value) && std::get<bool>(saved.value), "native direct save returns success without exposing filename or path");
        std::wstring exported;
        for (const auto& file : std::filesystem::directory_iterator(root)) exported = file.path().wstring();
        Gdiplus::Color decoded;
        check(ExportPixel(ReadFileBytes(exported), true, 1, 4, decoded), "direct export uses the retained original and same crop/rotation recipe");
        check(Call(tools,"saveToDirectory",direct).error == "menu.screenshot_directory_unavailable", "directory authorization is consumed by exactly one export");
        tools.AuthorizeScreenshotDirectory(name);
        auto injected = direct; injected[Value("path")] = Value("forbidden");
        check(Call(tools,"saveToDirectory",injected).error == "menu.screenshot_export_invalid" &&
            Call(tools,"saveToDirectory",direct).error == "menu.screenshot_directory_unavailable", "surface path injection is rejected and consumes stale authorization");
        tools.AuthorizeScreenshotDirectory(name); tools.Hide();
        check(Call(tools,"saveToDirectory",direct).error == "menu.screenshot_directory_unavailable", "menu hiding clears pending directory authorization but retains preview");
        tools.AuthorizeScreenshotDirectory(name); tools.Reset();
        check(Call(tools,"saveToDirectory",direct).error == "menu.screenshot_directory_unavailable", "account detachment clears both directory authorization and image");
        std::filesystem::remove_all(root);
        Call(tools,"imageTestLoad",Map{{Value("bytes"),Value(bytes)}});
      }
      auto invalidExport = Edit(); invalidExport[Value("export")] = Value(Map{{Value("format"), Value("gif")}, {Value("jpegQuality"), Value(90)}});
      check(Call(tools,"save",invalidExport).error == "menu.screenshot_export_invalid" && Size(Call(tools,"screenshotEdit",Edit()),4,2),
          "invalid save export fails before dialog while retaining captured original");
      const auto choose = [&tools, &bytes](int file) { return Call(tools,"imageTestSelect", Map{{Value("bytes"),Value(bytes)}, {Value("fixtureFile"),Value(file)}}); };
      const auto selectedA = choose(1), selectedB = choose(2), selectedAgain = choose(1);
      const auto* a = std::get_if<Map>(&selectedA.value), *b = std::get_if<Map>(&selectedB.value), *again = std::get_if<Map>(&selectedAgain.value);
      check(a && b && again && a->size() == 2 && a->at(Value("bytes")) == Value(bytes) &&
          a->at(Value("imageId")) == again->at(Value("imageId")) && !(a->at(Value("imageId")) == b->at(Value("imageId"))),
          "native selection reply exposes only pixels and opaque identity, no file metadata or path");
      tools.Hide();
      check(a && std::get<Map>(choose(1).value).at(Value("imageId")) == a->at(Value("imageId")), "menu hide keeps this run image identity");
      tools.Reset();
      check(a && !(std::get<Map>(choose(1).value).at(Value("imageId")) == a->at(Value("imageId"))), "session detach clears selected image identity cache");
      Call(tools,"imageTestLoad",Map{{Value("bytes"),Value(bytes)}});
      check(Size(Call(tools,"imageEdit",Edit(.5,0,1,1,1)),1,4), "reference crop uses the shared rotated-original recipe");
      check(Size(Call(tools,"imageEdit",Edit()),4,2), "reference reset derives from the selected original without recapturing");
      check(Call(tools,"imageEdit",Edit(-.1)).error == "menu.image_edit_failed", "invalid reference crop fails without changing selected source");
      check(Size(Call(tools,"screenshotEdit",Edit(.5,0,1,1,1)),1,4), "method channel applies normalized crop and rotation");
      check(Size(Call(tools,"screenshotEdit",Edit()),4,2), "subsequent preview derives from original not previous crop");
      for (const auto& invalid : {Edit(-.1), Edit(0,0,1.1), Edit(.5,0,.5), Edit(0,0,1,1,4), Edit(std::numeric_limits<double>::quiet_NaN())})
        check(Call(tools,"screenshotEdit",invalid).error == "menu.screenshot_edit_failed", "malformed crop fails closed");
      check(Call(tools,"screenshotEdit",Map{{Value("turns"),Value(1)}}).error == "menu.screenshot_edit_failed", "partial edit rejected");
      auto malformed = Edit(); malformed[Value("turns")] = Value(1.5);
      check(Call(tools,"save",malformed).error == "menu.screenshot_edit_failed", "fractional turns fail before save dialog");
      check(Call(tools,"imagePin",pin).error.empty(), "bounded reference pin can initialize hidden");
      HWND pinned = FixturePin();
      check(Size(Call(tools,"imageEdit",Edit(.5,0,1,1)),2,2) && FixturePin() == pinned,
        "reference editing preserves the existing game pin until an explicit update");
      check(pinned && !IsWindowVisible(pinned) && !IsWindowVisible(owner), "menu and fixture owner remain hidden");
      check(pinned && (GetWindowLongPtrW(pinned,GWL_EXSTYLE) & menu_image::kPinStyle) == menu_image::kPinStyle,
        "actual HWND is clickthrough nonactivating topmost toolwindow");
      check(SendMessageW(pinned,WM_NCHITTEST,0,0) == HTTRANSPARENT && SendMessageW(pinned,WM_MOUSEACTIVATE,0,0) == MA_NOACTIVATE,
        "actual HWND refuses mouse input and activation");
      auto wrong = pin; wrong[Value("width")] = Value(100);
      check(Call(tools,"imagePin",wrong).error == "menu.image_pin_failed" && IsWindow(pinned), "mismatch rejected preserving previous pinned image");
      wrong = pin; wrong[Value("x")] = Value(-1);
      check(Call(tools,"imagePin",wrong).error == "menu.image_pin_failed", "off-owner reference coordinates rejected");
      current = false;
      check(Call(tools,"screenshotEdit").error == "menu.closed", "closed session cannot access screenshots");
      current = true; Call(tools,"imageUnpin");
      check(!IsWindow(pinned), "unpin destroys window and timer");
      check(Call(tools,"imagePin",pin).error.empty(), "unpin preserves selected reference for explicit repin");
      Call(tools,"imageClear");
      check(!FixturePin() && Call(tools,"imagePin",pin).error == "menu.image_pin_failed", "clear destroys pin and native reference");
      check(Call(tools,"imageEdit",Edit()).error == "menu.image_edit_failed", "cleared reference cannot be edited using the captured screenshot");
      Call(tools,"screenshotClear");
      check(Call(tools,"screenshotEdit").error == "menu.screenshot_edit_failed", "clear destroys captured source");
      Call(tools,"imageTestLoad",Map{{Value("bytes"),Value(bytes)}}); Call(tools,"imagePin",pin); tools.Reset();
      check(!FixturePin() && Call(tools,"screenshotEdit").error == "menu.screenshot_edit_failed" &&
        Call(tools,"imagePin",pin).error == "menu.image_pin_failed", "account reset clears all native images and pin window");
    }
    DestroyWindow(owner);
  }
  Gdiplus::GdiplusShutdown(token); CoUninitialize();
  printf("%d assertions, %d failed\n", total, failed); return failed ? 1 : 0;
}
