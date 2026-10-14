# src/term/render.cr
require "bytewire"
require "termwidth"

class Term
  module Render
  end
end

require "./render/color_space"
require "./render/palette"
require "./render/paint"
require "./render/text_layout"
require "./render/canvas"
require "./render/theme"
require "./render/sprite"
require "./render/plane"
require "./render/pile"
require "./render/compositor"
