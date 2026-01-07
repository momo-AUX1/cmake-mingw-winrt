# ===================== MinGW + C++/WinRT CMake extension =====================
# Momo-AUX1 (2026) Licended under MIT License.
# either copy this or add this repo as a git submodule and include it from your CMakeLists.txt.
# Purpose: simplify using C++/WinRT with MinGW g++ targeting Windows.
# Requirements: MinGW g++ with C++20 support, Windows SDK installed.
# url: https://github.com/momo-AUX1/cmake-mingw-winrt
 # Usage:
#   option(MINGW_USE_WINRT "..." OFF)   
#   add_executable(myapp ...)
#   mingw_use_winrt(myapp)             # safe to call be it EXE or DLL
#
# Notes:
# - Does nothing unless MINGW_USE_WINRT=ON.
# - When ON, hard-errors if not building with MinGW g++ targeting Windows.
# - Auto-discovers the newest working Windows SDK version by trying versions in descending order.
# - Includes a small “retry” chain tries preferred env version first (if present), then falls back to scanning.

option(MINGW_USE_WINRT "Enable C++/WinRT for MinGW builds (auto-detect Windows SDK)" OFF)

# Optional overrides
set(WINRT_WINDOWS_SDK_ROOT    "" CACHE PATH   "Optional override: Windows SDK root (e.g. C:/Program Files (x86)/Windows Kits/10)")
set(WINRT_WINDOWS_SDK_VERSION "" CACHE STRING "Optional override: Windows SDK version (e.g. 10.0.22621.0)")

include_guard(GLOBAL)

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
  # make sure it starts with 10.
  if(_v MATCHES "^(10\\.[0-9]+\\.[0-9]+\\.[0-9]+)")
    set(_v "${CMAKE_MATCH_1}")
  endif()
  set(${_out} "${_v}" PARENT_SCOPE)
endfunction()

function(_mingw_winrt__pick_arch _out_arch)
  # Prefer explicit compiler target triple when cross-compiling
  set(_t "")
  if(DEFINED CMAKE_CXX_COMPILER_TARGET AND NOT "${CMAKE_CXX_COMPILER_TARGET}" STREQUAL "")
    set(_t "${CMAKE_CXX_COMPILER_TARGET}")
  elseif(DEFINED CMAKE_C_COMPILER_TARGET AND NOT "${CMAKE_C_COMPILER_TARGET}" STREQUAL "")
    set(_t "${CMAKE_C_COMPILER_TARGET}")
  else()
    set(_t "${CMAKE_SYSTEM_PROCESSOR}")
  endif()
  string(TOLOWER "${_t}" _t)

  if(_t MATCHES "aarch64|arm64")
    set(${_out_arch} "arm64" PARENT_SCOPE)
  elseif(_t MATCHES "x86_64|amd64|win64|mingw64|64")
    set(${_out_arch} "x64" PARENT_SCOPE)
  elseif(_t MATCHES "i686|x86|win32|mingw32|86")
    set(${_out_arch} "x86" PARENT_SCOPE)
  else()
    # Fallback: pointer size if known
    if(DEFINED CMAKE_SIZEOF_VOID_P AND CMAKE_SIZEOF_VOID_P EQUAL 8)
      set(${_out_arch} "x64" PARENT_SCOPE)
    else()
      set(${_out_arch} "x86" PARENT_SCOPE)
    endif()
  endif()
endfunction()

