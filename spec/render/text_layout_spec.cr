# spec/render/text_layout_spec.cr
require "./support"

describe Term::Render::TextLayout do
  it "measures text in cells and splits it into grapheme clusters" do
    Term::Render::TextLayout.width("a日b").should eq(4)
    Term::Render::TextLayout.clusters("é日").should eq(["é", "日"])
  end

  it "wraps at word boundaries and breaks words that are too long" do
    Term::Render::TextLayout.wrap("hello world", 8).should eq(["hello", "world"])
    Term::Render::TextLayout.wrap("one two\nthree", 20).should eq(["one two", "three"])
    Term::Render::TextLayout.wrap("abcdefgh", 3).should eq(["abc", "def", "gh"])
    Term::Render::TextLayout.wrap("", 5).should eq([""])
  end

  it "wraps at any grapheme without splitting a wide one" do
    Term::Render::TextLayout.wrap("abcdef", 4, Term::Render::Wrap::Grapheme).should eq(["abcd", "ef"])
    Term::Render::TextLayout.wrap("a日本語", 3, Term::Render::Wrap::Grapheme).should eq(["a日", "本", "語"])
    Term::Render::TextLayout.wrap("ab\ncd", 0, Term::Render::Wrap::Grapheme).should eq(["ab", "cd"])
  end

  it "truncates to a width with an optional tail" do
    Term::Render::TextLayout.truncate("abcdef", 4).should eq("abcd")
    Term::Render::TextLayout.truncate("abcdef", 4, "…").should eq("abc…")
    Term::Render::TextLayout.truncate("日本語", 3, "…").should eq("日…")
    Term::Render::TextLayout.truncate("abc", 5, "…").should eq("abc")
    Term::Render::TextLayout.truncate("abc", 0, "…").should eq("")
  end

  it "maps between grapheme indexes and columns" do
    Term::Render::TextLayout.column("a日b", 0).should eq(0)
    Term::Render::TextLayout.column("a日b", 2).should eq(3)
    Term::Render::TextLayout.column("a日b", 9).should eq(4)
    Term::Render::TextLayout.index("a日b", 0).should eq(0)
    Term::Render::TextLayout.index("a日b", 1).should eq(1)
    Term::Render::TextLayout.index("a日b", 2).should eq(1)
    Term::Render::TextLayout.index("a日b", 3).should eq(2)
    Term::Render::TextLayout.index("a日b", 9).should eq(3)
  end

  it "offsets text for an alignment" do
    Term::Render::TextLayout.offset("日本", 10, Term::Render::HorizontalAlignment::Right).should eq(6)
    Term::Render::TextLayout.offset("abcd", 10, Term::Render::HorizontalAlignment::Center).should eq(3)
  end
end

describe Term::Render::TextLayout do
  it "breaks an over-long word wherever it falls and keeps blank lines" do
    Term::Render::TextLayout.wrap("aaaaaaaaaaaa bb", 5).should eq(["aaaaa", "aaaaa", "aa bb"])
    Term::Render::TextLayout.wrap("x aaaaaaaa", 5).should eq(["x", "aaaaa", "aaa"])
    Term::Render::TextLayout.wrap("a\n\nb", 5).should eq(["a", "", "b"])
    Term::Render::TextLayout.wrap("abcd\nef", 4, Term::Render::Wrap::Grapheme).should eq(["abcd", "ef"])
    Term::Render::TextLayout.wrap("a\n\nb", 4, Term::Render::Wrap::Grapheme).should eq(["a", "", "b"])
  end

  it "expands tabs to tab stops" do
    Term::Render::TextLayout.expand_tabs("a\tb").should eq("a       b")
    Term::Render::TextLayout.expand_tabs("ab\tc\n\td", 4).should eq("ab  c\n    d")
    Term::Render::TextLayout.expand_tabs("plain").should eq("plain")
  end
end
