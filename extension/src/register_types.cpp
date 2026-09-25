#include "register_types.h"

#include "dds_reader.h"
#include "ogre_mesh.h"
#include "ror_flex.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_rorbridge_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    GDREGISTER_CLASS(rorgd::RorFlex);
    GDREGISTER_CLASS(rorgd::OgreMeshReader);
    GDREGISTER_CLASS(rorgd::DdsReader);
}

void uninitialize_rorbridge_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT rorbridge_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
                                                 const GDExtensionClassLibraryPtr p_library,
                                                 GDExtensionInitialization *r_initialization) {
    GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_rorbridge_module);
    init_obj.register_terminator(uninitialize_rorbridge_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
