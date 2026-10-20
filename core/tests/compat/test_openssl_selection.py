#!/usr/bin/env python3
"""Regression-test the Windows branch of our real FindOpenSSL.cmake.

Uses temporary SDK path fixtures, not executable .lib binaries. This proves
path selection / cache invalidation, not the Windows linker or MSVC build.
Run: python3 core/tests/compat/test_openssl_selection.py
"""
from pathlib import Path
import subprocess
import tempfile

CORE = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="lf-openssl-paths-") as tmp:
    root = Path(tmp)
    sdk = root / "portable-sdk"
    inc = sdk / "include" / "openssl"
    libs = sdk / "lib" / "VC" / "x64" / "MD"
    inc.mkdir(parents=True)
    libs.mkdir(parents=True)
    (inc / "ssl.h").write_text("/* selection-only fixture */\n")
    (inc / "opensslv.h").write_text('#define OPENSSL_VERSION_STR "3.5.9"\n')
    for name in ("libssl.lib", "libcrypto.lib"):
        (libs / name).write_bytes(b"path-selection fixture, not a Windows library\n")
    source = root / "source"
    source.mkdir()
    (source / "CMakeLists.txt").write_text('''cmake_minimum_required(VERSION 3.16)
project(PortableOpenSSLSelection NONE)
set(WIN32 TRUE)
set(UNIX FALSE)
set(MSVC TRUE)
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SIZEOF_VOID_P 8)
set(PLATFORM 64)
set(CMAKE_FIND_LIBRARY_SUFFIXES .lib)
set(CMAKE_FIND_LIBRARY_PREFIXES "")
list(PREPEND CMAKE_MODULE_PATH "''' + (CORE / "cmake/macros").as_posix() + '''")
# Simulate the stale system cache seen in the Windows build log.
set(SSL_EAY_RELEASE "/stale-system/libssl.lib" CACHE FILEPATH "")
set(LIB_EAY_RELEASE "/stale-system/libcrypto.lib" CACHE FILEPATH "")
find_package(OpenSSL REQUIRED COMPONENTS Crypto SSL)
foreach(kind SSL CRYPTO)
  get_target_property(location OpenSSL::${kind} IMPORTED_LOCATION_RELEASE)
endforeach()
if(NOT OPENSSL_SSL_LIBRARY STREQUAL "${OPENSSL_ROOT_DIR}/lib/VC/x64/MD/libssl.lib")
  message(FATAL_ERROR "SSL library escaped portable root: ${OPENSSL_SSL_LIBRARY}")
endif()
if(NOT OPENSSL_CRYPTO_LIBRARY STREQUAL "${OPENSSL_ROOT_DIR}/lib/VC/x64/MD/libcrypto.lib")
  message(FATAL_ERROR "Crypto library escaped portable root: ${OPENSSL_CRYPTO_LIBRARY}")
endif()
if(NOT OPENSSL_INCLUDE_DIR STREQUAL "${OPENSSL_ROOT_DIR}/include")
  message(FATAL_ERROR "Headers escaped portable root")
endif()
'''.replace('''foreach(kind SSL CRYPTO)
  get_target_property(location OpenSSL::${kind} IMPORTED_LOCATION_RELEASE)
endforeach()
''', ''))
    def configure(build):
        return subprocess.run(["cmake", "-S", str(source), "-B", str(build),
                               "-DOPENSSL_ROOT_DIR=" + sdk.as_posix()],
                              capture_output=True, text=True)
    good = configure(root / "good-build")
    if good.returncode:
        raise SystemExit(good.stdout + good.stderr)
    print("PASS Windows portable SDK overrides stale system SSL_EAY/LIB_EAY cache")
    (libs / "libcrypto.lib").unlink()
    bad = configure(root / "good-build")
    if bad.returncode == 0 or "Incomplete OpenSSL SDK" not in bad.stdout + bad.stderr:
        raise SystemExit("FAIL incomplete SDK silently fell back to another installation\n" + bad.stdout + bad.stderr)
    print("PASS incomplete SDK fails even with populated cache; no system fallback")
