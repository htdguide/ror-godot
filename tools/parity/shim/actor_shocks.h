// The part of Rigs of Rods' Actor that its beam laws read: `CalcBeams`, `CalcShocks2`,
// `CalcShocks3` and `GetNumActiveConnectedBeams`.
//
// All are member functions reading `ar_beams[i]` and what it points at. Declaring an Actor with
// only those members lets them be compiled from upstream's source unmodified. Names, types, enum
// values and constants are upstream's (SimData.h, SimConstants.h, BitFlags.h); a rename there
// breaks this build, which is the point. The debug, sound and console paths are compiled but
// stubbed: the oracle runs with every debug flag off and nothing to play.
#pragma once

#include "OgreVector3.h"
#include "rig_types.h"

#include <algorithm>
#include <cmath>
#include <sstream>
#include <string>
#include <array>
#include <unordered_map>
#include <vector>

using Ogre::Real;

namespace Ogre {
using String = std::string;
struct Math {
    // OgreMath.h: `std::max(std::min(val, maxval), minval)`.
    template <typename T> static T Clamp(T val, T minval, T maxval) {
        return std::max(std::min(val, maxval), minval);
    }
    // OgreMath.cpp 1.11: `fRad2Deg = Real(180.0) / PI`, `PI = Real(4.0 * atan(1.0))`.
    static float RadiansToDegrees(float radians) {
        static const float PI = float(4.0 * std::atan(1.0));
        static const float fRad2Deg = float(180.0) / PI;
        return radians * fRad2Deg;
    }
};
} // namespace Ogre

#define BITMASK( OFFSET ) ( 1 << ((OFFSET) - 1) )

// SimConstants.h
static const float DEFAULT_SPRING = 9000000.0f;
static const float DEFAULT_DAMP = 12000.0f;
static const float MIN_BEAM_LENGTH = 0.1f;
static const float SUPPORT_BEAM_LIMIT_DEFAULT = 4.0f;

// SimData.h
enum BeamType : short { BEAM_NORMAL, BEAM_HYDRO, BEAM_VIRTUAL };
enum SpecialBeam : short { NOSHOCK, SHOCK1, SHOCK2, SHOCK3, TRIGGER, SUPPORTBEAM, ROPE };
enum ShockFlags {
    SHOCK_FLAG_NORMAL = BITMASK(1),
    SHOCK_FLAG_ISSHOCK2 = BITMASK(5),
    SHOCK_FLAG_ISSHOCK3 = BITMASK(6),
    SHOCK_FLAG_SOFTBUMP = BITMASK(7),
    SHOCK_FLAG_ISTRIGGER = BITMASK(8),
    SHOCK_FLAG_TRG_BLOCKER = BITMASK(9),
    SHOCK_FLAG_TRG_CMD_SWITCH = BITMASK(10),
    SHOCK_FLAG_TRG_CMD_BLOCKER = BITMASK(11),
    SHOCK_FLAG_TRG_BLOCKER_A = BITMASK(12),
    SHOCK_FLAG_TRG_HOOK_UNLOCK = BITMASK(13),
    SHOCK_FLAG_TRG_HOOK_LOCK = BITMASK(14),
    SHOCK_FLAG_TRG_CONTINUOUS = BITMASK(15),
    SHOCK_FLAG_TRG_ENGINE = BITMASK(16),
};
enum EngineTriggerType {
    TRG_ENGINE_CLUTCH = 0, TRG_ENGINE_BRAKE = 1, TRG_ENGINE_ACC = 2, TRG_ENGINE_RPM = 3,
    TRG_ENGINE_SHIFTUP = 4, TRG_ENGINE_SHIFTDOWN = 5
};

struct shock_t {
    // What `CalcTriggers` reads and writes; upstream zeroes the whole struct.
    int beamid = 0;
    bool trigger_enabled = false;
    float trigger_switch_state = 0, trigger_boundary_t = 0;
    int trigger_cmdlong = 0, trigger_cmdshort = 0, last_debug_state = 0;
    int flags = 0;
    float springin = 0, dampin = 0, springout = 0, dampout = 0;
    float sprogin = 0, dprogin = 0, sprogout = 0, dprogout = 0;
    float splitin = 0, dslowin = 0, dfastin = 0, splitout = 0, dslowout = 0, dfastout = 0;
    float sbd_spring = 0, sbd_damp = 0;
};

