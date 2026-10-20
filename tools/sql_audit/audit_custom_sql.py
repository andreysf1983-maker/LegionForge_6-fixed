#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LegionForge custom SQL auditor.

Cross-checks every column referenced by sql/custom/*.sql against the column
lists that LegionCore 7.3.5 (build 26124) really reads.  Every list below was
copied from the SELECT statements inside core/src, so a clean run means the
patch cannot fail with "Unknown column" / "Table doesn't exist" any more.

Usage:  python3 tools/sql_audit/audit_custom_sql.py [sql/custom]
Exit code 0 = clean, 1 = problems found.
"""
import os
import re
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "sql/custom"

SCHEMA = {
    # ---------------- world ----------------
    "playercreateinfo": {"race", "class", "map", "zone", "position_x", "position_y",
                         "position_z", "orientation"},
    "playercreateinfo_item": {"race", "class", "itemid", "amount", "bonusListIDs"},
    "playercreateinfo_action": {"race", "class", "button", "action", "type"},
    "playercreateinfo_spell": {"race", "class", "spell", "Note"},
    "player_levelstats": {"race", "class", "level", "str", "agi", "sta", "inte"},
    "race_unlock_requirement": {"raceID", "expansion", "achievementId"},
    "creature_template": {
        "entry", "gossip_menu_id", "minlevel", "maxlevel", "SandboxScalingID",
        "ScaleLevelMin", "ScaleLevelMax", "ScaleLevelDelta", "ScaleLevelDuration",
        "exp", "faction", "npcflag", "npcflag2", "speed_walk", "speed_run",
        "speed_fly", "scale", "mindmg", "maxdmg", "dmgschool", "attackpower",
        "dmg_multiplier", "baseattacktime", "rangeattacktime", "unit_class",
        "unit_flags", "unit_flags2", "unit_flags3", "dynamicflags", "trainer_type",
        "trainer_spell", "trainer_class", "trainer_race", "minrangedmg",
        "maxrangedmg", "rangedattackpower", "lootid", "pickpocketloot", "skinloot",
        "resistance1", "resistance2", "resistance3", "resistance4", "resistance5",
        "resistance6", "spell1", "spell2", "spell3", "spell4", "spell5", "spell6",
        "spell7", "spell8", "PetSpellDataId", "VehicleId", "mingold", "maxgold",
        "AIName", "MovementType", "InhabitType", "HoverHeight", "Mana_mod_extra",
        "Armor_mod", "RegenHealth", "mechanic_immune_mask", "flags_extra",
        "ControllerID", "WorldEffects", "PassiveSpells", "StateWorldEffectID",
        "SpellStateVisualID", "SpellStateAnimID", "SpellStateAnimKitID", "IgnoreLos",
        "AffixState", "MaxVisible", "ScriptName"},
    "creature_template_wdb": {
        "Entry", "Name1", "Name2", "Name3", "Name4", "NameAlt1", "NameAlt2",
        "NameAlt3", "NameAlt4", "Title", "TitleAlt", "CursorName", "Type",
        "TypeFlags", "TypeFlags2", "RequiredExpansion", "Family", "Classification",
        "MovementInfoID", "HpMulti", "PowerMulti", "Leader", "KillCredit1",
        "KillCredit2", "VignetteID", "DisplayId1", "DisplayId2", "DisplayId3",
        "DisplayId4", "FlagQuest", "QuestItem1", "QuestItem2", "QuestItem3",
        "QuestItem4", "QuestItem5", "QuestItem6", "QuestItem7", "QuestItem8",
        "QuestItem9", "QuestItem10", "VerifiedBuild"},
    "creature_template_addon": {"entry", "path_id", "mount", "bytes1", "bytes2",
                                "emote", "auras"},
    "creature": {
        "guid", "id", "map", "zoneId", "areaId", "modelid", "equipment_id",
        "position_x", "position_y", "position_z", "orientation", "spawntimesecs",
        "spawndist", "currentwaypoint", "curhealth", "curmana", "MovementType",
        "spawnMask", "phaseMask", "npcflag", "npcflag2", "unit_flags", "unit_flags3",
        "dynamicflags", "ScriptName", "isActive", "PhaseId", "AiID", "MovementID",
        "MeleeID", "skipClone", "personal_size", "isTeemingSpawn"},
    "npc_vendor": {"entry", "slot", "item", "maxcount", "incrtime", "ExtendedCost",
                   "type", "money", "RandomPropertiesSeed", "RandomPropertiesID",
                   "BonusListID", "ItemModifiers", "IgnoreFiltering", "Context",
                   "PlayerConditionID"},
    "conditions": {"SourceTypeOrReferenceId", "SourceGroup", "SourceEntry",
                   "SourceId", "ElseGroup", "ConditionTypeOrReference",
                   "ConditionTarget", "ConditionValue1", "ConditionValue2",
                   "ConditionValue3", "NegativeCondition", "ErrorTextId",
                   "ScriptName", "Comment"},
    "item_script_names": {"Id", "ScriptName"},
    "game_event_arena_seasons": {"eventEntry", "season"},
    # ---------------- hotfixes (db2 mirrors) ----------------
    "item": {"ID", "IconFileDataID", "ClassID", "SubclassID", "SoundOverrideSubclass",
             "Material", "InventoryType", "SheatheType", "ItemGroupSoundsID",
             "VerifiedBuild"},
    "item_effect": {"ID", "SpellID", "CoolDownMSec", "CategoryCoolDownMSec",
                    "Charges", "SpellCategoryID", "ChrSpecializationID",
                    "LegacySlotIndex", "TriggerType", "ItemID", "VerifiedBuild"},
    "item_extended_cost": {"ID", "ItemID1", "ItemID2", "ItemID3", "ItemID4",
                           "ItemID5", "CurrencyCount1", "CurrencyCount2",
                           "CurrencyCount3", "CurrencyCount4", "CurrencyCount5",
                           "ItemCount1", "ItemCount2", "ItemCount3", "ItemCount4",
                           "ItemCount5", "RequiredArenaRating", "CurrencyID1",
                           "CurrencyID2", "CurrencyID3", "CurrencyID4", "CurrencyID5",
                           "ArenaBracket", "MinFactionID", "MinReputation", "Flags",
                           "RequiredAchievement", "VerifiedBuild"},
    "item_bonus_list_level_delta": {"ID", "ItemLevelDelta", "VerifiedBuild"},
    "spell": {"ID", "Name", "NameSubtext", "Description", "AuraDescription",
              "VerifiedBuild"},
}

LOOT_COLUMNS = {"entry", "item", "ChanceOrQuestChance", "lootmode", "groupid",
                "mincountOrRef", "maxcount", "shared", "patch", "type"}
for _t in ("creature_loot_template", "reference_loot_template", "item_loot_template",
           "spell_loot_template", "gameobject_loot_template", "skinning_loot_template",
           "pickpocketing_loot_template", "disenchant_loot_template",
           "fishing_loot_template", "mail_loot_template", "milling_loot_template",
           "prospecting_loot_template", "world_loot_template"):
    SCHEMA[_t] = set(LOOT_COLUMNS)

LOWER = {t: {c.lower() for c in cols} for t, cols in SCHEMA.items()}

# tables created by the patches themselves - always OK
SELF_MADE = re.compile(r"^(tmp_|lf_|legionforge_)")

INSERT_RE = re.compile(
    r"INSERT(?:\s+IGNORE)?\s+INTO\s+`?(\w+)`?\s*\(([^()]*?)\)", re.IGNORECASE | re.DOTALL)


def main():
    problems = []
    for fn in sorted(os.listdir(SRC)):
        if not fn.endswith(".sql"):
            continue
        path = os.path.join(SRC, fn)
        text = open(path, encoding="utf-8").read()
        for m in INSERT_RE.finditer(text):
            table = m.group(1)
            if SELF_MADE.match(table):
                continue
            key = table.lower()
            if key not in LOWER:
                continue  # table not part of the audited core-read set
            cols = [c.strip().strip("`") for c in m.group(2).split(",") if c.strip()]
            for c in cols:
                if c.lower() not in LOWER[key]:
                    line = text[:m.start()].count("\n") + 1
                    problems.append("%s:%d  %s.%s is not a LegionCore column"
                                    % (fn, line, table, c))
    if problems:
        print("FAILED - %d problem(s):" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("OK - every audited column exists in the LegionCore 7.3.5 schema.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
