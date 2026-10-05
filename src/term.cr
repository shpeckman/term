# src/term.cr
require "base64"
require "uuid"

class Term
  ST         = "\e\\"
  ID         = "term"
  PASTE_NAME = "UGFzdGUgZXZlbnQ="
  CHUNK      = 4095
  MISSING    = Int32::MIN
  CSI_LIMIT  = 256
  OSC_LIMIT  = 1 << 24
  POLL       = 100.milliseconds
  IDLE       = 1.hour
  SCREEN     = {"\e[?1049h", "\e[?1049l"}
  MODES      = [
    {"\e[>31u",        "\e[<u"},
    {"\e[?2048h",      "\e[?2048l"},
    {"\e[?1003;1016h", "\e[?1003;1016l"},
    {"\e[?1004h",      "\e[?1004l"},
    {"\e[?2033h",      "\e[?2033l"},
    {"\e[?2031h",      "\e[?2031l"},
    {"\e[?5522h",      "\e[?5522l"},
  ]

  @[Flags]
  enum Mods : UInt8
    Shift
    Alt
    Ctrl
    Super
    Hyper
    Meta
    CapsLock
    NumLock
  end

  enum Named
    Tab       =     9
    Enter     =    13
    Escape    =    27
    Backspace =   127
    Insert    = 57348
    Delete
    Left
    Right
    Up
    Down
    PageUp
    PageDown
    Home
    End
    CapsLock
    ScrollLock
    NumLock
    PrintScreen
    Pause
    Menu
    {% for index in 1..35 %}
      F{{ index }}
    {% end %}
    {% for index in 0..9 %}
      Kp{{ index }}
    {% end %}
    KpDecimal
    KpDivide
    KpMultiply
    KpSubtract
    KpAdd
    KpEnter
    KpEqual
    KpSeparator
    KpLeft
    KpRight
    KpUp
    KpDown
    KpPageUp
    KpPageDown
    KpHome
    KpEnd
    KpInsert
    KpDelete
    KpBegin
    MediaPlay
    MediaPause
    MediaPlayPause
    MediaReverse
    MediaStop
    MediaFastForward
    MediaRewind
    MediaTrackNext
    MediaTrackPrevious
    MediaRecord
    LowerVolume
    RaiseVolume
    MuteVolume
    LeftShift
    LeftControl
    LeftAlt
    LeftSuper
    LeftHyper
    LeftMeta
    RightShift
    RightControl
    RightAlt
    RightSuper
    RightHyper
    RightMeta
    IsoLevel3Shift
    IsoLevel5Shift
  end

  COMMAND   = Mods::Ctrl | Mods::Super | Mods::Hyper | Mods::Meta
  LOCKS     = Mods::CapsLock | Mods::NumLock
  MODIFIERS = Named::LeftShift.value..Named::IsoLevel5Shift.value

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

  enum Shape
    Alias
    Cell
    Copy
    Crosshair
    Default
    EResize
    EwResize
    Grab
    Grabbing
    Help
    Move
    NResize
    NeResize
    NeswResize
    NoDrop
    NotAllowed
    NsResize
    NwResize
    NwseResize
    Pointer
    Progress
    SResize
    SeResize
    SwResize
    Text
    VerticalText
    WResize
    Wait
    ZoomIn
    ZoomOut

    def wire : String
      to_s.underscore.tr("_", "-")
    end
  end

  enum ShapeQuery
    Current
    Default
    Grabbed

    def wire : String
      "__#{to_s.downcase}__"
    end
  end

  enum Status
    Done
    EIO
    EINVAL
    ENOSYS
    EPERM
    EBUSY
    EFBIG
  end

  enum Query
    Shape
    Color
    ClipboardRead
    ClipboardWrite
    Mode
  end

  enum State
    Ground
    Escape
    Csi
    Osc
    OscEscape
  end

  enum Direction
    Left
    Right
    Up
    Down
  end

  record Key, code : Int32, action : Action, mods : Mods, shifted : Int32?, base : Int32?, text : String? do
    enum Action
      Press   = 1
      Repeat
      Release
    end

    delegate shift?, alt?, ctrl?, to: @mods
    delegate press?, repeat?, release?, to: @action

    def named : Named?
      Named.from_value?(code)
    end

    def char : Char?
      code.unsafe_chr if code > 0 && named.nil?
    end

    def modifier? : Bool
      MODIFIERS.includes?(code)
    end

    def command? : Bool
      text.nil? || !(mods & COMMAND).none?
    end
  end

  record Mouse, action : Action, button : Button, mods : Mods, x : Int32, y : Int32, col : Int32, row : Int32 do
    enum Action
      Press
      Release
      Drag
      Hover
      Scroll
      Leave
    end

    enum Button
      Left
      Middle
      Right
      None
      WheelUp
      WheelDown
      WheelLeft
      WheelRight
      Aux8
      Aux9
      Aux10
      Aux11
    end

    delegate shift?, alt?, ctrl?, to: @mods
  end

  record Resize, rows : Int32, cols : Int32, height : Int32, width : Int32
  record Focus, gained : Bool
  record Visibility, visible : Bool
  record ColorScheme, dark : Bool
  record Paste, mimes : Array(String), primary : Bool, password : String?
  record TextInput, text : String
  record TypingMetric, code : Int32, dwell : Time::Span, latency : Time::Span, overlap : Int32

  record KeyGesture, kind : Kind, key : Key, count : Int32 = 1 do
    enum Kind
      Activate
      AutoRepeat
      Tap
      HoldStart
      HoldEnd
      HoldReached
      ModifierTap
    end
  end

  record Binding, kind : Kind, name : String do
    enum Kind
      Chord
      Sequence
      Shortcut
    end
  end

  record MouseGesture, kind : Kind, mouse : Mouse, count : Int32 = 1, dx : Int32 = 0, dy : Int32 = 0, velocity : Float64 = 0.0 do
    enum Kind
      Click
      DragStart
      DragMove
      DragEnd
      Enter
      HoverDwell
      HoverEnd
      Motion
      Scroll
      Swipe
      Chord
      LongPress
    end

    def direction : Direction
      if dx.abs >= dy.abs
        dx < 0 ? Direction::Left : Direction::Right
      else
        dy < 0 ? Direction::Up : Direction::Down
      end
    end
  end

  record Color, red : UInt16, green : UInt16, blue : UInt16, alpha : Float64 = 1.0 do
    def self.rgb(red : UInt8, green : UInt8, blue : UInt8, alpha : Float64 = 1.0) : Color
      new(red.to_u16 * 257, green.to_u16 * 257, blue.to_u16 * 257, alpha)
    end

    def self.parse(text : String) : Color?
      body, _, alpha = text.partition('@')
      opacity = alpha.empty? ? 1.0 : alpha.to_f?
      return unless opacity
      parts =
        if body.starts_with?("rgbi:")
          body.lchop("rgbi:").split('/').map do |part|
            part.to_f?.try { |value| (value.clamp(0.0, 1.0) * 0xffff).round.to_u16 }
          end
        elsif body.starts_with?("rgb:")
          body.lchop("rgb:").split('/').map { |part| scaled(part) }
        elsif body.starts_with?('#') && body.size.in?(4, 7, 10, 13)
          width = body.size // 3
          (0...3).map do |index|
            body[1 + index * width, width].to_u16?(16).try { |value| value << (16 - 4 * width) }
          end
        end
      return unless parts && parts.size == 3
      red, green, blue = parts
      return unless red && green && blue
      new(red, green, blue, opacity)
    end

    def self.scaled(digits : String) : UInt16?
      return unless digits.size.in?(1..4)
      digits.to_u32?(16).try do |value|
        (value * 0xffff // ((1_u32 << (4 * digits.size)) - 1)).to_u16
      end
    end

    def to_s(io : IO) : Nil
      io << "rgb:"
      {red, green, blue}.each_with_index do |channel, index|
        io << '/' unless index == 0
        io << channel.to_s(16).rjust(4, '0')
      end
      io << '@' << alpha unless alpha == 1.0
    end
  end

  record Clipboard, status : Status, data : Hash(String, Bytes) do
    delegate done?, to: @status

    def text : String?
      data["text/plain"]?.try { |bytes| String.new(bytes) }
    end
  end

  record Shortcut, code : Int32, mods : Mods, physical : Bool
  record Timer, at : Time::Span, kind : Kind, code : Int32 do
    enum Kind
      Hold
      Sequence
      Dwell
      LongPress
      Scroll
    end
  end

  alias Raw = Key | Mouse | Resize | Focus | Visibility | ColorScheme | Paste
  alias Event = Raw | TextInput | TypingMetric | KeyGesture | Binding | MouseGesture
  alias Reply = String | Int32 | Status | Clipboard | Hash(String, Color?)

  record Request, query : Query, sequence : String, waiter : Channel(Reply)

  alias Output = String | Request

  struct Config
    property alternate_screen = true
    property app_name : String? = nil
    property event_buffer       = 1024
    property query_timeout      = 1.second
    property clipboard_timeout  = 30.seconds
    property hold_repeats       = 3
    property hold_after         = 500.milliseconds
    property multi_tap_window   = 300.milliseconds
    property sequence_timeout   = 1.second
    property click_radius       = 4
    property click_window       = 300.milliseconds
    property multi_click_window = 400.milliseconds
    property long_press_after   = 500.milliseconds
    property hover_dwell_after  = 500.milliseconds
    property scroll_window      = 50.milliseconds
    property swipe_velocity     = 500.0
    getter chords    = {} of String => Array(Int32)
    getter sequences = {} of String => Array(Int32)
    getter shortcuts = {} of String => Shortcut

    def chord(name : String, *keys : Char | Named | Int32) : self
      @chords[name] = keys.map { |key| Term.code(key) }.to_a
      self
    end

    def sequence(name : String, *keys : Char | Named | Int32) : self
      @sequences[name] = keys.map { |key| Term.code(key) }.to_a
      self
    end

    def shortcut(name : String, key : Char | Named | Int32, mods : Mods = Mods::None, physical : Bool = false) : self
      @shortcuts[name] = Shortcut.new(Term.code(key), mods, physical)
      self
    end
  end

  private class Held
    getter key     : Key
    getter at      : Time::Span
    getter latency : Time::Span
    getter overlap : Int32
    property repeats = 0
    property? holding = false

    def initialize(@key, @at, @latency, @overlap)
    end
  end

  private class Node
    getter children = {} of Int32 => Node
    property action : String?
  end

  private class Transfer
    getter data = {} of String => IO::Memory
    getter? solicited : Bool
    getter? primary   : Bool
    getter password   : String?
    @carry = ""

    def initialize(@solicited, @primary, @password)
    end

    def add(mime : String, chunk : String) : Nil
      io = @data.put_if_absent(mime) { IO::Memory.new }
      @carry += chunk
      return unless @carry.bytesize % 4 == 0
      encoded = @carry
      @carry  = ""
      Base64.decode(encoded, io)
    end
  end

  def self.code(key : Char | Named | Int32) : Int32
    case key
    in Char  then key.ord
    in Named then key.value
    in Int32 then key
    end
  end

  def self.open(config : Config = Config.new, input : IO::FileDescriptor = STDIN, output : IO::FileDescriptor = STDOUT, & : Term ->)
    term = new(config, input, output)
    begin
      yield term
    ensure
      term.close
    end
  end

  getter events : Channel(Event)
  getter output : Channel(Output)

  @state       = State::Ground
  @seq         = IO::Memory.new
  @values      = [] of Int32
  @starts      = [] of Int32
  @cell_width  = 0
  @cell_height = 0
  @transfer : Transfer?

  @held     = {} of Int32 => Held
  @latched  = Set(String).new
  @lone     = Set(Int32).new
  @timers   = [] of Timer
  @physical = {} of {Int32, Mods} => String
  @symbolic = {} of {Int32, Mods} => String
  @root     = Node.new
  @node : Node
  @last_press = Time::Span.zero
  @tap_code   = 0
  @tap_at     = Time::Span.zero
  @tap_count  = 0

  @buttons = Set(Mouse::Button).new
  @press : Mouse?
  @press_at = Time::Span.zero
  @last : Mouse?
  @last_at = Time::Span.zero
  @click : Mouse?
  @click_at    = Time::Span.zero
  @click_count = 0
  @scroll : Mouse?
  @scroll_at    = Time::Span.zero
  @scroll_from  = Time::Span.zero
  @scroll_count = 0
  @dragging     = false
  @inside       = false
  @dwelling     = false

  def initialize(@config : Config = Config.new, @input : IO::FileDescriptor = STDIN, @io : IO::FileDescriptor = STDOUT)
    @events      = Channel(Event).new(@config.event_buffer)
    @output      = Channel(Output).new(256)
    @raw         = Channel(Raw).new(256)
    @stop        = Channel(Nil).new
    @reader_done = Channel(Nil).new
    @writer_done = Channel(Nil).new
    @waiters     = Query.values.to_h { |query| {query, Channel(Channel(Reply)).new(32)} }
    @credentials = @config.app_name.try do |name|
      ":pw=#{Base64.strict_encode(UUID.random.to_s)}:name=#{Base64.strict_encode(name)}"
    end || ""
    @node = @root
    @config.sequences.each do |name, codes|
      codes.reduce(@root) { |node, code| node.children.put_if_absent(code) { Node.new } }.action = name
    end
    @config.shortcuts.each do |name, shortcut|
      (shortcut.physical ? @physical : @symbolic)[{shortcut.code, shortcut.mods}] = name
    end
    modes     = @config.alternate_screen ? [SCREEN] + MODES : MODES
    @teardown = modes.reverse.join(&.[1])
    @input.raw! if @input.tty?
    @input.read_timeout = POLL
    @output.send(modes.join(&.[0]))
    spawn(name: "term.writer") { run_writer }
    spawn(name: "term.reader") { run_reader }
    spawn(name: "term.engine") { run_engine }
  end

  def close : Nil
    return if @stop.closed?
    @stop.close
    begin
      @output.send(@teardown)
    rescue Channel::ClosedError
    end
    @output.close
    @writer_done.receive?
    @events.close
    @reader_done.receive?
    @input.read_timeout = nil
    @input.cooked! if @input.tty?
  end

  def closed? : Bool
    @stop.closed?
  end

  def print(*objects) : Nil
    @output.send(objects.join)
  end

  def <<(object) : self
    @output.send(object.to_s)
    self
  end

  def pointer=(shape : Shape) : Shape
    @output.send("\e]22;=#{shape.wire}#{ST}")
    shape
  end

  def reset_pointer : Nil
    @output.send("\e]22;#{ST}")
  end

  def push_pointer(*shapes : Shape) : Nil
    @output.send("\e]22;>#{shapes.join(',', &.wire)}#{ST}")
  end

  def pop_pointer : Nil
    @output.send("\e]22;<#{ST}")
  end

  def pointer(which : ShapeQuery = :current) : String?
    reply = request(Query::Shape, "\e]22;?#{which.wire}#{ST}").as?(String)
    reply unless reply == "0"
  end

  def pointer_support(*shapes : Shape) : Array(Bool)?
    request(Query::Shape, "\e]22;?#{shapes.join(',', &.wire)}#{ST}").as?(String).try do |reply|
      reply.split(',').map { |flag| flag == "1" }
    end
  end

  def push_colors : Nil
    @output.send("\e]30001#{ST}")
  end

  def pop_colors : Nil
    @output.send("\e]30101#{ST}")
  end

  def color(key : String | Int32, value : Color | String) : Nil
    @output.send("\e]21;#{key}=#{value}#{ST}")
  end

  def dynamic_color(key : String | Int32) : Nil
    @output.send("\e]21;#{key}=#{ST}")
  end

  def reset_color(key : String | Int32) : Nil
    @output.send("\e]21;#{key}#{ST}")
  end

  def colors(*keys : String | Int32) : Hash(String, Color?)?
    query = keys.join(';') { |key| "#{key}=?" }
    request(Query::Color, "\e]21;#{query}#{ST}").as?(Hash(String, Color?))
  end

  def copy(text : String, primary : Bool = false, limit : Time::Span = @config.clipboard_timeout) : Status?
    clipboard_write({"text/plain" => text.to_slice}, primary: primary, limit: limit)
  end

  def clipboard_write(items : Hash(String, Bytes), aliases : Hash(String, Array(String)) = {} of String => Array(String), primary : Bool = false, limit : Time::Span = @config.clipboard_timeout) : Status?
    sequence = String.build do |io|
      io << "\e]5522;type=write" << location(primary) << @credentials << ST
      items.each do |mime, data|
        encoded = Base64.strict_encode(mime)
        offset  = 0
        loop do
          io << "\e]5522;type=wdata:mime=" << encoded << ';'
          Base64.strict_encode(data[offset, Math.min(CHUNK, data.size - offset)], io)
          io << ST
          offset += CHUNK
          break if offset >= data.size
        end
      end
      aliases.each do |target, names|
        io << "\e]5522;type=walias:mime=" << Base64.strict_encode(target) << ';'
        io << Base64.strict_encode(names.join(' ')) << ST
      end
      io << "\e]5522;type=wdata" << ST
    end
    request(Query::ClipboardWrite, sequence, limit).as?(Status)
  end

  def clipboard_read(*mimes : String, primary : Bool = false, limit : Time::Span = @config.clipboard_timeout) : Clipboard?
    fetch("#{location(primary)}#{@credentials}", mimes.join(' '), limit)
  end

  def clipboard_read(paste : Paste, *mimes : String, limit : Time::Span = @config.clipboard_timeout) : Clipboard?
    credentials = paste.password.try { |password| ":pw=#{password}:name=#{PASTE_NAME}" }
    fetch("#{location(paste.primary)}#{credentials}", mimes.join(' '), limit)
  end

  def clipboard_mimes(primary : Bool = false, limit : Time::Span = @config.clipboard_timeout) : Array(String)?
    fetch(location(primary), ".", limit).try do |clipboard|
      clipboard.data["."]?.try { |bytes| String.new(bytes).split }
    end
  end

  def supports?(mode : Int32) : Bool?
    request(Query::Mode, "\e[?#{mode}$p").as?(Int32).try { |state| !state.in?(0, 4) }
  end

  def query_visibility : Nil
    @output.send("\e[?998n")
  end

  def query_color_scheme : Nil
    @output.send("\e[?996n")
  end

  private def location(primary : Bool) : String
    primary ? ":loc=primary" : ""
  end

  private def fetch(meta : String, mimes : String, limit : Time::Span) : Clipboard?
    sequence = "\e]5522;type=read:id=#{ID}#{meta};#{Base64.strict_encode(mimes)}#{ST}"
    request(Query::ClipboardRead, sequence, limit).as?(Clipboard)
  end

  private def request(query : Query, sequence : String, limit : Time::Span = @config.query_timeout) : Reply?
    waiter = Channel(Reply).new(1)
    @output.send(Request.new(query, sequence, waiter))
    select
    when reply = waiter.receive
      reply
    when timeout(limit)
      waiter.close
      nil
    end
  end

  private def route(query : Query, reply : Reply) : Nil
    queue = @waiters[query]
    loop do
      select
      when waiter = queue.receive
        next if waiter.closed?
        waiter.send(reply)
        break
      else
        break
      end
    end
  rescue Channel::ClosedError
  end

  private def run_writer : Nil
    while item = @output.receive?
      transmit(item)
      loop do
        select
        when more = @output.receive?
          break unless more
          transmit(more)
        else
          break
        end
      end
      @io.flush
    end
  rescue IO::Error
  ensure
    @output.close
    @writer_done.close
  end

  private def transmit(item : Output) : Nil
    case item
    in String
      @io << item
    in Request
      @waiters[item.query].send(item.waiter)
      @io << item.sequence
    end
  end

  private def run_reader : Nil
    buffer = Bytes.new(4096)
    until @stop.closed?
      count = begin
        @input.read(buffer)
      rescue IO::TimeoutError
        next
      end
      break if count == 0
      buffer[0, count].each { |byte| feed(byte) }
    end
  rescue Channel::ClosedError | IO::Error
  ensure
    @raw.close
    @reader_done.close
  end

  private def push(event : Raw) : Nil
    @raw.send(event)
  end

  private def feed(byte : UInt8) : Nil
    case @state
    in .ground?
      @state = State::Escape if byte == 0x1b
    in .escape?
      @seq.clear
      @state = case byte
               when 0x5b then State::Csi
               when 0x5d then State::Osc
               when 0x1b then State::Escape
               else           State::Ground
               end
    in .csi?
      case byte
      when 0x20..0x3f
        @seq.write_byte(byte)
        @state = State::Ground if @seq.size > CSI_LIMIT
      when 0x40..0x7e
        @state = State::Ground
        csi(byte)
      when 0x1b
        @state = State::Escape
      else
        @state = State::Ground
      end
    in .osc?
      case byte
      when 0x07
        @state = State::Ground
        osc
      when 0x1b
        @state = State::OscEscape
      else
        @seq.write_byte(byte)
        @state = State::Ground if @seq.size > OSC_LIMIT
      end
    in .osc_escape?
      if byte == 0x5c
        @state = State::Ground
        osc
      else
        @state = State::Escape
        feed(byte)
      end
    end
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
    bytes  = @seq.to_slice
    letter = final.unsafe_chr
    parse(bytes)
    case bytes.first?.try(&.unsafe_chr)
    when '<'
      mouse(letter == 'm') if letter.in?('M', 'm')
    when '?'
      case letter
      when 'y'
        route(Query::Mode, param(1, 0, 0))
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
      when '~' then TILDES[param(0)]?.try { |named| key(named.value) }
      when 'I' then push Focus.new(true)
      when 'O' then push Focus.new(false)
      when 't' then resize if param(0) == 48
      else          LETTERS[letter]?.try { |named| key(named.value) }
      end
    end
  end

  private def key(code : Int32) : Nil
    mods    = Mods.new((param(1, 0, 1) &- 1).to_u8!)
    action  = Key::Action.from_value?(param(1, 1, 1)) || Key::Action::Press
    shifted = param(0, 1, 0)
    base    = param(0, 2, 0)
    text = if @starts.size > 2
             String.build do |io|
               (@starts[2]...@values.size).each do |index|
                 char(@values[index]).try { |char| io << char }
               end
             end.presence
           end
    push Key.new(code, action, mods, shifted > 0 ? shifted : nil, base > 0 ? base : nil, text)
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
    col = @cell_width > 0 ? x // @cell_width : 0
    row = @cell_height > 0 ? y // @cell_height : 0
    push Mouse.new(action, button, Mods.new(((pb >> 2) & 7).to_u8!), x, y, col, row)
  end

  private def resize : Nil
    rows         = param(1, 0, 0)
    cols         = param(2, 0, 0)
    height       = param(3, 0, 0)
    width        = param(4, 0, 0)
    @cell_width  = cols > 0 ? width // cols : 0
    @cell_height = rows > 0 ? height // rows : 0
    push Resize.new(rows, cols, height, width)
  end

  private def osc : Nil
    number, _, body = String.new(@seq.to_slice).partition(';')
    case number
    when "22"
      route(Query::Shape, body)
    when "21"
      route(Query::Color, decode_colors(body))
    when "5522"
      meta, _, payload = body.partition(';')
      fields = meta.split(':').to_h do |pair|
        name, _, value = pair.partition('=')
        {name, value}
      end
      clipboard(fields, payload)
    end
  end

  private def decode_colors(body : String) : Hash(String, Color?)
    body.split(';').each_with_object({} of String => Color?) do |pair, colors|
      name, _, value = pair.partition('=')
      colors[name] = Color.parse(value) unless name == "unknown"
    end
  end

  private def clipboard(meta : Hash(String, String), payload : String) : Nil
    status = meta["status"]? || return
    case meta["type"]?
    when "write"
      route(Query::ClipboardWrite, Status.parse?(status) || Status::EIO)
    when "read"
      case status
      when "OK"
        @transfer = Transfer.new(meta.has_key?("id"), meta["loc"]? == "primary", meta["pw"]?)
      when "DATA"
        @transfer.try &.add(Base64.decode_string(meta["mime"]? || ""), payload)
      when "DONE"
        finish
      else
        route(Query::ClipboardRead, Clipboard.new(Status.parse?(status) || Status::EIO, {} of String => Bytes))
      end
    end
  rescue Base64::Error
  end

  private def finish : Nil
    transfer  = @transfer || return
    @transfer = nil
    data      = transfer.data.transform_values(&.to_slice)
    if transfer.solicited?
      route(Query::ClipboardRead, Clipboard.new(Status::Done, data))
    else
      mimes = data["."]?.try { |bytes| String.new(bytes).split } || [] of String
      push Paste.new(mimes, transfer.primary?, transfer.password)
    end
  end

  private def run_engine : Nil
    loop do
      select
      when raw = @raw.receive?
        break unless raw
        track(raw, Time.monotonic)
      when timeout(patience)
        nil
      end
      now = Time.monotonic
      @timers.reject! do |timer|
        next false if timer.at > now
        fire(timer)
        true
      end
    end
  rescue Channel::ClosedError
  ensure
    @events.close
    @raw.close
  end

  private def patience : Time::Span
    deadline = @timers.min_of?(&.at) || return IDLE
    {deadline - Time.monotonic, Time::Span.zero}.max
  end

  private def emit(event : Event) : Nil
    @events.send(event)
  end

  private def arm(kind : Timer::Kind, now : Time::Span, delay : Time::Span, code : Int32 = 0) : Nil
    @timers.reject! { |timer| timer.kind == kind && timer.code == code }
    @timers << Timer.new(now + delay, kind, code)
  end

  private def fire(timer : Timer) : Nil
    case timer.kind
    in .hold?
      @held[timer.code]?.try { |held| hold(held) }
    in .sequence?
      @node = @root
    in .dwell?
      last = @last
      if last && @inside && !@dwelling
        @dwelling = true
        emit MouseGesture.new(:hover_dwell, last)
      end
    in .long_press?
      press = @press
      emit MouseGesture.new(:long_press, press) if press && !@dragging
    in .scroll?
      flush_scroll
    end
  end

  private def track(raw : Raw, now : Time::Span) : Nil
    emit raw
    case raw
    when Key   then track_key(raw, now)
    when Mouse then track_mouse(raw, now)
    end
  end

  private def track_key(key : Key, now : Time::Span) : Nil
    unless key.command? || key.release?
      key.text.try { |text| emit TextInput.new(text) }
    end
    case key.action
    in .press?   then pressed(key, now)
    in .repeat?  then repeated(key)
    in .release? then released(key, now)
    end
  end

  private def pressed(key : Key, now : Time::Span) : Nil
    code = key.code
    @held[code] = Held.new(key, now, now - @last_press, @held.size)
    @last_press = now
    arm(:hold, now, @config.hold_after, code)
    emit KeyGesture.new(:activate, key)
    @config.chords.each do |name, codes|
      next if @latched.includes?(name) || !codes.all? { |member| @held.has_key?(member) }
      @latched << name
      emit Binding.new(:chord, name)
    end
    if key.modifier?
      @lone << code
    else
      @lone.clear
      advance(code, now)
    end
    shortcut(key)
  end

  private def repeated(key : Key) : Nil
    held = @held[key.code]? || return
    held.repeats += 1
    hold(held)
    emit KeyGesture.new(:hold_reached, key, held.repeats) if held.repeats == @config.hold_repeats
    emit KeyGesture.new(:auto_repeat, key, held.repeats)
  end

  private def released(key : Key, now : Time::Span) : Nil
    code = key.code
    if held = @held.delete(code)
      if held.holding?
        emit KeyGesture.new(:hold_end, key)
      else
        again      = code == @tap_code && now - @tap_at < @config.multi_tap_window
        @tap_count = again ? @tap_count + 1 : 1
        @tap_code  = code
        @tap_at    = now
        emit KeyGesture.new(:tap, key, @tap_count)
      end
      emit TypingMetric.new(code, now - held.at, held.latency, held.overlap)
    end
    @latched.reject! do |name|
      !@config.chords[name].all? { |member| @held.has_key?(member) }
    end
    emit KeyGesture.new(:modifier_tap, key) if @lone.delete(code)
  end

  private def hold(held : Held) : Nil
    return if held.holding?
    held.holding = true
    emit KeyGesture.new(:hold_start, held.key)
  end

  private def advance(code : Int32, now : Time::Span) : Nil
    node = @node.children[code]? || @root.children[code]? || @root
    if name = node.action
      emit Binding.new(:sequence, name)
      node = @root
    end
    @node = node
    arm(:sequence, now, @config.sequence_timeout) unless node.same?(@root)
  end

  private def shortcut(key : Key) : Nil
    mods     = key.mods & ~LOCKS
    shifted  = key.shifted if mods.shift?
    physical = @physical[{key.base || key.code, mods}]?
    symbolic = @symbolic[{shifted || key.code, shifted ? mods & ~Mods::Shift : mods}]?
    emit Binding.new(:shortcut, physical) if physical
    emit Binding.new(:shortcut, symbolic) if symbolic
  end

  private def track_mouse(mouse : Mouse, now : Time::Span) : Nil
    if mouse.action.leave?
      @inside = false
      stir(@last || mouse)
      return
    end
    unless @inside
      @inside = true
      emit MouseGesture.new(:enter, mouse)
    end
    case mouse.action
    when .hover?
      moved(mouse, now)
    when .drag?
      moved(mouse, now)
      origin    = @press || mouse
      kind      = @dragging ? MouseGesture::Kind::DragMove : MouseGesture::Kind::DragStart
      @dragging = true
      emit MouseGesture.new(kind, mouse, 1, mouse.x - origin.x, mouse.y - origin.y)
    when .press?
      @buttons << mouse.button
      emit MouseGesture.new(:chord, mouse, @buttons.size) if @buttons.size > 1
      @press    = mouse
      @press_at = now
      @dragging = false
      arm(:long_press, now, @config.long_press_after)
    when .release?
      lifted(mouse, now)
    when .scroll?
      scrolled(mouse, now)
    end
    @last    = mouse
    @last_at = now
  end

  private def moved(mouse : Mouse, now : Time::Span) : Nil
    if last = @last
      dx = mouse.x - last.x
      dy = mouse.y - last.y
      emit MouseGesture.new(:motion, mouse, 1, dx, dy, speed(dx, dy, now - @last_at))
    end
    stir(mouse)
    arm(:dwell, now, @config.hover_dwell_after)
  end

  private def lifted(mouse : Mouse, now : Time::Span) : Nil
    @buttons.delete(mouse.button)
    press     = @press
    dragging  = @dragging
    @press    = nil
    @dragging = false
    return unless press
    dx = mouse.x - press.x
    dy = mouse.y - press.y
    if dragging
      velocity = speed(dx, dy, now - @press_at)
      emit MouseGesture.new(:drag_end, mouse, 1, dx, dy, velocity)
      emit MouseGesture.new(:swipe, mouse, 1, dx, dy, velocity) if velocity >= @config.swipe_velocity
    elsif press.button == mouse.button && near?(dx, dy) && now - @press_at <= @config.click_window
      click        = @click
      again        = click && click.button == mouse.button && now - @click_at <= @config.multi_click_window && near?(mouse.x - click.x, mouse.y - click.y)
      @click_count = again ? @click_count + 1 : 1
      @click       = mouse
      @click_at    = now
      emit MouseGesture.new(:click, mouse, @click_count)
    end
  end

  private def scrolled(mouse : Mouse, now : Time::Span) : Nil
    flush_scroll if @scroll.try(&.button) != mouse.button
    @scroll_from = now if @scroll_count == 0
    @scroll      = mouse
    @scroll_count += 1
    @scroll_at = now
    arm(:scroll, now, @config.scroll_window)
  end

  private def flush_scroll : Nil
    mouse         = @scroll || return
    count         = @scroll_count
    span          = @scroll_at - @scroll_from
    @scroll       = nil
    @scroll_count = 0
    velocity      = span > Time::Span.zero ? count / span.total_seconds : 0.0
    emit MouseGesture.new(:scroll, mouse, count, 0, 0, velocity)
  end

  private def stir(mouse : Mouse) : Nil
    return unless @dwelling
    @dwelling = false
    emit MouseGesture.new(:hover_end, mouse)
  end

  private def near?(dx : Int32, dy : Int32) : Bool
    dx * dx + dy * dy <= @config.click_radius * @config.click_radius
  end

  private def speed(dx : Int32, dy : Int32, span : Time::Span) : Float64
    span > Time::Span.zero ? Math.hypot(dx, dy) / span.total_seconds : 0.0
  end
end
