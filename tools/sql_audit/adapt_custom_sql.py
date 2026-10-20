#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LegionForge custom SQL adapter / auditor.

The files in sql/custom were authored against a TrinityCore *master*
(BfA / Shadowlands) database layout that came from an older WoW project.
This server runs LegionCore 7.3.5 build 26124, whose world/hotfixes layout is
different.  This script rewrites every INSERT/DELETE in sql/custom so that it
matches the schema the core actually reads.  All column lists below were
verified against the SELECT statements inside core/src:

  * creature_template          core/src/server/game/Globals/ObjectMgr.cpp (LoadCreatureTemplates)
  * creature_template_wdb      core/src/server/game/Globals/ObjectMgr.cpp (LoadWDBCreatureTemplates)
  * creature                   core/src/server/game/Globals/ObjectMgr.cpp (LoadCreatures)
  * creature_template_addon    core/src/server/game/Globals/ObjectMgr.cpp
  * *_loot_template            core/src/server/game/Loot/LootMgr.cpp (LootStore::LoadLootTable)
  * npc_vendor                 core/src/server/game/Globals/ObjectMgr.cpp (LoadVendors)
  * conditions                 core/src/server/game/Conditions/ConditionMgr.cpp
  * item / item_effect / ...   core/src/common/Database/Implementation/HotfixDatabase.cpp

