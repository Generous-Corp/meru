#pragma once

#if defined(BEADSY_VELLUM_EDITOR)
#include <vellum/canvas/canvas.hpp>
#include <vellum/canvas/svg.hpp>
#include <vellum/view/context_menu.hpp>
#include <vellum/view/parameter_binding.hpp>
#include <vellum/view/ui_components.hpp>
#include <vellum/view/view.hpp>
#include <vellum/view/widgets.hpp>

namespace beadsy {
namespace editor_canvas = ::vellum::canvas;
namespace editor_view = ::vellum::view;
}
#else
#include <pulp/canvas/canvas.hpp>
#include <pulp/canvas/svg.hpp>
#include <pulp/view/context_menu.hpp>
#include <pulp/view/parameter_binding.hpp>
#include <pulp/view/ui_components.hpp>
#include <pulp/view/view.hpp>
#include <pulp/view/widgets.hpp>
#if __has_include(<pulp/view/native_context_menu.hpp>)
#include <pulp/view/native_context_menu.hpp>
#define BEADSY_HAS_NATIVE_MENUS 1
#endif

namespace beadsy {
namespace editor_canvas = pulp::canvas;
namespace editor_view = pulp::view;
}
#endif
