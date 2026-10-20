/*
 * Copyright (C) 2026 LegionForge Project <https://legionforge.ru/>
 * LegionForge 7.3.5.26124 - modified 2026-10-20.
 * Upstream copyright notices below are retained as required by the GNU GPL v2.
 * Copyright (C) 2008-2016 TrinityCore <http://www.trinitycore.org/>
 * Copyright (C) 2005-2009 MaNGOS <http://getmangos.com/>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include "Errors.h"
#include "Duration.h"

// Флаг выставляется ядром при падении (объявлен в Util.h). Здесь он объявлен
// напрямую, чтобы Errors.cpp не тянул тяжёлые заголовки (boost/fmt) и всегда
// компилировался первым в common.
extern bool m_worldCrashChecker;

#include <cstdio>
#include <cstdlib>
#include <thread>
#include <cstdarg>
#include <csignal>
#include <chrono>

namespace Trinity {

void Assert(char const* file, int line, char const* function, char const* message)
{
    fprintf(stderr, "\n%s:%i in %s ASSERTION FAILED:\n  %s\n",
            file, line, function, message);
    std::abort();
}

void Assert(char const* file, int line, char const* function, char const* message, char const* format, ...)
{
    va_list args;
    va_start(args, format);

    fprintf(stderr, "\n%s:%i in %s ASSERTION FAILED:\n  %s ", file, line, function, message);
    vfprintf(stderr, format, args);
    fprintf(stderr, "\n");
    fflush(stderr);

    va_end(args);
    std::abort();
}

void Fatal(char const* file, int line, char const* function, char const* message, ...)
{
    va_list args;
    va_start(args, message);

    fprintf(stderr, "\n%s:%i in %s FATAL ERROR:\n  ", file, line, function);
    vfprintf(stderr, message, args);
    fprintf(stderr, "\n");
    fflush(stderr);

    std::this_thread::sleep_for(std::chrono::seconds(10));
    std::abort();
}

void Error(char const* file, int line, char const* function, char const* message)
{
    fprintf(stderr, "\n%s:%i in %s ERROR:\n  %s\n",
                   file, line, function, message);
    std::abort();
}

void Warning(char const* file, int line, char const* function, char const* message)
{
    fprintf(stderr, "\n%s:%i in %s WARNING:\n  %s\n",
                   file, line, function, message);
}

void Abort(char const* file, int line, char const* function)
{
    fprintf(stderr, "\n%s:%i in %s ABORTED.\n",
                   file, line, function);
    std::abort();
}

void AbortHandler(int signum)
{
    if (m_worldCrashChecker) // Prevent double dump if crash already run
    {
        std::this_thread::sleep_for(Milliseconds(5000)); // Waiting when gdb is dump this thread
        signal(signum, SIG_DFL);
        std::abort();
    }
    else
    {
        m_worldCrashChecker = true;
        fprintf(stderr, "AbortHandler: crash detected (signal %i)\n", signum);
        fflush(stderr);

        std::this_thread::sleep_for(Milliseconds(5000)); // Waiting for save and exit from work thread

        signal(signum, SIG_DFL);
        exit(1);
    }
}

void DumpHandler(int signum)
{
    if (m_worldCrashChecker) // Prevent double dump if crash already run
    {
        std::this_thread::sleep_for(Milliseconds(5000)); // Waiting when gdb is dump this thread
        signal(signum, SIG_DFL);
        std::abort();
    }
    else
    {
        m_worldCrashChecker = true;
        fprintf(stderr, "DumpHandler: crash detected (signal %i)\n", signum);
        fflush(stderr);

        std::this_thread::sleep_for(Milliseconds(5000)); // Waiting for save and exit from work thread

        signal(signum, SIG_DFL);
        exit(3);
    }
}

} // namespace Trinity
