# Install-time guard for direct `flutter build windows` as well as wrappers.
# This Host probe exits before storage, account, runtime or window initialization.
if(NOT DEFINED SB_OVERLAY_BUNDLE_ROOT OR SB_OVERLAY_BUNDLE_ROOT STREQUAL "")
  message(FATAL_ERROR "Overlay bundle root is required")
endif()
foreach(required IN ITEMS StarBridge.NativeHost.exe StarBridge.HostRuntime.dll
    StarBridge.Core.dll StarBridge.NativeBridge.dll
    StarBridge.OverlayRuntime.Windows.dll WinRT.Runtime.dll)
  if(NOT EXISTS "${SB_OVERLAY_BUNDLE_ROOT}/${required}" OR
      IS_DIRECTORY "${SB_OVERLAY_BUNDLE_ROOT}/${required}")
    message(FATAL_ERROR "Packaged overlay dependency missing: ${required}")
  endif()
endforeach()
set(expected "$ENV{StarBridgeEnableOverlaySourcePresets}")
if(expected STREQUAL "")
  set(expected "true")
endif()
string(TOLOWER "${expected}" expected)
if(NOT expected STREQUAL "true" AND NOT expected STREQUAL "false")
  message(FATAL_ERROR "Invalid overlay source build selection")
endif()
execute_process(
  COMMAND "${SB_OVERLAY_BUNDLE_ROOT}/StarBridge.NativeHost.exe" --overlay-source-build-info
  RESULT_VARIABLE probe_result OUTPUT_VARIABLE probe_output ERROR_VARIABLE probe_error
  OUTPUT_STRIP_TRAILING_WHITESPACE TIMEOUT 10)
if(NOT probe_result STREQUAL "0" OR
    NOT probe_output STREQUAL "overlay-source-presets=${expected}")
  message(FATAL_ERROR "Packaged overlay source capability mismatch; rebuild Native Host with the selected profile")
endif()
message(STATUS "Verified packaged overlay dependencies and source presets: ${expected}")
