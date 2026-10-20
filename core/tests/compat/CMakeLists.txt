# Exercise the same include directories and libraries used by the server.
add_executable(legionforge_compat_tests dependency_compat.cpp)
target_compile_features(legionforge_compat_tests PRIVATE cxx_std_17)
target_link_libraries(legionforge_compat_tests PRIVATE common process)
add_test(NAME legionforge_dependency_compat COMMAND legionforge_compat_tests)
set_tests_properties(legionforge_dependency_compat PROPERTIES TIMEOUT 30)

get_target_property(_process_includes process INTERFACE_INCLUDE_DIRECTORIES)
if(_process_includes)
  message(FATAL_ERROR "The process target must not export the bundled Boost.Process 0.5 include directory")
endif()
