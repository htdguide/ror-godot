# maps/

Maps for the production build go here, one folder per terrain, unpacked: a folder holding a
`.terrn2` and the files it names. `tools/import_terrain.sh <archive.zip>` unpacks one into this
folder on a production checkout. Nothing here is committed and nothing is converted: the World
tab lists what is in this folder the next time the settings panel opens.

The development build keeps its maps under `assets/terrains/` instead, and bundles Rigs of Rods'
own shipped test map from the submodule; the production build bundles none.
