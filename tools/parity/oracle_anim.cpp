// The parity oracle's animator mode (see oracle.cpp): upstream's `CalcHydros`, which calls its
// `CalcAnimators`, on animators a gate describes.
#include "actor_shocks.h"
#include "aero_engines.h"
#include "differentials.h"

#include <cstdio>
#include <sstream>
#include <string>
#include <vector>

// `anim n_animators n_steps`, then per animator "flags param factor ref_length short long", then per
// step "engine crank gear num_gears parking wheel_speed speedo_max rpm shift_up psi brake acc clutch
// diff_kind", node 0's velocity and height, the camera's pos, dir and roll nodes, then the
// airplane's "flap airbrake num_wings wing4_aoa num_engines" and per engine "rpm_pc throttle xprop
// indicated_torque max_torque pitch ignition failed". Prints per step every animator beam's length
// and the animators' shared memory.
bool run_anim(const std::string &line) {
    std::istringstream in(line.substr(4));
    int n_anims = 0, n_steps = 0;
    if (!(in >> n_anims >> n_steps)) {
        return false;
    }
    RoR::Actor actor;
    actor.beams.resize(static_cast<size_t>(n_anims));
    std::vector<node_t> nodes(4);
    actor.ar_nodes = nodes.data();
    actor.ar_beams = actor.beams.data();
    actor.ar_num_beams = n_anims;
    actor.ar_main_camera_node_pos = 1;
    actor.ar_main_camera_node_dir = 2;
    actor.ar_main_camera_node_roll = 3;
    for (int i = 0; i < n_anims; ++i) {
        hydrobeam_t hb;
        float factor = 0, ref = 0, sb = 0, lb = 0;
        in >> hb.hb_anim_flags >> hb.hb_anim_param >> factor >> ref >> sb >> lb;
        hb.hb_beam_index = static_cast<uint16_t>(i);
        hb.hb_speed = factor;
        hb.hb_ref_length = ref;
        actor.beams[static_cast<size_t>(i)].L = ref;
        actor.beams[static_cast<size_t>(i)].shortbound = sb;
        actor.beams[static_cast<size_t>(i)].longbound = lb;
        actor.ar_hydros.push_back(hb);
    }
    RoR::Actor::Engine engine;
    RoR::Differential diff;
    static FlexAirfoilShim airfoils[8];
    static wing_t wings[8];
    static AeroEngine aero[8];
    static RoR::Turboprop props[8];
    for (int i = 0; i < 8; ++i) {
        wings[i].fa = &airfoils[i];
        actor.ar_aeroengines[i].p = &aero[i];
        actor.ar_aeroengines[i].prop = &props[i];
    }
    actor.ar_wings = wings;
    const char *names[] = {"Open", "Split", "Locked", "Viscous"};
    for (int step = 0; step < n_steps; ++step) {
        int has_engine = 0, parking = 0, diff_kind = 0;
        in >> has_engine >> engine.crank >> engine.gear >> engine.num_gears >> parking >> actor.ar_wheel_speed >>
                actor.ar_guisettings_speedo_max_kph >> engine.rpm >> engine.shift_up_rpm >> engine.turbo_psi >>
                actor.ar_brake >> engine.acc >> engine.clutch >> diff_kind;
        in >> nodes[0].Velocity.x >> nodes[0].Velocity.y >> nodes[0].Velocity.z >> nodes[0].AbsPosition.y;
        for (int n = 1; n < 4; ++n) {
            in >> nodes[static_cast<size_t>(n)].RelPosition.x >> nodes[static_cast<size_t>(n)].RelPosition.y >>
                    nodes[static_cast<size_t>(n)].RelPosition.z;
        }
        in >> actor.ar_aerial_flap >> actor.ar_airbrake_intensity >> actor.ar_num_wings >> airfoils[4].aoa >>
                actor.ar_num_aeroengines;
        for (int e = 0; e < actor.ar_num_aeroengines && e < 8; ++e) {
            int xprop = 0, ignition = 0, failed = 0;
            in >> aero[e].rpmpc >> aero[e].throttle >> xprop >> props[e].indicated_torque >> props[e].max_torque >>
                    props[e].pitch >> ignition >> failed;
            aero[e].type = xprop ? AeroEngineType::AE_XPROP : AeroEngineType::AE_UNKNOWN;
            aero[e].ignition = ignition != 0;
            aero[e].failed = failed != 0;
        }
        if (!in || actor.ar_num_aeroengines > 8 || actor.ar_num_wings > 8) {
            return false;
        }
        actor.ar_engine = has_engine ? &engine : nullptr;
        actor.ar_parking_brake = parking != 0;
        actor.m_num_wheel_diffs = diff_kind >= 0 ? 1 : 0;
        if (diff_kind >= 0) {
            diff.type_name = names[diff_kind];
            actor.m_wheel_diffs[0] = &diff;
        }
        actor.CalcHydros();
        std::string out;
        char buffer[48];
        for (int i = 0; i < n_anims; ++i) {
            std::snprintf(buffer, sizeof buffer, "%.9g ", actor.beams[static_cast<size_t>(i)].L);
            out += buffer;
        }
        std::snprintf(buffer, sizeof buffer, "| %.9g %d %.9g", actor.ar_anim_previous_crank, actor.m_previous_gear,
                      actor.ar_anim_shift_timer);
        out += buffer;
        std::printf("%s\n", out.c_str());
    }
    return true;
}

