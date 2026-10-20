/* LegionForge dependency regressions; GNU GPL version 2 or later. */
#include "Common.h"
#include "MySQLCompat.h"
#include "DatabaseEnvFwd.h"
#include "Log.h"
#include "OpenSSLCrypto.h"
#include "ARC4.h"
#include "SHA1.h"
#include "HmacHash.h"
#include "StartProcess.h"
#include <boost/version.hpp>
#include <boost/asio/post.hpp>
#include <boost/process.hpp>
#include <openssl/opensslv.h>
#include <array>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <type_traits>

static void Check(bool ok, char const* what)
{
    if (!ok)
        throw std::runtime_error(what);
    std::cout << "PASS " << what << '\n';
}

static std::string Hex(uint8 const* data, size_t length)
{
    char const* digits = "0123456789abcdef";
    std::string output;
    for (size_t i = 0; i < length; ++i)
    {
        output.push_back(digits[data[i] >> 4]);
        output.push_back(digits[data[i] & 15]);
    }
    return output;
}

int main(int argc, char** argv)
{
    // Child modes are also portable to Windows: no shell/interpreter required.
    if (argc == 2 && std::strcmp(argv[1], "--pipe-child") == 0)
    {
        std::string block(8192, 'x');
        for (int i = 0; i < 16; ++i)
        {
            std::cout << block << std::flush;
            std::cerr << block << std::flush;
        }
        return 7;
    }
    if (argc == 2 && std::strcmp(argv[1], "--sleep-child") == 0)
    {
        std::this_thread::sleep_for(std::chrono::seconds(20));
        return 0;
    }

    try
    {
        static_assert(BOOST_VERSION >= 108300, "Run with the pinned Boost 1.83 SDK");
        static_assert(std::is_same<MySQLBool*, decltype(MYSQL_BIND::is_null)>::value,
            "NULL flag must match the selected client ABI");
        static_assert(std::is_same<decltype(boost::process::search_path("test")),
            boost::filesystem::path>::value, "Bundled Boost.Process 0.5 is shadowing Boost");
        std::cout << "Boost " << BOOST_LIB_VERSION << "; " << OPENSSL_VERSION_TEXT
                  << "; MySQL client " << mysql_get_client_info() << '\n';

        MYSQL* mysql = mysql_init(nullptr);
        Check(mysql != nullptr, "MySQL SDK and client library initialize together (no server connection)");
        mysql_close(mysql);

        OpenSSLCrypto::threadsSetup();
        SHA1Hash sha1;
        sha1.UpdateData(std::string("abc"));
        sha1.Finalize();
        Check(Hex(sha1.GetDigest(), sha1.GetLength()) == "a9993e364706816aba3e25717850c26c9cd0d89d",
            "Core SHA1 known-answer vector with OpenSSL 3");
        uint8 key[] = {'k', 'e', 'y'};
        HmacSha256 hmac(sizeof(key), key);
        hmac.UpdateData(std::string("The quick brown fox jumps over the lazy dog"));
        hmac.Finalize();
        Check(Hex(hmac.GetDigest(), hmac.GetLength()) ==
            "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
            "Core HMAC-SHA256 known-answer vector");
        uint8 rc4key[] = {'K', 'e', 'y'};
        std::array<uint8, 9> packet{{'P','l','a','i','n','t','e','x','t'}};
        ARC4 rc4(rc4key, sizeof(rc4key));
        rc4.UpdateData(static_cast<int>(packet.size()), packet.data());
        Check(Hex(packet.data(), packet.size()) == "bbf316e8d940af0ad3",
            "Core packet RC4 known-answer vector without OpenSSL legacy provider");
        OpenSSLCrypto::threadsCleanup();

        boost::asio::io_context context;
        LogStrand strand(context.get_executor());
        int serialized = 0;
        for (int i = 0; i < 1000; ++i)
            boost::asio::post(strand, [&] { ++serialized; });
        std::thread first([&] { context.run(); });
        std::thread second([&] { context.run(); });
        first.join();
        second.join();
        Check(serialized == 1000, "LogStrand serializes work across two io_context threads");

        // Initialize the core singleton before the process reader threads start.
        sLog->SetLogLevel("root", "0");
        std::string const self = boost::filesystem::absolute(argv[0]).string();
        Check(Trinity::StartProcess(self, {"--pipe-child"}, "compat", "", true) == 7,
            "Real StartProcess drains stdout and stderr concurrently and returns exit code");

        auto live = Trinity::StartAsyncProcess(self, {"--sleep-child"}, "compat", "", true);
        std::this_thread::sleep_for(std::chrono::milliseconds(150));
        live->Terminate();
        auto& result = live->GetFutureResult();
        Check(result.wait_for(std::chrono::seconds(3)) == std::future_status::ready,
            "Real asynchronous process cancellation completes promptly");
        Check(result.get() == EXIT_FAILURE, "Cancelled process reports failure");

        auto early = Trinity::StartAsyncProcess(self, {"--sleep-child"}, "compat", "", true);
        early->Terminate();
        auto& earlyResult = early->GetFutureResult();
        Check(earlyResult.wait_for(std::chrono::seconds(3)) == std::future_status::ready,
            "Cancellation requested before child registration is preserved");
        Check(earlyResult.get() == EXIT_FAILURE, "Early cancellation reports failure");
        std::cout << "All dependency regressions passed.\n";
        return 0;
    }
    catch (std::exception const& error)
    {
        std::cerr << "FAIL " << error.what() << '\n';
        return 1;
    }
}
