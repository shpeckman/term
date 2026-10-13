# spec/render/theme_spec.cr
require "./support"

private def themed(stage : Stage) : Nil
  stage.themes.define(:dark, base16: DARK16, fg: 0xcdd6f4, bg: 0x1e1e2e) do |theme|
    theme.role :accent, 4
    theme.role :text_muted, theme.mix(:text, :surface, 0.5)
    theme.role :sidebar, :surface_raised
  end
  stage.themes.define(:light, base16: LIGHT16, fg: 0x4c4f69, bg: 0xeff1f5)
end

private def watching(themes : Term::Render::Themes) : Array(String?)
  names = [] of String?
  themes.on_theme = ->(name : String?) { names << name; nil }
  names
end

private def ticking(themes : Term::Render::Themes) : Array(Proc(Nil))
  ticks = [] of Proc(Nil)
  themes.running = -> { true }
  themes.ticker = ->(span : Time::Span, tick : Proc(Nil)) {
    ticks << tick
    -> { ticks.delete(tick); nil }
  }
  ticks
end

describe Term::Render::Themes do
  it "detects the color depth from the environment" do
    Term::Render::ColorDepth.detect("truecolor", "xterm").should eq(Term::Render::ColorDepth::TrueColor)
    Term::Render::ColorDepth.detect(nil, "xterm-kitty").should eq(Term::Render::ColorDepth::TrueColor)
    Term::Render::ColorDepth.detect(nil, "xterm-256color").should eq(Term::Render::ColorDepth::Indexed256)
    Term::Render::ColorDepth.detect(nil, "linux").should eq(Term::Render::ColorDepth::Ansi16)
    Term::Render::ColorDepth.detect(nil, nil).should eq(Term::Render::ColorDepth::Indexed256)
  end

  it "eases between zero and one" do
    Term::Render::Easing.each do |easing|
      easing.apply(0.0).should be_close(0.0, 1e-9)
      easing.apply(1.0).should be_close(1.0, 1e-9)
    end
    Term::Render::Easing::InOut.apply(0.5).should be_close(0.5, 1e-9)
  end

  it "resolves the core roles against the terminal palette by default" do
    stage = Stage.new
    stage.themes.resolve(Term::Render::Roles::Core::Surface.value).should eq(Term::Render::Paint.background)
    stage.themes.resolve(Term::Render::Roles::Core::Text.value).should eq(Term::Render::Paint.foreground)
    stage.themes.resolve(Term::Render::Roles::Core::Accent.value).should eq(Term::Render::Paint.index(4))
    stage.themes.resolve(Term::Render::Roles::Core::Border.value).kind.should eq(Term::Render::Paint::Kind::RGB)
    stage.themes.resolve(Term::Render::Roles.slot(:never_defined)).should eq(Term::Render::Paint.foreground)
    stage.themes.role(:accent).should eq(Term::Render::Paint.role(Term::Render::Roles::Core::Accent.value))
    stage.themes.indexed?.should be_true
    stage.themes.themed_palette?.should be_false
  end

  it "generates a palette for a base16 theme and resolves its roles" do
    stage = Stage.new
    watch = watching(stage.themes)
    themed(stage)
    stage.themes.use(:dark)
    watch.should eq(["dark"])
    stage.themes.current.not_nil!.name.should eq("dark")
    stage.themes.palette.bg.should eq(0x1e1e2e_u32)
    stage.themes.palette[4].should eq(0x89b4fa_u32)
    stage.themes.palette.themed?.should be_true
    stage.themes.indexed?.should be_false
    muted = stage.themes.resolve(Term::Render::Roles::Core::TextMuted.value)
    muted.should eq(Term::Render::Paint.rgb(Term::Render::ColorSpace.mix(0xcdd6f4_u32, 0x1e1e2e_u32, 0.5_f32, Term::Render::BlendSpace::Oklab)))
    stage.themes.resolve(Term::Render::Roles.slot(:sidebar)).should eq(stage.themes.resolve(Term::Render::Roles::Core::SurfaceRaised.value))
    stage.themes.use(nil)
    watch.should eq(["dark", nil])
    stage.themes.palette.same?(Term::Render::Palette.stock).should be_true
    stage.themes.indexed?.should be_true
  end

  it "accepts an explicit palette and rejects malformed input" do
    stage = Stage.new
    table = Array.new(256) { |index| index * 0x010101 }
    stage.themes.define("flat", palette: table, fg: "#ffffff", bg: Term::Color.rgb(0_u8, 0_u8, 0_u8))
    stage.themes.use("flat")
    stage.themes.palette[200].should eq(0xc8c8c8_u32)
    stage.themes.palette.fg.should eq(0xffffff_u32)
    expect_raises(ArgumentError) { stage.themes.define(:bad, base16: [1, 2, 3]) }
    expect_raises(ArgumentError) { stage.themes.define(:bad, palette: [1, 2, 3]) }
    expect_raises(ArgumentError) { stage.themes.define(:bad, base16: DARK16, fg: "nope") }
    expect_raises(ArgumentError) { stage.themes.use(:missing) }
  end

  it "paints cells from a local theme as direct colors" do
    stage = Stage.new(4, 1)
    themed(stage)
    plane = stage.plane(4, 1)
    plane.put(0, 0, "a", fg: :accent, bg: :surface)
    plane.put(1, 0, "b", fg: 1)
    stage.frame
    stage.at(0, 0).fg_kind.should eq(Term::Render::Tile::Kind::Index)
    stage.at(0, 0).fg.should eq(4_u32)
    stage.at(0, 0).bg_kind.should eq(Term::Render::Tile::Kind::Default)
    stage.themes.use(:dark)
    wire = stage.frame
    stage.at(0, 0).fg_kind.should eq(Term::Render::Tile::Kind::RGB)
    stage.at(0, 0).fg.should eq(0x89b4fa_u32)
    stage.at(0, 0).bg.should eq(0x1e1e2e_u32)
    stage.at(1, 0).fg.should eq(0xf38ba8_u32)
    stage.at(3, 0).bg.should eq(0x1e1e2e_u32)
    wire.should contain("48;2;30;30;46")
  end

  it "re-resolves the current theme when it is defined again" do
    stage = Stage.new
    themed(stage)
    stage.themes.use(:dark)
    stage.themes.define(:dark, base16: DARK16, fg: 0xffffff, bg: 0x000000)
    stage.themes.palette.bg.should eq(0x000000_u32)
  end

  it "switches between a dark and a light theme" do
    stage = Stage.new
    watch = watching(stage.themes)
    themed(stage)
    stage.themes.pair(dark: :dark, light: :light)
    stage.themes.current.not_nil!.name.should eq("dark")
    stage.themes.dark?.should be_true
    stage.themes.system_dark = false
    stage.themes.current.not_nil!.name.should eq("light")
    stage.themes.palette.bg.should eq(0xeff1f5_u32)
    stage.themes.toggle
    stage.themes.mode.should eq(Term::Render::ThemeMode::Dark)
    stage.themes.current.not_nil!.name.should eq("dark")
    stage.themes.system_dark = false
    stage.themes.current.not_nil!.name.should eq("dark")
    stage.themes.mode = Term::Render::ThemeMode::Auto
    stage.themes.current.not_nil!.name.should eq("light")
    stage.themes.toggle
    stage.themes.current.not_nil!.name.should eq("dark")
    watch.should eq(["dark", "light", "dark", "light", "dark"])
  end

  it "animates a transition and finishes on the target palette" do
    stage = Stage.new
    themes = stage.themes
    watch = watching(themes)
    ticks = ticking(themes)
    themes.depth = Term::Render::ColorDepth::TrueColor
    themes.define(:dark, base16: DARK16, fg: 0xcdd6f4, bg: 0x1e1e2e)
    themes.define(:light, base16: LIGHT16, fg: 0x4c4f69, bg: 0xeff1f5)
    themes.use(:dark)
    middle = [] of UInt32
    themes.transition(to: :light, duration: 120.milliseconds)
    ticks.size.should eq(1)
    sleep 60.milliseconds
    ticks.last.call
    middle << themes.palette.bg
    sleep 80.milliseconds
    ticks.last.call
    watch.should eq(["dark", "light"])
    themes.transitioning?.should be_false
    themes.palette.bg.should eq(0xeff1f5_u32)
    middle.size.should eq(1)
    middle[0].should_not eq(0x1e1e2e_u32)
    middle[0].should_not eq(0xeff1f5_u32)
  end

  it "collapses a transition when it cannot animate" do
    stage = Stage.new
    themes = stage.themes
    watch = watching(themes)
    themes.depth = Term::Render::ColorDepth::Indexed256
    themes.delivery = Term::Render::ThemeDelivery::Local
    themes.define(:dark, base16: DARK16, fg: 0xcdd6f4, bg: 0x1e1e2e)
    themes.define(:light, base16: LIGHT16, fg: 0x4c4f69, bg: 0xeff1f5)
    themes.use(:dark)
    themes.transition(to: :light, duration: 10.seconds)
    themes.transitioning?.should be_false
    themes.palette.bg.should eq(0xeff1f5_u32)
    watch.should eq(["dark", "light"])
  end

  it "follows the system scheme with the default duration while running" do
    stage = Stage.new
    themes = stage.themes
    watch = watching(themes)
    ticks = ticking(themes)
    themes.depth = Term::Render::ColorDepth::TrueColor
    themes.duration = 40.milliseconds
    themes.define(:dark, base16: DARK16, fg: 0xcdd6f4, bg: 0x1e1e2e)
    themes.define(:light, base16: LIGHT16, fg: 0x4c4f69, bg: 0xeff1f5)
    themes.pair(dark: :dark, light: :light)
    themes.system_dark = false
    ticks.size.should eq(1)
    sleep 60.milliseconds
    ticks.last.call
    themes.current.not_nil!.name.should eq("light")
    themes.palette.bg.should eq(0xeff1f5_u32)
  end
end
