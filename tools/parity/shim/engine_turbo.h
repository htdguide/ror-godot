// Rigs of Rods' Engine and its torque curve's spline, with upstream's names, types and constructor
// defaults (gameplay/Engine.h, Engine.cpp, TorqueCurve.cpp, OgreSimpleSpline.cpp), so that
// `Engine::UpdateEngine` and the turbo pass, the gearbox methods and `getEngineTorque` compile as
// written.
#pragma once

#include <deque>
#include <vector>

#define MAXTURBO 4
#ifndef SOUND_START
#define SOUND_START(actor, trig)
#define SOUND_STOP(actor, trig)
#endif
#ifndef LOG
#define LOG(message)
#endif

namespace Ogre {
// Ogre 1.11's `SimpleSpline` (OgreSimpleSpline.cpp): Hermite segments through the points, the
// tangents recalculated on every point added, `interpolate` as `powers * mCoeffs * pt` with
// `Vector4 * Matrix4` summed as OgreMatrix4.h sums it.
class SimpleSpline {
public:
    void addPoint(const Vector3 &p) {
        mPoints.push_back(p);
        recalcTangents();
    }
    unsigned short getNumPoints() const { return (unsigned short)mPoints.size(); }
    const Vector3 &getPoint(unsigned short index) const { return mPoints[index]; }
    void clear() {
        mPoints.clear();
        mTangents.clear();
    }
    Vector3 interpolate(Real t) const {
        Real fSeg = t * (mPoints.size() - 1);
        unsigned int segIdx = (unsigned int)fSeg;
        t = fSeg - segIdx;
        return interpolate(segIdx, t);
    }
    Vector3 interpolate(unsigned int fromIndex, Real t) const {
        if ((fromIndex + 1) == mPoints.size()) {
            return mPoints[fromIndex];
        }
        if (t == 0.0f) {
            return mPoints[fromIndex];
        } else if (t == 1.0f) {
            return mPoints[fromIndex + 1];
        }
        Real t2 = t * t, t3 = t2 * t;
        const Real powers[4] = {t3, t2, t, 1};
        const Vector3 &point1 = mPoints[fromIndex];
        const Vector3 &point2 = mPoints[fromIndex + 1];
        const Vector3 &tan1 = mTangents[fromIndex];
        const Vector3 &tan2 = mTangents[fromIndex + 1];
        const Real pt[4][4] = {{point1.x, point1.y, point1.z, 1.0f}, {point2.x, point2.y, point2.z, 1.0f},
                               {tan1.x, tan1.y, tan1.z, 1.0f}, {tan2.x, tan2.y, tan2.z, 1.0f}};
        Real b[4], ret[4];
        for (int j = 0; j < 4; ++j) {
            b[j] = powers[0] * mCoeffs[0][j] + powers[1] * mCoeffs[1][j] + powers[2] * mCoeffs[2][j] + powers[3] * mCoeffs[3][j];
        }
        for (int j = 0; j < 4; ++j) {
            ret[j] = b[0] * pt[0][j] + b[1] * pt[1][j] + b[2] * pt[2][j] + b[3] * pt[3][j];
        }
        return Vector3(ret[0], ret[1], ret[2]);
    }
    void recalcTangents() {
        size_t numPoints = mPoints.size();
        if (numPoints < 2) {
            return;
        }
        bool isClosed = mPoints[0].x == mPoints[numPoints - 1].x && mPoints[0].y == mPoints[numPoints - 1].y &&
                        mPoints[0].z == mPoints[numPoints - 1].z;
        mTangents.resize(numPoints);
        for (size_t i = 0; i < numPoints; ++i) {
            if (i == 0) {
                mTangents[i] = isClosed ? 0.5 * (mPoints[1] - mPoints[numPoints - 2]) : 0.5 * (mPoints[1] - mPoints[0]);
            } else if (i == numPoints - 1) {
                mTangents[i] = isClosed ? mTangents[0] : 0.5 * (mPoints[i] - mPoints[i - 1]);
            } else {
                mTangents[i] = 0.5 * (mPoints[i + 1] - mPoints[i - 1]);
            }
        }
    }

private:
    std::vector<Vector3> mPoints, mTangents;
    const Real mCoeffs[4][4] = {{2, -2, 1, 1}, {-3, 3, -2, -1}, {0, 0, 1, 0}, {1, 0, 0, 0}};
};
} // namespace Ogre

#ifndef TRIGGER_EVENT_ASYNC
#define TRIGGER_EVENT_ASYNC(...)
#endif

namespace RoR {

class Actor;
using ActorPtr = Actor *;
enum class SimGearboxMode { AUTO, SEMI_AUTO, MANUAL, MANUAL_STICK, MANUAL_RANGES };

// Upstream's `TorqueCurve`, holding one spline; `getEngineTorque` is upstream's, lifted.
class TorqueCurve {
public:
    Real getEngineTorque(Real rpm);
    Ogre::SimpleSpline spline;
    Ogre::SimpleSpline *usedSpline = &spline;
};

// Rigs of Rods' `Engine` (gameplay/Engine.h): every member `UpdateEngine` and its gearbox methods
// read, with upstream's names and types. The constructor and the methods are upstream's, lifted.
class Engine {
public:
    enum turbomode { OLD, NEW };
    enum autoswitch { REAR, NEUTRAL, DRIVE, TWO, ONE, MANUALMODE };

