// The parity oracle's wing mode (see oracle.cpp): upstream's `Airfoil` and the physics of its
// `FlexAirfoil` on a wing a gate describes.
#include "flex_airfoil.h"

#include <cstdio>
#include <sstream>
#include <string>
#include <vector>

// `wing afl type chordratio mindef maxdef liftcoef breakable induced span area left wash_ratio
// propwash axis_x axis_y axis_z n_steps` (a wash ratio of 0 is none), the
// eight nodes' starting positions (front-left-down, front-right-down, front-left-up,
// front-right-up, then the back four), then per step the control value, the eight positions and
// the two front-down nodes' velocities. `afl` is a file path, or "-" for none. The constructor's
// physics, which shares its function with the mesh, is upstream's lines transcribed. Prints per
// step every node's force, the angle of attack and whether it has broken.
bool run_wing(const std::string &line) {
    std::istringstream in(line.substr(4));
    std::string afl, type;
    float chordratio = 0, mindef = 0, maxdef = 0, liftcoef = 0, span = 0, area = 0;
    int breakable = 0, induced = 0, left = 0, n_steps = 0;
    float wash_ratio = 0;
    AeroEngine engine;
    if (!(in >> afl >> type >> chordratio >> mindef >> maxdef >> liftcoef >> breakable >> induced >> span >> area >> left >>
          wash_ratio >> engine.propwash >> engine.axis.x >> engine.axis.y >> engine.axis.z >> n_steps)) {
        return false;
    }
    std::vector<node_t> nodes(8);
    for (node_t &n : nodes) {
        in >> n.RelPosition.x >> n.RelPosition.y >> n.RelPosition.z;
        n.AbsPosition = n.RelPosition;
    }
    RoR::FlexAirfoil fa;
    fa.nfld = 0, fa.nfrd = 1, fa.nflu = 2, fa.nfru = 3, fa.nbld = 4, fa.nbrd = 5, fa.nblu = 6, fa.nbru = 7;
    fa.nodes = nodes.data();
    fa.liftcoef = liftcoef;
    fa.breakable = breakable != 0;
    fa.mindef = mindef;
    fa.maxdef = maxdef;
    RoR::Airfoil airfoil(afl == "-" ? std::string() : afl);
    fa.airfoil = &airfoil;
    const char mtype = type[0];
    fa.type = mtype;
    // FlexAirfoil's constructor, its physics.
    fa.hascontrol = (mtype != 'n' && mtype != 'S' && mtype != 'T' && mtype != 'U' && mtype != 'V');
    fa.isstabilator = (mtype == 'S' || mtype == 'T' || mtype == 'U' || mtype == 'V');
    fa.deflection = 0.0;
    fa.chordratio = chordratio;
    float tsref = 2.0 * (nodes[fa.nfrd].RelPosition - nodes[fa.nfld].RelPosition).crossProduct(nodes[fa.nbld].RelPosition - nodes[fa.nfld].RelPosition).length();
    fa.sref = 2.0 * (nodes[fa.nfrd].RelPosition - nodes[fa.nfld].RelPosition).crossProduct(nodes[fa.nbrd].RelPosition - nodes[fa.nfrd].RelPosition).length();
    if (tsref > fa.sref) fa.sref = tsref;
    fa.sref = fa.sref * fa.sref;
    fa.lratio = (nodes[fa.nfld].RelPosition - nodes[fa.nflu].RelPosition).length() / (nodes[fa.nfld].RelPosition - nodes[fa.nbld].RelPosition).length();
    fa.rratio = (nodes[fa.nfrd].RelPosition - nodes[fa.nfru].RelPosition).length() / (nodes[fa.nfrd].RelPosition - nodes[fa.nbrd].RelPosition).length();
    if (induced) {
        fa.enableInducedDrag(span, area, left != 0);
    }
    AeroEnginePtr engines[1];
    engines[0].p = &engine;
    fa.aeroengines = engines;
    if (wash_ratio > 0) {
        fa.washpropnum[0] = 0;
        fa.washpropratio[0] = wash_ratio;
        fa.free_wash = 1;
    }
    for (int step = 0; step < n_steps; ++step) {
        float control = 0;
        in >> control;
        for (node_t &n : nodes) {
            in >> n.RelPosition.x >> n.RelPosition.y >> n.RelPosition.z;
            n.AbsPosition = n.RelPosition;
            n.Forces = Ogre::Vector3(0, 0, 0);
            n.Velocity = Ogre::Vector3(0, 0, 0);
        }
        in >> nodes[0].Velocity.x >> nodes[0].Velocity.y >> nodes[0].Velocity.z;
        in >> nodes[1].Velocity.x >> nodes[1].Velocity.y >> nodes[1].Velocity.z;
        if (!in) {
            return false;
        }
        fa.setControlDeflection(control);
        fa.updateBroken();
        fa.updateForces();
        std::string out;
        char buffer[96];
        for (const node_t &n : nodes) {
            std::snprintf(buffer, sizeof buffer, "%.9g %.9g %.9g ", n.Forces.x, n.Forces.y, n.Forces.z);
            out += buffer;
        }
        std::snprintf(buffer, sizeof buffer, "| %.9g %d", fa.aoa, fa.broken ? 1 : 0);
        out += buffer;
        std::printf("%s\n", out.c_str());
    }
    return true;
}
