#include <pulp-vellum/editor-packages/BeadsyVellumEditor.hpp>

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>

#import <Metal/Metal.h>

namespace {
using namespace beadsy;

class TestContext final : public pulp::format::EditorContext {
public:
  explicit TestContext(pulp::format::ParamPort &port) : port_(port) {}
  pulp::format::ParamPort &params() override { return port_; }
  pulp::format::VisualPort *visuals() override { return nullptr; }
  bool request_resize(const pulp::format::EditorSize &size) override {
    requested_size = size;
    return true;
  }
  bool host_action(const pulp::format::HostActionRequest &) override { return false; }
  pulp::format::EditorHostKind host_kind() const override {
    return pulp::format::EditorHostKind::plugin;
  }

  std::optional<pulp::format::EditorSize> requested_size;

private:
  pulp::format::ParamPort &port_;
};

struct Harness {
  pulp::state::StateStore state;
  Beadsy processor;
  pulp::format::StateStoreParamPort port;
  TestContext context{port};
  pulp::vellum::ParamPortModel model{port};
  pulp::vellum::EditorEnv env{context, model};

  Harness() : port(define_parameters()) {}

private:
  pulp::state::StateStore &define_parameters() {
    processor.set_state_store(&state);
    processor.define_parameters(state);
    return state;
  }
};
} // namespace

TEST_CASE("Meru Vellum controls follow host values and edit through the parameter port") {
  Harness h;
  BeadsyEditor root(h.env, h.processor);
  const auto hints = root.editor_view_size();
  root.set_bounds({0, 0, static_cast<float>(hints.design_width),
                         static_cast<float>(hints.design_height)});
  root.layout_children();

  auto *density = dynamic_cast<beadsy::detail::PanelKnob *>(root.child_at(0));
  REQUIRE(density != nullptr);
  h.state.set_value(beadsy::kDensity, 0.75f);
  h.state.set_value(beadsy::kMode, 1.0f);
  h.state.pump_listeners();
  CHECK(density->value() == Catch::Approx(0.75f));
  CHECK(root.source_mode_control()->mode() == 1);

  h.state.set_display_modulation(beadsy::kDensity, 0.9f);
  root.editor_idle();
  CHECK(density->modulated_display_value() == Catch::Approx(0.9f));
  CHECK(density->value() == Catch::Approx(0.75f));
  h.state.clear_display_modulation(beadsy::kDensity);
  root.editor_idle();
  CHECK(density->modulated_display_value() == Catch::Approx(0.75f));

  const auto bounds = density->bounds();
  const editor_view::Point center{bounds.x + bounds.width * 0.5f,
                                  bounds.y + bounds.height * 0.5f};
  root.simulate_drag(center, {center.x, center.y + 20.0f}, 3);
  CHECK(h.port.get(beadsy::kDensity) < 0.75f);

  SeedModeControl *seed = nullptr;
  for (std::size_t i = 0; i < root.child_count() && !seed; ++i)
    seed = dynamic_cast<SeedModeControl *>(root.child_at(i));
  REQUIRE(seed != nullptr);
  double now = 100.0;
  seed->set_clock([&] { return now; });
  const auto before = h.port.get(beadsy::kSeedMode);
  seed->on_mouse_down({});
  CHECK(h.port.open_gestures(beadsy::kSeedMode) == 1);
  CHECK(h.port.get(beadsy::kSeedMode) == 1.0f);
  now += 1.0;
  seed->on_mouse_up({});
  CHECK(h.port.open_gestures(beadsy::kSeedMode) == 0);
  CHECK(h.port.get(beadsy::kSeedMode) == before);

  ResizeGrip *grip = nullptr;
  for (std::size_t i = 0; i < root.child_count() && !grip; ++i)
    grip = dynamic_cast<ResizeGrip *>(root.child_at(i));
  REQUIRE(grip != nullptr);
  editor_view::MouseEvent mouse{};
  mouse.phase = editor_view::MousePhase::press;
  grip->on_mouse_event(mouse);
  mouse.phase = editor_view::MousePhase::drag;
  mouse.window_position.x = 50;
  grip->on_mouse_event(mouse);
  REQUIRE(h.context.requested_size.has_value());
  CHECK(h.context.requested_size->width == 400);
  CHECK(h.context.requested_size->height ==
        static_cast<std::uint32_t>(std::lround(400.0 / beadsy::kPanelAspectRatio)));
  mouse.phase = editor_view::MousePhase::release;
  grip->on_mouse_event(mouse);
}

