# src/term/graphics.cr
class Term
  PLACEHOLDER = '\u{10EEEE}'

  lib LibTerm
    fun shm_open(name : LibC::Char*, flags : LibC::Int, mode : LibC::ModeT) : LibC::Int
  end

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

  enum Format
    Text =   0
    RGB  =  24
    RGBA =  32
    PNG  = 100
  end

  enum Medium
    Direct
    File
    TempFile
    SharedMemory
  end

  enum Quiet
    None
    Ok
    All
  end

  enum Delete
    Visible
    Id
    Number
    Cursor
    Frames
    Cell
    CellZ
    Range
    Column
    Row
    Z
  end

  enum Playback
    Stop    = 1
    Loading
    Loop
  end

  MEDIA = {
    Medium::Direct       => 'd',
    Medium::File         => 'f',
    Medium::TempFile     => 't',
    Medium::SharedMemory => 's',
  }

  DELETES = {
    Delete::Visible => 'a',
    Delete::Id      => 'i',
    Delete::Number  => 'n',
    Delete::Cursor  => 'c',
    Delete::Frames  => 'f',
    Delete::Cell    => 'p',
    Delete::CellZ   => 'q',
    Delete::Range   => 'r',
    Delete::Column  => 'x',
    Delete::Row     => 'y',
    Delete::Z       => 'z',
  }

  record Pixels, data : Bytes | IO, format : Format = Format::RGBA, width : Int32 = 0, height : Int32 = 0, medium : Medium = Medium::Direct, compress : Bool = false, size : Int32 = 0, offset : Int32 = 0 do
    def self.png(data : Bytes | IO, compress : Bool = false) : Pixels
      new(data, Format::PNG, compress: compress)
    end

    def self.rgba(data : Bytes | IO, width : Int32, height : Int32, compress : Bool = false) : Pixels
      new(data, Format::RGBA, width, height, compress: compress)
    end

    def self.rgb(data : Bytes | IO, width : Int32, height : Int32, compress : Bool = false) : Pixels
      new(data, Format::RGB, width, height, compress: compress)
    end

    def self.at(path : String, medium : Medium = Medium::File, format : Format = Format::PNG, width : Int32 = 0, height : Int32 = 0, compress : Bool = false, size : Int32 = 0, offset : Int32 = 0) : Pixels
      new(path.to_slice, format, width, height, medium, compress, size, offset)
    end

    def self.temp(data : Bytes, format : Format = Format::PNG, width : Int32 = 0, height : Int32 = 0) : Pixels
      path = File.tempname("tty-graphics-protocol-", ".bin")
      File.write(path, data, perm: 0o600)
      at(path, Medium::TempFile, format, width, height)
    end

    def self.shared(data : Bytes, format : Format = Format::PNG, width : Int32 = 0, height : Int32 = 0) : Pixels
      name = "/tty-graphics-protocol-#{UUID.random}"
      {% if flag?(:linux) %}
        File.write("/dev/shm#{name}", data, perm: 0o600)
      {% elsif flag?(:win32) %}
        raise NotImplementedError.new("shared memory transmission")
      {% else %}
        fd = LibTerm.shm_open(name, LibC::O_CREAT | LibC::O_EXCL | LibC::O_RDWR, 0o600)
        raise IO::Error.from_errno("shm_open") if fd < 0
        begin
          raise IO::Error.from_errno("ftruncate") if LibC.ftruncate(fd, data.size) != 0
          unless data.empty?
            memory = LibC.mmap(nil, data.size, LibC::PROT_READ | LibC::PROT_WRITE, LibC::MAP_SHARED, fd, 0)
            raise IO::Error.from_errno("mmap") if memory == LibC::MAP_FAILED
            data.copy_to(memory.as(UInt8*), data.size)
            LibC.munmap(memory, data.size)
          end
        ensure
          LibC.close(fd)
        end
      {% end %}
      at(name, Medium::SharedMemory, format, width, height)
    end
  end

  record Placement, id : UInt32 = 0, x : Int32 = 0, y : Int32 = 0, width : Int32 = 0, height : Int32 = 0, offset_x : Int32 = 0, offset_y : Int32 = 0, columns : Int32 = 0, rows : Int32 = 0, z : Int32 = 0, hold_cursor : Bool = false, placeholder : Bool = false, parent : UInt32 = 0, parent_placement : UInt32 = 0, shift_x : Int32 = 0, shift_y : Int32 = 0

  record Ack, image : UInt32, number : UInt32, placement : UInt32, message : String do
    def ok? : Bool
      message == "OK"
    end

    def error : String?
      message unless ok?
    end
  end

  def self.placeholder(id : UInt32, columns : Int32, rows : Int32, placement : UInt32 = 0, compact : Bool = false) : Array(String)
    high = (id >> 24).to_i
    wire = Bytewire.new(128)
    Array.new(rows) do |row|
      wire.reset
      wire.str("\e[38;2;").int3(((id >> 16) & 255).to_i32!).semi.int3(((id >> 8) & 255).to_i32!).semi.int3((id & 255).to_i32!).char('m')
      if placement != 0
        wire.str("\e[58;2;").int3(((placement >> 16) & 255).to_i32!).semi.int3(((placement >> 8) & 255).to_i32!).semi.int3((placement & 255).to_i32!).char('m')
      end
      columns.times do |column|
        wire.char(PLACEHOLDER)
        next if compact && column > 0
        wire.char(DIACRITICS[row].unsafe_chr)
        next if compact && high == 0
        wire.char(DIACRITICS[column].unsafe_chr)
        wire.char(DIACRITICS[high].unsafe_chr) if high > 0
      end
      wire.str("\e[39m")
      wire.str("\e[59m") if placement != 0
      String.new(wire.written)
    end
  end

  def self.place_code(id : UInt32 = 0, number : UInt32 = 0, placement : Placement = Placement.new, quiet : Quiet = Quiet::None) : String
    build { |wire| wire.apc.char('G').str(place_control(id, number, placement, quiet)).st }
  end

  def self.delete_code(target : Delete = Delete::Visible, free : Bool = false, id : UInt32 = 0, number : UInt32 = 0, placement : UInt32 = 0, x : Int32 = 0, y : Int32 = 0, z : Int32 = 0) : String
    letter  = DELETES[target]
    control = keys(',', {'a', 'd'}, {'d', free ? letter.upcase : letter}, {'i', id}, {'I', number}, {'p', placement}, {'x', x}, {'y', y}, {'z', z})
    build { |wire| wire.apc.char('G').str(control).st }
  end

  protected def self.place_control(id : UInt32, number : UInt32, placement : Placement, quiet : Quiet) : String
    merge(',', keys(',', {'a', 'p'}, {'i', id}, {'I', number}, {'q', quiet.value}), placed(placement))
  end

  protected def self.placed(placement : Placement) : String
    keys(',', {'p', placement.id}, {'x', placement.x}, {'y', placement.y}, {'w', placement.width}, {'h', placement.height}, {'X', placement.offset_x}, {'Y', placement.offset_y}, {'c', placement.columns}, {'r', placement.rows}, {'z', placement.z}, {'C', placement.hold_cursor}, {'U', placement.placeholder}, {'P', placement.parent}, {'Q', placement.parent_placement}, {'H', placement.shift_x}, {'V', placement.shift_y})
  end

  def image(pixels : Pixels, id : UInt32 = 0, number : UInt32 = 0, placement : Placement? = nil, quiet : Quiet = Quiet::None, transient : Bool = false, limit : Time::Span = @config.query_timeout) : Ack?
    head, source = load(pixels)
    control = merge(',', keys(',', {'a', placement ? 'T' : 't'}, {'i', id}, {'I', number}, {'q', quiet.value}, {'N', transient}), head, placement ? placed(placement) : "")
    draw(control, source, id, number, quiet, limit)
  end

  def image_query(pixels : Pixels, id : UInt32 = 31, limit : Time::Span = @config.query_timeout) : Ack?
    head, source = load(pixels)
    draw(merge(',', keys(',', {'a', 'q'}, {'i', id}), head), source, id, 0_u32, Quiet::None, limit, probe: true)
  end

  def supports_graphics?(limit : Time::Span = @config.query_timeout) : Bool
    image_query(Pixels.rgb(Bytes.new(3), 1, 1), limit: limit).try(&.ok?) || false
  end

  def place(id : UInt32 = 0, number : UInt32 = 0, placement : Placement = Placement.new, quiet : Quiet = Quiet::None, limit : Time::Span = @config.query_timeout) : Ack?
    draw(Term.place_control(id, number, placement, quiet), Bytes.empty, id, number, quiet, limit)
  end

  def delete_images(target : Delete = Delete::Visible, free : Bool = false, id : UInt32 = 0, number : UInt32 = 0, placement : UInt32 = 0, x : Int32 = 0, y : Int32 = 0, z : Int32 = 0) : Nil
    code = Term.delete_code(target, free, id, number, placement, x, y, z)
    exclusive(Family::Graphics) { @output.send(code) }
  end

  def frame(pixels : Pixels, id : UInt32 = 0, number : UInt32 = 0, x : Int32 = 0, y : Int32 = 0, base : Int32 = 0, edit : Int32 = 0, gap : Int32 = 0, replace : Bool = false, background : UInt32 = 0, quiet : Quiet = Quiet::None, limit : Time::Span = @config.query_timeout) : Ack?
    head, source = load(pixels)
    control = merge(',', keys(',', {'a', 'f'}, {'i', id}, {'I', number}, {'q', quiet.value}, {'x', x}, {'y', y}, {'c', base}, {'r', edit}, {'z', gap}, {'X', replace}, {'Y', background}), head)
    draw(control, source, id, number, quiet, limit, "a=f")
  end

  def animate(id : UInt32 = 0, number : UInt32 = 0, state : Playback? = nil, current : Int32 = 0, loops : Int32 = 0, target : Int32 = 0, gap : Int32 = 0, quiet : Quiet = Quiet::None) : Nil
    control = keys(',', {'a', 'a'}, {'i', id}, {'I', number}, {'q', quiet.value}, {'s', state.try(&.value) || 0}, {'c', current}, {'v', loops}, {'r', target}, {'z', gap})
    exclusive(Family::Graphics) { @output.send(Term.build { |wire| wire.apc.char('G').str(control).st }) }
  end

  def compose(source : Int32, target : Int32, id : UInt32 = 0, number : UInt32 = 0, width : Int32 = 0, height : Int32 = 0, source_x : Int32 = 0, source_y : Int32 = 0, x : Int32 = 0, y : Int32 = 0, replace : Bool = false, quiet : Quiet = Quiet::None, limit : Time::Span = @config.query_timeout) : Ack?
    control = keys(',', {'a', 'c'}, {'i', id}, {'I', number}, {'q', quiet.value}, {'r', source}, {'c', target}, {'w', width}, {'h', height}, {'X', source_x}, {'Y', source_y}, {'x', x}, {'y', y}, {'C', replace})
    draw(control, Bytes.empty, id, number, quiet, limit)
  end

  private def placed(placement : Placement) : String
    Term.placed(placement)
  end

  private def load(pixels : Pixels) : {String, Bytes | IO}
    data = pixels.data
    size = pixels.size
    if pixels.compress && pixels.medium.direct?
      raw    = data.is_a?(IO) ? data.getb_to_end : data
      size   = raw.size if pixels.format.png?
      packed = IO::Memory.new
      Compress::Zlib::Writer.open(packed, &.write(raw))
      data = packed.to_slice
    end
    control = keys(',', {'f', pixels.format.value}, {'t', MEDIA[pixels.medium]}, {'s', pixels.width}, {'v', pixels.height}, {'S', size}, {'O', pixels.offset}, {'o', pixels.compress ? 'z' : 0})
    {control, data}
  end

  private def draw(control : String, source : Bytes | IO, id : UInt32, number : UInt32, quiet : Quiet, limit : Time::Span, action : String = "", probe : Bool = false) : Ack?
    more = merge(',', action, keys(',', {'q', quiet.value}))
    key  = number != 0 ? "I#{number}" : "i#{id}"
    wait = quiet.none? && (id != 0 || number != 0)
    waiter = exclusive(Family::Graphics) do
      pending = nil
      whole   = probe ? Bytewire.new(256) : nil
      first   = true
      blocks(source) do |chunk, last|
        code = Term.build do |wire|
          wire.apc.char('G').str(merge(',', first ? control : more, first && last ? "" : "m=#{last ? 0 : 1}"))
          wire.semi.base64(chunk) unless chunk.empty?
          wire.st
        end
        if whole
          whole.str(code)
        elsif first && wait
          pending = enqueue(Query::Graphics, code, key)
        else
          @output.send(code)
        end
        first = false
      end
      whole ? enqueue(Query::Graphics, String.new(whole.written), key, true) : pending
    end
    waiter.try { |channel| await(channel, limit).as?(Ack) }
  end
end
