# ===================== MinGW + C++/WinRT CMake extension =====================
# Momo-AUX1 (2026) Licensed under MIT License.
# Purpose: simplify using C++/WinRT with MinGW g++ targeting Windows.
# Usage:
#   set(USE_MINGW_WINRT ON)     # or -DUSE_MINGW_WINRT=ON at configure time
#   include("path/to/MinGWWinRT.cmake")
#
# Notes:
# - Does nothing unless USE_MINGW_WINRT/MINGW_USE_WINRT=ON.
# - When ON, hard-errors if not building with MinGW g++ targeting Windows (script mode is lenient).
# - Auto-discovers the newest working Windows SDK version by trying versions in descending order.
# - In script mode (cmake -P), exports ready-to-use CXXFLAGS/LDFLAGS for Makefiles.

option(MINGW_USE_WINRT "Enable C++/WinRT for MinGW builds (auto-detect Windows SDK)" OFF)
if(DEFINED USE_MINGW_WINRT)
  set(MINGW_USE_WINRT "${USE_MINGW_WINRT}" CACHE BOOL "Enable C++/WinRT for MinGW builds (alias for USE_MINGW_WINRT)" FORCE)
endif()
set(USE_MINGW_WINRT "${MINGW_USE_WINRT}" CACHE BOOL "Alias for MINGW_USE_WINRT" FORCE)

option(MINGW_WINRT_USE_WINSTORECOMPAT "Link winstorecompat shim when available" ON)
set(MINGW_WINRT_SCRIPT_OUTPUT "" CACHE FILEPATH "Optional output path for script-mode flag export.")
set(MINGW_WINRT_SCRIPT_FORMAT "shell" CACHE STRING "Format for script-mode export (shell|cmake)")
set_property(CACHE MINGW_WINRT_SCRIPT_FORMAT PROPERTY STRINGS shell cmake)

# Optional overrides
set(WINRT_WINDOWS_SDK_ROOT    "" CACHE PATH   "Optional override: Windows SDK root (e.g. C:/Program Files (x86)/Windows Kits/10)")
set(WINRT_WINDOWS_SDK_VERSION "" CACHE STRING "Optional override: Windows SDK version (e.g. 10.0.22621.0)")

include_guard(GLOBAL)

function(_mingw_winrt__set_prop _name _value)
  set_property(GLOBAL PROPERTY "MINGW_WINRT_${_name}" "${_value}")
endfunction()

function(_mingw_winrt__get_prop _out _name)
  get_property(_val GLOBAL PROPERTY "MINGW_WINRT_${_name}")
  set(${_out} "${_val}" PARENT_SCOPE)
endfunction()

function(_mingw_winrt__normalize_path _out _in)
  if(NOT _in)
    set(${_out} "" PARENT_SCOPE)
    return()
  endif()
  file(TO_CMAKE_PATH "${_in}" _p)
  string(REGEX REPLACE "/+$" "" _p "${_p}")
  set(${_out} "${_p}" PARENT_SCOPE)
endfunction()

function(_mingw_winrt__normalize_sdkver _out _in)
  if(NOT _in)
    set(${_out} "" PARENT_SCOPE)
    return()
  endif()
  set(_v "${_in}")
  string(REPLACE "\\" "/" _v "${_v}")
  string(REGEX REPLACE "/+$" "" _v "${_v}")
  if(_v MATCHES "^(10\\.[0-9]+\\.[0-9]+\\.[0-9]+)")
    set(_v "${CMAKE_MATCH_1}")
  endif()
  set(${_out} "${_v}" PARENT_SCOPE)
endfunction()

