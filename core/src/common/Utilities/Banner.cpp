/*
 * Copyright (C) 2026 LegionForge Project <https://legionforge.ru/>
 * LegionForge 7.3.5.26124 - modified 2026-10-20.
 * Upstream copyright notices below are retained as required by the GNU GPL v2.
 * Copyright (C) 2008-2019 TrinityCore <https://www.trinitycore.org/>
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

#include "Banner.h"
#include "GitRevision.h"
#include "StringFormat.h"

void Trinity::Banner::Show(char const* applicationName, void(*log)(char const* text), void(*logExtraInfo)())
{
    log(StringFormat("%s (%s)", GitRevision::GetFullVersion(), applicationName).c_str());
    log("<Ctrl-C> to stop.\n");
    log("  _                   _               ______                     ");
    log(" | |                 (_)              |  ___|                    ");
    log(" | |     ___  __ _ _ _  ___  _ __     | |_ ___  _ __ __ _  ___   ");
    log(" | |    / _ \\/ _` | | |/ _ \\| '_ \\    |  _/ _ \\| '__/ _` |/ _ \\  ");
    log(" | |___|  __/ (_| | | | (_) | | | |   | || (_) | | | (_| |  __/  ");
    log(" \\_____/\\___|\\__, |_|_|\\___/|_| |_|   \\_| \\___/|_|  \\__, |\\___|  ");
    log("              __/ |                                  __/ |       ");
    log("             |___/                                  |___/        ");
    log("");
    log("        ( L E G I O N F O R G E   P R O J E C T )");
    log("        World of Warcraft Legion 7.3.5 - client build 26124");
    log("        Build date: 2026-10-20\n");

    if (logExtraInfo)
        logExtraInfo();
}
