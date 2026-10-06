# spec/render/support.cr
require "spec"
require "../../src/term"

class Stage
  getter compositor : Term::Render::Compositor
  getter themes     : Term::Render::Themes

  def initialize(cols : Int32 = 20, rows : Int32 = 5)
    @buf = ByteBuilder.new
    @themes = Term::Render::Themes.new
    @themes.depth = Term::Render::ColorDepth::TrueColor
    @themes.output = -> { @buf }
    @compositor = Term::Render::Compositor.new
    @compositor.themes = @themes
    @compositor.resize(cols, rows)
    @themes.on_palette = -> { @compositor.pile.damage_all }
  end

  def plane(cols : Int32, rows : Int32, x : Int32 = 0, y : Int32 = 0) : Term::Render::Plane
    @compositor.plane(cols, rows, x, y)
  end

  def planes_top : Term::Render::Plane
    @compositor.pile.planes.last
  end

  def frame : String
    @buf.reset
    @compositor.render(@buf)
    String.new(@buf.written)
  end

  def compose : Nil
    @compositor.pile.compose(@themes, @compositor.blend)
  end

  def at(x : Int32, y : Int32) : Term::Render::Tile
    @compositor.at(x, y)
  end
end

DARK16 = [
  0x1e1e2e, 0xf38ba8, 0xa6e3a1, 0xf9e2af, 0x89b4fa, 0xf5c2e7, 0x94e2d5, 0xbac2de,
  0x585b70, 0xf38ba8, 0xa6e3a1, 0xf9e2af, 0x89b4fa, 0xf5c2e7, 0x94e2d5, 0xa6adc8,
]

LIGHT16 = [
  0xeff1f5, 0xd20f39, 0x40a02b, 0xdf8e1d, 0x1e66f5, 0xea76cb, 0x179299, 0x5c5f77,
  0xacb0be, 0xd20f39, 0x40a02b, 0xdf8e1d, 0x1e66f5, 0xea76cb, 0x179299, 0x4c4f69,
]
