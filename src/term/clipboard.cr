# src/term/clipboard.cr
class Term
  PASTE_NAME = "UGFzdGUgZXZlbnQ="
  CHUNK      = 4095

  record Clipboard, status : Status, data : Hash(String, Bytes) do
    delegate done?, to: @status

    def text : String?
      data["text/plain"]?.try { |bytes| String.new(bytes) }
    end
  end

  private class Transfer
    getter data = {} of String => IO::Memory
    getter? solicited : Bool
    getter? primary   : Bool
    getter password   : String?
    getter sink       : IO?
    @carry = ""

    def initialize(@solicited, @primary, @password, @sink)
    end

    def add(mime : String, chunk : String) : Nil
      io = @sink || @data.put_if_absent(mime) { IO::Memory.new }
      @carry += chunk
      return unless @carry.bytesize % 4 == 0
      encoded = @carry
      @carry  = ""
      Base64.decode(encoded, io)
    end
  end

  @transfer    : Transfer?
  @credentials : String

  def copy(text : String, primary : Bool = false, limit : Time::Span = @config.clipboard_timeout) : Status?
    clipboard_write({"text/plain" => text.to_slice}, primary: primary, limit: limit)
  end

  def clipboard_write(items : Hash(String, _), aliases : Hash(String, Array(String)) = {} of String => Array(String), primary : Bool = false, limit : Time::Span = @config.clipboard_timeout) : Status?
    attempts = items.each_value.all?(Bytes) ? @config.busy_retries : 0
    loop do
      status = write(items, aliases, primary, limit)
      return status unless status && status.ebusy? && attempts > 0
      attempts -= 1
      sleep @config.busy_delay
    end
  end

  private def write(items : Hash(String, _), aliases : Hash(String, Array(String)), primary : Bool, limit : Time::Span) : Status?
    waiter = exclusive(Family::Clipboard) do
      opened = enqueue(Query::ClipboardWrite, "\e]5522;type=write#{location(primary)}#{@credentials}#{ST}")
      items.each do |mime, data|
        encoded = Base64.strict_encode(mime)
        blocks(data, CHUNK) { |text, _| @output.send("\e]5522;type=wdata:mime=#{encoded};#{text}#{ST}") }
      end
      aliases.each do |target, names|
        @output.send("\e]5522;type=walias:mime=#{Base64.strict_encode(target)};#{Base64.strict_encode(names.join(' '))}#{ST}")
      end
      @output.send("\e]5522;type=wdata#{ST}")
      opened
    end
    await(waiter, limit).as?(Status)
  end

  def clipboard_read(*mimes : String, primary : Bool = false, into : IO? = nil, limit : Time::Span = @config.clipboard_timeout) : Clipboard?
    fetch("#{location(primary)}#{@credentials}", mimes.join(' '), limit, into)
  end

  def clipboard_read(paste : Paste, *mimes : String, into : IO? = nil, limit : Time::Span = @config.clipboard_timeout) : Clipboard?
    if text = paste.text
      return Clipboard.new(Status::Done, {"text/plain" => text.to_slice}) unless into
      into << text
      return Clipboard.new(Status::Done, {} of String => Bytes)
    end
    credentials = paste.password.try { |password| ":pw=#{password}:name=#{PASTE_NAME}" }
    fetch("#{location(paste.primary)}#{credentials}", mimes.join(' '), limit, into)
  end

  def clipboard_mimes(primary : Bool = false, limit : Time::Span = @config.clipboard_timeout) : Array(String)?
    fetch(location(primary), ".", limit).try do |clipboard|
      clipboard.data["."]?.try { |bytes| String.new(bytes).split }
    end
  end

  private def location(primary : Bool) : String
    primary ? ":loc=primary" : ""
  end

  private def fetch(meta : String, mimes : String, limit : Time::Span, sink : IO? = nil) : Clipboard?
    sequence = "\e]5522;type=read:id=#{@config.clipboard_id}#{meta};#{Base64.strict_encode(mimes)}#{ST}"
    attempts = @config.busy_retries
    loop do
      waiter = exclusive(Family::Clipboard) { enqueue(Query::ClipboardRead, sequence, sink: sink) }
      reply  = await(waiter, limit).as?(Clipboard)
      return reply unless reply && reply.status.ebusy? && attempts > 0
      attempts -= 1
      sleep @config.busy_delay
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
        waiting   = peek(Query::ClipboardRead)
        solicited = meta.has_key?("id") || (!meta.has_key?("pw") && !waiting.nil?)
        @transfer = Transfer.new(solicited, meta["loc"]? == "primary", meta["pw"]?, solicited ? waiting.try(&.sink) : nil)
      when "DATA"
        @transfer.try &.add(Base64.decode_string(meta["mime"]? || ""), payload)
      when "DONE"
        finish
      else
        route(Query::ClipboardRead, Clipboard.new(Status.parse?(status) || Status::EIO, {} of String => Bytes))
      end
    end
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
end
