#include "dds_reader.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <cstdint>
#include <cstring>

using namespace godot;

namespace rorgd {

namespace {

constexpr int64_t HEADER_SIZE = 128;   // magic + 124-byte header
constexpr int64_t PIXELFORMAT_AT = 76;
constexpr uint32_t DDPF_FOURCC = 0x4;
constexpr uint32_t DDPF_ALPHAPIXELS = 0x1;

uint32_t u32_at(const uint8_t *p, int64_t at) {
    uint32_t v = 0;
    std::memcpy(&v, p + at, 4);
    return v;
}

// Index of a mask's byte within a pixel, or -1. DDS stores channel layout as masks
// rather than as an order, so BGRA and RGBA files differ only by these values.
int byte_index_of_mask(uint32_t mask) {
    switch (mask) {
        case 0x000000ff: return 0;
        case 0x0000ff00: return 1;
        case 0x00ff0000: return 2;
        case 0xff000000: return 3;
        default: return -1;
    }
}

} // namespace

void DdsReader::_bind_methods() {
    ClassDB::bind_method(D_METHOD("read_file", "path"), &DdsReader::read_file);
}

Dictionary DdsReader::read_file(const String &path) {
    Dictionary out;

    Ref<FileAccess> file = FileAccess::open(path, FileAccess::READ);
    if (file.is_null()) {
        out["error"] = String("cannot open '") + path + String("'");
        return out;
    }
    PackedByteArray bytes = file->get_buffer(file->get_length());
    file->close();
    if (bytes.size() < HEADER_SIZE) {
        out["error"] = String("'") + path + String("' is too small to be a DDS");
        return out;
    }
    const uint8_t *d = bytes.ptr();
    if (std::memcmp(d, "DDS ", 4) != 0) {
        out["error"] = String("'") + path + String("' has no DDS magic");
        return out;
    }

    const uint32_t height = u32_at(d, 12);
    const uint32_t width = u32_at(d, 16);
    const uint32_t mip_count = u32_at(d, 28);
    const uint32_t pf_flags = u32_at(d, PIXELFORMAT_AT + 4);
    const uint32_t four_cc = u32_at(d, PIXELFORMAT_AT + 8);
    const uint32_t rgb_bits = u32_at(d, PIXELFORMAT_AT + 12);
    const uint32_t mask_r = u32_at(d, PIXELFORMAT_AT + 16);
    const uint32_t mask_g = u32_at(d, PIXELFORMAT_AT + 20);
    const uint32_t mask_b = u32_at(d, PIXELFORMAT_AT + 24);
    const uint32_t mask_a = u32_at(d, PIXELFORMAT_AT + 28);

    out["width"] = static_cast<int>(width);
    out["height"] = static_cast<int>(height);

    if (pf_flags & DDPF_FOURCC) {
        // Block-compressed: hand the blocks straight to the GPU format Godot already has.
        int format = -1;
        int64_t block_bytes = 0;
        if (std::memcmp(&four_cc, "DXT1", 4) == 0) {
            format = Image::FORMAT_DXT1;
            block_bytes = 8;
        } else if (std::memcmp(&four_cc, "DXT3", 4) == 0) {
            format = Image::FORMAT_DXT3;
            block_bytes = 16;
        } else if (std::memcmp(&four_cc, "DXT5", 4) == 0) {
            format = Image::FORMAT_DXT5;
            block_bytes = 16;
        }
        if (format < 0) {
            char cc[5] = {0};
            std::memcpy(cc, &four_cc, 4);
            out["error"] = String("unsupported DDS fourCC '") + String(cc) + String("'");
            return out;
        }
        // Every level the file ships, not only the first.
        //
        // A block-compressed image cannot have its mipmaps regenerated -- Godot's
        // `generate_mipmaps` fails on one -- so a reader that returns level 0 alone leaves every
        // DXT texture in the project with no mip chain at all, however many levels the author
        // stored. 217 of Starling Island's 248 DDS files carry one, and without it a distant
        // building's brickwork aliases into speckle and the roof dissolves into the sky.
        const int64_t levels = mip_count > 0 ? static_cast<int64_t>(mip_count) : 1;
        int64_t size = 0;
        for (int64_t level = 0; level < levels; ++level) {
            const int64_t w = (width >> level) > 0 ? (width >> level) : 1;
            const int64_t h = (height >> level) > 0 ? (height >> level) : 1;
            size += ((w + 3) / 4) * ((h + 3) / 4) * block_bytes;
        }
        if (bytes.size() < HEADER_SIZE + size) {
            out["error"] = String("DDS payload is shorter than its own header claims");
            return out;
        }
        out["error"] = String();
        out["format"] = format;
        out["mipmaps"] = static_cast<int>(levels);
        out["data"] = bytes.slice(HEADER_SIZE, HEADER_SIZE + size);
        return out;
    }

    // Uncompressed: convert whatever channel order the file uses into RGBA8.
    const int64_t pixel_bytes = rgb_bits / 8;
    if (pixel_bytes != 3 && pixel_bytes != 4) {
        out["error"] = String("unsupported DDS bit depth");
        return out;
    }
    const int64_t pixels = static_cast<int64_t>(width) * static_cast<int64_t>(height);
    if (bytes.size() < HEADER_SIZE + pixels * pixel_bytes) {
        out["error"] = String("DDS payload is shorter than its own header claims");
        return out;
    }
    const int r_at = byte_index_of_mask(mask_r);
    const int g_at = byte_index_of_mask(mask_g);
    const int b_at = byte_index_of_mask(mask_b);
    const int a_at = (pf_flags & DDPF_ALPHAPIXELS) ? byte_index_of_mask(mask_a) : -1;
    if (r_at < 0 || g_at < 0 || b_at < 0) {
        out["error"] = String("DDS channel masks are not byte aligned");
        return out;
    }

    PackedByteArray rgba;
    rgba.resize(pixels * 4);
    uint8_t *dst = rgba.ptrw();
    const uint8_t *src = d + HEADER_SIZE;
    for (int64_t i = 0; i < pixels; ++i) {
        const uint8_t *p = src + i * pixel_bytes;
        dst[i * 4 + 0] = p[r_at];
        dst[i * 4 + 1] = p[g_at];
        dst[i * 4 + 2] = p[b_at];
        dst[i * 4 + 3] = (a_at >= 0 && a_at < pixel_bytes) ? p[a_at] : 255;
    }
    out["error"] = String();
    out["mipmaps"] = 1;
    out["format"] = static_cast<int>(Image::FORMAT_RGBA8);
    out["data"] = rgba;
    return out;
}

} // namespace rorgd
