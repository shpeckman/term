# src/term/render/theme.cr
class ::Term
  module Render
    enum ColorDepth
      Ansi16
      Indexed256
      TrueColor

      def self.detect(colorterm : String? = ENV["COLORTERM"]?, term : String? = ENV["TERM"]?) : ColorDepth
        mode = (colorterm || "").downcase
        name = (term || "").downcase
        return TrueColor if DEPTH_MODES.includes?(mode)
        DEPTH_TERMS.each do |marker, depth|
          return depth if name.includes?(marker)
        end
        Indexed256
      end
    end

    DEPTH_MODES = {"truecolor", "24bit"}

    DEPTH_TERMS = {
      {"kitty",     ColorDepth::TrueColor},
      {"ghostty",   ColorDepth::TrueColor},
      {"wezterm",   ColorDepth::TrueColor},
      {"alacritty", ColorDepth::TrueColor},
      {"foot",      ColorDepth::TrueColor},
      {"contour",   ColorDepth::TrueColor},
      {"iterm",     ColorDepth::TrueColor},
      {"direct",    ColorDepth::TrueColor},
      {"256",       ColorDepth::Indexed256},
      {"linux",     ColorDepth::Ansi16},
      {"vt100",     ColorDepth::Ansi16},
      {"vt220",     ColorDepth::Ansi16},
      {"ansi",      ColorDepth::Ansi16},
      {"dumb",      ColorDepth::Ansi16},
    }

    enum ThemeDelivery
      Auto
      Push
      Local
    end

    enum ThemeMode
      Auto
      Dark
      Light
    end

    enum PaletteSource
      Terminal
      Generated
      Explicit
    end

    enum Easing
      Linear
      In
      Out
      InOut

      def apply(amount : Float64) : Float64
        case self
        in Linear then amount
        in In     then amount * amount * amount
        in Out    then 1.0 - (1.0 - amount) ** 3
        in InOut  then amount < 0.5 ? 4.0 * amount * amount * amount : 1.0 - (2.0 - 2.0 * amount) ** 3 / 2.0
        end
      end
    end

    struct Blend
      getter from   : Paint
      getter to     : Paint
      getter amount : Float32

      def initialize(@from : Paint, @to : Paint, @amount : Float32)
      end
    end

    alias RoleSpec = Paint | Blend

    module Roles
      DEFAULTS = [
        Paint.background,
        Paint.foreground,
        Blend.new(Paint.background, Paint.foreground, 0.08_f32),
        Blend.new(Paint.foreground, Paint.background, 0.45_f32),
        Blend.new(Paint.background, Paint.foreground, 0.25_f32),
        Paint.index(4),
        Blend.new(Paint.background, Paint.role(Core::Accent.value), 0.35_f32),
        Paint.index(1),
        Paint.index(3),
        Paint.index(2),
      ] of RoleSpec

      def default(slot : Int32) : RoleSpec
        DEFAULTS[slot]? || Paint.foreground
      end
    end

    class Theme
      getter name       : String
      getter source     : PaletteSource
      getter harmonious : Bool

      @fg : UInt32?
      @bg : UInt32?

      def initialize(@name : String, @source : PaletteSource, @colors : Array(UInt32),
                     @fg : UInt32?, @bg : UInt32?, @harmonious : Bool)
        @roles = {} of Int32 => RoleSpec
      end

      def self.rgb(value : Term::Color) : UInt32
        ColorSpace.pack(value)
      end

      def self.rgb(value : Int) : UInt32
        raise ArgumentError.new("color #{value} is outside 0x000000..0xFFFFFF") unless 0 <= value <= 0xFFFFFF
        value.to_u32
      end

      def self.rgb(value : String) : UInt32
        rgb(Term::Color.parse(value) || raise ArgumentError.new("invalid color #{value.inspect}"))
      end

      def role(name : String | Symbol, value : Blend) : Nil
        @roles[Roles.slot(name)] = value
      end

      def role(name : String | Symbol, value) : Nil
        @roles[Roles.slot(name)] = Paint.fg(value)
      end

      def mix(from, to, amount : Float64) : Blend
        Blend.new(Paint.fg(from), Paint.fg(to), amount.clamp(0.0, 1.0).to_f32)
      end

      def spec(slot : Int32) : RoleSpec
        @roles[slot]? || Roles.default(slot)
      end

      def palette(terminal : Palette) : Palette
        case @source
        in PaletteSource::Terminal
          terminal.dup
        in PaletteSource::Generated
          Palette.generate(@colors, @fg || @colors[7], @bg || @colors[0], @harmonious)
        in PaletteSource::Explicit
          Palette.new(Slice(UInt32).new(Palette::SIZE) { |index| @colors[index] },
            @fg || @colors[7], @bg || @colors[0])
        end
      end
    end

    class ::ByteBuilder
      def color_rgb(value : UInt32) : self
        str("rgb:").hex2((value >> 16).to_u8!).char('/').hex2((value >> 8).to_u8!).char('/').hex2(value.to_u8!)
      end
    end

    class Themes
      STEP       = 16.milliseconds
      RESET      = "\e]104\e\\\e]110\e\\\e]111\e\\"
      PUSH       = "\e]30001\e\\"
      POP        = "\e]30101\e\\"
      ROLE_DEPTH = 8

      getter palette   : Palette
      getter terminal  : Palette
      getter queried   : Palette
      getter current   : Theme?
      getter mode      : ThemeMode
      getter delivery  : ThemeDelivery
      getter depth     : ColorDepth
      getter? snap     : Bool
      getter? indexed  : Bool
      getter? known    : Bool
      getter? querying : Bool

      property duration        : Time::Span
      property easing          : Easing
      property space           : BlendSpace
      property? extend_palette : Bool

      property output : Proc(ByteBuilder) = -> : ByteBuilder { raise "Themes#output is not wired" }
      property running : Proc(Bool) = -> { false }
      property querier : Proc(Proc(Term::Palette?, Nil), Nil) = ->(done : Proc(Term::Palette?, Nil)) { done.call(nil) }
      property ticker : Proc(Time::Span, Proc(Nil), Proc(Nil)) = ->(span : Time::Span, tick : Proc(Nil)) { -> { nil } }
      property on_theme : Proc(String?, Nil) = ->(name : String?) { nil }
      property on_palette : Proc(Nil) = -> { nil }

      @dark        : String?
      @light       : String?
      @system_dark : Bool?
      @animation   : (-> Nil)?

      def initialize
        @queried        = Palette.stock
        @terminal       = Palette.stock
        @palette        = Palette.stock
        @themes         = {} of String => Theme
        @roles          = [] of Paint
        @current        = nil
        @mode           = ThemeMode::Auto
        @delivery       = ThemeDelivery::Auto
        @depth          = ColorDepth.detect
        @snap           = false
        @indexed        = true
        @known          = false
        @querying       = false
        @pushed         = false
        @stacked        = false
        @query          = 0
        @duration       = 250.milliseconds
        @easing         = Easing::InOut
        @space          = BlendSpace::Oklab
        @extend_palette = true
        @dark           = nil
        @light          = nil
        @system_dark    = nil
        @animation      = nil
        @roles          = settle(nil, @palette)
      end

      def open : Nil
        refresh_palette
        show(@palette, @roles)
      end

      def close : Nil
        halt
        @query += 1
        @querying = false
        restore
      end

      def system_dark=(dark : Bool?) : Bool?
        @system_dark = dark
        follow(@duration) if @mode.auto?
        dark
      end

      def define(name : String | Symbol, *, base16 : Indexable? = nil, palette : Indexable? = nil,
                 fg = nil, bg = nil, harmonious : Bool = false) : Theme
        source = PaletteSource::Terminal
        colors = [] of UInt32
        if entries = palette
          raise ArgumentError.new("palette needs #{Palette::SIZE} colors") unless entries.size == Palette::SIZE
          source = PaletteSource::Explicit
          colors = entries.map { |entry| Theme.rgb(entry) }.to_a
        elsif entries = base16
          raise ArgumentError.new("base16 needs 16 colors") unless entries.size == 16
          source = PaletteSource::Generated
          colors = entries.map { |entry| Theme.rgb(entry) }.to_a
        end
        theme = Theme.new(name.to_s, source, colors, fg.try { |value| Theme.rgb(value) },
          bg.try { |value| Theme.rgb(value) }, harmonious)
        replaced = @current.try(&.name) == theme.name
        @themes[theme.name] = theme
        if replaced
          @current = theme
          rebuild unless transitioning?
        end
        theme
      end

      def define(name : String | Symbol, *, base16 : Indexable? = nil, palette : Indexable? = nil,
                 fg = nil, bg = nil, harmonious : Bool = false, & : Theme ->) : Theme
        theme = define(name, base16: base16, palette: palette, fg: fg, bg: bg, harmonious: harmonious)
        yield theme
        rebuild if @current.same?(theme) && !transitioning?
        theme
      end

      def [](name : String | Symbol) : Theme
        @themes[name.to_s]? || raise ArgumentError.new("unknown theme #{name.to_s.inspect}")
      end

      def pair(dark : String | Symbol, light : String | Symbol, mode : ThemeMode = ThemeMode::Auto) : Nil
        @dark  = self[dark].name
        @light = self[light].name
        @mode  = mode
        follow(Time::Span.zero)
      end

      def mode=(mode : ThemeMode) : ThemeMode
        @mode = mode
        follow(@duration)
        mode
      end

      def toggle : Nil
        self.mode = dark? ? ThemeMode::Light : ThemeMode::Dark
      end

      def dark? : Bool
        case @mode
        in ThemeMode::Dark  then true
        in ThemeMode::Light then false
        in ThemeMode::Auto
          system = @system_dark
          system.nil? ? !@queried.light? : system
        end
      end

      def use(name : String | Symbol | Nil) : Nil
        go(name.try { |key| self[key] }, Time::Span.zero, @easing)
      end

      def transition(to : String | Symbol | Nil, duration : Time::Span = @duration,
                     easing : Easing = @easing) : Nil
        go(to.try { |key| self[key] }, duration, easing)
      end

      def transitioning? : Bool
        !@animation.nil?
      end

      def delivery=(delivery : ThemeDelivery) : ThemeDelivery
        @delivery = delivery
        restore
        rebuild unless transitioning?
        delivery
      end

      def depth=(depth : ColorDepth) : ColorDepth
        @depth = depth
        on_palette.call
        depth
      end

      def snap=(snap : Bool) : Bool
        @snap = snap
        on_palette.call
        snap
      end

      def themed_palette? : Bool
        @queried.themed?
      end

      def role(name : String | Symbol) : Paint
        Paint.role(name)
      end

      @[AlwaysInline]
      def resolve(slot : Int32) : Paint
        @roles = settle(@current, @palette) if slot >= @roles.size
        @roles.unsafe_fetch(slot)
      end

      def refresh_palette : Nil
        return unless running.call
        restore
        @querying = true
        serial    = (@query += 1)
        querier.call(->(found : Term::Palette?) { learn(found) if serial == @query })
      end

      def self.survey(term : Term) : Term::Palette?
        {% begin %}
          term.colors({% for index in 0...Palette::SIZE %}{{index}}, {% end %}"foreground", "background")
        {% end %}
      end

      def learn(found : Term::Palette?) : Nil
        return unless @querying
        if found
          Palette::SIZE.times do |index|
            color = found[index.to_s]? || next
            @queried[index] = Theme.rgb(color)
            @known = true
          end
          found["foreground"]?.try { |color| @queried.fg = Theme.rgb(color) }
          found["background"]?.try { |color| @queried.bg = Theme.rgb(color) }
        end
        finish_query
      end

      private def finish_query : Nil
        return unless @querying
        @querying = false
        @terminal.copy(@queried)
        return if transitioning?
        wanted = @mode.auto? ? (dark? ? @dark : @light) : nil
        if wanted && wanted != @current.try(&.name)
          follow(Time::Span.zero)
        else
          rebuild
        end
      end

      private def rebuild : Nil
        goal = target(@current)
        show(goal, settle(@current, goal))
      end

      private def follow(duration : Time::Span) : Nil
        name = (dark? ? @dark : @light) || return
        go(@themes[name]?, duration, @easing)
      end

      private def pushing? : Bool
        return false if @querying || !running.call
        @delivery.push? || (@delivery.auto? && @known)
      end

      private def target(theme : Theme?) : Palette
        if theme.nil? || theme.source.terminal?
          if @extend_palette && @known && !@delivery.local? && !@queried.themed?
            Palette.generate(@queried.colors[0, 16], @queried.fg, @queried.bg)
          else
            @queried.dup
          end
        else
          theme.palette(@queried)
        end
      end

      private def go(theme : Theme?, duration : Time::Span, easing : Easing) : Nil
        halt
        before   = @current
        goal     = target(theme)
        roles    = settle(theme, goal)
        @current = theme
        native   = (before.nil? || before.source.terminal?) && (theme.nil? || theme.source.terminal?)
        reduced  = !pushing? && !@depth.true_color?
        if duration <= Time::Span.zero || !running.call || native || reduced
          show(goal, roles)
          on_theme.call(theme.try(&.name))
          return
        end
        origin  = @palette.dup
        started = Time.instant
        shades  = @roles.map { |paint| Pile.rgb(paint, origin) }
        paints  = @roles.dup
        @animation = ticker.call(STEP, -> {
          amount = ((Time.instant - started) / duration).clamp(0.0, 1.0)
          if amount >= 1.0
            halt
            show(goal, roles)
            on_theme.call(theme.try(&.name))
          else
            eased = easing.apply(amount).to_f32
            show(Palette.mix(origin, goal, eased, @space), blend(paints, shades, roles, goal, eased))
          end
        })
      end

      private def halt : Nil
        @animation.try(&.call)
        @animation = nil
      end

      private def blend(paints : Array(Paint), shades : Array(UInt32), roles : Array(Paint),
                        goal : Palette, amount : Float32) : Array(Paint)
        Array(Paint).new(roles.size) do |slot|
          final = roles[slot]
          start = paints[slot]? || final
          if start == final && !final.kind.rgb?
            final
          else
            Paint.rgb(ColorSpace.mix(shades[slot]? || Pile.rgb(final, goal), Pile.rgb(final, goal), amount, @space))
          end
        end
      end

      private def settle(theme : Theme?, palette : Palette) : Array(Paint)
        Array(Paint).new(Roles.count) { |slot| flatten(theme, slot, palette, 0) }
      end

      private def flatten(theme : Theme?, slot : Int32, palette : Palette, depth : Int32) : Paint
        spec = theme ? theme.spec(slot) : Roles.default(slot)
        case spec
        in Paint
          direct(theme, spec, palette, depth)
        in Blend
          from = Pile.rgb(direct(theme, spec.from, palette, depth), palette)
          to   = Pile.rgb(direct(theme, spec.to, palette, depth), palette)
          Paint.rgb(ColorSpace.mix(from, to, spec.amount, @space))
        end
      end

      private def direct(theme : Theme?, paint : Paint, palette : Palette, depth : Int32) : Paint
        return paint unless paint.role?
        return Paint.foreground if depth >= ROLE_DEPTH
        flatten(theme, paint.value.to_i32!, palette, depth + 1)
      end

      private def show(palette : Palette, roles : Array(Paint)) : Nil
        @palette = palette
        @roles   = roles
        if pushing?
          push(palette)
          @indexed = true
        else
          @indexed = palette.same?(@terminal)
        end
        on_palette.call
      end

      private def push(palette : Palette) : Nil
        return if palette.same?(@terminal)
        target = output.call
        unless @pushed
          @pushed  = true
          @stacked = @known
          target.str(PUSH) if @stacked
        end
        Palette::SIZE.times do |index|
          next if palette[index] == @terminal[index]
          target.osc(4).int(index).semi.color_rgb(palette[index]).st
        end
        target.osc(10).color_rgb(palette.fg).st unless palette.fg == @terminal.fg
        target.osc(11).color_rgb(palette.bg).st unless palette.bg == @terminal.bg
        @terminal.copy(palette)
      end

      private def restore : Nil
        return unless @pushed
        output.call.str(@stacked ? POP : RESET)
        @pushed  = false
        @stacked = false
        @terminal.copy(@queried)
      end
    end
  end
end
