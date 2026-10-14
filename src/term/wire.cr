# src/term/wire.cr
class Term
  ST         = "\e\\"
  ATTRIBUTES = "\e[c"
  RAW_CHUNK  = 3072
  POLL       = 100.milliseconds
  IDENT      = /\A[a-zA-Z0-9_\-+.]+\z/
  STARTED    = Time.instant

  enum Query
    Shape
    Color
    ClipboardRead
    ClipboardWrite
    Mode
    Attributes
    Window
    Cell
    Graphics
    NotifySupport
    NotifyAlive
    DndSupport
    DropData
    DragStart
  end

  enum Family
    Clipboard
    Graphics
    Notify
    Dnd
  end

  alias Raw = Key | Mouse | Resize | Focus | Visibility | ColorScheme | Paste | Notification | Drop | Drag | Ack
  alias Event = Raw | TextInput | KeyCommand | Lock | TypingMetric | KeyGesture | Binding | MouseGesture
  alias Reply = String | Int32 | Bool | Status | Clipboard | Size | Ack | DropData | Array(String) | Palette | Hash(String, String) | Hash(String, Array(String)) | Nil

  record Request, query : Query, key : String, sequence : String, waiter : Channel(Reply), probe : Bool, sink : IO? = nil

  alias Output = String | Request

  protected def self.keys(separator : Char, *pairs) : String
    String.build do |io|
      pairs.each do |name, value|
        next if value == 0 || value == false
        io << separator unless io.empty?
        io << name << '=' << (value == true ? 1 : value)
      end
    end
  end

  protected def self.merge(separator : Char, *parts : String) : String
    parts.reject(&.empty?).join(separator)
  end

  getter events : Channel(Event)
  getter output : Channel(Output)

  @mutexes : Array(Sync::Mutex)
  @wire    = Sync::Mutex.new
  @waiting = {} of {Query, String} => Deque(Request)

  def print(*objects) : Nil
    @output.send(objects.join)
  end

  def <<(object) : self
    @output.send(object.to_s)
    self
  end

  private def ident(value : String) : String
    raise ArgumentError.new("invalid identifier: #{value.inspect}") unless value.matches?(IDENT)
    value
  end

  private def exclusive(family : Family, &)
    @mutexes[family.value].synchronize { yield }
  end

  private def blocks(source : Bytes | IO, size : Int32 = RAW_CHUNK, & : String, Bool ->) : Nil
    held = nil
    each_block(source, size) do |slice|
      held.try { |previous| yield previous, false }
      held = Base64.strict_encode(slice)
    end
    yield held || "", true
  end

  private def each_block(source : Bytes, size : Int32, & : Bytes ->) : Nil
    offset = 0
    while offset < source.size
      yield source[offset, Math.min(size, source.size - offset)]
      offset += size
    end
  end

  private def each_block(source : IO, size : Int32, & : Bytes ->) : Nil
    buffer = Bytes.new(size)
    loop do
      filled = 0
      while filled < size
        count = source.read(buffer[filled..])
        break if count == 0
        filled += count
      end
      yield buffer[0, filled] if filled > 0
      break if filled < size
    end
  end

  private def keys(separator : Char, *pairs) : String
    Term.keys(separator, *pairs)
  end

  private def merge(separator : Char, *parts : String) : String
    Term.merge(separator, *parts)
  end

  private def request(query : Query, sequence : String, limit : Time::Span = @config.query_timeout, key : String = "", probe : Bool = false) : Reply
    await(enqueue(query, sequence, key, probe), limit)
  end

  private def enqueue(query : Query, sequence : String, key : String = "", probe : Bool = false, sink : IO? = nil) : Channel(Reply)
    waiter = Channel(Reply).new(2)
    @output.send(Request.new(query, key, sequence, waiter, probe, sink))
    waiter
  end

  private def await(waiter : Channel(Reply), limit : Time::Span) : Reply
    select
    when reply = waiter.receive
      reply
    when timeout(limit)
      nil
    end
  ensure
    waiter.close
  end

  private def admit : Nil
    loop do
      select
      when request = @pending.receive?
        return unless request
        @waiting.put_if_absent({request.query, request.key}) { Deque(Request).new } << request
      else
        return
      end
    end
  end

  private def peek(query : Query, key : String = "") : Request?
    admit
    queue = @waiting[{query, key}]? || return
    while request = queue.first?
      return request unless request.waiter.closed?
      queue.shift
    end
  end

  private def sweep : Nil
    @waiting.reject! { |_, queue| queue.all?(&.waiter.closed?) }
  end

  private def route(query : Query, reply : Reply, key : String = "", strict : Bool = false) : Bool
    admit
    slot      = {query, key}
    queue     = @waiting[slot]? || return false
    delivered = false
    while request = queue.shift?
      delivered = deliver(request.waiter, reply)
      break if delivered || strict
    end
    @waiting.delete(slot) if queue.empty?
    delivered
  end

  private def deliver(waiter : Channel(Reply), reply : Reply) : Bool
    return false if waiter.closed?
    waiter.send(reply)
    true
  rescue Channel::ClosedError
    false
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
      @wire.synchronize { @io.flush }
    end
  rescue IO::Error | Channel::ClosedError
  ensure
    @output.close
    @writer_done.close
  end

  private def transmit(item : Output) : Nil
    case item
    in String
      @wire.synchronize { @io << item }
    in Request
      @pending.send(item)
      @pending.send(item.copy_with(query: Query::Attributes, key: "")) if item.probe
      @wire.synchronize do
        @io << item.sequence
        @io << ATTRIBUTES if item.probe
      end
    end
  end

  private def run_reader : Nil
    buffer = Bytes.new(4096)
    until @stop.closed?
      admit
      count = begin
        @input.read(buffer)
      rescue IO::TimeoutError
        sweep
        idle
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

  private def clock : Time::Span
    Time.instant - STARTED
  end
end
