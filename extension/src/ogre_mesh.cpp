#include "ogre_mesh.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <cstring>

using namespace godot;

namespace rorgd {

namespace {

// Chunk identifiers, from OGRE's MeshFileFormat.h.
constexpr uint16_t M_HEADER = 0x1000;
constexpr uint16_t M_MESH = 0x3000;
constexpr uint16_t M_SUBMESH = 0x4000;
constexpr uint16_t M_SUBMESH_OPERATION = 0x4010;
constexpr uint16_t M_SUBMESH_BONE_ASSIGNMENT = 0x4100;
constexpr uint16_t M_GEOMETRY = 0x5000;
constexpr uint16_t M_GEOMETRY_VERTEX_DECLARATION = 0x5100;
constexpr uint16_t M_GEOMETRY_VERTEX_ELEMENT = 0x5110;
constexpr uint16_t M_GEOMETRY_VERTEX_BUFFER = 0x5200;
constexpr uint16_t M_GEOMETRY_VERTEX_BUFFER_DATA = 0x5210;

// VertexElementSemantic.
constexpr uint16_t VES_POSITION = 1;
constexpr uint16_t VES_NORMAL = 4;
constexpr uint16_t VES_TEXTURE_COORDINATES = 7;

constexpr int CHUNK_HEADER_SIZE = 6;

struct VertexElement {
    uint16_t source = 0;
    uint16_t type = 0;
    uint16_t semantic = 0;
    uint16_t offset = 0;
    uint16_t index = 0;
};

// Byte width of a VertexElementType. Only the types that carry geometry are sized
// exactly; the rest need a width so that element offsets stay correct.
int element_size(uint16_t type) {
    switch (type) {
        case 0: return 4;    // FLOAT1
        case 1: return 8;    // FLOAT2
        case 2: return 12;   // FLOAT3
        case 3: return 16;   // FLOAT4
        case 4: return 4;    // COLOUR
        case 5: return 2;    // SHORT1
        case 6: return 4;    // SHORT2
        case 7: return 6;    // SHORT3
        case 8: return 8;    // SHORT4
        case 9: return 4;    // UBYTE4
        case 10: return 4;   // COLOUR_ARGB
        case 11: return 4;   // COLOUR_ABGR
        default: return 0;
    }
}

float read_float_at(const uint8_t *p) {
    float value = 0.0f;
    std::memcpy(&value, p, sizeof(float));
    return value;
}

} // namespace

uint8_t OgreMeshReader::Cursor::u8() {
    if (!ok(1)) { return 0; }
    return data[at++];
}

uint16_t OgreMeshReader::Cursor::u16() {
    if (!ok(2)) { at = size; return 0; }
    uint16_t v = 0;
    std::memcpy(&v, data + at, 2);
    at += 2;
    return v;
}

uint32_t OgreMeshReader::Cursor::u32() {
    if (!ok(4)) { at = size; return 0; }
    uint32_t v = 0;
    std::memcpy(&v, data + at, 4);
    at += 4;
    return v;
}

float OgreMeshReader::Cursor::f32() {
    if (!ok(4)) { at = size; return 0.0f; }
    float v = read_float_at(data + at);
    at += 4;
    return v;
}

// OGRE writes strings terminated by a newline rather than a NUL.
String OgreMeshReader::Cursor::str() {
    CharString buffer;
    String out;
    while (ok(1)) {
        char ch = static_cast<char>(data[at++]);
        if (ch == '\n') { break; }
        out += String::chr(ch);
    }
    return out;
}

void OgreMeshReader::_bind_methods() {
    ClassDB::bind_method(D_METHOD("read_file", "path"), &OgreMeshReader::read_file);
}

Dictionary OgreMeshReader::read_file(const String &path) {
    Dictionary result;
    m_error = String();

    Ref<FileAccess> file = FileAccess::open(path, FileAccess::READ);
    if (file.is_null()) {
        result["error"] = String("cannot open '") + path + String("'");
        return result;
    }
    PackedByteArray bytes = file->get_buffer(file->get_length());
    file->close();

    Cursor c{bytes.ptr(), bytes.size(), 0};
    if (c.u16() != M_HEADER) {
        result["error"] = String("'") + path + String("' is not an OGRE mesh: no header chunk");
        return result;
    }
    const String version = c.str();

    Geometry shared;
    Array submeshes;
    bool found_mesh = false;
    while (c.at + CHUNK_HEADER_SIZE <= c.size) {
        const int64_t chunk_start = c.at;
        const uint16_t id = c.u16();
        const uint32_t length = c.u32();
        if (length < CHUNK_HEADER_SIZE) {
            m_error = String("chunk with impossible length");
            break;
        }
        const int64_t chunk_end = chunk_start + static_cast<int64_t>(length);
        if (id == M_MESH) {
            found_mesh = true;
            read_mesh(c, chunk_end, shared, submeshes);
            // OGRE writes exactly one mesh stream and stops. Anything after it is
            // trailing bytes, not chunks: two meshes in the hero asset carry such
            // padding, and walking into it makes a sound file look corrupt.
            break;
        }
        c.at = chunk_end;
    }

    // Shared geometry may be written after the submeshes that reference it, so it is
    // resolved once the whole mesh stream has been read rather than at the point of use.
    for (int64_t i = 0; i < submeshes.size(); ++i) {
        Dictionary submesh = submeshes[i];
        if (!static_cast<bool>(submesh["uses_shared_vertices"])) { continue; }
        submesh["positions"] = shared.positions;
        submesh["normals"] = shared.normals;
        submesh["uvs"] = shared.uvs;
    }

    if (!found_mesh) {
        result["error"] = String("no mesh chunk in '") + path + String("'");
        return result;
    }
    result["error"] = m_error;
    result["version"] = version;
    result["shared_vertex_count"] = shared.positions.size();
    result["submeshes"] = submeshes;
    return result;
}

bool OgreMeshReader::read_mesh(Cursor &c, int64_t end, Geometry &shared, Array &submeshes) {
    c.u8();  // skeletallyAnimated
    while (c.at + CHUNK_HEADER_SIZE <= end) {
        const int64_t chunk_start = c.at;
        const uint16_t id = c.u16();
        const uint32_t length = c.u32();
        // A mesh chunk whose declared length runs past the end of its own file is common
        // enough in this library to be the rule rather than the exception, so the walk stops
        // at whatever it cannot make sense of and keeps everything read up to there.
        if (length < CHUNK_HEADER_SIZE || chunk_start + static_cast<int64_t>(length) > c.size) {
            break;
        }
        const int64_t chunk_end = chunk_start + static_cast<int64_t>(length);
        switch (id) {
            case M_GEOMETRY:
                read_geometry(c, chunk_end, shared);
                break;
            case M_SUBMESH:
                read_submesh(c, chunk_end, submeshes);
                break;
            default:
                break;  // Skeleton links, LOD, bounds, edge lists: not needed here.
        }
        c.at = chunk_end;
    }
    return true;
}

bool OgreMeshReader::read_submesh(Cursor &c, int64_t end, Array &submeshes) {
    Dictionary out;
    out["material"] = c.str();
    const bool uses_shared = c.u8() != 0;
    const uint32_t index_count = c.u32();
    const bool indices_32bit = c.u8() != 0;

    PackedInt32Array indices;
    indices.resize(static_cast<int64_t>(index_count));
    for (uint32_t i = 0; i < index_count; ++i) {
        indices[static_cast<int64_t>(i)] =
                indices_32bit ? static_cast<int32_t>(c.u32()) : static_cast<int32_t>(c.u16());
    }

    // Every triangle is reversed, and the vertex normals are left exactly as authored.
    // That pairing is not obvious and was got wrong twice, so it is worth the words.
    //
    // Measured in the file, index order and the authored normals agree on 99-100% of
    // triangles (tools/facing_probe.gd), which reads as "the file is already
    // counter-clockwise, do not touch it". On screen the opposite holds: loaded in file
    // order the vehicle is culled from outside and drawn from inside. Something between
    // here and the drawn pixel mirrors the geometry; it has not been isolated, and a
    // negative-determinant basis somewhere in the pose path is the first place to look.
    //
    // The temptation is then to negate the normals too, to keep them agreeing with the
    // winding. Do not: the gate body_blocks_sun measures the vehicle 2.13x brighter lit
    // from the camera's side than from behind with the normals as authored, and 0.73x --
    // brighter from behind, which is the sun appearing to shine through the bodywork --
    // with them negated. Whatever mirrors the triangles evidently leaves the normals
    // alone, so this must too.

    for (int64_t i = 0; i + 2 < indices.size(); i += 3) {
        const int32_t swap = indices[i + 1];
        indices[i + 1] = indices[i + 2];
        indices[i + 2] = swap;
    }

    // **A submesh that has been read is kept, whatever follows it.** The child chunks after
    // the index data are operation type, bone assignments, texture aliases -- nothing this
    // reader needs -- and walking off the end of them used to abandon the submesh entirely,
    // throwing away geometry that had already been read correctly. `a1da0UID-kwhale.mesh` is
    // one: its declared mesh chunk runs 110,924 bytes past a 106,944-byte file, so the walk
    // reaches a chunk header made of whatever lies beyond the submesh, and a whale that was
    // fully read drew nothing at all. Stop scanning children, keep the submesh.
    Geometry own;
    while (c.at + CHUNK_HEADER_SIZE <= end) {
        const int64_t chunk_start = c.at;
        const uint16_t id = c.u16();
        const uint32_t length = c.u32();
        if (length < CHUNK_HEADER_SIZE || chunk_start + static_cast<int64_t>(length) > c.size) {
            break;
        }
        const int64_t chunk_end = chunk_start + static_cast<int64_t>(length);
        if (id == M_GEOMETRY && !uses_shared) {
            read_geometry(c, chunk_end, own);
        } else if (id != M_SUBMESH_OPERATION && id != M_SUBMESH_BONE_ASSIGNMENT) {
            // Anything else in a submesh is not geometry this reader needs.
        }
        c.at = chunk_end;
    }

    out["positions"] = own.positions;
    out["normals"] = own.normals;
    out["uvs"] = own.uvs;
    out["indices"] = indices;
    out["uses_shared_vertices"] = uses_shared;
    submeshes.push_back(out);
    return true;
}

bool OgreMeshReader::read_geometry(Cursor &c, int64_t end, Geometry &out) {
    const uint32_t vertex_count = c.u32();
    std::vector<VertexElement> elements;
    // source -> (vertex size, data offset in the file)
    std::vector<std::pair<uint16_t, std::pair<uint16_t, int64_t>>> buffers;

    while (c.at + CHUNK_HEADER_SIZE <= end) {
        const int64_t chunk_start = c.at;
        const uint16_t id = c.u16();
        const uint32_t length = c.u32();
        // Keep whatever has been read rather than discarding the lot: see `read_submesh`.
        if (length < CHUNK_HEADER_SIZE || chunk_start + static_cast<int64_t>(length) > c.size) {
            break;
        }
        const int64_t chunk_end = chunk_start + static_cast<int64_t>(length);

        if (id == M_GEOMETRY_VERTEX_DECLARATION) {
            while (c.at + CHUNK_HEADER_SIZE <= chunk_end) {
                const int64_t el_start = c.at;
                const uint16_t el_id = c.u16();
                const uint32_t el_len = c.u32();
                if (el_len < CHUNK_HEADER_SIZE) { break; }
                if (el_id == M_GEOMETRY_VERTEX_ELEMENT) {
                    VertexElement e;
                    e.source = c.u16();
                    e.type = c.u16();
                    e.semantic = c.u16();
                    e.offset = c.u16();
                    e.index = c.u16();
                    elements.push_back(e);
                }
                c.at = el_start + static_cast<int64_t>(el_len);
            }
        } else if (id == M_GEOMETRY_VERTEX_BUFFER) {
            const uint16_t bind_index = c.u16();
            const uint16_t vertex_size = c.u16();
            const int64_t data_start = c.at;
            const uint16_t data_id = c.u16();
            c.u32();
            if (data_id == M_GEOMETRY_VERTEX_BUFFER_DATA) {
                buffers.push_back({bind_index, {vertex_size, c.at}});
            } else {
                c.at = data_start;
            }
        }
        c.at = chunk_end;
    }

    out.positions.resize(static_cast<int64_t>(vertex_count));
    out.normals.resize(static_cast<int64_t>(vertex_count));
    out.uvs.resize(static_cast<int64_t>(vertex_count));

    for (const VertexElement &e : elements) {
        if (element_size(e.type) == 0) { continue; }
        // Only the first UV set is read: the shim has no use for the others yet.
        if (e.semantic == VES_TEXTURE_COORDINATES && e.index != 0) { continue; }
        int64_t base = -1;
        uint16_t stride = 0;
        for (const auto &buffer : buffers) {
            if (buffer.first == e.source) {
                stride = buffer.second.first;
                base = buffer.second.second;
                break;
            }
        }
        if (base < 0 || stride == 0) { continue; }

        for (uint32_t v = 0; v < vertex_count; ++v) {
            const int64_t at = base + static_cast<int64_t>(v) * stride + e.offset;
            if (at + element_size(e.type) > c.size) { break; }
            const uint8_t *p = c.data + at;
            const int64_t vi = static_cast<int64_t>(v);
            if (e.semantic == VES_POSITION) {
                out.positions[vi] = Vector3(read_float_at(p), read_float_at(p + 4),
                                            read_float_at(p + 8));
            } else if (e.semantic == VES_NORMAL) {
                out.normals[vi] = Vector3(read_float_at(p), read_float_at(p + 4),
                                          read_float_at(p + 8));
            } else if (e.semantic == VES_TEXTURE_COORDINATES) {
                out.uvs[vi] = Vector2(read_float_at(p), read_float_at(p + 4));
            }
        }
    }
    return true;
}

} // namespace rorgd
