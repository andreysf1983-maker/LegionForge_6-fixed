/*
 * Copyright (C) 2026 LegionForge Project <https://legionforge.ru/>
 * LegionForge 7.3.5.26124 - modified 2026-10-20.
 *
 * Full native server implementation for:
 *  1. Shadowlands-style In-Place Item Upgrade System & Dalaran NPC (900104) + .upgrade
 *     (Valor currency 1191 & Essence 200001; keeps gems, enchants, sockets, tier bonuses, transmog;
 *      upgrades normal/raid/M+ Legion gear up to 1000 ilvl and Legendaries up to 1200 ilvl in steps of +5).
 *  2. Shadowlands / Dragonflight / The War Within Cross-Armor NPC Transmogrifier & Stylist (900105) + .transmog
 *     (unlocks all 5,652 backported armors & weapons in Item.db2 + Weapon/Shield Illusions + TWW/SL/DF Morphs).
 *  3. Dragonflight 10.2 Somnowls & Dream Cats, Shadowlands Ardenweald Runestags/Moths/Lupines,
 *     BfA Kul Tiran Wicker & Zandalari Dinosaur Druid Forms, and Legion Mage Tower Forms
 *     (via Dalaran Scrolls, 3D Druid Barbershop UI `aio_druid_barbershop`, Stylist NPC, and `.form`).
 *  4. Warlock Antorus/Legion Demon Appearance Scrolls (`legionforge_demon_scroll_item` + `.demon`).
 *  5. All 15 Allied & Custom Races (Haranir TWW, Dracthyr DF + `.visage` true Dragon model 87870,
 *     Vulpera, Dark Iron, Kul Tiran, Mag'har, Zandalari, Thin Human, Broken, Vrykul, Taunka) + `ULDR.FakeRace`.
 */

#include "ScriptMgr.h"
#include "ScriptedGossip.h"
#include "Chat.h"
#include "DatabaseEnv.h"
#include "DB2Stores.h"
#include "Item.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Pet.h"
#include "Player.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "World.h"
#include "WorldSession.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <map>
#include <mutex>
#include <set>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

extern uint32 (*g_LegionForgeFormModelHook)(Player const*, uint8);
extern void (*g_LegionForgeDemonAppearanceHook)(Player*, Creature*);

namespace
{
    constexpr uint32 ITEM_ESSENCE_LF            = 200001;
    constexpr uint32 CURRENCY_VALOR             = 1191;
    constexpr uint32 UPGRADE_ID_BASE            = 9000;   // hotfixes.item_upgrade IDs 9001..9080 => +5..+400 ilvl
    constexpr uint32 MAX_UPGRADE_STEP_INDEX     = 80;     // 80 * 5 = +400 ilvl max increment
    constexpr uint32 MAX_NORMAL_ILVL            = 1000;
    constexpr uint32 MAX_LEGENDARY_ILVL         = 1200;
    constexpr uint32 DISPLAY_DRACTHYR_TRUE_FORM = 87870;  // ModelID 18459 (FileDataID 4559662 in client CreatureModelData.db2)

    struct FormScrollDef
    {
        uint32 itemId = 0;
        uint8 formId = 0;
        uint32 displayId = 0;
        uint8 requiredClass = CLASS_DRUID;
        std::string comment;
    };

    struct DemonScrollDef
    {
        uint32 itemId = 0;
        uint32 petEntry = 0;
        uint32 displayId = 0;
        float scale = 1.0f;
        std::string comment;
    };

    struct SavedDemonChoice
    {
        uint32 displayId = 0;
        float scale = 1.0f;
        uint32 sourceItem = 0;
    };

    std::mutex g_lfMutex;
    std::unordered_map<uint32, FormScrollDef> g_formScrolls;
    std::map<std::pair<uint8, uint8>, uint32> g_formDefaults;
    std::unordered_map<uint32, DemonScrollDef> g_demonScrolls;
    std::unordered_map<uint32 /*itemId*/, uint32 /*itemModifiedAppearanceId*/> g_itemFirstAppearance;

    std::unordered_map<uint64, std::unordered_map<uint8, uint32>> g_playerForms;
    std::unordered_map<uint64, std::unordered_map<uint32, SavedDemonChoice>> g_playerDemons;
    std::unordered_map<uint64, uint8> g_playerRacialPack;

    static char const* GetEquipSlotRuName(uint8 slot)
    {
        switch (slot)
        {
            case EQUIPMENT_SLOT_HEAD:      return "Голова";
            case EQUIPMENT_SLOT_NECK:      return "Шея";
            case EQUIPMENT_SLOT_SHOULDERS: return "Плечи";
            case EQUIPMENT_SLOT_BODY:      return "Рубашка";
            case EQUIPMENT_SLOT_CHEST:     return "Грудь";
            case EQUIPMENT_SLOT_WAIST:     return "Пояс";
            case EQUIPMENT_SLOT_LEGS:      return "Ноги";
            case EQUIPMENT_SLOT_FEET:      return "Ступни";
            case EQUIPMENT_SLOT_WRISTS:    return "Запястья";
            case EQUIPMENT_SLOT_HANDS:     return "Кисти рук";
            case EQUIPMENT_SLOT_FINGER1:   return "Кольцо 1";
            case EQUIPMENT_SLOT_FINGER2:   return "Кольцо 2";
            case EQUIPMENT_SLOT_TRINKET1:  return "Аксессуар 1";
            case EQUIPMENT_SLOT_TRINKET2:  return "Аксессуар 2";
            case EQUIPMENT_SLOT_BACK:      return "Плащ / Крылья";
            case EQUIPMENT_SLOT_MAINHAND:  return "Правая рука";
            case EQUIPMENT_SLOT_OFFHAND:   return "Левая рука / Щит";
            case EQUIPMENT_SLOT_TABARD:    return "Гербовая накидка";
            default:                       return "Слот";
        }
    }

    static bool IsUpgradeableItem(Item* item, uint32& maxTargetIlvl)
    {
        if (!item)
            return false;
        ItemTemplate const* proto = item->GetTemplate();
        if (!proto || proto->GetArtifactID() != 0)
            return false;
        uint8 inv = proto->GetInventoryType();
        if (inv == INVTYPE_NON_EQUIP || inv == INVTYPE_BODY || inv == INVTYPE_TABARD || inv == INVTYPE_BAG)
            return false;
        maxTargetIlvl = (proto->GetQuality() == ITEM_QUALITY_LEGENDARY) ? MAX_LEGENDARY_ILVL : MAX_NORMAL_ILVL;
        return true;
    }

    static void CalcUpgradeCost(uint32 currentIlvl, bool isLegendary, uint32& valorCost, uint32& essenceCost)
    {
        if (isLegendary)
        {
            uint32 step = currentIlvl > 1000 ? (currentIlvl - 1000) / 5 : 0;
            valorCost = 500 + step * 50;
            essenceCost = 100 + step * 25;
        }
        else
        {
            uint32 step = currentIlvl > 880 ? (currentIlvl - 880) / 5 : 0;
            valorCost = 250 + step * 25;
            essenceCost = 25 + step * 10;
        }
    }

