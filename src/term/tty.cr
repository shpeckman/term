# src/term/tty.cr
module TTY
  {% if flag?(:linux) %}
    TIOCGWINSZ = 0x5413
    TIOCSWINSZ = 0x5414
    TIOCSCTTY  = 0x540e
    O_NOCTTY   =  0o400
  {% else %}
    TIOCGWINSZ = 0x40087468
    TIOCSWINSZ = 0x80087467
    TIOCSCTTY  = 0x20007461
    O_NOCTTY   =    0x20000
  {% end %}

  lib Lib
    struct Winsize
      rows   : UInt16
      cols   : UInt16
      width  : UInt16
      height : UInt16
    end

    fun ioctl(fd : LibC::Int, request : LibC::ULong, ...) : LibC::Int
    fun setsid : LibC::PidT
    fun posix_openpt(flags : LibC::Int) : LibC::Int
    fun grantpt(fd : LibC::Int) : LibC::Int
    fun unlockpt(fd : LibC::Int) : LibC::Int
    fun ptsname(fd : LibC::Int) : LibC::Char*
  end

  record Window, rows : Int32, cols : Int32, width : Int32 = 0, height : Int32 = 0

  def self.mode(fd : Int32) : LibC::Termios?
    mode = LibC::Termios.new
    mode if LibC.tcgetattr(fd, pointerof(mode)) == 0
  end

  def self.apply(fd : Int32, mode : LibC::Termios) : Bool
    LibC.tcsetattr(fd, LibC::TCSANOW, pointerof(mode)) == 0
  end

  def self.raw(mode : LibC::Termios) : LibC::Termios
    LibC.cfmakeraw(pointerof(mode))
    mode
  end

  def self.raw?(mode : LibC::Termios) : Bool
    mode.c_lflag & (LibC::ICANON | LibC::ECHO | LibC::ISIG) == 0 && mode.c_oflag & LibC::OPOST == 0
  end

  def self.window(fd : Int32) : Window?
    size = Lib::Winsize.new
    return unless Lib.ioctl(fd, TIOCGWINSZ, pointerof(size)) == 0
    Window.new(size.rows.to_i, size.cols.to_i, size.width.to_i, size.height.to_i)
  end

  def self.resize(fd : Int32, window : Window) : Bool
    size = Lib::Winsize.new(rows: window.rows.to_u16, cols: window.cols.to_u16, width: window.width.to_u16, height: window.height.to_u16)
    Lib.ioctl(fd, TIOCSWINSZ, pointerof(size)) == 0
  end

  def self.signal_group(signal : Signal) : Bool
    LibC.kill(0, signal.value) == 0
  end
end