    Engine() = default;
    Engine(float _min_rpm, float _max_rpm, float torque, float reverse_gear, float neutral_gear, std::vector<float> forward_gears, float diff_ratio, ActorPtr actor);
    void SetEngineOptions(float einertia, char etype, float eclutch, float ctime, float stime, float pstime, float irpm, float srpm, float maximix, float minimix, float ebraking);
    void SetTurboOptions(int type, float tinertiaFactor, int nturbos, float param1, float param2, float param3, float param4, float param5, float param6, float param7, float param8, float param9, float param10, float param11);
    float getTurboPSI();
    float getTurboPower();
    // The `if (m_engine_has_turbo)` block of `UpdateEngine`, with its local `acc`.
    void UpdateTurbo(float dt, float acc);
    void UpdateEngine(float dt, int doUpdate);
    void toggleAutoMode();
    void setAcc(float val);
    float getAccToHoldRPM();
    void autoSetAcc(float val);
    void shift(int val);
    void shiftTo(int newGear);
    void updateShifts();
    void autoShiftSet(int mode);
    void autoShiftUp();
    void autoShiftDown();
    void setManualClutch(float val);
    float getEnginePower() { return getEnginePower(m_cur_engine_rpm); }
    float getEnginePower(float rpm);
    float getIdleMixture();
    float getPrimeMixture();
    float getCrankFactor();
    void startEngine();
    void offStart();
    void stopEngine();
    int getNumGears() const { return m_num_gears; }

    ActorPtr m_actor = nullptr;
    bool m_engine_has_turbo = true;
    int m_engine_turbo_mode = OLD;
    bool m_engine_is_running = true;
    float m_cur_acc = 0.0f;
    float m_cur_engine_rpm = 0.0f;
    float m_engine_max_rpm = 0.0f;
    float m_engine_torque = 0.0f;
    int m_turbo_ver = 1;
    float m_cur_turbo_rpm[MAXTURBO] = {0, 0, 0, 0};
    float m_turbo_inertia_factor = 1;
    int m_num_turbos = 1;
    int m_max_turbo_rpm = 200000;
    float m_engine_addi_torque[MAXTURBO] = {0, 0, 0, 0};
    float m_turbo_engine_rpm_operation = 0.0f;
    bool m_turbo_has_bov = false;
    float m_turbo_bov_rpm[MAXTURBO] = {0, 0, 0, 0};
    int m_min_bov_psi = 11;
    bool m_turbo_has_wastegate = false;
    float m_min_wastegate_psi = 20;
    bool m_turbo_flutters = false;
    float m_turbo_wg_threshold_p = 0;
    float m_turbo_wg_threshold_n = 0;
    bool m_turbo_has_antilag = false;
    float m_antilag_min_rpm = 3000;
    float m_antilag_rand_chance = 0.9975;
    float m_antilag_power_factor = 170;
    // The rest of the engine, gearbox and clutch.
    float m_ref_wheel_revolutions = 0, m_cur_wheel_revolutions = 0;
    int m_cur_gear = 0, m_cur_gear_range = 0, m_num_gears = 0;
    std::vector<float> m_gear_ratios;
    float m_clutch_force = 10000, m_clutch_time = 0.2f, m_cur_clutch = 0, m_cur_clutch_torque = 0;
    bool m_engine_is_electric = false, m_engine_has_air = true;
    char m_engine_type = 't';
    float m_braking_torque = 0, m_cur_engine_torque = 0, m_diff_ratio = 1, m_tcase_ratio = 1, m_hydropump_state = 0;
    float m_min_idle_mixture = 0, m_max_idle_mixture = 0.1f, m_engine_inertia = 10, m_engine_min_rpm = 0;
    float m_engine_idle_rpm = 0, m_engine_stall_rpm = 300;
    bool m_engine_is_priming = false;
    TorqueCurve *m_torque_curve = nullptr;
    float m_air_pressure = 0;
    bool m_contact = false, m_starter = false;
    float m_post_shift_time = 0.2f, m_post_shift_clock = 0, m_shift_time = 0.5f, m_shift_clock = 0;
    int m_post_shifting = 0, m_shifting = 0, m_shift_val = 0;
    SimGearboxMode m_auto_mode = SimGearboxMode::AUTO;
    autoswitch m_autoselect = DRIVE;
    float m_auto_cur_acc = 0, m_full_rpm_range = 0, m_one_third_rpm_range = 0, m_half_rpm_range = 0, m_shift_behaviour = 0;
    int m_upshift_delay_counter = 0, m_kickdown_delay_counter = 0;
    std::deque<float> m_rpms, m_accs, m_brakes;
};

} // namespace RoR

// `ApproxMath.h`'s `frand` state back to its start, between cases.
void reset_frand();