    static bool PerformShadowlandsUpgrade(Player* player, uint8 slot, bool payWithEssence, std::string& feedback)
    {
        Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
        uint32 maxCap = 0;
        if (!IsUpgradeableItem(item, maxCap))
        {
            feedback = "|cffff4040[LegionForge]|r Этот слот пуст или предмет нельзя улучшить (артефакты усиливаются реликвиями).";
            return false;
        }

        uint32 curIlvl = item->GetItemLevel(player->getLevel());
        if (curIlvl >= maxCap)
        {
            std::ostringstream ss;
            ss << "|cffffd000[LegionForge]|r Предмет уже достиг максимального уровня (" << curIlvl << " / " << maxCap << " ilvl)!";
            feedback = ss.str();
            return false;
        }

        uint32 curMod = item->GetModifier(ITEM_MODIFIER_UPGRADE_ID);
        uint32 curRank = (curMod > UPGRADE_ID_BASE && curMod <= UPGRADE_ID_BASE + MAX_UPGRADE_STEP_INDEX) ? (curMod - UPGRADE_ID_BASE) : 0;
        if (curRank >= MAX_UPGRADE_STEP_INDEX)
        {
            feedback = "|cffffd000[LegionForge]|r Достигнут максимальный ранг улучшения этого предмета (+400 ilvl).";
            return false;
        }

        bool isLeg = item->GetTemplate()->GetQuality() == ITEM_QUALITY_LEGENDARY;
        uint32 valorCost = 0, essenceCost = 0;
        CalcUpgradeCost(curIlvl, isLeg, valorCost, essenceCost);

        if (payWithEssence)
        {
            if (!player->HasItemCount(ITEM_ESSENCE_LF, essenceCost))
            {
                std::ostringstream ss;
                ss << "|cffff4040[LegionForge]|r Недостаточно Сущности LegionForge: нужно " << essenceCost << " шт.";
                feedback = ss.str();
                return false;
            }
            player->DestroyItemCount(ITEM_ESSENCE_LF, essenceCost, true);
        }
        else
        {
            if (!player->HasCurrency(CURRENCY_VALOR, valorCost))
            {
                std::ostringstream ss;
                ss << "|cffff4040[LegionForge]|r Недостаточно Доблести (Valor): нужно " << valorCost << " ед. (добывается с мини-боссов и в подземельях).";
                feedback = ss.str();
                return false;
            }
            player->ModifyCurrency(CURRENCY_VALOR, -int32(valorCost));
        }

        uint32 nextRank = curRank + 1;
        uint32 newUpgradeId = UPGRADE_ID_BASE + nextRank;

        player->_ApplyItemBonuses(item, slot, false);
        item->SetModifier(ITEM_MODIFIER_UPGRADE_ID, newUpgradeId);
        player->_ApplyItemBonuses(item, slot, true);
        item->SetState(ITEM_CHANGED, player);
        item->SendUpdateToPlayer(player);
        player->SaveToDB();

        uint32 newIlvl = item->GetItemLevel(player->getLevel());
        std::ostringstream ok;
        ok << "|cff40ff40[LegionForge — Улучшение Shadowlands]|r "
           << GetEquipSlotRuName(slot) << ": |cffffd000" << curIlvl << " -> " << newIlvl
           << " ilvl|r (Ранг " << nextRank << ", характеристики пересчитаны, чары и камни сохранены)!";
        feedback = ok.str();
        return true;
    }

    static bool ApplyCustomTransmogToSlot(Player* player, uint8 slot, uint32 sourceItemId, std::string& feedback)
    {
        Item* equipped = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
        if (!equipped)
        {
            feedback = "|cffff4040[LegionForge]|r Сначала наденьте предмет экипировки в выбранный слот.";
            return false;
        }

        if (sourceItemId == 0)
        {
            equipped->SetModifier(ITEM_MODIFIER_TRANSMOG_APPEARANCE_ALL_SPECS, 0);
            player->SetVisibleItemSlot(slot, equipped);
            equipped->SetState(ITEM_CHANGED, player);
            player->SaveToDB();
            feedback = "|cff40ff40[LegionForge]|r Трансмогрификация слота сброшена к оригинальному виду.";
            return true;
        }

        uint32 appearanceModId = 0;
        {
            std::lock_guard<std::mutex> lock(g_lfMutex);
            auto it = g_itemFirstAppearance.find(sourceItemId);
            if (it != g_itemFirstAppearance.end())
                appearanceModId = it->second;
        }

        if (!appearanceModId)
        {
            feedback = "|cffff4040[LegionForge]|r Для этого ItemID не найдена 3D-модель в ItemModifiedAppearance.db2 клиента.";
            return false;
        }

        equipped->SetModifier(ITEM_MODIFIER_TRANSMOG_APPEARANCE_ALL_SPECS, appearanceModId);
        player->SetVisibleItemSlot(slot, equipped);
        equipped->SetState(ITEM_CHANGED, player);
        player->SaveToDB();

        std::ostringstream ok;
        ok << "|cff40ff40[LegionForge — Трансмогрификация]|r Слот «" << GetEquipSlotRuName(slot)
           << "» принял облик предмета ID " << sourceItemId << " (AppearanceID " << appearanceModId << ")!";
        feedback = ok.str();
        return true;
    }

    static std::unordered_map<uint8, std::vector<uint32>> const& GetRaceSpellsTable()
    {
        static std::unordered_map<uint8, std::vector<uint32>> const table =
        {
            { RACE_HUMAN,               { 59752, 20598, 20597 } },
            { RACE_ORC,                 { 20572, 20573, 21563 } },
            { RACE_DWARF,               { 20594, 59224, 20596 } },
            { RACE_NIGHTELF,            { 58984, 20582, 20585, 21009, 154748 } },
            { RACE_UNDEAD_PLAYER,       { 7744, 20577, 5227, 20579 } },
            { RACE_TAUREN,              { 20549, 20550, 154743, 20552 } },
            { RACE_GNOME,               { 20589, 20591, 92680, 20593 } },
            { RACE_TROLL,               { 26297, 58943, 20555 } },
            { RACE_GOBLIN,              { 69070, 69041, 69042, 69046 } },
            { RACE_BLOODELF,            { 28730, 154742, 28877 } },
            { RACE_DRAENEI,             { 59542, 6562, 28875 } },
            { RACE_WORGEN,              { 68992, 68975, 68976, 87840 } },
            { RACE_PANDAREN_ALLIANCE,   { 107079, 107072, 107074 } },
            { RACE_PANDAREN_HORDE,      { 107079, 107072, 107074 } },
            { RACE_NIGHTBORNE,          { 260364, 255661, 255664, 255665 } },
            { RACE_HIGHMOUNTAIN_TAUREN, { 255654, 255655, 255656, 255658, 255659 } },
            { RACE_VOID_ELF,            { 256948, 255667, 255668, 255669, 255670 } },
            { RACE_LIGHTFORGED_DRAENEI, { 255647, 259930, 255651, 255652, 255653 } },
            { RACE_DARK_IRON_DWARF,     { 265221, 265222, 265223, 265224, 265225 } },
            { RACE_MAGHAR_ORC,          { 274738, 273216, 273217, 273220 } },
            { RACE_HARANIR,             { 58984, 255659, 154748, 20555 } },
            { RACE_DRACTHYR,            { 68992, 256948, 154742 } },
            { RACE_BROKEN,              { 59542, 20582, 59221 } },
            { RACE_VULPERA,             { 69046, 69070, 255656 } },
            { RACE_VRYKUL,              { 20572, 20550, 59224 } },
            { RACE_KUL_TIRAN,           { 20549, 255659, 20598 } },
            { RACE_TAUNKA,              { 20549, 20550, 20572 } },
            { RACE_ZANDALARI_TROLL,     { 26297, 274738, 20555 } },
            { RACE_THIN_HUMAN,          { 59752, 20598, 20589 } },
        };
        return table;
    }

    static std::set<uint32> const& GetAllManagedRacialSpells()
    {
        static std::set<uint32> all = []()
        {
            std::set<uint32> s;
            for (auto const& kv : GetRaceSpellsTable())
                for (uint32 sp : kv.second)
                    s.insert(sp);
            return s;
        }();
        return all;
    }

