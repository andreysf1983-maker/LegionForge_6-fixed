
if(WIN32)
 set(BOOST_DEBUG ON)
  # LegionForge: accept BOOST_ROOT either from the environment or from -DBOOST_ROOT
  # (build_server.ps1 passes both). Prebuilt Boost for VS2022 lives in lib64-msvc-14.3.
  if(NOT BOOST_ROOT AND DEFINED ENV{BOOST_ROOT})
    set(BOOST_ROOT $ENV{BOOST_ROOT})
  endif()
  if(BOOST_ROOT)
    file(TO_CMAKE_PATH "${BOOST_ROOT}" BOOST_ROOT)
    if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS 19.0)
      list(APPEND BOOST_LIBRARYDIR ${BOOST_ROOT}/lib${PLATFORM}-msvc-12.0)
    elseif(CMAKE_CXX_COMPILER_VERSION VERSION_LESS 19.10)
      list(APPEND BOOST_LIBRARYDIR ${BOOST_ROOT}/lib${PLATFORM}-msvc-14.0)
    else()
      list(APPEND BOOST_LIBRARYDIR
        ${BOOST_ROOT}/lib${PLATFORM}-msvc-14.3
        ${BOOST_ROOT}/lib${PLATFORM}-msvc-14.2
        ${BOOST_ROOT}/lib${PLATFORM}-msvc-14.1
        ${BOOST_ROOT}/lib${PLATFORM}-msvc-14.0)
    endif()
  else()
    message(FATAL_ERROR "BOOST_ROOT is not set (neither -DBOOST_ROOT nor environment). Run build_server.bat - it downloads Boost into tools\\boost_1_83_0 automatically.")
  endif()

  set(Boost_USE_STATIC_LIBS        ON)
  set(Boost_USE_MULTITHREADED      ON)
  set(Boost_USE_STATIC_RUNTIME     OFF)
endif()

# The core uses the official Boost.Process and executor-based Asio APIs.
# Keep this consistent with the portable installer and compatibility tests.
find_package(Boost 1.83 REQUIRED system filesystem thread program_options iostreams regex)

# Find if Boost was compiled in C++03 mode because it requires -DBOOST_NO_CXX11_SCOPED_ENUMS

include (CheckCXXSourceCompiles)

set(CMAKE_REQUIRED_INCLUDES ${Boost_INCLUDE_DIR})
set(CMAKE_REQUIRED_LIBRARIES ${Boost_SYSTEM_LIBRARY} ${Boost_FILESYSTEM_LIBRARY} ${Boost_IOSTREAMS_LIBRARY})
set(CMAKE_REQUIRED_FLAGS "-std=c++11")
unset(boost_filesystem_copy_links_without_NO_SCOPED_ENUM CACHE)
check_cxx_source_compiles("
  #include <boost/filesystem/path.hpp>
  #include <boost/filesystem/operations.hpp>
  int main() { boost::filesystem::copy_file(boost::filesystem::path(), boost::filesystem::path()); }"
boost_filesystem_copy_links_without_NO_SCOPED_ENUM)
unset(CMAKE_REQUIRED_INCLUDES CACHE)
unset(CMAKE_REQUIRED_LIBRARIES CACHE)
unset(CMAKE_REQUIRED_FLAGS CACHE)

if (NOT boost_filesystem_copy_links_without_NO_SCOPED_ENUM)
  set(OPTIONAL_BOOST_NO_SCOPED_ENUMS -DBOOST_NO_CXX11_SCOPED_ENUMS)
endif()

add_library(boost INTERFACE)

target_link_libraries(boost
  INTERFACE
    ${Boost_LIBRARIES})

target_include_directories(boost
  INTERFACE
    ${Boost_INCLUDE_DIRS})

target_compile_definitions(boost
  INTERFACE
    -DBOOST_DATE_TIME_NO_LIB
    -DBOOST_REGEX_NO_LIB
    -DBOOST_CHRONO_NO_LIB
    # LegionForge: only header-only boost::locale::conv::utf_to_utf is used
    # (WordFilterMgr.cpp, cs_misc.cpp). Without this, boost/locale/config.hpp
    # auto-links libboost_locale-vc143-mt-x64-1_83.lib -> LNK1104 in worldserver.
    -DBOOST_LOCALE_NO_LIB
    ${OPTIONAL_BOOST_NO_SCOPED_ENUMS})

# Safety net: any remaining Boost #pragma comment(lib) resolves from the Boost lib dir.
if(Boost_LIBRARY_DIRS)
  target_link_directories(boost INTERFACE ${Boost_LIBRARY_DIRS})
endif()
