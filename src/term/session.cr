# src/term/session.cr
class Term
  SCREEN    = {"\e[?1049h", "\e[?1049l"}
  CELL_SIZE = "\e[16t"

  SIGNALS = {% if flag?(:win32) %}
              [Signal::INT]
            {% else %}
              [Signal::INT, Signal::TERM, Signal::HUP, Signal::QUIT]
            {% end %}

  @@open   = Sync::Exclusive(Array(Term)).new([] of Term)
  @@hooked = Atomic(Bool).new(false)

  def self.restore : Nil
    @@open.lock(&.dup).each(&.restore)
  end

  def self.suspend : Nil
    @@open.lock(&.dup).each(&.suspend)
  end

  def self.resume : Nil
    @@open.lock(&.dup).each(&.resume)
  end

  def self.refresh : Nil
    @@open.lock(&.dup).each(&.refresh)
  end

  def self.open(config : Config = Config.new, input : IO::FileDescriptor = STDIN, output : IO::FileDescriptor = STDOUT, & : Term ->)
    term = new(config, input, output)
    begin
      yield term
    ensure
      term.close
    end
  end

  @cell_width  = Atomic(Int32).new(0)
  @cell_height = Atomic(Int32).new(0)
  @setup       = ""
  @saved : TTY::Termios?
  @suspended = Atomic(Bool).new(false)
  @teardown : String
  @restored = Atomic(Bool).new(false)
  @features = Atomic(Int32).new(Feature::All.value)

  def initialize(@config : Config = Config.new, @input : IO::FileDescriptor = STDIN, @io : IO::FileDescriptor = STDOUT)
    ident(@config.clipboard_id)
    @events      = Channel(Event).new(@config.event_buffer)
    @output      = Channel(Output).new(256)
    @raw         = Channel(Raw).new(256)
    @pending     = Channel(Request).new(256)
    @serving     = Channel(Array(String) | Int32).new(1024)
    @stop        = Channel(Nil).new
    @reader_done = Channel(Nil).new
    @writer_done = Channel(Nil).new
    @mutexes     = Family.values.map { Sync::Mutex.new(:reentrant) }
    @credentials = @config.app_name.try do |name|
      ":pw=#{Base64.strict_encode(UUID.random.to_s)}:name=#{Base64.strict_encode(name)}"
    end || ""
    @mux = keys(':', {'i', @config.dnd_id})
    setup_engine
    screen    = @config.alternate_screen ? SCREEN : {"", ""}
    @teardown = @config.leave + screen[1]
    @saved    = capture
    raw
    @input.read_timeout = POLL
    measure
    register
    @output.send(screen[0])
    spawn(name: "term.writer") { run_writer }
    spawn(name: "term.reader") { run_reader }
    spawn(name: "term.engine") { run_engine }
    spawn(name: "term.server") { run_server }
    found = survey
    @features.set(found.value)
    @wire.synchronize do
      @teardown = @config.leave + FEATURES.reverse.join { |mode| mode.switch(found.includes?(mode.feature), false) } + screen[1]
      @setup    = screen[0] + FEATURES.join { |mode| mode.switch(found.includes?(mode.feature), true) } + CELL_SIZE + @config.enter
    end
    @output.send(@setup.lchop(screen[0]))
  end

  private def register : Nil
    @@open.lock(&.push(self))
    return if !@config.signals || @@hooked.swap(true)
    at_exit { Term.restore }
    SIGNALS.each do |signal|
      signal.trap do
        Term.restore
        exit 128 + signal.value
      end
    end
    {% unless flag?(:win32) %}
      Signal::TSTP.trap do
        Term.suspend
        Process.signal(Signal::STOP, Process.pid)
      end
      Signal::CONT.trap { Term.resume }
      Signal::WINCH.trap { Term.refresh }
    {% end %}
  end

  private def capture : TTY::Termios?
    TTY::Termios.get(@input) if @input.tty?
  rescue TTY::Error
  end

  private def measure : Resize?
    size   = TTY::Winsize.get(@io)
    rows   = size.rows.to_i
    cols   = size.cols.to_i
    width  = size.xpixel.to_i
    height = size.ypixel.to_i
    return unless cols > 0 && rows > 0
    @cell_width.set(width // cols) if width > 0
    @cell_height.set(height // rows) if height > 0
    Resize.new(rows, cols, height, width)
  rescue TTY::Error
  end

  private def raw : Nil
    @saved.try(&.raw.set(@input))
  rescue TTY::Error
  end

  private def cooked : Nil
    @saved.try(&.set(@input))
  rescue TTY::Error
  end

  private def park : Nil
    if @@hooked.get
      signal_group(Signal::TSTP)
    else
      suspend
      signal_group(Signal::STOP)
      resume
    end
  end

  private def signal_group(signal : Signal) : Nil
    TTY::Session.signal_process_group(0, signal)
  rescue TTY::Error
  end

  def refresh : Nil
    return if features.resize? || closed?
    measure.try { |resize| push resize }
  rescue Channel::ClosedError
  end

  def suspend : Nil
    @wire.synchronize do
      next if @restored.get || @suspended.swap(true)
      @io << @teardown
      @io.flush
      cooked
    end
  rescue IO::Error
  end

  def resume : Nil
    resumed = @wire.synchronize do
      next false if @restored.get || !@suspended.swap(false)
      raw
      @io << @setup
      @io.flush
      true
    end
    return unless resumed
    measure.try do |resize|
      select
      when @raw.send(resize)
      else
      end
    end
  rescue IO::Error | Channel::ClosedError
  end

  def features : Feature
    Feature.new(@features.get)
  end

  protected def restore : Nil
    @wire.synchronize do
      next if @restored.swap(true)
      @io << dnd_code("t=A") if @accepting.get
      @io << dnd_code("t=o:x=2") if @offering.get
      @io << @teardown
      @io.flush
      cooked
    end
  rescue IO::Error
  end

  def close : Nil
    return unless @stop.close
    @output.close
    @writer_done.receive?
    restore
    @@open.lock(&.delete(self))
    @pending.close
    @serving.close
    @events.close
    @reader_done.receive?
    @input.read_timeout = nil
  end

  def closed? : Bool
    @stop.closed?
  end

  def supports?(mode : Int32) : Bool?
    request(Query::Mode, "\e[?#{mode}$p", key: mode.to_s).as?(Int32).try { |state| !state.in?(0, 4) }
  end

  def query_visibility : Nil
    @output.send("\e[?998n")
  end

  def query_color_scheme : Nil
    @output.send("\e[?996n")
  end

  def window_size(limit : Time::Span = @config.query_timeout) : Size?
    request(Query::Window, "\e[14t", limit).as?(Size)
  end

  def cell_size(limit : Time::Span = @config.query_timeout) : Size?
    request(Query::Cell, "\e[16t", limit).as?(Size)
  end

  private def survey : Feature
    return Feature::All unless @config.detect
    deadline = clock + @config.query_timeout
    waiters  = FEATURES.map { |mode| {mode, enqueue(Query::Mode, mode.probe, mode.key, true)} }
    waiters.reduce(Feature::None) do |found, (mode, waiter)|
      state = await(waiter, {deadline - clock, Time::Span.zero}.max).as?(Int32) || 0
      state.in?(0, 4) ? found : found | mode.feature
    end
  end
end
