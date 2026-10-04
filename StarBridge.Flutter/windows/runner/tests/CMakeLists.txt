cmake_minimum_required(VERSION 3.14)
project(small_icon_dpi_tests LANGUAGES CXX RC)
enable_testing()
option(STARBRIDGE_FRIENDS_TESTS "Compile independent friends engine fixture" OFF)
if(STARBRIDGE_FRIENDS_TESTS)
  get_filename_component(FRIENDS_FLUTTER_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
  set(FRIENDS_EPHEMERAL "${FRIENDS_FLUTTER_ROOT}/windows/flutter/ephemeral")
  add_executable(friends_window_bridge_test friends_window_bridge_test.cpp ../friends_window_bridge.cpp)
  target_include_directories(friends_window_bridge_test PRIVATE .. "${FRIENDS_EPHEMERAL}" "${FRIENDS_EPHEMERAL}/cpp_client_wrapper/include")
  target_compile_features(friends_window_bridge_test PRIVATE cxx_std_17)
  target_compile_definitions(friends_window_bridge_test PRIVATE NOMINMAX UNICODE _UNICODE STARBRIDGE_FRIENDS_TEST)
  target_compile_options(friends_window_bridge_test PRIVATE /W4 /WX /wd4100 /utf-8 /EHsc)
  target_link_libraries(friends_window_bridge_test PRIVATE
    "${FRIENDS_FLUTTER_ROOT}/build/windows/x64/flutter/Release/flutter_wrapper_app.lib"
    "${FRIENDS_EPHEMERAL}/flutter_windows.dll.lib" dwmapi user32 gdi32 ole32)
  add_custom_command(TARGET friends_window_bridge_test POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${FRIENDS_EPHEMERAL}/flutter_windows.dll" "$<TARGET_FILE_DIR:friends_window_bridge_test>")
  add_test(NAME friends_window_hidden COMMAND friends_window_bridge_test "${FRIENDS_FLUTTER_ROOT}/build/windows/x64/runner/Release/data")
  set_tests_properties(friends_window_hidden PROPERTIES TIMEOUT 30)
  add_test(NAME messages_window_hidden COMMAND friends_window_bridge_test "${FRIENDS_FLUTTER_ROOT}/build/windows/x64/runner/Release/data" messages)
  add_test(NAME notifications_window_hidden COMMAND friends_window_bridge_test "${FRIENDS_FLUTTER_ROOT}/build/windows/x64/runner/Release/data" notifications)
  set_tests_properties(messages_window_hidden notifications_window_hidden PROPERTIES TIMEOUT 30)
endif()
add_executable(menu_overlay_session_test menu_overlay_session_test.cpp)
target_include_directories(menu_overlay_session_test PRIVATE ..)
target_compile_features(menu_overlay_session_test PRIVATE cxx_std_17)
add_test(NAME menu_overlay_session COMMAND menu_overlay_session_test)

add_executable(menu_overlay_window_test menu_overlay_window_test.cpp ../menu_overlay_window.cpp)
target_include_directories(menu_overlay_window_test PRIVATE ..)
target_compile_features(menu_overlay_window_test PRIVATE cxx_std_17)
target_compile_definitions(menu_overlay_window_test PRIVATE NOMINMAX UNICODE _UNICODE)
target_compile_options(menu_overlay_window_test PRIVATE /W4 /WX /utf-8)
target_link_libraries(menu_overlay_window_test PRIVATE dwmapi user32 gdi32)
add_test(NAME menu_overlay_window COMMAND menu_overlay_window_test)

option(STARBRIDGE_MENU_BRIDGE_TESTS "Use existing local Flutter SDK to test menu channel" OFF)
if(STARBRIDGE_MENU_BRIDGE_TESTS)
  get_filename_component(MENU_FLUTTER_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
  set(MENU_EPHEMERAL "${MENU_FLUTTER_ROOT}/windows/flutter/ephemeral")
  add_executable(menu_overlay_bridge_test menu_overlay_bridge_test.cpp
    ../menu_overlay_bridge.cpp ../menu_overlay_window.cpp ../menu_local_tools.cpp)
  target_include_directories(menu_overlay_bridge_test PRIVATE .. "${MENU_EPHEMERAL}" "${MENU_EPHEMERAL}/cpp_client_wrapper/include")
  target_compile_features(menu_overlay_bridge_test PRIVATE cxx_std_17)
  target_compile_definitions(menu_overlay_bridge_test PRIVATE NOMINMAX UNICODE _UNICODE)
  target_compile_options(menu_overlay_bridge_test PRIVATE /W4 /WX /wd4100 /utf-8 /EHsc)
  target_link_libraries(menu_overlay_bridge_test PRIVATE
    "${MENU_FLUTTER_ROOT}/build/windows/x64/flutter/Release/flutter_wrapper_app.lib"
    "${MENU_EPHEMERAL}/flutter_windows.dll.lib" dwmapi user32 gdi32 ole32 shell32 gdiplus uuid)
  add_custom_command(TARGET menu_overlay_bridge_test POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${MENU_EPHEMERAL}/flutter_windows.dll" "$<TARGET_FILE_DIR:menu_overlay_bridge_test>")
  add_test(NAME menu_overlay_bridge COMMAND menu_overlay_bridge_test)
  if(DEFINED STARBRIDGE_MENU_SURFACE_PAYLOAD)
    add_executable(menu_overlay_preview WIN32 menu_overlay_preview.cpp
      ../menu_overlay_bridge.cpp ../menu_overlay_window.cpp ../menu_local_tools.cpp ../runner.exe.manifest)
    target_include_directories(menu_overlay_preview PRIVATE .. "${MENU_EPHEMERAL}" "${MENU_EPHEMERAL}/cpp_client_wrapper/include")
    target_compile_features(menu_overlay_preview PRIVATE cxx_std_17)
    target_compile_definitions(menu_overlay_preview PRIVATE NOMINMAX UNICODE _UNICODE STARBRIDGE_MENU_PREVIEW)
    target_compile_options(menu_overlay_preview PRIVATE /W4 /WX /wd4100 /utf-8 /EHsc)
    target_link_libraries(menu_overlay_preview PRIVATE
      "${MENU_FLUTTER_ROOT}/build/windows/x64/flutter/Release/flutter_wrapper_app.lib"
      "${MENU_EPHEMERAL}/flutter_windows.dll.lib" dwmapi user32 gdi32 ole32 shell32 gdiplus uuid)
    set_target_properties(menu_overlay_preview PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY_RELEASE "${STARBRIDGE_MENU_SURFACE_PAYLOAD}")
    # A private test executable beside an existing Debug payload; never launch
    # starbridge_flutter.exe or bootstrap its desktop/Host/account entrypoint.
    set_target_properties(menu_overlay_bridge_test PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY_RELEASE "${STARBRIDGE_MENU_SURFACE_PAYLOAD}")
    add_test(NAME menu_overlay_hidden_engine COMMAND menu_overlay_bridge_test --hidden-engine)
    set_tests_properties(menu_overlay_hidden_engine PROPERTIES TIMEOUT 30)
  endif()
endif()

add_executable(small_icon_dpi_test small_icon_dpi_test.cpp ../win32_window.cpp ../Runner.rc)
target_include_directories(small_icon_dpi_test PRIVATE stubs ..)
target_compile_features(small_icon_dpi_test PRIVATE cxx_std_17)
target_compile_definitions(small_icon_dpi_test PRIVATE NOMINMAX UNICODE _UNICODE)
target_compile_options(small_icon_dpi_test PRIVATE $<$<COMPILE_LANGUAGE:CXX>:/utf-8> $<$<COMPILE_LANGUAGE:CXX>:/W4> $<$<COMPILE_LANGUAGE:CXX>:/WX>)
target_link_libraries(small_icon_dpi_test PRIVATE dwmapi user32 gdi32 advapi32)
add_test(NAME small_icon_dpi COMMAND small_icon_dpi_test)

add_executable(installer_shutdown_test installer_shutdown_test.cpp ../win32_window.cpp ../Runner.rc)
target_include_directories(installer_shutdown_test PRIVATE stubs ..)
target_compile_features(installer_shutdown_test PRIVATE cxx_std_17)
target_compile_definitions(installer_shutdown_test PRIVATE NOMINMAX UNICODE _UNICODE)
target_compile_options(installer_shutdown_test PRIVATE $<$<COMPILE_LANGUAGE:CXX>:/utf-8> $<$<COMPILE_LANGUAGE:CXX>:/W4> $<$<COMPILE_LANGUAGE:CXX>:/WX>)
target_link_libraries(installer_shutdown_test PRIVATE dwmapi user32 gdi32 advapi32)
add_test(NAME installer_shutdown COMMAND installer_shutdown_test)

# Uses the existing canonical AOT payload, but never bootstraps the app or Host.
if(DEFINED STARBRIDGE_TRAY_PAYLOAD)
  get_filename_component(FLUTTER_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
  set(EPHEMERAL "${FLUTTER_ROOT}/windows/flutter/ephemeral")
  add_executable(tray_surface_runtime_test tray_surface_runtime_test.cpp
    ../application_lifecycle_bridge.cpp ../tray_surface_bridge.cpp ../win32_window.cpp ../Runner.rc)
  target_include_directories(tray_surface_runtime_test PRIVATE .. "${EPHEMERAL}" "${EPHEMERAL}/cpp_client_wrapper/include")
  target_compile_features(tray_surface_runtime_test PRIVATE cxx_std_17)
  target_compile_definitions(tray_surface_runtime_test PRIVATE NOMINMAX UNICODE _UNICODE)
  target_compile_options(tray_surface_runtime_test PRIVATE $<$<COMPILE_LANGUAGE:CXX>:/utf-8>)
  target_link_libraries(tray_surface_runtime_test PRIVATE
    "${FLUTTER_ROOT}/build/windows/x64/flutter/Release/flutter_wrapper_app.lib"
    "${EPHEMERAL}/flutter_windows.dll.lib" dwmapi user32 gdi32 advapi32 shell32 ole32)
  set_target_properties(tray_surface_runtime_test PROPERTIES RUNTIME_OUTPUT_DIRECTORY_RELEASE "${STARBRIDGE_TRAY_PAYLOAD}")
endif()

# Isolated probes are not release executables and do not borrow package identity.
foreach(fixture small_icon_dpi_test installer_shutdown_test tray_surface_runtime_test)
  if(TARGET ${fixture})
    target_compile_definitions(${fixture} PRIVATE
      "STARBRIDGE_PRODUCT_VERSION=\"0.0.0.0\""
      "STARBRIDGE_PRODUCT_VERSION_NUMBER=0,0,0,0")
  endif()
endforeach()
