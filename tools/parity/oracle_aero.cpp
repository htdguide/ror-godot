// The parity oracle's aero engine mode (see oracle.cpp): upstream's `Turboprop` and `Turbojet` on
// an engine a gate describes.
#include "aero_engines.h"
#include "autopilot.h"

#include <cstdio>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

// `aero prop n_nodes ref back p1 p2 p3 p4 couple power piston pitch afl n_steps`, or
// `aero jet n_nodes front back side reversable dry wet back_diameter start_rpm n_steps`, then every node's
// position and mass, then per step "throttle reverse start do_update" and every node's position
// and velocity. A node of -1 is none; `afl` a path or "-". The turboprop's constructor, which also
// builds its smoke, is upstream's physics lines transcribed; the turbojet's is upstream's own.
// Prints per step every node's force, then the rpm, the prop wash, the pitch (0 for a jet), and
// whether it has failed and has ignition.
bool run_aero(const std::string &line) {
    std::istringstream in(line.substr(5));
    std::string kind;
    int n_nodes = 0;
    in >> kind >> n_nodes;
    int ids[7] = {-1, -1, -1, -1, -1, -1, -1};
    float power = 0, pitch = 0, dry = 0, wet = 0, diameter = 0, start_rpm = 0;
    int piston = 0, reversable = 0, n_steps = 0;
    std::string afl;
    if (kind == "prop") {
        for (int &id : ids) {
            in >> id;
        }
        in >> power >> piston >> pitch >> afl >> n_steps;
    } else {
        in >> ids[0] >> ids[1] >> ids[2] >> reversable >> dry >> wet >> diameter >> start_rpm >> n_steps;
    }
    std::vector<node_t> nodes(static_cast<size_t>(n_nodes));
    for (node_t &n : nodes) {
        in >> n.RelPosition.x >> n.RelPosition.y >> n.RelPosition.z >> n.mass;
        n.AbsPosition = n.RelPosition;
    }
    if (!in) {
        return false;
    }
    RoR::Actor actor;
    actor.ar_nodes = nodes.data();
    std::unique_ptr<RoR::Turboprop> prop;
    std::unique_ptr<RoR::Turbojet> jet;
    std::unique_ptr<RoR::Airfoil> airfoil;
    if (kind == "prop") {
        prop = std::make_unique<RoR::Turboprop>();
        RoR::Turboprop &t = *prop;
        t.m_actor = &actor;
        const int nr = ids[0], nb = ids[1], np1 = ids[2], np2 = ids[3], np3 = ids[4], np4 = ids[5], tqn = ids[6];
        // Turboprop's constructor, its physics.
        t.is_piston = piston != 0;
        t.fixed_pitch = pitch;
        t.torquenode = tqn;
        t.rotenergy = 0;
        t.pitchspeed = 5.0;
        t.numblades = 4;
        t.twistmap[0] = 2;
        t.twistmap[1] = 6;
        t.twistmap[2] = 10;
        t.twistmap[3] = 19;
        t.twistmap[4] = 32;
        t.noderef = nr;
        t.nodeback = nb;
        t.nodep[0] = np1;
        t.nodep[1] = np2;
        if (t.torquenode != -1) {
            Ogre::Plane pplane = Ogre::Plane((nodes[nr].RelPosition - nodes[nb].RelPosition).normalisedCopy(), 0.0);
            Ogre::Vector3 apos = pplane.projectVector(nodes[nr].RelPosition);
            Ogre::Vector3 tpos = pplane.projectVector(nodes[tqn].RelPosition);
            t.torquedist = (apos - tpos).length();
        } else {
            t.torquedist = 1.0;
        }
        if (np3 == -1) {
            t.numblades = 2;
        } else {
            t.nodep[2] = np3;
            if (np4 == -1) {
                t.numblades = 3;
            } else {
                t.nodep[3] = np4;
            }
        }
        t.propwash = 0;
        t.timer = 0;
        t.lastflip = 0;
        t.warmupstart = 0.0;
        t.warmuptime = 14.0;
        t.warmup = false;
        airfoil = std::make_unique<RoR::Airfoil>(afl == "-" ? std::string() : afl);
        t.airfoil = airfoil.get();
        t.fullpower = power;
        t.max_torque = 9549.3 * t.fullpower / 1000.0;
        t.indicated_torque = 0.0;
        t.radius = (nodes[t.noderef].RelPosition - nodes[t.nodep[0]].RelPosition).length();
        t.bladewidth = 0.4;
        t.proparea = 3.14159 * t.radius * t.radius;
        t.airdensity = 1.225;
        t.regspeed = 1010;
        t.maxrevpitch = -5.0;
        t.reset();
    } else {
        RigDef::Turbojet def;
        def.is_reversable = reversable;
        def.dry_thrust = dry;
        def.wet_thrust = wet;
        def.back_diameter = diameter;
        jet = std::make_unique<RoR::Turbojet>(&actor, ids[0], ids[1], ids[2], def);
        jet->setRPM(start_rpm);
    }
    for (int step = 0; step < n_steps; ++step) {
        float throttle = 0;
        int reverse = 0, start = 0, do_update = 0;
        in >> throttle >> reverse >> start >> do_update;
        for (node_t &n : nodes) {
            in >> n.RelPosition.x >> n.RelPosition.y >> n.RelPosition.z >> n.Velocity.x >> n.Velocity.y >> n.Velocity.z;
            n.AbsPosition = n.RelPosition;
            n.Forces = Ogre::Vector3(0, 0, 0);
        }
        if (!in) {
            return false;
        }
        std::string out;
        char buffer[160];
        if (prop) {
            if (reverse) prop->toggleReverse();
            if (start) prop->flipStart();
            prop->setThrottle(throttle);
            prop->updateForces(0.0005f, do_update);
        } else {
            if (reverse) jet->toggleReverse();
            if (start) jet->flipStart();
            jet->setThrottle(throttle);
            jet->updateForces(0.0005f, do_update);
        }
        for (const node_t &n : nodes) {
            std::snprintf(buffer, sizeof buffer, "%.9g %.9g %.9g ", n.Forces.x, n.Forces.y, n.Forces.z);
            out += buffer;
        }
        if (prop) {
            std::snprintf(buffer, sizeof buffer, "| %.9g %.9g %.9g %d %d", prop->rpm, prop->propwash, prop->pitch,
                          prop->failed ? 1 : 0, prop->ignition ? 1 : 0);
        } else {
            std::snprintf(buffer, sizeof buffer, "| %.9g %.9g %.9g %d %d", jet->m_rpm_percent, jet->m_propwash, 0.0,
                          jet->m_is_failed ? 1 : 0, jet->m_ignition ? 1 : 0);
        }
        out += buffer;
        std::printf("%s\n", out.c_str());
    }
    return true;
}

