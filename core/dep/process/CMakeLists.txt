# Copyright (C) 2008-2016 TrinityCore <http://www.trinitycore.org/>
#
# This file is free software; as a special exception the author gives
# unlimited permission to copy and/or distribute it, with or without
# modifications, as long as this notice is preserved.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY, to the extent permitted by law; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

add_library(process INTERFACE)

# Keep the target name for common/shared, but do NOT export this directory.
# Its bundled Boost.Process 0.5 headers shadow the official Boost 1.83 API and
# select windows::child without wait()/exit_code()/terminate(). The process
# implementation now comes exclusively from the linked Boost installation.

target_link_libraries(process
  INTERFACE
    boost)
