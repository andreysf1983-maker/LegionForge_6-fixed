/*
 * Copyright (C) 2026 LegionForge Project <https://legionforge.ru/>
 * LegionForge 7.3.5.26124 - modified 2026-10-20.
 * Upstream copyright notices below are retained as required by the GNU GPL v2.
 * Copyright (C) 2008-2012 TrinityCore <http://www.trinitycore.org/>
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

#include "ARC4.h"
#include <utility>

ARC4::ARC4(uint32 len) : m_keyLen(len ? len : 1)
{
}

ARC4::ARC4(uint8* seed, uint32 len) : m_keyLen(len ? len : 1)
{
    Init(seed);
}

ARC4::~ARC4()
{
}

void ARC4::Init(uint8* seed)
{
    m_state = RC4_Context();
    rc4_init(&m_state, seed, int(m_keyLen));
}

void ARC4::UpdateData(int len, uint8* data)
{
    if (len > 0 && data)
        rc4_process(&m_state, data, len);
}

void ARC4::rc4_init(RC4_Context * ctx, const uint8 * seed, int seedlen)
{
    for (int i = 0; i < 256; ++i)
        ctx->S[i] = i;

    ctx->x = 0;
    ctx->y = 0;

    int j = 0;

    for (int i = 0; i < 256; ++i)
    {
        j = (j + ctx->S[i] + seed[i % seedlen]) % 256;
        std::swap(ctx->S[i], ctx->S[j]);
    }
}

void ARC4::rc4_process(RC4_Context * ctx, uint8 * data, int datalen)
{
    int i = 0;
    int j = 0;

    for (i = 0; i < datalen; ++i)
    {
        ctx->x = (ctx->x + 1) % 256;
        ctx->y = (ctx->y + ctx->S[ctx->x]) % 256;
        std::swap(ctx->S[ctx->x], ctx->S[ctx->y]);
        j = (ctx->S[ctx->x] + ctx->S[ctx->y]) % 256;
        data[i] ^= ctx->S[j];
    }
}