function(_mingw_winrt__pick_arch _out_arch)
  set(_t "")
  if(DEFINED CMAKE_CXX_COMPILER_TARGET AND NOT "${CMAKE_CXX_COMPILER_TARGET}" STREQUAL "")
    set(_t "${CMAKE_CXX_COMPILER_TARGET}")
  elseif(DEFINED CMAKE_C_COMPILER_TARGET AND NOT "${CMAKE_C_COMPILER_TARGET}" STREQUAL "")
    set(_t "${CMAKE_C_COMPILER_TARGET}")
  elseif(DEFINED CMAKE_SYSTEM_PROCESSOR AND NOT "${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "")
    set(_t "${CMAKE_SYSTEM_PROCESSOR}")
  elseif(DEFINED CMAKE_HOST_SYSTEM_PROCESSOR AND NOT "${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "")
    set(_t "${CMAKE_HOST_SYSTEM_PROCESSOR}")
  else()
    set(_t "")
  endif()
  string(TOLOWER "${_t}" _t)

  if(_t MATCHES "aarch64|arm64")
    set(${_out_arch} "arm64" PARENT_SCOPE)
  elseif(_t MATCHES "x86_64|amd64|win64|mingw64|64")
    set(${_out_arch} "x64" PARENT_SCOPE)
  elseif(_t MATCHES "i686|x86|win32|mingw32|86")
    set(${_out_arch} "x86" PARENT_SCOPE)
  else()
    if(DEFINED CMAKE_SIZEOF_VOID_P AND CMAKE_SIZEOF_VOID_P EQUAL 8)
      set(${_out_arch} "x64" PARENT_SCOPE)
    else()
      set(${_out_arch} "x86" PARENT_SCOPE)
    endif()
  endif()
endfunction()

function(_mingw_winrt__collect_sdk_roots _out_roots)
  set(_roots "")

  if(WINRT_WINDOWS_SDK_ROOT)
    list(APPEND _roots "${WINRT_WINDOWS_SDK_ROOT}")
  endif()

  if(DEFINED ENV{WindowsSdkDir} AND NOT "$ENV{WindowsSdkDir}" STREQUAL "")
    list(APPEND _roots "$ENV{WindowsSdkDir}")
  endif()
  if(DEFINED ENV{WindowsSdkDir_10} AND NOT "$ENV{WindowsSdkDir_10}" STREQUAL "")
    list(APPEND _roots "$ENV{WindowsSdkDir_10}")
  endif()

  list(APPEND _roots
    "C:/Program Files (x86)/Windows Kits/10"
    "C:/Program Files/Windows Kits/10"
  )

  if(DEFINED CMAKE_FIND_ROOT_PATH)
    foreach(_r IN LISTS CMAKE_FIND_ROOT_PATH)
      if(_r)
        list(APPEND _roots "${_r}/Windows Kits/10")
        list(APPEND _roots "${_r}/WindowsKits/10")
      endif()
    endforeach()
  endif()

  set(_valid "")
  foreach(_r IN LISTS _roots)
    _mingw_winrt__normalize_path(_nr "${_r}")
    if(_nr AND EXISTS "${_nr}/Include" AND EXISTS "${_nr}/Lib")
      list(APPEND _valid "${_nr}")
    endif()
  endforeach()
  list(REMOVE_DUPLICATES _valid)

  set(${_out_roots} "${_valid}" PARENT_SCOPE)
endfunction()

function(_mingw_winrt__lib_find_one _out_path _libdir _basename)
  set(_cands
    "${_libdir}/${_basename}.lib"
    "${_libdir}/${_basename}.a"
    "${_libdir}/lib${_basename}.a"
    "${_libdir}/${_basename}"
  )
  foreach(_c IN LISTS _cands)
    if(EXISTS "${_c}")
      set(${_out_path} "${_c}" PARENT_SCOPE)
      return()
    endif()
  endforeach()

  file(GLOB _g
    "${_libdir}/${_basename}.*"
    "${_libdir}/${_basename}*.*"
    "${_libdir}/*${_basename}.*"
  )
  list(LENGTH _g _n)
  if(_n GREATER 0)
    list(GET _g 0 _pick)
    set(${_out_path} "${_pick}" PARENT_SCOPE)
    return()
  endif()

  set(${_out_path} "" PARENT_SCOPE)
endfunction()

function(_mingw_winrt__try_sdk_version _out_ok _root _ver _arch)
  set(_ok FALSE)

  set(_inc_root "${_root}/Include/${_ver}")
  set(_lib_um   "${_root}/Lib/${_ver}/um/${_arch}")
  set(_lib_ucrt "${_root}/Lib/${_ver}/ucrt/${_arch}")

  if(NOT EXISTS "${_inc_root}/cppwinrt")
    set(${_out_ok} FALSE PARENT_SCOPE)
    return()
  endif()

  if(NOT EXISTS "${_lib_um}")
    set(${_out_ok} FALSE PARENT_SCOPE)
    return()
  endif()

  _mingw_winrt__lib_find_one(_wa "${_lib_um}" "windowsapp")
  _mingw_winrt__lib_find_one(_ro "${_lib_um}" "runtimeobject")

  if(NOT _wa OR NOT _ro)
    set(${_out_ok} FALSE PARENT_SCOPE)
    return()
  endif()

  set_property(GLOBAL PROPERTY MINGW_WINRT_SDK_ROOT    "${_root}")
  set_property(GLOBAL PROPERTY MINGW_WINRT_SDK_VER     "${_ver}")
  set_property(GLOBAL PROPERTY MINGW_WINRT_SDK_ARCH    "${_arch}")
  set_property(GLOBAL PROPERTY MINGW_WINRT_LIB_WINDOWSAPP   "${_wa}")
  set_property(GLOBAL PROPERTY MINGW_WINRT_LIB_RUNTIMEOBJECT "${_ro}")
  set_property(GLOBAL PROPERTY MINGW_WINRT_LIBDIR_UM   "${_lib_um}")
  set_property(GLOBAL PROPERTY MINGW_WINRT_LIBDIR_UCRT "${_lib_ucrt}")
  set_property(GLOBAL PROPERTY MINGW_WINRT_INCDIR_CPPWINRT "${_inc_root}/cppwinrt")
  set_property(GLOBAL PROPERTY MINGW_WINRT_INCDIR_SHARED   "${_inc_root}/shared")
  set_property(GLOBAL PROPERTY MINGW_WINRT_INCDIR_UM       "${_inc_root}/um")
  set_property(GLOBAL PROPERTY MINGW_WINRT_INCDIR_WINRT    "${_inc_root}/winrt")
  set_property(GLOBAL PROPERTY MINGW_WINRT_INCDIR_UCRT     "${_inc_root}/ucrt")

  set(${_out_ok} TRUE PARENT_SCOPE)
endfunction()

function(_mingw_winrt__resolve_sdk_or_die)
  get_property(_has GLOBAL PROPERTY MINGW_WINRT_SDK_VER SET)
  if(_has)
    return()
  endif()

  _mingw_winrt__pick_arch(_arch)

  _mingw_winrt__normalize_sdkver(_pref_ver "${WINRT_WINDOWS_SDK_VERSION}")

  if(NOT _pref_ver AND DEFINED ENV{WindowsSDKVersion} AND NOT "$ENV{WindowsSDKVersion}" STREQUAL "")
    _mingw_winrt__normalize_sdkver(_pref_ver "$ENV{WindowsSDKVersion}")
  endif()

  _mingw_winrt__collect_sdk_roots(_roots)
  if(NOT _roots)
    message(FATAL_ERROR
      "MINGW_USE_WINRT=ON but no Windows SDK root found.\n"
      "Looked in common locations and env vars (WindowsSdkDir, WindowsSdkDir_10).\n"
      "If your SDK is in a non-standard place, set WINRT_WINDOWS_SDK_ROOT in CMake cache."
    )
  endif()

  foreach(_root IN LISTS _roots)
    if(_pref_ver)
      _mingw_winrt__try_sdk_version(_ok "${_root}" "${_pref_ver}" "${_arch}")
      if(_ok)
        return()
      endif()
    endif()

    file(GLOB _vers RELATIVE "${_root}/Include" "${_root}/Include/10.*")
    if(_vers)
      list(SORT _vers)
      list(REVERSE _vers)
      foreach(_ver IN LISTS _vers)
        _mingw_winrt__try_sdk_version(_ok "${_root}" "${_ver}" "${_arch}")
        if(_ok)
          return()
        endif()
      endforeach()
    endif()
  endforeach()

  message(FATAL_ERROR
    "MINGW_USE_WINRT=ON but could not find a usable Windows SDK.\n"
    "Needs: Include/<ver>/cppwinrt and Lib/<ver>/um/<arch> with windowsapp + runtimeobject import libs.\n"
    "Tried roots: ${_roots}\n"
    "If you have the SDK but in a custom location, set WINRT_WINDOWS_SDK_ROOT.\n"
    "If you want to force a version, set WINRT_WINDOWS_SDK_VERSION (e.g. 10.0.22621.0)."
  )
endfunction()

function(_mingw_winrt__locate_winstorecompat _out_path)
  set(_paths "")
  if(DEFINED CMAKE_CXX_IMPLICIT_LINK_DIRECTORIES)
    list(APPEND _paths ${CMAKE_CXX_IMPLICIT_LINK_DIRECTORIES})
  endif()
  if(DEFINED CMAKE_C_IMPLICIT_LINK_DIRECTORIES)
    list(APPEND _paths ${CMAKE_C_IMPLICIT_LINK_DIRECTORIES})
  endif()
  list(REMOVE_DUPLICATES _paths)

  set(_lib "")
  if(_paths)
    find_library(_lib NAMES winstorecompat PATHS ${_paths})
  endif()
  if(NOT _lib)
    find_library(_lib NAMES winstorecompat)
  endif()

  set(${_out_path} "${_lib}" PARENT_SCOPE)
endfunction()

function(_mingw_winrt__validate_toolchain)
  if(CMAKE_SCRIPT_MODE_FILE)
    if(NOT CMAKE_HOST_WIN32)
      message(FATAL_ERROR "MINGW_USE_WINRT=ON requires a Windows host when running in script mode.")
    endif()
    return()
  endif()

  if(NOT (CMAKE_CXX_COMPILER_ID STREQUAL "GNU"))
    message(FATAL_ERROR "MINGW_USE_WINRT=ON requires MinGW g++ (GNU). Current compiler: ${CMAKE_CXX_COMPILER_ID}")
  endif()
  if(NOT WIN32)
    message(FATAL_ERROR "MINGW_USE_WINRT=ON requires targeting Windows (CMAKE_SYSTEM_NAME=Windows).")
  endif()
  if(NOT MINGW)
    message(STATUS "MinGW WinRT: 'MINGW' variable not set, but compiler is GNU + target is WIN32; continuing.")
  endif()
endfunction()

function(_mingw_winrt__configure_once)
  get_property(_configured GLOBAL PROPERTY MINGW_WINRT_READY SET)
  if(_configured)
    return()
  endif()

  _mingw_winrt__validate_toolchain()
  _mingw_winrt__resolve_sdk_or_die()

  get_property(_root GLOBAL PROPERTY MINGW_WINRT_SDK_ROOT)
  get_property(_ver  GLOBAL PROPERTY MINGW_WINRT_SDK_VER)
  get_property(_arch GLOBAL PROPERTY MINGW_WINRT_SDK_ARCH)

  get_property(_inc_cppwinrt GLOBAL PROPERTY MINGW_WINRT_INCDIR_CPPWINRT)
  get_property(_inc_shared   GLOBAL PROPERTY MINGW_WINRT_INCDIR_SHARED)
  get_property(_inc_um       GLOBAL PROPERTY MINGW_WINRT_INCDIR_UM)
  get_property(_inc_winrt    GLOBAL PROPERTY MINGW_WINRT_INCDIR_WINRT)
  get_property(_inc_ucrt     GLOBAL PROPERTY MINGW_WINRT_INCDIR_UCRT)

  get_property(_lib_wa GLOBAL PROPERTY MINGW_WINRT_LIB_WINDOWSAPP)
  get_property(_lib_ro GLOBAL PROPERTY MINGW_WINRT_LIB_RUNTIMEOBJECT)
  get_property(_libdir_um   GLOBAL PROPERTY MINGW_WINRT_LIBDIR_UM)
  get_property(_libdir_ucrt GLOBAL PROPERTY MINGW_WINRT_LIBDIR_UCRT)

  set(_include_dirs
    "${_inc_cppwinrt}"
    "${_inc_shared}"
    "${_inc_um}"
    "${_inc_winrt}"
  )
  set(_link_dirs "")
  if(EXISTS "${_libdir_ucrt}")
    list(APPEND _link_dirs "${_libdir_ucrt}")
  endif()
  list(APPEND _link_dirs "${_libdir_um}")
  list(REMOVE_DUPLICATES _link_dirs)

  set(_compile_defines UNICODE _UNICODE WIN32_LEAN_AND_MEAN WINRT_LEAN_AND_MEAN)
  set(_compile_options -municode)
  set(_link_options -municode)

  set(_libs "${_lib_wa}" "${_lib_ro}" ole32 shell32)

  set(_have_winstorecompat FALSE)
  set(_winstorecompat "")
  if(MINGW_WINRT_USE_WINSTORECOMPAT)
    _mingw_winrt__locate_winstorecompat(_winstorecompat)
    if(_winstorecompat)
      list(INSERT _libs 0 "${_winstorecompat}")
      set(_have_winstorecompat TRUE)
    endif()
  endif()

  if(NOT CMAKE_SCRIPT_MODE_FILE)
    message(STATUS "MinGW WinRT: Using Windows SDK ${_ver} at ${_root} (${_arch})")
    if(MINGW_WINRT_USE_WINSTORECOMPAT)
      if(_have_winstorecompat)
        message(STATUS "MinGW WinRT: winstorecompat shim enabled (${_winstorecompat})")
      else()
        message(STATUS "MinGW WinRT: winstorecompat not found; proceeding without it")
      endif()
    endif()
  endif()

  set(_cxxflag_list "")
  foreach(_dir IN LISTS _include_dirs)
    list(APPEND _cxxflag_list "-I\"${_dir}\"")
  endforeach()
  foreach(_def IN LISTS _compile_defines)
    list(APPEND _cxxflag_list "-D${_def}")
  endforeach()
  list(APPEND _cxxflag_list ${_compile_options})
  list(JOIN _cxxflag_list " " _cxxflags)

  set(_ldflag_list "")
  foreach(_dir IN LISTS _link_dirs)
    list(APPEND _ldflag_list "-L\"${_dir}\"")
  endforeach()
  list(APPEND _ldflag_list ${_link_options})
  foreach(_lib IN LISTS _libs)
    if(EXISTS "${_lib}")
      list(APPEND _ldflag_list "\"${_lib}\"")
    elseif(_lib MATCHES "^-")
      list(APPEND _ldflag_list "${_lib}")
    else()
      list(APPEND _ldflag_list "-l${_lib}")
    endif()
  endforeach()
  list(JOIN _ldflag_list " " _ldflags)

  _mingw_winrt__set_prop(INCLUDE_DIRS "${_include_dirs}")
  _mingw_winrt__set_prop(LINK_DIRS    "${_link_dirs}")
  _mingw_winrt__set_prop(COMPILE_DEFINES "${_compile_defines}")
  _mingw_winrt__set_prop(COMPILE_OPTIONS "${_compile_options}")
  _mingw_winrt__set_prop(LINK_OPTIONS "${_link_options}")
  _mingw_winrt__set_prop(LIBS "${_libs}")
  _mingw_winrt__set_prop(CXXFLAGS "${_cxxflags}")
  _mingw_winrt__set_prop(LDFLAGS "${_ldflags}")
  _mingw_winrt__set_prop(HAS_WINSTORECOMPAT "${_have_winstorecompat}")
  if(_have_winstorecompat)
    _mingw_winrt__set_prop(WINSTORECOMPAT "${_winstorecompat}")
  endif()
  _mingw_winrt__set_prop(READY TRUE)
endfunction()

function(_mingw_winrt__emit_script_exports)
  _mingw_winrt__get_prop(_cxxflags CXXFLAGS)
  _mingw_winrt__get_prop(_ldflags LDFLAGS)
  _mingw_winrt__get_prop(_includes INCLUDE_DIRS)
  _mingw_winrt__get_prop(_link_dirs LINK_DIRS)
  _mingw_winrt__get_prop(_libs LIBS)

  if(NOT MINGW_WINRT_SCRIPT_FORMAT)
    set(MINGW_WINRT_SCRIPT_FORMAT "shell")
  endif()

  if(MINGW_WINRT_SCRIPT_FORMAT STREQUAL "cmake")
    set(_lines
      "set(MINGW_WINRT_INCLUDE_DIRS \"${_includes}\")"
      "set(MINGW_WINRT_LINK_DIRS \"${_link_dirs}\")"
      "set(MINGW_WINRT_LIBS \"${_libs}\")"
      "set(MINGW_WINRT_CXXFLAGS \"${_cxxflags}\")"
      "set(MINGW_WINRT_LDFLAGS \"${_ldflags}\")"
    )
  else()
    set(_lines
      "MINGW_WINRT_INCLUDE_DIRS=\"${_includes}\""
      "MINGW_WINRT_LINK_DIRS=\"${_link_dirs}\""
      "MINGW_WINRT_LIBS=\"${_libs}\""
      "MINGW_WINRT_CXXFLAGS=\"${_cxxflags}\""
      "MINGW_WINRT_LDFLAGS=\"${_ldflags}\""
    )
  endif()

  list(JOIN _lines "\n" _payload)

  if(MINGW_WINRT_SCRIPT_OUTPUT)
    file(WRITE "${MINGW_WINRT_SCRIPT_OUTPUT}" "${_payload}\n")
  else()
    message("${_payload}")
  endif()
endfunction()

function(mingw_winrt_enable_global)
  if(NOT MINGW_USE_WINRT)
    return()
  endif()

  _mingw_winrt__configure_once()

  get_property(_applied GLOBAL PROPERTY MINGW_WINRT_APPLIED SET)
  if(_applied)
    return()
  endif()

  if(CMAKE_SCRIPT_MODE_FILE)
    _mingw_winrt__set_prop(APPLIED TRUE)
    return()
  endif()

  _mingw_winrt__get_prop(_include_dirs INCLUDE_DIRS)
  _mingw_winrt__get_prop(_link_dirs LINK_DIRS)
  _mingw_winrt__get_prop(_compile_defines COMPILE_DEFINES)
  _mingw_winrt__get_prop(_compile_options COMPILE_OPTIONS)
  _mingw_winrt__get_prop(_link_options LINK_OPTIONS)
  _mingw_winrt__get_prop(_libs LIBS)

  set(_iface "mingw_winrt")
  set(_iface_alias "mingw_winrt::winrt")
  if(NOT TARGET ${_iface})
    add_library(${_iface} INTERFACE)
    add_library(${_iface_alias} ALIAS ${_iface})

    target_include_directories(${_iface} INTERFACE ${_include_dirs})
    if(_link_dirs)
      target_link_directories(${_iface} INTERFACE ${_link_dirs})
    endif()
    target_compile_definitions(${_iface} INTERFACE ${_compile_defines})
    target_compile_options(${_iface} INTERFACE ${_compile_options})
    target_link_options(${_iface} INTERFACE ${_link_options})
    target_link_libraries(${_iface} INTERFACE ${_libs})
  endif()

  link_libraries(${_iface_alias})

  get_property(_targets DIRECTORY PROPERTY BUILDSYSTEM_TARGETS)
  foreach(_t IN LISTS _targets)
    if(NOT TARGET "${_t}")
      continue()
    endif()
    if(_t STREQUAL "${_iface}" OR _t STREQUAL "${_iface_alias}")
      continue()
    endif()
    get_target_property(_type "${_t}" TYPE)
    if(_type STREQUAL "INTERFACE_LIBRARY")
      target_link_libraries(${_t} INTERFACE ${_iface_alias})
    else()
      target_link_libraries(${_t} PRIVATE ${_iface_alias})
    endif()
  endforeach()

  _mingw_winrt__set_prop(APPLIED TRUE)
endfunction()

function(mingw_use_winrt target)
  if(NOT MINGW_USE_WINRT)
    return()
  endif()
  mingw_winrt_enable_global()

  if(CMAKE_SCRIPT_MODE_FILE)
    return()
  endif()

  if(NOT TARGET "${target}")
    message(FATAL_ERROR "mingw_use_winrt(): target '${target}' does not exist yet (call after add_executable/add_library).")
  endif()
  target_link_libraries(${target} PRIVATE mingw_winrt::winrt)
endfunction()

if(CMAKE_SCRIPT_MODE_FILE)
  if(MINGW_USE_WINRT)
    _mingw_winrt__configure_once()
    _mingw_winrt__emit_script_exports()
  endif()
  return()
endif()

if(MINGW_USE_WINRT)
  mingw_winrt_enable_global()
endif()
