# src/term/render/compositor.cr
module Term::Render
  class ::ByteBuilder
    def cursor_at(row : Int32, col : Int32) : self
      reserve(26)
      unsafe_csi.unsafe_int(row + 1).unsafe_semi.unsafe_int(col + 1).unsafe_byte(0x48_u8)
    end
  end

  enum CursorShape
    Block
    Underline
    Bar
  end

  class Compositor
    FALLBACK_COLS =   80
    FALLBACK_ROWS =   24
    GAP_LIMIT     =    4
    ERASE_MIN     =    4
    SHIFT_MIN     =    2
    SYNC_MODE     = 2026
    ENTER         = "\e[?25l"
    LEAVE         = "\e[0m\e[0 q\e[?25h"

    SGR = [
      {Attr::Bold,            "1",   22},
      {Attr::Dim,             "2",   22},
      {Attr::Italic,          "3",   23},
      {Attr::Underline,       "4",   24},
      {Attr::DoubleUnderline, "4:2", 24},
      {Attr::CurlyUnderline,  "4:3", 24},
      {Attr::DottedUnderline, "4:4", 24},
      {Attr::DashedUnderline, "4:5", 24},
      {Attr::Blink,           "5",   25},
      {Attr::Reverse,         "7",   27},
      {Attr::Conceal,         "8",   28},
      {Attr::Strike,          "9",   29},
      {Attr::Overline,        "53",  55},
    ]

    getter pile         : Pile
    getter root         : Plane
    getter cursor_shape : CursorShape?
    getter cursor_blink : Bool
    getter blend        : BlendSpace

    property themes : Themes

    @pen : Tile

    def initialize
      @pile         = Pile.new(FALLBACK_COLS, FALLBACK_ROWS)
      @root         = @pile.plane(FALLBACK_COLS, FALLBACK_ROWS)
      @front        = Slice(Tile).new(FALLBACK_COLS * FALLBACK_ROWS, Tile::VOID)
      @painters     = [] of Compositor -> Nil
      @themes       = Themes.new
      @blend        = BlendSpace::Linear
      @cursor_shape = nil
      @cursor_blink = true
      @sync         = false
      @open         = false
      @col          = -1
      @row          = -1
      @pen          = Tile::BLANK
      @caret_on     = false
      @caret_col    = -1
      @caret_row    = -1
      @caret_code   = 0
      @pile.merger  = ->(under : Paint, over : Paint) { fuse(under, over) }
    end

    def enter(target : ByteBuilder) : Nil
      invalidate
      @caret_on = false
      target.str(ENTER)
    end

    def leave(target : ByteBuilder) : Nil
      @pile.sprites.each do |sprite|
        unplace(target, sprite) if sprite.placed
      end
      target.str("\e[0m")
      target.str("\e[0 q") if @caret_code > 0
      target.str("\e[?25h")
      @caret_on   = false
      @caret_code = 0
      @caret_col  = -1
      @caret_row  = -1
    end

    def cols : Int32
      @pile.cols
    end

    def rows : Int32
      @pile.rows
    end

    def plane(cols : Int32, rows : Int32, x : Int32 = 0, y : Int32 = 0,
              z : Layer = Layer::Top, parent : Plane? = nil) : Plane
      @pile.plane(cols, rows, x, y, z, parent || @root)
    end

    def paint(painter : Compositor -> Nil) : Nil
      @painters = @painters + [painter]
    end

    def drop_paint(painter : Compositor -> Nil) : Nil
      @painters = @painters.reject { |entry| entry == painter }
    end

    def at(x : Int32, y : Int32) : Tile
      @pile.tile(x, y)
    end

    def blend=(blend : BlendSpace) : BlendSpace
      unless blend == @blend
        @blend = blend
        @pile.damage_all
      end
      blend
    end

    def cursor_shape=(shape : CursorShape?) : CursorShape?
      @cursor_shape = shape
      @pile.touch
      shape
    end

    def cursor_blink=(blink : Bool) : Bool
      @cursor_blink = blink
      @pile.touch
      blink
    end

    def hide_cursor : Nil
      @pile.caret = nil
    end

    def invalidate : Nil
      @front.fill(Tile::VOID)
      @pile.sprites.each(&.placed=(nil))
      @pile.damage_all
    end

    def resize(cols : Int32, rows : Int32) : Nil
      unless cols == @pile.cols && rows == @pile.rows
        @pile.resize(cols, rows)
        @front = Slice(Tile).new(@pile.cols * @pile.rows, Tile::VOID)
        @root.resize(cols, rows)
      end
      invalidate
    end

    def sync? : Bool
      @sync
    end

    def sync=(sync : Bool) : Bool
      @sync = sync
    end

    def render(target : ByteBuilder) : Nil
      @painters.each(&.call(self))
      @open = false
      if @pile.damaged?
        @pile.compose(themes, @blend)
        shift(target)
        emit(target)
      end
      place(target)
      point(target)
      @pile.settle
    end

    private def fuse(under : Paint, over : Paint) : Paint
      Pile.fuse(settled(under, themes), settled(over, themes), themes.palette, @blend)
    end

    private def settled(paint : Paint, themes : Themes) : Paint
      return paint unless paint.role?
      found = themes.resolve(paint.value.to_i32!)
      Paint.new(found.kind, found.value, paint.alpha)
    end

    private def unplace(target : ByteBuilder, sprite : Sprite) : Nil
      target.str(Term.delete_code(Term::Delete::Id, id: sprite.image_id, placement: sprite.placement_id))
      sprite.placed = nil
    end

    private def shift(target : ByteBuilder) : Nil
      return if @pile.shifts.empty? || !@pile.sprites.empty?
      tiles = @pile.tiles
      cols  = @pile.cols
      @pile.shifts.each do |hint|
        count = hint.lines.abs
        moved = hint.bottom - hint.top - count
        next if moved < SHIFT_MIN || !steady?(hint, cols)
        match = 0
        moved.times do |step|
          to   = hint.lines > 0 ? hint.top + step : hint.top + count + step
          from = hint.lines > 0 ? to + count : to - count
          match += 1 if alike?(tiles[to * cols, cols], @front[from * cols, cols])
        end
        next if match * 2 < moved
        start(target)
        target.csi.int(hint.top + 1).semi.int(hint.bottom).str("r\e[").int(count)
        target.char(hint.lines > 0 ? 'S' : 'T').str("\e[r")
        @col = -1
        @row = -1
        if hint.lines > 0
          @front[(hint.top + count) * cols, moved * cols].move_to(@front[hint.top * cols, moved * cols])
          @front[(hint.top + moved) * cols, count * cols].fill(Tile::BLANK)
        else
          @front[hint.top * cols, moved * cols].move_to(@front[(hint.top + moved) * cols, moved * cols])
          @front[hint.top * cols, count * cols].fill(Tile::BLANK)
        end
        (hint.top...hint.bottom).each { |row| @pile.widen(row) }
      end
    end

    private def steady?(hint : Pile::Shift, cols : Int32) : Bool
      @front[hint.top * cols, (hint.bottom - hint.top) * cols].none?(&.void?)
    end

    private def alike?(fresh : Slice(Tile), shown : Slice(Tile)) : Bool
      fresh.size.times do |index|
        return false unless fresh.unsafe_fetch(index).same?(shown.unsafe_fetch(index))
      end
      true
    end

    private def emit(target : ByteBuilder) : Nil
      tiles = @pile.tiles
      cols  = @pile.cols
      row   = 0
      while row < @pile.rows
        low, high = @pile.span(row)
        tail = -1
        col  = low
        while col < high
          index = row * cols + col
          back  = tiles.unsafe_fetch(index)
          if back.same?(@front.unsafe_fetch(index))
            col += 1
            next
          end
          @front.unsafe_put(index, back)
          if back.covered?
            col += 1
            next
          end
          start(target)
          tail = tail_of(tiles, row, cols) if tail < 0
          if col >= tail && cols - col >= ERASE_MIN
            reach(target, tiles, col, row, cols)
            style(target, Tile.new(bg: back.bg, bg_kind: back.bg_kind))
            target.str("\e[K")
            tiles[index, cols - col].copy_to(@front[index, cols - col])
            break
          end
          reach(target, tiles, col, row, cols)
          draw(target, back, cols)
          col += 1
        end
        row += 1
      end
    end

    private def place(target : ByteBuilder) : Nil
      unless @pile.retired.empty?
        @pile.retired.each do |sprite|
          next unless sprite.placed
          start(target)
          unplace(target, sprite)
        end
        @pile.retired.clear
      end
      @pile.sprites.each do |sprite|
        spot = sprite.live
        next if spot == sprite.placed
        start(target)
        if spot
          target.cursor_at(spot.row, spot.col)
          @row = spot.row
          @col = spot.col
          target.str(Term.place_code(sprite.image_id, placement: Term::Placement.new(id: sprite.placement_id,
            x: spot.left, y: spot.top, width: spot.width, height: spot.height, columns: spot.cols,
            rows: spot.rows, z: spot.z, hold_cursor: true), quiet: Term::Quiet::Ok))
          sprite.placed = spot
        else
          unplace(target, sprite)
        end
      end
    end

    private def point(target : ByteBuilder) : Nil
      spot = @pile.caret_position
      code = (shape = @cursor_shape) ? shape.value * 2 + (@cursor_blink ? 1 : 2) : 0
      if @open
        target.str("\e]8;;\e\\") if @pen.link != 0_u32
        target.str("\e[0m")
      end
      if spot
        col, row = spot
        if @open || !@caret_on || col != @caret_col || row != @caret_row || code != @caret_code
          target.cursor_at(row, col)
          target.csi.int(code).str(" q") unless code == @caret_code
          target.str("\e[?25h") unless @caret_on
          @caret_on   = true
          @caret_col  = col
          @caret_row  = row
          @caret_code = code
        end
      elsif @caret_on
        target.str("\e[?25l")
        @caret_on = false
      end
      if @open
        target.str("\e[?2026l") if sync?
        @open = false
      end
    end

    private def start(target : ByteBuilder) : Nil
      return if @open
      @open = true
      @col  = -1
      @row  = -1
      @pen  = Tile::BLANK
      target.str("\e[?2026h") if sync?
      target.str("\e[?25l") if @caret_on
      target.str("\e[0m")
      @caret_on = false
    end

    private def tail_of(tiles : Slice(Tile), row : Int32, cols : Int32) : Int32
      last = tiles.unsafe_fetch(row * cols + cols - 1)
      return cols unless last.blank?
      col = cols - 1
      while col > 0
        tile = tiles.unsafe_fetch(row * cols + col - 1)
        break unless tile.blank? && tile.bg_kind == last.bg_kind && tile.bg == last.bg
        col -= 1
      end
      col
    end

    private def reach(target : ByteBuilder, tiles : Slice(Tile), col : Int32, row : Int32, cols : Int32) : Nil
      return if @row == row && @col == col
      if @row == row && @col >= 0 && col > @col
        gap = col - @col
        if gap <= GAP_LIMIT && bridge?(tiles, row * cols + @col, gap)
          gap.times do |step|
            glyph(target, tiles.unsafe_fetch(row * cols + @col + step).glyph)
          end
        else
          target.csi.int(gap).char('C')
        end
      else
        target.cursor_at(row, col)
      end
      @row = row
      @col = col
    end

    private def bridge?(tiles : Slice(Tile), index : Int32, gap : Int32) : Bool
      gap.times do |step|
        tile = tiles.unsafe_fetch(index + step)
        return false if tile.cont? || tile.broken? || tile.block?
        return false unless tile.styled?(@pen)
      end
      true
    end

    private def draw(target : ByteBuilder, tile : Tile, cols : Int32) : Nil
      style(target, tile)
      width = 1
      if tile.broken?
        target.byte(0x20_u8)
      else
        glyph(target, tile.glyph)
        width = tile.span.to_i
      end
      @col += width
      @col = -1 if @col >= cols
    end

    private def glyph(target : ByteBuilder, glyph : UInt32) : Nil
      if glyph == 0_u32
        target.byte(0x20_u8)
      elsif Graphemes.pooled?(glyph)
        target.bytes(Graphemes.bytes(glyph))
      else
        target.char(glyph.unsafe_chr)
      end
    end

    private def lead(target : ByteBuilder, open : Bool) : Bool
      open ? target.semi : target.csi
      true
    end

    private def style(target : ByteBuilder, tile : Tile) : Nil
      pen = @pen
      unless tile.link == pen.link
        if tile.link == 0_u32
          target.str("\e]8;;\e\\")
        else
          target.str("\e]8;id=").int(tile.link).semi.str(Links.uri(tile.link)).st
        end
      end
      open = false
      unless tile.attrs == pen.attrs
        gone = pen.attrs & ~tile.attrs
        want = tile.attrs & ~pen.attrs
        last = 0
        SGR.each do |flag, _, off|
          next unless gone.includes?(flag) && off != last
          open = lead(target, open)
          target.int(off)
          last = off
          SGR.each do |other, _, shared|
            want |= other if shared == off && tile.attrs.includes?(other)
          end
        end
        SGR.each do |flag, on, _|
          next unless want.includes?(flag)
          open = lead(target, open)
          target.str(on)
        end
      end
      unless tile.fg_kind == pen.fg_kind && tile.fg == pen.fg
        open = lead(target, open)
        color(target, tile.fg_kind, tile.fg, 30)
      end
      unless tile.bg_kind == pen.bg_kind && tile.bg == pen.bg
        open = lead(target, open)
        color(target, tile.bg_kind, tile.bg, 40)
      end
      unless tile.line_kind == pen.line_kind && tile.line == pen.line
        open = lead(target, open)
        rule(target, tile.line_kind, tile.line)
      end
      target.byte(0x6D_u8) if open
      @pen = tile
    end

    private def color(target : ByteBuilder, kind : Tile::Kind, value : UInt32, base : Int32) : Nil
      case kind
      in Tile::Kind::Default
        target.int(base + 9)
      in Tile::Kind::Index
        if value < 8_u32
          target.int(base + value.to_i32!)
        elsif value < 16_u32
          target.int(base + 52 + value.to_i32!)
        else
          target.int(base + 8).str(";5;").int3(value.to_i32!)
        end
      in Tile::Kind::RGB
        target.int(base + 8).str(";2;").int3((value >> 16).to_i32! & 0xFF).semi.int3((value >> 8).to_i32! & 0xFF).semi.int3(value.to_i32! & 0xFF)
      end
    end

    private def rule(target : ByteBuilder, kind : Tile::Kind, value : UInt32) : Nil
      case kind
      in Tile::Kind::Default
        target.str("59")
      in Tile::Kind::Index
        target.str("58:5:").int3(value.to_i32!)
      in Tile::Kind::RGB
        target.str("58:2::").int3((value >> 16).to_i32! & 0xFF).char(':').int3((value >> 8).to_i32! & 0xFF).char(':').int3(value.to_i32! & 0xFF)
      end
    end
  end
end
