// What upstream's SlideNode.h takes from ForwardDeclarations.h: node_t and beam_t, which the other
// shims declare, and the assertion macro its constructor uses.
#pragma once

#include <cassert>
#include <cmath>
#include <limits>

struct node_t;
struct beam_t;

#define ROR_ASSERT(expr) assert(expr)
