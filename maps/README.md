# maps/

Maps for the production build go here, one per terrain: an unpacked folder, or the zip as the
Rigs of Rods repository hands it out — a zip is unpacked beside itself, once, the next time the
game lists this folder, and left where it was. A terrain holds a `.terrn2` and the files it
names. Nothing here is committed.

The development build keeps its maps under `assets/terrains/` instead, and bundles Rigs of Rods'
own shipped test map from the submodule; the production build bundles none.
