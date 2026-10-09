#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <thread>

namespace rorgd {

// One thread that runs one job at a time for one owner.
//
// The owner posts a job and gets on with its frame; the job runs here; the owner waits for it
// before touching anything the job touches. That is the whole protocol. There is no queue, on
// purpose: a solver handed its next frame's substeps before the last ones are done is a solver
// falling behind, and falling behind should be seen as a wait rather than hidden in a buffer.
//
// Knows nothing about Godot. The thread is a std::thread rather than a WorkerThreadPool task so
// that the step never shares a pool with the renderer, and so that the solver can be stepped
// from a plain SceneTree script with no engine services around it.
class RorStepWorker {
public:
    RorStepWorker() = default;
    ~RorStepWorker();
    RorStepWorker(const RorStepWorker &) = delete;
    RorStepWorker &operator=(const RorStepWorker &) = delete;

    // Runs `job` on the worker thread, starting the thread the first time. Waits for any job
    // still pending first, so two posts in a row run in order and never at once.
    void post(std::function<void()> job);
    // Blocks until no job is pending. Returns the microseconds spent blocked: zero when the job
    // had already finished, which is the number the owner wants to be small.
    int64_t wait();
    bool pending() const { return m_pending.load(std::memory_order_acquire); }
    bool started() const { return m_thread.joinable(); }

private:
    void run();

    std::thread m_thread;
    std::mutex m_mutex;
    std::condition_variable m_wake;
    std::condition_variable m_done;
    std::function<void()> m_job;
    std::atomic<bool> m_pending{false};
    bool m_quit = false;
};

// Microseconds on a monotonic clock, for timing a step on whichever thread runs it.
int64_t steady_usec();

} // namespace rorgd
