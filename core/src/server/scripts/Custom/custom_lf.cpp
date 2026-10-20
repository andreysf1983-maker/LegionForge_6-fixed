/*
 * Copyright (C) 2026 LegionForge Project <https://legionforge.ru/>
 * LegionForge 7.3.5.26124 - modified 2026-10-20.
 * Upstream copyright notices below are retained as required by the GNU GPL v2.
 * Copyright (C) 2008-2012 TrinityCore <http://www.trinitycore.org/>
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

#include "ScriptMgr.h"

class phase_sacer_holy_41957 : public PlayerScript
{
public:
    phase_sacer_holy_41957() : PlayerScript("phase_sacer_holy_41957") {}


    void OnUpdate(Player* player, uint32 diff) override
    {
        if (player->getClass() == CLASS_PRIEST && player->GetMapId() == 0 && player->GetZoneId() == 85 && player->GetAreaId() == 173
            && player->GetQuestStatus(41957) == QUEST_STATUS_COMPLETE)
        {
            player->TeleportTo(1220, -785.4245f, 4558.1738f, 726.3496f, 1.632f);
        }

        //Poniendo fase 6230 al llegar a dalaran con la quest completa
        if (player->getClass() == CLASS_PRIEST && player->GetMapId() == 1220 && 
            (player->GetQuestStatus(41957) == QUEST_STATUS_COMPLETE || player->GetQuestStatus(41957) == QUEST_STATUS_REWARDED) 
            && player->GetQuestStatus(41966) == QUEST_STATUS_NONE) 
        {                     
            std::set<uint32> phaseIds_sacer_holy_quest_41957;
            
            {
                if (PhaseEntry const* phase = sPhaseStore.LookupEntry(6230))
                    phaseIds_sacer_holy_quest_41957.insert(phase->ID);
            }
                  player->SetPhaseId(phaseIds_sacer_holy_quest_41957, true);
           
        }
                
        if (player->getClass() == CLASS_PRIEST && player->GetMapId() == 1220 &&
            (player->GetQuestStatus(41966)== QUEST_STATUS_INCOMPLETE  || player->GetQuestStatus(41966) == QUEST_STATUS_COMPLETE || 
                player->GetQuestStatus(41966) == QUEST_STATUS_REWARDED) && player->GetQuestStatus(41967) == QUEST_STATUS_NONE)
        {
            std::set<uint32> phaseIds_sacer_holy_quest_41966;

            {
                if (PhaseEntry const* phase1 = sPhaseStore.LookupEntry(6231))
                    phaseIds_sacer_holy_quest_41966.insert(phase1->ID);
            }
            player->SetPhaseId(phaseIds_sacer_holy_quest_41966, true);

        }
         
        if (player->getClass() == CLASS_PRIEST && player->GetMapId() == 1220 &&
            player->GetQuestStatus(41966) == QUEST_STATUS_REWARDED && player->GetQuestStatus(41967) == QUEST_STATUS_REWARDED &&
            player->GetQuestStatus(42074) == QUEST_STATUS_REWARDED)
        {
            std::set<uint32> phase_end = player->GetPhases();
            phase_end.erase(6230);
            phase_end.erase(6231);
            player->SetPhaseId(phase_end, true);
        }          

    }
};


class quest_39654 : public PlayerScript
{
public:
    quest_39654() : PlayerScript("quest_39654") {}


    void OnUpdate(Player* player, uint32 diff) override
    {
        if ((player->GetQuestStatus(39654) == QUEST_STATUS_COMPLETE) && (player->GetQuestStatus(39654) != QUEST_STATUS_REWARDED))
        {
            player->learnSpell(192085, false);

        }

    }
};

class boss_announcer1 : public PlayerScript
{
public:
    boss_announcer1() : PlayerScript("boss_announcer1") {}

    void OnCreatureKill(Player* player, Creature* boss)
    {
        if (boss->isWorldBoss())
        {
            std::string plr = player->GetName();
            std::string boss_n = boss->GetName();
            // bool ingroup = player->GetGroup();
            std::string tag_colour = "7bbef7";
            std::string plr_colour = "7bbef7";
            std::string boss_colour = "ff0000";
            std::ostringstream stream;
            stream << "|CFF" << tag_colour <<
                "|r|cff" << plr_colour << " " << plr <<
                "|r y su grupo mataron a |CFF" << boss_colour << "[" << boss_n << "]|r " "que es un jefe" << "!";
            sWorld->SendServerMessage(SERVER_MSG_STRING, stream.str().c_str());
        }

    };
};

class resu_mago_gesta : public PlayerScript
{
public:
    resu_mago_gesta() : PlayerScript("resu_mago_gesta") {}


    void OnUpdate(Player* player, uint32 diff) override
    {
        if (player->getClass() == CLASS_MAGE && player->GetMapId() == 1494 && player->GetZoneId() == 7777)
        {
            if (player->HasAuraType(SPELL_AURA_SPIRIT_OF_REDEMPTION))
                player->RemoveAurasByType(SPELL_AURA_MOD_SHAPESHIFT);


            if (!player->isAlive())
            {
                player->ResurrectPlayer(1.0f);
                player->SpawnCorpseBones();
            }
        }

    }
};










void AddSC_custom_lf()
{
    new phase_sacer_holy_41957();
    new quest_39654();
    new boss_announcer1();
    new resu_mago_gesta();
 
}
