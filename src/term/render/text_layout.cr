# src/term/render/text_layout.cr
module Term::Render
  enum Wrap
    Word
    Grapheme
  end

  module TextLayout
    extend self

    NEWLINE  = 0x0A_u8
    TAB      = 0x09_u8
    TAB_SIZE =       8

    def width(text : String) : Int32
      width = 0
      Graphemes.each(text) { |_, span| width += span.to_i }
      width
    end

    def clusters(text : String) : Array(String)
      clusters = [] of String
      Graphemes.each(text) { |cluster, _| clusters << String.new(cluster) }
      clusters
    end

    def lines(text : String) : Array(String)
      text.split('\n')
    end

    def expand_tabs(text : String, size : Int32 = TAB_SIZE) : String
      return text unless text.includes?('\t')

      String.build do |io|
        column = 0
        Graphemes.each(text) do |cluster, span|
          first = cluster.unsafe_fetch(0)

          if cluster.size == 1 && first == TAB
            pad = size - column % size
            pad.times { io << ' ' }
            column += pad
          else
            io.write(cluster)
            column = cluster.size == 1 && first == NEWLINE ? 0 : column + span.to_i
          end
        end
      end
    end

    def wrap(text : String, width : Int32, mode : Wrap = Wrap::Word) : Array(String)
      case mode
      in Wrap::Word     then wrap_words(text, width)
      in Wrap::Grapheme then wrap_graphemes(text, width)
      end
    end

    def truncate(text : String, width : Int32, tail : String = "") : String
      return "" if width <= 0
      return text if width(text) <= width

      limit = width - width(tail)

      String.build do |io|
        used = 0
        Graphemes.each(text) do |cluster, span|
          break if used + span.to_i > limit
          io.write(cluster)
          used += span.to_i
        end
        io << tail
      end
    end

    def offset(text : String, width : Int32, align : HorizontalAlignment) : Int32
      align.offset(width(text), width)
    end

    def column(text : String, index : Int32) : Int32
      column = 0
      count = 0
      Graphemes.each(text) do |_, span|
        break if count >= index
        column += span.to_i
        count += 1
      end
      column
    end

    def index(text : String, column : Int32) : Int32
      index = 0
      edge = 0
      Graphemes.each(text) do |_, span|
        edge += span.to_i
        break if column < edge
        index += 1
      end
      index
    end

    private def wrap_words(text : String, width : Int32) : Array(String)
      lines = [] of String
      text.split('\n').each { |paragraph| fold(paragraph, width, lines) }
      lines
    end

    private def fold(paragraph : String, width : Int32, lines : Array(String)) : Nil
      if width <= 0 || width(paragraph) <= width
        lines << paragraph
        return
      end

      line = nil.as(String?)

      paragraph.split(' ').each do |word|
        candidate = line ? "#{line} #{word}" : word

        if width(candidate) <= width
          line = candidate
          next
        end

        lines << line if line

        if width(word) <= width
          line = word
        else
          split(word, width, lines)
          line = lines.pop
        end
      end

      lines << line if line
    end

    private def wrap_graphemes(text : String, width : Int32) : Array(String)
      lines = [] of String

      text.split('\n').each do |paragraph|
        if width <= 0 || paragraph.empty?
          lines << paragraph
        else
          split(paragraph, width, lines)
        end
      end

      lines
    end

    private def split(text : String, width : Int32, lines : Array(String)) : Nil
      line = IO::Memory.new
      used = 0

      Graphemes.each(text) do |cluster, span|
        extent = span.to_i

        if used > 0 && used + extent > width
          lines << line.to_s
          line.clear
          used = 0
        end

        line.write(cluster)
        used += extent
      end

      lines << line.to_s
    end
  end

  enum HorizontalAlignment
    Left
    Center
    Right

    def offset(content : Int32, available : Int32) : Int32
      case self
      in HorizontalAlignment::Left   then 0
      in HorizontalAlignment::Center then Math.max((available - content) // 2, 0)
      in HorizontalAlignment::Right  then Math.max(available - content, 0)
      end
    end
  end

  enum VerticalAlignment
    Top
    Middle
    Bottom

    def offset(content : Int32, available : Int32) : Int32
      case self
      in VerticalAlignment::Top    then 0
      in VerticalAlignment::Middle then Math.max((available - content) // 2, 0)
      in VerticalAlignment::Bottom then Math.max(available - content, 0)
      end
    end
  end
end
