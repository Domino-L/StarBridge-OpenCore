# Flutter encodes --dart-define values as comma-separated base64 tokens.
# This token is exactly STARBRIDGE_ENABLE_MENU_OVERLAY=true.
set(STARBRIDGE_MENU_ENABLED OFF)
foreach(SB_TOOL_ENV IN LISTS FLUTTER_TOOL_ENVIRONMENT)
  if(SB_TOOL_ENV MATCHES "^DART_DEFINES=(.*)$")
    string(REPLACE "," ";" SB_DART_DEFINES "${CMAKE_MATCH_1}")
    if("U1RBUkJSSURHRV9FTkFCTEVfTUVOVV9PVkVSTEFZPXRydWU=" IN_LIST SB_DART_DEFINES)
      set(STARBRIDGE_MENU_ENABLED ON)
    endif()
  endif()
endforeach()
