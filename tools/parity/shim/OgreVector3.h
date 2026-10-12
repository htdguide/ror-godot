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
#include <limits>

namespace Ogre {

using Real = float;

struct Quaternion;

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

    // OgreVector.h's `getRotationTo` (Sam Hocevar's "quaternion from two vectors"), with the
    // default zero fallback axis; `Quaternion` is below.
    Quaternion getRotationTo(const Vector3 &dest) const;

    Vector3 operator+(const Vector3 &o) const { return Vector3(x + o.x, y + o.y, z + o.z); }
    Vector3 operator-(const Vector3 &o) const { return Vector3(x - o.x, y - o.y, z - o.z); }
    Vector3 operator*(float s) const { return Vector3(x * s, y * s, z * s); }
    Vector3 operator-() const { return Vector3(-x, -y, -z); }
    Vector3 &operator+=(const Vector3 &o) { x += o.x; y += o.y; z += o.z; return *this; }
    Vector3 &operator-=(const Vector3 &o) { x -= o.x; y -= o.y; z -= o.z; return *this; }
    Vector3 &operator*=(float s) { x *= s; y *= s; z *= s; return *this; }
    // OgreVector.h 1.11: `Real fInv = 1.0f / s; return fInv * *this;` and the same in place.
    Vector3 &operator/=(float s) {
        const float fInv = 1.0f / s;
        x *= fInv;
        y *= fInv;
        z *= fInv;
        return *this;
    }
    Vector3 operator/(float s) const {
        const float fInv = 1.0f / s;
        return Vector3(fInv * x, fInv * y, fInv * z);
    }
};

inline Vector3 operator*(float s, const Vector3 &v) { return v * s; }

// OgreMath.h's `Degree`, as `FlexAirfoil::updateForces` reads one.
struct Degree {
    float mDeg = 0.0f;
    Degree() = default;
    explicit Degree(float d) : mDeg(d) {}
    float valueDegrees() const { return mDeg; }
    // `Math::DegreesToRadians`: `fDeg2Rad = PI / Real(180.0)`.
    float valueRadians() const {
        static const float PI = float(4.0 * std::atan(1.0));
        static const float fDeg2Rad = PI / float(180.0);
        return mDeg * fDeg2Rad;
    }
};

// OgreQuaternion.h/.cpp: the constructor, `normalise` and `ToAngleAxis`.
struct Quaternion {
    float w = 1.0f, x = 0.0f, y = 0.0f, z = 0.0f;
    Quaternion() = default;
    Quaternion(float fW, float fX, float fY, float fZ) : w(fW), x(fX), y(fY), z(fZ) {}
    // `Quaternion(const Radian&, const Vector3&)` from a Degree: `FromAngleAxis`, the half angle
    // `0.5 * Radian` (a Real), `Math::Sin` and `Math::Cos` of it.
    Quaternion(const Degree &angle, const Vector3 &axis) {
        const float radians = angle.valueRadians();
        const float half = float(0.5) * radians;
        const float fSin = std::sin(half);
        w = std::cos(half);
        x = fSin * axis.x;
        y = fSin * axis.y;
        z = fSin * axis.z;
    }
    // `Quaternion::operator*(const Vector3&)`, the nVidia SDK implementation.
    Vector3 operator*(const Vector3 &v) const {
        Vector3 qvec(x, y, z);
        Vector3 uv = qvec.crossProduct(v);
        Vector3 uuv = qvec.crossProduct(uv);
        uv *= (2.0f * w);
        uuv *= 2.0f;
        return v + uv + uuv;
    }
    float Norm() const { return std::sqrt(w * w + x * x + y * y + z * z); }
    float normalise() {
        const float len = Norm();
        const float s = 1.0f / len;
        w *= s;
        x *= s;
        y *= s;
        z *= s;
        return len;
    }
    // `ToAngleAxis(Radian&, Vector3&)` with `Math::ACos`, and the `Degree&` overload's conversion
    // (`Math::RadiansToDegrees`, `fRad2Deg = Real(180.0) / PI`).
    void ToAngleAxis(Degree &angle, Vector3 &axis) const {
        static const float PI = float(4.0 * std::atan(1.0));
        float radians = 0.0f;
        const float fSqrLength = x * x + y * y + z * z;
        if (fSqrLength > 0.0) {
            const float acos_w = (-1.0 < w) ? (w < 1.0 ? std::acos(w) : 0.0f) : PI;
            radians = float(2.0) * acos_w;
            const float fInvLength = float(1.) / std::sqrt(fSqrLength);
            axis.x = x * fInvLength;
            axis.y = y * fInvLength;
            axis.z = z * fInvLength;
        } else {
            axis = Vector3(1.0f, 0.0f, 0.0f);
        }
        static const float fRad2Deg = float(180.0) / PI;
        angle.mDeg = radians * fRad2Deg;
    }
};

inline Quaternion Vector3::getRotationTo(const Vector3 &dest) const {
    float a = std::sqrt(squaredLength() * dest.squaredLength());
    float b = a + dest.dotProduct(*this);
    if (std::abs(2 * a - b) <= std::numeric_limits<float>::epsilon() || a == 0) {
        return Quaternion();
    }
    Vector3 axis;
    if (b < (float)1e-06 * a) {
        b = (float)0.0;
        axis = std::abs(x) > std::abs(z) ? Vector3(-y, x, (float)0.0) : Vector3((float)0.0, -z, y);
    } else {
        axis = crossProduct(dest);
    }
    Quaternion q(b, axis.x, axis.y, axis.z);
    q.normalise();
    return q;
}

// OgrePlane.h: the constructors (the three-point one by `Math::calculateBasicFaceNormal`) and
// `projectVector`.
struct Plane {
    Vector3 normal;
    float d = 0.0f;
    Plane(const Vector3 &n, const Vector3 &point) : normal(n), d(-n.dotProduct(point)) {}
    Plane(const Vector3 &rkNormal, float fConstant) : normal(rkNormal), d(-fConstant) {}
    Plane(const Vector3 &p0, const Vector3 &p1, const Vector3 &p2) {
        normal = (p1 - p0).crossProduct(p2 - p0);
        normal.normalise();
        d = -normal.dotProduct(p0);
    }
    Vector3 projectVector(const Vector3 &v) const {
        const float m00 = 1.0f - normal.x * normal.x, m01 = -normal.x * normal.y, m02 = -normal.x * normal.z;
        const float m10 = -normal.y * normal.x, m11 = 1.0f - normal.y * normal.y, m12 = -normal.y * normal.z;
        const float m20 = -normal.z * normal.x, m21 = -normal.z * normal.y, m22 = 1.0f - normal.z * normal.z;
        return Vector3(m00 * v.x + m01 * v.y + m02 * v.z, m10 * v.x + m11 * v.y + m12 * v.z,
                       m20 * v.x + m21 * v.y + m22 * v.z);
    }
};

} // namespace Ogre
