# Halcyon's embeddable EKA2L1 bridge for macOS.
#
# The upstream iOS port's platform layer (state, threads, launcher, window glue and
# the C++ API in emu_bridge.mm) is plain C++/Foundation. On macOS we compile the same
# files, and the drivers layer picks the NSOpenGL (AGL) context, which renders into
# the NSView we pass as the "layer". Only the UIKit browser launcher is replaced.
#
# This directory is added by the patched src/emu/CMakeLists.txt when
# HALCYON_EMBED_DIR is set (see core/scripts/patch-core.py).

set(IOS_GLUE "${CMAKE_CURRENT_LIST_DIR}/../../external/eka2l1/src/emu/ios")
get_filename_component(IOS_GLUE "${IOS_GLUE}" ABSOLUTE)

add_library(halcyon_mac_bridge STATIC
    ${IOS_GLUE}/src/emu_bridge.mm
    ${IOS_GLUE}/src/emu_window_ios.cpp
    ${IOS_GLUE}/src/input_dialog.cpp
    ${IOS_GLUE}/src/launcher.cpp
    ${IOS_GLUE}/src/state.cpp
    ${IOS_GLUE}/src/thread.cpp
    applauncher_mac.mm)

target_include_directories(halcyon_mac_bridge PUBLIC ${IOS_GLUE}/include)

target_link_libraries(halcyon_mac_bridge PUBLIC
    common
    cpu
    drivers
    epoc
    epockern
    epocpkg
    epocservs
    epocloader
    config
    glad
    lunasvg
    sqlite3
    yaml-cpp)

# Same prebuilt Symbian patch DLLs the iOS and Android frontends stage.
add_dependencies(halcyon_mac_bridge
    avkonfep
    audiooutputrouting
    ecam
    scdv
    mediaclientaudio
    mediaclientaudiostream
    mediaclientvideo
    vibractrl
    backlightctrl
    postingsurfacefactory
    goommonitor)