TEST_CASE("Meru Vellum route pickers connect each channel on the host catalog") {
  Harness h;
  pulp::host::MutableAudioRouteCatalog catalog;
  catalog.set_routes({
      {"track:left", "Left", pulp::host::AudioRouteKind::Track, 1, true},
      {"track:right", "Right", pulp::host::AudioRouteKind::Track, 2, true},
  });
  catalog.set_connect_channel_callback(
      [](const pulp::host::AudioRouteInfo &, std::size_t, std::size_t) { return true; });
  BeadsyEditor root(h.env, h.processor);
  root.set_audio_route_catalog(&catalog);
  auto *left = root.audio_route_picker();
  auto *right = root.audio_route_picker_right();
  REQUIRE(left != nullptr);
  REQUIRE(right != nullptr);
  CHECK_FALSE(left->enabled());
  CHECK_FALSE(right->enabled());

  h.state.set_value(beadsy::kMode, 2.0f);
  h.state.pump_listeners();
  REQUIRE(left->enabled());
  REQUIRE(right->enabled());
  CHECK(left->bus_index() == 1);
  CHECK(right->bus_index() == 1);
  left->set_selected(1);
  right->set_selected(2);
  CHECK(catalog.connected_route_channel(1, 0) == "track:left");
  CHECK(catalog.connected_route_channel(1, 1) == "track:right");
  CHECK(h.processor.route_identity(0) == "track:left");
  CHECK(h.processor.route_identity(1) == "track:right");
}

TEST_CASE("Meru Vellum package provides the authored panel size and aspect ratio") {
  Harness h;
  auto *factory = pulp::vellum::generated::BeadsyVellumEditor();
  auto editor = factory->create(h.processor, h.context, pulp::format::EditorRole::editor);
  REQUIRE(editor != nullptr);
  const auto hints = editor->size_hints();
  CHECK(hints.design_width == 350);
  CHECK(hints.design_height == 551);
  CHECK(hints.aspect_ratio == Catch::Approx(beadsy::kPanelAspectRatio));
  CHECK(editor->size().width == 350);
  CHECK(editor->size().height == 551);
  REQUIRE(editor->set_size({1000, 1000, 1.0}));
  CHECK(editor->size().width <= hints.max_width);
  CHECK(editor->size().height <= hints.max_height);
}

TEST_CASE("Meru Vellum panel produces a GPU frame", "[gpu]") {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    const bool metal_available = device != nil;
    [device release];
    if (!metal_available)
      SKIP("needs a GPU run by the lead");
  }

  Harness h;
  BeadsyEditor root(h.env, h.processor);
  const auto hints = root.editor_view_size();
  root.set_bounds({0, 0, static_cast<float>(hints.design_width),
                         static_cast<float>(hints.design_height)});
  root.layout_children();
  std::string error;
  REQUIRE(pulp::vellum::register_editor_dawn_bootstrap(h.processor.descriptor().bundle_id, &error));
  root.set_requires_gpu_host(true);
  editor_view::PluginViewHost::Options options;
  options.size = {hints.preferred_width, hints.preferred_height};
  options.use_gpu = true;
  auto host = editor_view::PluginViewHost::create(root, options);
  REQUIRE(host != nullptr);
  REQUIRE(host->is_gpu_backed());
  REQUIRE(host->present_first_frame());
  CHECK_FALSE(host->capture_back_buffer_png().empty());
}
