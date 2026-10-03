#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <utility>
#include <vector>

namespace rorgd {

// Reads OGRE .mesh binary files without OGRE.
//
// The community library is full of these and they are the geometry half of every
// flexbodies vehicle, so the shim cannot load a mod without this. Written fresh rather
// than pulled from OGRE because taking a dependency on OGRE 1.x is exactly what this
// project exists to escape.
//
// Chunked format: every chunk is a uint16 id followed by a uint32 length that includes
// the six header bytes. Unknown chunks are skipped by length, which is what makes the
// format forward compatible and what lets this reader ignore animation, edge lists and
// LOD data it has no use for.
class OgreMeshReader : public godot::RefCounted {
    GDCLASS(OgreMeshReader, godot::RefCounted)

protected:
    static void _bind_methods();

public:
    // Returns { error, version, shared_vertex_count, submeshes: [ { material,
    // positions, normals, uvs, indices } ] }. A non-empty "error" means nothing else in
    // the dictionary can be trusted.
    godot::Dictionary read_file(const godot::String &path);

private:
    struct Cursor {
        const uint8_t *data = nullptr;
        int64_t size = 0;
        int64_t at = 0;

        bool ok(int64_t need) const { return at + need <= size; }
        uint8_t u8();
        uint16_t u16();
        uint32_t u32();
        float f32();
        godot::String str();  // newline-terminated, as OGRE writes it
    };

    struct Geometry {
        godot::PackedVector3Array positions;
        godot::PackedVector3Array normals;
        godot::PackedVector2Array uvs;
    };

    godot::String m_error;

    bool read_mesh(Cursor &c, int64_t end, Geometry &shared, godot::Array &submeshes);
    // Where the next submesh really starts, found by its own shape rather than by the length
    // the chunk before it claims. -1 when there is none. See the note in `read_mesh`.
    int64_t next_submesh(const Cursor &c, int64_t from, int64_t limit) const;
    bool read_submesh(Cursor &c, int64_t end, godot::Array &submeshes);
    bool read_geometry(Cursor &c, int64_t end, Geometry &out);
};

} // namespace rorgd
