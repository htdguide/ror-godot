#include "ror_step_worker.h"

#include <chrono>

namespace rorgd {

int64_t steady_usec() {
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

RorStepWorker::~RorStepWorker() {
    if (!m_thread.joinable()) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_quit = true;
    }
    m_wake.notify_all();
    m_thread.join();
}

void RorStepWorker::post(std::function<void()> job) {
    wait();
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_job = std::move(job);
        m_pending.store(true, std::memory_order_release);
    }
    if (!m_thread.joinable()) {
        m_thread = std::thread(&RorStepWorker::run, this);
    }
    m_wake.notify_one();
}

int64_t RorStepWorker::wait() {
    if (!m_pending.load(std::memory_order_acquire)) {
        return 0;
    }
    const int64_t began = steady_usec();
    std::unique_lock<std::mutex> lock(m_mutex);
    m_done.wait(lock, [this] { return !m_pending.load(std::memory_order_acquire); });
    return steady_usec() - began;
}

void RorStepWorker::run() {
    for (;;) {
        std::function<void()> job;
        {
            std::unique_lock<std::mutex> lock(m_mutex);
            m_wake.wait(lock, [this] { return m_quit || m_pending.load(std::memory_order_acquire); });
            if (m_quit) {
                return;
            }
            job = std::move(m_job);
        }
        job();
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_pending.store(false, std::memory_order_release);
        }
        m_done.notify_all();
    }
}

} // namespace rorgd
