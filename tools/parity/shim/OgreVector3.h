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
    static const Vector3 UNIT_Y;

    float dotProduct(const Vector3 &other) const { return x * other.x + y * other.y + z * other.z; }
    float squaredLength() const { return x * x + y * y + z * z; }
    float length() const { return std::sqrt(squaredLength()); }

    // Ogre 1.11's `normalise()` (OgreVector.h, the version upstream builds with): in place, by the
    // inverse length, only when the length is above zero, returning the length it had.
    float normalise() {
        const float len = length();
        if (len > 0.0f) {
            const float inv = 1.0f / len;
            x *= inv;
            y *= inv;
            z *= inv;
        }
        return len;
    }
    Vector3 normalisedCopy() const {
        Vector3 ret = *this;
        ret.normalise();
        return ret;
    }
    Vector3 crossProduct(const Vector3 &v) const {
        return Vector3(y * v.z - z * v.y, z * v.x - x * v.z, x * v.y - y * v.x);
    }
    Vector3 midPoint(const Vector3 &v) const {
        return Vector3((x + v.x) * 0.5f, (y + v.y) * 0.5f, (z + v.z) * 0.5f);
    }
    bool isZeroLength() const { return squaredLength() < 1e-06 * 1e-06; }

    // OgreVector.h's `getRotationTo` (Sam Hocevar's "quaternion from two vectors"), reduced to the
    // `w` of the normalised result, which is all `CalcFuseDrag` reads.
    struct RotationW {
        float w;
    };
    RotationW getRotationTo(const Vector3 &dest) const {
        const float a = std::sqrt(squaredLength() * dest.squaredLength());
        float b = a + dest.dotProduct(*this);
        if (std::fabs(b - 2 * a) <= 1.192092896e-07f || a == 0) {
            return {1.0f};
        }
        Vector3 axis;
        if (b < 1e-06f * a) {
            b = 0.0f;
            axis = std::fabs(x) > std::fabs(z) ? Vector3(-y, x, 0.0f) : Vector3(0.0f, -z, y);
        } else {
            axis = crossProduct(dest);
        }
        const float len = std::sqrt(b * b + axis.x * axis.x + axis.y * axis.y + axis.z * axis.z);
        return {len > 0.0f ? b * (1.0f / len) : b};
    }

    Vector3 operator+(const Vector3 &o) const { return Vector3(x + o.x, y + o.y, z + o.z); }
    Vector3 operator-(const Vector3 &o) const { return Vector3(x - o.x, y - o.y, z - o.z); }
    Vector3 operator*(float s) const { return Vector3(x * s, y * s, z * s); }
    Vector3 operator-() const { return Vector3(-x, -y, -z); }
    Vector3 &operator+=(const Vector3 &o) { x += o.x; y += o.y; z += o.z; return *this; }
    Vector3 &operator-=(const Vector3 &o) { x -= o.x; y -= o.y; z -= o.z; return *this; }
    Vector3 &operator*=(float s) { x *= s; y *= s; z *= s; return *this; }
    Vector3 &operator/=(float s) { x /= s; y /= s; z /= s; return *this; }
    Vector3 operator/(float s) const { return Vector3(x / s, y / s, z / s); }
};

inline Vector3 operator*(float s, const Vector3 &v) { return v * s; }

// OgrePlane.h, the constructor and `projectVector` upstream's `CalcWheels` uses.
struct Plane {
    Vector3 normal;
    float d = 0.0f;
    Plane(const Vector3 &n, const Vector3 &point) : normal(n), d(-n.dotProduct(point)) {}
    Vector3 projectVector(const Vector3 &v) const {
        const float m00 = 1.0f - normal.x * normal.x, m01 = -normal.x * normal.y, m02 = -normal.x * normal.z;
        const float m10 = -normal.y * normal.x, m11 = 1.0f - normal.y * normal.y, m12 = -normal.y * normal.z;
        const float m20 = -normal.z * normal.x, m21 = -normal.z * normal.y, m22 = 1.0f - normal.z * normal.z;
        return Vector3(m00 * v.x + m01 * v.y + m02 * v.z, m10 * v.x + m11 * v.y + m12 * v.z,
                       m20 * v.x + m21 * v.y + m22 * v.z);
    }
};

} // namespace Ogre
