# spec/term_spec.cr
require "spec"
require "file_utils"
require "../src/term"

SETUP    = "\e[?1049h\e[>31u\e[?2048h\e[?1003;1016h\e[?1004h\e[?2033h\e[?2031h\e[?5522h\e[16t"
TEARDOWN = "\e[?5522l\e[?2031l\e[?2033l\e[?1004l\e[?1003;1016l\e[?2048l\e[<u\e[?1049l"
DA1      = "\e[?62;c"

private def osc(body : String) : String
  "\e]#{body}\e\\"
end

private def apc(body : String) : String
  "\e_G#{body}\e\\"
end

private def b64(data : String | Bytes) : String
  Base64.strict_encode(data)
end

private def press(key : Char) : String
  "\e[#{key.ord}u"
end

private def release(key : Char) : String
  "\e[#{key.ord};1:3u"
end

private def tap(key : Char) : String
  press(key) + release(key)
end

private class Rig
  getter term : Term
  getter seen = ""
  getter last = ""
  @buffer = ""
  @feed : IO::FileDescriptor
  @screen : IO::FileDescriptor
  @reader : IO::FileDescriptor
  @writer : IO::FileDescriptor

  def initialize(config : Term::Config = Term::Config.new)
    reader, @feed = IO.pipe
    @screen, writer = IO.pipe
    @screen.read_timeout = 20.milliseconds
    @term = Term.new(config, reader, writer)
    @reader = reader
    @writer = writer
    expect(/\e\[16t/)
  end

  def feed(text : String) : Nil
    @feed << text
    @feed.flush
  end

  def expect(pattern : Regex, attempts : Int32 = 150) : Regex::MatchData
    chunk = Bytes.new(65536)
    attempts.times do
      if match = pattern.match(@buffer)
        @seen = match.pre_match + match[0]
        @last = match[0]
        @buffer = match.post_match
        return match
      end
      begin
        count = @screen.read(chunk)
        @buffer += String.new(chunk[0, count]) if count > 0
      rescue IO::TimeoutError
      end
    end
    raise "expected output matching #{pattern.inspect}, got #{@buffer.inspect}"
  end

  def expect(text : String) : Regex::MatchData
    expect(Regex.new(Regex.escape(text)))
  end

  def ask(pattern : Regex, reply : Regex::MatchData -> String, &block : -> T) : T forall T
    result = Channel(T).new(1)
    spawn { result.send(block.call) }
    feed(reply.call(expect(pattern)))
    select
    when value = result.receive
      value
    when timeout(5.seconds)
      raise "no result for #{pattern.inspect}"
    end
  end

  def ask(pattern : Regex, reply : String, &block : -> T) : T forall T
    ask(pattern, ->(_match : Regex::MatchData) { reply }, &block)
  end

  def event(type : T.class, & : T -> Bool) : T forall T
    loop do
      select
      when event = @term.events.receive?
        raise "events closed while waiting for #{T}" unless event
        return event if event.is_a?(T) && yield event
      when timeout(3.seconds)
        raise "no #{T} event"
      end
    end
  end

  def event(type : T.class) : T forall T
    event(type) { true }
  end

  def upto(& : Term::Event -> Bool) : Array(Term::Event)
    events = [] of Term::Event
    loop do
      select
      when event = @term.events.receive?
        raise "events closed" unless event
        events << event
        return events if yield event
      when timeout(3.seconds)
        raise "marker event never arrived, got #{events.inspect}"
      end
    end
  end

  def close : Nil
    @feed.close
    @term.close
    @writer.close
    @screen.close
    @reader.close
  end
end

private def rig(config : Term::Config = Term::Config.new, & : Rig ->) : Nil
  rig = Rig.new(config)
  begin
    yield rig
  ensure
    rig.close
  end
end

private def kinds(events : Array(Term::Event)) : Array(Term::KeyGesture::Kind)
  events.compact_map(&.as?(Term::KeyGesture)).map(&.kind)
end

private def gestures(events : Array(Term::Event)) : Array(Term::MouseGesture::Kind)
  events.compact_map(&.as?(Term::MouseGesture)).map(&.kind)
end

private def bindings(events : Array(Term::Event), kind : Term::Binding::Kind) : Array(String)
  events.compact_map(&.as?(Term::Binding)).select { |binding| binding.kind == kind }.map(&.name)
end

private def marker?(event : Term::Event, key : Char) : Bool
  event.is_a?(Term::TypingMetric) && event.code == key.ord
end

describe Term do
  describe "lifecycle" do
    it "enables every mode on open and undoes them in reverse on close" do
      reader, feed = IO.pipe
      screen, writer = IO.pipe
      term = Term.new(Term::Config.new, reader, writer)
      term.closed?.should be_false
      feed.close
      term.close
      writer.close
      screen.gets_to_end.should eq(SETUP + TEARDOWN)
      term.closed?.should be_true
      term.events.receive?.should be_nil
    end

    it "stays on the main screen when the alternate screen is disabled" do
      config = Term::Config.new
      config.alternate_screen = false
      reader, feed = IO.pipe
      screen, writer = IO.pipe
      term = Term.new(config, reader, writer)
      feed.close
      term.close
      writer.close
      output = screen.gets_to_end
      output.should_not contain("1049")
      output.should start_with("\e[>31u")
      output.should end_with("\e[<u")
    end

    it "closes when the block given to open returns and tolerates a second close" do
      reader, feed = IO.pipe
      screen, writer = IO.pipe
      captured = nil
      Term.open(Term::Config.new, reader, writer) do |term|
        captured = term
        feed.close
      end
      term = captured.not_nil!
      term.closed?.should be_true
      term.close
      writer.close
      screen.gets_to_end.should eq(SETUP + TEARDOWN)
    end

    it "writes through print and <<" do
      rig do |rig|
        rig.term.print "a", 1, :b
        rig.term << "x" << 2
        rig.expect("a1bx2")
      end
    end
  end

  describe "keyboard" do
    it "decodes every field of a CSI u report" do
      rig do |rig|
        rig.feed "\e[97:65:113;2:1;65u"
        key = rig.event(Term::Key)
        key.code.should eq(97)
        key.char.should eq('a')
        key.shifted.should eq(65)
        key.base.should eq(113)
        key.mods.should eq(Term::Mods::Shift)
        key.shift?.should be_true
        key.press?.should be_true
        key.text.should eq("A")
        key.named.should be_nil
        key.command?.should be_false
      end
    end

    it "decodes the whole modifier bitfield and the event type" do
      rig do |rig|
        rig.feed "\e[97;256:2u\e[97;1:3u"
        key = rig.event(Term::Key)
        key.mods.should eq(Term::Mods::All)
        key.repeat?.should be_true
        rig.event(Term::Key).release?.should be_true
      end
    end

    it "treats a missing modifier field as no modifiers and a press" do
      rig do |rig|
        rig.feed "\e[13u"
        key = rig.event(Term::Key)
        key.named.should eq(Term::Named::Enter)
        key.mods.should eq(Term::Mods::None)
        key.press?.should be_true
        key.char.should be_nil
      end
    end

    it "decodes legacy letter and tilde forms" do
      rig do |rig|
        rig.feed "\e[1;5A\e[B\e[3~\e[15;2~\e[1;3:3H\e[E"
        up = rig.event(Term::Key)
        up.named.should eq(Term::Named::Up)
        up.ctrl?.should be_true
        rig.event(Term::Key).named.should eq(Term::Named::Down)
        rig.event(Term::Key).named.should eq(Term::Named::Delete)
        f5 = rig.event(Term::Key)
        f5.named.should eq(Term::Named::F5)
        f5.shift?.should be_true
        home = rig.event(Term::Key)
        home.named.should eq(Term::Named::Home)
        home.alt?.should be_true
        home.release?.should be_true
        rig.event(Term::Key).named.should eq(Term::Named::KpBegin)
      end
    end

    it "maps the documented functional key codes" do
      Term::Named::CapsLock.value.should eq(57358)
      Term::Named::Menu.value.should eq(57363)
      Term::Named::F13.value.should eq(57376)
      Term::Named::F35.value.should eq(57398)
      Term::Named::Kp0.value.should eq(57399)
      Term::Named::KpBegin.value.should eq(57427)
      Term::Named::MediaPlay.value.should eq(57428)
      Term::Named::MuteVolume.value.should eq(57440)
      Term::Named::LeftShift.value.should eq(57441)
      Term::Named::RightShift.value.should eq(57447)
      Term::Named::IsoLevel5Shift.value.should eq(57454)
      rig do |rig|
        rig.feed "\e[57376u\e[57441;2u"
        rig.event(Term::Key).named.should eq(Term::Named::F13)
        shift = rig.event(Term::Key)
        shift.named.should eq(Term::Named::LeftShift)
        shift.modifier?.should be_true
      end
    end

    it "emits text input for text and not for commands or releases" do
      rig do |rig|
        rig.feed "\e[0;;229:8364u\e[97;5;97u\e[98;1:3;98u#{tap('q')}"
        events = rig.upto { |event| marker?(event, 'q') }
        events.compact_map(&.as?(Term::TextInput)).map(&.text).should eq(["å€"])
        keys = events.compact_map(&.as?(Term::Key))
        keys[0].code.should eq(0)
        keys[0].text.should eq("å€")
        keys[1].command?.should be_true
      end
    end

    it "reports a tap, counts multi-taps and measures typing" do
      rig do |rig|
        rig.feed tap('a') + tap('a') + tap('b')
        events = rig.upto { |event| marker?(event, 'b') }
        taps = events.compact_map(&.as?(Term::KeyGesture)).select(&.kind.tap?)
        taps.map(&.count).should eq([1, 2, 1])
        taps.map(&.key.code).should eq([97, 97, 98])
        metrics = events.compact_map(&.as?(Term::TypingMetric))
        metrics.size.should eq(3)
        metrics[0].latency.should eq(Time::Span.zero)
        metrics[0].overlap.should eq(0)
      end
    end

    it "counts rollover overlap from the pressed set" do
      rig do |rig|
        rig.feed press('a') + press('b') + release('a') + release('b')
        events = rig.upto { |event| marker?(event, 'b') }
        metrics = events.compact_map(&.as?(Term::TypingMetric))
        metrics.map(&.code).should eq([97, 98])
        metrics.map(&.overlap).should eq([0, 1])
      end
    end

    it "turns repeats into a hold and reports the repeat threshold" do
      rig do |rig|
        rig.feed "#{press('a')}\e[97;1:2u\e[97;1:2u\e[97;1:2u#{release('a')}"
        events = rig.upto { |event| marker?(event, 'a') }
        kinds(events).should eq([
          Term::KeyGesture::Kind::Activate,
          Term::KeyGesture::Kind::HoldStart,
          Term::KeyGesture::Kind::AutoRepeat,
          Term::KeyGesture::Kind::AutoRepeat,
          Term::KeyGesture::Kind::HoldReached,
          Term::KeyGesture::Kind::AutoRepeat,
          Term::KeyGesture::Kind::HoldEnd,
        ])
        reached = events.compact_map(&.as?(Term::KeyGesture)).find!(&.kind.hold_reached?)
        reached.count.should eq(3)
      end
    end

    it "starts a hold from the timer when no repeat arrives" do
      config = Term::Config.new
      config.hold_after = 20.milliseconds
      rig(config) do |rig|
        rig.feed press('a')
        rig.event(Term::KeyGesture, &.kind.hold_start?).key.code.should eq(97)
        rig.feed release('a')
        rig.event(Term::KeyGesture, &.kind.hold_end?)
      end
    end

    it "fires a chord once per completion and re-arms after a release" do
      config = Term::Config.new
      config.chord("ab", 'a', 'b')
      rig(config) do |rig|
        rig.feed press('a') + press('b') + press('c') + "\e[98;1:2u" + release('b') + press('b') + tap('q')
        events = rig.upto { |event| marker?(event, 'q') }
        bindings(events, :chord).should eq(["ab", "ab"])
      end
    end

    it "walks a key sequence and ignores modifiers and repeats in between" do
      config = Term::Config.new
      config.sequence("leader", ' ', 'f', 'g')
      rig(config) do |rig|
        rig.feed "#{tap(' ')}\e[57441;2u\e[57441;1:3u#{press('f')}\e[102;1:2u#{release('f')}#{tap('g')}"
        events = rig.upto { |event| marker?(event, 'g') }
        bindings(events, :sequence).should eq(["leader"])
      end
    end

    it "resets a key sequence on a wrong key and on the timeout" do
      config = Term::Config.new
      config.sequence_timeout = 20.milliseconds
      config.sequence("gg", 'g', 'g')
      rig(config) do |rig|
        rig.feed tap('g') + tap('x') + tap('g')
        events = rig.upto { |event| marker?(event, 'g') && event.as(Term::TypingMetric).latency > Time::Span.zero }
        bindings(events, :sequence).should be_empty
        sleep 80.milliseconds
        rig.feed tap('q') + tap('g')
        events = rig.upto { |event| marker?(event, 'g') }
        bindings(events, :sequence).should be_empty
        rig.feed tap('g')
        events = rig.upto { |event| marker?(event, 'g') }
        bindings(events, :sequence).should eq(["gg"])
      end
    end

    it "matches symbolic shortcuts, ignoring lock modifiers and consuming shift" do
      config = Term::Config.new
      config.shortcut("save", 's', Term::Mods::Ctrl)
      config.shortcut("plus", '+', Term::Mods::Ctrl)
      rig(config) do |rig|
        rig.feed "\e[115;5u\e[115;197u\e[61:43;6u\e[115;3u#{tap('q')}"
        events = rig.upto { |event| marker?(event, 'q') }
        bindings(events, :shortcut).should eq(["save", "save", "plus"])
      end
    end

    it "matches physical shortcuts on the base layout key" do
      config = Term::Config.new
      config.shortcut("quit", 'q', Term::Mods::Ctrl, physical: true)
      rig(config) do |rig|
        rig.feed "\e[97::113;5u\e[113;5u\e[97;5u#{tap('z')}"
        events = rig.upto { |event| marker?(event, 'z') }
        bindings(events, :shortcut).should eq(["quit", "quit"])
      end
    end

    it "reports a modifier tapped alone and not one used with another key" do
      rig do |rig|
        rig.feed "\e[57441;2u\e[57441;1:3u\e[57442;5u#{press('a')}\e[57442;1:3u#{release('a')}"
        events = rig.upto { |event| marker?(event, 'a') }
        taps = events.compact_map(&.as?(Term::KeyGesture)).select(&.kind.modifier_tap?)
        taps.map(&.key.code).should eq([57441])
      end
    end
  end

  describe "mouse" do
    it "decodes buttons, modifiers and pixel coordinates" do
      rig do |rig|
        rig.feed "\e[<20;45;65M"
        mouse = rig.event(Term::Mouse)
        mouse.action.should eq(Term::Mouse::Action::Press)
        mouse.button.should eq(Term::Mouse::Button::Left)
        mouse.mods.should eq(Term::Mods::Shift | Term::Mods::Ctrl)
        mouse.x.should eq(45)
        mouse.y.should eq(65)
        mouse.col.should eq(0)
        mouse.row.should eq(0)
      end
    end

    it "decodes every event class in priority order" do
      rig do |rig|
        rig.feed "\e[<1;1;1M\e[<2;1;1m\e[<34;2;2M\e[<35;3;3M\e[<65;3;3M\e[<67;3;3M\e[<129;3;3M\e[<131;3;3m\e[<8;3;3M\e[<256;0;0M"
        expected = [
          {Term::Mouse::Action::Press, Term::Mouse::Button::Middle},
          {Term::Mouse::Action::Release, Term::Mouse::Button::Right},
          {Term::Mouse::Action::Drag, Term::Mouse::Button::Right},
          {Term::Mouse::Action::Hover, Term::Mouse::Button::None},
          {Term::Mouse::Action::Scroll, Term::Mouse::Button::WheelDown},
          {Term::Mouse::Action::Scroll, Term::Mouse::Button::WheelRight},
          {Term::Mouse::Action::Press, Term::Mouse::Button::Aux9},
          {Term::Mouse::Action::Release, Term::Mouse::Button::Aux11},
          {Term::Mouse::Action::Press, Term::Mouse::Button::Left},
          {Term::Mouse::Action::Leave, Term::Mouse::Button::None},
        ]
        expected.each do |action, button|
          mouse = rig.event(Term::Mouse)
          {mouse.action, mouse.button}.should eq({action, button})
        end
      end
    end

    it "converts pixels to cells from the resize report" do
      rig do |rig|
        rig.feed "\e[48;10;20;200;400t\e[<0;45;65M"
        resize = rig.event(Term::Resize)
        {resize.rows, resize.cols, resize.height, resize.width}.should eq({10, 20, 200, 400})
        mouse = rig.event(Term::Mouse)
        {mouse.col, mouse.row}.should eq({2, 3})
      end
    end

    it "converts pixels to cells from the cell size report" do
      rig do |rig|
        rig.feed "\e[6;20;10t\e[<0;45;65M"
        mouse = rig.event(Term::Mouse)
        {mouse.col, mouse.row}.should eq({4, 3})
      end
    end

    it "synthesizes clicks and counts multi-clicks within the radius" do
      rig do |rig|
        click = "\e[<0;10;10M\e[<0;11;11m"
        rig.feed click + click + click + "\e[<0;90;90M\e[<0;90;90m" + "\e[<2;90;90M\e[<2;90;90m"
        clicks = Array.new(5) { rig.event(Term::MouseGesture, &.kind.click?) }
        clicks.map(&.count).should eq([1, 2, 3, 1, 1])
        clicks.last.mouse.button.should eq(Term::Mouse::Button::Right)
      end
    end

    it "does not click when the release is outside the radius or on another button" do
      rig do |rig|
        rig.feed "\e[<0;10;10M\e[<0;30;10m\e[<0;10;10M\e[<1;10;10m#{tap('q')}"
        events = rig.upto { |event| marker?(event, 'q') }
        gestures(events).should_not contain(Term::MouseGesture::Kind::Click)
      end
    end

    it "brackets drag reports into start, move and end with a swipe" do
      rig do |rig|
        rig.feed "\e[<0;10;10M\e[<32;30;10M\e[<32;50;14M\e[<0;50;14m#{tap('q')}"
        events = rig.upto { |event| marker?(event, 'q') }
        drags = events.compact_map(&.as?(Term::MouseGesture)).select { |gesture| gesture.kind.drag_start? || gesture.kind.drag_move? || gesture.kind.drag_end? }
        drags.map(&.kind).should eq([Term::MouseGesture::Kind::DragStart, Term::MouseGesture::Kind::DragMove, Term::MouseGesture::Kind::DragEnd])
        drags.map(&.dx).should eq([20, 40, 40])
        drags.last.dy.should eq(4)
        drags.last.direction.should eq(Term::Direction::Right)
        swipe = events.compact_map(&.as?(Term::MouseGesture)).find!(&.kind.swipe?)
        swipe.velocity.should be > 500.0
        gestures(events).should_not contain(Term::MouseGesture::Kind::Click)
      end
    end

    it "infers enter from the first report and after a leave" do
      rig do |rig|
        rig.feed "\e[<35;5;5M\e[<35;6;6M\e[<256;0;0M\e[<35;7;7M#{tap('q')}"
        events = rig.upto { |event| marker?(event, 'q') }
        enters = events.compact_map(&.as?(Term::MouseGesture)).select(&.kind.enter?)
        enters.map(&.mouse.x).should eq([5, 7])
      end
    end

    it "reports motion deltas between successive reports" do
      rig do |rig|
        rig.feed "\e[<35;10;10M\e[<35;13;14M"
        motion = rig.event(Term::MouseGesture, &.kind.motion?)
        {motion.dx, motion.dy}.should eq({3, 4})
        motion.velocity.should be > 0.0
        motion.direction.should eq(Term::Direction::Down)
      end
    end

    it "coalesces consecutive wheel reports into one scroll gesture per direction" do
      rig do |rig|
        rig.feed "\e[<64;5;5M\e[<64;5;5M\e[<64;5;5M\e[<65;5;5M"
        up = rig.event(Term::MouseGesture, &.kind.scroll?)
        up.count.should eq(3)
        up.mouse.button.should eq(Term::Mouse::Button::WheelUp)
        down = rig.event(Term::MouseGesture, &.kind.scroll?)
        down.count.should eq(1)
        down.mouse.button.should eq(Term::Mouse::Button::WheelDown)
      end
    end

    it "detects multi-button chords" do
      rig do |rig|
        rig.feed "\e[<0;5;5M\e[<2;5;5M"
        chord = rig.event(Term::MouseGesture, &.kind.chord?)
        chord.count.should eq(2)
        chord.mouse.button.should eq(Term::Mouse::Button::Right)
      end
    end

    it "reports a long press when no release follows" do
      config = Term::Config.new
      config.long_press_after = 20.milliseconds
      rig(config) do |rig|
        rig.feed "\e[<0;5;5M"
        rig.event(Term::MouseGesture, &.kind.long_press?).mouse.x.should eq(5)
      end
    end

    it "reports hover dwell and its end when motion resumes" do
      config = Term::Config.new
      config.hover_dwell_after = 20.milliseconds
      rig(config) do |rig|
        rig.feed "\e[<35;5;5M"
        rig.event(Term::MouseGesture, &.kind.hover_dwell?).mouse.x.should eq(5)
        rig.feed "\e[<35;9;9M"
        rig.event(Term::MouseGesture, &.kind.hover_end?).mouse.x.should eq(9)
      end
    end
  end

  describe "terminal notifications" do
    it "reports focus, visibility and color scheme changes" do
      rig do |rig|
        rig.feed "\e[I\e[O\e[?999;1n\e[?999;2n\e[?997;1n\e[?997;2n"
        rig.event(Term::Focus).gained.should be_true
        rig.event(Term::Focus).gained.should be_false
        rig.event(Term::Visibility).visible.should be_true
        rig.event(Term::Visibility).visible.should be_false
        rig.event(Term::ColorScheme).dark.should be_true
        rig.event(Term::ColorScheme).dark.should be_false
      end
    end

    it "sends the visibility and color scheme queries" do
      rig do |rig|
        rig.term.query_visibility
        rig.term.query_color_scheme
        rig.expect("\e[?998n\e[?996n")
      end
    end

    it "queries mode support" do
      rig do |rig|
        rig.ask(/\e\[\?5522\$p/, "\e[?5522;2$y") { rig.term.supports?(5522) }.should be_true
        rig.ask(/\e\[\?2026\$p/, "\e[?2026;0$y") { rig.term.supports?(2026) }.should be_false
        rig.ask(/\e\[\?7\$p/, "\e[?7;4$y") { rig.term.supports?(7) }.should be_false
      end
    end

    it "queries the window and cell size in pixels" do
      rig do |rig|
        window = rig.ask(/\e\[14t/, "\e[4;600;800t") { rig.term.window_size }.not_nil!
        {window.width, window.height}.should eq({800, 600})
        cell = rig.ask(/\e\[16t/, "\e[6;20;10t") { rig.term.cell_size }.not_nil!
        {cell.width, cell.height}.should eq({10, 20})
      end
    end
  end

  describe "pointer shape" do
    it "sets, pushes, pops and resets" do
      rig do |rig|
        (rig.term.pointer = Term::Shape::NsResize).should eq(Term::Shape::NsResize)
        rig.term.push_pointer(:wait, :vertical_text)
        rig.term.pop_pointer
        rig.term.reset_pointer
        rig.expect("\e]22;=ns-resize\e\\\e]22;>wait,vertical-text\e\\\e]22;<\e\\\e]22;\e\\")
      end
    end

    it "names all thirty mandatory shapes" do
      names = Term::Shape.values.map(&.wire)
      names.size.should eq(30)
      names.should contain("nesw-resize")
      names.should contain("not-allowed")
      names.should contain("zoom-out")
      names.all?(&.matches?(/\A[a-z0-9_-]+\z/)).should be_true
    end

    it "queries the current, default and grabbed shapes" do
      rig do |rig|
        rig.ask(/\e\]22;\?__current__\e\\/, osc("22;crosshair")) { rig.term.pointer }.should eq("crosshair")
        rig.ask(/\e\]22;\?__current__\e\\/, osc("22;0")) { rig.term.pointer }.should be_nil
        rig.ask(/\e\]22;\?__default__\e\\/, osc("22;text")) { rig.term.pointer(:default) }.should eq("text")
        rig.ask(/\e\]22;\?__grabbed__\e\\/, "\e]22;grabbing\a") { rig.term.pointer(:grabbed) }.should eq("grabbing")
      end
    end

    it "queries shape support" do
      rig do |rig|
        flags = rig.ask(/\e\]22;\?pointer,crosshair,wait\e\\/, osc("22;1,0,1")) do
          rig.term.pointer_support(:pointer, :crosshair, :wait)
        end
        flags.should eq([true, false, true])
      end
    end
  end

  describe "color control" do
    it "pushes and pops the color stack" do
      rig do |rig|
        rig.term.push_colors
        rig.term.pop_colors
        rig.expect("\e]30001\e\\\e]30101\e\\")
      end
    end

    it "sets, makes dynamic and resets colors" do
      rig do |rig|
        rig.term.color("foreground", "green")
        rig.term.color(1, Term::Color.rgb(255, 0, 128))
        rig.term.color("transparent_background_color1", Term::Color.rgb(0, 0, 0, 0.5))
        rig.term.dynamic_color("cursor")
        rig.term.reset_color("background")
        rig.expect("\e]21;foreground=green\e\\\e]21;1=rgb:ffff/0000/8080\e\\\e]21;transparent_background_color1=rgb:0000/0000/0000@0.5\e\\\e]21;cursor=\e\\\e]21;background\e\\")
      end
    end

    it "queries colors, mapping undefined values to nil and dropping unknown keys" do
      rig do |rig|
        colors = rig.ask(/\e\]21;foreground=\?;cursor=\?;7=\?;nonsense=\?\e\\/, osc("21;foreground=rgb:ff/00/00;cursor=;7=#3a7;unknown=bm9uc2Vuc2U")) do
          rig.term.colors("foreground", "cursor", 7, "nonsense")
        end.not_nil!
        colors.keys.should eq(["foreground", "cursor", "7"])
        colors["foreground"].should eq(Term::Color.new(0xffff, 0, 0))
        colors["cursor"].should be_nil
        colors["7"].should eq(Term::Color.new(0x3000, 0xa000, 0x7000))
      end
    end

    it "parses the rgb form by scaling each component" do
      Term::Color.parse("rgb:f/0/8").should eq(Term::Color.new(0xffff, 0, 0x8888))
      Term::Color.parse("rgb:FF/80/00").should eq(Term::Color.new(0xffff, 0x8080, 0))
      Term::Color.parse("rgb:fff/000/800").should eq(Term::Color.new(0xffff, 0, 0x8007))
      Term::Color.parse("rgb:1234/abcd/ffff").should eq(Term::Color.new(0x1234, 0xabcd, 0xffff))
    end

    it "parses the hash form as most significant bits" do
      Term::Color.parse("#3a7").should eq(Term::Color.new(0x3000, 0xa000, 0x7000))
      Term::Color.parse("#ff0080").should eq(Term::Color.new(0xff00, 0, 0x8000))
      Term::Color.parse("#123456789").should eq(Term::Color.new(0x1230, 0x4560, 0x7890))
      Term::Color.parse("#111122223333").should eq(Term::Color.new(0x1111, 0x2222, 0x3333))
    end

    it "parses the rgbi form with clipping, and alpha on any form" do
      Term::Color.parse("rgbi:1.0/0/2.5").should eq(Term::Color.new(0xffff, 0, 0xffff))
      Term::Color.parse("rgbi:-1/1e0/0.0").should eq(Term::Color.new(0, 0xffff, 0))
      Term::Color.parse("#ff0000@0.3").should eq(Term::Color.new(0xff00, 0, 0, 0.3))
      Term::Color.parse("rgb:ff/00/00@0.1").not_nil!.alpha.should eq(0.1)
    end

    it "rejects values it cannot decode" do
      Term::Color.parse("").should be_nil
      Term::Color.parse("red").should be_nil
      Term::Color.parse("rgb:gg/00/00").should be_nil
      Term::Color.parse("rgb:ff/00").should be_nil
      Term::Color.parse("rgb:fffff/0/0").should be_nil
      Term::Color.parse("#ff00").should be_nil
      Term::Color.parse("#ff0000@x").should be_nil
    end

    it "round-trips through its wire form" do
      color = Term::Color.new(0x1234, 0xabcd, 0x00ff, 0.25)
      color.to_s.should eq("rgb:1234/abcd/00ff@0.25")
      Term::Color.parse(color.to_s).should eq(color)
    end
  end

  describe "clipboard" do
    it "writes text and reports success" do
      rig do |rig|
        status = rig.ask(/\e\]5522;type=wdata\e\\/, osc("5522;type=write:status=DONE")) { rig.term.copy("hi") }
        status.should eq(Term::Status::Done)
        rig.seen.should eq("\e]5522;type=write\e\\\e]5522;type=wdata:mime=dGV4dC9wbGFpbg==;aGk=\e\\\e]5522;type=wdata\e\\")
      end
    end

    it "sends the password and name when an app name is configured, and the location" do
      config = Term::Config.new
      config.app_name = "demo"
      rig(config) do |rig|
        rig.ask(/\e\]5522;type=wdata\e\\/, osc("5522;type=write:status=DONE")) { rig.term.copy("x", primary: true) }
        match = rig.seen.match!(/\e\]5522;type=write:loc=primary:pw=([A-Za-z0-9+\/=]+):name=ZGVtbw==\e\\/)
        Base64.decode_string(match[1]).should match(/\A[0-9a-f-]{36}\z/)
      end
    end

    it "chunks large payloads below the limit and sends aliases" do
      rig do |rig|
        data = Bytes.new(9000) { |index| (index % 251).to_u8 }
        rig.ask(/\e\]5522;type=wdata\e\\/, osc("5522;type=write:status=DONE")) do
          rig.term.clipboard_write({"image/png" => data}, {"image/png" => ["image/x-png", "PNG"]})
        end
        chunks = rig.seen.scan(/\e\]5522;type=wdata:mime=aW1hZ2UvcG5n;([^\e]*)\e\\/).map { |match| Base64.decode(match[1]) }
        chunks.size.should eq(3)
        chunks.all? { |chunk| chunk.size <= 4096 }.should be_true
        chunks.reduce(Bytes.empty) { |all, chunk| all + chunk }.should eq(data)
        rig.seen.should contain("\e]5522;type=walias:mime=aW1hZ2UvcG5n;#{b64("image/x-png PNG")}\e\\")
      end
    end

    it "reports write errors" do
      rig do |rig|
        rig.ask(/type=wdata\e\\/, osc("5522;type=write:status=EPERM")) { rig.term.copy("x") }.should eq(Term::Status::EPERM)
        rig.ask(/type=wdata\e\\/, osc("5522;type=write:status=EFBIG")) { rig.term.copy("x") }.should eq(Term::Status::EFBIG)
        rig.ask(/type=wdata\e\\/, osc("5522;type=write:status=EWHAT")) { rig.term.copy("x") }.should eq(Term::Status::EIO)
      end
    end

    it "reads several MIME types delivered in separately padded chunks" do
      rig do |rig|
        reply = osc("5522;type=read:status=OK:id=term") +
                osc("5522;type=read:status=DATA:id=term:mime=#{b64("text/plain")};#{b64("He")}") +
                osc("5522;type=read:status=DATA:id=term:mime=#{b64("text/plain")};#{b64("llo")}") +
                osc("5522;type=read:status=DATA:id=term:mime=#{b64("image/png")};#{b64(Bytes[1, 2, 3])}") +
                osc("5522;type=read:status=DONE:id=term")
        clipboard = rig.ask(/\e\]5522;type=read:id=term;#{Regex.escape(b64("text/plain image/png"))}\e\\/, reply) do
          rig.term.clipboard_read("text/plain", "image/png")
        end.not_nil!
        clipboard.done?.should be_true
        clipboard.text.should eq("Hello")
        clipboard.data["image/png"].should eq(Bytes[1, 2, 3])
      end
    end

    it "reads from the primary selection" do
      rig do |rig|
        reply = osc("5522;type=read:status=ENOSYS:id=term")
        clipboard = rig.ask(/\e\]5522;type=read:id=term:loc=primary;/, reply) { rig.term.clipboard_read("text/plain", primary: true) }.not_nil!
        clipboard.status.should eq(Term::Status::ENOSYS)
        clipboard.done?.should be_false
        clipboard.text.should be_nil
      end
    end

    it "lists the available MIME types" do
      rig do |rig|
        reply = osc("5522;type=read:status=OK:id=term") +
                osc("5522;type=read:status=DATA:id=term:mime=Lg==;#{b64(" text/html  text/plain\n")}") +
                osc("5522;type=read:status=DONE:id=term")
        rig.ask(/\e\]5522;type=read:id=term;Lg==\e\\/, reply) { rig.term.clipboard_mimes }.should eq(["text/html", "text/plain"])
      end
    end

    it "turns an unsolicited listing into a paste event and reads with its password" do
      rig do |rig|
        rig.feed osc("5522;type=read:status=OK:loc=primary:pw=c2VjcmV0") +
                 osc("5522;type=read:status=DATA:mime=Lg==:pw=c2VjcmV0;#{b64("text/html text/plain\n")}") +
                 osc("5522;type=read:status=DONE:pw=c2VjcmV0")
        paste = rig.event(Term::Paste)
        paste.mimes.should eq(["text/html", "text/plain"])
        paste.primary.should be_true
        paste.password.should eq("c2VjcmV0")
        reply = osc("5522;type=read:status=OK:id=term") +
                osc("5522;type=read:status=DATA:id=term:mime=#{b64("text/html")};#{b64("<b>Bold text</b>")}") +
                osc("5522;type=read:status=DONE:id=term")
        request = /\e\]5522;type=read:id=term:loc=primary:pw=c2VjcmV0:name=UGFzdGUgZXZlbnQ=;#{Regex.escape(b64("text/html"))}\e\\/
        clipboard = rig.ask(request, reply) { rig.term.clipboard_read(paste, "text/html") }.not_nil!
        String.new(clipboard.data["text/html"]).should eq("<b>Bold text</b>")
      end
    end

    it "ignores a read reply carrying invalid base64" do
      rig do |rig|
        rig.feed osc("5522;type=read:status=OK") + osc("5522;type=read:status=DATA:mime=Lg==;@@@@") + press('a')
        rig.event(Term::Key).code.should eq(97)
      end
    end
  end

  describe "graphics" do
    it "transmits a small image in one code and returns the acknowledgement" do
      rig do |rig|
        ack = rig.ask(/\e_G[^\e]*\e\\/, apc("i=7;OK")) { rig.term.image(Term::Pixels.rgb(Bytes[1, 2, 3], 1, 1), id: 7) }.not_nil!
        rig.last.should eq("\e_Ga=t,i=7,f=24,t=d,s=1,v=1;AQID\e\\")
        ack.ok?.should be_true
        ack.error.should be_nil
        ack.image.should eq(7)
      end
    end

    it "transmits and displays with every placement key" do
      rig do |rig|
        placement = Term::Placement.new(id: 3, x: 1, y: 2, width: 3, height: 4, offset_x: 5, offset_y: 6, columns: 7, rows: 8, z: -9, hold_cursor: true, placeholder: true, parent: 10, parent_placement: 11, shift_x: 12, shift_y: -13)
        rig.term.image(Term::Pixels.png(Bytes[9]), placement: placement, transient: true).should be_nil
        rig.expect("\e_Ga=T,N=1,f=100,t=d,p=3,x=1,y=2,w=3,h=4,X=5,Y=6,c=7,r=8,z=-9,C=1,U=1,P=10,Q=11,H=12,V=-13;CQ==\e\\")
      end
    end

    it "chunks large direct data with only m on continuation chunks" do
      rig do |rig|
        data = Bytes.new(4 * 40 * 40) { |index| (index % 253).to_u8 }
        rig.ask(/\e_Ga=t,i=5.*?m=0;[^\e]*\e\\/m, apc("i=5;OK")) { rig.term.image(Term::Pixels.rgba(data, 40, 40), id: 5) }
        codes = rig.last.scan(/\e_G([^;]*);([^\e]*)\e\\/)
        codes.map(&.[1]).should eq(["a=t,i=5,f=32,t=d,s=40,v=40,m=1", "m=1", "m=0"])
        codes.map(&.[2].bytesize).should eq([4096, 4096, 344])
        Base64.decode(codes.join(&.[2])).should eq(data)
      end
    end

    it "does not wait when responses are suppressed or no id is given" do
      rig do |rig|
        data = Bytes.new(4000, 1_u8)
        rig.term.image(Term::Pixels.rgb(data, 40, 25), id: 5, quiet: :all).should be_nil
        rig.term.image(Term::Pixels.rgb(Bytes[1, 2, 3], 1, 1)).should be_nil
        rig.expect("\e_Ga=t,f=24,t=d,s=1,v=1;AQID\e\\")
        codes = rig.seen.scan(/\e_G([^;]*);/).map(&.[1])
        codes.should eq(["a=t,i=5,q=2,f=24,t=d,s=40,v=25,m=1", "q=2,m=0", "a=t,f=24,t=d,s=1,v=1"])
      end
    end

    it "compresses direct data and requests an id through an image number" do
      rig do |rig|
        data = Bytes.new(500, 7_u8)
        ack = rig.ask(/\e_Ga=t,I=13[^\e]*\e\\/, apc("i=99,I=13;OK")) { rig.term.image(Term::Pixels.png(data, compress: true), number: 13) }.not_nil!
        {ack.image, ack.number}.should eq({99, 13})
        match = rig.last.match!(/\e_G([^;]*);([^\e]*)\e\\/)
        match[1].should eq("a=t,I=13,f=100,t=d,S=500,o=z")
        Compress::Zlib::Reader.open(IO::Memory.new(Base64.decode(match[2])), &.getb_to_end).should eq(data)
      end
    end

    it "sends paths for file, temporary file and shared memory media" do
      rig do |rig|
        rig.term.image(Term::Pixels.at("/path/to/file.png"), quiet: :all)
        rig.term.image(Term::Pixels.at("/tmp/tty-graphics-protocol-x", :temp_file, :rgb, 10, 20), quiet: :ok)
        rig.term.image(Term::Pixels.at("/some-shared-memory-name", :shared_memory, :rgba, 10, 2, compress: true, size: 80, offset: 10))
        rig.expect("\e_Ga=t,q=2,f=100,t=f;#{b64("/path/to/file.png")}\e\\" \
                   "\e_Ga=t,q=1,f=24,t=t,s=10,v=20;#{b64("/tmp/tty-graphics-protocol-x")}\e\\" \
                   "\e_Ga=t,f=32,t=s,s=10,v=2,S=80,O=10,o=z;#{b64("/some-shared-memory-name")}\e\\")
      end
    end

    it "places an image and returns the terminal's error" do
      rig do |rig|
        ack = rig.ask(/\e_Ga=p[^\e]*\e\\/, apc("i=9,p=3;ENOENT:image not found")) do
          rig.term.place(id: 9, placement: Term::Placement.new(id: 3, columns: 4, rows: 2, placeholder: true))
        end.not_nil!
        rig.last.should eq("\e_Ga=p,i=9,p=3,c=4,r=2,U=1\e\\")
        ack.ok?.should be_false
        ack.error.should eq("ENOENT:image not found")
        ack.placement.should eq(3)
      end
    end

    it "builds relative placements by image number" do
      rig do |rig|
        rig.ask(/\e_Ga=p[^\e]*\e\\/, apc("i=4,I=2,p=1;OK")) do
          rig.term.place(number: 2, placement: Term::Placement.new(id: 1, parent: 8, parent_placement: 9, shift_x: -1, shift_y: 2))
        end.not_nil!.image.should eq(4)
        rig.last.should eq("\e_Ga=p,I=2,p=1,P=8,Q=9,H=-1,V=2\e\\")
      end
    end

    it "routes interleaved acknowledgements to the matching request" do
      rig do |rig|
        results = Channel({Int32, Term::Ack?}).new(2)
        spawn { results.send({1, rig.term.place(id: 1)}) }
        spawn { results.send({2, rig.term.place(id: 2)}) }
        rig.expect(/\e_Ga=p,i=\d\e\\\e_Ga=p,i=\d\e\\/)
        rig.feed apc("i=2;EINVAL") + apc("i=1;OK")
        acks = {results.receive, results.receive}.to_h
        acks[1].not_nil!.message.should eq("OK")
        acks[2].not_nil!.message.should eq("EINVAL")
      end
    end

    it "deletes by every documented target" do
      rig do |rig|
        rig.term.delete_images
        rig.term.delete_images(:id, id: 10)
        rig.term.delete_images(:id, id: 10, placement: 7)
        rig.term.delete_images(:z, free: true, z: -1)
        rig.term.delete_images(:cell, x: 3, y: 4)
        rig.term.delete_images(:number, free: true, number: 13)
        rig.term.delete_images(:range, x: 2, y: 9)
        rig.term.delete_images(:cell_z, free: true, x: 3, y: 4, z: 5)
        rig.term.delete_images(:frames, id: 2)
        rig.expect("\e_Ga=d,d=a\e\\\e_Ga=d,d=i,i=10\e\\\e_Ga=d,d=i,i=10,p=7\e\\\e_Ga=d,d=Z,z=-1\e\\\e_Ga=d,d=p,x=3,y=4\e\\\e_Ga=d,d=N,I=13\e\\\e_Ga=d,d=r,x=2,y=9\e\\\e_Ga=d,d=Q,x=3,y=4,z=5\e\\\e_Ga=d,d=f,i=2\e\\")
        Term::DELETES.values.sort.join.should eq("acfinpqrxyz")
      end
    end

    it "transmits animation frames and keeps a=f on continuation chunks" do
      rig do |rig|
        rig.term.frame(Term::Pixels.rgb(Bytes.new(3), 1, 1), id: 5, x: 1, y: 2, base: 3, edit: 4, gap: -1, replace: true, background: 4278190335, quiet: :all)
        rig.expect("\e_Ga=f,i=5,q=2,x=1,y=2,c=3,r=4,z=-1,X=1,Y=4278190335,f=24,t=d,s=1,v=1;AAAA\e\\")
        ack = rig.ask(/\e_Ga=f,I=3.*?m=0;[^\e]*\e\\/m, apc("i=8,I=3;OK")) { rig.term.frame(Term::Pixels.rgb(Bytes.new(3600), 40, 30), number: 3, gap: 40) }.not_nil!
        ack.image.should eq(8)
        rig.last.scan(/\e_G([^;]*);/).map(&.[1]).should eq(["a=f,I=3,z=40,f=24,t=d,s=40,v=30,m=1", "a=f,m=0"])
      end
    end

    it "controls animations" do
      rig do |rig|
        rig.term.animate(id: 3, current: 7).should be_nil
        rig.term.animate(id: 7, target: 3, gap: 48)
        rig.term.animate(number: 2, state: :loop, loops: 1)
        rig.term.animate(id: 2, state: Term::Playback::Stop)
        rig.term.animate(id: 2, state: Term::Playback::Loading)
        rig.expect("\e_Ga=a,i=3,q=2,c=7\e\\\e_Ga=a,i=7,q=2,r=3,z=48\e\\\e_Ga=a,I=2,q=2,s=3,v=1\e\\\e_Ga=a,i=2,q=2,s=1\e\\\e_Ga=a,i=2,q=2,s=2\e\\")
      end
    end

    it "composes frames and can wait for the result" do
      rig do |rig|
        rig.term.compose(7, 9, id: 1, width: 23, height: 27, source_x: 4, source_y: 8, x: 1, y: 3, replace: true).should be_nil
        rig.expect("\e_Ga=c,i=1,q=2,r=7,c=9,w=23,h=27,X=4,Y=8,x=1,y=3,C=1\e\\")
        ack = rig.ask(/\e_Ga=c,i=1,r=1,c=2\e\\/, apc("i=1;ENOENT")) { rig.term.compose(1, 2, id: 1, quiet: :none) }.not_nil!
        ack.error.should eq("ENOENT")
      end
    end

    it "detects support when the query is answered before device attributes" do
      rig do |rig|
        rig.ask(/\e_Ga=q,i=31,f=24,t=d,s=1,v=1;AAAA\e\\\e\[c/, apc("i=31;OK") + DA1) { rig.term.supports_graphics? }.should be_true
        rig.ask(/\e_Ga=q,i=31[^\e]*\e\\\e\[c/, apc("i=31;OK") + DA1) { rig.term.supports_graphics? }.should be_true
      end
    end

    it "detects no support when device attributes arrive first" do
      rig do |rig|
        rig.ask(/\e_Ga=q,i=31[^\e]*\e\\\e\[c/, DA1) { rig.term.supports_graphics? }.should be_false
        rig.ask(/\e_Ga=q,i=31[^\e]*\e\\\e\[c/, apc("i=31;EINVAL:nope") + DA1) { rig.term.supports_graphics? }.should be_false
        rig.ask(/\e_Ga=q,i=31[^\e]*\e\\\e\[c/, apc("i=31;OK") + DA1) { rig.term.supports_graphics? }.should be_true
      end
    end

    it "returns the load result of an image query" do
      rig do |rig|
        ack = rig.ask(/\e_Ga=q,i=44,f=100,t=s;[^\e]*\e\\\e\[c/, apc("i=44;EBADF:Failed to read image file") + DA1) do
          rig.term.image_query(Term::Pixels.at("/name", :shared_memory), id: 44)
        end.not_nil!
        ack.error.should eq("EBADF:Failed to read image file")
      end
    end

    it "builds Unicode placeholder rows" do
      rows = Term.placeholder(42, 2, 2)
      rows.should eq([
        "\e[38;2;0;0;42m\u{10EEEE}̅̅\u{10EEEE}̅̍\e[39m",
        "\e[38;2;0;0;42m\u{10EEEE}̍̅\u{10EEEE}̍̍\e[39m",
      ])
    end

    it "carries the high id byte in a third diacritic and the placement in the underline color" do
      Term.placeholder(33554474, 1, 1, 0x010203).should eq(["\e[38;2;0;0;42m\e[58;2;1;2;3m\u{10EEEE}̅̅̎\e[39m\e[59m"])
      Term.placeholder(0x00abcdef, 1, 3).last.should eq("\e[38;2;171;205;239m\u{10EEEE}̎̅\e[39m")
      Term::DIACRITICS.size.should eq(297)
      Term::DIACRITICS.first(4).should eq([0x0305, 0x030d, 0x030e, 0x0310])
      Term::DIACRITICS.uniq.size.should eq(297)
    end
  end

  describe "desktop notifications" do
    it "sends a one-shot notification and returns its generated id" do
      rig do |rig|
        id = rig.term.notify("Hello world")
        rig.expect(/\e\]99;i=([0-9a-f-]{36}):e=1;#{Regex.escape(b64("Hello world"))}\e\\/)[1].should eq(id)
      end
    end

    it "sends every option, then body, buttons and icon data with the done flag last" do
      rig do |rig|
        icon = Bytes.new(3000) { |index| (index % 200).to_u8 }
        id = rig.term.notify("Title", "Body", id: "n1", report: true, closes: true, app: "demo", types: ["im", "email"], icons: ["info", "demo"], icon: icon, icon_key: "k1", buttons: ["Yes", "No"], sound: "silent", urgency: Term::Urgency::Critical, expires: 5.seconds, occasion: Term::Occasion::Invisible)
        id.should eq("n1")
        rig.expect(/\e\]99;i=n1:p=icon:e=1:g=k1;[^\e]*\e\\/)
        codes = rig.seen.scan(/\e\]99;([^;]*);([^\e]*)\e\\/).map { |match| {match[1], match[2]} }
        codes.map(&.[0]).should eq([
          "i=n1:a=report,focus:c=1:f=#{b64("demo")}:t=#{b64("im")}:t=#{b64("email")}:n=#{b64("info")}:n=#{b64("demo")}:g=k1:o=invisible:s=#{b64("silent")}:u=2:w=5000:e=1:d=0",
          "i=n1:p=body:e=1:d=0",
          "i=n1:p=buttons:e=1:d=0",
          "i=n1:p=icon:e=1:g=k1:d=0",
          "i=n1:p=icon:e=1:g=k1",
        ])
        Base64.decode_string(codes[0][1]).should eq("Title")
        Base64.decode_string(codes[1][1]).should eq("Body")
        Base64.decode_string(codes[2][1]).should eq("Yes No")
        chunks = codes[3..].map { |code| Base64.decode(code[1]) }
        chunks.map(&.size).should eq([2048, 952])
        (chunks[0] + chunks[1]).should eq(icon)
      end
    end

    it "encodes the action set" do
      rig do |rig|
        rig.term.notify("a", id: "x", focus: false)
        rig.term.notify("a", id: "y", focus: false, report: true)
        rig.term.notify("a", id: "z", expires: Time::Span.zero, urgency: Term::Urgency::Low)
        rig.expect("\e]99;i=x:a=-focus:e=1;YQ==\e\\\e]99;i=y:a=report,-focus:e=1;YQ==\e\\\e]99;i=z:u=0:w=0:e=1;YQ==\e\\")
      end
    end

    it "chunks long text on character boundaries" do
      rig do |rig|
        title = "a" + "é" * 1500
        rig.term.notify(title, id: "long")
        rig.expect(/\e\]99;i=long:e=1;[^\e]*\e\\/)
        codes = rig.seen.scan(/\e\]99;([^;]*);([^\e]*)\e\\/).map { |match| {match[1], Base64.decode(match[2])} }
        codes.map(&.[0]).should eq(["i=long:e=1:d=0", "i=long:e=1"])
        codes.map(&.[1].size).should eq([2047, 954])
        codes.all? { |code| String.new(code[1]).valid_encoding? }.should be_true
        codes.join { |code| String.new(code[1]) }.should eq(title)
      end
    end

    it "sends an empty notice, a cached icon reference and a close request" do
      rig do |rig|
        rig.term.notify(Term::Notice.new(id: "e"))
        rig.term.notify(Term::Notice.new(body: "only body", id: "b", icon_key: "k1"))
        rig.term.close_notification("b")
        rig.expect("\e]99;i=e;\e\\\e]99;i=b:g=k1:p=body:e=1;#{b64("only body")}\e\\\e]99;i=b:p=close;\e\\")
      end
    end

    it "reports activation, button and close events" do
      rig do |rig|
        rig.feed osc("99;i=n1;") + osc("99;i=n1;2") + osc("99;i=n1:p=close;") + osc("99;i=n2:p=close;untracked") + osc("99;;")
        activated = rig.event(Term::Notification)
        {activated.kind, activated.id, activated.button}.should eq({Term::Notification::Kind::Activated, "n1", 0})
        button = rig.event(Term::Notification)
        {button.kind, button.button}.should eq({Term::Notification::Kind::Button, 2})
        closed = rig.event(Term::Notification)
        {closed.kind, closed.untracked}.should eq({Term::Notification::Kind::Closed, false})
        untracked = rig.event(Term::Notification)
        {untracked.id, untracked.untracked}.should eq({"n2", true})
        rig.event(Term::Notification).id.should eq("0")
      end
    end

    it "queries live notifications" do
      rig do |rig|
        reply = ->(match : Regex::MatchData) { osc("99;i=#{match[1]}:p=alive;id1,id2,id3") }
        rig.ask(/\e\]99;i=([^:]+):p=alive;\e\\/, reply) { rig.term.notifications_alive }.should eq(["id1", "id2", "id3"])
        empty = ->(match : Regex::MatchData) { osc("99;i=#{match[1]}:p=alive;") }
        rig.ask(/\e\]99;i=([^:]+):p=alive;\e\\/, empty) { rig.term.notifications_alive }.should eq([] of String)
      end
    end

    it "queries support and reports none when device attributes arrive first" do
      rig do |rig|
        reply = ->(match : Regex::MatchData) { osc("99;i=#{match[1]}:p=?;a=report,focus:c=1:o=always:p=title,body,icon:s=system,silent:u=0,1,2:w=1") + DA1 }
        support = rig.ask(/\e\]99;i=([^:]+):p=\?;\e\\\e\[c/, reply) { rig.term.notification_support }.not_nil!
        support["a"].should eq(["report", "focus"])
        support["p"].should eq(["title", "body", "icon"])
        support["u"].should eq(["0", "1", "2"])
        support["w"].should eq(["1"])
        rig.ask(/\e\]99;i=([^:]+):p=\?;\e\\\e\[c/, DA1) { rig.term.notification_support }.should be_nil
      end
    end
  end

  describe "drag and drop" do
    it "starts and stops accepting drops, and stops on close" do
      reader, feed = IO.pipe
      screen, writer = IO.pipe
      term = Term.new(Term::Config.new, reader, writer)
      term.accept_drops
      term.accept_drops("text/plain", "application/x-private")
      term.stop_drops
      term.accept_drops
      term.offer_drags
      feed.close
      term.close
      writer.close
      screen.gets_to_end.should eq(SETUP + "\e]72;t=a\e\\\e]72;t=a;text/plain application/x-private\e\\\e]72;t=A\e\\\e]72;t=a\e\\\e]72;t=o:x=1\e\\\e]72;t=A\e\\\e]72;t=o:x=2\e\\" + TEARDOWN)
    end

    it "hashes the machine id and sends it for remote drops and drags" do
      path = "/etc/machine-id"
      if File.exists?(path)
        expected = "1:#{OpenSSL::HMAC.hexdigest(:sha256, "tty-dnd-protocol-machine-id", File.read(path).rstrip)}"
        Term.machine_id.should eq(expected)
        expected.should match(/\A1:[0-9a-f]{64}\z/)
        rig do |rig|
          rig.term.accept_drops("text/uri-list", remote: true)
          rig.term.offer_drags(remote: true)
          rig.expect("\e]72;t=a;text/uri-list\e\\\e]72;t=a:x=1;#{expected}\e\\\e]72;t=o:x=1;#{expected}\e\\")
        end
      else
        Term.machine_id.should be_nil
      end
    end

    it "adds the multiplexer id to every code" do
      config = Term::Config.new
      config.dnd_id = 7
      rig(config) do |rig|
        rig.term.accept_drops
        rig.term.drop_reply(:move)
        rig.term.drag_presend(1, "hi".to_slice)
        rig.expect("\e]72;t=a:i=7\e\\\e]72;t=m:o=2:i=7\e\\\e]72;t=p:x=1:i=7:m=1;aGk=\e\\\e]72;t=p:x=1:i=7:m=0\e\\")
      end
    end

    it "reports drop moves, leaves and the drop itself" do
      rig do |rig|
        rig.feed osc("72;t=m:x=1:y=2:X=10:Y=20:o=3;text/uri-list text/plain") + osc("72;t=m:x=2:y=2:X=30:Y=20:o=3") + osc("72;t=m:x=-1:y=-1") + osc("72;t=M:x=4:y=5:X=40:Y=50:o=1;text/uri-list")
        move = rig.event(Term::Drop)
        {move.kind, move.col, move.row, move.x, move.y}.should eq({Term::Drop::Kind::Move, 1, 2, 10, 20})
        move.operations.should eq(Term::Operation::Copy | Term::Operation::Move)
        move.mimes.should eq(["text/uri-list", "text/plain"])
        rig.event(Term::Drop).mimes.should be_nil
        leave = rig.event(Term::Drop)
        {leave.kind, leave.col, leave.row}.should eq({Term::Drop::Kind::Leave, -1, -1})
        land = rig.event(Term::Drop)
        {land.kind, land.col, land.row, land.operations}.should eq({Term::Drop::Kind::Land, 4, 5, Term::Operation::Copy})
        land.mimes.should eq(["text/uri-list"])
      end
    end

    it "assembles a chunked MIME list using the first chunk's metadata" do
      rig do |rig|
        rig.feed osc("72;t=m:x=1:y=2:o=2:m=1;text/pl") + osc("72;m=1;ain image") + osc("72;m=0;/png")
        move = rig.event(Term::Drop)
        {move.col, move.row, move.operations}.should eq({1, 2, Term::Operation::Move})
        move.mimes.should eq(["text/plain", "image/png"])
      end
    end

    it "accepts, rejects and finishes drops" do
      rig do |rig|
        rig.term.drop_reply(:copy, "text/uri-list", "text/plain")
        rig.term.drop_reply
        rig.term.drop_close(5)
        rig.term.drop_finish(:move)
        rig.term.drop_finish
        rig.expect("\e]72;t=m:o=1;text/uri-list text/plain\e\\\e]72;t=m\e\\\e]72;t=r:Y=5\e\\\e]72;t=r:o=2\e\\\e]72;t=r:o=0\e\\")
      end
    end

    it "reads dropped data sent in unpadded chunks and sees the remote flag" do
      rig do |rig|
        encoded = b64("file:///a\r\n#comment\r\nfile:///d/\r\n").rstrip('=')
        reply = osc("72;t=r:x=1:X=1:m=1;#{encoded[0, 10]}") + osc("72;t=r:x=1:m=1;#{encoded[10..]}") + osc("72;t=r:x=1;")
        data = rig.ask(/\e\]72;t=r:x=1\e\\/, reply) { rig.term.drop_data(1) }.not_nil!
        data.ok?.should be_true
        data.remote?.should be_true
        data.symlink?.should be_false
        data.uris.should eq(["file:///a", "file:///d/"])
      end
    end

    it "reads a single unchunked response and reports errors" do
      rig do |rig|
        data = rig.ask(/\e\]72;t=r:x=2\e\\/, osc("72;t=r:x=2;#{b64("plain")}")) { rig.term.drop_data(2) }.not_nil!
        data.text.should eq("plain")
        data.remote?.should be_false
        failed = rig.ask(/\e\]72;t=r:x=3\e\\/, osc("72;t=R:x=3;EPERM:not dropped yet")) { rig.term.drop_data(3) }.not_nil!
        failed.ok?.should be_false
        failed.error.should eq("EPERM:not dropped yet")
        failed.data.should be_empty
      end
    end

    it "reads remote files, symlinks and directories" do
      rig do |rig|
        file = rig.ask(/\e\]72;t=r:x=1:y=1\e\\/, osc("72;t=r:x=1:y=1:X=0:m=1;#{b64("data")}") + osc("72;t=r:x=1:y=1;")) { rig.term.drop_data(1, 1) }.not_nil!
        {file.text, file.symlink?, file.directory?}.should eq({"data", false, false})
        link = rig.ask(/\e\]72;t=r:x=1:y=2\e\\/, osc("72;t=r:x=1:y=2:X=1;#{b64("target")}")) { rig.term.drop_data(1, 2) }.not_nil!
        {link.text, link.symlink?, link.remote?}.should eq({"target", true, false})
        dir = rig.ask(/\e\]72;t=r:x=1:y=3\e\\/, osc("72;t=r:x=1:y=3:X=5;#{b64("a\0b\0sub")}")) { rig.term.drop_data(1, 3) }.not_nil!
        {dir.directory?, dir.handle, dir.entries}.should eq({true, 5, ["a", "b", "sub"]})
        child = rig.ask(/\e\]72;t=r:Y=5:x=3\e\\/, osc("72;t=r:Y=5:x=3:X=6;#{b64("c")}")) { rig.term.drop_entry(5, 3) }.not_nil!
        {child.directory?, child.handle, child.entries}.should eq({true, 6, ["c"]})
        gone = rig.ask(/\e\]72;t=r:Y=5:x=2\e\\/, osc("72;t=R:Y=5:x=2;ENOENT")) { rig.term.drop_entry(5, 2) }.not_nil!
        gone.error.should eq("ENOENT")
      end
    end

    it "matches interleaved responses to their requests" do
      rig do |rig|
        results = Channel({Int32, String?}).new(2)
        spawn { results.send({1, rig.term.drop_data(1, 1).try(&.text)}) }
        spawn { results.send({2, rig.term.drop_data(1, 2).try(&.text)}) }
        rig.expect(/\e\]72;t=r:x=1:y=\d\e\\\e\]72;t=r:x=1:y=\d\e\\/)
        rig.feed osc("72;t=r:x=1:y=2:m=1;#{b64("two")}") + osc("72;t=r:x=1:y=1:m=1;#{b64("one")}") + osc("72;t=r:x=1:y=2;") + osc("72;t=r:x=1:y=1;")
        {results.receive, results.receive}.to_h.should eq({1 => "one", 2 => "two"})
      end
    end

    it "offers drags and reports the start gesture" do
      rig do |rig|
        rig.term.offer_drags
        rig.term.stop_drags
        rig.expect("\e]72;t=o:x=1\e\\\e]72;t=o:x=2\e\\")
        rig.feed osc("72;t=o:x=3:y=4:X=30:Y=40")
        gesture = rig.event(Term::Drag)
        {gesture.kind, gesture.col, gesture.row, gesture.x, gesture.y}.should eq({Term::Drag::Kind::Gesture, 3, 4, 30, 40})
      end
    end

    it "sends the offer, chunking a long MIME list" do
      rig do |rig|
        rig.term.drag_offer(Term::Operation::Copy | Term::Operation::Move, "text/plain", "text/uri-list")
        rig.expect("\e]72;t=o:o=3;text/plain text/uri-list\e\\")
        mimes = {"a/" + "a" * 1500, "b/" + "b" * 1500, "c/" + "c" * 1500}
        rig.term.drag_offer(Term::Operation::Copy, *mimes)
        rig.expect(/\e\]72;t=o:o=1;[^\e]*\e\\/)
        codes = rig.seen.scan(/\e\]72;([^;]*);([^\e]*)\e\\/).map { |match| {match[1], match[2]} }
        codes.map(&.[0]).should eq(["t=o:o=1:m=1", "t=o:o=1"])
        codes[0][1].bytesize.should eq(4096)
        codes.join(&.[1]).should eq(mimes.join(' '))
      end
    end

    it "pre-sends data as a stream ended by an empty chunk" do
      rig do |rig|
        data = Bytes.new(5000) { |index| (index % 199).to_u8 }
        rig.term.drag_presend(0, data)
        rig.expect("\e]72;t=p:m=0\e\\")
        codes = rig.seen.scan(/\e\]72;([^;\e]*);([^\e]*)\e\\/).map { |match| {match[1], match[2]} }
        codes.map(&.[0]).should eq(["t=p:m=1", "t=p:m=1"])
        codes.map(&.[1].bytesize).should eq([4096, 2572])
        Base64.decode(codes.join(&.[1])).should eq(data)
        rig.term.drag_presend(2, "hi".to_slice)
        rig.expect("\e]72;t=p:x=2:m=1;aGk=\e\\\e]72;t=p:x=2:m=0\e\\")
      end
    end

    it "sends drag images, text images and image changes" do
      rig do |rig|
        rig.term.drag_image(1, Bytes[1, 2, 3, 4], :rgba, 1, 1)
        rig.term.drag_image(2, Bytes[9], :png, 16, 16)
        rig.term.drag_text(3, "X", 2, 1, 512)
        rig.term.drag_show(1)
        rig.term.drag_show(0)
        rig.expect("\e]72;t=p:x=-1:y=32:X=1:Y=1:m=1;AQIDBA==\e\\\e]72;t=p:x=-1:y=32:X=1:Y=1:m=0\e\\" \
                   "\e]72;t=p:x=-2:y=100:X=16:Y=16:m=1;CQ==\e\\\e]72;t=p:x=-2:y=100:X=16:Y=16:m=0\e\\" \
                   "\e]72;t=p:x=-3:X=2:Y=1:o=512:m=1;WA==\e\\\e]72;t=p:x=-3:X=2:Y=1:o=512:m=0\e\\" \
                   "\e]72;t=P:x=1\e\\\e]72;t=P\e\\")
      end
    end

    it "starts the drag and returns the terminal's answer" do
      rig do |rig|
        rig.ask(/\e\]72;t=P:x=-1\e\\/, osc("72;t=E;OK")) { rig.term.drag_start }.should eq("OK")
        rig.ask(/\e\]72;t=P:x=-1\e\\/, osc("72;t=E;EPERM")) { rig.term.drag_start }.should eq("EPERM")
      end
    end

    it "reports unsolicited drag errors and status events" do
      rig do |rig|
        rig.feed osc("72;t=E;EFBIG") + osc("72;t=E;OK") + osc("72;t=e:x=1:y=2") + osc("72;t=e:x=2:o=2") + osc("72;t=e:x=3") + osc("72;t=e:x=5:y=1") + osc("72;t=k:x=4") + osc("72;t=e:x=4:y=1") + osc("72;t=e:x=4:y=0")
        error = rig.event(Term::Drag)
        {error.kind, error.error}.should eq({Term::Drag::Kind::Error, "EFBIG"})
        rig.event(Term::Drag).kind.should eq(Term::Drag::Kind::Started)
        accepted = rig.event(Term::Drag)
        {accepted.kind, accepted.index}.should eq({Term::Drag::Kind::Accepted, 2})
        action = rig.event(Term::Drag)
        {action.kind, action.operation}.should eq({Term::Drag::Kind::Action, Term::Operation::Move})
        rig.event(Term::Drag).kind.should eq(Term::Drag::Kind::Dropped)
        request = rig.event(Term::Drag)
        {request.kind, request.index}.should eq({Term::Drag::Kind::DataRequest, 1})
        file = rig.event(Term::Drag)
        {file.kind, file.index}.should eq({Term::Drag::Kind::FileRequest, 4})
        canceled = rig.event(Term::Drag)
        {canceled.kind, canceled.canceled}.should eq({Term::Drag::Kind::Finished, true})
        rig.event(Term::Drag).canceled.should be_false
      end
    end

    it "answers data requests and reports failures and cancellation" do
      rig do |rig|
        rig.term.drag_data(1, "payload".to_slice)
        rig.term.drag_data(0, Bytes.empty)
        rig.term.drag_fail(1, "ENOENT", "no such type")
        rig.term.drag_fail(0, "EIO")
        rig.term.drag_abort("EIO", "read failed")
        rig.term.drag_cancel
        rig.expect("\e]72;t=e:y=1:m=1;#{b64("payload")}\e\\\e]72;t=e:y=1:m=0\e\\\e]72;t=e:m=0\e\\\e]72;t=E:y=1;ENOENT:no such type\e\\\e]72;t=E;EIO\e\\\e]72;t=E;EIO:read failed\e\\\e]72;t=E:y=-1\e\\")
      end
    end

    it "sends uri-list entries for files, symlinks and directory children" do
      rig do |rig|
        rig.term.drag_entry(1, "data".to_slice)
        rig.term.drag_entry(2, "target".to_slice, 1)
        rig.term.drag_entry(3, "a\0b".to_slice, 2)
        rig.term.drag_entry(3, "x".to_slice, 0, 2, 1)
        rig.expect("\e]72;t=k:x=1:m=1;#{b64("data")}\e\\\e]72;t=k:x=1:m=0\e\\" \
                   "\e]72;t=k:x=2:X=1:m=1;#{b64("target")}\e\\\e]72;t=k:x=2:X=1:m=0\e\\" \
                   "\e]72;t=k:x=3:X=2:m=1;#{b64("a\0b")}\e\\\e]72;t=k:x=3:X=2:m=0\e\\" \
                   "\e]72;t=k:x=3:Y=2:y=1:m=1;#{b64("x")}\e\\\e]72;t=k:x=3:Y=2:y=1:m=0\e\\")
      end
    end

    it "sends a directory tree breadth first with every child" do
      root = File.tempname("term-spec")
      Dir.mkdir_p(File.join(root, "sub"))
      File.write(File.join(root, "a.txt"), "hello")
      File.write(File.join(root, "sub", "b.txt"), "deep")
      File.symlink("a.txt", File.join(root, "link"))
      begin
        rig do |rig|
          rig.term.drag_path(1, root)
          rig.expect("\e]72;t=k:x=1:Y=3:y=1:m=0\e\\")
          heads = rig.seen.scan(/\e\]72;([^;\e]*);([^\e]*)\e\\/).map { |match| {match[1], Base64.decode_string(match[2])} }
          heads.should eq([
            {"t=k:x=1:X=2:m=1", "a.txt\0link\0sub"},
            {"t=k:x=1:Y=2:y=1:m=1", "hello"},
            {"t=k:x=1:X=1:Y=2:y=2:m=1", "a.txt"},
            {"t=k:x=1:X=3:Y=2:y=3:m=1", "b.txt"},
            {"t=k:x=1:Y=3:y=1:m=1", "deep"},
          ])
          rig.seen.scan(/:m=0\e\\/).size.should eq(5)
        end
      ensure
        FileUtils.rm_rf(root)
      end
    end

    it "aborts the drag with the error name when a path cannot be read" do
      rig do |rig|
        rig.term.drag_path(1, "/nonexistent/term-spec")
        rig.expect("\e]72;t=E;ENOENT\e\\")
      end
    end

    it "detects support" do
      rig do |rig|
        rig.ask(/\e\]72;t=q\e\\\e\[c/, osc("72;t=q;") + DA1) { rig.term.supports_dnd? }.should be_true
        rig.ask(/\e\]72;t=q\e\\\e\[c/, DA1) { rig.term.supports_dnd? }.should be_false
      end
    end
  end

  describe "robustness" do
    it "returns nil when a query times out and still answers the next one" do
      config = Term::Config.new
      config.query_timeout = 40.milliseconds
      rig(config) do |rig|
        rig.term.pointer.should be_nil
        rig.term.supports?(5522).should be_nil
        rig.term.window_size.should be_nil
        rig.term.place(id: 3).should be_nil
        rig.term.supports_graphics?.should be_false
        rig.term.supports_dnd?.should be_false
        rig.term.notification_support.should be_nil
        rig.term.notifications_alive.should be_nil
        rig.term.colors("foreground").should be_nil
        rig.term.drag_start(limit: 40.milliseconds).should be_nil
        rig.term.drop_data(1, limit: 40.milliseconds).should be_nil
        rig.term.copy("x", limit: 40.milliseconds).should be_nil
        rig.term.clipboard_read("text/plain", limit: 40.milliseconds).should be_nil
        rig.expect(/type=read:id=term;[^\e]*\e\\/)
        rig.ask(/\e\[14t/, "\e[4;600;800t") { rig.term.window_size(2.seconds) }.should eq(Term::Size.new(800, 600))
      end
    end

    it "ignores plain bytes, unknown sequences and unsolicited replies" do
      rig do |rig|
        rig.feed "hello\r\n\exyz\e[5n\e[>1;2;3c\e[?1;2c\e]22;pointer\e\\\e]21;foreground=red\e\\\e_Gi=1;OK\e\\\e]99;i=q:p=alive;a\e\\\e]72;t=r:x=1;AAAA\e\\\e]72;t=q;\e\\\eP1$r0m\e\\\e^private\e\\\e]7;file:///x\a\e[4;1;2t" + press('a')
        key = rig.event(Term::Key)
        key.code.should eq(97)
      end
    end

    it "recovers from sequences interrupted by a new escape" do
      rig do |rig|
        rig.feed "\e[12;\e[97u\e]99;i=a\e[98u\e_Gi=1\e[99u"
        Array.new(3) { rig.event(Term::Key).code }.should eq([97, 98, 99])
      end
    end

    it "parses a sequence split across reads" do
      rig do |rig|
        "\e[97;5u".each_char do |char|
          rig.feed char.to_s
          sleep 2.milliseconds
        end
        key = rig.event(Term::Key)
        {key.code, key.ctrl?}.should eq({97, true})
      end
    end

    it "ignores invalid base64 in drag and drop data and keeps running" do
      rig do |rig|
        config_limit = 60.milliseconds
        result = Channel(Term::DropData?).new(1)
        spawn { result.send(rig.term.drop_data(1, limit: config_limit)) }
        rig.expect("\e]72;t=r:x=1\e\\")
        rig.feed osc("72;t=r:x=1;@@@@") + press('a')
        rig.event(Term::Key).code.should eq(97)
        result.receive.should be_nil
      end
    end

    it "keeps escape sequences from concurrent writers intact" do
      rig do |rig|
        done = Channel(Nil).new
        8.times do |writer|
          spawn do
            20.times { rig.term.color(writer, "rgb:00/00/00") }
            done.send(nil)
          end
        end
        8.times { done.receive }
        rig.term.print "END"
        rig.expect("END")
        codes = rig.seen.rchop("END").scan(/\e\]21;(\d)=rgb:00\/00\/00\e\\/)
        codes.size.should eq(160)
        codes.sum(&.[0].bytesize).should eq(rig.seen.rchop("END").bytesize)
      end
    end
  end
end