struct beam_t {
    node_t *p1 = nullptr;
    node_t *p2 = nullptr;
    float k = 0, d = 0, L = 0;
    float minmaxposnegstress = 0, maxposstress = 0, maxnegstress = 0;
    float strength = 0, stress = 0, plastic_coef = 0;
    float shortbound = 0, longbound = 0;
    int detacher_group = 0;
    SpecialBeam bounded = NOSHOCK;
    BeamType bm_type = BEAM_NORMAL;
    bool bm_inter_actor = false, bm_disabled = false, bm_broken = false;
    float debug_k = 0, debug_d = 0, debug_v = 0;
    shock_t *shock = nullptr;
};

// SimConstants.h
#define PHYSICS_DT 0.0005f
static const float RAD_PER_SEC_TO_RPM = 9.5492965855137f;

// Application.h, numbered as upstream numbers them.
enum class WheelPropulsion : int { NONE = 0, FORWARD = 1, BACKWARD = 2 };
enum class WheelBraking : int { NONE = 0, FOOT_HAND = 1, FOOT_HAND_SKID_LEFT = 2, FOOT_HAND_SKID_RIGHT = 3, FOOT_ONLY = 4 };

// SimData.h, the fields `CalcWheels` reads and writes.
struct wheel_t {
    int wh_num_nodes = 0;
    node_t *wh_nodes[50] = {};
    node_t *wh_axis_node_0 = nullptr;
    node_t *wh_axis_node_1 = nullptr;
    node_t *wh_arm_node = nullptr;
    node_t *wh_near_attach_node = nullptr;
    WheelBraking wh_braking = WheelBraking::NONE;
    WheelPropulsion wh_propulsed = WheelPropulsion::NONE;
    float wh_radius = 0, wh_mass = 0, wh_speed = 0, wh_avg_speed = 0, wh_torque = 0;
    float wh_last_torque = 0, wh_last_retorque = 0, wh_net_rp = 0;
    float wh_alb_coef = 0, wh_tc_coef = 0;
    bool wh_is_detached = false;
    float debug_rpm = 0, debug_torque = 0;
    Ogre::Vector3 debug_vel, debug_slip, debug_force, debug_scaled_cforce;
};
struct wheeldetacher_t {
    int wd_wheel_id = 0;
    int wd_detacher_group = 0;
};

// The diagnostics CalcBeams writes when its debug flags are on. They are off in the oracle; these
// exist so the code that would write them compiles.
#define SOUND_MODULATE(...) ((void)0)
#define SOUND_PLAY_ONCE(...) ((void)0)
#define SOUND_START(...) ((void)0)
#define SOUND_STOP(...) ((void)0)
#define TOSTRING(x) std::to_string(x)

// Upstream's `Airfoil`: `CalcFuseDrag` asks it for the fuselage's drag coefficient and multiplies
// it by the fuselage's side area, which is zero because the spawner sets its back node to its front
// node. Any finite answer gives the same result.
struct FuseAirfoilShim {
    void getparams(float, float, float, float *cl, float *cd, float *cm) { *cl = 0.5f; *cd = 0.3f; *cm = 0.0f; }
};

// SimData.h's command key and its array, as upstream writes them.
static const int MAX_COMMANDS = 84;
struct command_t {
    int commandValueState = 0;
    float commandValue = 0;
    float triggerInputValue = 0.f;
    float playerInputValue = 0.f;
    bool trigger_cmdkeyblock_state = false;
};
class CmdKeyArray {
public:
    command_t &operator[](int index) {
        if (index >= 0 && index <= MAX_COMMANDS) {
            return m_commandkey[index];
        } else if (index < 0) {
            return m_virtualkey[index];
        } else {
            return m_dummykey;
        }
    }
private:
    std::array<command_t, MAX_COMMANDS + 1> m_commandkey;
    std::unordered_map<int, command_t> m_virtualkey;
    command_t m_dummykey;
};

#ifndef LOG
#define LOG(message)
#endif

