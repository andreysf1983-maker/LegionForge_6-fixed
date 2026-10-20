/*
 * LegionForge MySQL client compatibility.
 * Distributed under the GNU General Public License, version 2 or later.
 */
#ifndef LEGIONFORGE_MYSQL_COMPAT_H
#define LEGIONFORGE_MYSQL_COMPAT_H

// mysql.h may require Winsock declarations on Windows. Include it before
// windows.h through the same order used by the rest of the database module.
#ifdef _WIN32
#include <winsock2.h>
#endif
#include <mysql.h>
#include <type_traits>

// MySQL 8 uses bool, whereas MySQL 5.7 and MariaDB use my_bool (often char).
// Derive the exact ABI type instead of redefining a vendor typedef or guessing
// from MYSQL_VERSION_ID (MariaDB's version IDs follow a different scheme).
using MySQLBool = std::remove_pointer<decltype(MYSQL_BIND::is_null)>::type;

#endif // LEGIONFORGE_MYSQL_COMPAT_H
