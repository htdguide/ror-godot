// The part of Ogre::Vector3 that Rigs of Rods' contact law uses.
//
// Upstream's physics is written against Ogre's vector type. Compiling its code unmodified
// therefore needs that type — but not Ogre, which is a renderer. This is the API surface the
// extracted functions call, and nothing more, so that what is being compiled is upstream's
// arithmetic rather than a translation of it.
//
// Every operation here is the plain IEEE float expression Ogre uses. The approximations that
// matter are in ApproxMath.h and are compiled from upstream's own header.
#pragma once

#include <cmath>

namespace Ogre {

using Real = float;

struct Vector3 {
    float x = 0.0f, y = 0.0f, z = 0.0f;

    Vector3() = default;
    Vector3(float in_x, float in_y, float in_z) : x(in_x), y(in_y), z(in_z) {}

    static const Vector3 ZERO;

    float dotProduct(const Vector3 &other) const { return x * other.x + y * other.y + z * other.z; }
    float squaredLength() const { return x * x + y * y + z * z; }
    float length() const { return std::sqrt(squaredLength()); }

    // Ogre's normalise() is in place and returns the length it had. Code that relies on both
    // halves of that is why this cannot be a free function returning a normalised copy.
    float normalise() {
        const float len = length();
        if (len > 1e-08f) {
            x /= len;
            y /= len;
            z /= len;
        }
        return len;
    }

    Vector3 operator+(const Vector3 &o) const { return Vector3(x + o.x, y + o.y, z + o.z); }
    Vector3 operator-(const Vector3 &o) const { return Vector3(x - o.x, y - o.y, z - o.z); }
    Vector3 operator*(float s) const { return Vector3(x * s, y * s, z * s); }
    Vector3 operator-() const { return Vector3(-x, -y, -z); }
    Vector3 &operator+=(const Vector3 &o) { x += o.x; y += o.y; z += o.z; return *this; }
};

inline Vector3 operator*(float s, const Vector3 &v) { return v * s; }

} // namespace Ogre