    uint32 GetCustomFormModelImpl(Player const* player, uint8 formId)
    {
        if (!player)
            return 0;

        std::lock_guard<std::mutex> lock(g_lfMutex);
        auto pIt = g_playerForms.find(player->GetGUIDLow());
        if (pIt != g_playerForms.end())
        {
            auto fIt = pIt->second.find(formId);
            if (fIt != pIt->second.end() && fIt->second != 0)
                return fIt->second;
        }

        auto raceDef = g_formDefaults.find(std::make_pair(formId, player->getRace()));
        if (raceDef != g_formDefaults.end() && raceDef->second != 0)
            return raceDef->second;

        auto globalDef = g_formDefaults.find(std::make_pair(formId, uint8(0)));
        if (globalDef != g_formDefaults.end() && globalDef->second != 0)
            return globalDef->second;

        return 0;
    }

    void ApplyCustomDemonAppearanceImpl(Player* owner, Creature* summon)
    {
        if (!owner || !summon)
            return;

        SavedDemonChoice choice;
        {
            std::lock_guard<std::mutex> lock(g_lfMutex);
            auto pIt = g_playerDemons.find(owner->GetGUIDLow());
            if (pIt == g_playerDemons.end())
                return;
            auto dIt = pIt->second.find(summon->GetEntry());
            if (dIt == pIt->second.end() || dIt->second.displayId == 0)
                return;
            choice = dIt->second;
        }

        summon->SetDisplayId(choice.displayId);
        summon->SetNativeDisplayId(choice.displayId);
        if (choice.scale > 0.05f)
            summon->SetObjectScale(choice.scale);
    }

