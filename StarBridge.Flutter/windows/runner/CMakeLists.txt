cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "application_lifecycle_bridge.cpp"
  "tray_surface_bridge.cpp"
  "flutter_window.cpp"
  "hangar_browser_bridge.cpp"
  "main.cpp"
  "native_host_bridge.cpp"
  "overlay_editor_window.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Match Dart's opt-in exactly. Omission/false excludes native menu windows,
# channels and hotkeys from the binary, without affecting the information HUD.
include("${FLUTTER_MANAGED_DIR}/ephemeral/generated_config.cmake")
include("${CMAKE_CURRENT_SOURCE_DIR}/product_features.cmake")
if(STARBRIDGE_MENU_ENABLED)
  target_sources(${BINARY_NAME} PRIVATE
    "menu_overlay_bridge.cpp" "menu_local_tools.cpp" "menu_overlay_window.cpp")
  target_compile_definitions(${BINARY_NAME} PRIVATE STARBRIDGE_ENABLE_MENU_OVERLAY)
endif()

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Runner sources contain localized Win32 strings. Force MSVC to decode the
# UTF-8 source bytes deterministically instead of using the machine code page.
target_compile_options(${BINARY_NAME} PRIVATE /utf-8)

# Product versions may have four components; pubspec remains valid SemVer.
# Match NativeHost/installer instead of treating pubspec's build number as a
# product revision or dropping the fourth component from the display string.
set(SB_VERSION_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../../../Directory.Build.props")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${SB_VERSION_FILE}")
include("${CMAKE_CURRENT_SOURCE_DIR}/product_version.cmake")
target_compile_definitions(${BINARY_NAME} PRIVATE
  "STARBRIDGE_PRODUCT_VERSION=\"${SB_PRODUCT_VERSION}\""
  "STARBRIDGE_PRODUCT_VERSION_NUMBER=${SB_PRODUCT_VERSION_NUMBER}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "comdlg32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "ole32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "gdiplus.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Optional existing SDK, no build-time download. Without it the reader reports
# unavailable; public builds remain possible without additional dependencies.
set(STARBRIDGE_WEBVIEW2_SDK_ROOT "" CACHE PATH "Existing WebView2 SDK directory")
if(NOT STARBRIDGE_WEBVIEW2_SDK_ROOT)
  set(STARBRIDGE_WEBVIEW2_SDK_ROOT "$ENV{USERPROFILE}/.nuget/packages/microsoft.web.webview2/1.0.3179.45")
endif()
if(EXISTS "${STARBRIDGE_WEBVIEW2_SDK_ROOT}/build/native/include/WebView2.h")
  set(SB_READER_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../../../prototypes/hangar-reader")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${SB_READER_SOURCE}/rsi_account_panel_identity.js" "${SB_READER_SOURCE}/rsi_hangar_page.js" "${SB_READER_SOURCE}/rsi_hangar_capture.js")
  file(READ "${SB_READER_SOURCE}/rsi_account_panel_identity.js" SB_READER_IDENTITY)
  file(READ "${SB_READER_SOURCE}/rsi_hangar_page.js" SB_READER_PAGE)
  file(READ "${SB_READER_SOURCE}/rsi_hangar_capture.js" SB_READER_CAPTURE)
  configure_file(hangar_reader_assets.h.in hangar_reader_assets.h @ONLY)
  target_compile_definitions(${BINARY_NAME} PRIVATE STARBRIDGE_HAS_HANGAR_WEBVIEW)
  target_include_directories(${BINARY_NAME} PRIVATE "${STARBRIDGE_WEBVIEW2_SDK_ROOT}/build/native/include" "${CMAKE_CURRENT_BINARY_DIR}")
  target_link_libraries(${BINARY_NAME} PRIVATE "${STARBRIDGE_WEBVIEW2_SDK_ROOT}/build/native/x64/WebView2LoaderStatic.lib" ole32 oleaut32 shlwapi version)
endif()

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
