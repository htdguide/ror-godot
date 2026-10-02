class_name DdsImage
extends RefCounted
## One DDS file as an `Image`, with the mip chain the file ships.
##
## **A block-compressed image cannot have its mipmaps regenerated.** Godot's `generate_mipmaps`
## fails on one, so for as long as the reader returned the top level alone, every DXT texture in
## this project had exactly one level — and there is no filter that makes a single 256×256 level
## look right on a wall 500 m away. Starling Island's distant brickwork aliased into speckle and
## its roofs dissolved into the sky, which reads as a transparency fault and is a sampling one.
##
## 217 of that terrain's 248 DDS files carry a full chain. The authors stored them; nothing read
## them.
##
## The chain is only handed to Godot when the payload is **exactly** the size Godot computes for a
## full chain of that format and size. A file that stops its chain early — at 4×4, say — is laid
## out differently from what `create_from_data` expects, and would be read as garbage; those fall
## back to the top level, which is what they had before.


## The image at `path`, or null when it cannot be read.
static func read(path: String, reader: RefCounted) -> Image:
    if reader == null or not FileAccess.file_exists(path):
        return null
    var result: Dictionary = reader.read_file(path)
    if (result.get("error", "") as String) != "":
        return null
    var width: int = int(result["width"])
    var height: int = int(result["height"])
    var format: Image.Format = int(result["format"]) as Image.Format
    var data: PackedByteArray = result["data"] as PackedByteArray
    var levels: int = int(result.get("mipmaps", 1))
    var chained: bool = levels > 1 and data.size() == _payload_size(width, height, format, true)
    if not chained and levels > 1:
        # Only the first level is in a layout Godot understands.
        data = data.slice(0, _payload_size(width, height, format, false))
    return Image.create_from_data(width, height, chained, format, data)


## How many bytes Godot expects for an image of this size and format, with or without its chain.
##
## Asked of Godot rather than worked out here: the block arithmetic for every compressed format
## is exactly the knowledge this project should not be keeping a second copy of.
static func _payload_size(width: int, height: int, format: Image.Format, chain: bool) -> int:
    return Image.create_empty(width, height, chain, format).get_data().size()
