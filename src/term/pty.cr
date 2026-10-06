# src/term/pty.cr
require "./tty"

class Term
  class PTY
    getter master  : IO::FileDescriptor
    getter slave   : IO::FileDescriptor?
    getter name    : String
    getter process : Process?

    def self.open(window : TTY::Window? = nil) : PTY
      master = TTY::Lib.posix_openpt(LibC::O_RDWR | TTY::O_NOCTTY)
      raise IO::Error.from_errno("posix_openpt") if master < 0
      if TTY::Lib.grantpt(master) != 0 || TTY::Lib.unlockpt(master) != 0
        error = IO::Error.from_errno("grantpt")
        LibC.close(master)
        raise error
      end
      name  = String.new(TTY::Lib.ptsname(master))
      slave = LibC.open(name, LibC::O_RDWR | TTY::O_NOCTTY | LibC::O_CLOEXEC)
      if slave < 0
        error = IO::Error.from_errno("open")
        LibC.close(master)
        raise error
      end
      pty = new(IO::FileDescriptor.new(master), IO::FileDescriptor.new(slave), name)
      pty.master.close_on_exec = true
      window.try { |size| pty.window = size }
      pty
    end

    def self.spawn(command : String, args : Enumerable(String) = [] of String, env : Hash(String, String) = {} of String => String, window : TTY::Window? = nil) : PTY
      path     = Process.find_executable(command) || raise IO::Error.new("command not found: #{command}")
      strings  = [path] + args.to_a
      settings = ENV.to_h.merge(env)
      settings["TERM"] ||= "xterm-256color"
      pairs = settings.map { |key, value| "#{key}=#{value}" }
      argv  = strings.map(&.to_unsafe) << Pointer(UInt8).null
      envp  = pairs.map(&.to_unsafe) << Pointer(UInt8).null
      pty   = open(window)
      blocked = uninitialized LibC::SigsetT
      previous = uninitialized LibC::SigsetT
      LibC.sigfillset(pointerof(blocked))
      LibC.pthread_sigmask(LibC::SIG_SETMASK, pointerof(blocked), pointerof(previous))
      pid = LibC.fork
      execute(pty.name.to_unsafe, path.to_unsafe, argv.to_unsafe, envp.to_unsafe, pointerof(previous)) if pid == 0
      error = Errno.value
      LibC.pthread_sigmask(LibC::SIG_SETMASK, pointerof(previous), nil)
      if pid < 0
        pty.close
        raise IO::Error.from_os_error("fork", error)
      end
      pty.adopt(pid)
      pty
    end

    private def self.execute(name : UInt8*, path : UInt8*, argv : UInt8**, envp : UInt8**, mask : LibC::SigsetT*) : NoReturn
      signal = 1
      while signal < 32
        LibC.signal(signal, LibC::SIG_DFL)
        signal += 1
      end
      TTY::Lib.setsid
      fd = LibC.open(name, LibC::O_RDWR)
      LibC._exit(126) if fd < 0
      TTY::Lib.ioctl(fd, TTY::TIOCSCTTY, 0)
      LibC.dup2(fd, 0)
      LibC.dup2(fd, 1)
      LibC.dup2(fd, 2)
      LibC.close(fd) if fd > 2
      LibC.pthread_sigmask(LibC::SIG_SETMASK, mask, nil)
      LibC.execve(path, argv, envp)
      LibC._exit(127)
    end

    def initialize(@master : IO::FileDescriptor, @slave : IO::FileDescriptor?, @name : String)
    end

    protected def adopt(pid : LibC::PidT) : Nil
      @process = Process.new(Crystal::System::Process.new(pid))
      @slave.try &.close
      @slave = nil
    end

    def window : TTY::Window?
      TTY.window(@master.fd)
    end

    def window=(window : TTY::Window) : TTY::Window
      TTY.resize(@master.fd, window)
      window
    end

    def mode : LibC::Termios?
      TTY.mode(@master.fd)
    end

    def mode=(mode : LibC::Termios) : LibC::Termios
      TTY.apply(@master.fd, mode)
      mode
    end

    def <<(text : String) : self
      @master << text
      @master.flush
      self
    end

    def rest : String
      String.build do |io|
        chunk = Bytes.new(4096)
        loop do
          count = @master.read(chunk)
          break if count == 0
          io.write(chunk[0, count])
        end
      rescue error : IO::Error
        raise error if error.is_a?(IO::TimeoutError)
      end
    end

    def close : Nil
      @slave.try &.close
      @master.close
    rescue IO::Error
    end
  end
end
