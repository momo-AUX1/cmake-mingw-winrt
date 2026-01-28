## MinGWWinRT.cmake — C++/WinRT helper for MinGW (auto Windows SDK + frozen fallback)

**MinGWWinRT.cmake** is a drop-in CMake module that makes **C++/WinRT** usable from **MinGW (GCC or Clang)** with minimal setup.

It auto-detects a usable **Windows 10+ SDK** (*Live mode*). If none is found (or you force it), it falls back to **bundled “Frozen” WinRT headers** while still linking the required WinRT import libraries provided by your toolchain.

✅ Tried and tested on **PC** and **Xbox Series X|S**  
Example project:  *(see note below)*  
Repository: https://github.com/momo-AUX1/CoreAppMinGW

> Note: If you publish this module in its own repository, it’s best to link that repo here and use it as a git submodule (recommended below).

---

## Why use this?

If you’re building Windows / UWP-style code with MinGW and want to call WinRT APIs directly (e.g. `Windows::ApplicationModel`, `Windows::Foundation`, `Windows::Gaming::Input`, etc.):

- No “helper layer” bottleneck — you can use the WinRT surface you include/link
- Auto-picks the newest working Windows SDK (when installed)
- Frozen fallback for portability / CI / minimal environments
- Works with **GCC** and **Clang**
- Optional **winstorecompat** support (MSYS2) when available
- Can export ready-to-use flags in **script mode** (`cmake -P`) for Makefiles/other build systems

---

## What it does

When enabled, the module configures:

- Include paths for C++/WinRT:
  - **Live SDK**: `Windows Kits/10/Include/<ver>/cppwinrt` (+ shared/um/winrt)
  - **Frozen**: `${MINGW_WINRT_FROZEN_SDK_ROOT}` (contains `winrt/base.h`)
- Links required WinRT import libraries:
  - `windowsapp`
  - `runtimeobject`
  - plus `ole32`, `shell32`
- Adds Unicode flags:
  - `-municode` compile + link
- Optionally links **winstorecompat** if installed

---

## Requirements

### Supported environments
- Windows host (MSYS2 recommended)
- Toolchains:
  - MinGW **GCC** (mingw64 or ucrt64)
  - MinGW **Clang** (clang64 / llvm-mingw style)

### Windows SDK (Live mode)
Live mode uses an installed Windows SDK under Windows Kits (typically):

- `C:\Program Files (x86)\Windows Kits\10`

If a usable SDK is found, the module automatically picks the newest version with:
- `Include/<ver>/cppwinrt`
- `Lib/<ver>/um/<arch>/windowsapp` and `runtimeobject`

If no SDK is found, it falls back to Frozen headers (unless you force Live).

---

## Dependencies to install (MSYS2)

Pick **one** subsystem and install its toolchain. These are **needed** because they provide:
- compiler + linker
- CMake
- Ninja
- import libs used for WinRT linking

### Clang64 subsystem (recommended for Live mode stability)

```bash
pacman -S mingw-w64-clang-x86_64-{toolchain,cmake,ninja}
````

### UCRT64 subsystem (GCC)

```bash
pacman -S mingw-w64-ucrt-x86_64-{toolchain,cmake,ninja}
```

### MINGW64 subsystem (GCC)

```bash
pacman -S mingw-w64-x86_64-{toolchain,cmake,ninja}
```

### Optional: winstorecompat

`winstorecompat` is optional. If you want it, install the matching package for your subsystem.

Example for **MINGW64 x64**:

```bash
pacman -S mingw-w64-x86_64-winstorecompat
```
---

## Add to your project (recommended: Git submodule)

Instead of copying files around, add this module as a **git submodule** so updates are easy.

From your repo root:

```bash
git submodule add https://github.com/momo-AUX1/cmake-mingw-winrt.git external/mingw-winrt
git submodule update --init --recursive
```

example layout:

```text
your-project/
  external/mingw-winrt/
    MinGWWinRT.cmake
    winrt/include/              # optional Frozen headers tree
  src/
    main.cpp
  CMakeLists.txt
