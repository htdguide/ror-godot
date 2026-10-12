// What upstream's `Turboprop` and `Turbojet` (physics/air/TurboProp.cpp, TurboJet.cpp) read and
// write, with upstream's names and types, without their sound and smoke.
#pragma once

#include "flex_airfoil.h"

namespace RigDef {
struct Turbojet {
    int is_reversable = 0;
    float dry_thrust = 0.f;
    float wet_thrust = 0.f;
    float front_diameter = 0.f;
    float back_diameter = 0.f;
    float nozzle_length = 0.f;
};
} // namespace RigDef

namespace RoR {
using ActorPtr = Actor *;
enum class AeroEngineKind { AE_XPROP, AE_TURBOJET };

class Turboprop {
public:
    void updateForces(float dt, int doUpdate);
    void setThrottle(float val);
    void reset();
    void toggleReverse();
    void flipStart();
    bool is_piston = false;
    float pitch = 0;
    float indicated_torque = 0;
    float max_torque = 0;
    float torquedist = 0;
    Airfoil *airfoil = nullptr;
    float fullpower = 0;
    float proparea = 0;
    float airdensity = 0;
    float timer = 0;
    float lastflip = 0;
    float warmupstart = 0;
    float warmuptime = 0;
    int numblades = 0;
    float bladewidth = 0;
    float pitchspeed = 0;
    float maxrevpitch = 0;
    float regspeed = 0;
    float twistmap[5];
    double rotenergy = 0;
    float fixed_pitch = 0;
    bool reverse = false, warmup = false, ignition = false;
    float radius = 0;
    bool failed = false, failedold = false;
    float rpm = 0, throtle = 0, propwash = 0;
    Ogre::Vector3 axis;
    int mod_id = 0, src_id = 0, thr_id = 0;
    ActorPtr m_actor = nullptr;
    int nodeback = 0, noderef = 0;
    int nodep[4];
    int torquenode = -1;
};

class Turbojet {
public:
    Turbojet(ActorPtr actor, int tnodefront, int tnodeback, int tnoderef, RigDef::Turbojet &def);
    void flipStart();
    void reset();
    void setThrottle(float val);
    void toggleReverse();
    void updateForces(float dt, int doUpdate);
    void setRPM(float _rpm);
    bool tjet_afterburnable = false;
    Ogre::Vector3 m_axis;
    bool m_afterburner_active = false, m_is_failed = false, m_ignition = false, m_reversable = false, m_reverse = false;
    bool m_warmup = false;
    float m_afterburn_thrust = 0, m_area = 0, m_exhaust_velocity = 0, m_last_flip = 0, m_max_dry_thrust = 0;
    float m_propwash = 0, m_radius = 0, m_reflen = 0, m_rpm_percent = 0, m_throtle = 0, m_timer = 0;
    float m_warmup_start = 0, m_warmup_time = 0;
    int m_sound_ab = 0, m_sound_mod = 0, m_sound_src = 0, m_sound_thr = 0;
    ActorPtr m_actor = nullptr;
    int m_node_back = 0, m_node_front = 0, m_node_ref = 0;
};
} // namespace RoR
