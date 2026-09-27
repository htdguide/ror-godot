class_name Dds
extends RefCounted
## Reads a DDS texture into a Godot `Image`.
##
## Every texture in a Rigs of Rods terrain is a DDS, and Godot's DDS support is an editor import
## plugin: `Image.load_from_file` on one fails with "Failed to load image. Error 15". This project
## has no editor session in its loop, so a terrain's own textures have to be read at run time or
## not at all.
##
## Which is less work than it sounds, because the block-compressed formats are what the GPU wants
## anyway: the header states the size and the format, and the bytes after it are already a valid
## `FORMAT_DXT1`/`DXT3`/`DXT5` payload, mipmap chain included. Nothing is decoded here — the data
## is handed to `Image.create_from_data` as it is found, and `Image.decompress` is available for
## anything that needs pixels on the CPU.
##
## Uncompressed DDS is also read, because normal maps in these packs often are: La Paz ships an
## 800x600 32-bit `blank_NRM.dds`, which is not a power of two and has no mipmaps, and a reader
## that assumes compression rejects it.

const MAGIC: int = 0x20534444
const HEADER_BYTES: int = 124
const DATA_OFFSET: int = 128
## Where things live in the header, in bytes from the start of the file.
const AT_HEIGHT: int = 12
const AT_WIDTH: int = 16
const AT_MIPMAPS: int = 28
const AT_PIXEL_FLAGS: int = 80
const AT_FOURCC: int = 84
const AT_BIT_COUNT: int = 88
## The pixel-format flags this reads: a four-character code, or plain RGB with an alpha channel.
const FLAG_FOURCC: int = 0x4
const FLAG_RGB: int = 0x40
const FLAG_ALPHA: int = 0x1


## Reads a DDS file. Returns null when it is not one, or is in a format this does not read.
static func load_image(path: String) -> Image:
    var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
    if bytes.size() < DATA_OFFSET:
        return null
    if bytes.decode_u32(0) != MAGIC or bytes.decode_u32(4) != HEADER_BYTES:
        return null
    var width: int = bytes.decode_u32(AT_WIDTH)
    var height: int = bytes.decode_u32(AT_HEIGHT)
    if width <= 0 or height <= 0:
        return null
    var format: int = _format(bytes)
    if format < 0:
        return null
    var payload: PackedByteArray = bytes.slice(DATA_OFFSET)
    if format == Image.FORMAT_RGBA8:
        payload = _as_rgba(payload, width, height, bytes.decode_u32(AT_BIT_COUNT))
        if payload.is_empty():
            return null
        return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, payload)
    # Block-compressed: the mipmap chain is only usable whole, so a file that was cut short
    # loses its mipmaps rather than being rejected.
    var mipmaps: int = maxi(bytes.decode_u32(AT_MIPMAPS), 1)
    var whole: int = _chain_bytes(width, height, mipmaps, format)
    if mipmaps > 1 and payload.size() >= whole:
        return Image.create_from_data(
            width, height, true, format, payload.slice(0, whole)
        )
    var first: int = _chain_bytes(width, height, 1, format)
    if payload.size() < first:
        return null
    return Image.create_from_data(width, height, false, format, payload.slice(0, first))


## Which Godot format the header describes, or -1 for one this does not read.
static func _format(bytes: PackedByteArray) -> int:
    var flags: int = bytes.decode_u32(AT_PIXEL_FLAGS)
    if (flags & FLAG_FOURCC) != 0:
        match bytes.slice(AT_FOURCC, AT_FOURCC + 4).get_string_from_ascii():
            "DXT1":
                return Image.FORMAT_DXT1
            "DXT2", "DXT3":
                return Image.FORMAT_DXT3
            "DXT4", "DXT5":
                return Image.FORMAT_DXT5
        return -1
    if (flags & FLAG_RGB) != 0:
        return Image.FORMAT_RGBA8
    return -1


## How many bytes `mipmaps` levels of a block-compressed image take.
static func _chain_bytes(width: int, height: int, mipmaps: int, format: int) -> int:
    var block: int = 8 if format == Image.FORMAT_DXT1 else 16
    var total: int = 0
    var w: int = width
    var h: int = height
    for _level: int in mipmaps:
        total += int(ceil(float(w) / 4.0)) * int(ceil(float(h) / 4.0)) * block
        w = maxi(w / 2, 1)
        h = maxi(h / 2, 1)
    return total


## Uncompressed DDS is stored BGRA, and may have no alpha channel at all.
static func _as_rgba(
    payload: PackedByteArray, width: int, height: int, bit_count: int
) -> PackedByteArray:
    var stride: int = bit_count / 8
    if stride < 3:
        return PackedByteArray()
    var pixels: int = width * height
    if payload.size() < pixels * stride:
        return PackedByteArray()
    var out: PackedByteArray = PackedByteArray()
    out.resize(pixels * 4)
    for index: int in pixels:
        var at: int = index * stride
        out[index * 4] = payload[at + 2]
        out[index * 4 + 1] = payload[at + 1]
        out[index * 4 + 2] = payload[at]
        out[index * 4 + 3] = payload[at + 3] if stride >= 4 else 255
    return out