```

---

## Usage in CMake (example project)

### Minimal `CMakeLists.txt`

```cmake
cmake_minimum_required(VERSION 3.16)
project(WinRTExample LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Enable the module
set(MINGW_USE_WINRT ON)

# Optional knobs:
# set(MINGW_WINRT_USE_WINSTORECOMPAT ON)
# set(MINGW_WINRT_FORCE_LIVE_SDK OFF)
# set(MINGW_WINRT_FORCE_FROZEN_SDK OFF)
# set(MINGW_WINRT_FROZEN_SDK_ROOT "${CMAKE_SOURCE_DIR}/external/mingw-winrt/winrt/include")

include(external/mingw-winrt/MinGWWinRT.cmake)

add_executable(winrt_example
  src/main.cpp
)

# Optional explicit linking (not needed anymore as the module applies globally now)
mingw_use_winrt(winrt_example)
```

### Example `src/main.cpp`

```cpp
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>

#include <iostream>

int main() {
  winrt::init_apartment();

  winrt::Windows::Foundation::Uri uri(L"https://example.com");
  std::wcout << L"Host: " << uri.Host().c_str() << L"\n";

  return 0;
}
```

---

## Build (Ninja)

From an MSYS2 shell matching your subsystem:

```bash
cmake -S . -B build -G Ninja -DMINGW_USE_WINRT=ON
cmake --build build
```

Force Frozen mode:

```bash
cmake -S . -B build -G Ninja \
  -DMINGW_USE_WINRT=ON \
  -DMINGW_WINRT_FORCE_FROZEN_SDK=ON
cmake --build build
```

Force Live SDK mode:

```bash
cmake -S . -B build -G Ninja \
  -DMINGW_USE_WINRT=ON \
  -DMINGW_WINRT_FORCE_LIVE_SDK=ON
cmake --build build
```

---

## Configuration options

| Option                           |                                   Default | Meaning                                                            |
| -------------------------------- | ----------------------------------------: | ------------------------------------------------------------------ |
| `MINGW_USE_WINRT`                |                                     `OFF` | Enables this module. Alias: `USE_MINGW_WINRT`.                     |
| `MINGW_WINRT_USE_WINSTORECOMPAT` |                                      `ON` | Try to link `winstorecompat` if found.                             |
| `MINGW_WINRT_FORCE_LIVE_SDK`     |                                     `OFF` | Require an installed Windows SDK (fail if missing).                |
| `MINGW_WINRT_FORCE_FROZEN_SDK`   |                                     `OFF` | Skip Windows SDK detection and use Frozen headers.                 |
| `MINGW_WINRT_FROZEN_SDK_ROOT`    | `${CMAKE_CURRENT_LIST_DIR}/winrt/include` | Path containing `winrt/base.h`.                                    |
| `WINRT_WINDOWS_SDK_ROOT`         |                                     empty | Override SDK root (e.g. `C:/Program Files (x86)/Windows Kits/10`). |
| `WINRT_WINDOWS_SDK_VERSION`      |                                     empty | Override SDK version (e.g. `10.0.22621.0`).                        |

---

## Script mode (flag export)

You can run the module in script mode to print/export `CXXFLAGS` / `LDFLAGS`:

```bash
cmake -P external/mingw-winrt/MinGWWinRT.cmake -DMINGW_USE_WINRT=ON
```

Optional:

* `MINGW_WINRT_SCRIPT_FORMAT=shell` or `cmake`
* `MINGW_WINRT_SCRIPT_OUTPUT=<path>`

---

## Troubleshooting

### “winstorecompat not found; proceeding without it”

Install the package for your subsystem (example for MINGW64):

```bash
pacman -S mingw-w64-x86_64-winstorecompat
```

Verify:

```bash
ls "$MINGW_PREFIX/lib"/libwinstorecompat.*
```

### Frozen vs Live behavior differences

* Live mode uses your installed Windows SDK headers/libs and tends to match platform expectations closely.
* Frozen mode is great for portability and CI, but depends on your environment/toolchain for import libs and may behave differently in some deeper platform paths.

---

## Example project

A working example using this module can be found here:

[https://github.com/momo-AUX1/CoreAppMinGW](https://github.com/momo-AUX1/CoreAppMinGW)

---

## License

MIT.