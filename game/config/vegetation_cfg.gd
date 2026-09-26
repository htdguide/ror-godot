class_name VegetationCfg
extends RefCounted
## What grows where, and how big. Tunables only — the meshes and the placement are in
## `world/valley_vegetation.gd`, and where the stand is belongs to the layout.
##
## This is vegetation tier 1 from PLAN §0.5's M2 staging: conifers and shrubs, generated rather
## than sourced, so the scene still needs no third-party asset. Tiers 2 and 3 — grass and the
## density the plan wants under a camera — arrive with the lit particle and GI work.

## The grid the placement walks, in metres. Every cell offers one candidate, which is then
## accepted or rejected by the rules below, so this sets the *densest* the valley can be and the
## per-species chance sets how much of that is taken.
const CELL_M: float = 6.0

## Species. `chance` is the share of candidate cells that become this species where it is allowed
## at all; `stand_chance` is that share inside the conifer stand.
const CONIFER: Dictionary = {
    "chance": 0.07,
    "stand_chance": 0.72,
    "height_m": 11.0,
    "height_spread": 0.45,
    "radius_m": 2.3,
    "trunk_radius_m": 0.22,
    "tiers": 3,
    "foliage": Color(0.10, 0.20, 0.11),
    "trunk": Color(0.12, 0.09, 0.07),
}
const SHRUB: Dictionary = {
    "chance": 0.16,
    "stand_chance": 0.12,
    "height_m": 1.3,
    "height_spread": 0.4,
    "radius_m": 1.1,
    "foliage": Color(0.19, 0.26, 0.13),
}

## Where anything may grow at all.
##
## Nothing grows on the test track: the driving gates spawn there, and a tree standing in a lane
## is a tree standing in the middle of the measurement. Nothing grows in water, on the road, on
## the rock shelf, or on ground steeper than a tree can hold.
const MIN_ABS_Z_M: float = 150.0
## Over how much of the ground past that the density ramps up. Without it the forest has a
## drawn edge along the whole valley, which is what a rule applied as a hard cut looks like from
## the ridge.
const EDGE_FADE_M: float = 55.0
const MAX_SLOPE: float = 0.55
## How far from the road's centre line the ground stays clear. Wider than the corridor, so the
## road has a verge rather than a wall of trunks at its edge.
const ROAD_CLEARANCE_M: float = 14.0
## How far above the lake's surface the ground has to be. Trees do not grow in the shallows.
const SHORE_CLEARANCE_M: float = 0.6

## Which surfaces will carry vegetation. Rock and grass are the wall and the ridge; the lanes on
## the valley floor are the test track and are excluded by MIN_ABS_Z_M anyway.
const SURFACES: Array[String] = ["grass", "rock"]
## Conifers stop at the altitude where the wall turns to bare rock, as a fraction of the wall's
## height. Below it they are everywhere; above it only shrubs.
const TREE_LINE: float = 0.82

## Placement is deterministic and seedless: a hash of the cell's own coordinates, so the same
## valley grows the same forest on any machine and a gate can check an instance by recomputing it
## rather than by storing one.
const HASH_SALT: int = 0x9E3779B9

## Instances are drawn as one multimesh per species. Trees cast shadows — `switchback_backlit` is
## a shot of tree shadows — and shrubs do not, because a shrub's shadow costs the same as a
## tree's and is worth far less.
const CONIFER_CASTS_SHADOW: bool = true
const SHRUB_CASTS_SHADOW: bool = false
## Beyond this distance a species stops drawing. The valley is 2 km and a shrub is a metre.
const CONIFER_VISIBLE_M: float = 900.0
const SHRUB_VISIBLE_M: float = 260.0
