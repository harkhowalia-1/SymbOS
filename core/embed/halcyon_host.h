/*
 * Halcyon host hooks, added to the EKA2L1 iOS port by core/scripts/patch-core.py.
 *
 * When a Symbian app opens a text-entry or yes/no dialog, the core calls these
 * hooks on the emulator's OS thread instead of auto-answering. The app shows the
 * system keyboard or an alert and replies with finish_text_input / finish_question.
 *
 * Licensed under the GNU General Public License v3 or later.
 */
#pragma once

#include <functional>
#include <string>

namespace eka2l1::ios::host {
    // initial text (UTF-8), maximum length in characters
    extern std::function<void(const std::string &, int)> on_text_input_request;
    // message, first button, second button (UTF-8)
    extern std::function<void(const std::string &, const std::string &, const std::string &)> on_question_request;

    void finish_text_input(const std::string &text);
    // 1 = first button, 0 = second button
    void finish_question(int result);
}
