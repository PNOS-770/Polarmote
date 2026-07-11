set(_project_root "${ASMOTE_ROOT_DIR}")
set(_build_dir "${BUILD_DIR}")

if(NOT _project_root OR NOT _build_dir)
  message(FATAL_ERROR "Missing ASMOTE_ROOT_DIR or BUILD_DIR.")
endif()

set(_src_dll "${_project_root}/x86_64-pc-windows-msvc_super_native_extensions.dll")
set(_src_implib "${_project_root}/x86_64-pc-windows-msvc_super_native_extensions.dll.lib")

if(NOT EXISTS "${_src_dll}" OR NOT EXISTS "${_src_implib}")
  message(STATUS
    "super_native_extensions precompiled files not found in project root, skip copy.")
  return()
endif()

set(_plugin_temp_dir "${_build_dir}/plugins/super_native_extensions/cargokit_build")
set(_precompiled_root "${_plugin_temp_dir}/precompiled")
set(_crate_hash_dir "${_plugin_temp_dir}/crate_hash")
file(MAKE_DIRECTORY "${_precompiled_root}")

set(_hashes)

file(GLOB _existing_entries RELATIVE "${_precompiled_root}" "${_precompiled_root}/*")
foreach(_entry IN LISTS _existing_entries)
  if(IS_DIRECTORY "${_precompiled_root}/${_entry}")
    list(APPEND _hashes "${_entry}")
  endif()
endforeach()

if(NOT _hashes)
  file(GLOB _hash_markers "${_crate_hash_dir}/*")
  foreach(_marker IN LISTS _hash_markers)
    if(NOT IS_DIRECTORY "${_marker}")
      file(READ "${_marker}" _hash_raw LIMIT 128)
      string(STRIP "${_hash_raw}" _hash_value)
      if(_hash_value MATCHES "^[0-9a-fA-F]+$")
        list(APPEND _hashes "${_hash_value}")
      endif()
    endif()
  endforeach()
endif()

if(NOT _hashes)
  list(APPEND _hashes "e150673d77a4fd6654b60843c3cbb22d")
endif()

list(REMOVE_DUPLICATES _hashes)

foreach(_hash IN LISTS _hashes)
  set(_target_dir "${_precompiled_root}/${_hash}")
  file(MAKE_DIRECTORY "${_target_dir}")

  set(_dst_dll "${_target_dir}/x86_64-pc-windows-msvc_super_native_extensions.dll")
  set(_dst_implib "${_target_dir}/x86_64-pc-windows-msvc_super_native_extensions.dll.lib")

  if(NOT EXISTS "${_dst_dll}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${_src_dll}" "${_dst_dll}"
      RESULT_VARIABLE _copy_dll_rc
    )
    if(NOT _copy_dll_rc EQUAL 0)
      message(WARNING "Failed copying ${_src_dll} -> ${_dst_dll}")
    else()
      message(STATUS "Copied missing precompiled DLL to ${_target_dir}")
    endif()
  endif()

  if(NOT EXISTS "${_dst_implib}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${_src_implib}" "${_dst_implib}"
      RESULT_VARIABLE _copy_implib_rc
    )
    if(NOT _copy_implib_rc EQUAL 0)
      message(WARNING "Failed copying ${_src_implib} -> ${_dst_implib}")
    else()
      message(STATUS "Copied missing precompiled import lib to ${_target_dir}")
    endif()
  endif()
endforeach()
