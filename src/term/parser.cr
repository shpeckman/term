# src/term/parser.cr
class Term
  MISSING    = Int32::MIN
  CSI_LIMIT  = 256
  TEXT_LIMIT = 1 << 28
  PASTE_END  = "\e[201~".to_slice

  enum State
    Ground
    Escape
    Ss3
    Csi
    Text
    TextEscape
    Paste
  end

  LETTERS = {
    'A' => Named::Up,
    'B' => Named::Down,
    'C' => Named::Right,
    'D' => Named::Left,
    'E' => Named::KpBegin,
    'F' => Named::End,
    'H' => Named::Home,
    'P' => Named::F1,
    'Q' => Named::F2,
    'S' => Named::F4,
  }

  SS3 = LETTERS.merge({'R' => Named::F3})

  TILDES = {
     2 => Named::Insert,
     3 => Named::Delete,
     5 => Named::PageUp,
     6 => Named::PageDown,
     7 => Named::Home,
     8 => Named::End,
    11 => Named::F1,
    12 => Named::F2,
    13 => Named::F3,
    14 => Named::F4,
    15 => Named::F5,
    17 => Named::F6,
    18 => Named::F7,
    19 => Named::F8,
    20 => Named::F9,
    21 => Named::F10,
    23 => Named::F11,
    24 => Named::F12,
  }

  @state   = State::Ground
  @string  = 0_u8
  @seq     = Bytewire.new(256)
  @reader  = Bytewire::Reader.new(Bytes.empty)
  @scratch = Bytewire.new(64)
  @values  = [] of Int32
  @starts  = [] of Int32
  @utf     = Bytewire.new(4)

  private def feed(byte : UInt8) : Nil
    case @state
    in .ground?
      if byte == 0x1b
        @state = State::Escape
      elsif byte < 0x80
        typed(byte.unsafe_chr, Mods::None)
      else
        utf(byte)
      end
    in .escape?
      @seq.reset
      @state = case byte
               when 0x5b then State::Csi
               when 0x4f then State::Ss3
               when 0x1b then State::Escape
               when 0x50, 0x58, 0x5d, 0x5e, 0x5f
                 @string = byte
                 State::Text
               else
                 State::Ground
               end
      if @state.ground?
        byte < 0x80 ? typed(byte.unsafe_chr, Mods::Alt) : utf(byte)
      end
    in .ss3?
      @state = State::Ground
      if named = SS3[byte.unsafe_chr]?
        tapped(Key.new(named.value, Key::Action::Press, Mods::None, nil, nil, nil))
      end
    in .paste?
      @seq.byte(byte)
      slice = @seq.written
      if byte == 0x7e && slice.size >= PASTE_END.size && slice[-PASTE_END.size..] == PASTE_END
        @state = State::Ground
        push Paste.new(["text/plain"], false, nil, String.new(slice[0, slice.size - PASTE_END.size]).scrub)
      elsif slice.size > TEXT_LIMIT
        @state = State::Ground
      end
    in .csi?
      case byte
      when 0x20..0x3f
        @seq.byte(byte)
        @state = State::Ground if @seq.pos > CSI_LIMIT
      when 0x40..0x7e
        @state = State::Ground
        csi(byte)
      when 0x1b
        @state = State::Escape
      else
        @state = State::Ground
      end
    in .text?
      case byte
      when 0x07
        @state = State::Ground
        text
      when 0x1b
        @state = State::TextEscape
      else
        @seq.byte(byte)
        @state = State::Ground if @seq.pos > TEXT_LIMIT
      end
    in .text_escape?
      if byte == 0x5c
        @state = State::Ground
        text
      else
        @state = State::Escape
        feed(byte)
      end
    end
  end

  private def idle : Nil
    case @state
    when .escape?
      @state = State::Ground
      tapped(Key.new(Named::Escape.value, Key::Action::Press, Mods::None, nil, nil, nil))
    when .ss3?
      @state = State::Ground
      typed('O', Mods::Alt)
    end
  end

  private def utf(byte : UInt8) : Nil
    @utf.reset if byte & 0xc0 != 0x80
    @utf.byte(byte)
    slice = @utf.written
    lead  = slice[0]
    need  = lead >= 0xf0 ? 4 : lead >= 0xe0 ? 3 : lead >= 0xc0 ? 2 : 0
    return @utf.reset if need == 0
    return if slice.size < need
    @reader.reset(slice)
    char = @reader.char?
    @utf.reset
    typed(char, Mods::None) if char
  end

  private def typed(char : Char, mods : Mods) : Nil
    code, extra, text =
      case char.ord
      when 0x0d   then {Named::Enter.value, Mods::None, nil}
      when 0x09   then {Named::Tab.value, Mods::None, nil}
      when 0x7f   then {Named::Backspace.value, Mods::None, nil}
      when 0x00   then {32, Mods::Ctrl, nil}
      when 1..26  then {char.ord + 96, Mods::Ctrl, nil}
      when 28..31 then {char.ord + 64, Mods::Ctrl, nil}
      else
        lower = char.downcase
        {lower.ord, lower == char ? Mods::None : Mods::Shift, char.to_s}
      end
    mods |= extra
    shifted = char.ord if text && mods.shift?
    tapped(Key.new(code, Key::Action::Press, mods, shifted, nil, mods.alt? ? nil : text))
  end

  private def tapped(key : Key) : Nil
    push key
    push key.copy_with(action: Key::Action::Release, text: nil)
  end

  private def text : Nil
    case @string
    when 0x5d then osc
    when 0x5f then apc
    end
  rescue Base64::Error | ArgumentError
  end

  private def parse(bytes : Bytes) : Nil
    @values.clear
    @starts.clear
    @starts << 0
    current  = MISSING
    negative = false
    bytes.each do |byte|
      case byte
      when 0x30..0x39
        current = (current == MISSING ? 0 : current) &* 10 &+ (byte &- 0x30)
      when 0x2d
        negative = true
      when 0x3a, 0x3b
        @values << (negative && current != MISSING ? -current : current)
        current  = MISSING
        negative = false
        @starts << @values.size if byte == 0x3b
      end
    end
    @values << (negative && current != MISSING ? -current : current)
  end

  private def param(group : Int32, sub : Int32 = 0, default : Int32 = MISSING) : Int32
    start = @starts[group]? || return default
    stop  = @starts[group + 1]? || @values.size
    index = start + sub
    return default unless index < stop
    value = @values[index]
    value == MISSING ? default : value
  end

  private def csi(final : UInt8) : Nil
    bytes  = @seq.written
    letter = final.unsafe_chr
    parse(bytes)
    case bytes.first?.try(&.unsafe_chr)
    when '<'
      mouse(letter == 'm') if letter.in?('M', 'm')
    when '?'
      case letter
      when 'c'
        route(Query::Attributes, nil, strict: true)
      when 'u'
        route(Query::Mode, 1, "u")
      when 'y'
        route(Query::Mode, param(1, 0, 0), param(0, 0, 0).to_s)
      when 'n'
        case param(0)
        when 997 then push ColorScheme.new(param(1) == 1)
        when 999 then push Visibility.new(param(1) == 1)
        end
      end
    when '>', '='
      nil
    else
      case letter
      when 'u' then key(param(0, 0, 0))
      when '~' then tilde
      when 'I' then push Focus.new(true)
      when 'O' then push Focus.new(false)
      when 't' then report
      else          LETTERS[letter]?.try { |named| key(named.value) }
      end
    end
  end

  private def tilde : Nil
    if param(0) == 200
      @seq.reset
      @state = State::Paste
    else
      TILDES[param(0)]?.try { |named| key(named.value) }
    end
  end

  private def report : Nil
    case param(0)
    when 48
      resize
    when 4
      route(Query::Window, Size.new(param(2, 0, 0), param(1, 0, 0)))
    when 6
      @cell_height.set(param(1, 0, 0))
      @cell_width.set(param(2, 0, 0))
      route(Query::Cell, Size.new(@cell_width.get, @cell_height.get))
    end
  end

  private def key(code : Int32) : Nil
    mods    = Mods.new((param(1, 0, 1) &- 1).to_u8!)
    action  = Key::Action.from_value?(param(1, 1, 1)) || Key::Action::Press
    shifted = param(0, 1, 0)
    base    = param(0, 2, 0)
    text = if @starts.size > 2
             @scratch.reset
             (@starts[2]...@values.size).each do |index|
               char(@values[index]).try { |char| @scratch.char(char) }
             end
             String.new(@scratch.written) unless @scratch.empty?
           end
    key = Key.new(code, action, mods, shifted > 0 ? shifted : nil, base > 0 ? base : nil, text)
    features.keyboard? ? push(key) : tapped(key)
  end

  private def char(value : Int32) : Char?
    value.unsafe_chr if 0 < value <= Char::MAX_CODEPOINT && !(0xd800..0xdfff).includes?(value)
  end

  private def mouse(release : Bool) : Nil
    pb  = param(0, 0, 0)
    x   = param(1, 0, 0)
    y   = param(2, 0, 0)
    low = pb & 3
    action, button =
      if pb.bits_set?(256)
        {Mouse::Action::Leave, Mouse::Button::None}
      elsif pb.bits_set?(64)
        {Mouse::Action::Scroll, Mouse::Button.new(4 + low)}
      elsif pb.bits_set?(32) && low == 3
        {Mouse::Action::Hover, Mouse::Button::None}
      elsif release
        {Mouse::Action::Release, Mouse::Button.new(pb.bits_set?(128) ? 8 + low : low)}
      elsif pb.bits_set?(32)
        {Mouse::Action::Drag, Mouse::Button.new(pb.bits_set?(128) ? 8 + low : low)}
      else
        {Mouse::Action::Press, Mouse::Button.new(pb.bits_set?(128) ? 8 + low : low)}
      end
    width  = @cell_width.get
    height = @cell_height.get
    if features.pixels?
      col = width > 0 ? x // width : 0
      row = height > 0 ? y // height : 0
    else
      col = {x - 1, 0}.max
      row = {y - 1, 0}.max
      x   = col * {width, 1}.max
      y   = row * {height, 1}.max
    end
    push Mouse.new(action, button, Mods.new(((pb >> 2) & 7).to_u8!), x, y, col, row)
  end

  private def resize : Nil
    rows   = param(1, 0, 0)
    cols   = param(2, 0, 0)
    height = param(3, 0, 0)
    width  = param(4, 0, 0)
    @cell_width.set(cols > 0 ? width // cols : 0)
    @cell_height.set(rows > 0 ? height // rows : 0)
    push Resize.new(rows, cols, height, width)
  end

  private def fields(bytes : Bytes, separator : UInt8 = 0x3a_u8) : Hash(String, String)
    result = {} of String => String
    reader = Bytewire::Reader.new(bytes)
    until reader.eof?
      pair = reader.take_until?(separator) || reader.take_rest
      reader.byte?
      next if pair.empty?
      sub   = Bytewire::Reader.new(pair)
      name  = sub.take_until?(0x3d_u8) || sub.take_rest
      value = sub.match?(0x3d_u8) ? sub.take_rest : Bytes.empty
      result[String.new(name).strip] = String.new(value).strip
    end
    result
  end

  private def fields(text : String, separator : Char = ':') : Hash(String, String)
    fields(text.to_slice, separator.ord.to_u8)
  end

  private def number(meta : Hash(String, String), name : String) : Int32
    meta[name]?.try(&.to_i?) || 0
  end

  private def osc : Nil
    @reader.reset(@seq.written)
    code = @reader.int?(Int32) || return
    return unless @reader.semi?
    case code
    when 22
      route(Query::Shape, String.new(@reader.take_rest))
    when 21
      route(Query::Color, decode_colors(@reader.take_rest))
    when 5522, 99, DND
      meta    = @reader.take_until?(0x3b_u8) || @reader.take_rest
      payload = @reader.semi? ? String.new(@reader.take_rest) : ""
      parsed  = fields(meta)
      case code
      when 5522 then clipboard(parsed, payload)
      when 99   then notified(parsed, payload)
      when DND  then chained(parsed, payload)
      end
    end
  end

  private def apc : Nil
    @reader.reset(@seq.written)
    return unless @reader.match?('G')
    control = @reader.take_until?(0x3b_u8) || @reader.take_rest
    message = @reader.semi? ? String.new(@reader.take_rest) : ""
    meta    = fields(control, 0x2c_u8)
    ack     = Ack.new(meta["i"]?.try(&.to_u32?) || 0_u32, meta["I"]?.try(&.to_u32?) || 0_u32, meta["p"]?.try(&.to_u32?) || 0_u32, message)
    route(Query::Graphics, ack, ack.number != 0 ? "I#{ack.number}" : "i#{ack.image}") || push(ack)
  end
end
