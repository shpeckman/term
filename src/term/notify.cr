# src/term/notify.cr
class Term
  SEPARATOR  = ' '
  TEXT_CHUNK = 2048

  enum Urgency
    Low
    Normal
    Critical
  end

  enum Occasion
    Always
    Unfocused
    Invisible
  end

  record Notice, title : String = "", body : String = "", id : String? = nil, app : String? = nil, types : Array(String) = [] of String, icons : Array(String) = [] of String, icon : Bytes? = nil, icon_key : String? = nil, buttons : Array(String) = [] of String, sound : String? = nil, urgency : Urgency? = nil, expires : Time::Span? = nil, occasion : Occasion = Occasion::Always, focus : Bool = true, report : Bool = false, closes : Bool = false

  record Notification, kind : Kind, id : String, button : Int32 = 0, untracked : Bool = false do
    enum Kind
      Activated
      Button
      Closed
    end
  end

  @icons = Set(String).new

  def notify(notice : Notice) : String
    id      = ident(notice.id || UUID.random.to_s)
    cache   = notice.icon_key.try { |key| ident(key) }
    actions = "#{"report," if notice.report}#{"-" unless notice.focus}focus"
    meta = String.build do |io|
      io << "i=" << id
      io << ":a=" << actions unless actions == "focus"
      io << ":c=1" if notice.closes
      notice.app.try { |app| io << ":f=" << Base64.strict_encode(app) }
      notice.types.each { |type| io << ":t=" << Base64.strict_encode(type) }
      notice.icons.each { |icon| io << ":n=" << Base64.strict_encode(icon) }
      cache.try { |key| io << ":g=" << key }
      io << ":o=" << notice.occasion.to_s.downcase unless notice.occasion.always?
      notice.sound.try { |sound| io << ":s=" << Base64.strict_encode(sound) }
      notice.urgency.try { |urgency| io << ":u=" << urgency.value }
      notice.expires.try { |span| io << ":w=" << span.total_milliseconds.to_i }
    end
    exclusive(Family::Notify) do
      parts = [] of {String, String}
      slices(notice.title.to_slice, true).each { |chunk| parts << {"title", chunk} }
      slices(notice.body.to_slice, true).each { |chunk| parts << {"body", chunk} }
      slices(notice.buttons.join(SEPARATOR).to_slice, true).each { |chunk| parts << {"buttons", chunk} }
      icon = notice.icon
      if icon && !(cache && @icons.includes?(cache))
        slices(icon, false).each { |chunk| parts << {"icon", chunk} }
        cache.try { |key| @icons << key }
      end
      parts << {"title", ""} if parts.empty?
      sequence = String.build do |io|
        parts.each_with_index do |(type, chunk), index|
          io << "\e]99;" << (index == 0 ? meta : "i=#{id}")
          io << ":p=" << type unless type == "title"
          io << ":e=1" unless chunk.empty?
          cache.try { |key| io << ":g=" << key } if type == "icon" && index > 0
          io << ":d=0" unless index == parts.size - 1
          io << ';' << chunk << ST
        end
      end
      @output.send(sequence)
    end
    id
  end

  def notify(title : String, body : String = "", **options) : String
    notify(Notice.new(**options, title: title, body: body))
  end

  def close_notification(id : String) : Nil
    exclusive(Family::Notify) { @output.send("\e]99;i=#{ident(id)}:p=close;#{ST}") }
  end

  def notifications_alive(limit : Time::Span = @config.query_timeout) : Array(String)?
    id = UUID.random.to_s
    request(Query::NotifyAlive, "\e]99;i=#{id}:p=alive;#{ST}", limit, id).as?(Array(String))
  end

  def notification_support(limit : Time::Span = @config.query_timeout) : Hash(String, Array(String))?
    id = UUID.random.to_s
    request(Query::NotifySupport, "\e]99;i=#{id}:p=?;#{ST}", limit, id, true).as?(Hash(String, Array(String)))
  end

  private def slices(data : Bytes, text : Bool) : Array(String)
    chunks = [] of String
    offset = 0
    while offset < data.size
      size = Math.min(TEXT_CHUNK, data.size - offset)
      if text
        while size > 1 && offset + size < data.size && data[offset + size] & 0xc0 == 0x80
          size -= 1
        end
      end
      chunks << Base64.strict_encode(data[offset, size])
      offset += size
    end
    chunks
  end

  private def notified(meta : Hash(String, String), payload : String) : Nil
    id = meta["i"]? || "0"
    case meta["p"]?
    when "?"
      route(Query::NotifySupport, fields(payload).transform_values(&.split(',')), id)
    when "alive"
      route(Query::NotifyAlive, payload.split(',', remove_empty: true), id)
    when "close"
      push Notification.new(:closed, id, untracked: payload == "untracked")
    when nil, "title"
      button = payload.to_i? || 0
      push Notification.new(button > 0 ? Notification::Kind::Button : Notification::Kind::Activated, id, button)
    end
  end
end