    void LoadLegionForgeTables()
    {
        CharacterDatabase.DirectExecute(
            "CREATE TABLE IF NOT EXISTS `character_form_appearance` ("
            "`guid` BIGINT UNSIGNED NOT NULL,"
            "`form_id` TINYINT UNSIGNED NOT NULL,"
            "`display_id` INT UNSIGNED NOT NULL,"
            "`source_item` INT UNSIGNED NOT NULL DEFAULT 0,"
            "PRIMARY KEY (`guid`, `form_id`)"
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

        CharacterDatabase.DirectExecute(
            "CREATE TABLE IF NOT EXISTS `character_demon_appearance` ("
            "`guid` BIGINT UNSIGNED NOT NULL,"
            "`pet_entry` INT UNSIGNED NOT NULL,"
            "`display_id` INT UNSIGNED NOT NULL,"
            "`scale` FLOAT NOT NULL DEFAULT 1,"
            "`source_item` INT UNSIGNED NOT NULL DEFAULT 0,"
            "PRIMARY KEY (`guid`, `pet_entry`)"
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

        CharacterDatabase.DirectExecute(
            "CREATE TABLE IF NOT EXISTS `character_custom_racials` ("
            "`guid` BIGINT UNSIGNED NOT NULL PRIMARY KEY,"
            "`race_id` TINYINT UNSIGNED NOT NULL DEFAULT 0"
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

        std::unordered_map<uint32, FormScrollDef> forms;
        std::map<std::pair<uint8, uint8>, uint32> defaults;
        std::unordered_map<uint32, DemonScrollDef> demons;
        std::unordered_map<uint32, uint32> firstApp;

        if (QueryResult r = WorldDatabase.Query("SELECT item_id, form_id, display_id, required_class, comment FROM legionforge_form_scrolls ORDER BY item_id"))
        {
            do
            {
                Field* f = r->Fetch();
                FormScrollDef d;
                d.itemId = f[0].GetUInt32();
                d.formId = f[1].GetUInt8();
                d.displayId = f[2].GetUInt32();
                d.requiredClass = f[3].GetUInt8();
                d.comment = f[4].GetString();
                forms[d.itemId] = d;
            } while (r->NextRow());
        }

        if (QueryResult r = WorldDatabase.Query("SELECT form_id, race_id, display_id FROM legionforge_form_defaults"))
        {
            do
            {
                Field* f = r->Fetch();
                defaults[std::make_pair(f[0].GetUInt8(), f[1].GetUInt8())] = f[2].GetUInt32();
            } while (r->NextRow());
        }

        if (QueryResult r = WorldDatabase.Query("SELECT item_id, pet_entry, display_id, scale, comment FROM legionforge_demon_scrolls"))
        {
            do
            {
                Field* f = r->Fetch();
                DemonScrollDef d;
                d.itemId = f[0].GetUInt32();
                d.petEntry = f[1].GetUInt32();
                d.displayId = f[2].GetUInt32();
                d.scale = f[3].GetFloat();
                d.comment = f[4].GetString();
                demons[d.itemId] = d;
            } while (r->NextRow());
        }

        for (ItemModifiedAppearanceEntry const* ima : sItemModifiedAppearanceStore)
        {
            if (ima && firstApp.find(ima->ItemID) == firstApp.end())
                firstApp[ima->ItemID] = ima->ID;
        }

        std::lock_guard<std::mutex> lock(g_lfMutex);
        g_formScrolls.swap(forms);
        g_formDefaults.swap(defaults);
        g_demonScrolls.swap(demons);
        g_itemFirstAppearance.swap(firstApp);
    }

    void SyncPlayerLanguagesAndRacials(Player* player, uint8 overrideRacePack = 0)
    {
        if (!player)
            return;

        uint32 team = Player::TeamForRace(player->getRace());
        if (team == HORDE)
        {
            if (!player->HasSpell(669))
                player->learnSpell(669, false);
            player->SetSkill(109, 0, 300, 300);
        }
        else if (team == ALLIANCE)
        {
            if (!player->HasSpell(668))
                player->learnSpell(668, false);
            player->SetSkill(98, 0, 300, 300);
        }

        uint8 targetRace = overrideRacePack ? overrideRacePack : player->getRace();
        auto const& table = GetRaceSpellsTable();
        auto it = table.find(targetRace);
        if (it == table.end())
            return;

        if (overrideRacePack != 0)
        {
            for (uint32 sp : GetAllManagedRacialSpells())
                if (player->HasSpell(sp))
                    player->removeSpell(sp, false, false, false);
        }

        for (uint32 sp : it->second)
        {
            if (sSpellMgr->GetSpellInfo(sp) && !player->HasSpell(sp))
                player->learnSpell(sp, false);
        }
    }

    void SendDruidBarbershopList(Player* player)
    {
        if (!player || player->getClass() != CLASS_DRUID)
            return;

        uint8 curForm = uint8(player->GetShapeshiftForm());
        if (curForm == 0)
            curForm = uint8(FORM_CAT);

        uint32 currentSelected = 0;
        std::vector<FormScrollDef> options;
        {
            std::lock_guard<std::mutex> lock(g_lfMutex);
            auto pIt = g_playerForms.find(player->GetGUIDLow());
            if (pIt != g_playerForms.end())
            {
                auto fIt = pIt->second.find(curForm);
                if (fIt != pIt->second.end())
                    currentSelected = fIt->second;
            }
            for (auto const& kv : g_formScrolls)
                if (kv.second.formId == curForm)
                    options.push_back(kv.second);
        }
        std::sort(options.begin(), options.end(), [](FormScrollDef const& a, FormScrollDef const& b) { return a.itemId < b.itemId; });

        ChrRacesEntry const* rEntry = sChrRacesStore.LookupEntry(player->getRace());
        uint32 baseDisp = rEntry ? (player->getGender() == GENDER_MALE ? rEntry->MaleDisplayID : rEntry->FemaleDisplayID) : player->GetNativeDisplayId();

        std::ostringstream out;
        out << "UISMSG_DRUIDBSH_GET:";
        out << "1|" << baseDisp << "|0||0|Default|0|" << (currentSelected == 0 ? 1 : 0);
        for (auto const& opt : options)
        {
            std::string cleanName = opt.comment.empty() ? "Legion Form" : opt.comment;
            std::replace(cleanName.begin(), cleanName.end(), ':', ' ');
            std::replace(cleanName.begin(), cleanName.end(), '|', '/');
            out << ":1|" << opt.displayId << "|1||0|" << cleanName << "|0|" << (currentSelected == opt.displayId ? 1 : 0);
        }
        player->WhisperAddon(out.str(), "UISMSG_TO_CLIENT", player);
    }
}

class legionforge_world_loader : public WorldScript
{
public:
    legionforge_world_loader() : WorldScript("legionforge_world_loader") { }

    void OnConfigLoad(bool /*reload*/) override
    {
        LoadLegionForgeTables();
    }
};

// NPC 900104 — Shadowlands Valor / Essence Item Upgrade Master (Dalaran Krasus' Landing)
class npc_legionforge_upgrade_master : public CreatureScript
{
public:
    npc_legionforge_upgrade_master() : CreatureScript("npc_legionforge_upgrade_master") { }

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        player->PlayerTalkClass->ClearMenus();
        uint32 valor = player->GetCurrency(CURRENCY_VALOR);
        uint32 essence = player->GetItemCount(ITEM_ESSENCE_LF);

        std::ostringstream hdr;
        hdr << "|cff00ccff[Баланс]|r Доблесть: " << valor << " | Сущность LF: " << essence;
        player->ADD_GOSSIP_ITEM(0, hdr.str(), GOSSIP_SENDER_MAIN, 900);

        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
        {
            Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
            uint32 cap = 0;
            if (!IsUpgradeableItem(item, cap))
                continue;

            uint32 ilvl = item->GetItemLevel(player->getLevel());
            bool isLeg = item->GetTemplate()->GetQuality() == ITEM_QUALITY_LEGENDARY;
            uint32 vCost = 0, eCost = 0;
            CalcUpgradeCost(ilvl, isLeg, vCost, eCost);

            std::ostringstream line;
            line << "[" << GetEquipSlotRuName(slot) << "] ";
            if (ilvl >= cap)
                line << "|cff00ff00" << ilvl << " ilvl (МАКС)|r";
            else
                line << "|cffffd000" << ilvl << " -> " << std::min(ilvl + 5, cap) << " ilvl|r (" << vCost << " Доблести / " << eCost << " Сущн.)";

            player->ADD_GOSSIP_ITEM(4, line.str(), 100 + slot, 1);
        }

        player->PlayerTalkClass->SendGossipMenu(1, creature->GetGUID());
        return true;
    }

    bool OnGossipSelect(Player* player, Creature* creature, uint32 sender, uint32 action) override
    {
        player->PlayerTalkClass->ClearMenus();
        if (sender >= 100 && sender < 100 + EQUIPMENT_SLOT_END)
        {
            uint8 slot = uint8(sender - 100);
            if (action == 1)
            {
                Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
                uint32 cap = 0;
                if (!IsUpgradeableItem(item, cap))
                    return OnGossipHello(player, creature);

                uint32 ilvl = item->GetItemLevel(player->getLevel());
                bool isLeg = item->GetTemplate()->GetQuality() == ITEM_QUALITY_LEGENDARY;
                uint32 vCost = 0, eCost = 0;
                CalcUpgradeCost(ilvl, isLeg, vCost, eCost);

                std::ostringstream b1, b2;
                b1 << "Улучшить (+5 ilvl) за " << vCost << " Доблести (Valor)";
                b2 << "Улучшить (+5 ilvl) за " << eCost << " Сущности LegionForge";
                player->ADD_GOSSIP_ITEM(4, b1.str(), sender, 2);
                player->ADD_GOSSIP_ITEM(4, b2.str(), sender, 3);
                player->ADD_GOSSIP_ITEM(7, "<< Назад ко всем слотам", GOSSIP_SENDER_MAIN, 900);
                player->PlayerTalkClass->SendGossipMenu(1, creature->GetGUID());
                return true;
            }
            if (action == 2 || action == 3)
            {
                std::string msg;
                PerformShadowlandsUpgrade(player, slot, action == 3, msg);
                ChatHandler(player->GetSession()).PSendSysMessage("%s", msg.c_str());
                return OnGossipHello(player, creature);
            }
        }
        return OnGossipHello(player, creature);
    }
};

// NPC 900105 — Cross-Expansion Transmogrifier (Shadowlands / Dragonflight / TWW) & Druid Form Stylist
class npc_legionforge_transmog_master : public CreatureScript
{
public:
    npc_legionforge_transmog_master() : CreatureScript("npc_legionforge_transmog_master") { }

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        player->PlayerTalkClass->ClearMenus();
        player->ADD_GOSSIP_ITEM(9, "|cffa335eeТрансмогрификация брони/оружия по любому ItemID (5 652 модели SL/DF/TWW)|r", GOSSIP_SENDER_MAIN, 10);
        player->ADD_GOSSIP_ITEM(9, "|cff00ccffГотовые сеты и оружие Shadowlands / Dragonflight / The War Within|r", GOSSIP_SENDER_MAIN, 20);
        player->ADD_GOSSIP_ITEM(9, "|cff40ff40Облики Друида: Dragonflight 10.2 Сплюшки, Арденвельд, Кул-Тирас, Зандалар|r", GOSSIP_SENDER_MAIN, 30);
        player->ADD_GOSSIP_ITEM(9, "|cffff8000Смена кастомной расы / Облик Драктира / Карточки расовых способностей|r", GOSSIP_SENDER_MAIN, 40);
        player->ADD_GOSSIP_ITEM(7, "Сбросить всю кастомную трансмогрификацию", GOSSIP_SENDER_MAIN, 50);
        player->PlayerTalkClass->SendGossipMenu(1, creature->GetGUID());
        return true;
    }

    bool OnGossipSelect(Player* player, Creature* creature, uint32 sender, uint32 action) override
    {
        player->PlayerTalkClass->ClearMenus();

        // Direct Druid form application (sender == 300 + formId, action == displayId)
        if (sender >= 300 && sender < 400)
        {
            uint8 formId = uint8(sender - 300);
            {
                std::lock_guard<std::mutex> lock(g_lfMutex);
                g_playerForms[player->GetGUIDLow()][formId] = action;
            }
            CharacterDatabase.PExecute("REPLACE INTO character_form_appearance (guid, form_id, display_id, source_item) VALUES (%llu, %u, %u, 0)",
                uint64(player->GetGUIDLow()), uint32(formId), action);
            if (uint8(player->GetShapeshiftForm()) == formId)
                player->SetDisplayId(action);
            ChatHandler(player->GetSession()).PSendSysMessage("|cff40ff40[LegionForge]|r Облик формы друида сохранён (DisplayID %u)!", action);
            player->CLOSE_GOSSIP_MENU();
            return true;
        }

        // Direct curated Shadowlands / Dragonflight / TWW transmog item apply (sender == 500 + slot, action == itemId)
        if (sender >= 500 && sender < 500 + EQUIPMENT_SLOT_END)
        {
            std::string msg;
            ApplyCustomTransmogToSlot(player, uint8(sender - 500), action, msg);
            ChatHandler(player->GetSession()).PSendSysMessage("%s", msg.c_str());
            return OnGossipHello(player, creature);
        }

        if (action == 10)
        {
            for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
            {
                if (slot == EQUIPMENT_SLOT_NECK || slot == EQUIPMENT_SLOT_FINGER1 || slot == EQUIPMENT_SLOT_FINGER2 ||
                    slot == EQUIPMENT_SLOT_TRINKET1 || slot == EQUIPMENT_SLOT_TRINKET2)
                    continue;
                if (player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                {
                    player->ADD_GOSSIP_ITEM_EXTENDED(9,
                        std::string("Ввести ItemID облика -> ") + GetEquipSlotRuName(slot),
                        200 + slot, 1,
                        "Введите любой ItemID брони/оружия (например 260184 Лук Сильваны, 260369 Меч Изумрудного Гладиатора DF, 285672..285680 Доспехи Верховного Лича / Святого Воителя, или 0 для сброса):",
                        0, true);
                }
            }
            player->ADD_GOSSIP_ITEM(7, "<< Назад", GOSSIP_SENDER_MAIN, 1);
            player->PlayerTalkClass->SendGossipMenu(1, creature->GetGUID());
            return true;
        }

        if (action == 20)
        {
            player->ADD_GOSSIP_ITEM(9, "[Оружие SL] Раэ'шаларе, Шёпот Смерти (Сильвана)", 500 + EQUIPMENT_SLOT_MAINHAND, 260184);
            player->ADD_GOSSIP_ITEM(9, "[Оружие SL] Крылатая глефа грешного гладиатора (Вентиры)", 500 + EQUIPMENT_SLOT_MAINHAND, 260170);
            player->ADD_GOSSIP_ITEM(9, "[Оружие DF] Двуручный меч изумрудного гладиатора (Амирдрассил)", 500 + EQUIPMENT_SLOT_MAINHAND, 260318);
            player->ADD_GOSSIP_ITEM(9, "[Оружие DF] Меч кровавого монарха", 500 + EQUIPMENT_SLOT_MAINHAND, 260188);
            player->ADD_GOSSIP_ITEM(9, "[Шлем SL/TWW] Корона верховного лича (красная)", 500 + EQUIPMENT_SLOT_HEAD, 285678);
            player->ADD_GOSSIP_ITEM(9, "[Плечи SL/TWW] Наплечные щитки верховного лича (красные)", 500 + EQUIPMENT_SLOT_SHOULDERS, 285679);
            player->ADD_GOSSIP_ITEM(9, "[Грудь SL/TWW] Нагрудный доспех верховного лича (красный)", 500 + EQUIPMENT_SLOT_CHEST, 285680);
            player->ADD_GOSSIP_ITEM(9, "[Грудь SL] Одежды проводника душ", 500 + EQUIPMENT_SLOT_CHEST, 260325);
            player->ADD_GOSSIP_ITEM(9, "[Руки SL] Перчатки проводника душ", 500 + EQUIPMENT_SLOT_HANDS, 260323);
            player->ADD_GOSSIP_ITEM(9, "[Пояс TWW] Пояс скитальца Бездны", 500 + EQUIPMENT_SLOT_WAIST, 260332);
            player->ADD_GOSSIP_ITEM(7, "<< Назад", GOSSIP_SENDER_MAIN, 1);
            player->PlayerTalkClass->SendGossipMenu(1, creature->GetGUID());
            return true;
        }

        if (action == 30)
        {
            player->ADD_GOSSIP_ITEM(9, "[Dragonflight 10.2] Пылающая сплюшка Ану'релоса (Лётная эпик)", 300 + FORM_FLIGHT_EPIC, 111600);
            player->ADD_GOSSIP_ITEM(9, "[Dragonflight 10.2] Дремлющая сплюшка Изумрудного Сна (Лётная эпик)", 300 + FORM_FLIGHT_EPIC, 111601);
            player->ADD_GOSSIP_ITEM(9, "[Dragonflight 10.2] Изумрудная сплюшка «Перо друзей» (Лётная эпик)", 300 + FORM_FLIGHT_EPIC, 111602);
            player->ADD_GOSSIP_ITEM(9, "[Dragonflight 10.2] Лунная серебристая сплюшка (Лётная эпик)", 300 + FORM_FLIGHT_EPIC, 111603);
            player->ADD_GOSSIP_ITEM(9, "[Dragonflight] Аш'адар, Вестник Рассвета — золотая кошка", 300 + FORM_CAT, 104779);
            player->ADD_GOSSIP_ITEM(9, "[Dragonflight] Аш'адар, Лунный Охотник — ночная кошка", 300 + FORM_CAT, 104786);
            player->ADD_GOSSIP_ITEM(9, "[Shadowlands Арденвельд] Сверкающий мотылёк (Лётная эпик)", 300 + FORM_FLIGHT_EPIC, 98462);
            player->ADD_GOSSIP_ITEM(9, "[Shadowlands Арденвельд] Полуночный рунический олень (Походная)", 300 + FORM_TRAVEL, 98453);
            player->ADD_GOSSIP_ITEM(9, "[Shadowlands Арденвельд] Призрачный вульпин (Походная)", 300 + FORM_TRAVEL, 95572);
            player->ADD_GOSSIP_ITEM(9, "[BfA Кул-Тирас] Плетёная друст-кошка", 300 + FORM_CAT, 90512);
            player->ADD_GOSSIP_ITEM(9, "[BfA Кул-Тирас] Плетёный друст-медведь", 300 + FORM_BEAR, 90515);
            player->ADD_GOSSIP_ITEM(9, "[BfA Кул-Тирас] Плетёный друст-олень (Походная)", 300 + FORM_TRAVEL, 90691);
            player->ADD_GOSSIP_ITEM(9, "[BfA Зандалар] Раптор Гонка — дино-кошка", 300 + FORM_CAT, 91021);
            player->ADD_GOSSIP_ITEM(9, "[BfA Зандалар] Анкилодон — дино-медведь", 300 + FORM_BEAR, 91087);
            player->ADD_GOSSIP_ITEM(9, "[Legion Башня Магов] Оборотень-медведь (Werebear)", 300 + FORM_BEAR, 74282);
            player->ADD_GOSSIP_ITEM(9, "[Legion Башня Магов] Звёздная призрачная кошка", 300 + FORM_CAT, 74312);
            player->ADD_GOSSIP_ITEM(7, "<< Назад", GOSSIP_SENDER_MAIN, 1);
            player->PlayerTalkClass->SendGossipMenu(1, creature->GetGUID());
            return true;
        }

        if (action == 40)
        {
            player->WhisperAddon("UISMSG_FAKE_RACE_YES:", "UISMSG_TO_CLIENT", player);
            ChatHandler(player->GetSession()).PSendSysMessage("|cff40ff40[LegionForge]|r Открыто графическое окно расовых способностей! Для смены самой расы введите |cffffd000.race list|r и |cffffd000.race set <ID>|r.");
            player->CLOSE_GOSSIP_MENU();
            return true;
        }

        if (action == 50)
        {
            std::string dummy;
            for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
                ApplyCustomTransmogToSlot(player, slot, 0, dummy);
            ChatHandler(player->GetSession()).PSendSysMessage("|cff40ff40[LegionForge]|r Вся трансмогрификация сброшена.");
            player->CLOSE_GOSSIP_MENU();
            return true;
        }

        return OnGossipHello(player, creature);
    }

    bool OnGossipSelectCode(Player* player, Creature* creature, uint32 sender, uint32 /*action*/, char const* code) override
    {
        player->PlayerTalkClass->ClearMenus();
        if (sender >= 200 && sender < 200 + EQUIPMENT_SLOT_END && code)
        {
            uint8 slot = uint8(sender - 200);
            uint32 itemId = uint32(std::strtoul(code, nullptr, 10));
            std::string msg;
            ApplyCustomTransmogToSlot(player, slot, itemId, msg);
            ChatHandler(player->GetSession()).PSendSysMessage("%s", msg.c_str());
        }
        return OnGossipHello(player, creature);
    }
};

class legionforge_form_scroll_item : public ItemScript
{
public:
    legionforge_form_scroll_item() : ItemScript("legionforge_form_scroll_item") { }

    bool OnUse(Player* player, Item* item, SpellCastTargets const& /*targets*/) override
    {
        if (!player || !item)
            return true;

        FormScrollDef def;
        {
            std::lock_guard<std::mutex> lock(g_lfMutex);
            auto it = g_formScrolls.find(item->GetEntry());
            if (it == g_formScrolls.end())
                return false;
            def = it->second;
        }

        if (def.requiredClass != 0 && player->getClass() != def.requiredClass)
        {
            ChatHandler(player->GetSession()).PSendSysMessage("|cffff4040[LegionForge]|r Этот свиток предназначен для друидов.");
            return true;
        }

        {
            std::lock_guard<std::mutex> lock(g_lfMutex);
            g_playerForms[player->GetGUIDLow()][def.formId] = def.displayId;
        }

        CharacterDatabase.PExecute(
            "REPLACE INTO `character_form_appearance` (`guid`, `form_id`, `display_id`, `source_item`) VALUES (%llu, %u, %u, %u)",
            uint64(player->GetGUIDLow()), uint32(def.formId), def.displayId, def.itemId);

        if (uint8(player->GetShapeshiftForm()) == def.formId)
            player->SetDisplayId(def.displayId);

        player->DestroyItemCount(item->GetEntry(), 1, true);
        ChatHandler(player->GetSession()).PSendSysMessage(
            "|cff40ff40[LegionForge]|r Облик формы друида сохранён (DisplayID: %u). Сброс: |cffffd000.form reset|r", def.displayId);
        return true;
    }
};

class legionforge_demon_scroll_item : public ItemScript
{
public:
    legionforge_demon_scroll_item() : ItemScript("legionforge_demon_scroll_item") { }

    bool OnUse(Player* player, Item* item, SpellCastTargets const& /*targets*/) override
    {
        if (!player || !item)
            return true;

        DemonScrollDef def;
        {
            std::lock_guard<std::mutex> lock(g_lfMutex);
            auto it = g_demonScrolls.find(item->GetEntry());
            if (it == g_demonScrolls.end())
                return false;
            def = it->second;
        }

        if (player->getClass() != CLASS_WARLOCK)
        {
            ChatHandler(player->GetSession()).PSendSysMessage("|cffff4040[LegionForge]|r Свитки обликов демонов доступны только чернокнижникам.");
            return true;
        }

        {
            std::lock_guard<std::mutex> lock(g_lfMutex);
            g_playerDemons[player->GetGUIDLow()][def.petEntry] = { def.displayId, def.scale, def.itemId };
        }

        CharacterDatabase.PExecute(
            "REPLACE INTO `character_demon_appearance` (`guid`, `pet_entry`, `display_id`, `scale`, `source_item`) VALUES (%llu, %u, %u, %f, %u)",
            uint64(player->GetGUIDLow()), def.petEntry, def.displayId, def.scale, def.itemId);

        if (Pet* pet = player->GetPet())
        {
            if (pet->GetEntry() == def.petEntry)
            {
                pet->SetDisplayId(def.displayId);
                pet->SetNativeDisplayId(def.displayId);
                if (def.scale > 0.05f)
                    pet->SetObjectScale(def.scale);
            }
        }

        player->DestroyItemCount(item->GetEntry(), 1, true);
        ChatHandler(player->GetSession()).PSendSysMessage(
            "|cff40ff40[LegionForge]|r Облик демона сохранён навсегда (DisplayID: %u). Сброс: |cffffd000.demon reset|r", def.displayId);
        return true;
    }
};

class legionforge_player_bridge : public PlayerScript
{
public:
    legionforge_player_bridge() : PlayerScript("legionforge_player_bridge") { }

    void OnCreatureKill(Player* killer, Creature* killed) override
    {
        if (!killer || !killed)
            return;
        if (killed->GetEntry() >= 900000 && killed->GetEntry() <= 900099)
        {
            killer->ModifyCurrency(CURRENCY_VALOR, 250);
            ChatHandler(killer->GetSession()).PSendSysMessage("|cff40ff40[LegionForge]|r Вы получили |cffffd000250 Доблести (Valor)|r за победу над мини-боссом!");
        }
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        if (!player)
            return;

        uint64 guidLow = player->GetGUIDLow();
        uint8 overridePack = 0;

        if (QueryResult r = CharacterDatabase.PQuery("SELECT form_id, display_id FROM character_form_appearance WHERE guid = %llu", guidLow))
        {
            std::lock_guard<std::mutex> lock(g_lfMutex);
            auto& m = g_playerForms[guidLow];
            m.clear();
            do
            {
                Field* f = r->Fetch();
                m[f[0].GetUInt8()] = f[1].GetUInt32();
            } while (r->NextRow());
        }

        if (QueryResult r = CharacterDatabase.PQuery("SELECT pet_entry, display_id, scale, source_item FROM character_demon_appearance WHERE guid = %llu", guidLow))
        {
            std::lock_guard<std::mutex> lock(g_lfMutex);
            auto& m = g_playerDemons[guidLow];
            m.clear();
            do
            {
                Field* f = r->Fetch();
                m[f[0].GetUInt32()] = { f[1].GetUInt32(), f[2].GetFloat(), f[3].GetUInt32() };
            } while (r->NextRow());
        }

        if (QueryResult r = CharacterDatabase.PQuery("SELECT race_id FROM character_custom_racials WHERE guid = %llu", guidLow))
        {
            overridePack = r->Fetch()[0].GetUInt8();
            std::lock_guard<std::mutex> lock(g_lfMutex);
            g_playerRacialPack[guidLow] = overridePack;
        }

        SyncPlayerLanguagesAndRacials(player, overridePack);
        player->InitDisplayIds();

        if (Pet* pet = player->GetPet())
            ApplyCustomDemonAppearanceImpl(player, pet);
    }

    void OnChat(Player* player, uint32 type, uint32 lang, std::string& msg) override
    {
        if (!player || type != CHAT_MSG_ADDON || lang != LANG_ADDON)
            return;

        if (msg.compare(0, 16, "UIMSG_TO_SERVER\t") != 0)
            return;

        std::string payload = msg.substr(16);
        std::size_t tabPos = payload.find('\t');
        std::string opcode = (tabPos == std::string::npos) ? payload : payload.substr(0, tabPos);
        std::string arg = (tabPos == std::string::npos) ? "" : payload.substr(tabPos + 1);

        if (opcode == "UIMSG_GET_REALM_ID")
        {
            player->WhisperAddon("UISMSG_UCUSTOM_REALM_ID:1:", "UISMSG_TO_CLIENT", player);
        }
        else if (opcode == "UIMSG_DRUIDBSH_GET")
        {
            SendDruidBarbershopList(player);
        }
        else if (opcode == "UIMSG_DRUIDBSH_SET")
        {
            int idx = std::atoi(arg.c_str());
            uint8 curForm = uint8(player->GetShapeshiftForm());
            if (curForm == 0)
                curForm = uint8(FORM_CAT);

            std::vector<FormScrollDef> options;
            {
                std::lock_guard<std::mutex> lock(g_lfMutex);
                for (auto const& kv : g_formScrolls)
                    if (kv.second.formId == curForm)
                        options.push_back(kv.second);
            }
            std::sort(options.begin(), options.end(), [](FormScrollDef const& a, FormScrollDef const& b) { return a.itemId < b.itemId; });

            uint32 chosenDisplay = (idx > 0 && static_cast<std::size_t>(idx) <= options.size()) ? options[idx - 1].displayId : 0;
            {
                std::lock_guard<std::mutex> lock(g_lfMutex);
                g_playerForms[player->GetGUIDLow()][curForm] = chosenDisplay;
            }
            if (chosenDisplay == 0)
                CharacterDatabase.PExecute("DELETE FROM character_form_appearance WHERE guid = %llu AND form_id = %u", uint64(player->GetGUIDLow()), uint32(curForm));
            else
                CharacterDatabase.PExecute("REPLACE INTO character_form_appearance (guid, form_id, display_id, source_item) VALUES (%llu, %u, %u, 0)", uint64(player->GetGUIDLow()), uint32(curForm), chosenDisplay);

            if (uint8(player->GetShapeshiftForm()) == curForm && chosenDisplay != 0)
                player->SetDisplayId(chosenDisplay);

            SendDruidBarbershopList(player);
        }
        else if (opcode == "UIMSG_FAKE_RACE_SET")
        {
            int raceId = std::atoi(arg.c_str());
            uint8 newPack = (raceId > 0 && raceId < MAX_RACES) ? uint8(raceId) : 0;
            {
                std::lock_guard<std::mutex> lock(g_lfMutex);
                g_playerRacialPack[player->GetGUIDLow()] = newPack;
            }
            CharacterDatabase.PExecute("REPLACE INTO character_custom_racials (guid, race_id) VALUES (%llu, %u)", uint64(player->GetGUIDLow()), uint32(newPack));
            SyncPlayerLanguagesAndRacials(player, newPack);
            ChatHandler(player->GetSession()).PSendSysMessage("|cff40ff40[LegionForge]|r Расовые способности успешно обновлены!");
        }
    }
};

class legionforge_commands : public CommandScript
{
public:
    legionforge_commands() : CommandScript("legionforge_commands") { }

    std::vector<ChatCommand> GetCommands() const override
    {
        static std::vector<ChatCommand> raceSub =
        {
            { "list",      SEC_PLAYER, false, &HandleRaceList,      "" },
            { "set",       SEC_PLAYER, false, &HandleRaceSet,       "" },
            { "cards",     SEC_PLAYER, false, &HandleRaceCards,     "" },
            { "customize", SEC_PLAYER, false, &HandleRaceCustomize, "" },
        };
        static std::vector<ChatCommand> formSub =
        {
            { "look",      SEC_PLAYER, false, &HandleFormLook,      "" },
            { "set",       SEC_PLAYER, false, &HandleFormSet,       "" },
            { "reset",     SEC_PLAYER, false, &HandleFormReset,     "" },
        };
        static std::vector<ChatCommand> demonSub =
        {
            { "reset",     SEC_PLAYER, false, &HandleDemonReset,    "" },
        };
        static std::vector<ChatCommand> upgradeSub =
        {
            { "list",      SEC_PLAYER, false, &HandleUpgradeList,   "" },
            { "valor",     SEC_PLAYER, false, &HandleUpgradeValor,  "" },
            { "essence",   SEC_PLAYER, false, &HandleUpgradeEssence,"" },
        };
        static std::vector<ChatCommand> transmogSub =
        {
            { "apply",     SEC_PLAYER, false, &HandleTransmogApply, "" },
            { "illusion",  SEC_PLAYER, false, &HandleTransmogIllus, "" },
            { "reset",     SEC_PLAYER, false, &HandleTransmogReset, "" },
        };
        static std::vector<ChatCommand> root =
        {
            { "race",      SEC_PLAYER, false, nullptr,              "", raceSub },
            { "form",      SEC_PLAYER, false, nullptr,              "", formSub },
            { "demon",     SEC_PLAYER, false, nullptr,              "", demonSub },
            { "upgrade",   SEC_PLAYER, false, nullptr,              "", upgradeSub },
            { "transmog",  SEC_PLAYER, false, nullptr,              "", transmogSub },
            { "visage",    SEC_PLAYER, false, &HandleVisageToggle,  "" },
        };
        return root;
    }

    static bool HandleUpgradeList(ChatHandler* handler, char const* /*args*/)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player)
            return false;
        handler->PSendSysMessage("|cffffd000=== Улучшение брони и оружия LegionForge (механика Shadowlands) ===|r");
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
        {
            Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
            uint32 cap = 0;
            if (!IsUpgradeableItem(item, cap))
                continue;
            uint32 ilvl = item->GetItemLevel(player->getLevel());
            uint32 vCost = 0, eCost = 0;
            CalcUpgradeCost(ilvl, item->GetTemplate()->GetQuality() == ITEM_QUALITY_LEGENDARY, vCost, eCost);
            handler->PSendSysMessage("  Слот |cffffd000%u|r (%s): |cff00ff00%u / %u ilvl|r — %u Доблести или %u Сущности",
                uint32(slot), GetEquipSlotRuName(slot), ilvl, cap, vCost, eCost);
        }
        handler->PSendSysMessage("  Команды: |cffffd000.upgrade valor <слот>|r или |cffffd000.upgrade essence <слот>|r (либо НПС 900104 в Даларане)");
        return true;
    }

