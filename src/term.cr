# src/term.cr
require "base64"
require "uuid"
require "compress/zlib"
require "openssl/hmac"
require "uri"

class Term
  ST          = "\e\\"
  PASTE_NAME  = "UGFzdGUgZXZlbnQ="
  MACHINE_KEY = "tty-dnd-protocol-machine-id"
  ATTRIBUTES  = "\e[c"
  PLACEHOLDER = '\u{10EEEE}'
  SEPARATOR   = ' '
  DND         =   72
  CHUNK       = 4095
  WIRE_CHUNK  = 4096
  RAW_CHUNK   = 3072
  TEXT_CHUNK  = 2048
  MISSING     = Int32::MIN
  CSI_LIMIT   = 256
  TEXT_LIMIT  = 1 << 28
  POLL        = 100.milliseconds
  IDLE        = 1.hour
  SCREEN      = {"\e[?1049h", "\e[?1049l"}
  KEYBOARD    = {"\e[>31u", "\e[<u"}
  CELL_SIZE   = "\e[16t"
  PASTE_END   = "\e[201~".to_slice
  IDENT       = /\A[a-zA-Z0-9_\-+.]+\z/
  COLOR_NAMES = <<-NAMES
    aliceblue=f0f8ff antiquewhite=faebd7 antiquewhite1=ffefdb antiquewhite2=eedfcc antiquewhite3=cdc0b0
    antiquewhite4=8b8378 aquamarine=7fffd4 aquamarine1=7fffd4 aquamarine2=76eec6 aquamarine3=66cdaa
    aquamarine4=458b74 azure=f0ffff azure1=f0ffff azure2=e0eeee azure3=c1cdcd azure4=838b8b beige=f5f5dc
    bisque=ffe4c4 bisque1=ffe4c4 bisque2=eed5b7 bisque3=cdb79e bisque4=8b7d6b black=000000 blanchedalmond=ffebcd
    blue=0000ff blue1=0000ff blue2=0000ee blue3=0000cd blue4=00008b blueviolet=8a2be2 brown=a52a2a brown1=ff4040
    brown2=ee3b3b brown3=cd3333 brown4=8b2323 burlywood=deb887 burlywood1=ffd39b burlywood2=eec591
    burlywood3=cdaa7d burlywood4=8b7355 cadetblue=5f9ea0 cadetblue1=98f5ff cadetblue2=8ee5ee cadetblue3=7ac5cd
    cadetblue4=53868b chartreuse=7fff00 chartreuse1=7fff00 chartreuse2=76ee00 chartreuse3=66cd00
    chartreuse4=458b00 chocolate=d2691e chocolate1=ff7f24 chocolate2=ee7621 chocolate3=cd661d chocolate4=8b4513
    coral=ff7f50 coral1=ff7256 coral2=ee6a50 coral3=cd5b45 coral4=8b3e2f cornflowerblue=6495ed cornsilk=fff8dc
    cornsilk1=fff8dc cornsilk2=eee8cd cornsilk3=cdc8b1 cornsilk4=8b8878 cyan=00ffff cyan1=00ffff cyan2=00eeee
    cyan3=00cdcd cyan4=008b8b darkblue=00008b darkcyan=008b8b darkgoldenrod=b8860b darkgoldenrod1=ffb90f
    darkgoldenrod2=eead0e darkgoldenrod3=cd950c darkgoldenrod4=8b6508 darkgray=a9a9a9 darkgreen=006400
    darkgrey=a9a9a9 darkkhaki=bdb76b darkmagenta=8b008b darkolivegreen=556b2f darkolivegreen1=caff70
    darkolivegreen2=bcee68 darkolivegreen3=a2cd5a darkolivegreen4=6e8b3d darkorange=ff8c00 darkorange1=ff7f00
    darkorange2=ee7600 darkorange3=cd6600 darkorange4=8b4500 darkorchid=9932cc darkorchid1=bf3eff
    darkorchid2=b23aee darkorchid3=9a32cd darkorchid4=68228b darkred=8b0000 darksalmon=e9967a darkseagreen=8fbc8f
    darkseagreen1=c1ffc1 darkseagreen2=b4eeb4 darkseagreen3=9bcd9b darkseagreen4=698b69 darkslateblue=483d8b
    darkslategray=2f4f4f darkslategray1=97ffff darkslategray2=8deeee darkslategray3=79cdcd darkslategray4=528b8b
    darkslategrey=2f4f4f darkturquoise=00ced1 darkviolet=9400d3 debianred=d70751 deeppink=ff1493 deeppink1=ff1493
    deeppink2=ee1289 deeppink3=cd1076 deeppink4=8b0a50 deepskyblue=00bfff deepskyblue1=00bfff deepskyblue2=00b2ee
    deepskyblue3=009acd deepskyblue4=00688b dimgray=696969 dimgrey=696969 dodgerblue=1e90ff dodgerblue1=1e90ff
    dodgerblue2=1c86ee dodgerblue3=1874cd dodgerblue4=104e8b firebrick=b22222 firebrick1=ff3030 firebrick2=ee2c2c
    firebrick3=cd2626 firebrick4=8b1a1a floralwhite=fffaf0 forestgreen=228b22 gainsboro=dcdcdc ghostwhite=f8f8ff
    gold=ffd700 gold1=ffd700 gold2=eec900 gold3=cdad00 gold4=8b7500 goldenrod=daa520 goldenrod1=ffc125
    goldenrod2=eeb422 goldenrod3=cd9b1d goldenrod4=8b6914 gray=bebebe gray0=000000 gray1=030303 gray10=1a1a1a
    gray100=ffffff gray11=1c1c1c gray12=1f1f1f gray13=212121 gray14=242424 gray15=262626 gray16=292929
    gray17=2b2b2b gray18=2e2e2e gray19=303030 gray2=050505 gray20=333333 gray21=363636 gray22=383838 gray23=3b3b3b
    gray24=3d3d3d gray25=404040 gray26=424242 gray27=454545 gray28=474747 gray29=4a4a4a gray3=080808 gray30=4d4d4d
    gray31=4f4f4f gray32=525252 gray33=545454 gray34=575757 gray35=595959 gray36=5c5c5c gray37=5e5e5e
    gray38=616161 gray39=636363 gray4=0a0a0a gray40=666666 gray41=696969 gray42=6b6b6b gray43=6e6e6e gray44=707070
    gray45=737373 gray46=757575 gray47=787878 gray48=7a7a7a gray49=7d7d7d gray5=0d0d0d gray50=7f7f7f gray51=828282
    gray52=858585 gray53=878787 gray54=8a8a8a gray55=8c8c8c gray56=8f8f8f gray57=919191 gray58=949494
    gray59=969696 gray6=0f0f0f gray60=999999 gray61=9c9c9c gray62=9e9e9e gray63=a1a1a1 gray64=a3a3a3 gray65=a6a6a6
    gray66=a8a8a8 gray67=ababab gray68=adadad gray69=b0b0b0 gray7=121212 gray70=b3b3b3 gray71=b5b5b5 gray72=b8b8b8
    gray73=bababa gray74=bdbdbd gray75=bfbfbf gray76=c2c2c2 gray77=c4c4c4 gray78=c7c7c7 gray79=c9c9c9 gray8=141414
    gray80=cccccc gray81=cfcfcf gray82=d1d1d1 gray83=d4d4d4 gray84=d6d6d6 gray85=d9d9d9 gray86=dbdbdb
    gray87=dedede gray88=e0e0e0 gray89=e3e3e3 gray9=171717 gray90=e5e5e5 gray91=e8e8e8 gray92=ebebeb gray93=ededed
    gray94=f0f0f0 gray95=f2f2f2 gray96=f5f5f5 gray97=f7f7f7 gray98=fafafa gray99=fcfcfc green=00ff00 green1=00ff00
    green2=00ee00 green3=00cd00 green4=008b00 greenyellow=adff2f grey=bebebe grey0=000000 grey1=030303
    grey10=1a1a1a grey100=ffffff grey11=1c1c1c grey12=1f1f1f grey13=212121 grey14=242424 grey15=262626
    grey16=292929 grey17=2b2b2b grey18=2e2e2e grey19=303030 grey2=050505 grey20=333333 grey21=363636 grey22=383838
    grey23=3b3b3b grey24=3d3d3d grey25=404040 grey26=424242 grey27=454545 grey28=474747 grey29=4a4a4a grey3=080808
    grey30=4d4d4d grey31=4f4f4f grey32=525252 grey33=545454 grey34=575757 grey35=595959 grey36=5c5c5c
    grey37=5e5e5e grey38=616161 grey39=636363 grey4=0a0a0a grey40=666666 grey41=696969 grey42=6b6b6b grey43=6e6e6e
    grey44=707070 grey45=737373 grey46=757575 grey47=787878 grey48=7a7a7a grey49=7d7d7d grey5=0d0d0d grey50=7f7f7f
    grey51=828282 grey52=858585 grey53=878787 grey54=8a8a8a grey55=8c8c8c grey56=8f8f8f grey57=919191
    grey58=949494 grey59=969696 grey6=0f0f0f grey60=999999 grey61=9c9c9c grey62=9e9e9e grey63=a1a1a1 grey64=a3a3a3
    grey65=a6a6a6 grey66=a8a8a8 grey67=ababab grey68=adadad grey69=b0b0b0 grey7=121212 grey70=b3b3b3 grey71=b5b5b5
    grey72=b8b8b8 grey73=bababa grey74=bdbdbd grey75=bfbfbf grey76=c2c2c2 grey77=c4c4c4 grey78=c7c7c7
    grey79=c9c9c9 grey8=141414 grey80=cccccc grey81=cfcfcf grey82=d1d1d1 grey83=d4d4d4 grey84=d6d6d6 grey85=d9d9d9
    grey86=dbdbdb grey87=dedede grey88=e0e0e0 grey89=e3e3e3 grey9=171717 grey90=e5e5e5 grey91=e8e8e8 grey92=ebebeb
    grey93=ededed grey94=f0f0f0 grey95=f2f2f2 grey96=f5f5f5 grey97=f7f7f7 grey98=fafafa grey99=fcfcfc
    honeydew=f0fff0 honeydew1=f0fff0 honeydew2=e0eee0 honeydew3=c1cdc1 honeydew4=838b83 hotpink=ff69b4
    hotpink1=ff6eb4 hotpink2=ee6aa7 hotpink3=cd6090 hotpink4=8b3a62 indianred=cd5c5c indianred1=ff6a6a
    indianred2=ee6363 indianred3=cd5555 indianred4=8b3a3a ivory=fffff0 ivory1=fffff0 ivory2=eeeee0 ivory3=cdcdc1
    ivory4=8b8b83 khaki=f0e68c khaki1=fff68f khaki2=eee685 khaki3=cdc673 khaki4=8b864e lavender=e6e6fa
    lavenderblush=fff0f5 lavenderblush1=fff0f5 lavenderblush2=eee0e5 lavenderblush3=cdc1c5 lavenderblush4=8b8386
    lawngreen=7cfc00 lemonchiffon=fffacd lemonchiffon1=fffacd lemonchiffon2=eee9bf lemonchiffon3=cdc9a5
    lemonchiffon4=8b8970 lightblue=add8e6 lightblue1=bfefff lightblue2=b2dfee lightblue3=9ac0cd lightblue4=68838b
    lightcoral=f08080 lightcyan=e0ffff lightcyan1=e0ffff lightcyan2=d1eeee lightcyan3=b4cdcd lightcyan4=7a8b8b
    lightgoldenrod=eedd82 lightgoldenrod1=ffec8b lightgoldenrod2=eedc82 lightgoldenrod3=cdbe70
    lightgoldenrod4=8b814c lightgoldenrodyellow=fafad2 lightgray=d3d3d3 lightgreen=90ee90 lightgrey=d3d3d3
    lightpink=ffb6c1 lightpink1=ffaeb9 lightpink2=eea2ad lightpink3=cd8c95 lightpink4=8b5f65 lightsalmon=ffa07a
    lightsalmon1=ffa07a lightsalmon2=ee9572 lightsalmon3=cd8162 lightsalmon4=8b5742 lightseagreen=20b2aa
    lightskyblue=87cefa lightskyblue1=b0e2ff lightskyblue2=a4d3ee lightskyblue3=8db6cd lightskyblue4=607b8b
    lightslateblue=8470ff lightslategray=778899 lightslategrey=778899 lightsteelblue=b0c4de lightsteelblue1=cae1ff
    lightsteelblue2=bcd2ee lightsteelblue3=a2b5cd lightsteelblue4=6e7b8b lightyellow=ffffe0 lightyellow1=ffffe0
    lightyellow2=eeeed1 lightyellow3=cdcdb4 lightyellow4=8b8b7a limegreen=32cd32 linen=faf0e6 magenta=ff00ff
    magenta1=ff00ff magenta2=ee00ee magenta3=cd00cd magenta4=8b008b maroon=b03060 maroon1=ff34b3 maroon2=ee30a7
    maroon3=cd2990 maroon4=8b1c62 mediumaquamarine=66cdaa mediumblue=0000cd mediumorchid=ba55d3
    mediumorchid1=e066ff mediumorchid2=d15fee mediumorchid3=b452cd mediumorchid4=7a378b mediumpurple=9370db
    mediumpurple1=ab82ff mediumpurple2=9f79ee mediumpurple3=8968cd mediumpurple4=5d478b mediumseagreen=3cb371
    mediumslateblue=7b68ee mediumspringgreen=00fa9a mediumturquoise=48d1cc mediumvioletred=c71585
    midnightblue=191970 mintcream=f5fffa mistyrose=ffe4e1 mistyrose1=ffe4e1 mistyrose2=eed5d2 mistyrose3=cdb7b5
    mistyrose4=8b7d7b moccasin=ffe4b5 navajowhite=ffdead navajowhite1=ffdead navajowhite2=eecfa1
    navajowhite3=cdb38b navajowhite4=8b795e navy=000080 navyblue=000080 oldlace=fdf5e6 olivedrab=6b8e23
    olivedrab1=c0ff3e olivedrab2=b3ee3a olivedrab3=9acd32 olivedrab4=698b22 orange=ffa500 orange1=ffa500
    orange2=ee9a00 orange3=cd8500 orange4=8b5a00 orangered=ff4500 orangered1=ff4500 orangered2=ee4000
    orangered3=cd3700 orangered4=8b2500 orchid=da70d6 orchid1=ff83fa orchid2=ee7ae9 orchid3=cd69c9 orchid4=8b4789
    palegoldenrod=eee8aa palegreen=98fb98 palegreen1=9aff9a palegreen2=90ee90 palegreen3=7ccd7c palegreen4=548b54
    paleturquoise=afeeee paleturquoise1=bbffff paleturquoise2=aeeeee paleturquoise3=96cdcd paleturquoise4=668b8b
    palevioletred=db7093 palevioletred1=ff82ab palevioletred2=ee799f palevioletred3=cd6889 palevioletred4=8b475d
    papayawhip=ffefd5 peachpuff=ffdab9 peachpuff1=ffdab9 peachpuff2=eecbad peachpuff3=cdaf95 peachpuff4=8b7765
    peru=cd853f pink=ffc0cb pink1=ffb5c5 pink2=eea9b8 pink3=cd919e pink4=8b636c plum=dda0dd plum1=ffbbff
    plum2=eeaeee plum3=cd96cd plum4=8b668b powderblue=b0e0e6 purple=a020f0 purple1=9b30ff purple2=912cee
    purple3=7d26cd purple4=551a8b red=ff0000 red1=ff0000 red2=ee0000 red3=cd0000 red4=8b0000 rosybrown=bc8f8f
    rosybrown1=ffc1c1 rosybrown2=eeb4b4 rosybrown3=cd9b9b rosybrown4=8b6969 royalblue=4169e1 royalblue1=4876ff
    royalblue2=436eee royalblue3=3a5fcd royalblue4=27408b saddlebrown=8b4513 salmon=fa8072 salmon1=ff8c69
    salmon2=ee8262 salmon3=cd7054 salmon4=8b4c39 sandybrown=f4a460 seagreen=2e8b57 seagreen1=54ff9f
    seagreen2=4eee94 seagreen3=43cd80 seagreen4=2e8b57 seashell=fff5ee seashell1=fff5ee seashell2=eee5de
    seashell3=cdc5bf seashell4=8b8682 sienna=a0522d sienna1=ff8247 sienna2=ee7942 sienna3=cd6839 sienna4=8b4726
    skyblue=87ceeb skyblue1=87ceff skyblue2=7ec0ee skyblue3=6ca6cd skyblue4=4a708b slateblue=6a5acd
    slateblue1=836fff slateblue2=7a67ee slateblue3=6959cd slateblue4=473c8b slategray=708090 slategray1=c6e2ff
    slategray2=b9d3ee slategray3=9fb6cd slategray4=6c7b8b slategrey=708090 snow=fffafa snow1=fffafa snow2=eee9e9
    snow3=cdc9c9 snow4=8b8989 springgreen=00ff7f springgreen1=00ff7f springgreen2=00ee76 springgreen3=00cd66
    springgreen4=008b45 steelblue=4682b4 steelblue1=63b8ff steelblue2=5cacee steelblue3=4f94cd steelblue4=36648b
    tan=d2b48c tan1=ffa54f tan2=ee9a49 tan3=cd853f tan4=8b5a2b thistle=d8bfd8 thistle1=ffe1ff thistle2=eed2ee
    thistle3=cdb5cd thistle4=8b7b8b tomato=ff6347 tomato1=ff6347 tomato2=ee5c42 tomato3=cd4f39 tomato4=8b3626
    turquoise=40e0d0 turquoise1=00f5ff turquoise2=00e5ee turquoise3=00c5cd turquoise4=00868b violet=ee82ee
    violetred=d02090 violetred1=ff3e96 violetred2=ee3a8c violetred3=cd3278 violetred4=8b2252 wheat=f5deb3
    wheat1=ffe7ba wheat2=eed8ae wheat3=cdba96 wheat4=8b7e66 white=ffffff whitesmoke=f5f5f5 yellow=ffff00
    yellow1=ffff00 yellow2=eeee00 yellow3=cdcd00 yellow4=8b8b00 yellowgreen=9acd32
    NAMES
  NAMES = COLOR_NAMES.split.to_h do |pair|
    name, _, hex = pair.partition('=')
    {name, hex.to_i(16)}
  end

  {% unless flag?(:win32) %}
    TIOCGWINSZ = {% if flag?(:linux) %} 0x5413 {% else %} 0x40087468 {% end %}

    lib LibTerm
      struct Winsize
        rows : UInt16
        cols : UInt16
        width : UInt16
        height : UInt16
      end

      fun ioctl(fd : LibC::Int, request : LibC::ULong, ...) : LibC::Int
      fun shm_open(name : LibC::Char*, flags : LibC::Int, mode : LibC::ModeT) : LibC::Int
    end
  {% end %}
  STARTED    = Time.instant
  DIACRITICS = [
    0x0305, 0x030d, 0x030e, 0x0310, 0x0312, 0x033d, 0x033e, 0x033f, 0x0346, 0x034a, 0x034b, 0x034c,
    0x0350, 0x0351, 0x0352, 0x0357, 0x035b, 0x0363, 0x0364, 0x0365, 0x0366, 0x0367, 0x0368, 0x0369,
    0x036a, 0x036b, 0x036c, 0x036d, 0x036e, 0x036f, 0x0483, 0x0484, 0x0485, 0x0486, 0x0487, 0x0592,
    0x0593, 0x0594, 0x0595, 0x0597, 0x0598, 0x0599, 0x059c, 0x059d, 0x059e, 0x059f, 0x05a0, 0x05a1,
    0x05a8, 0x05a9, 0x05ab, 0x05ac, 0x05af, 0x05c4, 0x0610, 0x0611, 0x0612, 0x0613, 0x0614, 0x0615,
    0x0616, 0x0617, 0x0657, 0x0658, 0x0659, 0x065a, 0x065b, 0x065d, 0x065e, 0x06d6, 0x06d7, 0x06d8,
    0x06d9, 0x06da, 0x06db, 0x06dc, 0x06df, 0x06e0, 0x06e1, 0x06e2, 0x06e4, 0x06e7, 0x06e8, 0x06eb,
    0x06ec, 0x0730, 0x0732, 0x0733, 0x0735, 0x0736, 0x073a, 0x073d, 0x073f, 0x0740, 0x0741, 0x0743,
    0x0745, 0x0747, 0x0749, 0x074a, 0x07eb, 0x07ec, 0x07ed, 0x07ee, 0x07ef, 0x07f0, 0x07f1, 0x07f3,
    0x0816, 0x0817, 0x0818, 0x0819, 0x081b, 0x081c, 0x081d, 0x081e, 0x081f, 0x0820, 0x0821, 0x0822,
    0x0823, 0x0825, 0x0826, 0x0827, 0x0829, 0x082a, 0x082b, 0x082c, 0x082d, 0x0951, 0x0953, 0x0954,
    0x0f82, 0x0f83, 0x0f86, 0x0f87, 0x135d, 0x135e, 0x135f, 0x17dd, 0x193a, 0x1a17, 0x1a75, 0x1a76,
    0x1a77, 0x1a78, 0x1a79, 0x1a7a, 0x1a7b, 0x1a7c, 0x1b6b, 0x1b6d, 0x1b6e, 0x1b6f, 0x1b70, 0x1b71,
    0x1b72, 0x1b73, 0x1cd0, 0x1cd1, 0x1cd2, 0x1cda, 0x1cdb, 0x1ce0, 0x1dc0, 0x1dc1, 0x1dc3, 0x1dc4,
    0x1dc5, 0x1dc6, 0x1dc7, 0x1dc8, 0x1dc9, 0x1dcb, 0x1dcc, 0x1dd1, 0x1dd2, 0x1dd3, 0x1dd4, 0x1dd5,
    0x1dd6, 0x1dd7, 0x1dd8, 0x1dd9, 0x1dda, 0x1ddb, 0x1ddc, 0x1ddd, 0x1dde, 0x1ddf, 0x1de0, 0x1de1,
    0x1de2, 0x1de3, 0x1de4, 0x1de5, 0x1de6, 0x1dfe, 0x20d0, 0x20d1, 0x20d4, 0x20d5, 0x20d6, 0x20d7,
    0x20db, 0x20dc, 0x20e1, 0x20e7, 0x20e9, 0x20f0, 0x2cef, 0x2cf0, 0x2cf1, 0x2de0, 0x2de1, 0x2de2,
    0x2de3, 0x2de4, 0x2de5, 0x2de6, 0x2de7, 0x2de8, 0x2de9, 0x2dea, 0x2deb, 0x2dec, 0x2ded, 0x2dee,
    0x2def, 0x2df0, 0x2df1, 0x2df2, 0x2df3, 0x2df4, 0x2df5, 0x2df6, 0x2df7, 0x2df8, 0x2df9, 0x2dfa,
    0x2dfb, 0x2dfc, 0x2dfd, 0x2dfe, 0x2dff, 0xa66f, 0xa67c, 0xa67d, 0xa6f0, 0xa6f1, 0xa8e0, 0xa8e1,
    0xa8e2, 0xa8e3, 0xa8e4, 0xa8e5, 0xa8e6, 0xa8e7, 0xa8e8, 0xa8e9, 0xa8ea, 0xa8eb, 0xa8ec, 0xa8ed,
    0xa8ee, 0xa8ef, 0xa8f0, 0xa8f1, 0xaab0, 0xaab2, 0xaab3, 0xaab7, 0xaab8, 0xaabe, 0xaabf, 0xaac1,
    0xfe20, 0xfe21, 0xfe22, 0xfe23, 0xfe24, 0xfe25, 0xfe26, 0x10a0f, 0x10a38, 0x1d185, 0x1d186, 0x1d187,
    0x1d188, 0x1d189, 0x1d1aa, 0x1d1ab, 0x1d1ac, 0x1d1ad, 0x1d242, 0x1d243, 0x1d244,
  ]

  @[Flags]
  enum Mods : UInt8
    Shift
    Alt
    Ctrl
    Super
    Hyper
    Meta
    CapsLock
    NumLock
  end

  enum Named
    Tab       =     9
    Enter     =    13
    Escape    =    27
    Backspace =   127
    Insert    = 57348
    Delete
    Left
    Right
    Up
    Down
    PageUp
    PageDown
    Home
    End
    CapsLock
    ScrollLock
    NumLock
    PrintScreen
    Pause
    Menu
    {% for index in 1..35 %}
      F{{ index }}
    {% end %}
    {% for index in 0..9 %}
      Kp{{ index }}
    {% end %}
    KpDecimal
    KpDivide
    KpMultiply
    KpSubtract
    KpAdd
    KpEnter
    KpEqual
    KpSeparator
    KpLeft
    KpRight
    KpUp
    KpDown
    KpPageUp
    KpPageDown
    KpHome
    KpEnd
    KpInsert
    KpDelete
    KpBegin
    MediaPlay
    MediaPause
    MediaPlayPause
    MediaReverse
    MediaStop
    MediaFastForward
    MediaRewind
    MediaTrackNext
    MediaTrackPrevious
    MediaRecord
    LowerVolume
    RaiseVolume
    MuteVolume
    LeftShift
    LeftControl
    LeftAlt
    LeftSuper
    LeftHyper
    LeftMeta
    RightShift
    RightControl
    RightAlt
    RightSuper
    RightHyper
    RightMeta
    IsoLevel3Shift
    IsoLevel5Shift
  end

  COMMAND   = Mods::Ctrl | Mods::Super | Mods::Hyper | Mods::Meta
  LOCKS     = Mods::CapsLock | Mods::NumLock
  MODIFIERS = Named::LeftShift.value..Named::IsoLevel5Shift.value

  LETTERS = {
    'A' => Named::Up,
    'B' => Named::Down,
    'C' => Named::Right,
    'D' => Named::Left,
    'E' => Named::KpBegin,
    'F' => Named::End,
    'H' => Named::Home,
    'P' => Named::F1,
    'Q' => Named::F2,
    'S' => Named::F4,
  }

  SS3 = LETTERS.merge({'R' => Named::F3})

  TILDES = {
     2 => Named::Insert,
     3 => Named::Delete,
     5 => Named::PageUp,
     6 => Named::PageDown,
     7 => Named::Home,
     8 => Named::End,
    11 => Named::F1,
    12 => Named::F2,
    13 => Named::F3,
    14 => Named::F4,
    15 => Named::F5,
    17 => Named::F6,
    18 => Named::F7,
    19 => Named::F8,
    20 => Named::F9,
    21 => Named::F10,
    23 => Named::F11,
    24 => Named::F12,
  }

  enum Shape
    Alias
    Cell
    Copy
    Crosshair
    Default
    EResize
    EwResize
    Grab
    Grabbing
    Help
    Move
    NResize
    NeResize
    NeswResize
    NoDrop
    NotAllowed
    NsResize
    NwResize
    NwseResize
    Pointer
    Progress
    SResize
    SeResize
    SwResize
    Text
    VerticalText
    WResize
    Wait
    ZoomIn
    ZoomOut

    def wire : String
      to_s.underscore.tr("_", "-")
    end
  end

  enum ShapeQuery
    Current
    Default
    Grabbed

    def wire : String
      "__#{to_s.downcase}__"
    end
  end

  enum Status
    Done
    EIO
    EINVAL
    ENOSYS
    EPERM
    EBUSY
    EFBIG
  end

  enum Query
    Shape
    Color
    ClipboardRead
    ClipboardWrite
    Mode
    Attributes
    Window
    Cell
    Graphics
    NotifySupport
    NotifyAlive
    DndSupport
    DropData
    DragStart
  end

  enum State
    Ground
    Escape
    Ss3
    Csi
    Text
    TextEscape
    Paste
  end

  @[Flags]
  enum Feature
    Keyboard
    Resize
    Motion
    Pixels
    Focus
    Visibility
    ColorScheme
    Paste
  end

  record Mode, feature : Feature, number : Int32, fallback : Int32 = 0 do
    def key : String
      number == 0 ? "u" : number.to_s
    end

    def probe : String
      number == 0 ? "\e[?u" : "\e[?#{number}$p"
    end

    def switch(supported : Bool, enable : Bool) : String
      return supported ? KEYBOARD[enable ? 0 : 1] : "" if number == 0
      code = supported ? number : fallback
      code == 0 ? "" : "\e[?#{code}#{enable ? 'h' : 'l'}"
    end
  end

  FEATURES = [
    Mode.new(Feature::Keyboard, 0),
    Mode.new(Feature::Resize, 2048),
    Mode.new(Feature::Motion, 1003),
    Mode.new(Feature::Pixels, 1016, 1006),
    Mode.new(Feature::Focus, 1004),
    Mode.new(Feature::Visibility, 2033),
    Mode.new(Feature::ColorScheme, 2031),
    Mode.new(Feature::Paste, 5522, 2004),
  ]

  SIGNALS = {% if flag?(:win32) %}
              [Signal::INT]
            {% else %}
              [Signal::INT, Signal::TERM, Signal::HUP, Signal::QUIT]
            {% end %}

  enum Family
    Clipboard
    Graphics
    Notify
    Dnd
  end

  enum Direction
    Left
    Right
    Up
    Down
  end

  enum Format
    Text =   0
    RGB  =  24
    RGBA =  32
    PNG  = 100
  end

  enum Medium
    Direct
    File
    TempFile
    SharedMemory
  end

  enum Quiet
    None
    Ok
    All
  end

  enum Delete
    Visible
    Id
    Number
    Cursor
    Frames
    Cell
    CellZ
    Range
    Column
    Row
    Z
  end

  enum Playback
    Stop    = 1
    Loading
    Loop
  end

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

  @[Flags]
  enum Operation
    Copy
    Move
  end

  MEDIA = {
    Medium::Direct       => 'd',
    Medium::File         => 'f',
    Medium::TempFile     => 't',
    Medium::SharedMemory => 's',
  }

  DELETES = {
    Delete::Visible => 'a',
    Delete::Id      => 'i',
    Delete::Number  => 'n',
    Delete::Cursor  => 'c',
    Delete::Frames  => 'f',
    Delete::Cell    => 'p',
    Delete::CellZ   => 'q',
    Delete::Range   => 'r',
    Delete::Column  => 'x',
    Delete::Row     => 'y',
    Delete::Z       => 'z',
  }

  record Key, code : Int32, action : Action, mods : Mods, shifted : Int32?, base : Int32?, text : String? do
    enum Action
      Press   = 1
      Repeat
      Release
    end

    delegate shift?, alt?, ctrl?, to: @mods
    delegate press?, repeat?, release?, to: @action

    def named : Named?
      Named.from_value?(code)
    end

    def char : Char?
      code.unsafe_chr if code > 0 && named.nil?
    end

    def modifier? : Bool
      MODIFIERS.includes?(code)
    end

    def command? : Bool
      text.nil? || !(mods & COMMAND).none?
    end
  end

  record Mouse, action : Action, button : Button, mods : Mods, x : Int32, y : Int32, col : Int32, row : Int32 do
    enum Action
      Press
      Release
      Drag
      Hover
      Scroll
      Leave
    end

    enum Button
      Left
      Middle
      Right
      None
      WheelUp
      WheelDown
      WheelLeft
      WheelRight
      Aux8
      Aux9
      Aux10
      Aux11
    end

    delegate shift?, alt?, ctrl?, to: @mods
  end

  record Resize, rows : Int32, cols : Int32, height : Int32, width : Int32
  record Focus, gained : Bool
  record Visibility, visible : Bool
  record ColorScheme, dark : Bool
  record Paste, mimes : Array(String), primary : Bool, password : String?, text : String? = nil
  record TextInput, text : String
  record KeyCommand, key : Key
  record Lock, lock : Mods, active : Bool
  record TypingMetric, code : Int32, dwell : Time::Span, latency : Time::Span, overlap : Int32
  record Size, width : Int32, height : Int32

  record Notification, kind : Kind, id : String, button : Int32 = 0, untracked : Bool = false do
    enum Kind
      Activated
      Button
      Closed
    end
  end

  record Drop, kind : Kind, col : Int32, row : Int32, x : Int32, y : Int32, operations : Operation, mimes : Array(String)? do
    enum Kind
      Move
      Leave
      Land
    end
  end

  record Drag, kind : Kind, col : Int32 = 0, row : Int32 = 0, x : Int32 = 0, y : Int32 = 0, index : Int32 = 0, operation : Operation = Operation::None, canceled : Bool = false, error : String? = nil do
    enum Kind
      Gesture
      Started
      Accepted
      Action
      Dropped
      Finished
      DataRequest
      FileRequest
      Error
    end
  end

  record KeyGesture, kind : Kind, key : Key, count : Int32 = 1 do
    enum Kind
      Activate
      AutoRepeat
      Tap
      MultiTap
      HoldStart
      HoldEnd
      HoldReached
      ModifierTap
    end
  end

  record Binding, kind : Kind, name : String do
    enum Kind
      Chord
      Sequence
      Shortcut
    end
  end

  record MouseGesture, kind : Kind, mouse : Mouse, count : Int32 = 1, dx : Int32 = 0, dy : Int32 = 0, velocity : Float64 = 0.0 do
    enum Kind
      Click
      DragStart
      DragMove
      DragEnd
      Enter
      HoverDwell
      HoverEnd
      Motion
      Scroll
      Swipe
      Chord
      LongPress
    end

    def direction : Direction
      if dx.abs >= dy.abs
        dx < 0 ? Direction::Left : Direction::Right
      else
        dy < 0 ? Direction::Up : Direction::Down
      end
    end
  end

  record Color, red : UInt16, green : UInt16, blue : UInt16, alpha : Float64 = 1.0 do
    def self.rgb(red : UInt8, green : UInt8, blue : UInt8, alpha : Float64 = 1.0) : Color
      new(red.to_u16 * 257, green.to_u16 * 257, blue.to_u16 * 257, alpha)
    end

    def self.parse(text : String) : Color?
      body, _, alpha = text.partition('@')
      opacity = alpha.empty? ? 1.0 : alpha.to_f?
      return unless opacity
      parts =
        if body.starts_with?("rgbi:")
          body.lchop("rgbi:").split('/').map do |part|
            part.to_f?.try { |value| (value.clamp(0.0, 1.0) * 0xffff).round.to_u16 }
          end
        elsif body.starts_with?("rgb:")
          body.lchop("rgb:").split('/').map { |part| scaled(part) }
        elsif body.starts_with?('#') && body.size.in?(4, 7, 10, 13)
          width = body.size // 3
          (0...3).map do |index|
            body[1 + index * width, width].to_u16?(16).try { |value| value << (16 - 4 * width) }
          end
        elsif named = NAMES[body.downcase.delete(' ')]?
          [16, 8, 0].map { |shift| (((named >> shift) & 255) * 257).to_u16.as(UInt16?) }
        end
      return unless parts && parts.size == 3
      red, green, blue = parts
      return unless red && green && blue
      new(red, green, blue, opacity)
    end

    def self.scaled(digits : String) : UInt16?
      return unless digits.size.in?(1..4)
      digits.to_u32?(16).try do |value|
        (value * 0xffff // ((1_u32 << (4 * digits.size)) - 1)).to_u16
      end
    end

    def to_s(io : IO) : Nil
      io << "rgb:"
      {red, green, blue}.each_with_index do |channel, index|
        io << '/' unless index == 0
        io << channel.to_s(16).rjust(4, '0')
      end
      io << '@' << alpha unless alpha == 1.0
    end
  end

  record Palette, colors : Hash(String, Color?), unknown : Array(String) do
    delegate :[], :[]?, :keys, :size, :has_key?, :each, to: @colors
  end

  record Clipboard, status : Status, data : Hash(String, Bytes) do
    delegate done?, to: @status

    def text : String?
      data["text/plain"]?.try { |bytes| String.new(bytes) }
    end
  end

  record Pixels, data : Bytes | IO, format : Format = Format::RGBA, width : Int32 = 0, height : Int32 = 0, medium : Medium = Medium::Direct, compress : Bool = false, size : Int32 = 0, offset : Int32 = 0 do
    def self.png(data : Bytes | IO, compress : Bool = false) : Pixels
      new(data, Format::PNG, compress: compress)
    end

    def self.rgba(data : Bytes | IO, width : Int32, height : Int32, compress : Bool = false) : Pixels
      new(data, Format::RGBA, width, height, compress: compress)
    end

    def self.rgb(data : Bytes | IO, width : Int32, height : Int32, compress : Bool = false) : Pixels
      new(data, Format::RGB, width, height, compress: compress)
    end

    def self.at(path : String, medium : Medium = Medium::File, format : Format = Format::PNG, width : Int32 = 0, height : Int32 = 0, compress : Bool = false, size : Int32 = 0, offset : Int32 = 0) : Pixels
      new(path.to_slice, format, width, height, medium, compress, size, offset)
    end

    def self.temp(data : Bytes, format : Format = Format::PNG, width : Int32 = 0, height : Int32 = 0) : Pixels
      path = File.tempname("tty-graphics-protocol-", ".bin")
      File.write(path, data, perm: 0o600)
      at(path, Medium::TempFile, format, width, height)
    end

    def self.shared(data : Bytes, format : Format = Format::PNG, width : Int32 = 0, height : Int32 = 0) : Pixels
      name = "/tty-graphics-protocol-#{UUID.random}"
      {% if flag?(:linux) %}
        File.write("/dev/shm#{name}", data, perm: 0o600)
      {% elsif flag?(:win32) %}
        raise NotImplementedError.new("shared memory transmission")
      {% else %}
        fd = LibTerm.shm_open(name, LibC::O_CREAT | LibC::O_EXCL | LibC::O_RDWR, 0o600)
        raise IO::Error.from_errno("shm_open") if fd < 0
        begin
          raise IO::Error.from_errno("ftruncate") if LibC.ftruncate(fd, data.size) != 0
          unless data.empty?
            memory = LibC.mmap(nil, data.size, LibC::PROT_READ | LibC::PROT_WRITE, LibC::MAP_SHARED, fd, 0)
            raise IO::Error.from_errno("mmap") if memory == LibC::MAP_FAILED
            data.copy_to(memory.as(UInt8*), data.size)
            LibC.munmap(memory, data.size)
          end
        ensure
          LibC.close(fd)
        end
      {% end %}
      at(name, Medium::SharedMemory, format, width, height)
    end
  end

  record Placement, id : UInt32 = 0, x : Int32 = 0, y : Int32 = 0, width : Int32 = 0, height : Int32 = 0, offset_x : Int32 = 0, offset_y : Int32 = 0, columns : Int32 = 0, rows : Int32 = 0, z : Int32 = 0, hold_cursor : Bool = false, placeholder : Bool = false, parent : UInt32 = 0, parent_placement : UInt32 = 0, shift_x : Int32 = 0, shift_y : Int32 = 0

  record Ack, image : UInt32, number : UInt32, placement : UInt32, message : String do
    def ok? : Bool
      message == "OK"
    end

    def error : String?
      message unless ok?
    end
  end

  record Notice, title : String = "", body : String = "", id : String? = nil, app : String? = nil, types : Array(String) = [] of String, icons : Array(String) = [] of String, icon : Bytes? = nil, icon_key : String? = nil, buttons : Array(String) = [] of String, sound : String? = nil, urgency : Urgency? = nil, expires : Time::Span? = nil, occasion : Occasion = Occasion::Always, focus : Bool = true, report : Bool = false, closes : Bool = false

  record DropData, data : Bytes, flag : Int32 = 0, error : String? = nil, entry : Bool = false do
    def ok? : Bool
      error.nil?
    end

    def text : String
      String.new(data)
    end

    def remote? : Bool
      !entry && flag == 1
    end

    def symlink? : Bool
      entry && flag == 1
    end

    def directory? : Bool
      entry && flag != 0 && flag != 1
    end

    def handle : Int32
      flag
    end

    def entries : Array(String)
      text.split('\0', remove_empty: true)
    end

    def uris : Array(String)
      text.lines.map(&.strip).reject { |line| line.empty? || line.starts_with?('#') }
    end
  end

  record Shortcut, code : Int32, mods : Mods, physical : Bool
  record Timer, at : Time::Span, kind : Kind, code : Int32 do
    enum Kind
      Hold
      Sequence
      Dwell
      LongPress
      Scroll
    end
  end

  alias Raw = Key | Mouse | Resize | Focus | Visibility | ColorScheme | Paste | Notification | Drop | Drag | Ack
  alias Event = Raw | TextInput | KeyCommand | Lock | TypingMetric | KeyGesture | Binding | MouseGesture
  alias Reply = String | Int32 | Bool | Status | Clipboard | Size | Ack | DropData | Array(String) | Palette | Hash(String, String) | Hash(String, Array(String)) | Nil

  record Request, query : Query, key : String, sequence : String, waiter : Channel(Reply), probe : Bool, sink : IO? = nil

  alias Output = String | Request

  struct Config
    property alternate_screen = true
    property detect           = true
    property signals          = true
    property app_name : String? = nil
    property clipboard_id       = "term"
    property busy_retries       = 3
    property busy_delay         = 100.milliseconds
    property event_backlog      = 65536
    property hover_radius       = 4
    property dnd_id             = 0
    property event_buffer       = 1024
    property query_timeout      = 1.second
    property clipboard_timeout  = 30.seconds
    property transfer_timeout   = 30.seconds
    property hold_repeats       = 3
    property hold_after         = 500.milliseconds
    property multi_tap_window   = 300.milliseconds
    property sequence_timeout   = 1.second
    property click_radius       = 4
    property click_window       = 300.milliseconds
    property multi_click_window = 400.milliseconds
    property long_press_after   = 500.milliseconds
    property hover_dwell_after  = 500.milliseconds
    property scroll_window      = 50.milliseconds
    property swipe_velocity     = 500.0
    getter chords    = {} of String => Array(Int32)
    getter sequences = {} of String => Array(Int32)
    getter shortcuts = {} of String => Shortcut

    def chord(name : String, *keys : Char | Named | Int32) : self
      @chords[name] = keys.map { |key| Term.code(key) }.to_a
      self
    end

    def sequence(name : String, *keys : Char | Named | Int32) : self
      @sequences[name] = keys.map { |key| Term.code(key) }.to_a
      self
    end

    def shortcut(name : String, key : Char | Named | Int32, mods : Mods = Mods::None, physical : Bool = false) : self
      @shortcuts[name] = Shortcut.new(Term.code(key), mods, physical)
      self
    end
  end

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

  private class Node
    getter children = {} of Int32 => Node
    property action : String?
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

  private class Chain
    getter meta = {} of String => String
    getter text = IO::Memory.new
    getter data = IO::Memory.new
    @carry = ""

    def decode(payload : String, target : IO, final : Bool) : Nil
      @carry += payload
      size = final ? @carry.bytesize : @carry.bytesize & ~3
      return if size == 0
      encoded = @carry.byte_slice(0, size)
      @carry  = @carry.byte_slice(size)
      Base64.decode(encoded, target)
    end
  end

  def self.code(key : Char | Named | Int32) : Int32
    case key
    in Char  then key.ord
    in Named then key.value
    in Int32 then key
    end
  end

  def self.machine_id : String?
    raw = {% if flag?(:darwin) %}
            `ioreg -rd1 -c IOPlatformExpertDevice`[/"IOPlatformUUID" = "([^"]+)"/, 1]?
          {% elsif flag?(:win32) %}
            `reg query HKLM\\SOFTWARE\\Microsoft\\Cryptography /v MachineGuid`[/REG_SZ\s+(\S+)/, 1]?
          {% else %}
            File.read("/etc/machine-id").rstrip
          {% end %}
    raw.try { |id| "1:#{OpenSSL::HMAC.hexdigest(:sha256, MACHINE_KEY, id)}" }
  rescue IO::Error
    nil
  end

  def self.placeholder(id : UInt32, columns : Int32, rows : Int32, placement : UInt32 = 0, compact : Bool = false) : Array(String)
    high = (id >> 24).to_i
    Array.new(rows) do |row|
      String.build do |io|
        io << "\e[38;2;" << ((id >> 16) & 255) << ';' << ((id >> 8) & 255) << ';' << (id & 255) << 'm'
        io << "\e[58;2;" << ((placement >> 16) & 255) << ';' << ((placement >> 8) & 255) << ';' << (placement & 255) << 'm' if placement != 0
        columns.times do |column|
          io << PLACEHOLDER
          next if compact && column > 0
          io << DIACRITICS[row].unsafe_chr
          next if compact && high == 0
          io << DIACRITICS[column].unsafe_chr
          io << DIACRITICS[high].unsafe_chr if high > 0
        end
        io << "\e[39m"
        io << "\e[59m" if placement != 0
      end
    end
  end

  def self.uri_list(paths : Enumerable(String | Path)) : String
    paths.join do |path|
      full = Path.new(path).expand
      "file://#{URI.encode_path(full.to_s)}#{"/" if Dir.exists?(full) && !full.to_s.ends_with?('/')}\r\n"
    end
  end

  @@open   = [] of Term
  @@lock   = Mutex.new
  @@hooked = false

  def self.restore : Nil
    @@lock.synchronize { @@open.dup }.each(&.restore)
  end

  def self.suspend : Nil
    @@lock.synchronize { @@open.dup }.each(&.suspend)
  end

  def self.resume : Nil
    @@lock.synchronize { @@open.dup }.each(&.resume)
  end

  def self.refresh : Nil
    @@lock.synchronize { @@open.dup }.each(&.refresh)
  end

  def self.open(config : Config = Config.new, input : IO::FileDescriptor = STDIN, output : IO::FileDescriptor = STDOUT, & : Term ->)
    term = new(config, input, output)
    begin
      yield term
    ensure
      term.close
    end
  end

  getter events : Channel(Event)
  getter output : Channel(Output)

  @state       = State::Ground
  @string      = 0_u8
  @seq         = IO::Memory.new
  @values      = [] of Int32
  @starts      = [] of Int32
  @cell_width  = Atomic(Int32).new(0)
  @cell_height = Atomic(Int32).new(0)
  @setup       = ""
  @suspended   = Atomic(Bool).new(false)
  @mutexes : Array(Mutex)
  @icons   = Set(String).new
  @backlog = Deque(Event).new
  @locks    : Mods?
  @anchor   : Mouse?
  @transfer : Transfer?
  @waiting = {} of {Query, String} => Deque(Request)
  @chains  = {} of String => Chain
  @chain   = ""
  @mux         : String
  @credentials : String
  @teardown    : String
  @accepting = Atomic(Bool).new(false)
  @restored  = Atomic(Bool).new(false)
  @features  = Atomic(Int32).new(Feature::All.value)
  @utf       = IO::Memory.new
  @offering  = Atomic(Bool).new(false)

  @held     = {} of Int32 => Held
  @latched  = Set(String).new
  @lone     = Set(Int32).new
  @timers   = [] of Timer
  @physical = {} of {Int32, Mods} => String
  @symbolic = {} of {Int32, Mods} => String
  @root     = Node.new
  @node : Node
  @last_press = Time::Span.zero
  @tap_code   = 0
  @tap_at     = Time::Span.zero
  @tap_count  = 0

  @buttons = Set(Mouse::Button).new
  @press : Mouse?
  @press_at = Time::Span.zero
  @last : Mouse?
  @last_at = Time::Span.zero
  @click : Mouse?
  @click_at    = Time::Span.zero
  @click_count = 0
  @scroll : Mouse?
  @scroll_at    = Time::Span.zero
  @scroll_from  = Time::Span.zero
  @scroll_count = 0
  @dragging     = false
  @inside       = false
  @dwelling     = false

  def initialize(@config : Config = Config.new, @input : IO::FileDescriptor = STDIN, @io : IO::FileDescriptor = STDOUT)
    ident(@config.clipboard_id)
    @events      = Channel(Event).new(@config.event_buffer)
    @output      = Channel(Output).new(256)
    @raw         = Channel(Raw).new(256)
    @pending     = Channel(Request).new(256)
    @serving     = Channel(Array(String) | Int32).new(1024)
    @stop        = Channel(Nil).new
    @reader_done = Channel(Nil).new
    @writer_done = Channel(Nil).new
    @mutexes     = Family.values.map { Mutex.new(:reentrant) }
    @credentials = @config.app_name.try do |name|
      ":pw=#{Base64.strict_encode(UUID.random.to_s)}:name=#{Base64.strict_encode(name)}"
    end || ""
    @mux  = keys(':', {'i', @config.dnd_id})
    @node = @root
    @config.sequences.each do |name, codes|
      codes.reduce(@root) { |node, code| node.children.put_if_absent(code) { Node.new } }.action = name
    end
    @config.shortcuts.each do |name, shortcut|
      (shortcut.physical ? @physical : @symbolic)[{shortcut.code, shortcut.mods}] = name
    end
    screen    = @config.alternate_screen ? SCREEN : {"", ""}
    @teardown = screen[1]
    @input.raw! if @input.tty?
    @input.read_timeout = POLL
    measure
    register
    @output.send(screen[0])
    spawn(name: "term.writer") { run_writer }
    spawn(name: "term.reader") { run_reader }
    spawn(name: "term.engine") { run_engine }
    spawn(name: "term.server") { run_server }
    found = survey
    @features.set(found.value)
    @teardown = FEATURES.reverse.join { |mode| mode.switch(found.includes?(mode.feature), false) } + screen[1]
    @setup    = screen[0] + FEATURES.join { |mode| mode.switch(found.includes?(mode.feature), true) } + CELL_SIZE
    @output.send(@setup.lchop(screen[0]))
  end

  private def register : Nil
    @@lock.synchronize do
      @@open << self
      next if @@hooked || !@config.signals
      @@hooked = true
      at_exit { Term.restore }
      SIGNALS.each do |signal|
        signal.trap do
          Term.restore
          exit 128 + signal.value
        end
      end
      {% unless flag?(:win32) %}
        Signal::TSTP.trap do
          Term.suspend
          Process.signal(Signal::STOP, Process.pid)
        end
        Signal::CONT.trap { Term.resume }
        Signal::WINCH.trap { Term.refresh }
      {% end %}
    end
  end

  private def measure : Resize?
    {% unless flag?(:win32) %}
      size = LibTerm::Winsize.new
      return unless LibTerm.ioctl(@io.fd, TIOCGWINSZ, pointerof(size)) == 0 && size.cols > 0 && size.rows > 0
      @cell_width.set(size.width.to_i // size.cols) if size.width > 0
      @cell_height.set(size.height.to_i // size.rows) if size.height > 0
      Resize.new(size.rows.to_i, size.cols.to_i, size.height.to_i, size.width.to_i)
    {% end %}
  end

  def refresh : Nil
    return if features.resize? || closed?
    measure.try { |resize| push resize }
  rescue Channel::ClosedError
  end

  def suspend : Nil
    return if @restored.get || @suspended.swap(true)
    @io << @teardown
    @io.flush
    @input.cooked! if @input.tty?
  rescue IO::Error
  end

  def resume : Nil
    return if @restored.get || !@suspended.swap(false)
    @input.raw! if @input.tty?
    @io << @setup
    @io.flush
  rescue IO::Error
  end

  def features : Feature
    Feature.new(@features.get)
  end

  protected def restore : Nil
    return if @restored.swap(true)
    @io << dnd_code("t=A") if @accepting.get
    @io << dnd_code("t=o:x=2") if @offering.get
    @io << @teardown
    @io.flush
    @input.cooked! if @input.tty?
  rescue IO::Error
  end

  def close : Nil
    return if @stop.closed?
    @stop.close
    @output.close
    @writer_done.receive?
    restore
    @@lock.synchronize { @@open.delete(self) }
    @pending.close
    @serving.close
    @events.close
    @reader_done.receive?
    @input.read_timeout = nil
  end

  def closed? : Bool
    @stop.closed?
  end

  def print(*objects) : Nil
    @output.send(objects.join)
  end

  def <<(object) : self
    @output.send(object.to_s)
    self
  end

  def pointer=(shape : Shape) : Shape
    @output.send("\e]22;=#{shape.wire}#{ST}")
    shape
  end

  def reset_pointer : Nil
    @output.send("\e]22;#{ST}")
  end

  def push_pointer(*shapes : Shape) : Nil
    @output.send("\e]22;>#{shapes.join(',', &.wire)}#{ST}")
  end

  def pop_pointer : Nil
    @output.send("\e]22;<#{ST}")
  end

  def pointer(which : ShapeQuery = :current) : String?
    reply = request(Query::Shape, "\e]22;?#{which.wire}#{ST}").as?(String)
    reply unless reply == "0"
  end

  def pointer_support(*shapes : Shape) : Array(Bool)?
    request(Query::Shape, "\e]22;?#{shapes.join(',', &.wire)}#{ST}").as?(String).try do |reply|
      reply.split(',').map { |flag| flag == "1" }
    end
  end

  def push_colors : Nil
    @output.send("\e]30001#{ST}")
  end

  def pop_colors : Nil
    @output.send("\e]30101#{ST}")
  end

  def color(key : String | Int32, value : Color | String) : Nil
    @output.send("\e]21;#{key}=#{value}#{ST}")
  end

  def dynamic_color(key : String | Int32) : Nil
    @output.send("\e]21;#{key}=#{ST}")
  end

  def reset_color(key : String | Int32) : Nil
    @output.send("\e]21;#{key}#{ST}")
  end

  def colors(*keys : String | Int32) : Palette?
    query = keys.join(';') { |key| "#{key}=?" }
    request(Query::Color, "\e]21;#{query}#{ST}").as?(Palette)
  end

  def confirm_color(key : String | Int32, value : Color | String, limit : Time::Span = @config.query_timeout) : Color?
    request(Query::Color, "\e]21;#{key}=#{value};#{key}=?#{ST}", limit).as?(Palette).try &.[key.to_s]?
  end

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

  def supports?(mode : Int32) : Bool?
    request(Query::Mode, "\e[?#{mode}$p", key: mode.to_s).as?(Int32).try { |state| !state.in?(0, 4) }
  end

  def query_visibility : Nil
    @output.send("\e[?998n")
  end

  def query_color_scheme : Nil
    @output.send("\e[?996n")
  end

  def window_size(limit : Time::Span = @config.query_timeout) : Size?
    request(Query::Window, "\e[14t", limit).as?(Size)
  end

  def cell_size(limit : Time::Span = @config.query_timeout) : Size?
    request(Query::Cell, "\e[16t", limit).as?(Size)
  end

  def image(pixels : Pixels, id : UInt32 = 0, number : UInt32 = 0, placement : Placement? = nil, quiet : Quiet = Quiet::None, transient : Bool = false, limit : Time::Span = @config.query_timeout) : Ack?
    head, source = load(pixels)
    control = merge(',', keys(',', {'a', placement ? 'T' : 't'}, {'i', id}, {'I', number}, {'q', quiet.value}, {'N', transient}), head, placement ? placed(placement) : "")
    draw(control, source, id, number, quiet, limit)
  end

  def image_query(pixels : Pixels, id : UInt32 = 31, limit : Time::Span = @config.query_timeout) : Ack?
    head, source = load(pixels)
    draw(merge(',', keys(',', {'a', 'q'}, {'i', id}), head), source, id, 0_u32, Quiet::None, limit, probe: true)
  end

  def supports_graphics?(limit : Time::Span = @config.query_timeout) : Bool
    image_query(Pixels.rgb(Bytes.new(3), 1, 1), limit: limit).try(&.ok?) || false
  end

  def place(id : UInt32 = 0, number : UInt32 = 0, placement : Placement = Placement.new, quiet : Quiet = Quiet::None, limit : Time::Span = @config.query_timeout) : Ack?
    control = merge(',', keys(',', {'a', 'p'}, {'i', id}, {'I', number}, {'q', quiet.value}), placed(placement))
    draw(control, Bytes.empty, id, number, quiet, limit)
  end

  def delete_images(target : Delete = Delete::Visible, free : Bool = false, id : UInt32 = 0, number : UInt32 = 0, placement : UInt32 = 0, x : Int32 = 0, y : Int32 = 0, z : Int32 = 0) : Nil
    letter  = DELETES[target]
    control = keys(',', {'a', 'd'}, {'d', free ? letter.upcase : letter}, {'i', id}, {'I', number}, {'p', placement}, {'x', x}, {'y', y}, {'z', z})
    exclusive(Family::Graphics) { @output.send("\e_G#{control}#{ST}") }
  end

  def frame(pixels : Pixels, id : UInt32 = 0, number : UInt32 = 0, x : Int32 = 0, y : Int32 = 0, base : Int32 = 0, edit : Int32 = 0, gap : Int32 = 0, replace : Bool = false, background : UInt32 = 0, quiet : Quiet = Quiet::None, limit : Time::Span = @config.query_timeout) : Ack?
    head, source = load(pixels)
    control = merge(',', keys(',', {'a', 'f'}, {'i', id}, {'I', number}, {'q', quiet.value}, {'x', x}, {'y', y}, {'c', base}, {'r', edit}, {'z', gap}, {'X', replace}, {'Y', background}), head)
    draw(control, source, id, number, quiet, limit, "a=f")
  end

  def animate(id : UInt32 = 0, number : UInt32 = 0, state : Playback? = nil, current : Int32 = 0, loops : Int32 = 0, target : Int32 = 0, gap : Int32 = 0, quiet : Quiet = Quiet::None) : Nil
    control = keys(',', {'a', 'a'}, {'i', id}, {'I', number}, {'q', quiet.value}, {'s', state.try(&.value) || 0}, {'c', current}, {'v', loops}, {'r', target}, {'z', gap})
    exclusive(Family::Graphics) { @output.send("\e_G#{control}#{ST}") }
  end

  def compose(source : Int32, target : Int32, id : UInt32 = 0, number : UInt32 = 0, width : Int32 = 0, height : Int32 = 0, source_x : Int32 = 0, source_y : Int32 = 0, x : Int32 = 0, y : Int32 = 0, replace : Bool = false, quiet : Quiet = Quiet::None, limit : Time::Span = @config.query_timeout) : Ack?
    control = keys(',', {'a', 'c'}, {'i', id}, {'I', number}, {'q', quiet.value}, {'r', source}, {'c', target}, {'w', width}, {'h', height}, {'X', source_x}, {'Y', source_y}, {'x', x}, {'y', y}, {'C', replace})
    draw(control, Bytes.empty, id, number, quiet, limit)
  end

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

  def dnd_support(limit : Time::Span = @config.query_timeout) : Hash(String, String)?
    dnd_request(Query::DndSupport, "t=q", limit, probe: true).as?(Hash(String, String))
  end

  def supports_dnd?(limit : Time::Span = @config.query_timeout) : Bool
    !dnd_support(limit).nil?
  end

  def accept_drops(*mimes, remote : Bool = false) : Nil
    @accepting.set(true)
    machine = Term.machine_id if remote
    exclusive(Family::Dnd) do
      dnd("t=a", mimes.join(' '))
      dnd("t=a:x=1", machine) if machine
    end
  end

  def stop_drops : Nil
    @accepting.set(false)
    dnd("t=A")
  end

  def drop_reply(operation : Operation = Operation::None, *mimes) : Nil
    dnd(keys(':', {'t', 'm'}, {'o', operation.value}), mimes.join(' '))
  end

  def drop_data(index : Int32, entry : Int32 = 0, into : IO? = nil, limit : Time::Span = @config.transfer_timeout) : DropData?
    dnd_request(Query::DropData, keys(':', {'t', 'r'}, {'x', index}, {'y', entry}), limit, "#{index}:#{entry}:0", sink: into).as?(DropData)
  end

  def drop_entry(handle : Int32, index : Int32, into : IO? = nil, limit : Time::Span = @config.transfer_timeout) : DropData?
    dnd_request(Query::DropData, keys(':', {'t', 'r'}, {'Y', handle}, {'x', index}), limit, "#{index}:0:#{handle}", sink: into).as?(DropData)
  end

  def drop_close(handle : Int32) : Nil
    dnd(keys(':', {'t', 'r'}, {'Y', handle}))
  end

  def drop_finish(operation : Operation = Operation::None) : Nil
    dnd("t=r:o=#{operation.value}")
  end

  def drop_save(index : Int32, entry : Int32, destination : Path | String, limit : Time::Span = @config.transfer_timeout) : Bool
    save(Path.new(destination), limit, ->(file : IO) { drop_data(index, entry, file, limit) })
  end

  private def save(destination : Path, limit : Time::Span, fetch : IO -> DropData?) : Bool
    data = File.open(destination, "w") { |file| fetch.call(file) }
    unless data && data.ok?
      File.delete?(destination)
      return false
    end
    return true unless data.symlink? || data.directory?
    listing = File.read(destination)
    File.delete(destination)
    if data.symlink?
      File.symlink(listing, destination)
      return true
    end
    Dir.mkdir_p(destination)
    names = listing.split('\0', remove_empty: true)
    saved = names.each_with_index(1).all? do |name, number|
      next false if name.includes?('/') || name == ".." || name == "."
      save(destination / name, limit, ->(file : IO) { drop_entry(data.handle, number, file, limit) })
    end
    drop_close(data.handle)
    saved
  end

  def offer_drags(remote : Bool = false) : Nil
    @offering.set(true)
    machine = Term.machine_id if remote
    dnd("t=o:x=1", machine || "")
  end

  def stop_drags : Nil
    @offering.set(false)
    dnd("t=o:x=2")
  end

  def drag_offer(operations : Operation, *mimes : String) : Nil
    dnd(keys(':', {'t', 'o'}, {'o', operations.value}), mimes.join(' '))
  end

  def drag_presend(index : Int32, data : Bytes | IO) : Nil
    dnd_stream(keys(':', {'t', 'p'}, {'x', index}), data)
  end

  def drag_image(number : Int32, data : Bytes | IO, format : Format, width : Int32, height : Int32, opacity : Int32 = 0) : Nil
    dnd_stream(keys(':', {'t', 'p'}, {'x', -number}, {'y', format.value}, {'X', width}, {'Y', height}, {'o', opacity}), data)
  end

  def drag_text(number : Int32, text : String, numerator : Int32 = 1, denominator : Int32 = 1, opacity : Int32 = 0) : Nil
    drag_image(number, text.to_slice, Format::Text, numerator, denominator, opacity)
  end

  def drag_show(index : Int32) : Nil
    dnd(keys(':', {'t', 'P'}, {'x', index}))
  end

  def drag_start(limit : Time::Span = @config.transfer_timeout) : String?
    dnd_request(Query::DragStart, "t=P:x=-1", limit).as?(String)
  end

  def drag_data(index : Int32, data : Bytes | IO) : Nil
    dnd_stream(keys(':', {'t', 'e'}, {'y', index}), data)
  end

  def drag_fail(index : Int32, name : String, description : String? = nil) : Nil
    dnd(keys(':', {'t', 'E'}, {'y', index}), merge(':', name, description || ""))
  end

  def drag_abort(name : String, description : String? = nil) : Nil
    dnd("t=E", merge(':', name, description || ""))
  end

  def drag_cancel : Nil
    dnd("t=E:y=-1")
  end

  def drag_entry(index : Int32, data : Bytes | IO, flag : Int32 = 0, parent : Int32 = 0, child : Int32 = 0) : Nil
    dnd_stream(keys(':', {'t', 'k'}, {'x', index}, {'X', flag}, {'Y', parent}, {'y', child}), data)
  end

  def drag_files(paths : Enumerable(String | Path)) : String
    list = paths.map { |path| Path.new(path).expand.to_s }.to_a
    @serving.send(list)
    Term.uri_list(list)
  end

  def drag_path(index : Int32, path : Path | String) : Nil
    exclusive(Family::Dnd) do
      queue = Deque({Path, Int32, Int32}).new
      queue << {Path.new(path), 0, 0}
      handle = 1
      while item = queue.shift?
        target, parent, child = item
        info = File.info(target, follow_symlinks: false)
        if info.symlink?
          drag_entry(index, File.readlink(target).to_slice, 1, parent, child)
        elsif info.directory?
          handle += 1
          names = Dir.children(target).select do |name|
            kind = File.info(target / name, follow_symlinks: false)
            kind.file? || kind.directory? || kind.symlink?
          end.sort!
          names.each_with_index(1) { |name, number| queue << {target / name, handle, number} }
          drag_entry(index, names.join('\0').to_slice, handle, parent, child)
        elsif info.file?
          File.open(target) { |file| drag_entry(index, file, 0, parent, child) }
        elsif parent == 0
          drag_abort("EINVAL")
        end
      end
    end
  rescue error : IO::Error
    drag_abort(error.os_error.try(&.to_s) || "EIO")
  end

  private def ident(value : String) : String
    raise ArgumentError.new("invalid identifier: #{value.inspect}") unless value.matches?(IDENT)
    value
  end

  private def exclusive(family : Family, &)
    @mutexes[family.value].synchronize { yield }
  end

  private def dnd(meta : String, payload : String = "") : Nil
    exclusive(Family::Dnd) { @output.send(dnd_code(meta, payload)) }
  end

  private def dnd_stream(meta : String, source : Bytes | IO) : Nil
    prefix = "\e]#{DND};#{merge(':', meta, @mux)}"
    exclusive(Family::Dnd) do
      blocks(source) do |text, _|
        @output.send("#{prefix}:m=1;#{text}#{ST}") unless text.empty?
      end
      @output.send("#{prefix}:m=0#{ST}")
    end
  end

  private def dnd_request(query : Query, meta : String, limit : Time::Span, key : String = "", probe : Bool = false, sink : IO? = nil) : Reply
    await(exclusive(Family::Dnd) { enqueue(query, dnd_code(meta), key, probe, sink) }, limit)
  end

  private def blocks(source : Bytes | IO, size : Int32 = RAW_CHUNK, & : String, Bool ->) : Nil
    held = nil
    each_block(source, size) do |slice|
      held.try { |previous| yield previous, false }
      held = Base64.strict_encode(slice)
    end
    yield held || "", true
  end

  private def each_block(source : Bytes, size : Int32, & : Bytes ->) : Nil
    offset = 0
    while offset < source.size
      yield source[offset, Math.min(size, source.size - offset)]
      offset += size
    end
  end

  private def each_block(source : IO, size : Int32, & : Bytes ->) : Nil
    buffer = Bytes.new(size)
    loop do
      filled = 0
      while filled < size
        count = source.read(buffer[filled..])
        break if count == 0
        filled += count
      end
      yield buffer[0, filled] if filled > 0
      break if filled < size
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

  private def keys(separator : Char, *pairs) : String
    String.build do |io|
      pairs.each do |name, value|
        next if value == 0 || value == false
        io << separator unless io.empty?
        io << name << '=' << (value == true ? 1 : value)
      end
    end
  end

  private def merge(separator : Char, *parts : String) : String
    parts.reject(&.empty?).join(separator)
  end

  private def placed(placement : Placement) : String
    keys(',', {'p', placement.id}, {'x', placement.x}, {'y', placement.y}, {'w', placement.width}, {'h', placement.height}, {'X', placement.offset_x}, {'Y', placement.offset_y}, {'c', placement.columns}, {'r', placement.rows}, {'z', placement.z}, {'C', placement.hold_cursor}, {'U', placement.placeholder}, {'P', placement.parent}, {'Q', placement.parent_placement}, {'H', placement.shift_x}, {'V', placement.shift_y})
  end

  private def load(pixels : Pixels) : {String, Bytes | IO}
    data = pixels.data
    size = pixels.size
    if pixels.compress && pixels.medium.direct?
      raw    = data.is_a?(IO) ? data.getb_to_end : data
      size   = raw.size if pixels.format.png?
      packed = IO::Memory.new
      Compress::Zlib::Writer.open(packed, &.write(raw))
      data = packed.to_slice
    end
    control = keys(',', {'f', pixels.format.value}, {'t', MEDIA[pixels.medium]}, {'s', pixels.width}, {'v', pixels.height}, {'S', size}, {'O', pixels.offset}, {'o', pixels.compress ? 'z' : 0})
    {control, data}
  end

  private def draw(control : String, source : Bytes | IO, id : UInt32, number : UInt32, quiet : Quiet, limit : Time::Span, action : String = "", probe : Bool = false) : Ack?
    more = merge(',', action, keys(',', {'q', quiet.value}))
    key  = number != 0 ? "I#{number}" : "i#{id}"
    wait = quiet.none? && (id != 0 || number != 0)
    waiter = exclusive(Family::Graphics) do
      pending = nil
      whole   = probe ? String::Builder.new : nil
      first   = true
      blocks(source) do |text, last|
        code = String.build do |io|
          io << "\e_G" << merge(',', first ? control : more, first && last ? "" : "m=#{last ? 0 : 1}")
          io << ';' << text unless text.empty?
          io << ST
        end
        if whole
          whole << code
        elsif first && wait
          pending = enqueue(Query::Graphics, code, key)
        else
          @output.send(code)
        end
        first = false
      end
      whole ? enqueue(Query::Graphics, whole.to_s, key, true) : pending
    end
    waiter.try { |channel| await(channel, limit).as?(Ack) }
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

  private def dnd_code(meta : String, payload : String = "") : String
    prefix = "\e]#{DND};#{merge(':', meta, @mux)}"
    String.build do |io|
      offset = 0
      while payload.bytesize - offset > WIRE_CHUNK
        io << prefix << ":m=1;" << payload.byte_slice(offset, WIRE_CHUNK) << ST
        offset += WIRE_CHUNK
      end
      io << prefix
      io << ';' << payload.byte_slice(offset) if offset < payload.bytesize
      io << ST
    end
  end

  private def request(query : Query, sequence : String, limit : Time::Span = @config.query_timeout, key : String = "", probe : Bool = false) : Reply
    await(enqueue(query, sequence, key, probe), limit)
  end

  private def enqueue(query : Query, sequence : String, key : String = "", probe : Bool = false, sink : IO? = nil) : Channel(Reply)
    waiter = Channel(Reply).new(2)
    @output.send(Request.new(query, key, sequence, waiter, probe, sink))
    waiter
  end

  private def await(waiter : Channel(Reply), limit : Time::Span) : Reply
    select
    when reply = waiter.receive
      reply
    when timeout(limit)
      nil
    end
  ensure
    waiter.close
  end

  private def survey : Feature
    return Feature::All unless @config.detect
    deadline = clock + @config.query_timeout
    waiters  = FEATURES.map { |mode| {mode, enqueue(Query::Mode, mode.probe, mode.key, true)} }
    waiters.reduce(Feature::None) do |found, (mode, waiter)|
      state = await(waiter, {deadline - clock, Time::Span.zero}.max).as?(Int32) || 0
      state.in?(0, 4) ? found : found | mode.feature
    end
  end

  private def admit : Nil
    loop do
      select
      when request = @pending.receive?
        return unless request
        @waiting.put_if_absent({request.query, request.key}) { Deque(Request).new } << request
      else
        return
      end
    end
  end

  private def peek(query : Query, key : String = "") : Request?
    admit
    queue = @waiting[{query, key}]? || return
    while request = queue.first?
      return request unless request.waiter.closed?
      queue.shift
    end
  end

  private def sweep : Nil
    @waiting.reject! { |_, queue| queue.all?(&.waiter.closed?) }
  end

  private def route(query : Query, reply : Reply, key : String = "", strict : Bool = false) : Bool
    admit
    slot      = {query, key}
    queue     = @waiting[slot]? || return false
    delivered = false
    while request = queue.shift?
      delivered = deliver(request.waiter, reply)
      break if delivered || strict
    end
    @waiting.delete(slot) if queue.empty?
    delivered
  end

  private def deliver(waiter : Channel(Reply), reply : Reply) : Bool
    return false if waiter.closed?
    waiter.send(reply)
    true
  rescue Channel::ClosedError
    false
  end

  private def run_writer : Nil
    while item = @output.receive?
      transmit(item)
      loop do
        select
        when more = @output.receive?
          break unless more
          transmit(more)
        else
          break
        end
      end
      @io.flush
    end
  rescue IO::Error | Channel::ClosedError
  ensure
    @output.close
    @writer_done.close
  end

  private def transmit(item : Output) : Nil
    case item
    in String
      @io << item
    in Request
      @pending.send(item)
      @pending.send(item.copy_with(query: Query::Attributes, key: "")) if item.probe
      @io << item.sequence
      @io << ATTRIBUTES if item.probe
    end
  end

  private def run_reader : Nil
    buffer = Bytes.new(4096)
    until @stop.closed?
      admit
      count = begin
        @input.read(buffer)
      rescue IO::TimeoutError
        sweep
        idle
        next
      end
      break if count == 0
      buffer[0, count].each { |byte| feed(byte) }
    end
  rescue Channel::ClosedError | IO::Error
  ensure
    @raw.close
    @reader_done.close
  end

  private def run_server : Nil
    paths = [] of String
    while message = @serving.receive?
      case message
      in Array(String)
        paths = message
      in Int32
        next if paths.empty?
        path = paths[message - 1]?
        path ? drag_path(message, path) : drag_abort("ENOENT")
      end
    end
  rescue Channel::ClosedError
  end

  private def push(event : Raw) : Nil
    @raw.send(event)
  end

  private def feed(byte : UInt8) : Nil
    case @state
    in .ground?
      if byte == 0x1b
        @state = State::Escape
      elsif byte < 0x80
        typed(byte.unsafe_chr, Mods::None)
      else
        utf(byte)
      end
    in .escape?
      @seq.clear
      @state = case byte
               when 0x5b then State::Csi
               when 0x4f then State::Ss3
               when 0x1b then State::Escape
               when 0x50, 0x58, 0x5d, 0x5e, 0x5f
                 @string = byte
                 State::Text
               else
                 State::Ground
               end
      if @state.ground?
        byte < 0x80 ? typed(byte.unsafe_chr, Mods::Alt) : utf(byte)
      end
    in .ss3?
      @state = State::Ground
      if named = SS3[byte.unsafe_chr]?
        tapped(Key.new(named.value, Key::Action::Press, Mods::None, nil, nil, nil))
      end
    in .paste?
      @seq.write_byte(byte)
      slice = @seq.to_slice
      if byte == 0x7e && slice.size >= PASTE_END.size && slice[-PASTE_END.size..] == PASTE_END
        @state = State::Ground
        push Paste.new(["text/plain"], false, nil, String.new(slice[0, slice.size - PASTE_END.size]).scrub)
      elsif slice.size > TEXT_LIMIT
        @state = State::Ground
      end
    in .csi?
      case byte
      when 0x20..0x3f
        @seq.write_byte(byte)
        @state = State::Ground if @seq.size > CSI_LIMIT
      when 0x40..0x7e
        @state = State::Ground
        csi(byte)
      when 0x1b
        @state = State::Escape
      else
        @state = State::Ground
      end
    in .text?
      case byte
      when 0x07
        @state = State::Ground
        text
      when 0x1b
        @state = State::TextEscape
      else
        @seq.write_byte(byte)
        @state = State::Ground if @seq.size > TEXT_LIMIT
      end
    in .text_escape?
      if byte == 0x5c
        @state = State::Ground
        text
      else
        @state = State::Escape
        feed(byte)
      end
    end
  end

  private def idle : Nil
    case @state
    when .escape?
      @state = State::Ground
      tapped(Key.new(Named::Escape.value, Key::Action::Press, Mods::None, nil, nil, nil))
    when .ss3?
      @state = State::Ground
      typed('O', Mods::Alt)
    end
  end

  private def utf(byte : UInt8) : Nil
    @utf.clear if byte & 0xc0 != 0x80
    @utf.write_byte(byte)
    lead = @utf.to_slice[0]
    need = lead >= 0xf0 ? 4 : lead >= 0xe0 ? 3 : lead >= 0xc0 ? 2 : 0
    return @utf.clear if need == 0
    return if @utf.size < need
    text = String.new(@utf.to_slice)
    @utf.clear
    typed(text[0], Mods::None) if text.valid_encoding?
  end

  private def typed(char : Char, mods : Mods) : Nil
    code, extra, text =
      case char.ord
      when 0x0d   then {Named::Enter.value, Mods::None, nil}
      when 0x09   then {Named::Tab.value, Mods::None, nil}
      when 0x7f   then {Named::Backspace.value, Mods::None, nil}
      when 0x00   then {32, Mods::Ctrl, nil}
      when 1..26  then {char.ord + 96, Mods::Ctrl, nil}
      when 28..31 then {char.ord + 64, Mods::Ctrl, nil}
      else
        lower = char.downcase
        {lower.ord, lower == char ? Mods::None : Mods::Shift, char.to_s}
      end
    mods |= extra
    shifted = char.ord if text && mods.shift?
    tapped(Key.new(code, Key::Action::Press, mods, shifted, nil, mods.alt? ? nil : text))
  end

  private def tapped(key : Key) : Nil
    push key
    push key.copy_with(action: Key::Action::Release, text: nil)
  end

  private def text : Nil
    case @string
    when 0x5d then osc
    when 0x5f then apc
    end
  rescue Base64::Error
  end

  private def parse(bytes : Bytes) : Nil
    @values.clear
    @starts.clear
    @starts << 0
    current  = MISSING
    negative = false
    bytes.each do |byte|
      case byte
      when 0x30..0x39
        current = (current == MISSING ? 0 : current) &* 10 &+ (byte &- 0x30)
      when 0x2d
        negative = true
      when 0x3a, 0x3b
        @values << (negative && current != MISSING ? -current : current)
        current  = MISSING
        negative = false
        @starts << @values.size if byte == 0x3b
      end
    end
    @values << (negative && current != MISSING ? -current : current)
  end

  private def param(group : Int32, sub : Int32 = 0, default : Int32 = MISSING) : Int32
    start = @starts[group]? || return default
    stop  = @starts[group + 1]? || @values.size
    index = start + sub
    return default unless index < stop
    value = @values[index]
    value == MISSING ? default : value
  end

  private def csi(final : UInt8) : Nil
    bytes  = @seq.to_slice
    letter = final.unsafe_chr
    parse(bytes)
    case bytes.first?.try(&.unsafe_chr)
    when '<'
      mouse(letter == 'm') if letter.in?('M', 'm')
    when '?'
      case letter
      when 'c'
        route(Query::Attributes, nil, strict: true)
      when 'u'
        route(Query::Mode, 1, "u")
      when 'y'
        route(Query::Mode, param(1, 0, 0), param(0, 0, 0).to_s)
      when 'n'
        case param(0)
        when 997 then push ColorScheme.new(param(1) == 1)
        when 999 then push Visibility.new(param(1) == 1)
        end
      end
    when '>', '='
      nil
    else
      case letter
      when 'u' then key(param(0, 0, 0))
      when '~' then tilde
      when 'I' then push Focus.new(true)
      when 'O' then push Focus.new(false)
      when 't' then report
      else          LETTERS[letter]?.try { |named| key(named.value) }
      end
    end
  end

  private def tilde : Nil
    if param(0) == 200
      @seq.clear
      @state = State::Paste
    else
      TILDES[param(0)]?.try { |named| key(named.value) }
    end
  end

  private def report : Nil
    case param(0)
    when 48
      resize
    when 4
      route(Query::Window, Size.new(param(2, 0, 0), param(1, 0, 0)))
    when 6
      @cell_height.set(param(1, 0, 0))
      @cell_width.set(param(2, 0, 0))
      route(Query::Cell, Size.new(@cell_width.get, @cell_height.get))
    end
  end

  private def key(code : Int32) : Nil
    mods    = Mods.new((param(1, 0, 1) &- 1).to_u8!)
    action  = Key::Action.from_value?(param(1, 1, 1)) || Key::Action::Press
    shifted = param(0, 1, 0)
    base    = param(0, 2, 0)
    text = if @starts.size > 2
             String.build do |io|
               (@starts[2]...@values.size).each do |index|
                 char(@values[index]).try { |char| io << char }
               end
             end.presence
           end
    key = Key.new(code, action, mods, shifted > 0 ? shifted : nil, base > 0 ? base : nil, text)
    features.keyboard? ? push(key) : tapped(key)
  end

  private def char(value : Int32) : Char?
    value.unsafe_chr if 0 < value <= Char::MAX_CODEPOINT && !(0xd800..0xdfff).includes?(value)
  end

  private def mouse(release : Bool) : Nil
    pb  = param(0, 0, 0)
    x   = param(1, 0, 0)
    y   = param(2, 0, 0)
    low = pb & 3
    action, button =
      if pb.bits_set?(256)
        {Mouse::Action::Leave, Mouse::Button::None}
      elsif pb.bits_set?(64)
        {Mouse::Action::Scroll, Mouse::Button.new(4 + low)}
      elsif pb.bits_set?(32) && low == 3
        {Mouse::Action::Hover, Mouse::Button::None}
      elsif release
        {Mouse::Action::Release, Mouse::Button.new(pb.bits_set?(128) ? 8 + low : low)}
      elsif pb.bits_set?(32)
        {Mouse::Action::Drag, Mouse::Button.new(pb.bits_set?(128) ? 8 + low : low)}
      else
        {Mouse::Action::Press, Mouse::Button.new(pb.bits_set?(128) ? 8 + low : low)}
      end
    width  = @cell_width.get
    height = @cell_height.get
    if features.pixels?
      col = width > 0 ? x // width : 0
      row = height > 0 ? y // height : 0
    else
      col = {x - 1, 0}.max
      row = {y - 1, 0}.max
      x   = col * {width, 1}.max
      y   = row * {height, 1}.max
    end
    push Mouse.new(action, button, Mods.new(((pb >> 2) & 7).to_u8!), x, y, col, row)
  end

  private def resize : Nil
    rows   = param(1, 0, 0)
    cols   = param(2, 0, 0)
    height = param(3, 0, 0)
    width  = param(4, 0, 0)
    @cell_width.set(cols > 0 ? width // cols : 0)
    @cell_height.set(rows > 0 ? height // rows : 0)
    push Resize.new(rows, cols, height, width)
  end

  private def fields(text : String, separator : Char = ':') : Hash(String, String)
    text.split(separator, remove_empty: true).to_h do |pair|
      name, _, value = pair.partition('=')
      {name.strip, value.strip}
    end
  end

  private def number(meta : Hash(String, String), name : String) : Int32
    meta[name]?.try(&.to_i?) || 0
  end

  private def osc : Nil
    code, _, body = String.new(@seq.to_slice).partition(';')
    meta, _, payload = body.partition(';')
    case code.to_i?
    when 22   then route(Query::Shape, body)
    when 21   then route(Query::Color, decode_colors(body))
    when 5522 then clipboard(fields(meta), payload)
    when 99   then notified(fields(meta), payload)
    when DND  then chained(fields(meta), payload)
    end
  end

  private def apc : Nil
    body = String.new(@seq.to_slice)
    return unless body.starts_with?('G')
    control, _, message = body.lchop('G').partition(';')
    meta = fields(control, ',')
    ack  = Ack.new(meta["i"]?.try(&.to_u32?) || 0_u32, meta["I"]?.try(&.to_u32?) || 0_u32, meta["p"]?.try(&.to_u32?) || 0_u32, message)
    route(Query::Graphics, ack, ack.number != 0 ? "I#{ack.number}" : "i#{ack.image}") || push(ack)
  end

  private def decode_colors(body : String) : Palette
    palette = Palette.new({} of String => Color?, [] of String)
    body.split(';') do |pair|
      name, _, value = pair.partition('=')
      if name == "unknown"
        palette.unknown << Base64.decode_string(value)
      else
        palette.colors[name] = Color.parse(value)
      end
    end
    palette
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

  private def chained(meta : Hash(String, String), payload : String) : Nil
    if type = meta["t"]?
      @chain = type.in?("r", "R") ? "r:#{number(meta, "x")}:#{number(meta, "y")}:#{number(meta, "Y")}" : type
    end
    name  = @chain
    chain = @chains.put_if_absent(name) { Chain.new }
    chain.meta.merge!(meta)
    final = meta["m"]? != "1"
    if chain.meta["t"]? == "r"
      chain.decode(payload, peek(Query::DropData, name.lchop("r:")).try(&.sink) || chain.data, final)
    else
      chain.text << payload
    end
    return unless final
    @chains.delete(name)
    dispatch(chain.meta, chain.text.to_s, chain.data.to_slice)
  end

  private def dispatch(meta : Hash(String, String), payload : String, data : Bytes) : Nil
    col = number(meta, "x")
    row = number(meta, "y")
    case type = meta["t"]?
    when "m", "M"
      kind = type == "M" ? Drop::Kind::Land : (col < 0 ? Drop::Kind::Leave : Drop::Kind::Move)
      push Drop.new(kind, col, row, number(meta, "X"), number(meta, "Y"), Operation.new(number(meta, "o") & 3), payload.presence.try(&.split))
    when "r", "R"
      entry = meta.has_key?("y") || meta.has_key?("Y")
      reply = type == "r" ? DropData.new(data, number(meta, "X"), entry: entry) : DropData.new(Bytes.empty, error: payload, entry: entry)
      route(Query::DropData, reply, "#{col}:#{row}:#{number(meta, "Y")}")
    when "o"
      push Drag.new(:gesture, col, row, number(meta, "X"), number(meta, "Y"))
    when "e"
      case col
      when 1 then push Drag.new(:accepted, index: row)
      when 2 then push Drag.new(:action, operation: Operation.new(number(meta, "o") & 3))
      when 3 then push Drag.new(:dropped)
      when 4 then push Drag.new(:finished, canceled: row == 1)
      when 5 then push Drag.new(:data_request, index: row)
      end
    when "E"
      route(Query::DragStart, payload) || push(payload == "OK" ? Drag.new(:started) : Drag.new(:error, error: payload))
    when "k"
      push Drag.new(:file_request, index: col)
      @serving.send(col)
    when "q"
      route(Query::DndSupport, fields(payload))
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
        fire(timer)
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

  private def clock : Time::Span
    Time.instant - STARTED
  end

  private def emit(event : Event) : Nil
    @backlog.shift if @backlog.size >= @config.event_backlog
    @backlog << event
  end

  private def arm(kind : Timer::Kind, now : Time::Span, delay : Time::Span, code : Int32 = 0) : Nil
    @timers.reject! { |timer| timer.kind == kind && timer.code == code }
    @timers << Timer.new(now + delay, kind, code)
  end

  private def fire(timer : Timer) : Nil
    case timer.kind
    in .hold?
      @held[timer.code]?.try { |held| hold(held) }
    in .sequence?
      @node = @root
    in .dwell?
      last = @last
      if last && @inside && !@dwelling
        @dwelling = true
        emit MouseGesture.new(:hover_dwell, last)
      end
    in .long_press?
      press = @press
      emit MouseGesture.new(:long_press, press) if press && !@dragging
    in .scroll?
      flush_scroll
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
    mods     = key.mods & ~LOCKS
    shifted  = key.shifted if mods.shift?
    physical = @physical[{key.base || key.code, mods}]?
    symbolic = @symbolic[{shifted || key.code, shifted ? mods & ~Mods::Shift : mods}]?
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
    flush_scroll if @scroll.try(&.button) != mouse.button
    @scroll_from = now if @scroll_count == 0
    @scroll      = mouse
    @scroll_count += 1
    @scroll_at = now
    arm(:scroll, now, @config.scroll_window)
  end

  private def flush_scroll : Nil
    mouse         = @scroll || return
    count         = @scroll_count
    span          = @scroll_at - @scroll_from
    @scroll       = nil
    @scroll_count = 0
    velocity      = span > Time::Span.zero ? count / span.total_seconds : 0.0
    emit MouseGesture.new(:scroll, mouse, count, 0, 0, velocity)
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
