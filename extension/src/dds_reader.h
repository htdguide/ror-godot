#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace rorgd {

// Reads DDS textures, which Godot cannot load at run time.
//
// Godot handles DDS as an editor import format only: Image.load_from_file refuses one
// with ERR_FILE_UNRECOGNIZED. The community library is full of them, so the shim needs
// its own reader.
//
// Compressed payloads are handed through untouched, because Godot supports the DXT block
// formats on the GPU directly; decompressing them would throw away the compression the
// texture was authored with. Uncompressed payloads are converted to RGBA8, which is the
// one format every path accepts.
class DdsReader : public godot::RefCounted {
    GDCLASS(DdsReader, godot::RefCounted)

protected:
    static void _bind_methods();

public:
    // Returns { error, width, height, format, mipmaps, data }, where `format` is an
    // Image.Format value ready for Image.create_from_data and `data` holds every mip level the
    // file ships, one after another, in the order Godot expects them.
    //
    // It used to return the top level alone, on the grounds that Godot could regenerate the
    // rest. It cannot: `generate_mipmaps` fails on a block-compressed image, so every DXT
    // texture in the project had exactly one level and aliased badly at any distance.
    godot::Dictionary read_file(const godot::String &path);
};

} // namespace rorgd
