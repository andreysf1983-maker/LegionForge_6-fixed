/*
 * Copyright (C) 2026 LegionForge Project <https://legionforge.ru/>
 * LegionForge 7.3.5.26124 - modified 2026-10-20.
 * Upstream copyright notices below are retained as required by the GNU GPL v2.
 * Copyright (C) 2008-2016 TrinityCore <http://www.trinitycore.org/>
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

#ifndef DEF_WELLOFETERNITY_H
#define DEF_WELLOFETERNITY_H

#define WoEScriptName "instance_well_of_eternity"

enum WoEDataTypes
{
    DATA_PEROTHARN          = 0,
    DATA_QUEEN_AZSHARA      = 1,
    DATA_MANNOROTH          = 2,
    DATA_VAROTHEN           = 3,
    DATA_EVENT_ILLIDAN      = 4
};

enum WoECreatureIds
{
    NPC_PEROTHARN           = 55085,
    NPC_QUEEN_AZSHARA       = 54853,
    NPC_MANNOROTH           = 54969,
    NPC_VAROTHEN            = 55419,
    NPC_ILLIDAN             = 55532,
    NPC_TYRANDE             = 55500,
    NPC_MALFURION           = 55570
};

enum WoEGameObjectIds
{
    GO_COURTYARD_DOOR       = 210085,
    GO_PORTAL_TO_AZSHARA    = 210086
};

#endif // DEF_WELLOFETERNITY_H
