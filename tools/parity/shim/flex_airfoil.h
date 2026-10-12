// What upstream's `Airfoil` (physics/air/Airfoil.cpp) and the physics of its `FlexAirfoil`
// (physics/flex/FlexAirfoil.cpp) read, with upstream's names: Ogre's resource manager reduced to
// reading a file by name, and FlexAirfoil's members without its mesh.
#pragma once

#include "actor_shocks.h"

#include <cstring>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>

namespace Ogre {
// `DataStream::readLine`: up to the newline, which is dropped, as is a carriage return before it.
struct DataStream {
    std::istringstream in;
    bool eof() { return in.eof() || in.peek() == EOF; }
    size_t readLine(char *buf, size_t maxCount) {
        std::string line;
        std::getline(in, line);
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        line = line.substr(0, maxCount);
        std::memcpy(buf, line.c_str(), line.size() + 1);
        return line.size();
    }
};
using DataStreamPtr = std::shared_ptr<DataStream>;
// `ResourceGroupManager`, finding a file by its path.
struct ResourceGroupManager {
    static ResourceGroupManager &getSingleton() {
        static ResourceGroupManager m;
        return m;
    }
    String findGroupContainingResource(const String &name) {
        std::ifstream f(name);
        if (!f) {
            throw 1;
        }
        return "files";
    }
    DataStreamPtr openResource(const String &name, const String &) {
        auto ds = std::make_shared<DataStream>();
        std::ifstream f(name);
        std::stringstream all;
        all << f.rdbuf();
        ds->in.str(all.str());
        return ds;
    }
};
} // namespace Ogre

namespace RoR {
class Airfoil {
public:
    Airfoil(Ogre::String const &fname);
    ~Airfoil() {}
    void getparams(float a, float cratio, float cdef, float *ocl, float *ocd, float *ocm);

private:
    float cl[3601];
    float cd[3601];
    float cm[3601];
};

static const int MAX_AEROENGINES = 16;
class FlexAirfoil {
public:
    void setControlDeflection(float val);
    void enableInducedDrag(float span, float area, bool l);
    void updateForces();
    // `updateVerticesPhysics`' break test, its two lines lifted into a function of their own.
    void updateBroken();
    float aoa = 0;
    char type = 'n';
    int nfld = 0, nfrd = 0, nflu = 0, nfru = 0, nbld = 0, nbrd = 0, nblu = 0, nbru = 0;
    bool broken = false;
    bool breakable = true;
    float liftcoef = 1;
    node_t *nodes = nullptr;
    float sref = 0, deflection = 0, chordratio = 0;
    bool hascontrol = false, isstabilator = false;
    float lratio = 0, rratio = 0, mindef = 0, maxdef = 0;
    bool useInducedDrag = false;
    float idSpan = 0, idArea = 0;
    bool idLeft = false;
    Airfoil *airfoil = nullptr;
    AeroEnginePtr *aeroengines = nullptr;
    int free_wash = 0;
    int washpropnum[MAX_AEROENGINES];
    float washpropratio[MAX_AEROENGINES];
};
} // namespace RoR