// What `CalcHydros` and `CalcAnimators` read (SimData.h, SimConstants.h), with upstream's names.
enum HydroFlags {
    HYDRO_FLAG_SPEED = BITMASK(1), HYDRO_FLAG_DIR = BITMASK(2), HYDRO_FLAG_AILERON = BITMASK(3),
    HYDRO_FLAG_RUDDER = BITMASK(4), HYDRO_FLAG_ELEVATOR = BITMASK(5), HYDRO_FLAG_REV_AILERON = BITMASK(6),
    HYDRO_FLAG_REV_RUDDER = BITMASK(7), HYDRO_FLAG_REV_ELEVATOR = BITMASK(8),
};
enum AnimFlags : unsigned int {
    ANIM_FLAG_AIRSPEED = BITMASK(1), ANIM_FLAG_VVI = BITMASK(2), ANIM_FLAG_ALTIMETER = BITMASK(3),
    ANIM_FLAG_AOA = BITMASK(4), ANIM_FLAG_FLAP = BITMASK(5), ANIM_FLAG_AIRBRAKE = BITMASK(6),
    ANIM_FLAG_ROLL = BITMASK(7), ANIM_FLAG_PITCH = BITMASK(8), ANIM_FLAG_THROTTLE = BITMASK(9),
    ANIM_FLAG_RPM = BITMASK(10), ANIM_FLAG_ACCEL = BITMASK(11), ANIM_FLAG_BRAKE = BITMASK(12),
    ANIM_FLAG_CLUTCH = BITMASK(13), ANIM_FLAG_TACHO = BITMASK(14), ANIM_FLAG_SPEEDO = BITMASK(15),
    ANIM_FLAG_PBRAKE = BITMASK(16), ANIM_FLAG_TURBO = BITMASK(17), ANIM_FLAG_SHIFTER = BITMASK(18),
    ANIM_FLAG_AETORQUE = BITMASK(19), ANIM_FLAG_AEPITCH = BITMASK(20), ANIM_FLAG_AESTATUS = BITMASK(21),
    ANIM_FLAG_TORQUE = BITMASK(22), ANIM_FLAG_HEADING = BITMASK(23), ANIM_FLAG_DIFFLOCK = BITMASK(24),
    ANIM_FLAG_BRUDDER = BITMASK(29), ANIM_FLAG_BTHROTTLE = BITMASK(30),
};
static const float FLAP_ANGLES[6] = {0.f, -0.07f, -0.17f, -0.33f, -0.67f, -1.f};
// The oracle's animators run with no inertia: upstream's `CmdKeyInertia` passes its input through
// until it is configured, which ours is held to by the hydro inertia gate.
struct CmdKeyInertiaShim {
    float CalcCmdKeyDelay(float in, float) { return in; }
};
struct hydrobeam_t {
    uint16_t hb_beam_index{0};
    float hb_ref_length{0};
    float hb_speed{0};
    unsigned int hb_flags{0};
    unsigned int hb_anim_flags{0};
    float hb_anim_param{0};
    CmdKeyInertiaShim hb_inertia;
};
// Upstream's console variables CalcHydros reads for analogue steering, at their defaults.
struct CVar {
    float value;
    float getFloat() const { return value; }
};
// The parts of aero engines, wings and screw props the animators would read; a vehicle in these
// cases has none, so these are never called.
enum class AeroEngineType { AE_UNKNOWN, AE_XPROP };
struct AeroEngine {
    // What a wing's wash reads, set by the oracle's wing cases.
    float propwash = 0;
    Ogre::Vector3 axis;
    float getpropwash() { return propwash; }
    Ogre::Vector3 getAxis() { return axis; }
    float getRPMpc() { return 0; }
    float getThrottle() { return 0; }
    AeroEngineType getType() { return AeroEngineType::AE_UNKNOWN; }
    bool getIgnition() { return false; }
    bool isFailed() { return false; }
};
struct AeroEnginePtr {
    AeroEngine *p = nullptr;
    AeroEngine *operator->() { return p; }
    AeroEngine *GetRef() { return p; }
};
struct Screwprop {
    float getRudder() { return 0; }
    float getThrottle() { return 0; }
};
struct FlexAirfoilShim {
    float aoa = 0;
};
struct wing_t {
    FlexAirfoilShim *fa = nullptr;
};

