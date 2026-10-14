#!/usr/bin/env python3
"""Apply Halcyon's small, idempotent build patches to the EKA2L1 submodule.

We keep the emulator core as an untouched git submodule and adjust three build
files at build time instead of maintaining a fork:

1. src/emu/CMakeLists.txt  - on macOS, build Halcyon's embeddable bridge
   (core/embed) instead of the Qt desktop frontend, when HALCYON_EMBED_DIR is set.
2. src/external/ffmpeg/CMakeLists.txt - link the FFmpeg we cross-compile
   (core/scripts/build-ffmpeg.sh) when HALCYON_FFMPEG_DIR is set. The bundled
   prebuilts are x86_64-only on macOS and missing for iOS devices.
3. src/emu/ios/src/launcher.cpp - the port answers Symbian text-entry and yes/no
   dialogs automatically. Route them to host hooks (core/embed/halcyon_host.h) so
   the app can show the system keyboard and a real alert, falling back to the old
   behaviour when no hook is installed.

Running this twice is safe: each edit checks for its marker first.
"""
import pathlib
import sys

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "external/eka2l1").resolve()
MARK = "# HALCYON-PATCH"      # CMake files
CPP_MARK = "// HALCYON-PATCH"  # C++ files


def patch(rel, old, new):
    path = ROOT / rel
    text = path.read_text()
    if new in text:
        print(f"  already patched: {rel}")
        return
    if old not in text:
        sys.exit(f"error: expected text not found in {rel}; the submodule changed. Update patch-core.py.")
    path.write_text(text.replace(old, new, 1))
    print(f"  patched: {rel}")


print(f"Patching EKA2L1 at {ROOT}")

patch(
    "src/emu/CMakeLists.txt",
    "else()\n    add_subdirectory(qt)\nendif()",
    f"elseif (HALCYON_EMBED_DIR) {MARK}\n"
    "    add_subdirectory(${HALCYON_EMBED_DIR} halcyon_embed)\n"
    "else()\n    add_subdirectory(qt)\nendif()",
)

patch(
    "src/external/ffmpeg/CMakeLists.txt",
    "if (NOT DEFINED FFMPEG_CORE_NAME)",
    f"{MARK}: use Halcyon's cross-compiled FFmpeg when provided.\n"
    "if (HALCYON_FFMPEG_DIR)\n"
    "\tif (NOT DEFINED FFMPEG_CORE_NAME)\n\t\tset(FFMPEG_CORE_NAME ffmpeg)\n\tendif()\n"
    "\tadd_library(${FFMPEG_CORE_NAME} INTERFACE)\n"
    "\ttarget_include_directories(${FFMPEG_CORE_NAME} INTERFACE \"${HALCYON_FFMPEG_DIR}/include\")\n"
    "\ttarget_link_libraries(${FFMPEG_CORE_NAME} INTERFACE\n"
    "\t\t\"${HALCYON_FFMPEG_DIR}/lib/libavformat.a\"\n"
    "\t\t\"${HALCYON_FFMPEG_DIR}/lib/libavcodec.a\"\n"
    "\t\t\"${HALCYON_FFMPEG_DIR}/lib/libswscale.a\"\n"
    "\t\t\"${HALCYON_FFMPEG_DIR}/lib/libavutil.a\"\n"
    "\t\t\"${HALCYON_FFMPEG_DIR}/lib/libswresample.a\"\n"
    "\t\t\"z\")\n"
    "\treturn()\n"
    "endif()\n\n"
    "if (NOT DEFINED FFMPEG_CORE_NAME)",
)

patch(
    "src/emu/ios/src/launcher.cpp",
    "#include <ios/launcher.h>\n",
    f"#include <ios/launcher.h>\n#include <ios/input_dialog.h> {CPP_MARK}\n",
)

HOOKS = f"""    {CPP_MARK}: host hooks for native text entry and yes/no dialogs.
    namespace host {{
        std::function<void(const std::string &, int)> on_text_input_request;
        std::function<void(const std::string &, const std::string &, const std::string &)> on_question_request;

        void finish_text_input(const std::string &text) {{
            if (drivers::ui::launcher_instance) {{
                drivers::ui::launcher_instance->on_finished_text_input(text, true);
            }}
        }}

        void finish_question(const int result) {{
            if (drivers::ui::launcher_instance) {{
                drivers::ui::launcher_instance->on_question_dialog_finished(result);
            }}
        }}
    }}

    bool launcher::open_input_view("""

patch(
    "src/emu/ios/src/launcher.cpp",
    "    bool launcher::open_input_view(",
    HOOKS,
)

patch(
    "src/emu/ios/src/launcher.cpp",
    "        input_complete_callback_ = complete_callback;\n",
    "        input_complete_callback_ = complete_callback;\n"
    f"        if (host::on_text_input_request) {{ {CPP_MARK}\n"
    "            host::on_text_input_request(common::ucs2_to_utf8(initial_text), max_len);\n"
    "            return true;\n"
    "        }\n",
)

patch(
    "src/emu/ios/src/launcher.cpp",
    "        yes_no_complete_callback_ = complete_callback;\n",
    "        yes_no_complete_callback_ = complete_callback;\n"
    f"        if (host::on_question_request) {{ {CPP_MARK}\n"
    "            host::on_question_request(common::ucs2_to_utf8(text), common::ucs2_to_utf8(button1_text),\n"
    "                common::ucs2_to_utf8(button2_text));\n"
    "            return true;\n"
    "        }\n",
)

print("Done.")
