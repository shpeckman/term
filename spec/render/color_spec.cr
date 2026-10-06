# spec/render/color_spec.cr
require "./support"

private def close(a : UInt32, b : UInt32, slack : Int32 = 1) : Bool
  {16, 8, 0}.all? { |shift| (((a >> shift) & 0xFF).to_i - ((b >> shift) & 0xFF).to_i).abs <= slack }
end

describe Term::Render::ColorSpace do
  it "round-trips every sRGB level through linear light" do
    256.times do |level|
      Term::Render::ColorSpace.encode(Term::Render::ColorSpace.decode(level.to_u8)).should eq(level.to_u8)
    end
  end

  it "round-trips colors through CIELAB and Oklab" do
    [0x000000_u32, 0xffffff_u32, 0x1e66f5_u32, 0xf38ba8_u32, 0x40a02b_u32, 0x808080_u32].each do |rgb|
      close(Term::Render::ColorSpace.from_lab(Term::Render::ColorSpace.lab(rgb)), rgb).should be_true
      close(Term::Render::ColorSpace.from_oklab(Term::Render::ColorSpace.oklab(rgb)), rgb).should be_true
    end
  end

  it "measures CIELAB lightness" do
    Term::Render::ColorSpace.lightness(0xffffff_u32).should be_close(100.0, 0.05)
    Term::Render::ColorSpace.lightness(0x000000_u32).should be_close(0.0, 0.05)
    Term::Render::ColorSpace.lightness(0x777777_u32).should be_close(50.0, 0.6)
  end

  it "mixes in the requested space" do
    Term::Render::ColorSpace.mix(0x000000_u32, 0xffffff_u32, 0.5_f32, Term::Render::BlendSpace::Linear).should eq(0xbcbcbc_u32)
    close(Term::Render::ColorSpace.mix(0x000000_u32, 0xffffff_u32, 0.5_f32, Term::Render::BlendSpace::Lab), 0x777777_u32).should be_true
    close(Term::Render::ColorSpace.mix(0x000000_u32, 0xffffff_u32, 0.5_f32, Term::Render::BlendSpace::Oklab), 0x777777_u32, 3).should be_true
    Term::Render::BlendSpace.each do |space|
      Term::Render::ColorSpace.mix(0x123456_u32, 0xfedcba_u32, 0.0_f32, space).should eq(0x123456_u32)
      Term::Render::ColorSpace.mix(0x123456_u32, 0xfedcba_u32, 1.0_f32, space).should eq(0xfedcba_u32)
    end
  end

  it "keeps a blue to white fade free of purple in Oklab" do
    middle = Term::Render::ColorSpace.mix(0x0000ff_u32, 0xffffff_u32, 0.5_f32, Term::Render::BlendSpace::Oklab)
    ((middle >> 16) & 0xFF).should be <= ((middle >> 8) & 0xFF) + 8
  end
end

