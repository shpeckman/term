# src/term/engine.cr
class Term
  IDLE = 1.hour

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

  private class Wheel
    property mouse : Mouse?
    property count   = 0
    property closes  = Time::Span.zero
    property emitted = Time::Span.zero
  end

  private class Node
    getter children = {} of Int32 => Node
    property action : String?
  end

  @backlog = Deque(Event).new
  @locks  : Mods?
  @anchor : Mouse?
  @held       = {} of Int32 => Held
  @latched    = Set(String).new
  @lone       = Set(Int32).new
  @timers     = [] of Timer
  @physical   = {} of {Int32, Mods} => String
  @symbolic   = {} of {Int32, Mods} => String
  @root       = Node.new
  @node       = Node.new
  @last_press = Time::Span.zero
  @tap_code   = 0
  @tap_at     = Time::Span.zero
  @tap_count  = 0
  @buttons    = Set(Mouse::Button).new
  @press : Mouse?
  @press_at = Time::Span.zero
  @last : Mouse?
  @last_at = Time::Span.zero
  @click : Mouse?
  @click_at    = Time::Span.zero
  @click_count = 0
  @wheels      = {Wheel.new, Wheel.new}
  @dragging    = false
  @inside      = false
  @dwelling    = false

  private def setup_engine : Nil
    @node = @root
    @config.sequences.each do |name, codes|
      codes.reduce(@root) { |node, code| node.children.put_if_absent(code) { Node.new } }.action = name
    end
    @config.shortcuts.each do |name, shortcut|
      (shortcut.physical ? @physical : @symbolic)[{shortcut.code, shortcut.mods}] = name
    end
  end

  private def run_engine : Nil
    loop do
      if head = @backlog.first?
        select
        when @events.send(head)
          @backlog.shift
        when raw = @raw.receive?
          break unless raw
          track(raw, clock)
        when timeout(patience)
          nil
        end
      else
        select
        when raw = @raw.receive?
          break unless raw
          track(raw, clock)
        when timeout(patience)
          nil
        end
      end
      now = clock
      @timers.reject! do |timer|
        next false if timer.at > now
        fire(timer, now)
        true
      end
    end
    @backlog.each { |event| @events.send(event) }
  rescue Channel::ClosedError
  ensure
    @events.close
    @raw.close
  end

  private def patience : Time::Span
    deadline = @timers.min_of?(&.at) || return IDLE
    {deadline - clock, Time::Span.zero}.max
  end

  private def emit(event : Event) : Nil
    @backlog.shift if @backlog.size >= @config.event_backlog
    @backlog << event
  end

  private def arm(kind : Timer::Kind, now : Time::Span, delay : Time::Span, code : Int32 = 0) : Nil
    @timers.reject! { |timer| timer.kind == kind && timer.code == code }
    @timers << Timer.new(now + delay, kind, code)
  end

  private def fire(timer : Timer, now : Time::Span) : Nil
    case timer.kind
    in .hold?
      @held[timer.code]?.try { |held| hold(held) }
    in .sequence?
      @node = @root
    in .dwell?
      last = @last
      if last && @inside && !@dwelling
        @dwelling = true
        emit MouseGesture.new(:hover_dwell, last.copy_with(action: Mouse::Action::Hover, button: Mouse::Button::None))
      end
    in .long_press?
      press = @press
      emit MouseGesture.new(:long_press, press) if press && !@dragging
    in .scroll?
      flush_scroll(@wheels[timer.code], now)
    end
  end

  private def track(raw : Raw, now : Time::Span) : Nil
    if raw.is_a?(Mouse) && raw.action.leave?
      raw = @last.try { |last| raw.copy_with(x: last.x, y: last.y, col: last.col, row: last.row) } || raw
    end
    emit raw
    case raw
    when Key   then track_key(raw, now)
    when Mouse then track_mouse(raw, now)
    end
  end

  private def track_key(key : Key, now : Time::Span) : Nil
    toggled(key.mods & LOCKS) if features.keyboard?
    if key.command?
      emit KeyCommand.new(key)
    elsif !key.release?
      key.text.try { |text| emit TextInput.new(text) }
    end
    case key.action
    in .press?   then pressed(key, now)
    in .repeat?  then repeated(key)
    in .release? then released(key, now)
    end
    park if @saved && @config.job_control && key.press? && key.code == 'z'.ord && (key.mods & ~LOCKS) == Mods::Ctrl
  end

  private def toggled(locks : Mods) : Nil
    previous = @locks
    @locks   = locks
    return unless previous
    {Mods::CapsLock, Mods::NumLock}.each do |lock|
      emit Lock.new(lock, locks.includes?(lock)) if (previous ^ locks).includes?(lock)
    end
  end

  private def pressed(key : Key, now : Time::Span) : Nil
    code = key.code
    @held[code] = Held.new(key, now, @last_press.zero? ? @last_press : now - @last_press, @held.size)
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
        emit KeyGesture.new(:multi_tap, key, @tap_count)
      end
      emit TypingMetric.new(code, now - held.at, held.latency, held.overlap)
    end
    @latched.to_a.each do |name|
      @latched.delete(name) unless @config.chords[name].all? { |member| @held.has_key?(member) }
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
    physical = @physical[key.stroke(true)]?
    symbolic = @symbolic[key.stroke]?
    emit Binding.new(:shortcut, physical) if physical
    emit Binding.new(:shortcut, symbolic) if symbolic
  end

  private def track_mouse(mouse : Mouse, now : Time::Span) : Nil
    if mouse.action.leave?
      @inside = false
      @anchor = nil
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
    anchor = @anchor
    radius = @config.hover_radius
    return if anchor && (mouse.x - anchor.x) ** 2 + (mouse.y - anchor.y) ** 2 <= radius * radius
    @anchor = mouse
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
    axis   = mouse.button.wheel_left? || mouse.button.wheel_right? ? 1 : 0
    wheel  = @wheels[axis]
    turned = wheel.mouse.try(&.button) != mouse.button
    flush_scroll(wheel, now) if turned
    wheel.mouse = mouse
    wheel.count += 1
    if turned || (wheel.count == 1 && now >= wheel.closes)
      flush_scroll(wheel, now, turned || now - wheel.emitted > @config.scroll_pause)
    elsif now >= wheel.closes
      flush_scroll(wheel, now)
    elsif wheel.count == 1
      arm(:scroll, now, wheel.closes - now, axis)
    end
  end

  private def flush_scroll(wheel : Wheel, now : Time::Span, rested : Bool = false) : Nil
    mouse = wheel.mouse || return
    count = wheel.count
    return if count == 0
    span = {now - wheel.emitted, @config.scroll_window}.max
    wheel.count = 0
    wheel.emitted = now
    wheel.closes = now + @config.scroll_window
    emit MouseGesture.new(:scroll, mouse, count, 0, 0, rested || span <= Time::Span.zero ? 0.0 : count / span.total_seconds)
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
