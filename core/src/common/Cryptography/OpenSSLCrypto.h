/*
 * Copyright (C) 2026 LegionForge Project <https://legionforge.ru/>
 * LegionForge 7.3.5.26124 - modified 2026-10-20.
 * Upstream copyright notices below are retained as required by the GNU GPL v2.
 * Copyright (C) 2008-2014 TrinityCore <http://www.trinitycore.org/>
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

#ifndef LEGIONFORGE_OPENSSL_CRYPTO_H
#define LEGIONFORGE_OPENSSL_CRYPTO_H

#include "Define.h"

// OpenSSL < 1.1 requires application-provided locking callbacks. OpenSSL
// 1.1+ manages those locks internally; the API remains for server callers.
namespace OpenSSLCrypto
{
    // Call before starting threads that use OpenSSL.
    void threadsSetup();
    // Call after joining those threads; does not shut down OpenSSL globally.
    void threadsCleanup();
}

#endif // LEGIONFORGE_OPENSSL_CRYPTO_H
