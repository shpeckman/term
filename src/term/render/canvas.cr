# src/term/render/canvas.cr
module Term::Render
  module Canvas
    abstract def cols : Int32
    abstract def rows : Int32
    abstract def put(x : Int32, y : Int32, text : String, fg : Paint? = nil, bg : Paint? = nil,
                     attrs : Attr = Attr::None, line : Paint? = nil,
                     link : String? = nil) : Int32
    abstract def fill(x : Int32, y : Int32, cols : Int32, rows : Int32, glyph : Char? = nil,
                      fg : Paint? = nil, bg : Paint? = nil,
                      attrs : Attr = Attr::None, line : Paint? = nil,
                      link : String? = nil) : Nil
    abstract def fill(glyph : Char? = nil, fg : Paint? = nil, bg : Paint? = nil,
                      attrs : Attr = Attr::None, line : Paint? = nil,
                      link : String? = nil) : Nil
    abstract def erase : Nil
  end
end