// A hook trigger's request, which upstream queues as a message for the game loop; recorded here.
enum class ActorLinkingRequestType { INVALID, HOOK_LOCK, HOOK_UNLOCK };
struct ActorLinkingRequest {
    int alr_actor_instance_id = -1;
    ActorLinkingRequestType alr_type = ActorLinkingRequestType::INVALID;
    int alr_hook_group = -1;
};
enum MsgType { MSG_SIM_ACTOR_LINKING_REQUESTED };
struct Message {
    Message(MsgType, ActorLinkingRequest *rq) : request(rq) {}
    ActorLinkingRequest *request;
};
struct GameContext {
    std::vector<std::string> requests;
    void PushMessage(Message m) {
        requests.push_back(std::string(m.request->alr_type == ActorLinkingRequestType::HOOK_LOCK ? "lock " : "unlock ") +
                           std::to_string(m.request->alr_hook_group));
        delete m.request;
    }
};

namespace RoR {
template <size_t N> struct Str {
    std::ostringstream out;
    template <typename T> Str &operator<<(const T &value) { out << value; return *this; }
    std::string text;
    const char *ToCStr() { text = out.str(); return text.c_str(); }
};
inline void Log(const char *) {}
struct Console {
    enum MessageType { CONSOLE_MSGTYPE_ACTOR };
    enum MessageArea { CONSOLE_SYSTEM_NOTICE };
    void putMessage(int, int, const std::string &) {}
};
class Differential;
namespace App {
inline CVar *io_analog_smoothing = new CVar{1.0f};
inline CVar *io_analog_sensitivity = new CVar{1.0f};
inline Console *GetConsole() { static Console console; return &console; }
inline GameContext *GetGameContext() { static GameContext context; return &context; }
}
struct Buoyance {
    enum { BUOY_NORMAL, BUOY_DRAGONLY, BUOY_DRAGLESS };
    bool sink = false;
};

class Actor {
public:
    std::vector<beam_t> beams;
    beam_t *ar_beams = nullptr;
    int ar_num_beams = 0;
    node_t *ar_nodes = nullptr;
    std::vector<std::vector<int>> ar_node_to_beam_connections;
    wheel_t *ar_wheels = nullptr;
    std::vector<wheeldetacher_t> ar_wheeldetachers;
    int ar_num_buoycabs = 0;
    int *ar_buoycabs = nullptr;
    int *ar_buoycab_types = nullptr;
    int *ar_cabs = nullptr;
    Buoyance *m_buoyance = nullptr;
    int ar_instance_id = 0;
    bool m_beam_break_debug_enabled = false;
    bool m_beam_deform_debug_enabled = false;

    // What `CalcWheels` reads besides the wheels.
    int ar_num_wheels = 0;
    float tc_timer = 0, alb_timer = 0, tc_pulse_time = 0, alb_pulse_time = 0;
    bool tc_pulse_state = false, alb_pulse_state = false, tc_mode = false, alb_mode = false;
    float tc_ratio = 0, alb_ratio = 0, alb_minspeed = 0, tc_wheelslip_constant = 0.25f;
    bool m_antilockbrake = false, m_tractioncontrol = false;
    float ar_wheel_spin = 0, ar_wheel_speed = 0, ar_avg_wheel_speed = 0;
    float ar_brake_force = 0, ar_brake = 0, m_handbrake_force = 0, ar_hydro_dir_state = 0, ar_total_mass = 1;
    bool ar_parking_brake = false;
    int m_num_proped_wheels = 0;
    float m_odometer_total = 0, m_odometer_user = 0;
    // The engine calls a trigger makes, recorded for the oracle to print.
    struct Engine {
        std::vector<std::string> calls;
        void setWheelSpin(float) {}
        void setClutch(float v) { calls.push_back("clutch " + std::to_string(v)); }
        // What the animators read, set by the oracle from each step.
        float crank = 0, rpm = 0, shift_up_rpm = 1, turbo_psi = 0, acc = 0, clutch = 0;
        int gear = 0, num_gears = 0;
        float getCrankFactor() { return crank; }
        int getGear() { return gear; }
        int getNumGears() { return num_gears; }
        float getRPM() { return rpm; }
        float getShiftUpRPM() { return shift_up_rpm; }
        float getTurboPSI() { return turbo_psi; }
        float getAcc() { return acc; }
        float getClutch() { return clutch; }
        void setAcc(float v) { calls.push_back("acc " + std::to_string(v)); }
        void shift(int by) { calls.push_back("shift " + std::to_string(by)); }
    } *ar_engine = nullptr;
    // The camera direction upstream computes from its camera nodes; the oracle is handed it.
    Ogre::Vector3 direction;
    Ogre::Vector3 getDirection() { return direction; }
    void CalcWheels(bool doUpdate, int num_steps);
    // What `CalcFuseDrag` reads and writes.
    FuseAirfoilShim *m_fusealge_airfoil = nullptr;
    node_t *m_fusealge_front = nullptr;
    node_t *m_fusealge_back = nullptr;
    float m_fusealge_width = 0.0f;
    Ogre::Vector3 ar_fusedrag;
    int ar_num_nodes = 0;
    void CalcFuseDrag();