Usage:  python3 tools/sql_audit/adapt_custom_sql.py [sql/custom]
"""
import os
import re
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "sql/custom"

LOOT_TABLES = {
    "creature_loot_template", "reference_loot_template", "item_loot_template",
    "spell_loot_template", "gameobject_loot_template", "disenchant_loot_template",
    "fishing_loot_template", "mail_loot_template", "milling_loot_template",
    "pickpocketing_loot_template", "prospecting_loot_template",
    "skinning_loot_template", "world_loot_template",
}

# columns that simply do not exist in the LegionCore 7.3.5 layout
DROP = {
    "creature_template": {
        "name", "femalename", "subname", "rank", "type", "requiredexpansion",
        "basevariance", "rangevariance", "healthmodifier", "manamodifier",
        "armormodifier", "damagemodifier", "experiencemodifier", "verifiedbuild",
        "modelid1", "modelid2", "modelid3", "modelid4", "family", "type_flags",
    },
    "creature": {"phasegroup", "verifiedbuild"},
    "creature_template_addon": {"aianimkit", "movementanimkit", "meleeanimkit"},
    "conditions": {"errortype"},
    "npc_vendor": {"verifiedbuild"},
}

RENAME = {
    "creature_template": {"healthscalingexpansion": "exp"},
    "item": {"soundoverridesubclassid": "SoundOverrideSubclass"},
    "item_effect": {"parentitemid": "ItemID"},
    "npc_vendor": {"bonuslistids": "BonusListID"},
}


def split_rows(text):
    """Split a VALUES payload into rows, each row a list of raw field strings."""
    rows, row, buf = [], [], []
    depth, i, n = 0, 0, len(text)
    quote = None
    while i < n:
        ch = text[i]
        if quote:
            buf.append(ch)
            if ch == "\\" and i + 1 < n:
                buf.append(text[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            buf.append(ch)
            i += 1
            continue
        if ch == "(":
            depth += 1
            if depth == 1:
                buf, row = [], []
                i += 1
                continue
            buf.append(ch)
            i += 1
            continue
        if ch == ")":
            depth -= 1
            if depth == 0:
                row.append("".join(buf).strip())
                rows.append(row)
                buf = []
                i += 1
                continue
            buf.append(ch)
            i += 1
            continue
        if ch == "," and depth == 1:
            row.append("".join(buf).strip())
            buf = []
            i += 1
            continue
        if depth >= 1:
            buf.append(ch)
        i += 1
    return rows


def unq(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == "'" and v[-1] == "'":
        return v[1:-1]
    return v


def num(v):
    try:
        return float(unq(v))
    except ValueError:
        return 0.0


def fmt_num(f):
    return str(int(f)) if f == int(f) else str(round(f, 4))


def convert_loot(cols, rows):
    """TC-master loot layout -> LegionCore loot layout."""
    idx = {c.lower(): i for i, c in enumerate(cols)}
    need = ("entry", "item", "reference", "chance", "questrequired", "lootmode",
            "groupid", "mincount", "maxcount")
    if not all(k in idx for k in need):
        return None
    out = []
    for r in rows:
        if len(r) != len(cols):
            return None
        entry = unq(r[idx["entry"]])
        item = int(num(r[idx["item"]]))
        ref = int(num(r[idx["reference"]]))
        chance = num(r[idx["chance"]])
        quest = int(num(r[idx["questrequired"]]))
        lootmode = int(num(r[idx["lootmode"]]))
        groupid = int(num(r[idx["groupid"]]))
        mincount = int(num(r[idx["mincount"]]))
        maxcount = int(num(r[idx["maxcount"]]))
        comment = unq(r[idx["comment"]]) if "comment" in idx else ""
        if ref > 0:
            mincount_or_ref, item = -ref, 0
        else:
            mincount_or_ref = mincount if mincount else 1
        chance_or_quest = -abs(chance) if quest else chance
        line = "(%s,%d,%s,%d,%d,%d,%d)" % (
            entry, item, fmt_num(chance_or_quest), lootmode or 1, groupid,
            mincount_or_ref, maxcount if maxcount else 1)
        if comment:
            line += " /* %s */" % comment.replace("*/", "")
        out.append(line)
    newcols = ("(`entry`,`item`,`ChanceOrQuestChance`,`lootmode`,`groupid`,"
               "`mincountOrRef`,`maxcount`)")
    return newcols, out


def convert_generic(table, cols, rows):
    drop = DROP.get(table, set())
    ren = RENAME.get(table, {})
    keep = [i for i, c in enumerate(cols) if c.lower() not in drop]
    newcols = [ren.get(cols[i].lower(), cols[i]) for i in keep]
    out = []
    for r in rows:
        if len(r) != len(cols):
            return None
        vals = []
        for i in keep:
            v = r[i]
            if table == "npc_vendor" and cols[i].lower() == "bonuslistids":
                v = "0" if unq(v) in ("", "0") else unq(v)
            vals.append(v)
        out.append("(" + ",".join(vals) + ")")
    return "(" + ",".join("`%s`" % c for c in newcols) + ")", out


INSERT_RE = re.compile(
    r"(INSERT(?:\s+IGNORE)?\s+INTO\s+`?(\w+)`?\s*)\(([^()]*?)\)\s*VALUES\s*(.*?);",
    re.IGNORECASE | re.DOTALL)


def process_sql(text):
    def repl(m):
        head, table, colblob, values = m.group(1), m.group(2).lower(), m.group(3), m.group(4)
        cols = [c.strip().strip("`") for c in colblob.split(",")]
        rows = split_rows(values)
        if not rows:
            return m.group(0)
        if table in LOOT_TABLES:
            res = convert_loot(cols, rows)
        elif table in DROP or table in RENAME:
            res = convert_generic(table, cols, rows)
        else:
            return m.group(0)
        if res is None:
            return m.group(0)
        newcols, newrows = res
        return head + newcols + " VALUES\n" + ",\n".join(newrows) + ";"

    text = INSERT_RE.sub(repl, text)
    text = re.sub(r"(`?item_effect`?[^;]{0,200}?)`ParentItemID`", r"\1`ItemID`",
                  text, flags=re.IGNORECASE | re.DOTALL)
    text = text.replace("`SoundOverrideSubclassID`", "`SoundOverrideSubclass`")
    return text


def main():
    changed = 0
    for fn in sorted(os.listdir(SRC)):
        if not fn.endswith(".sql"):
            continue
        p = os.path.join(SRC, fn)
        with open(p, encoding="utf-8") as fh:
            src = fh.read()
        dst = process_sql(src)
        if dst != src:
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(dst)
            changed += 1
            print("adapted:", fn)
    print("files changed:", changed)


if __name__ == "__main__":
    main()