describe Term::Render::Palette do
  it "builds the stock xterm table" do
    stock = Term::Render::Palette.stock
    stock[16].should eq(0x000000_u32)
    stock[21].should eq(0x0000ff_u32)
    stock[196].should eq(0xff0000_u32)
    stock[231].should eq(0xffffff_u32)
    stock[232].should eq(0x080808_u32)
    stock[255].should eq(0xeeeeee_u32)
    stock.themed?.should be_false
  end

  it "generates the cube and ramp from base16 through CIELAB" do
    base    = DARK16.map(&.to_u32)
    palette = Term::Render::Palette.generate(base, 0xcdd6f4_u32, 0x1e1e2e_u32)
    16.times { |index| palette[index].should eq(base[index]) }
    close(palette[16], 0x1e1e2e_u32).should be_true
    close(palette[231], 0xcdd6f4_u32).should be_true
    close(palette[16 + 36 * 5], base[1]).should be_true
    close(palette[16 + 6 * 5], base[2]).should be_true
    close(palette[16 + 5], base[4]).should be_true
    palette.themed?.should be_true
    levels = (232..255).map { |index| Term::Render::ColorSpace.lightness(palette[index]) }
    levels.each_cons_pair { |low, high| high.should be > low }
    levels.first.should be > Term::Render::ColorSpace.lightness(0x1e1e2e_u32)
    levels.last.should be < Term::Render::ColorSpace.lightness(0xcdd6f4_u32)
  end

  it "swaps the corners on light themes unless harmonious" do
    base    = LIGHT16.map(&.to_u32)
    swapped = Term::Render::Palette.generate(base, 0x4c4f69_u32, 0xeff1f5_u32)
    close(swapped[16], 0x4c4f69_u32).should be_true
    close(swapped[231], 0xeff1f5_u32).should be_true
    swapped.light?.should be_true
    swapped.inverted?.should be_true
    swapped.ramp(0).should eq(255)
    kept = Term::Render::Palette.generate(base, 0x4c4f69_u32, 0xeff1f5_u32, harmonious: true)
    close(kept[16], 0xeff1f5_u32).should be_true
    kept.inverted?.should be_false
    kept.ramp(0).should eq(232)
  end

  it "finds the nearest entry and forgets it when a color changes" do
    palette = Term::Render::Palette.stock
    palette.nearest(0xff0000_u32).should eq(9_u8)
    palette.nearest(0x0000fe_u32).should eq(21_u8)
    palette.nearest(0x0000fe_u32, 16).should eq(4_u8)
    palette[21] = 0x00ff00_u32
    palette.nearest(0x0000fe_u32).should_not eq(21_u8)
  end

  it "interpolates whole palettes" do
    from = Term::Render::Palette.stock
    to   = Term::Render::Palette.generate(DARK16.map(&.to_u32), 0xcdd6f4_u32, 0x1e1e2e_u32)
    Term::Render::Palette.mix(from, to, 0.0_f32, Term::Render::BlendSpace::Oklab).same?(from).should be_true
    Term::Render::Palette.mix(from, to, 1.0_f32, Term::Render::BlendSpace::Oklab).same?(to).should be_true
    half = Term::Render::Palette.mix(from, to, 0.5_f32, Term::Render::BlendSpace::Oklab)
    half.same?(from).should be_false
    half.same?(to).should be_false
  end

  it "rejects tables of the wrong size" do
    expect_raises(ArgumentError) { Term::Render::Palette.generate([0_u32], 0_u32, 0_u32) }
    expect_raises(ArgumentError) { Term::Render::Palette.new(Slice(UInt32).new(3, 0_u32), 0_u32, 0_u32) }
  end
end

describe Term::Render::Paint do
  it "converts the accepted color forms" do
    Term::Render::Paint.fg(:default).kind.should eq(Term::Render::Paint::Kind::Foreground)
    Term::Render::Paint.bg(:default).kind.should eq(Term::Render::Paint::Kind::Background)
    Term::Render::Paint.fg(:background).kind.should eq(Term::Render::Paint::Kind::Background)
    Term::Render::Paint.bg(4).should eq(Term::Render::Paint.index(4))
    Term::Render::Paint.fg("#ff8800").should eq(Term::Render::Paint.rgb(0xff8800_u32))
    Term::Render::Paint.fg(Term::Color.rgb(1_u8, 2_u8, 3_u8, 0.5)).should eq(Term::Render::Paint.rgb(0x010203_u32, 128_u8))
    Term::Render::Paint.bg({:surface, 0.5}).should eq(Term::Render::Paint.new(Term::Render::Paint::Kind::Role, 0_u32, 128_u8))
    Term::Render::Paint.fg(:none).clear?.should be_true
    Term::Render::Paint.fg(:accent).should eq(Term::Render::Paint.role(Term::Render::Roles::Core::Accent.value))
    Term::Render::Paint.fg("sidebar").value.should eq(Term::Render::Roles.slot("sidebar").to_u32)
    expect_raises(ArgumentError) { Term::Render::Paint.fg(300) }
    expect_raises(ArgumentError) { Term::Render::Paint.fg("#zz") }
  end

  it "interns multi-codepoint clusters and keeps single codepoints inline" do
    Term::Render::Graphemes.intern("a").should eq(97_u32)
    family = Term::Render::Graphemes.intern("👨‍👩‍👧")
    Term::Render::Graphemes.pooled?(family).should be_true
    Term::Render::Graphemes.intern("👨‍👩‍👧").should eq(family)
    Term::Render::Graphemes.text(family).should eq("👨‍👩‍👧")
  end
end