// `hydro n_hydros n_steps`, then per hydro "flags factor ref_length", then per step "steer_command
// aileron rudder elevator wheel_speed". Speed coupling on, as ours steers. Prints per step every
// hydro beam's length and the steering's and three surfaces' states.
bool run_hydro(const std::string &line) {
    std::istringstream in(line.substr(5));
    int n_hydros = 0, n_steps = 0;
    if (!(in >> n_hydros >> n_steps)) {
        return false;
    }
    RoR::Actor actor;
    actor.beams.resize(static_cast<size_t>(n_hydros));
    actor.ar_beams = actor.beams.data();
    actor.ar_num_beams = n_hydros;
    actor.ar_hydro_speed_coupling_active = true;
    actor.ar_hydro_speed_coupling_enabled = true;
    for (int i = 0; i < n_hydros; ++i) {
        hydrobeam_t hb;
        float ref = 0;
        in >> hb.hb_flags >> hb.hb_speed >> ref;
        hb.hb_beam_index = static_cast<uint16_t>(i);
        hb.hb_ref_length = ref;
        actor.beams[static_cast<size_t>(i)].L = ref;
        actor.ar_hydros.push_back(hb);
    }
    for (int step = 0; step < n_steps; ++step) {
        float steer = 0;
        in >> steer >> actor.ar_hydro_aileron_command >> actor.ar_hydro_rudder_command >>
                actor.ar_hydro_elevator_command >> actor.ar_wheel_speed;
        if (!in) {
            return false;
        }
        // Ours clamps the steering command as it is set, as upstream's input does.
        actor.ar_hydro_dir_command = steer < -1.0f ? -1.0f : (steer > 1.0f ? 1.0f : steer);
        actor.CalcHydros();
        std::string out;
        char buffer[48];
        for (int i = 0; i < n_hydros; ++i) {
            std::snprintf(buffer, sizeof buffer, "%.9g ", actor.beams[static_cast<size_t>(i)].L);
            out += buffer;
        }
        std::snprintf(buffer, sizeof buffer, "| %.9g %.9g %.9g %.9g", actor.ar_hydro_dir_state,
                      actor.ar_hydro_aileron_state, actor.ar_hydro_rudder_state, actor.ar_hydro_elevator_state);
        out += buffer;
        std::printf("%s\n", out.c_str());
    }
    return true;
}