    static bool HandleUpgradeValor(ChatHandler* handler, char const* args)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player || !args || !*args)
        {
            handler->PSendSysMessage("Использование: |cffffd000.upgrade valor <номер_слота>|r (список слотов: .upgrade list)");
            return true;
        }
        uint8 slot = uint8(std::atoi(args));
        if (slot >= EQUIPMENT_SLOT_END)
            return true;
        std::string msg;
        PerformShadowlandsUpgrade(player, slot, false, msg);
        handler->PSendSysMessage("%s", msg.c_str());
        return true;
    }

    static bool HandleUpgradeEssence(ChatHandler* handler, char const* args)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player || !args || !*args)
        {
            handler->PSendSysMessage("Использование: |cffffd000.upgrade essence <номер_слота>|r (список слотов: .upgrade list)");
            return true;
        }
        uint8 slot = uint8(std::atoi(args));
        if (slot >= EQUIPMENT_SLOT_END)
            return true;
        std::string msg;
        PerformShadowlandsUpgrade(player, slot, true, msg);
        handler->PSendSysMessage("%s", msg.c_str());
        return true;
    }

    static bool HandleTransmogApply(ChatHandler* handler, char const* args)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player || !args || !*args)
        {
            handler->PSendSysMessage("Использование: |cffffd000.transmog apply <слот 0..18> <ItemID>|r");
            return true;
        }
        char* endPtr = nullptr;
        uint32 slot = std::strtoul(args, &endPtr, 10);
        uint32 itemId = endPtr ? std::strtoul(endPtr, nullptr, 10) : 0;
        if (slot >= EQUIPMENT_SLOT_END)
            return true;
        std::string msg;
        ApplyCustomTransmogToSlot(player, uint8(slot), itemId, msg);
        handler->PSendSysMessage("%s", msg.c_str());
        return true;
    }

    static bool HandleTransmogIllus(ChatHandler* handler, char const* args)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player || !args || !*args)
        {
            handler->PSendSysMessage("Использование: |cffffd000.transmog illusion <15=правая рука | 16=левая рука/щит> <EnchantID>|r");
            return true;
        }
        char* endPtr = nullptr;
        uint32 slot = std::strtoul(args, &endPtr, 10);
        uint32 enchId = endPtr ? std::strtoul(endPtr, nullptr, 10) : 0;
        if (slot != EQUIPMENT_SLOT_MAINHAND && slot != EQUIPMENT_SLOT_OFFHAND)
            return true;
        Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, uint8(slot));
        if (!item)
            return true;
        item->SetModifier(ITEM_MODIFIER_ENCHANT_ILLUSION_ALL_SPECS, enchId);
        player->SetVisibleItemSlot(uint8(slot), item);
        item->SetState(ITEM_CHANGED, player);
        player->SaveToDB();
        handler->PSendSysMessage("|cff40ff40[LegionForge]|r Иллюзия чар %u применена к слоту %u!", enchId, slot);
        return true;
    }

    static bool HandleTransmogReset(ChatHandler* handler, char const* /*args*/)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player)
            return false;
        std::string dummy;
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
            ApplyCustomTransmogToSlot(player, slot, 0, dummy);
        handler->PSendSysMessage("|cff40ff40[LegionForge]|r Вся трансмогрификация сброшена.");
        return true;
    }

    static bool HandleRaceList(ChatHandler* handler, char const* /*args*/)
    {
        handler->PSendSysMessage("|cffffd000=== Доступные кастомные и союзные расы LegionForge ===|r");
        handler->PSendSysMessage("  |cff60c0ffАльянс:|r 13 Драктир | 14 Сломленный | 16 Врайкул | 17 Дворф Чёрного Железа | 18 Култирасец | 29 Эльф Бездны | 30 Озарённый дреней | 33 Худой человек");
        handler->PSendSysMessage("  |cffff6060Орда:|r 12 Харанир (TWW) | 15 Вульпера | 19 Таунка | 20 Маг'хар | 21 Зандалар | 27 Ночнорождённый | 28 Таурен Крутогорья");
        handler->PSendSysMessage("  |cffb0ff80Команды:|r |cffffd000.race set <ID>|r, |cffffd000.race cards|r (окно расовых способностей), |cffffd000.visage|r (драконий облик Драктира)");
        return true;
    }

    static bool HandleRaceCards(ChatHandler* handler, char const* /*args*/)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player)
            return false;
        player->WhisperAddon("UISMSG_FAKE_RACE_YES:", "UISMSG_TO_CLIENT", player);
        handler->PSendSysMessage("|cff40ff40[LegionForge]|r Открыто графическое окно выбора расовых способностей.");
        return true;
    }

    static bool HandleRaceCustomize(ChatHandler* handler, char const* /*args*/)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player)
            return false;
        player->SetAtLoginFlag(AT_LOGIN_CUSTOMIZE);
        handler->PSendSysMessage("|cff40ff40[LegionForge]|r Бесплатная настройка внешности активирована — выйдите в меню выбора персонажа.");
        return true;
    }

    static bool HandleRaceSet(ChatHandler* handler, char const* args)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player || !args || !*args)
        {
            handler->PSendSysMessage("Использование: |cffffd000.race set <ID расы>|r (список: .race list)");
            return true;
        }
        int raceId = std::atoi(args);
        ChrRacesEntry const* rEntry = sChrRacesStore.LookupEntry(raceId);
        if (!rEntry || raceId <= 0 || raceId >= MAX_RACES || raceId == RACE_PANDAREN_NEUTRAL)
        {
            handler->PSendSysMessage("|cffff4040[LegionForge]|r Неверный ID расы (%d). Введите .race list.", raceId);
            return true;
        }

        player->SetRace(uint8(raceId));
        player->setFactionForRace(uint8(raceId));
        player->InitDisplayIds();
        SyncPlayerLanguagesAndRacials(player, 0);
        player->SetAtLoginFlag(AT_LOGIN_CUSTOMIZE);
        player->SaveToDB();
        handler->PSendSysMessage("|cff40ff40[LegionForge]|r Раса изменена на ID %d!", raceId);
        return true;
    }

    static bool HandleVisageToggle(ChatHandler* handler, char const* /*args*/)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player)
            return false;
        if (player->GetDisplayId() == DISPLAY_DRACTHYR_TRUE_FORM)
        {
            player->DeMorph();
            player->InitDisplayIds();
            handler->PSendSysMessage("|cff40ff40[LegionForge]|r Возвращён гуманоидный облик.");
        }
        else if (sCreatureDisplayInfoStore.LookupEntry(DISPLAY_DRACTHYR_TRUE_FORM))
        {
            player->SetDisplayId(DISPLAY_DRACTHYR_TRUE_FORM);
            handler->PSendSysMessage("|cff40ff40[LegionForge]|r Активирован истинный драконий облик Драктира (DisplayID 87870)!");
        }
        return true;
    }

    static bool HandleFormLook(ChatHandler* handler, char const* /*args*/)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player)
            return false;
        uint8 curForm = uint8(player->GetShapeshiftForm());
        handler->PSendSysMessage("|cff40ff40[LegionForge]|r Форма: %u | DisplayID: %u | Кастомная модель: %u",
            uint32(curForm), player->GetDisplayId(), GetCustomFormModelImpl(player, curForm));
        return true;
    }

    static bool HandleFormSet(ChatHandler* handler, char const* args)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player || !args || !*args)
        {
            handler->PSendSysMessage("Использование: |cffffd000.form set <DisplayID>|r");
            return true;
        }
        uint32 disp = uint32(std::strtoul(args, nullptr, 10));
        if (!sCreatureDisplayInfoStore.LookupEntry(disp))
        {
            handler->PSendSysMessage("|cffff4040[LegionForge]|r DisplayID %u отсутствует в клиенте.", disp);
            return true;
        }
        uint8 curForm = uint8(player->GetShapeshiftForm());
        if (curForm == 0)
            curForm = uint8(FORM_CAT);
        {
            std::lock_guard<std::mutex> lock(g_lfMutex);
            g_playerForms[player->GetGUIDLow()][curForm] = disp;
        }
        CharacterDatabase.PExecute("REPLACE INTO character_form_appearance (guid, form_id, display_id, source_item) VALUES (%llu, %u, %u, 0)",
            uint64(player->GetGUIDLow()), uint32(curForm), disp);
        if (uint8(player->GetShapeshiftForm()) == curForm)
            player->SetDisplayId(disp);
        handler->PSendSysMessage("|cff40ff40[LegionForge]|r Облик формы %u установлен на DisplayID %u.", uint32(curForm), disp);
        return true;
    }

    static bool HandleFormReset(ChatHandler* handler, char const* /*args*/)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player)
            return false;
        {
            std::lock_guard<std::mutex> lock(g_lfMutex);
            g_playerForms.erase(player->GetGUIDLow());
        }
        CharacterDatabase.PExecute("DELETE FROM character_form_appearance WHERE guid = %llu", uint64(player->GetGUIDLow()));
        player->InitDisplayIds();
        handler->PSendSysMessage("|cff40ff40[LegionForge]|r Кастомные облики форм сброшены.");
        return true;
    }

    static bool HandleDemonReset(ChatHandler* handler, char const* /*args*/)
    {
        Player* player = handler->GetSession()->GetPlayer();
        if (!player)
            return false;
        {
            std::lock_guard<std::mutex> lock(g_lfMutex);
            g_playerDemons.erase(player->GetGUIDLow());
        }
        CharacterDatabase.PExecute("DELETE FROM character_demon_appearance WHERE guid = %llu", uint64(player->GetGUIDLow()));
        handler->PSendSysMessage("|cff40ff40[LegionForge]|r Кастомные облики демонов сброшены. Перепризовите демона.");
        return true;
    }
};

void AddSC_legionforge_custom_features()
{
    g_LegionForgeFormModelHook = &GetCustomFormModelImpl;
    g_LegionForgeDemonAppearanceHook = &ApplyCustomDemonAppearanceImpl;

    new legionforge_world_loader();
    new npc_legionforge_upgrade_master();
    new npc_legionforge_transmog_master();
    new legionforge_form_scroll_item();
    new legionforge_demon_scroll_item();
    new legionforge_player_bridge();
    new legionforge_commands();
}
