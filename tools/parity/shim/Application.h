// Stub for Rigs of Rods' Application.h, so that its physics headers can be compiled on
// their own.
//
// ApproxMath.h includes Application.h and uses nothing from it. Application.h in turn pulls
// in the whole game — the console, the script engine, the GUI manager — so compiling it is
// not an option and is not necessary. This satisfies the include and nothing else.
//
// If upstream ever makes ApproxMath.h actually depend on Application.h, this stub stops
// compiling, which is the correct outcome: it would mean the extraction is no longer honest.
#pragma once
