// The fields of Rigs of Rods' node and ground model that its contact law reads and writes.
//
// `node_t` upstream is 200 bytes of simulation, rendering and gameplay state. The contact law
// touches nine fields of it. Declaring those nine, rather than including SimData.h and with it
// half the game, is what lets upstream's own function be compiled and called.
//
// The names and types are upstream's. A rename there breaks this build, which is the point.
#pragma once

#include "OgreVector3.h"

struct node_t {
    Ogre::Vector3 Forces;
    Ogre::Real friction_coef = 1.0f;
    Ogre::Real surface_coef = 1.0f;
    Ogre::Real volume_coef = 1.0f;
    float nd_avg_collision_slip = 0.0f;
    Ogre::Vector3 nd_last_collision_slip;
    Ogre::Vector3 nd_last_collision_force;
};

// Upstream's ground_model_t, reduced to the fields the contact law reads. The defaults are
// its `concrete` entry from resources/skeleton/config/ground_models.cfg.
struct ground_model_t {
    float va = 3.0f;
    float ms = 1.2f;
    float mc = 0.75f;
    float t2 = 0.01f;
    float vs = 6.0f;
    float alpha = 2.0f;
    float strength = 1.0f;
    float fluid_density = 0.0f;
    float flow_consistency_index = 0.0f;
    float flow_behavior_index = 1.0f;
    float solid_ground_level = 0.0f;
    float drag_anisotropy = 1.0f;
};

static const float DEFAULT_GRAVITY = -9.807f;
