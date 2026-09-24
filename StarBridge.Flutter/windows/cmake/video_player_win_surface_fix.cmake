# Compatibility correction for video_player_win 3.2.2 (BSD-3-Clause).
# Generate a build-local translation unit; never edit the shared pub cache.
# Flutter consumes visible_width/visible_height, not width/height, as the
# external OpenGL texture dimensions. Upstream leaves both zero after memset.
function(starbridge_patch_video_surface source destination)
  file(SHA256 "${source}" source_hash)
  if(NOT source_hash STREQUAL "1797ab687469df81c332b742f90a9bf7d7bcac359aaa21f09479f9916bcf4be3")
    message(FATAL_ERROR "video_player_win source changed; review the surface fix before upgrading.")
  endif()
  file(READ "${source}" source_text)
  set(anchor "texture_buffer.height = desc.Height;")
  string(FIND "${source_text}" "${anchor}" anchor_index)
  if(anchor_index LESS 0)
    message(FATAL_ERROR "Missing video surface correction anchor.")
  endif()
  string(REPLACE "${anchor}"
    "${anchor}\n      texture_buffer.visible_width = desc.Width;\n      texture_buffer.visible_height = desc.Height;"
    corrected_source "${source_text}")
  # configure_file avoids unnecessary rebuilds when the content is unchanged.
  set(patched_video_source "${corrected_source}")
  configure_file("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/video_player_win_surface.cpp.in"
    "${destination}" @ONLY)
endfunction()

if(TARGET video_player_win_plugin)
  get_target_property(plugin_source_dir video_player_win_plugin SOURCE_DIR)
  set(original_source "${plugin_source_dir}/video_player_win_plugin.cpp")
  set(corrected_source "${CMAKE_CURRENT_BINARY_DIR}/starbridge_video_surface/video_player_win_plugin.cpp")
  starbridge_patch_video_surface("${original_source}" "${corrected_source}")
  get_target_property(plugin_sources video_player_win_plugin SOURCES)
  list(REMOVE_ITEM plugin_sources "video_player_win_plugin.cpp" "${original_source}")
  set_property(TARGET video_player_win_plugin PROPERTY SOURCES "${plugin_sources};${corrected_source}")
  target_include_directories(video_player_win_plugin PRIVATE "${plugin_source_dir}")
endif()