    template <size_t N> void LogBeamNodes(Str<N> &, beam_t &) {}
    // What `CalcTriggers` and `engineTriggerHelper` read and write (`actor_triggers.h`).
    CmdKeyArray ar_command_key;
    shock_t *ar_shocks = nullptr;
    int ar_num_shocks = 0;
    bool m_trigger_debug_enabled = false;
    std::vector<bool> ar_beams_invisible;
    void CalcTriggers(int i, Real difftoBeamL, bool trigger_hooks);
    // What `CalcHydros` and `CalcAnimators` read and write.
    float ar_hydro_dir_command = 0, ar_hydro_dir_wheel_display = 0;
    bool ar_hydro_speed_coupling_active = false, ar_hydro_speed_coupling_enabled = false;
    float ar_hydro_aileron_state = 0, ar_hydro_aileron_command = 0, ar_hydro_rudder_state = 0;
    float ar_hydro_rudder_command = 0, ar_hydro_elevator_state = 0, ar_hydro_elevator_command = 0;
    std::vector<hydrobeam_t> ar_hydros;
    Screwprop *ar_screwprops[1] = {nullptr};
    int ar_num_screwprops = 0;
    Differential *m_wheel_diffs[1] = {nullptr};
    int m_num_wheel_diffs = 0;
    float ar_anim_previous_crank = 0, ar_anim_shift_timer = 0;
    int m_previous_gear = 0;
    float ar_guisettings_speedo_max_kph = 140.f;
    AeroEnginePtr ar_aeroengines[1];
    int ar_num_aeroengines = 0;
    wing_t *ar_wings = nullptr;
    int ar_num_wings = 0;
    float ar_airbrake_intensity = 0;
    int ar_aerial_flap = 0;
    int ar_main_camera_node_pos = 0, ar_main_camera_node_dir = 0, ar_main_camera_node_roll = 0;
    Ogre::Vector3 GetCameraDir() { return (ar_nodes[ar_main_camera_node_pos].RelPosition - ar_nodes[ar_main_camera_node_dir].RelPosition).normalisedCopy(); }
    Ogre::Vector3 GetCameraRoll() { return (ar_nodes[ar_main_camera_node_pos].RelPosition - ar_nodes[ar_main_camera_node_roll].RelPosition).normalisedCopy(); }
    // The heading animator flag has no option that sets it.
    float getRotation() { return 0.0f; }
    void CalcHydros();
    void CalcAnimators(hydrobeam_t const &hydrobeam, float &cstate, int &div);
    void engineTriggerHelper(int engineNumber, EngineTriggerType type, float triggerValue);
    void CalcBeams(bool trigger_hooks);
    int GetNumActiveConnectedBeams(int nodeid);
    void CalcShocks2(int i, Real difftoBeamL, Real &k, Real &d, Real v);
    void CalcShocks3(int i, Real difftoBeamL, Real &k, Real &d, Real v);
};
} // namespace RoR
