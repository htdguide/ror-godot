// The parity oracle's trigger mode (see oracle.cpp): upstream's `ProcessTrigger`, `CalcBeams` and
// `CalcTriggers` on triggers a gate describes.
#include "actor_shocks.h"
#include "spawner_trigger.h"

#include <cstdio>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

// `trigger n_nodes n_triggers n_steps`, the nodes' positions, then per trigger "a b contraction
// expansion short long options timer" (options "-" for none), then per step "hooks" and every
// node's position. Upstream's own `ProcessTrigger` builds them and its `CalcBeams` runs them, which
// calls its `CalcTriggers`; between steps, `CalcCommands`' line that turns a key's trigger input
// into its value. Prints per step every trigger's state, every key's value and block, the hook
// requests, the engine calls and the brake.
bool run_trigger(const std::string &line) {
    std::istringstream in(line.substr(7));
    int n_nodes = 0, n_triggers = 0, n_steps = 0;
    if (!(in >> n_nodes >> n_triggers >> n_steps)) {
        return false;
    }
    std::vector<node_t> nodes(static_cast<size_t>(n_nodes));
    for (node_t &n : nodes) {
        in >> n.RelPosition.x >> n.RelPosition.y >> n.RelPosition.z;
        n.AbsPosition = n.RelPosition;
    }
    for (int i = 0; i < n_nodes; ++i) {
        nodes[static_cast<size_t>(i)].pos = i;
    }
    RoR::Actor actor;
    actor.beams.resize(1024);
    std::vector<shock_t> shocks(1024);
    actor.ar_node_to_beam_connections.resize(static_cast<size_t>(n_nodes));
    actor.ar_beams = actor.beams.data();
    actor.ar_nodes = nodes.data();
    actor.ar_num_nodes = n_nodes;
    actor.ar_shocks = shocks.data();
    RoR::Actor::Engine engine;
    actor.ar_engine = &engine;
    RoR::ActorSpawner spawner;
    spawner.m_actor = &actor;
    auto defaults = std::make_shared<RigDef::BeamDefaults>();
    const std::string letters = "icxbBAshHtE";
    for (int t = 0; t < n_triggers; ++t) {
        RigDef::Trigger def;
        std::string options;
        in >> def.nodes[0] >> def.nodes[1] >> def.contraction_trigger_limit >> def.expansion_trigger_limit >>
                def.shortbound_trigger_action >> def.longbound_trigger_action >> options >> def.boundary_timer;
        // Upstream's `GetArgTriggerOptions`: one bit per letter, in RigDef's order.
        for (char c : options) {
            const size_t bit = letters.find(c);
            if (bit != std::string::npos) {
                def.options |= BITMASK(static_cast<int>(bit) + 1);
            }
        }
        def.beam_defaults = defaults;
        spawner.ProcessTrigger(def);
    }
    for (int b = 0; b < actor.ar_num_beams; ++b) {
        actor.ar_node_to_beam_connections[static_cast<size_t>(actor.ar_beams[b].p1 - nodes.data())].push_back(b);
        actor.ar_node_to_beam_connections[static_cast<size_t>(actor.ar_beams[b].p2 - nodes.data())].push_back(b);
    }
    for (int step = 0; step < n_steps; ++step) {
        int hooks = 0;
        in >> hooks;
        for (node_t &n : nodes) {
            in >> n.RelPosition.x >> n.RelPosition.y >> n.RelPosition.z;
            n.AbsPosition = n.RelPosition;
            n.Forces = Ogre::Vector3(0, 0, 0);
        }
        if (!in) {
            return false;
        }
        RoR::App::GetGameContext()->requests.clear();
        engine.calls.clear();
        actor.CalcBeams(hooks != 0);
        for (int i = 1; i <= MAX_COMMANDS; i++) {
            actor.ar_command_key[i].commandValue = std::max(actor.ar_command_key[i].playerInputValue,
                                                            actor.ar_command_key[i].triggerInputValue);
            actor.ar_command_key[i].triggerInputValue = 0.0f;
        }
        std::string out = "T";
        for (int b = 0; b < actor.ar_num_beams; ++b) {
            const shock_t &shock = *actor.ar_beams[b].shock;
            out += " " + std::to_string(shock.trigger_enabled ? 1 : 0) + "," + std::to_string(shock.trigger_cmdshort) + "," +
                   std::to_string(shock.trigger_cmdlong);
        }
        char buffer[64];
        out += " K";
        for (int i = 1; i <= MAX_COMMANDS; i++) {
            if (actor.ar_command_key[i].commandValue != 0.0f) {
                std::snprintf(buffer, sizeof buffer, " %d:%.9g", i, actor.ar_command_key[i].commandValue);
                out += buffer;
            }
        }
        out += " B";
        for (int i = -5; i <= MAX_COMMANDS; i++) {
            if (actor.ar_command_key[i].trigger_cmdkeyblock_state) {
                out += " " + std::to_string(i);
            }
        }
        out += " H";
        for (const std::string &r : RoR::App::GetGameContext()->requests) {
            out += " " + r;
        }
        out += " E";
        for (const std::string &c : engine.calls) {
            out += " " + c;
        }
        std::snprintf(buffer, sizeof buffer, " R %.9g", actor.ar_brake);
        out += buffer;
        std::printf("%s\n", out.c_str());
    }
    return true;
}