// `airbrake n_steps`, then "width length maxangle", then per step "intensity", node ref's height
// and velocity, and the four nodes' starting forces (ref, x, y, a). Upstream's `Airbrake` with its
// spawner's area and its `updatePosition` from `setAirbrakeIntensity`. Prints per step the four
// nodes' forces.
bool run_airbrake(const std::string &line) {
    std::istringstream in(line.substr(8));
    int n_steps = 0;
    float width = 0, length = 0, maxangle = 0;
    if (!(in >> n_steps >> width >> length >> maxangle)) {
        return false;
    }
    RoR::Airbrake ab;
    node_t nodes[4];
    ab.noderef = &nodes[0];
    ab.nodex = &nodes[1];
    ab.nodey = &nodes[2];
    ab.nodea = &nodes[3];
    ab.maxangle = maxangle;
    ab.area = width * length * 1.f;
    for (int step = 0; step < n_steps; ++step) {
        int intensity = 0;
        in >> intensity >> nodes[0].AbsPosition.y >> nodes[0].Velocity.x >> nodes[0].Velocity.y >> nodes[0].Velocity.z;
        for (int k = 0; k < 4; ++k) {
            in >> nodes[k].Forces.x >> nodes[k].Forces.y >> nodes[k].Forces.z;
        }
        if (!in) {
            return false;
        }
        ab.ratio = (float)intensity / 5.0;
        ab.applyForce();
        std::string out;
        char buffer[96];
        for (int k = 0; k < 4; ++k) {
            std::snprintf(buffer, sizeof buffer, "%.9g %.9g %.9g ", nodes[k].Forces.x, nodes[k].Forces.y, nodes[k].Forces.z);
            out += buffer;
        }
        std::printf("%s\n", out.c_str());
    }
    return true;
}

// `autopilot n_steps`, then left, right and back nodes' starting positions; per step an action
// (0 none, 1-4 heading mode none/fixed/wlv/nav toggle, 5-6 alt fixed/vs toggle, 7 ias toggle,
// 8-11 adj hdg/alt/vs/ias by value) and its value, each node's height and velocity, then a throttle
// and dt. Upstream's `Autopilot` as reset, references set as the wings close. Prints per step the
// aileron, elevator and throttle it asks for and its heading, alt, vs and ias.
bool run_autopilot(const std::string &line) {
    std::istringstream in(line.substr(9));
    int n_steps = 0;
    if (!(in >> n_steps)) {
        return false;
    }
    node_t nodes[3];
    for (int k = 0; k < 3; ++k) {
        in >> nodes[k].RelPosition.x >> nodes[k].RelPosition.y >> nodes[k].RelPosition.z;
        nodes[k].AbsPosition = nodes[k].RelPosition;
    }
    RoR::Autopilot ap;
    ap.setInertialReferences(&nodes[0], &nodes[1], &nodes[2], &nodes[0]);
    for (int step = 0; step < n_steps; ++step) {
        int action = 0, value = 0;
        in >> action >> value;
        for (int k = 0; k < 3; ++k) {
            in >> nodes[k].RelPosition.y >> nodes[k].Velocity.x >> nodes[k].Velocity.y >> nodes[k].Velocity.z;
            nodes[k].AbsPosition.y = nodes[k].RelPosition.y;
        }
        float thrtl = 0, dt = 0;
        in >> thrtl >> dt;
        if (!in) {
            return false;
        }
        switch (action) {
            case 2: ap.toggleHeading(RoR::Autopilot::HEADING_FIXED); break;
            case 3: ap.toggleHeading(RoR::Autopilot::HEADING_WLV); break;
            case 4: ap.toggleHeading(RoR::Autopilot::HEADING_NAV); break;
            case 5: ap.toggleAlt(RoR::Autopilot::ALT_FIXED); break;
            case 6: ap.toggleAlt(RoR::Autopilot::ALT_VS); break;
            case 7: ap.toggleIAS(); break;
            case 8: ap.adjHDG(value); break;
            case 9: ap.adjALT(value); break;
            case 10: ap.adjVS(value); break;
            case 11: ap.adjIAS(value); break;
            default: break;
        }
        const float aileron = ap.getAilerons();
        const float elevator = ap.getElevator();
        const float throttle = ap.getThrottle(thrtl, dt);
        std::printf("%.9g %.9g %.9g %d %d %d %d\n", aileron, elevator, throttle, ap.heading, ap.alt, ap.vs, ap.ias);
    }
    return true;
}
