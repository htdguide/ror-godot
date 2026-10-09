#include "ror_solver.h"

#include <functional>
#include <thread>

// The solver on its own thread: M1 acceptance 2's second half.
//
// Rigs of Rods runs its physics on threads of its own and draws the last completed state, and
// that is the model here. `step_async` hands the frame's substeps to a worker and returns; the
// caller poses the vehicle from the positions it already has and gets on with deforming and
// submitting while the solver runs. The next frame waits for the step before it touches
// anything, and `sync` is what every other entry point calls first, so a caller that asks for
// positions straight after posting gets the stepped ones and simply loses the overlap. The
// thread changes where the arithmetic runs and not what it is — the worker runs the same
// sequential `step_now` — which `the_solver_steps_on_its_own_thread` holds by hashing a
// threaded run against a synchronous one.
//
// Timing is taken here on whichever thread runs the step, with a monotonic clock, so a frame can
// report what the solver cost and, separately, how long the frame waited for it.

namespace rorgd {

namespace {
int64_t thread_hash() {
    return static_cast<int64_t>(std::hash<std::thread::id>()(std::this_thread::get_id()));
}
} // namespace

void RorSolver::step(float dt, int substeps) {
    sync();
    const int64_t began = steady_usec();
    step_now(dt, substeps);
    m_step_usec.fetch_add(steady_usec() - began, std::memory_order_relaxed);
    m_step_thread.store(thread_hash(), std::memory_order_relaxed);
}

void RorSolver::step_async(float dt, int substeps) {
    m_worker.post([this, dt, substeps] {
        const int64_t began = steady_usec();
        step_now(dt, substeps);
        m_step_usec.fetch_add(steady_usec() - began, std::memory_order_relaxed);
        m_step_thread.store(thread_hash(), std::memory_order_relaxed);
    });
}

void RorSolver::sync() const {
    m_wait_usec += m_worker.wait();
}

bool RorSolver::step_pending() const {
    return m_worker.pending();
}

int64_t RorSolver::take_step_usec() {
    sync();
    return m_step_usec.exchange(0, std::memory_order_relaxed);
}

int64_t RorSolver::take_wait_usec() {
    const int64_t waited = m_wait_usec;
    m_wait_usec = 0;
    return waited;
}

int64_t RorSolver::last_step_thread() const {
    sync();
    return m_step_thread.load(std::memory_order_relaxed);
}

int64_t RorSolver::caller_thread() const {
    return thread_hash();
}

} // namespace rorgd
