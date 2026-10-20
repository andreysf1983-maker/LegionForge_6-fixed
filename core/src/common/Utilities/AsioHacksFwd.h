/*
 * Copyright (C) 2026 LegionForge Project <https://legionforge.ru/>
 * LegionForge 7.3.5.26124 - modified 2026-10-20.
 * Upstream copyright notices below are retained as required by the GNU GPL v2.
 * Copyright (C) 2008-2017 TrinityCore <http://www.trinitycore.org/>
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

#ifndef AsioHacksFwd_h__
#define AsioHacksFwd_h__

// Boost.Asio 1.66+ changed the template signatures of basic_resolver and
// basic_deadline_timer (the *_service template parameters were removed).
// Hand-written forward declarations of those templates no longer match the
// real ones and cause redeclaration errors as soon as a translation unit also
// includes the genuine Asio headers. Include the real headers instead - they
// provide ip::address, ip::tcp, tcp::endpoint, tcp::resolver and deadline_timer.
#include <boost/asio/deadline_timer.hpp>
#include <boost/asio/ip/address.hpp>
#include <boost/asio/ip/tcp.hpp>

namespace Trinity
{
    class AsioStrand;
}

#endif // AsioHacksFwd_h__
