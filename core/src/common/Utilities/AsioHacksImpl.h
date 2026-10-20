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

#ifndef AsioHacksImpl_h__
#define AsioHacksImpl_h__

#include <boost/asio/io_context.hpp>
#include <boost/asio/strand.hpp>

namespace Trinity
{
    // boost::asio::strand is a template since Boost 1.66; bind it to the
    // io_context executor so the helper keeps its old, non-template name.
    class AsioStrand : public boost::asio::strand<boost::asio::io_context::executor_type>
    {
    public:
        explicit AsioStrand(boost::asio::io_context& ioContext)
            : boost::asio::strand<boost::asio::io_context::executor_type>(ioContext.get_executor()) { }
    };
}

#endif // AsioHacksImpl_h__
