# src/term/render/plane.cr
module Term::Render
  PLACEHOLDER = '\u{10EEEE}'

  DIACRITICS = [
    0x0305, 0x030d, 0x030e, 0x0310, 0x0312, 0x033d, 0x033e, 0x033f, 0x0346, 0x034a, 0x034b, 0x034c,
    0x0350, 0x0351, 0x0352, 0x0357, 0x035b, 0x0363, 0x0364, 0x0365, 0x0366, 0x0367, 0x0368, 0x0369,
    0x036a, 0x036b, 0x036c, 0x036d, 0x036e, 0x036f, 0x0483, 0x0484, 0x0485, 0x0486, 0x0487, 0x0592,
    0x0593, 0x0594, 0x0595, 0x0597, 0x0598, 0x0599, 0x059c, 0x059d, 0x059e, 0x059f, 0x05a0, 0x05a1,
    0x05a8, 0x05a9, 0x05ab, 0x05ac, 0x05af, 0x05c4, 0x0610, 0x0611, 0x0612, 0x0613, 0x0614, 0x0615,
    0x0616, 0x0617, 0x0657, 0x0658, 0x0659, 0x065a, 0x065b, 0x065d, 0x065e, 0x06d6, 0x06d7, 0x06d8,
    0x06d9, 0x06da, 0x06db, 0x06dc, 0x06df, 0x06e0, 0x06e1, 0x06e2, 0x06e4, 0x06e7, 0x06e8, 0x06eb,
    0x06ec, 0x0730, 0x0732, 0x0733, 0x0735, 0x0736, 0x073a, 0x073d, 0x073f, 0x0740, 0x0741, 0x0743,
    0x0745, 0x0747, 0x0749, 0x074a, 0x07eb, 0x07ec, 0x07ed, 0x07ee, 0x07ef, 0x07f0, 0x07f1, 0x07f3,
    0x0816, 0x0817, 0x0818, 0x0819, 0x081b, 0x081c, 0x081d, 0x081e, 0x081f, 0x0820, 0x0821, 0x0822,
    0x0823, 0x0825, 0x0826, 0x0827, 0x0829, 0x082a, 0x082b, 0x082c, 0x082d, 0x0951, 0x0953, 0x0954,
    0x0f82, 0x0f83, 0x0f86, 0x0f87, 0x135d, 0x135e, 0x135f, 0x17dd, 0x193a, 0x1a17, 0x1a75, 0x1a76,
    0x1a77, 0x1a78, 0x1a79, 0x1a7a, 0x1a7b, 0x1a7c, 0x1b6b, 0x1b6d, 0x1b6e, 0x1b6f, 0x1b70, 0x1b71,
    0x1b72, 0x1b73, 0x1cd0, 0x1cd1, 0x1cd2, 0x1cda, 0x1cdb, 0x1ce0, 0x1dc0, 0x1dc1, 0x1dc3, 0x1dc4,
    0x1dc5, 0x1dc6, 0x1dc7, 0x1dc8, 0x1dc9, 0x1dcb, 0x1dcc, 0x1dd1, 0x1dd2, 0x1dd3, 0x1dd4, 0x1dd5,
    0x1dd6, 0x1dd7, 0x1dd8, 0x1dd9, 0x1dda, 0x1ddb, 0x1ddc, 0x1ddd, 0x1dde, 0x1ddf, 0x1de0, 0x1de1,
    0x1de2, 0x1de3, 0x1de4, 0x1de5, 0x1de6, 0x1dfe, 0x20d0, 0x20d1, 0x20d4, 0x20d5, 0x20d6, 0x20d7,
    0x20db, 0x20dc, 0x20e1, 0x20e7, 0x20e9, 0x20f0, 0x2cef, 0x2cf0, 0x2cf1, 0x2de0, 0x2de1, 0x2de2,
    0x2de3, 0x2de4, 0x2de5, 0x2de6, 0x2de7, 0x2de8, 0x2de9, 0x2dea, 0x2deb, 0x2dec, 0x2ded, 0x2dee,
    0x2def, 0x2df0, 0x2df1, 0x2df2, 0x2df3, 0x2df4, 0x2df5, 0x2df6, 0x2df7, 0x2df8, 0x2df9, 0x2dfa,
    0x2dfb, 0x2dfc, 0x2dfd, 0x2dfe, 0x2dff, 0xa66f, 0xa67c, 0xa67d, 0xa6f0, 0xa6f1, 0xa8e0, 0xa8e1,
    0xa8e2, 0xa8e3, 0xa8e4, 0xa8e5, 0xa8e6, 0xa8e7, 0xa8e8, 0xa8e9, 0xa8ea, 0xa8eb, 0xa8ec, 0xa8ed,
    0xa8ee, 0xa8ef, 0xa8f0, 0xa8f1, 0xaab0, 0xaab2, 0xaab3, 0xaab7, 0xaab8, 0xaabe, 0xaabf, 0xaac1,
    0xfe20, 0xfe21, 0xfe22, 0xfe23, 0xfe24, 0xfe25, 0xfe26, 0x10a0f, 0x10a38, 0x1d185, 0x1d186, 0x1d187,
    0x1d188, 0x1d189, 0x1d1aa, 0x1d1ab, 0x1d1ac, 0x1d1ad, 0x1d242, 0x1d243, 0x1d244,
  ]

  enum Layer
    Top
    Bottom
  end

  class Plane
    include Canvas

    MAX_PLACEMENT = 0xFFFFFF_u32

    getter cols      : Int32
    getter rows      : Int32
    getter x         : Int32
    getter y         : Int32
    getter parent    : Plane?
    getter children  : Array(Plane)
    getter sprites   : Array(Sprite)
    getter serial    : UInt32
    getter opacity   : UInt8
    getter base_cell : Cell
    getter fg        : Paint
    getter bg        : Paint
    getter? visible  : Bool
    getter? disposed : Bool
    getter? clip     : Bool

    @resized : (Plane -> Nil)?

    def initialize(@pile : Pile, @parent : Plane?, cols : Int32, rows : Int32,
                   @x : Int32 = 0, @y : Int32 = 0)
      @cols      = Math.max(cols, 0)
      @rows      = Math.max(rows, 0)
      @cells     = Slice(Cell).new(@cols * @rows, Cell::EMPTY)
      @children  = [] of Plane
      @sprites   = [] of Sprite
      @serial    = @pile.serial
      @opacity   = 255_u8
      @base_cell = Cell::EMPTY
      @fg        = Paint.foreground
      @bg        = Paint::NONE
      @visible   = true
      @disposed  = false
      @clip      = false
      @resized   = nil
      @left      = 0
      @top       = 0
      @right     = 0
      @bottom    = 0
      @parent.try(&.children.<<(self))
    end

    def inspect(io : IO) : Nil
      io << "#<Term::Render::Plane #" << @serial << ' ' << @cols << 'x' << @rows << " at " << @x << ',' << @y
      io << " hidden" unless @visible
      io << " disposed" if @disposed
      io << '>'
    end

    def plane(cols : Int32, rows : Int32, x : Int32 = 0, y : Int32 = 0, z : Layer = Layer::Top) : Plane
      @pile.plane(cols, rows, x, y, z, self)
    end

    def fg=(value) : Paint
      @fg = Paint.fg(value)
    end

    def bg=(value) : Paint
      @bg = Paint.bg(value)
    end

    def abs_x : Int32
      (@parent.try(&.abs_x) || 0) + @x
    end

    def abs_y : Int32
      (@parent.try(&.abs_y) || 0) + @y
    end

    def shown? : Bool
      @visible && !@disposed && (@parent.try(&.shown?) != false)
    end

    def strength : Float32
      (@opacity / 255.0_f32) * (@parent.try(&.strength) || 1.0_f32)
    end

    def z : Int32
      @pile.index(self)
    end

    def covers?(col : Int32, row : Int32) : Bool
      left = abs_x
      top  = abs_y
      col >= left && col < left + @cols && row >= top && row < top + @rows
    end

    def clip=(value : Bool) : Bool
      unless value == @clip
        @clip = value
        scar
      end
      value
    end

    def window : Tuple(Int32, Int32, Int32, Int32)
      left   = abs_x
      top    = abs_y
      right  = left + @cols
      bottom = top + @rows

      if limit = @parent.try(&.reach)
        left   = Math.max(left, limit[0])
        top    = Math.max(top, limit[1])
        right  = Math.min(right, limit[2])
        bottom = Math.min(bottom, limit[3])
      end

      {left, top, right, bottom}
    end

    def shows?(col : Int32, row : Int32) : Bool
      left, top, right, bottom = window
      col >= left && col < right && row >= top && row < bottom
    end

    protected def reach : Tuple(Int32, Int32, Int32, Int32)?
      @clip ? window : @parent.try(&.reach)
    end

    def [](x : Int32, y : Int32) : Cell
      inside?(x, y) ? @cells.unsafe_fetch(y * @cols + x) : Cell::EMPTY
    end

    @[AlwaysInline]
    def cell(x : Int32, y : Int32) : Cell
      @cells.unsafe_fetch(y * @cols + x)
    end

    def base(glyph : Char? = nil, fg = nil, bg = nil, attrs : Attr = Attr::None, line = nil) : Nil
      @base_cell = Cell.new(glyph ? glyph.ord.to_u32 : 0_u32, ink(fg), field(bg), attrs, line: rule(line))
      mark(0, 0, @cols, @rows)
    end

    def put(x : Int32, y : Int32, text : String, fg = nil, bg = nil, attrs : Attr = Attr::None,
            line = nil, link : String? = nil) : Int32
      target = link ? Links.intern(link) : 0_u32
      return 0 if y < 0 || y >= @rows
      front = ink(fg)
      back  = field(bg)
      under = rule(line)
      col   = x
      Graphemes.each(text) do |cluster, width|
        break if col >= @cols
        next if width == 0_u8 || control?(cluster)
        span = width.to_i
        if col >= 0
          if col + span <= @cols
            write(col, y, Graphemes.intern(cluster), front, back, attrs, span, under, target)
          else
            write(col, y, 0x20_u32, front, back, attrs, 1, under, target)
          end
        end
        col += span
      end
      col - x
    end

    def fill(x : Int32, y : Int32, cols : Int32, rows : Int32, glyph : Char? = nil,
             fg = nil, bg = nil, attrs : Attr = Attr::None, line = nil, link : String? = nil) : Nil
      target = link ? Links.intern(link) : 0_u32
      left   = Math.max(x, 0)
      top    = Math.max(y, 0)
      right  = Math.min(x + cols, @cols)
      bottom = Math.min(y + rows, @rows)
      return if left >= right || top >= bottom
      stamp = glyph ? glyph.ord.to_u32 : 0_u32
      front = ink(fg)
      back  = field(bg)
      under = rule(line)
      row   = top
      while row < bottom
        col = left
        while col < right
          sever(col, row)
          index = row * @cols + col
          @cells.unsafe_put(index, Cell.new(stamp, front, @pile.merge(@cells.unsafe_fetch(index).bg, back),
            attrs, line: under, link: target))
          col += 1
        end
        row += 1
      end
      mark(left, top, right, bottom)
    end

    def fill(glyph : Char? = nil, fg = nil, bg = nil, attrs : Attr = Attr::None,
             line = nil, link : String? = nil) : Nil
      fill(0, 0, @cols, @rows, glyph, fg, bg, attrs, line, link)
    end

    def erase(x : Int32, y : Int32, cols : Int32, rows : Int32) : Nil
      left   = Math.max(x, 0)
      top    = Math.max(y, 0)
      right  = Math.min(x + cols, @cols)
      bottom = Math.min(y + rows, @rows)
      return if left >= right || top >= bottom
      (top...bottom).each do |row|
        (left...right).each do |col|
          sever(col, row)
          @cells.unsafe_put(row * @cols + col, Cell::EMPTY)
        end
      end
      mark(left, top, right, bottom)
    end

    def erase : Nil
      @cells.fill(Cell::EMPTY)
      mark(0, 0, @cols, @rows)
    end

    def scroll(lines : Int32) : Nil
      return if lines == 0 || @rows == 0 || @cols == 0
      count = lines.abs
      return erase if count >= @rows
      kept = (@rows - count) * @cols
      if lines > 0
        @cells[count * @cols, kept].move_to(@cells[0, kept])
        @cells[kept, count * @cols].fill(Cell::EMPTY)
      else
        @cells[0, kept].move_to(@cells[count * @cols, kept])
        @cells[0, count * @cols].fill(Cell::EMPTY)
      end
      heal
      mark(0, 0, @cols, @rows)
      left = abs_x
      @pile.scrolled(abs_y, @rows, lines) if shown? && left <= 0 && left + @cols >= @pile.cols
    end

    def image(x : Int32, y : Int32, image_id : UInt32, columns : Int32, rows : Int32,
              placement : UInt32? = nil) : Nil
      marks = DIACRITICS
      if columns > marks.size || rows > marks.size
        raise ArgumentError.new("placeholder extent exceeds the diacritic table")
      end
      if placement && placement > MAX_PLACEMENT
        raise ArgumentError.new("placeholder placement ids are limited to 24 bits")
      end
      tone  = Paint.rgb(image_id & 0xFFFFFF_u32)
      under = placement ? Paint.rgb(placement) : Paint::NONE
      high  = (image_id >> 24).to_i32!
      rows.times do |row|
        columns.times do |col|
          next unless inside?(x + col, y + row)
          cluster = String.build do |text|
            text << PLACEHOLDER << marks[row].chr << marks[col].chr
            text << marks[high].chr if high > 0
          end
          sever(x + col, y + row)
          index = (y + row) * @cols + x + col
          @cells.unsafe_put(index, Cell.new(Graphemes.intern(cluster), tone,
            @pile.merge(@cells.unsafe_fetch(index).bg, @bg), Attr::None, flags: Cell::EXACT, line: under))
        end
      end
      mark(x, y, x + columns, y + rows)
    end

    def sprite(image_id : UInt32, x : Int32, y : Int32, columns : Int32, rows : Int32,
               width : Int32 = 0, height : Int32 = 0) : Sprite
      sprite = Sprite.new(self, @pile, image_id, @pile.serial, x, y,
        Math.max(columns, 0), Math.max(rows, 0), width, height)
      unless @disposed
        @sprites << sprite
        @pile.enlist(sprite)
        @pile.damage(abs_x + x, abs_y + y, columns, rows)
      end
      sprite
    end

    def cursor(x : Int32, y : Int32) : Nil
      @pile.caret = Pile::Caret.new(self, x, y) unless @disposed
    end

    def hide_cursor : Nil
      @pile.caret = nil if @pile.caret.try(&.plane.same?(self))
    end

    def move(x : Int32, y : Int32) : Nil
      return if x == @x && y == @y
      scar
      @x = x
      @y = y
      scar
    end

    def resize(cols : Int32, rows : Int32) : Nil
      cols = Math.max(cols, 0)
      rows = Math.max(rows, 0)
      return if cols == @cols && rows == @rows
      scar
      cells = Slice(Cell).new(cols * rows, Cell::EMPTY)
      keep  = Math.min(cols, @cols)
      Math.min(rows, @rows).times do |row|
        @cells[row * @cols, keep].copy_to(cells[row * cols, keep])
      end
      @cells = cells
      @cols  = cols
      @rows  = rows
      heal
      scar
      @children.dup.each(&.follow)
    end

    def on_resize(&block : Plane -> Nil) : Nil
      @resized = block
    end

    def opacity=(value : Float64) : Float64
      level = (value.clamp(0.0, 1.0) * 255).round.to_u8
      unless level == @opacity
        @opacity = level
        scar
      end
      value
    end

    def visible=(value : Bool) : Bool
      unless value == @visible
        @visible = value
        scar
      end
      value
    end

    def to_top : Nil
      @pile.reorder(self, @pile.planes.size - 1)
    end

    def to_bottom : Nil
      @pile.reorder(self, 0)
    end

    def raise_one : Nil
      @pile.reorder(self, z + 1)
    end

    def lower_one : Nil
      @pile.reorder(self, z - 1)
    end

    def above(other : Plane) : Nil
      @pile.place(self, other, 1)
    end

    def below(other : Plane) : Nil
      @pile.place(self, other, 0)
    end

    def reparent(parent : Plane?) : Nil
      return if parent.same?(@parent) || parent.same?(self)
      scar
      @parent.try(&.children.delete(self))
      @parent = parent
      parent.try(&.children.<<(self))
      scar
    end

    def dispose : Nil
      return if @disposed
      @children.dup.each(&.dispose)
      @sprites.dup.each(&.dispose)
      hide_cursor
      scar
      @disposed = true
      @parent.try(&.children.delete(self))
      @pile.remove(self)
      @cells = Slice(Cell).empty
      @cols  = 0
      @rows  = 0
    end

    def dirty? : Bool
      @right > @left
    end

    def dirty : Tuple(Int32, Int32, Int32, Int32)
      {@left, @top, @right, @bottom}
    end

    def clean : Nil
      @left   = 0
      @top    = 0
      @right  = 0
      @bottom = 0
    end

    def scar : Nil
      return if @disposed
      @pile.damage(abs_x, abs_y, @cols, @rows)
      @children.each(&.scar)
    end

    protected def follow : Nil
      @resized.try(&.call(self))
    end

    @[AlwaysInline]
    private def inside?(x : Int32, y : Int32) : Bool
      x >= 0 && x < @cols && y >= 0 && y < @rows
    end

    private def ink(value) : Paint
      value.nil? ? @fg : Paint.fg(value)
    end

    private def field(value) : Paint
      value.nil? ? @bg : Paint.bg(value)
    end

    private def rule(value) : Paint
      value.nil? ? Paint::NONE : Paint.fg(value)
    end

    private def control?(cluster : Bytes) : Bool
      first = cluster.unsafe_fetch(0)
      first < 0x20_u8 || first == 0x7F_u8 ||
        (first == 0xC2_u8 && cluster.size > 1 && cluster.unsafe_fetch(1) < 0xA0_u8)
    end

    private def write(col : Int32, row : Int32, glyph : UInt32, fg : Paint, bg : Paint, attrs : Attr,
                      span : Int32, line : Paint, link : UInt32) : Nil
      span.times { |across| sever(col + across, row) }
      span.times do |across|
        index = row * @cols + col + across
        @cells.unsafe_put(index, Cell.new(across == 0 ? glyph : 0_u32, fg,
          @pile.merge(@cells.unsafe_fetch(index).bg, bg), attrs, span.to_u8, across.to_u8,
          across == 0 ? 0_u8 : Cell::CONT, line, link))
      end
      mark(col, row, col + span, row + 1)
    end

    private def sever(col : Int32, row : Int32) : Nil
      cell = @cells.unsafe_fetch(row * @cols + col)
      return unless cell.block?
      left = col - cell.dx
      cell.span.to_i.times do |across|
        next unless inside?(left + across, row)
        index = row * @cols + left + across
        @cells.unsafe_put(index, @cells.unsafe_fetch(index).blanked)
      end
      mark(left, row, left + cell.span, row + 1)
    end

    private def heal : Nil
      @rows.times do |row|
        @cols.times do |col|
          index = row * @cols + col
          cell  = @cells.unsafe_fetch(index)
          next unless cell.block?
          @cells.unsafe_put(index, cell.blanked) unless whole?(col - cell.dx, row, cell)
        end
      end
    end

    private def whole?(left : Int32, row : Int32, cell : Cell) : Bool
      span = cell.span.to_i
      return false unless inside?(left, row) && inside?(left + span - 1, row)
      span.times do |across|
        part = @cells.unsafe_fetch(row * @cols + left + across)
        return false unless part.span == cell.span && part.dx == across && part.cont? == (across > 0)
      end
      true
    end

    private def mark(left : Int32, top : Int32, right : Int32, bottom : Int32) : Nil
      left   = Math.max(left, 0)
      top    = Math.max(top, 0)
      right  = Math.min(right, @cols)
      bottom = Math.min(bottom, @rows)
      return if left >= right || top >= bottom
      if dirty?
        @left   = Math.min(@left, left)
        @top    = Math.min(@top, top)
        @right  = Math.max(@right, right)
        @bottom = Math.max(@bottom, bottom)
      else
        @left   = left
        @top    = top
        @right  = right
        @bottom = bottom
        @pile.touch
      end
    end
  end
end