function(_mingw_winrt__collect_sdk_roots _out_roots)
  set(_roots "")

  # cache override
  if(WINRT_WINDOWS_SDK_ROOT)
    list(APPEND _roots "${WINRT_WINDOWS_SDK_ROOT}")
  endif()

  # Common env vars
  if(DEFINED ENV{WindowsSdkDir} AND NOT "$ENV{WindowsSdkDir}" STREQUAL "")
    list(APPEND _roots "$ENV{WindowsSdkDir}")
  endif()
  if(DEFINED ENV{WindowsSdkDir_10} AND NOT "$ENV{WindowsSdkDir_10}" STREQUAL "")
    list(APPEND _roots "$ENV{WindowsSdkDir_10}")
  endif()

  # Common install locations (Windows host ONLY)
  list(APPEND _roots
    "C:/Program Files (x86)/Windows Kits/10"
    "C:/Program Files/Windows Kits/10"
  )

  # If using a sysroot / toolchain root path, try those too
  if(DEFINED CMAKE_FIND_ROOT_PATH)
    foreach(_r IN LISTS CMAKE_FIND_ROOT_PATH)
      if(_r)
        list(APPEND _roots "${_r}/Windows Kits/10")
        list(APPEND _roots "${_r}/WindowsKits/10")
      endif()
    endforeach()
  endif()

  # Normalize + filter to only existing roots that look like a Windows SDK
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
  # Prefer .lib (Windows SDK import libs), then accept .a variants.
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

  # Last resort: glob (case variations)
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

  # All good: export details via GLOBAL properties so we compute once.
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
  # If already resolved once, stop.
  get_property(_has GLOBAL PROPERTY MINGW_WINRT_SDK_VER SET)
  if(_has)
    return()
  endif()

  _mingw_winrt__pick_arch(_arch)

  # Preferred version candidates:
  # Cache override WINRT_WINDOWS_SDK_VERSION
  _mingw_winrt__normalize_sdkver(_pref_ver "${WINRT_WINDOWS_SDK_VERSION}")

  # Common env vars
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

  # Try preferred version first, then scan newest->oldest for each root.
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
      list(REVERSE _vers) # newest first
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

function(mingw_use_winrt target)
  if(NOT MINGW_USE_WINRT)
    return()
  endif()

  if(NOT TARGET "${target}")
    message(FATAL_ERROR "mingw_use_winrt(): target '${target}' does not exist yet (call after add_executable/add_library).")
  endif()

  # Validate toolchain MinGW g++ targeting Windows
  if(NOT (CMAKE_CXX_COMPILER_ID STREQUAL "GNU"))
    message(FATAL_ERROR "MINGW_USE_WINRT=ON requires MinGW g++ (GNU). Current compiler: ${CMAKE_CXX_COMPILER_ID}")
  endif()
  if(NOT WIN32)
    message(FATAL_ERROR "MINGW_USE_WINRT=ON requires targeting Windows (CMAKE_SYSTEM_NAME=Windows).")
  endif()
  if(NOT MINGW)
    # cross-compile scenario
    message(STATUS "MinGW WinRT: 'MINGW' variable not set, but compiler is GNU + target is WIN32; continuing.")
  endif()

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

  # One-time info message to clarifey what was picked
  message(STATUS "MinGW WinRT: Using Windows SDK ${_ver} at ${_root} (${_arch})")

  target_include_directories(${target} PRIVATE
    "${_inc_cppwinrt}"
    "${_inc_shared}"
    "${_inc_um}"
    "${_inc_winrt}"
    #"${_inc_ucrt}" needs vcruntime.h just disable it for now
  )

  # Link dirs: UM is required, UCRT is optional but commonly helpful for UWP link setups
  if(EXISTS "${_libdir_ucrt}")
    target_link_directories(${target} PRIVATE "${_libdir_ucrt}")
  endif()
  target_link_directories(${target} PRIVATE "${_libdir_um}")

  target_compile_definitions(${target} PRIVATE
    UNICODE _UNICODE
    WIN32_LEAN_AND_MEAN
    WINRT_LEAN_AND_MEAN
  )

  # -municode is MinGW-specific (wmain entry); harmless if you use wWinMain/main but can scream about undefined symbol wWinMain
  target_compile_options(${target} PRIVATE -municode)
  target_link_options(${target} PRIVATE -municode)

  target_link_libraries(${target} PRIVATE
    "${_lib_wa}"
    "${_lib_ro}"
    ole32
    shell32
  )
endfunction()
# =================== end MinGW + C++/WinRT CMake extension ===================
