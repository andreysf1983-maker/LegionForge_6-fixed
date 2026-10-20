/*
 * Copyright (C) 2026 LegionForge Project <https://legionforge.ru/>
 * LegionForge 7.3.5.26124 - modified 2026-10-20.
 * Upstream copyright notices below are retained as required by the GNU GPL v2.
 * Copyright (C) 2008-2018 TrinityCore <https://www.trinitycore.org/>
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

#include "StartProcess.h"
#include "Errors.h"
#include "Log.h"
#include "Optional.h"

#include <boost/algorithm/string/join.hpp>
#include <boost/filesystem/operations.hpp>
#include <boost/filesystem/path.hpp>
#include <boost/iostreams/copy.hpp>
#include <boost/iostreams/stream.hpp>
#include <boost/process.hpp>
#include <atomic>
#include <mutex>

// Boost.Process was rewritten when it became an official Boost library in 1.64:
// the old "process v0.5" API (namespace boost::process::initializers with
// execute/run_exe/set_args/bind_std*/create_pipe/wait_for_exit) no longer
// exists in Boost 1.83. The code below uses the current boost::process::child
// interface with ipstream pipes.
using namespace boost::process;
using namespace boost::iostreams;

namespace Trinity
{

template<typename T>
class TCLogSink
{
    T callback_;

public:
    typedef char      char_type;
    typedef sink_tag  category;

    // Requires a callback type which has a void(std::string) signature
    TCLogSink(T callback)
        : callback_(std::move(callback)) { }

    std::streamsize write(const char* str, std::streamsize size)
    {
        callback_(std::string(str, size));
        return size;
    }
};

template<typename T>
auto MakeTCLogSink(T&& callback)
    -> TCLogSink<typename std::decay<T>::type>
{
    return { std::forward<T>(callback) };
}

template<typename T>
static int CreateChildProcess(T waiter, std::string const& executable,
                              std::vector<std::string> const& argsVector,
                              std::string const& logger, std::string const& input,
                              bool secure)
{
    ipstream outStream;
    ipstream errStream;

    if (!secure)
    {
        TC_LOG_TRACE(LOG_FILTER_GENERAL, "Starting process \"%s\" with arguments: \"%s\".",
                executable.c_str(), boost::algorithm::join(argsVector, " ").c_str());
    }

    // Start the child process
    child c = [&]
    {
        if (!input.empty())
        {
            // With binding stdin
            return child
            {
                exe = boost::filesystem::absolute(executable).string(),
                args = argsVector,
                std_in = boost::filesystem::path(input),
                std_out = outStream,
                std_err = errStream
            };
        }

        // Without binding stdin
        return child
        {
            exe = boost::filesystem::absolute(executable).string(),
            args = argsVector,
            std_in = boost::process::close,
            std_out = outStream,
            std_err = errStream
        };
    }();

    auto outInfo = MakeTCLogSink([&](std::string msg)
    {
        TC_LOG_INFO(LOG_FILTER_GENERAL, "%s", msg.c_str());
    });

    auto outError = MakeTCLogSink([&](std::string msg)
    {
        TC_LOG_ERROR(LOG_FILTER_GENERAL, "%s", msg.c_str());
    });

    // Drain both pipes while the child runs. Sequential reads can deadlock
    // when stderr fills up while we are waiting for stdout EOF (or vice versa).
    auto stdoutReader = std::async(std::launch::async, [&] { copy(outStream, outInfo); });
    auto stderrReader = std::async(std::launch::async, [&] { copy(errStream, outError); });

    // Register the asynchronous child with its waiter immediately, not only
    // after all output has arrived, so Terminate() can interrupt a live child.
    int const result = waiter(c);
    stdoutReader.get();
    stderrReader.get();

    if (!secure)
    {
        TC_LOG_TRACE(LOG_FILTER_GENERAL, ">> Process \"%s\" finished with return value %i.",
                executable.c_str(), result);
    }

    return result;
}

int StartProcess(std::string const& executable, std::vector<std::string> const& args,
                 std::string const& logger, std::string input_file, bool secure)
{
    return CreateChildProcess([](child& c) -> int
    {
        try
        {
            c.wait();
            return c.exit_code();
        }
        catch (...)
        {
            return EXIT_FAILURE;
        }
    }, executable, args, logger, input_file, secure);
}

class AsyncProcessResultImplementation
    : public AsyncProcessResult
{
    std::string const executable;
    std::vector<std::string> const args;
    std::string const logger;
    std::string const input_file;
    bool const is_secure;

    std::atomic<bool> was_terminated;

    // Workaround for missing move support in boost < 1.57
    Optional<std::shared_ptr<std::future<int>>> result;
    Optional<std::reference_wrapper<child>> my_child;
    std::mutex child_mutex;

public:
    explicit AsyncProcessResultImplementation(std::string executable_, std::vector<std::string> args_,
                                     std::string logger_, std::string input_file_,
                                     bool secure)
        : executable(std::move(executable_)), args(std::move(args_)),
          logger(std::move(logger_)), input_file(input_file_),
          is_secure(secure), was_terminated(false) { }

    AsyncProcessResultImplementation(AsyncProcessResultImplementation const&) = delete;
    AsyncProcessResultImplementation& operator= (AsyncProcessResultImplementation const&) = delete;
    AsyncProcessResultImplementation(AsyncProcessResultImplementation&&) = delete;
    AsyncProcessResultImplementation& operator= (AsyncProcessResultImplementation&&) = delete;

    int StartProcess()
    {
        return CreateChildProcess([&](child& c) -> int
        {
            int result;
            {
                std::lock_guard<std::mutex> lock(child_mutex);
                ASSERT(!my_child, "Process started already!");
                my_child = std::reference_wrapper<child>(c);
                if (was_terminated)
                {
                    std::error_code ec;
                    c.terminate(ec);
                }
            }

            try
            {
                c.wait();
                result = c.exit_code();
            }
            catch (...)
            {
                result = EXIT_FAILURE;
            }

            {
                std::lock_guard<std::mutex> lock(child_mutex);
                my_child.reset();
            }
            return was_terminated ? EXIT_FAILURE : result;

        }, executable, args, logger, input_file, is_secure);
    }

    void SetFuture(std::future<int> result_)
    {
        result = std::make_shared<std::future<int>>(std::move(result_));
    }

    /// Returns the future which contains the result of the process
    /// as soon it is finished.
    std::future<int>& GetFutureResult() override
    {
        ASSERT(result && *result, "The process wasn't started!");
        return **result;
    }

    /// Tries to terminate the process
    void Terminate() override
    {
        std::lock_guard<std::mutex> lock(child_mutex);
        was_terminated = true;
        if (my_child)
        {
            try
            {
                my_child->get().terminate();
            }
            catch(...)
            {
                // Do nothing
            }
        }
    }
};

std::shared_ptr<AsyncProcessResult>
    StartAsyncProcess(std::string executable, std::vector<std::string> args,
                      std::string logger, std::string input_file, bool secure)
{
    auto handle = std::make_shared<AsyncProcessResultImplementation>(
        std::move(executable), std::move(args), std::move(logger), std::move(input_file), secure);

    handle->SetFuture(std::async(std::launch::async, [handle] { return handle->StartProcess(); }));
    return handle;
}

std::string SearchExecutableInPath(std::string const& filename)
{
    try
    {
        return search_path(filename).string();
    }
    catch (...)
    {
        return "";
    }
}

} // namespace Trinity
