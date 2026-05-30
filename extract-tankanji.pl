#!/usr/bin/perl
our $VERSION = "0.1.0"; # Time-stamp: <2026-05-30T15:36:27Z>

use utf8;
use strict;
use warnings;
use sort 'stable';
use Encode qw(encode decode);

# 出力の文字コードは euc-jisx0213 である。2026年、Perl スクリプトは
# UTF-8 化したが、内部処理は依然、ほとんど euc-jisx0213 で行っている。

our $OUT = "tankanji-2026.txt"; # 出力を標準出力にしない場合はこれを設定

# ここからの資料は主に入手したのは 2005年であり、2026年5月現在、多くが
# 消えているか、インターネットアーカイブにしか残っていない。

# これらの寄せ集めで「自動生成」した辞書に私の著作権が主張できるかはか
# なり微妙である。しかし、単漢字変換という文化を残すにはこれらを参考に
# するしかなかった。許されんことを願う。

# IME「風」に含まれる単漢字辞書。今回はまず単漢字の読みごとの頻度を参
# 考にしている。そして「風」辞書の読みと漢字は優先割り当てしている。も
# ちろん、「風」辞書と同じ場所にではない。さらに SKK の辞書の読みでは
# どうしても足らないと感じたので、「風」辞書の読みはすべて「コピー」し
# て補った。

# https://www.vector.co.jp/soft/winnt/writing/se122541.html
our $KAZE_REA = "Wind2.rea";
our $KAZE_DIC = "Wind2.dic";

# 頻度情報のために pubdic+ が必要。かんなのパッケージには付いてくる。
# http://www.remus.dti.ne.jp/~endo-h/wnn/ などで入手。
our $PUBDIC_DIR = "Canna37p3/dic/ideo/pubdic";
our @PUBDIC = glob("$PUBDIC_DIR/*.p");

# SKK辞書のホームページより。
# http://openlab.ring.gr.jp/skk/wiki/wiki.cgi?page=SKK%BC%AD%BD%F1
our $SKKDIC_DIR = ".";
our @SKKDIC = ("SKK-JISYO.L",
	       "SKK-JISYO.JIS3_4");

# JISX0213 InfoCenter (http://www.jca.apc.org/~earthian/aozora/0213.html)より
our $JISX0213INFO_DIR = "jisx0213";
our $RADICAL_TXT = "$JISX0213INFO_DIR/radical-tab.txt";
our $PLURAL_TXT = "$JISX0213INFO_DIR/plural0213.txt";
our $ONKUN_TXT = "$JISX0213INFO_DIR/onkun0213.txt";
our $ITAIJI_TXT = "$JISX0213INFO_DIR/variant0213.txt";

# 大修館書店の漢字文化アーカイブ(http://www.taishukan.co.jp/kanji/)よ
# り。古い常用漢字表。
our $TAISHUKAN_DIR = "taishukan";
our $JOYOKANJI = "$TAISHUKAN_DIR/joyokanji.txt";

# 2026年、Claude さんに Wikipedia から作ってもらった新しい常用漢字表。
#
# 《常用漢字一覧 - Wikipedia》  
# https://ja.wikipedia.org/wiki/%E5%B8%B8%E7%94%A8%E6%BC%A2%E5%AD%97%E4%B8%80%E8%A6%A7
our $JOYOKANJI_2010 = "joyokanji_gakunen.euc.txt";

# 自分で作った補助ファイル
our $BUSHUNAME_TXT = "bushu-name.euc.txt";
our $BUSHUINFO_TXT = "bushu-info.euc.txt";
our $PREDEF_TANKANJI_TXT = "predef-tankanji.euc.txt";
our $YOMI_IGNORE_TXT = "yomi-ignore.euc.txt";
our $SKK_AFTER_IGNORE = "SKK-JISYO.hoi";
our $KANA_TABLE_PL = "kana-table.euc.pl";
our $DAKUON_TABLE_PL = "dakuon-table.euc.pl";

our $DEBUG = 0;

# 以下は「ハイパーパラメータ」で、ここを調整することで辞書が多少変化す
# る。あと 後述の @JOYO_PREF も「ハイパーパラメータ」的である。これら
# を変更して納得のいくものを選んだ。

#our $HINDO_CUTOFF = 5;
our $HINDO_CUTOFF = 10;
#our $USE_NEW_JOYO = 1;
our $USE_NEW_JOYO = 0;
our $USE_JOYO_PREF_ALL = 0;
#our $USE_JOYO_PREF_ALL = 1;

# 2026年時のプログラムは Gemini さん・ChatGPT さん・Claude さんに指導
# をあおぐところも多かった。

use Fcntl qw(:seek);

#$OUT = "test.euc.out";
if (0) {
  open(STDERR, ">&STDOUT") or die;
}

if (defined $OUT && $OUT) {
  open(STDOUT, ">$OUT") or die;
}

binmode STDERR, ':utf8';

for my $sig (qw(__WARN__ __DIE__)) {
    $SIG{$sig} = sub {
        my $msg = shift;

        if ($sig eq '__WARN__') {
            local $SIG{__WARN__};
            CORE::warn decode('euc-jp', $msg);
        } else {
            local $SIG{__DIE__};
            die decode('euc-jp', $msg);
        }
    };
}

our %DAKUON;
our %H2R;
our %K2R;
our %R2HK;
our %HK2H;
our %HK2H3;
our %HK2K;
our %HK2K3;

use lib ".";
require $DAKUON_TABLE_PL;
require $KANA_TABLE_PL;

our %K2Z = (
	"MAX" => 1,
	1 => {
#	"*"	=>	"＊",
	},
       );

our $KANJI = "(?:\x8f?[\xa1-\xfe][\xa1-\xfe]|\x8e[\xa1-\xfe])";
our $JISX0213_C = 
  "(?:\x8f[\xa1-\xfe][\xa1-\xfe]|\xf4[\xa7-\xfe]|[\xf5-\xfe][\xa1-\xfe]"
  . "|\xa2[\xb0-\xb9\xc2-\xc9\xd1-\xdb\xeb-\xf1\xfa-\xfd]"
  . "|\xa3[\xa1-\xaf\xba-\xc0\xdb-\xe0\xfb-\xfe]"
  . "|\xa4[\xf4-\xfb]|\xa5[\xf7-\xfe]"
  . "|\xa6[\xb9-\xc0\xd9-\xfe]"
  . "|\xa7[\xc2-\xd0\xf2-\xfe]"
  . "|\xa8[\xc1-\xde\xe7-\xfc]"
  . "|[\xa9-\xab][\xa1-\xfe]"
  . "|\xac[\xa1-\xf3\xfd\xfe]"
  . "|\xad[\xa1-\xd7\xdf-\xef\xf3\xf8\xf9\xfd\xfe]"
  . "|\xae[\xa2-\xfe]|\xaf[\xa1-\xfd]"
  . "|\xcf[\xd5-\xfd])";
our $IN_MS = "(?:\xad[\xa1-\xd6\xdf-\xef\xf3\xf8\xf9])";
our $NOT_IN_MS = "\xa2\xaf";
our $GAIJI = 
  "(?:\xa4[\xfc-\xfe]|\xa8[\xdf-\xe6\xfd\xfe]|\xac[\xf4-\xfc]"
  . "|\xad[\xd8-\xde\xf0-\xf2\xf4-\xf7\xfa-\xfc]"
  . "|\xae\xa1|\xaf\xfe|\xcf[\xd4\xfe]"
  . "|\xf4\xa7|\xfe[\xfa-\xfe]|\x8f\xfe[\xf7-\xfe])";
our $NOT_AVAIL = "(?:\x8f[\xa2\xa6\xa7\xa9-\xab\xb0-\xed][\xa1-\xfe]|$GAIJI)";
our $JISX0213_KANA = "(?:\xa4[\xf4-\xfb]|\xa5[\xf7-\xfe]|\xa6[\xee-\xfe]|\xa7[\xf2-\xf5])";
our $KANAKIGOU = "(?:\xa1[\xa2-\xac\xbc\xd6-\xd9])";
our $DAKUTENLINE = "(?:\xa1[\xab\xac\xbc])";
our $DAKUTEN = "(?:\xa1[\xab\xac])";
our $TRUEHIRAGANA = "(?:\xa4[\xa1-\xfb])";
our $TRUEKATAKANA = "(?:\xa5[\xa1-\xfe]|\xa6[\xee-\xfe]|\xa7[\xf2-\xf5])";
our $HANKATA = "(?:\x8e[\xa1-\xdf])";
our $TRUEKANJI = 
  "(?:\x8f[\xa1-\xfe][\xa1-\xfe]|\xae[\xa2-\xfe]|[\xaf-\xfe][\xa1-\xfe]"
  . "|\xa1[\xb8\xb9])";
our $OKURI = "(?:$DAKUTEN|$TRUEHIRAGANA)";
our $HIRAGANA = "(?:$DAKUTENLINE|$TRUEHIRAGANA)";
our $KATAKANA = "(?:$KANAKIGOU|$TRUEKATAKANA)";
our $TRUEOKURI = "(?:\xa4[\xa6\xaf\xc4\xcc\xe0\xb0\xba\xd6\xb9\xeb\xa4]|$TRUEHIRAGANA\xa4[\xa4\xb9\xeb])";

#our $UNDEF_CODE = "\xA2\xAE";
our $UNDEF_CODE = "  ";

our $YOMI_IGNORE_PAT = "(?:(?:[^\\.01-9\x80-\xFF].*)|(?:\\.\\.+)|(?:[01-9]+[^01-9].*)|(?:(?:[\xa1-\xa3\xa8-\xae][\xa1-\xfe]|\xa6[\xa1-\xed]|\xa7[\xa1-\xf1\xf6-\xfe])+))";
our $KANJI_IGNORE_PAT = "(?:\xa1\xb9)";

our $SJIS_C = '(?:[\x81-\x9F\xE0-\xFF].)';
our $SJIS_KANA = '[\xa1-\xdf]';
our $IGNORE_GAIJI = 0;
our $IGNORE_YOMI = 1;

our @KAZE_ORDER = (
    40,  38,  32,  34,  36,  35,  33,  31,  37,  39,
    22,  16,   6,  10,  14,  13,   9,   5,  15,  21,
    18,  12,   2,   4,   8,   7,   3,   1,  11,  17,
    30,  28,  20,  24,  26,  25,  23,  19,  27,  29,
);

our @ORDER = (
     0,   1,   2,   3,   4,   5,   6,   7,   8,   9,
    10,  11,  12,  13,  14,  15,  16,  17,  18,  19,
    20,  21,  22,  23,  24,  25,  26,  27,  28,  29,
    30,  31,  32,  33,  34,  35,  36,  37,  38,  39,
);

#our @JOYO_PREF = (27, 22, 26, 23, 17, 12, 25, 24, 16, 13, 28, 21, 15, 14, 18, 11);
#our @JOYO_PREF = (27, 22, 26, 23, 17, 12, 25, 24, 16, 13);
#our @JOYO_PREF = (27, 22, 26, 23, 17, 12, 25, 24, 16, 13);
#our @JOYO_PREF = (26, 23, 27, 22, 25, 24, 28, 21, 16, 13, 17, 12, 36, 33, 37, 32, 35, 34);
our @JOYO_PREF = (26, 23, 27, 22, 25, 24, 28, 21);
#our @JOYO_PREF = (26, 23, 27, 22, 25, 24);
#our @JOYO_PREF = ();

our %BUSHU_PREF =
(
"all:L"
=>[2.8,	[24, 14, 4, 5]],
"all:L|B"
=>[3.8,	[22, 23, 24, 34, 33]],
"occur:A"
=>[2.4,	[17, 18, 19, 8, 9]],
"occur:R"
=>[2.4,	[27, 28, 29, 19, 39]],
"asis:Water"
=>[4.2,	[26, 25, 16, 15, 14]],
"first:B"
=>[2,	[36, 37, 35]],
"first:IN"
=>[1.6,	[32, 33, 31, 34]],
"asis:Tree"
=>[3.4,	[16, 15, 14, 26, 25]],
"asis:Hand"
=>[3.6,	[4, 14, 15, 5]],
"occur:SBL"
=>[2.2,	[34, 35, 36, 37]],
"all:L|B|InS*"
=>[2.2,	[21, 11, 10]],
"asis:Heart"
=>[3.2,	[13, 12, 3, 2]],
"occur:SAL"
=>[1.8,	[12, 2, 1]],
"asis:Sun"
=>[3.2,	[11, 12, 21, 1]],
"asis:Grass"
=>[3.4,	[6, 5, 7, 8]],
"asis:Gold"
=>[3.4,	[20, 21, 30, 31]],
"asis:Bamboo"
=>[2.6,	[7, 8, 6]],
"asis:Fire"
=>[2.6,	[30, 31, 20]],
"asis:Power"
=>[3.4,	[39, 29, 28, 19]],
"occur:SAB"
=>[1.4,	[32, 33]],
"occur:SA"
=>[1.4,	[37, 38, 39]],
"occur:S"
=>[1.8,	[38, 37, 39]],
"firsttwo:L|IN"
=>[1.6,	[31, 32]],
"asis:Jade"
=>[4.6,	[10, 11, 0, 1, 2]],
"asis:Mountain"
=>[2.9,	[0, 1, 10]],
"occur:SLR"
=>[1.4,	[38, 37, 39]],
"asis:Foot"
=>[3,	[0, 1, 2]],
"asis:Boat"
=>[3,	[0, 1, 2]],
"occur:SAR"
=>[1.2,	[9, 8]],
"occur:SL"
=>[1.4,	[38, 37]],
"occur:SB"
=>[1.4,	[38, 37]],
);
our %POSTOWIN = ();
for (my $i = 0; $i < 40; $i++) {
  $POSTOWIN{$KAZE_ORDER[$i] - 1} = $i;
}

my %PUBDIC_TANKANJI = ();
my %KAZE_TANKANJI = ();
my %SKK_TANKANJI = ();
my %PREDEF_TANKANJI = ();
my %PREDEF_PAGE_SET = ();
my %ONKUN = ();
my %TANKANJI = ();
my %ITAIJI = ();
my %HINDO = ();
my %JOYO = ();
my %BUSHU = ();
my %STROKE = ();
my %BUSHUINFO = ();
my %KHAIRETSU = ();
my %YHAIRETSU = ();
my %PREDEF_PREF = ();
my %YOMI_IGNORE = ();
my %WORD = ();
my %NEWWORD = ();
my %YOMI_TO_KANJI = ();
my %YOMI_TO_SKK_KANJI = ();
my %YOMI_HINDO = ();
my %KAZE_YTOK = ();


our @BUSHUANALORDER = ("occur", "occur2", "first", "firsttwo", "set", "all");
my %BUSHUANAL = 
  ("asis"  => {},
   "or" => {},
   "occur" => {},
   "occur2" => {},
   "set" => {},
   "firsttwo" => {},
   "all" => {},
   "first" => {},
   );
our %YOMISUU = ();

my %_S2E = ();

# Tankanji which is not in SKK & PUBDIC
# 9C5A:彁 E499:苹 E4CA:萍 E54F:薜 EA48:鶇
#9C5A:彁: か
#E499:苹: ひょう びょう へい ほう
#E4CA:萍: うきくさ びょう へい
#E54F:薜: へい
#EA48:鶇: つ つぐみ とう
#&extract_kaze_tankanji($KAZE_REA, $KAZE_DIC);
#%TMP = ();
#foreach $k ("\x9C\x5A", "\xE4\x99", "\xE4\xCA", "\xE5\x4F", "\xEA\x48") {
#  $TMP{$k} = $KAZE_TANKANJI{$k}
#}
#&dump_tankanji(\%TMP);

# Tankanji which is not in Kaze
# E450:膠 EA9F:堯 EAA0:槇 EAA1:遙 EAA2:瑤 EAA3:凜 EAA4:熙
#E450:膠: こう にかわ
#EA9F:堯: ぎょう
#EAA0:槇: まき
#EAA1:遙: はる はるか よう
#EAA2:瑤: よう
#EAA3:凜: りん
#EAA4:熙: き ひろし
#foreach my $file (@PUBDIC) {
#  &extract_pubdic_tankanji($file);
#}
#foreach my $file (@SKKDIC) {
#  &extract_skk_tankanji($file, \%SKK_TANKANJI);
#}
#&merge_tankanji(\%SKK_TANKANJI, \%PUBDIC_TANKANJI);
#foreach $k ("\xE4\x50", "\xEA\x9F", "\xEA\xA0", "\xEA\xA1", "\xEA\xA2", "\xEA\xA3", "\xEA\xA4") {
#  $TMP{$k} = $TANKANJI{$k}
#}
#&dump_tankanji(\%TMP);
#exit(0);

if ($DEBUG) {
  &extract_joyokanji;
  &extract_bushu_info;
  &extract_bushu;
  &extract_onkun;
  &extract_itaiji;
  &extract_kaze_tankanji($KAZE_REA, $KAZE_DIC);
  &extract_yomi_ignore;
  $IGNORE_YOMI = 1;
#  &extract_pubdic_tankanji("$PUBDIC_DIR/h.p");
  &extract_predef_tankanji($PREDEF_TANKANJI_TXT, \%PREDEF_TANKANJI);
  foreach my $file (@SKKDIC) {
    &extract_skk_tankanji($file, \%SKK_TANKANJI);
  }
  $IGNORE_YOMI = 0;
  &extract_skk_tankanji($SKK_AFTER_IGNORE, \%SKK_TANKANJI);
  &merge_tankanji(\%SKK_TANKANJI, \%PUBDIC_TANKANJI);
#  &diff_tankanji("Kaze", \%KAZE_TANKANJI, "SKK", \%SKK_TANKANJI);
#  &dump_tankanji(\%PUBDIC_TANKANJI);
#  &dump_tankanji(\%SKK_TANKANJI);
#  &dump_tankanji(\%TANKANJI);
#  &dump_kaze_tankanji;
#  &check_order_tankanji(\%KAZE_TANKANJI);
} else {
  &extract_joyokanji;
  &extract_bushu_info;
  &extract_bushu;
  &extract_onkun;
  &extract_itaiji;
  &extract_predef_tankanji;
  &extract_kaze_tankanji($KAZE_REA, $KAZE_DIC);
  &extract_yomi_ignore;
  #$IGNORE_YOMI = 1;
  $IGNORE_YOMI = 0;
  foreach my $file (@PUBDIC) {
    &extract_pubdic_tankanji($file);
  }
  foreach my $file (@SKKDIC) {
    &extract_skk_tankanji($file, \%SKK_TANKANJI);
  }
  
  $IGNORE_YOMI = 0;
  &extract_skk_tankanji($SKK_AFTER_IGNORE, \%SKK_TANKANJI);
  &check_skk_tankanji(\%SKK_TANKANJI);
  &merge_tankanji(\%SKK_TANKANJI, \%PUBDIC_TANKANJI);
  &merge_tankanji_ignore_okuri(\%ONKUN);
  &merge_kaze_tankanji();
  &complement_itaiji(\%TANKANJI);
  foreach my $file (@PUBDIC) {
    &extract_pubdic_yomi_hindo($file);
  }
# &remove_but_joyo(\%TANKANJI);
  #&make_hairetsu(\%TANKANJI);
  #&make_hairetsu_with_bushu_info(\%TANKANJI);
  &make_yomi_to_kanji();
  &make_kaze_ytok();
  &check_kaze_tankanji();
  #&make_hairetsu_with_bushu_info_2(\%TANKANJI);
  &make_hairetsu_with_bushu_info_3(\%TANKANJI);
  #&swap_yhairetsu_by_yomi_hindo();
  &swap_yhairetsu_by_yomi_hindo_2();
#  foreach my $file (@PUBDIC) {
#    &extract_pubdic_word($file, \%WORD);
#  }
#  foreach my $file (@SKKDIC) {
#    &extract_skk_word($file, \%WORD);
#  }
#  %NEWWORD = %{&extract_new_words(\%WORD, \%TANKANJI)};
#  &dump_dic(\%NEWWORD);
#  &diff_tankanji("Kaze", \%KAZE_TANKANJI, "PUBDIC", \%PUBDIC_TANKANJI);
#  &diff_tankanji("Kaze", \%KAZE_TANKANJI, "SKK", \%SKK_TANKANJI);
#  &diff_tankanji("Kaze", \%KAZE_TANKANJI, "SKK&PUBDIC", \%TANKANJI);
#  &diff_tankanji("PUBDIC", \%PUBDIC_TANKANJI, "SKK", \%SKK_TANKANJI);
#  &diff_tankanji("TANKANJI", \%TANKANJI, "ONKUN", \%ONKUN);
#  &check_order_tankanji(\%TANKANJI);
#  &check_order_tankanji_x0213(\%TANKANJI);
#  &check_order_tankanji_x0213(\%ONKUN);
#  &check_order_tankanji_x0213(\%BUSHU);
#  &check_order_symbols_x0213(\%PREDEF_TANKANJI);
#  &dump_hindo(\%TANKANJI);
#  &dump_khairetsu();
#  &dump_yhairetsu();
  &dump_yhairetsu_with_bushu_info();
#  &dump_kaze_tankanji;
#  &analyze_hairetsu();
#  &analyze_bushu(\%TANKANJI);
#  &check_bushu_pref();
#  &dump_bushu_info;
}

sub strtohex {
  my ($str) = @_;

# return unpack("H*", $str));
  return join("", map {sprintf("\\x%X", $_)} unpack("C*", $str));
}

# copyref doesn't work well.
sub copyref {
  my ($ref, $refs) = @_;
  $refs = {} if ! defined $refs;
  if ($ref =~ /^SCALAR\(.*\)$/) {
    my $var;
    $var = $$ref;
    return \$var;
  }
  if ($ref =~ /^HASH\(.*\)$/) {
    my $tbl = {};
    my ($key, $value);
    $refs->{$ref} = $tbl;
    foreach $key (keys %{$ref}) {
      $value = $ref->{$key};
      if (exists $refs->{$value}) {
	$tbl->{$key} = $refs->{$value};
      } else {
	$tbl->{$key} = &copyref($value, $refs);
      }
    }
    return $tbl;
  }
  if ($ref =~ /^ARRAY\(.*\)$/) {
    my $array = [];
    $refs->{$ref} = $array;
    foreach my $a (@{$ref}) {
      if (exists $refs->{$a}) {
	push(@{$array}, $refs->{$a});
      } else {
	push(@{$array}, &copyref($a, $refs));
      }
    }
    return $array;
  }
  return $ref;
}

sub postowin {
  my ($pos) = @_;
  my ($page, $loc);
  $pos--;
  $loc = $POSTOWIN{$pos % 40};
  $page = int($pos /= 40) + 1;
  return ($page, $loc);
}

sub sjistoeuc_new {
  my ($rstr) = @_;

  $rstr =~ s{
	      ([\x81-\x9f\xe0-\xfc][\x40-\x7e\x80-\xfc]|[\xa1-\xdf])
	  }{
	    my $str = $1;

	    my ($c1,$c2);

	    if (length($str)==1) {
	      $c1 = unpack('C',$str);

	      pack('CC',0x8e,$c1);

	    } else {

	      ($c1,$c2)=unpack('CC',$str);

	      if ($c2 >= 0x9f) {

                $c2 += 2;

                if ($c1 >= 0xf0) {

		  if ($c1 <= 0xf4) {
		    $c1 =
		      (0xa8,0xa4,0xac,0xae,0xee)
		      [$c1-0xf0];
		  } else {
		    $c1 = ($c1*2-0xfa)&0xff;
		  }

		  "\x8f".pack('CC',$c1,$c2);

                } else {

		  $c1 =
		    $c1*2-
		    ($c1>=0xe0?0xe0:0x60);

		  pack('CC',$c1,$c2);
                }

	      } else {

                $c2 += 0x60+($c2<0x7f);

                if ($c1>=0xf0) {

		  if ($c1<=0xf4) {
		    $c1=
		      (0xa1,0xa3,0xa5,0xad,0xaf)
		      [$c1-0xf0];
		  } else {
		    $c1=($c1*2-0xfb)&0xff;
		  }

		  "\x8f".pack('CC',$c1,$c2);

                } else {

		  $c1=
		    $c1*2-
		    ($c1>=0xe0?0xe1:0x61);

		  pack('CC',$c1,$c2);
                }
	      }
	    }

	  }gex;

  return $rstr;
}

sub sjistoeuc_old {
  my ($rstr) = @_;
  $rstr =~ s(
	     ($SJIS_C|$SJIS_KANA)
	     )
    {
      my $str = $1;
      unless ($_S2E{$1}){
	my ($c1, $c2);
	if (length($str) == 1) {
	  $c1 = unpack('C', $str);
	} else {
	  ($c1, $c2) = unpack('CC', $str);
	}
	if (0xa1 <= $c1 && $c1 <= 0xdf) {
	  $c2 = $c1;
	  $c1 = 0x8e;
	  $_S2E{$str} = pack('CC', $c1, $c2);
	} elsif ($c2 >= 0x9f) {
	  $c2 += 2;
	  if ($c1 >= 0xf0) {
	    if ($c1 <= 0xf4) {
	      $c1 = (0xa8, 0xa4, 0xac, 0xae, 0xee)[$c1 - 0xf0];
	    } else {
	      $c1 = $c1 * 2 - 0xfa;
	    }
	    if ($c1 > 0xff) {
	      die "c1: $c1";
	    }
	    $_S2E{$str} = "\x8f" . pack('CC', $c1, $c2);
	  } else {
	    $c1 = $c1 * 2 - ($c1 >= 0xe0 ? 0xe0 : 0x60);
	    $_S2E{$str} = pack('CC', $c1, $c2);
	  }
	} else {
	  $c2 += 0x60 + ($c2 < 0x7f);
	  if ($c1 >= 0xf0) {
	    if ($c1 <= 0xf4) {
	      $c1 = (0xa1, 0xa3, 0xa5, 0xad, 0xaf)[$c1 - 0xf0];
	    } else {
	      $c1 = $c1 * 2 - 0xfb;
	    }
	    $_S2E{$str} = "\x8f" . pack('CC', $c1, $c2);
	  } else {
	    $c1 = $c1 * 2 - ($c1 >= 0xe0 ? 0xe1 : 0x61);
	    $_S2E{$str} = pack('CC', $c1, $c2);
	  }
	}
      }
      $_S2E{$str};
    }geox;

  return $rstr;
}

sub sjistoeuc {
  my ($s) = @_;
  my $r1 = sjistoeuc_old($s);
  my $r2 = sjistoeuc_new($s);
  if ($r1 ne $r2) {
    die "$r1 ne $r2";
  }
  return $r1;
}

sub translit {
  my ($str, $tbl) = @_;
  my $max = $tbl->{"MAX"};
  my ($l, $c);
  my $r = "";
  while ($str) {
    $l = length($str);
    $l = $max if $max < $l;
    while ($l > 0) {
      $c = substr($str, 0, $l);
      if (exists $tbl->{$l} && exists $tbl->{$l}->{$c}) {
	$r .= $tbl->{$l}->{$c};
	$str = substr($str, $l);
	last;
      } else {
	$l--;
      }
    }
    if ($l == 0) {
      if ($str =~ /^$KANJI/o) {
	$str = "$'";
	$r .= $&;
      } else {
	$r .= substr($str, 0, 1);
	$str = substr($str, 1);
      }
    }
  }
  return $r;
}

sub k2h {
  my ($str) = @_;
  return translit(translit(translit($str, \%K2R), \%R2HK), \%HK2H);
}

sub charlength {
  my ($kanji) = @_;
  my ($l) = length($kanji);
  my ($r) = 0;
  while ($l) {
    $r++;
    if ($kanji =~ /^$KANJI/) {
      $l -= length($&);
      $kanji = "$'";
    } else {
      $l--;
      $kanji = substr($kanji, 1);
    }
  }
  return $r;
}

sub splittochars {
  my ($kanji) = @_;
  my ($l) = length($kanji);
  my (@r) = ();
  while ($l) {
    if ($kanji =~ /^$KANJI/o) {
      push(@r, $&);
      $l -= length($&);
      $kanji = "$'";
    } else {
      push(@r, substr($kanji, 0, 1));
      $l--;
      $kanji = substr($kanji, 1);
    }
  }
  return @r;
}

sub firstdiv2 {
  my $l = shift;
  return [$l - 1, 1];
}

sub nextdiv2 {
  my ($l, $r) = @{$_[0]};
  return undef if $l == 1;
  return [$l - 1, $r + 1];
}

sub setdiv {
  my ($y, $k) = @_;
  my ($r) = {};
  $r->{"k"} = $k;
  return undef if $k > $y;
  if ($k >= 2) {
    $r->{"div"} = &firstdiv2($y);
    $r->{"ch"} = &setdiv($r->{"div"}->[0], $k - 1);
    return $r;
  }
  return undef;
}

sub nextdiv {
  my ($r) = @_;
  my ($k) = $r->{"k"};
  if ($k == 2) {
    my ($cur) = $r->{"div"};
    $r->{"div"} = &nextdiv2($r->{"div"});
    return $cur;
  }
  return undef if ! defined $r->{"ch"};
  my $chcur = &nextdiv($r->{"ch"});
  if (defined $chcur) {
    return [@{$chcur}, $r->{"div"}->[1]];
  } else {
    $r->{"div"} = &nextdiv2($r->{"div"});
    $r->{"ch"} = undef;
    if (defined $r->{"div"}) {
      $r->{"ch"} = &setdiv($r->{"div"}->[0], $k - 1);
      return &nextdiv($r);
    }
  }
  return undef;
}

sub set_kanji_div {
  my ($kanji, $yomi) = @_;
  my ($r) = {};
  my (@k, @y, %hira);
  @k = &splittochars($kanji);
  @y = &splittochars($yomi);
  $r->{"kanji"} = [@k];
  $r->{"yomi"} = [@y];
  if (@k <= @y) {
    $r->{"div"} = &setdiv(scalar(@y), scalar(@k));
    for (my $i = 0; $i < @k; $i++) {
      if ($k[$i] =~ /^$HIRAGANA$/o) {
	$hira{$i} = $k[$i];
      } elsif ($k[$i] =~ /^$KATAKANA$/o) {
	$hira{$i} = &k2h($k[$i]);
      }
    }
    $r->{"hira"} = \%hira;
  }
  return $r;
}

sub next_kanji_div {
  my ($r) = @_;
  my @kanji = @{$r->{"kanji"}};
  my @yomi = @{$r->{"yomi"}};

  return undef if exists $r->{"end"};
  if (! exists $r->{"div"}) {
    $r->{"end"} = 1;
#    return [[join("", @kanji), join("", @yomi)]];
    return undef;
  }

  NKD: while (! exists $r->{"end"}) {
    my ($div) = &nextdiv($r->{"div"});
    if (! defined $div) {
      $r->{"end"} = 1;
      return undef;
    }
    my @r = ();
    my @y = @yomi;
    for (my $i = 0; $i < @{$div}; $i++) {
      push(@r, join("", splice(@y, 0, $div->[$i])));
    }
    foreach my $i (keys %{$r->{"hira"}}) {
      next NKD if $r[$i] ne $r->{"kanji"}->[$i];
    }
    foreach (my $i = 0; $i < @r; $i++) {
      $r[$i] = [$kanji[$i], $r[$i]];
    }
    return [@r];
  }
  return undef;
}

sub remove_okuri {
  my ($kanji, $yomi) = @_;
  return ($kanji, $yomi) if $kanji !~ /$HIRAGANA/o;

  my @k;
  my @y;
  @k = &splittochars($kanji);
  @y = &splittochars($yomi);
  
  my $l = 0;
  for ($l = 0; $l < @k && $l < @y; $l++) {
    last if $y[@y - $l - 1] ne $k[@k - $l - 1];
  }
  @k = splice(@k, 0, @k - $l);
  @y = splice(@y, 0, @y - $l);
  return (join("", @k), join("", @y));
}

sub remove_hira {
  my ($kanji, $yomi) = @_;
  return ($kanji, $yomi) if $kanji !~ /$HIRAGANA/o;

  my @k;
  my @y;
  @k = &splittochars($kanji);
  @y = &splittochars($yomi);
  
  my $l = 0;
  for ($l = 0; $l < @k && $l < @y; $l++) {
    last if $y[@y - $l - 1] ne $k[@k - $l - 1];
  }
  @k = splice(@k, 0, @k - $l);
  @y = splice(@y, 0, @y - $l);

  $l = 0;
  for ($l = 0; $l < @k && $l < @y; $l++) {
    last if $y[$l] ne $k[$l];
  }
  @k = splice(@k, $l);
  @y = splice(@y, $l);
  return (join("", @k), join("", @y));
}

sub seion_first {
  my ($y) = @_;
  if (exists $DAKUON{substr($y, 0, 2)}) {
    $y = $DAKUON{substr($y, 0, 2)} . substr($y, 2);
  }
  return $y;
}

sub extract_new_word {
  my ($new, $words, $kanji, $yomi, $ok, $oy) = @_;

#  ($kanji, $yomi) = &remove_hira($kanji, $yomi);
  return if $kanji eq "" || $kanji eq $yomi;
  return if $kanji =~ /^(?:$KATAKANA|$HIRAGANA)+$/o;
  return if $kanji !~ /^$KANJI+$/o;
  return if $yomi !~ /^$HIRAGANA+$/o;
  return if $kanji =~ /^$KANJI_IGNORE_PAT$/o;
  $ok = $kanji if ! defined $ok;
  $oy = $yomi if ! defined $oy;

  my $dinfo = &set_kanji_div($kanji, $yomi);
  my $div = &next_kanji_div($dinfo);
  if (! defined $div) {
    return if exists $words->{$kanji} && 
      (exists $words->{$kanji}->{$yomi}
       || exists $words->{$kanji}->{seion_first($yomi)});
    print STDERR "new $kanji $yomi $ok $oy\n";
    $words->{$kanji} = {} if ! exists $words->{$kanji};
    $words->{$kanji}->{$yomi} = 1;
    $new->{$kanji} = {} if ! exists $new->{$kanji};
    $new->{$kanji}->{$yomi} = 1;
    return;
  }
  my %new = ();
  do {
    my $nw = "";
    my $ny = "";
    my $resolved;
    $resolved = 1;
    for (my $i = 0; $i < @{$div}; $i++) {
      my ($k, $y) = @{$div->[$i]};
      if (exists $dinfo->{"hira"}->{$i} || 
	  (exists $words->{$k} &&
	   exists $words->{$k}->{$y})) {
	if ($nw ne "") {
	  if (! (exists $words->{$nw} && 
		 (exists $words->{$nw}->{$ny}
		  || exists $words->{$kanji}->{seion_first($yomi)})) ) {
	    $new{$nw} = {} if ! exists $new{$nw};
	    $new{$nw}->{$ny} = 1;
	    $resolved = 0;
	  }
	  $nw = $ny = "";
	}
      } else {
	$nw .= $k;
	$ny .= $y;
      }
    }
    if ($nw ne "") {
      if (! (exists $words->{$nw} && 
	     (exists $words->{$kanji}->{$yomi}
	      || exists $words->{$kanji}->{seion_first($yomi)})) ) {
	$new{$nw} = {} if ! exists $new{$nw};
	$new{$nw}->{$ny} = 1;
	$resolved = 0;
      }
      $nw = $ny = "";
    }
    return if $resolved;
  } while (defined ($div = &next_kanji_div($dinfo)));

  if (exists $new{$kanji}) {
    $new->{$kanji} = $new{$kanji};
    print STDERR "new2 $kanji $yomi $ok $oy\n";
    return;
  }
  foreach my $nw (keys %new) {
    foreach my $ny (keys %{$new{$nw}}) {
      ($nw, $ny) = &remove_hira($nw, $ny);
      &extract_new_word($new, $words, $nw, $ny, $ok, $oy);
    }
  }
  return;
}

sub extract_pubdic_tankanji {
  my ($file) = @_;
  my ($htbl) = \%HINDO;
  my ($orig, $nookuri, $okuri, $newyomi);

  open(DIC, $file) or die;
  binmode(DIC);
  while (<DIC>) {
    chomp;
    $orig = $_;
    next if /^\s*\#/;
    my ($yomi, $kanji, $hinshi, $hindo, @rest) = split;
    die "Illegal code $file: $yomi, $kanji, $hinshi, $hindo\n" if @rest;
    warn "Illegal yomi $yomi $kanji " . strtohex($yomi) . "in $file\n" if ($yomi !~ /^$HIRAGANA+$/o);
    $hindo = 0 if ! defined $hindo;
    $hindo++;
    $hindo = $HINDO_CUTOFF if $hindo > $HINDO_CUTOFF;
    #$hindo = 1 if $kanji =~ /^$TRUEKANJI$/; # 単漢字の頻度は何かおかしいので使わない。
    if ($hindo > 0) { 
      my $word = $kanji;

      $word =~ s($KANJI){
	if ($& =~ /^$TRUEKANJI$/) {
	  my ($tankanji) = $&;
	  $htbl->{$tankanji} = [] if ! exists $htbl->{$tankanji};
	  push(@{$htbl->{$tankanji}}, $hindo);
	}
      }eogx;
    }
    $nookuri = $kanji;
    $okuri = undef;
    $okuri = $2 if $nookuri =~ s/([^\x8f\x8e])($HIRAGANA+)$/$1/o;
    $newyomi = $yomi;
    if (defined $okuri && $okuri ne "" && $okuri ne $newyomi) {
      if (substr($newyomi, -length($okuri)) eq $okuri) {
	$newyomi = substr($newyomi, 0, length($newyomi) - length($okuri));
      } else {
	warn "Illegal okuri $yomi $okuri $kanji in $file\n";
	$nookuri = $kanji;
	$okuri = undef;
      }
    }
    if ($IGNORE_YOMI) {
      next if (exists $YOMI_IGNORE{$newyomi}
	       && ($YOMI_IGNORE{$newyomi} eq "" ||
		   grep {$nookuri eq $_} @{$YOMI_IGNORE{$newyomi}}));
      next if $newyomi =~ /^$YOMI_IGNORE_PAT$/o;
    }
    if ($nookuri =~ /^$KANJI$/o) {
#      warn "Tankanji $newyomi-$yomi $nookuri $kanji $hinshi $hindo\n";
      $PUBDIC_TANKANJI{$nookuri} = {} if ! exists $PUBDIC_TANKANJI{$nookuri};
      $PUBDIC_TANKANJI{$nookuri}->{$newyomi} = [$yomi, $kanji, $hinshi, $hindo];
    }
  }
  close(DIC) or die;
}

## Gemini さんによる分かち書きの実装。
# ========================================================================
# メイン関数: estimate_wakachigaki
# ========================================================================
# 引数: 
#   $nookuri_euc  - 漢字単語 (EUC-JPバイナリ) 例: "学校", "活発"
#   $newyomi_euc  - 全体の読み (EUC-JPバイナリ) 例: "がっこう", "かっぱつ"
#   $TANKANJI_EUC - 単漢字辞書参照ハッシュ $TANKANJI->{$kanji}->{$yomi} (EUC-JP)
# 戻り値:
#   最善の分割結果の配列参照（失敗時は undef）
# ========================================================================
sub estimate_wakachigaki {
  my ($nookuri_euc, $newyomi_euc, $TANKANJI_EUC) = @_;

  # 1. 文字単位で安全に処理するため、内部で一時的にデコード (フラグ付きUTF-8化)
  my $nookuri = decode('euc-jp', $nookuri_euc);
  my $newyomi = decode('euc-jp', $newyomi_euc);

  my @kanjis = split //, $nookuri;
  return undef if !@kanjis;

  # 暫定のベスト経路を記憶するコンテキスト
  my $best_context = {
		      path        => undef,
		      min_penalty => 999999, # 十分に大きな初期値
		     };

  # 2. スコア制深さ優先探索 (DFS) の開始
  _wakachi_dfs(\@kanjis, 0, $newyomi, [], 0, $best_context, $TANKANJI_EUC);

  # 3. 結果の整形 (EUC-JPバイナリにエンコードし直して返す)
  if (defined $best_context->{path}) {
    my @euc_path;
    foreach my $node (@{$best_context->{path}}) {
      push @euc_path, {
		       kanji => encode('euc-jp', $node->{kanji}),
		       yomi  => encode('euc-jp', $node->{yomi}),
		       type  => $node->{type}, # デバッグ用: 'exact', 'sokuon', 'rendaku', 'fallback'
		      };
    }
    return \@euc_path;
  }

  return undef; 
}

# ========================================================================
# 内部探索関数 (DFS)
# ========================================================================
sub _wakachi_dfs {
  my ($kanjis, $k_idx, $rem_yomi, $current_path, $current_penalty, $best_context, $TANKANJI_EUC) = @_;

  # 【枝切り】すでに暫定の最小ペナルティを超えていたらこれ以上探索しない
  return if $current_penalty >= $best_context->{min_penalty};

  # 【ゴール判定】すべての漢字を消費した場合
  if ($k_idx == scalar @$kanjis) {
    if ($rem_yomi eq '') {	# 読みもぴったり使い切れていれば成功
      $best_context->{min_penalty} = $current_penalty;
      $best_context->{path} = [ map { { %$_ } } @$current_path ]; # ディープコピー
    }
    return;
  }

  my $kanji = $kanjis->[$k_idx];
  my $kanji_euc = encode('euc-jp', $kanji);

  # ==================================================================
  # 【追加】パターン0: ひらがな・カタカナの自己一致 (ペナルティ: 0)
  # ==================================================================
  if ($kanji =~ /^[ぁ-んァ-ヴ]$/) {
    my $match_yomi = $kanji;

    # 読み（$rem_yomi）は通常ひらがななので、カタカナはひらがなに変換する
    $match_yomi =~ tr/ァ-ン/ぁ-ん/;
    $match_yomi =~ s/ヴ/ぶ/; # 「ヴ」の暫定処理（環境に合わせて「う」等に調整してください）

    my $len = length($match_yomi);
    if (index($rem_yomi, $match_yomi) == 0) {
      push @$current_path, { kanji => $kanji, yomi => $match_yomi, type => 'kana' };
      _wakachi_dfs($kanjis, $k_idx + 1, substr($rem_yomi, $len), $current_path, $current_penalty, $best_context, $TANKANJI_EUC);
      pop @$current_path;
      return; # 💡 かな文字として一致した場合は、後ろの漢字辞書引きをスキップして終了
    }
  }

  # 辞書から登録されている読み(EUC)を取得して内部用にデコード
  my @registered_yomis;
  if (exists $TANKANJI_EUC->{$kanji_euc}) {
    @registered_yomis = map { decode('euc-jp', $_) } sort keys %{$TANKANJI_EUC->{$kanji_euc}};
  }

  # ------------------------------------------------------------------
  # パターンA: 辞書にある読みと「完全一致」する場合 (ペナルティ: 0)
  # ------------------------------------------------------------------
  foreach my $orig_yomi (@registered_yomis) {
    my $len = length($orig_yomi);
    if (index($rem_yomi, $orig_yomi) == 0) {
      push @$current_path, { kanji => $kanji, yomi => $orig_yomi, type => 'exact' };
      _wakachi_dfs($kanjis, $k_idx + 1, substr($rem_yomi, $len), $current_path, $current_penalty, $best_context, $TANKANJI_EUC);
      pop @$current_path;
    }
  }

  # ------------------------------------------------------------------
  # パターンB: 促音化（末尾の「く・つ・ち」➡「っ」） (ペナルティ: 1)
  # ------------------------------------------------------------------
  foreach my $orig_yomi (@registered_yomis) {
    if ($orig_yomi =~ /^(.*)([くつち])$/) {
      my $sokuon_yomi = $1 . 'っ';
      if (index($rem_yomi, $sokuon_yomi) == 0) {
	push @$current_path, { kanji => $kanji, yomi => $sokuon_yomi, type => 'sokuon' };
	_wakachi_dfs($kanjis, $k_idx + 1, substr($rem_yomi, length($sokuon_yomi)), $current_path, $current_penalty + 1, $best_context, $TANKANJI_EUC);
	pop @$current_path;
      }
    }
  }

  # ------------------------------------------------------------------
  # パターンC: 連濁・半濁音化（先頭の清音化） (ペナルティ: 1)
  # ------------------------------------------------------------------
  my %rendaku_map = (
		     'か'=>'が', 'き'=>'ぎ', 'く'=>'ぐ', 'け'=>'げ', 'こ'=>'ご',
		     'さ'=>'ざ', 'し'=>'じ', 'す'=>'ず', 'せ'=>'ぜ', 'そ'=>'ぞ',
		     'た'=>'だ', 'ち'=>'ぢ', 'つ'=>'づ', 'て'=>'で', 'と'=>'ど',
		     'は'=>'ば', 'ひ'=>'び', 'ふ'=>'ぶ', 'へ'=>'べ', 'ほ'=>'ぼ',
		    );
  foreach my $orig_yomi (@registered_yomis) {
    if ($orig_yomi =~ /^(.)(.*)$/) {
      my ($head, $tail) = ($1, $2);
      my @candidate_heads;

      # 通常の連濁
      push @candidate_heads, $rendaku_map{$head} if exists $rendaku_map{$head};
      # は行の半濁音化救済（例：「活発」の「はつ」➡「ぱつ」）
      push @candidate_heads, 'ぱ' if $head eq 'は';
      push @candidate_heads, 'ぴ' if $head eq 'ひ';
      push @candidate_heads, 'ぷ' if $head eq 'ふ';
      push @candidate_heads, 'ぺ' if $head eq 'へ';
      push @candidate_heads, 'ぽ' if $head eq 'ほ';

      foreach my $h (@candidate_heads) {
	my $rendaku_yomi = $h . $tail;
	if (index($rem_yomi, $rendaku_yomi) == 0) {
	  push @$current_path, { kanji => $kanji, yomi => $rendaku_yomi, type => 'rendaku' };
	  _wakachi_dfs($kanjis, $k_idx + 1, substr($rem_yomi, length($rendaku_yomi)), $current_path, $current_penalty + 1, $best_context, $TANKANJI_EUC);
	  pop @$current_path;
	}
      }
    }
  }

  # ------------------------------------------------------------------
  # パターンD: 強制救済（辞書未登録、または特殊な当て字など） (ペナルティ: 5)
  # ------------------------------------------------------------------
  # これを入れないと、1文字でも辞書にない読みがあると全体が不成立(undef)になります。
  # 残りの読みから1〜4文字を強制的にこの漢字に割り当てて突き進みます。
  my $max_len = length($rem_yomi) < 4 ? length($rem_yomi) : 4;
  for (my $len = 1; $len <= $max_len; $len++) {
    my $fallback_yomi = substr($rem_yomi, 0, $len);
    push @$current_path, { kanji => $kanji, yomi => $fallback_yomi, type => 'fallback' };
    _wakachi_dfs($kanjis, $k_idx + 1, substr($rem_yomi, $len), $current_path, $current_penalty + 5, $best_context, $TANKANJI_EUC);
    pop @$current_path;
  }
}

sub extract_pubdic_yomi_hindo {
  my ($file) = @_;
  my ($orig, $nookuri, $okuri, $newyomi);

  open(DIC, $file) or die;
  binmode(DIC);
  while (<DIC>) {
    chomp;
    $orig = $_;
    next if /^\s*\#/;
    my ($yomi, $kanji, $hinshi, $hindo, @rest) = split;
    die "Illegal code $file: $yomi, $kanji, $hinshi, $hindo\n" if @rest;
    warn "Illegal yomi $yomi $kanji " . strtohex($yomi) . "in $file\n" if ($yomi !~ /^$HIRAGANA+$/o);
    $hindo = 0 if ! defined $hindo;
    $nookuri = $kanji;
    $okuri = undef;
    $okuri = $2 if $nookuri =~ s/([^\x8f\x8e])($HIRAGANA+)$/$1/o;
    $newyomi = $yomi;
    if (defined $okuri && $okuri ne "" && $okuri ne $newyomi) {
      if (substr($newyomi, -length($okuri)) eq $okuri) {
	$newyomi = substr($newyomi, 0, length($newyomi) - length($okuri));
      } else {
	warn "Illegal okuri $yomi $okuri $kanji in $file\n";
	$nookuri = $kanji;
	$okuri = undef;
      }
    }
    $hindo++;
    $hindo = $HINDO_CUTOFF if $hindo > $HINDO_CUTOFF;
    #$hindo = 1 if $kanji =~ /^$TRUEKANJI$/; # 単漢字の頻度は何かおかしいので使わない。
    if ($hindo > 0) {
      my $result = &estimate_wakachigaki($nookuri, $newyomi, \%TANKANJI);
      if ($nookuri =~ /^$TRUEKANJI$/) {
	my ($tankanji) = $&;
	$YOMI_HINDO{$tankanji} = {} if ! exists $YOMI_HINDO{$tankanji};
	$YOMI_HINDO{$tankanji}->{$newyomi} = []
	  if ! exists $YOMI_HINDO{$tankanji}->{$newyomi};
	push(@{$YOMI_HINDO{$tankanji}->{$newyomi}}, $hindo);
      } elsif (defined $result) {
	foreach my $node (@$result) {
	  my $y = $node->{yomi};
	  my $tankanji = $node->{kanji};
	  $YOMI_HINDO{$tankanji} = {} if ! exists $YOMI_HINDO{$tankanji};
	  $YOMI_HINDO{$tankanji}->{$y} = []
	    if ! exists $YOMI_HINDO{$tankanji}->{$y};
	  push(@{$YOMI_HINDO{$tankanji}->{$y}}, $hindo);
	}
      } else {
	warn "NO WAKACHI: $nookuri $newyomi";
	$nookuri =~ s($KANJI){
	  if ($& =~ /^$TRUEKANJI$/) {
	    my ($tankanji) = $&;
	    foreach my $y (sort keys %{$TANKANJI{$tankanji}}) {
	      if (index($newyomi, $y) != -1) {
		$YOMI_HINDO{$tankanji} = {} if ! exists $YOMI_HINDO{$tankanji};
		$YOMI_HINDO{$tankanji}->{$y} = []
		  if ! exists $YOMI_HINDO{$tankanji}->{$y};
		push(@{$YOMI_HINDO{$tankanji}->{$y}}, $hindo);
	      }
	    }
	  }
	}eogx;
      }
    }
  }
  my $ka1 = encode('euc-jp', "菓");
  my $ka2 = encode('euc-jp', "苅");
  my $ka0 = encode('euc-jp', "か");
  my $s1 = join(",", @{$YOMI_HINDO{$ka1}->{$ka0} || \[]});
  my $s2 = join(",", @{$YOMI_HINDO{$ka2}->{$ka0} || \[]});
  # warn "ka: $s1:$s2";

  close(DIC) or die;
}

sub extract_skk_tankanji {
  my ($file, $tbl) = @_;
  my ($yomi, $orig, $nookuri, $okuri, $newyomi);
  my (@kanji);
  my $ytok = \%YOMI_TO_SKK_KANJI;
  open(DIC, $file) or die;
  binmode(DIC);
  while (<DIC>) {
    chomp;
    next if /^\s*(?:\z|\;)/;
    $orig = $_;
    $_ =~ /\s+/;
    $yomi = $`;
    $_ = "$'";
    @kanji = split("/", $_);
    map {s/(.)[\;].+$/$1/} @kanji;
    $yomi =~ s/^>($HIRAGANA)/$1/o;
    $yomi =~ s/($HIRAGANA)>/$1/o;
    $yomi =~ s/^($HIRAGANA)+[a-z]$/$1/o;
    if ($yomi ne "#") {
      while ($yomi =~ s/\#//) {
	map {s/\#[0-9]//} @kanji;
      }
    }

    my $chars = encode("euc-jp", "、。：「」／？！＋＜＞→←↑↓ヴ");
    if ($yomi !~ /^(($HIRAGANA|[\x20-\x7e${chars}])+)$/) {
      die "xYOMI: \"$yomi\"";
    }
    #if ($yomi =~ /^([\x20-\x7e]+)$/) {
    #  warn "yYOMI: \"$yomi\"";
    #}

#    warn "Illegal yomi $yomi $kanji " . strtohex($yomi) . "in $file\n" if ($yomi !~ /^$HIRAGANA+$/o);
    foreach my $kanji (@kanji) {
      $nookuri = $kanji;
      $okuri = undef;
      $okuri = $2 if $nookuri =~ s/([^\x8f\x8e])($OKURI+)$/$1/o;
      $newyomi = $yomi;
      if (defined $okuri && $okuri ne "" && $okuri ne $newyomi) {
	if (substr($newyomi, -length($okuri)) eq $okuri) {
	  $newyomi = substr($newyomi, 0, length($newyomi) - length($okuri));
	} else {
	  if ($yomi =~ /^$HIRAGANA+$/ && $nookuri ne "") {
	    warn "Illegal okuri $yomi-$nookuri-$okuri-$kanji in $file\n";
	  }
	  $nookuri = $kanji;
	  $okuri = undef;
	}
      }
      if ($IGNORE_YOMI) {
	next if (exists $YOMI_IGNORE{$newyomi}
		 && ($YOMI_IGNORE{$newyomi} eq "" ||
		     grep {$nookuri eq $_} @{$YOMI_IGNORE{$newyomi}}));
	next if $newyomi =~ /^$YOMI_IGNORE_PAT$/o;
      }
      if ($nookuri =~ /^$KANJI$/o) {
#      warn "Tankanji $newyomi-$yomi $nookuri $kanji $hinshi $hindo\n";
	$tbl->{$nookuri} = {} if ! exists $tbl->{$nookuri};
	$tbl->{$nookuri}->{$newyomi} = [$yomi, $kanji];
      }
      if ($nookuri eq $kanji) {
	$ytok->{$yomi} = [] if ! exists $ytok->{$yomi};
	if (! grep {$_ eq $nookuri} @{$ytok->{$yomi}}) {
	  push(@{$ytok->{$yomi}}, $nookuri);
	}
      }
    }
  }
  close(DIC) or die;
}

sub check_skk_tankanji {
  my ($tbl) = @_;

  for my $kanji (keys %$tbl) {
    for my $yomi (keys %{$tbl->{$kanji}}) {
      if ($yomi =~ /^[\x20-\x7e]+$/) {
	#warn "YOMI: $yomi $kanji";
      }
    }
  }
}

sub extract_yomi_ignore {
  open(TXT, $YOMI_IGNORE_TXT) or die;
  binmode(TXT);
  while (<TXT>) {
    next if /^\s*\;/;
    chomp;
    my ($yomi, $list) = split;
    my @kanji;
    @kanji = split(/\//, $list) if $list;
    map {$_ =~ s/\;.*$//} @kanji;
    if (@kanji) {
      $YOMI_IGNORE{$yomi} = [@kanji];
    } else {
      $YOMI_IGNORE{$yomi} = "";
    }
  }
  close(TXT);
}

sub extract_predef_tankanji {
  my %ytops;
  
  open(TXT, $PREDEF_TANKANJI_TXT) or die;
  binmode(TXT);
  my $mode = 0;
  my ($page, $loc, $pos, $h);
  my @yomi;
  while (<TXT>) {
    next if /^\s*\#\#\#/;
    if ($mode == 0) {
      next if ! /^\#\#?\s*YOMI/;
      $mode = 1;
    }
    chomp;
    if (/^\#\#?\s*YOMI[\:\s]\s*/) {
      @yomi = split(/\|/, "$'");
      foreach my $yomi (@yomi) {
	$YHAIRETSU{$yomi} = [];
      }
      $mode = 2;
      $page = 0;
      next;
    }
    if ($mode == 2) {
      if (/^\#PAGE\s*([01-9]+)/) {
	$page = $1 - 1;
	next;
      } elsif (/^\#\#$/) {
	$mode = 1;
	next;
      } elsif (/^\#/) {
	next;
      }
      $pos = 40 * $page;
      $loc = 0;
      for (my $i = 0; $i < 4; $i++) {
	s([\x00-\x7F]{2}|$KANJI){
	  my $kanji = $&;
	  if ($kanji ne $UNDEF_CODE) {
	    foreach my $yomi (@yomi) {
	      $PREDEF_TANKANJI{$kanji} = {} 
	        if ! defined $PREDEF_TANKANJI{$kanji};
	      $PREDEF_TANKANJI{$kanji}->{$yomi} = 1;
	      $YHAIRETSU{$yomi}->[$pos] = $kanji;

	      $ytops{$yomi}->{$page} = [] if ! exists $ytops{$yomi}->{$page};
	      if (! grep {$_ eq $kanji} @{$ytops{$yomi}->{$page}}) {
		push(@{$ytops{$yomi}->{$page}}, $kanji);
	      }
	      if (! exists $PREDEF_PAGE_SET{$kanji}) {
		$PREDEF_PAGE_SET{$kanji} = $ytops{$yomi}->{$page};
	      }
	    }
	    if (! exists $PREDEF_PREF{$kanji}) {
	      $PREDEF_PREF{$kanji} = [$pos];
	    } else {
	      my $j;
	      for ($j = 0; $j < @{$PREDEF_PREF{$kanji}}; $j++) {
		if ($PREDEF_PREF{$kanji}->[$j] % 40 != $loc) {
		  warn "Multiple relative position: $kanji at $loc, $PREDEF_PREF{$kanji}->[$j].\n";
		}
		last if $PREDEF_PREF{$kanji}->[$j] >= $pos;
	      }
	      splice(@{$PREDEF_PREF{$kanji}}, $j, 0, $pos);
	    }
	  }
	  $loc++;
	  $pos++;
	  $kanji;
	}eogx;
	chomp($_ = <TXT>) if $i != 3;
      }
      $page++;
      next;
    }
    warn "Unreachable code. $_";
  }
  close(TXT);
}

sub extract_kaze_tankanji {
  my ($rea, $dic) = @_;
  my ($pre_size) = 0x50;
  my ($buf);

  open(REA, $rea) or die;
  binmode(REA);
  open(DIC, $dic) or die;
  binmode(DIC);
  seek(REA, $pre_size, SEEK_SET) or die;
  read(REA, $buf, 2 * 4) or die;
  my ($num, $cache, $unknown1, $unknown2) = unpack("S*", $buf);
  seek(REA, $cache * 8 + $unknown1 * 8 + 0x10, SEEK_CUR);
  my ($yomi, $dicaddr, $bytes, $pos, $subpos, $kanji);
  while ($num > 0) {
    $num--;
    read(REA, $buf, 12);
    ($yomi, $dicaddr, $bytes) = unpack("a8SS", $buf);
    $yomi =~ s/\x00+//;
    $yomi = &sjistoeuc($yomi);
    $yomi =~ s/(\x8E[\xB6\xB9\xDC])\x8E\xDF/\_$1/og;
    $yomi = &translit($yomi, \%HK2H);
    seek(DIC, $pre_size + $dicaddr, SEEK_SET);
    read(DIC, $buf, $bytes);
    while (length($buf) > 0) {
      ($pos, $buf) = unpack("Ca*", $buf);
      if ($pos == 0xFF) {
	($subpos, $buf) = unpack("Ca*", $buf);
	if ($subpos >= 0x81) {
	  $buf = pack("C", $subpos) . $buf;
	} else {
	  $pos += $subpos;
	}
      }
      ($kanji, $buf) = unpack("a2a*", $buf);
      $kanji = &sjistoeuc($kanji);
      $KAZE_TANKANJI{$kanji} = {} if ! exists $KAZE_TANKANJI{$kanji};
      $KAZE_TANKANJI{$kanji}->{$yomi} = $pos;
    }
  }
  close(DIC);
  close(REA);
}

sub extract_joyokanji {
  my ($file) = $JOYOKANJI;
  open(DIC, $file) or die;
  binmode(DIC);
  <DIC>;
  <DIC>;
  <DIC>;
  while (<DIC>) {
    my ($kanji, $gakunen, $kakusuu, $yomi) = split("\t");
    $kanji = &sjistoeuc($kanji);
    if ($gakunen =~ /^\x82([\x4F-\x58])/) {
      $gakunen = unpack("C", $1) - 0x4F;
    } else {
      $gakunen = 0;
    }
    $JOYO{$kanji} = $gakunen;
    my ($hindo) = 127;
    $hindo = 255 - ($gakunen - 1) * 8 if $gakunen;
    $HINDO{$kanji} = [] if ! exists $HINDO{$kanji};
    #push(@{$HINDO{$kanji}}, $hindo);
  }
  close(DIC);

  my %newjoyo = ();
  $file = $JOYOKANJI_2010;
  open(DIC, $file) or die;
  binmode(DIC);
  while (<DIC>) {
    my ($ekanji, $gakunen) = split;
    if ($gakunen !~ /^[1-6DS]$/) {
      die "$file: Parse Error!";
    }
    #next if $gakunen eq "D";
    $gakunen = 0 if $gakunen eq "D" or $gakunen eq "S";
    if (! exists $JOYO{$ekanji}) {
      #warn "New JOYO: $ekanji $gakunen\n";
    } elsif ($JOYO{$ekanji} != $gakunen) {
      #warn "JOYO changed: $ekanji $JOYO{$ekanji} -> $gakunen\n";
    }
    $newjoyo{$ekanji} = $gakunen;
  }
  close(DIC);
  foreach my $kanji (sort keys %JOYO) {
    if (! exists $newjoyo{$kanji}) {
      #warn "Old JOYO: $kanji $JOYO{$kanji}\n";
    }
  }
  if ($USE_NEW_JOYO) {
    %JOYO = ();
    %JOYO = %newjoyo;
  }
}

sub extract_bushu {
  my $bushuname = $BUSHUNAME_TXT;
  my $radical = $RADICAL_TXT;
  my $plural = $PLURAL_TXT;
  if (! exists $BUSHUINFO{1}) {
    open(TXT, $bushuname);
    binmode(TXT);
    while (<TXT>) {
      if (/^[0-9]/) {
	my ($rad, $st, $pos, @yomi) = split;
	my ($name) = grep(/^[a-zA-Z0-9]+$/, @yomi);
	$pos =~ s/\|\(.*\)//g;
	$BUSHUINFO{$rad} = {
	  "name" => $name,
	  "stroke" => $st,
	  "pos" => [split(/\|/, $pos)],
	  "num" => 0,
	  "max" => 0,
	  "sum" => 0,
	  "minalloc" => 0,
	  "yomi" => {},
#	  "category" => undef,
	}
      }
    }
    close(TXT);
  }
  
  open(TXT, $radical) or die "$radical: $!";
  binmode(TXT);
  while (<TXT>) {
    if (/^[0-9]/) {
      my ($rad, $st, $kanji, @rest) = split;
      $kanji = &sjistoeuc($kanji);
      $BUSHU{$kanji} = [$rad];
      my $k = decode('euc-jp', $kanji);
      #warn "OK!" if ($k eq "出");
      $STROKE{$kanji} = $st + $BUSHUINFO{$rad}->{"stroke"};
      $BUSHUINFO{$rad}->{"num"}++;
    }
  }
  close(TXT);

  open(TXT, $plural) or die;
  binmode(TXT);
  while (<TXT>) {
    my (undef, undef, $kanji, $rad1, $st1, $rad2, $st2) = split(",");
    next if ! defined $kanji;
    next if $kanji !~ s/^\(//;
    next if $kanji !~ s/\)$//;
    $kanji = &sjistoeuc($kanji);
    $BUSHU{$kanji} = [$rad1, $rad2];
  }
  close(TXT);
}

sub extract_bushu_info {
  open(TXT, $BUSHUINFO_TXT);
  binmode(TXT);
  while (<TXT>) {
    next if /^\s*\#/;
    my ($name, $rad, $st, $pos, $num, $max, $sum, $minalloc, $cat) = split;
    $BUSHUINFO{$rad} = {
      "name" => $name,
      "stroke" => $st,
      "pos" => [split(/\|/, $pos)],
      "num" => $num,
      "max" => $max,
      "sum" => $sum,
      "minalloc" => $minalloc,
      "yomi" => {},
      "category" => $cat,
    }
  }
  close(TXT);
}

sub extract_onkun {
  my $file = $ONKUN_TXT;
  open(TXT, $file) or die;
  binmode(TXT);
  while (<TXT>) {
    chomp;
    $_ = &sjistoeuc($_);
    if (/^($KATAKANA+)\xa1\xa1/o) {
      my $yomi = &k2h($1);
      $_ = "\xa1\xa1$'";
      while (/\xa1\xa1($KANJI)/og) {
	my $kanji = $1;
	$ONKUN{$kanji} = {} if ! exists $ONKUN{$kanji};
	$ONKUN{$kanji}->{$yomi} = 1;
      }
    }
  }
  close(TXT);
}

sub extract_itaiji {
  my $file = $ITAIJI_TXT;
  open(TXT, $file) or die;
  binmode(TXT);
  <TXT>;
  <TXT>;
  while (<TXT>) {
    chomp;
    my (@l) = ();
    foreach my $k (split(",", $_)) {
      if ($k =~ /^\((.+)\)$/o) {
	push(@l, &sjistoeuc($1));
	#push(@l, $1);
      }
    }
    foreach my $k (@l) {
      $ITAIJI{$k} = [grep {$k ne $_} @l] if ! exists $ITAIJI{$k};
    }
  }
  close(TXT);
}

sub extract_pubdic_word {
  my ($file, $tbl) = @_;
  my ($orig, $nookuri, $okuri, $newyomi);
  
  open(DIC, $file) or die;
  binmode(DIC);
  while (<DIC>) {
    chomp;
    $orig = $_;
    next if /^\s*\#/;
    my ($yomi, $kanji, $hinshi, $hindo, @rest) = split;
    die "Illegal code $file: $yomi, $kanji, $hinshi, $hindo\n" if @rest;
    warn "Illegal yomi $yomi $kanji " . strtohex($yomi) . "in $file\n" if ($yomi !~ /^$HIRAGANA+$/o);
    ($nookuri, $newyomi) = &remove_hira($kanji, $yomi);
    if ($IGNORE_YOMI) {
      next if (exists $YOMI_IGNORE{$newyomi}
	       && ($YOMI_IGNORE{$newyomi} eq "" ||
		   grep {$nookuri eq $_} @{$YOMI_IGNORE{$newyomi}}));
      next if $newyomi =~ /^$YOMI_IGNORE_PAT$/o;
    }
    $tbl->{$nookuri} = {} if ! exists $tbl->{$nookuri};
    $tbl->{$nookuri}->{$newyomi} = 1;
  }
  close(DIC) or die;
}

sub extract_skk_word {
  my ($file, $tbl) = @_;
  my ($yomi, $orig, $nookuri, $okuri, $newyomi);
  my (@kanji);
  open(DIC, $file) or die;
  binmode(DIC);
  while (<DIC>) {
    chomp;
    next if /^\s*(?:\z|\;)/;
    $orig = $_;
    $_ =~ /\s+/;
    $yomi = $`;
    $_ = "$'";
    @kanji = split("/", $_);
    map {s/(.)[\;].+$/$1/} @kanji;
    $yomi =~ s/^($HIRAGANA+)[a-z]$/$1/o;
    $yomi =~ s/^>($HIRAGANA)/$1/o;
    $yomi =~ s/($HIRAGANA)>/$1/o;
    if ($yomi ne "#") {
      while ($yomi =~ s/\#//) {
	map {s/\#[0-9]//} @kanji;
      }
    }
    
    foreach my $kanji (@kanji) {
      ($nookuri, $newyomi) = &remove_hira($kanji, $yomi);
      if ($IGNORE_YOMI) {
	next if (exists $YOMI_IGNORE{$newyomi}
		 && ($YOMI_IGNORE{$newyomi} eq "" ||
		     grep {$nookuri eq $_} @{$YOMI_IGNORE{$newyomi}}));
	next if $newyomi =~ /^$YOMI_IGNORE_PAT$/o;
      }
      $tbl->{$nookuri} = {} if ! exists $tbl->{$nookuri};
      $tbl->{$nookuri}->{$newyomi} = [$yomi, $kanji];
    }
  }
  close(DIC) or die;
}

sub extract_new_words {
  my ($words, $tankanji) = @_;
  my (%word, %new);
  
  &merge_dic(\%word, $words, $tankanji);

  foreach my $w (keys %{$words}) {
    foreach my $y (keys %{$words->{$w}}) {
      &extract_new_word(\%new, \%word, $w, $y);
    }
  }
  return \%new;
}

sub merge_dic {
  my ($dest) = shift;
  foreach my $tbl (@_) {
    foreach my $kanji (keys %{$tbl}) {
      $dest->{$kanji} = {} if ! exists $dest->{$kanji};
      foreach my $yomi (keys %{$tbl->{$kanji}}) {
	$dest->{$kanji}->{$yomi} = 1;
      }
    }
  }
}

sub merge_tankanji {
  &merge_dic(\%TANKANJI, @_);
}

sub merge_tankanji_ignore_okuri {
  foreach my $tbl (@_) {
    foreach my $kanji (sort keys %{$tbl}) {
      $TANKANJI{$kanji} = {} if ! exists $TANKANJI{$kanji};
      foreach my $yomi (sort {length($a) <=> length($b)} 
			(sort keys %{$tbl->{$kanji}})) {
	next if grep {substr($yomi, 0, length($_)) eq $_
				&& substr($yomi, length($_)) =~ /^$TRUEOKURI$/o}  
	                    (sort keys %{$TANKANJI{$kanji}});
	$TANKANJI{$kanji}->{$yomi} = 1;
      }
    }
  }
}

sub complement_itaiji {
  my ($tbl) = @_;
  foreach my $k (sort keys %ITAIJI) {
    if (! exists $tbl->{$k}) {
      my $new = undef;
      foreach my $i (@{$ITAIJI{$k}}) {
	if (exists $tbl->{$i}) {
	  $new = $tbl->{$i} if ! defined $new || (keys %{$new}) > (keys %{$tbl->{$i}});
	}
      }
      $tbl->{$k} = $new if defined $new;
    }
  }
}

sub sum {
  my ($r) = 0;
  $r += shift while (@_);
  return $r;
}

sub max {
  my ($r) = 0;
  my ($i);
  while (@_) {
    $i = shift;
    $r = $i if $r < $i;
  }
  return $r;
}

sub compare_tankanji_hindo_max {
  my ($a, $b) = @_;
  my ($A, $B) = (0, 0);
  if (exists $HINDO{$a}) {
    $A = &max(@{$HINDO{$a}});
  }
  if (exists $HINDO{$b}) {
    $B = &max(@{$HINDO{$b}});
  }
  return $A <=> $B;
}

sub compare_tankanji_hindo_sum {
  my ($a, $b) = @_;
  my ($A, $B) = (0, 0);
  if (exists $HINDO{$a}) {
    $A = &sum(@{$HINDO{$a}});
  }
  if (exists $HINDO{$b}) {
    $B = &sum(@{$HINDO{$b}});
  }
  return $A <=> $B;
}

sub compare_tankanji_hindo {
  my ($a, $b) = @_;
  my ($r) = 0;

  if ($r == 0) {
    $r = !!(exists $JOYO{$a}) <=> !!(exists $JOYO{$b});

    if ($r == 0 && exists $JOYO{$a} && exists $JOYO{$b}) {
      my $val_a = (! $JOYO{$a}) ? 100 : $JOYO{$a};
      my $val_b = (! $JOYO{$b}) ? 100 : $JOYO{$b};
      $r = $val_b <=> $val_a;
    }
  }

  #$r = &compare_tankanji_hindo_max($a, $b) if $r == 0;
  $r = &compare_tankanji_hindo_sum($a, $b) if $r == 0;
  if ($r == 0) {
    $r = !!(exists $BUSHU{$a}) <=> !!(exists $BUSHU{$b});
    if ($r == 0 && exists $BUSHU{$a} && exists $BUSHU{$b}) {
      $r = $STROKE{$b} <=> $STROKE{$a};
    }
  }
  if ($r == 0) {
    $r = !!(substr($a, 0, 1) eq "\x8f") <=> !!(substr($b, 0, 1) eq "\x8f");
    if ($r == 0) {
      $r = $b cmp $a;
    }
  }
  return $r;
}

sub make_hairetsu {
  my ($tbl) = @_;
  foreach my $tankanji (sort {&compare_tankanji_hindo($b,$a)} (keys %{$tbl})) {
    my ($pos) = 1;
    foreach my $yomi (keys %{$tbl->{$tankanji}}) {
      next if exists $PREDEF_TANKANJI{$tankanji} && exists $YHAIRETSU{$yomi} 
	&& grep {defined $_ && $_ eq $tankanji} @{$YHAIRETSU{$yomi}};
      $YHAIRETSU{$yomi} = [] if ! exists $YHAIRETSU{$yomi};
      my ($least) = 0;
      while ($least <= @{$YHAIRETSU{$yomi}}) {
	last if ! defined ${$YHAIRETSU{$yomi}}[$least] 
	  || ${$YHAIRETSU{$yomi}}[$least] eq "";
	$least++;
      }
      $least++;
      $pos = $least if $pos < $least;
    }
    $KHAIRETSU{$tankanji} = $pos;
    foreach my $yomi (keys %{$tbl->{$tankanji}}) {
      ${$YHAIRETSU{$yomi}}[$pos - 1] = $tankanji;
    }
  }
}  

sub make_pref_info {
  my ($kanji) = @_;
  my $pinfo = {};
  my @pref = ();
  $pinfo->{"kanji"} = $kanji;

  if (exists $PREDEF_PREF{$kanji}) {
    @pref = @{$PREDEF_PREF{$kanji}};
  } elsif (! defined $BUSHU{$kanji}) {
    my $hex = unpack('H*', $kanji);
    warn "No BUSHU: $hex ($kanji)";
    # die "No BUSHU: $hex ($kanji)";
  } else {
    my (@rad) = @{$BUSHU{$kanji}};
    foreach my $rad (@rad) {
      my $cat = $BUSHUINFO{$rad}->{"category"};
      if (! exists $BUSHU_PREF{$cat}) {
	warn "Unreacheable Code. $cat\n";
	next;
      }
      if (@pref) {
	my (@new, @old);
	foreach my $p (@{$BUSHU_PREF{$cat}->[1]}) {
	  if (grep {$p == $_} @pref) {
	    push(@new, $p);
	  } else {
	    push(@old, $p);
	  }
	}
	foreach my $p (reverse @pref) {
	  if (! (grep {$p == $_} @new) ) {
	    unshift(@old, $p);
	  }
	}
	@pref = (@new, @old);
      } else {
	@pref = @{$BUSHU_PREF{$cat}->[1]};
      }
    }
  }
  @pref = sort {$KAZE_ORDER[$a] <=> $KAZE_ORDER[$b]} (0..39) if ! @pref;
  if (exists $JOYO{$kanji} && ($USE_JOYO_PREF_ALL || $JOYO{$kanji})) {
    my @a = grep {my $a = $_; grep {$a eq $_} @JOYO_PREF} @pref;
    my @b = grep {my $a = $_; ! grep {$a eq $_} @pref} @JOYO_PREF;
    my @c = grep {my $a = $_; ! grep {$a eq $_} @JOYO_PREF} @pref;
    @pref = (@a, @b, @c);
  }
  $pinfo->{"pref"} = \@pref;
  return $pinfo;
}


sub first_pref {
  my ($kanji) = @_;
  my $pinfo = &make_pref_info($kanji);

  return ($pinfo, &next_pref($pinfo));
}

sub next_pref {
  my ($pinfo) = @_;
  my @pref = @{$pinfo->{"pref"}};
  my ($cur, $page);
  if (! exists $pinfo->{"cur"}) {
    $cur = 0;
    $page = 0;
  } else {
    $cur = $pinfo->{"cur"};
    $page = $pinfo->{"page"};
  }
  if ($cur >= @pref) {
    $page++;
    $cur = 0;
  }
  $pinfo->{"cur"} = $cur + 1;
  $pinfo->{"page"} = $page;
  if ($pref[$cur] >= 40) {
    if ($page <= int($pref[$cur]/40)) {
      $page = int($pref[$cur]/40);
      $pinfo->{"page"} = $page;
    }
    return ($page, $pref[$cur] % 40);
  }
  return ($page, $pref[$cur]);
}

sub make_hairetsu_with_bushu_info {
  my ($tbl) = @_;
  foreach my $tankanji (sort {&compare_tankanji_hindo($b,$a)} (keys %{$tbl})) {
    my ($pinfo, $page, $loc) = &first_pref($tankanji);
    my ($ex, $pos);
    do {
      $ex = 0;
      $pos = $page * 40 + $loc;
      foreach my $yomi (keys %{$tbl->{$tankanji}}) {
	next if exists $PREDEF_TANKANJI{$tankanji} 
	  && exists $YHAIRETSU{$yomi} 
	  && grep {defined $_ && $_ eq $tankanji} @{$YHAIRETSU{$yomi}};
	$YHAIRETSU{$yomi} = [] if ! exists $YHAIRETSU{$yomi};
	if (defined $YHAIRETSU{$yomi}[$pos]) {
	  $ex = 1;
	  last;
	}
      }
      ($page, $loc) = &next_pref($pinfo);
    } while ($ex);
    $KHAIRETSU{$tankanji} = $pos;
    if ($pos >= 40 * 20) {
      warn "Too large. $pos $tankanji.\n";
    }
    foreach my $yomi (keys %{$tbl->{$tankanji}}) {
      next if exists $PREDEF_TANKANJI{$tankanji} 
        && exists $YHAIRETSU{$yomi} 
        && grep {defined $_ && $_ eq $tankanji} @{$YHAIRETSU{$yomi}};
      ${$YHAIRETSU{$yomi}}[$pos] = $tankanji;
    }
  }
}

sub make_yomi_to_kanji {
  foreach my $kanji (sort keys %TANKANJI) {
    foreach my $yomi (sort keys %{$TANKANJI{$kanji}}) {
      $YOMI_TO_KANJI{$yomi} = [] if ! exists $YOMI_TO_KANJI{$yomi};
      if (grep {$_ eq $kanji} @{$YOMI_TO_KANJI{$yomi}}) {
	next;
      }
      push(@{$YOMI_TO_KANJI{$yomi}}, $kanji);
    }
  }
}

sub yomi_sort {
  my (@a) = @_;
  return sort {length($a) <=> length($b)} (sort @a);
}

sub pos_score {
  my ($prefs) = @_;
  my $r = 0;
  foreach my $x (@$prefs) {
    my ($y, $z) = @$x;
    $r += $z;
  }
  return $r;
}

sub make_hairetsu_with_bushu_info_2 {
  my ($tbl) = @_;
  my %ytok;
  #my $pinfo = &make_pref_info(encode('euc-jp', "科"));
  #die join(",", @{$pinfo->{pref}});
  foreach my $kanji (sort {&compare_tankanji_hindo($b,$a)} (sort keys %{$tbl})) {
    foreach my $yomi (yomi_sort(keys %{$tbl->{$kanji}})){
      $ytok{$yomi} = [] if ! exists $ytok{$yomi};
      next if grep {$_ eq $kanji} @{$ytok{$yomi}};
      push(@{$ytok{$yomi}}, $kanji);
    }
  }
	
  foreach my $tankanji (sort {&compare_tankanji_hindo($b,$a)} (sort keys %{$tbl})) {
    if (exists $PREDEF_PAGE_SET{$tankanji}) {
      foreach my $yomi (yomi_sort(keys %{$tbl->{$tankanji}})) {
	$YHAIRETSU{$yomi} = [] if ! exists $YHAIRETSU{$yomi};
	if (exists $YHAIRETSU{$yomi}
	    && grep {defined $_ && $_ eq $tankanji} @{$YHAIRETSU{$yomi}}) {
	  next;
	}
	my @kanjis;
	@kanjis = @{$ytok{$yomi}} if exists $ytok{$yomi};
	@kanjis = grep {my $a = $_; grep {$_ eq $a} @kanjis} @{$PREDEF_PAGE_SET{$tankanji}};
	my $page;
	for ($page = 0; ; $page++) {
	  my $done2 = 1;
	  foreach my $kanji (@kanjis) {
	    my @pref = @{$PREDEF_PREF{$kanji}};
	    my $pref = $pref[0] % 40;
	    if (defined $YHAIRETSU{$yomi}->[$page * 40 + $pref] &&
		$YHAIRETSU{$yomi}->[$page * 40 + $pref] ne $kanji) {
	      $done2 = 0;
	      last;
	    }
	  }
	  last if $done2;
	  if ($page > 40) {
	    die "Too Large Page!: $yomi $tankanji";
	  }
	}
	foreach my $kanji (@kanjis) {
	  my @pref = @{$PREDEF_PREF{$kanji}};
	  my $pref = $pref[0] % 40;
	  $YHAIRETSU{$yomi}->[$page * 40 + $pref] = $kanji;
	}
      }
    } else {
      my $ukanji = decode('euc-jp', $tankanji);
      next if ($ukanji =~ /^[ぁ-んァ-ヴ０１-９]$/);

      my $pinfo = &make_pref_info($tankanji);
      my %pospref;
      foreach my $pos (@{$pinfo->{pref}}) {
	foreach my $yomi (yomi_sort(keys %{$tbl->{$tankanji}})) {
	  $YHAIRETSU{$yomi} = [] if ! exists $YHAIRETSU{$yomi};
	  for (my $page = 0; ; $page++) {
	    if (defined $YHAIRETSU{$yomi}->[$page * 40 + $pos]
		&& $YHAIRETSU{$yomi}->[$page * 40 + $pos] ne $tankanji) {
	      next;
	    }

	    $pospref{$pos} = [] if ! exists $pospref{$pos};
	    push(@{$pospref{$pos}}, [$yomi, $page]);
	    last;
	  }
	}
      }
      my @a = sort {pos_score($pospref{$a}) <=> pos_score($pospref{$b})} @{$pinfo->{pref}};
      if ($ukanji eq "科") {
      #  die join(",", @{$pinfo->{pref}}) . ":" . join(",", map {pos_score($pospref{$_})} @{$pinfo->{pref}}) . ":" . join(",", @a);
      }
      my $truepos = $a[0];
      foreach my $x (@{$pospref{$truepos}}) {
	my ($yomi, $page) = @$x;
	$YHAIRETSU{$yomi}->[$page * 40 + $truepos] = $tankanji;
      }
    }
  }
}


sub make_hairetsu_with_bushu_info_3 {
  my ($tbl) = @_;
  my %ytok;

  #my $pinfo = &make_pref_info(encode('euc-jp', "科"));
  #die join(",", @{$pinfo->{pref}});
  foreach my $kanji (sort {&compare_tankanji_hindo($b,$a)} (sort keys %{$tbl})) {
    foreach my $yomi (yomi_sort(keys %{$tbl->{$kanji}})){
      $ytok{$yomi} = [] if ! exists $ytok{$yomi};
      next if grep {$_ eq $kanji} @{$ytok{$yomi}};
      push(@{$ytok{$yomi}}, $kanji);
    }
  }
	
  foreach my $tankanji (sort {&compare_tankanji_hindo($b,$a)} (sort keys %{$tbl})) {
    if (exists $PREDEF_PAGE_SET{$tankanji}) {
      foreach my $yomi (yomi_sort(keys %{$tbl->{$tankanji}})) {
	$YHAIRETSU{$yomi} = [] if ! exists $YHAIRETSU{$yomi};
	if (exists $YHAIRETSU{$yomi}
	    && grep {defined $_ && $_ eq $tankanji} @{$YHAIRETSU{$yomi}}) {
	  next;
	}
	my @kanjis;
	@kanjis = @{$ytok{$yomi}} if exists $ytok{$yomi};
	@kanjis = grep {my $a = $_; grep {$_ eq $a} @kanjis} @{$PREDEF_PAGE_SET{$tankanji}};
	my $page;
	for ($page = 0; ; $page++) {
	  my $done2 = 1;
	  foreach my $kanji (@kanjis) {
	    my @pref = @{$PREDEF_PREF{$kanji}};
	    my $pref = $pref[0] % 40;
	    if (defined $YHAIRETSU{$yomi}->[$page * 40 + $pref] &&
		$YHAIRETSU{$yomi}->[$page * 40 + $pref] ne $kanji) {
	      $done2 = 0;
	      last;
	    }
	  }
	  last if $done2;
	  if ($page > 40) {
	    die "Too Large Page!: $yomi $tankanji";
	  }
	}
	foreach my $kanji (@kanjis) {
	  my @pref = @{$PREDEF_PREF{$kanji}};
	  my $pref = $pref[0] % 40;
	  $YHAIRETSU{$yomi}->[$page * 40 + $pref] = $kanji;
	}
      }
    } else {
      next if ($tankanji =~ /^\xad[\xf0-\xfc]$/);
      my $ukanji = decode('euc-jp', $tankanji);
      next if ($ukanji =~ /^[ぁ-んァ-ヴ０１-９]$/);
      next if ! exists $KAZE_TANKANJI{$tankanji};

      my $pinfo = &make_pref_info($tankanji);
      my %pospref;
      foreach my $pos (@{$pinfo->{pref}}) {
	my @a = sort keys %{$KAZE_TANKANJI{$tankanji}};
	my @b = sort keys %{$tbl->{$tankanji}};
	my @c = grep {my $a = $_; grep {$a eq $_} @a} @b;
	foreach my $yomi (yomi_sort(@c)) {
	  $YHAIRETSU{$yomi} = [] if ! exists $YHAIRETSU{$yomi};
	  for (my $page = 0; ; $page++) {
	    if (defined $YHAIRETSU{$yomi}->[$page * 40 + $pos]
		&& $YHAIRETSU{$yomi}->[$page * 40 + $pos] ne $tankanji) {
	      next;
	    }

	    $pospref{$pos} = [] if ! exists $pospref{$pos};
	    push(@{$pospref{$pos}}, [$yomi, $page]);
	    last;
	  }
	}
      }
      my @a = sort {pos_score($pospref{$a}) <=> pos_score($pospref{$b})} @{$pinfo->{pref}};
      if ($ukanji eq "科") {
	#  die join(",", @{$pinfo->{pref}}) . ":" . join(",", map {pos_score($pospref{$_})} @{$pinfo->{pref}}) . ":" . join(",", @a);
      }
      my $truepos = $a[0];
      foreach my $x (@{$pospref{$truepos}}) {
	my ($yomi, $page) = @$x;
	$YHAIRETSU{$yomi}->[$page * 40 + $truepos] = $tankanji;
      }
    }
  }

  foreach my $tankanji (sort {&compare_tankanji_hindo($b,$a)} (sort keys %{$tbl})) {
    if (exists $PREDEF_PAGE_SET{$tankanji}) {
      #pass
    } else {
      next if ($tankanji =~ /^\xad[\xf0-\xfc]$/);
      my $ukanji = decode('euc-jp', $tankanji);
      next if ($ukanji =~ /^[ぁ-んァ-ヴ０１-９]$/);

      if (exists $KAZE_TANKANJI{$tankanji}) {
	my @a = sort keys %{$KAZE_TANKANJI{$tankanji}};
	my @b = sort keys %{$tbl->{$tankanji}};
	my @c = grep {my $a = $_; grep {$a eq $_} @a} @b;
	my @y = yomi_sort(@c);
	if (@y) {
	  my $yomi0 = $y[0];
	  my $pos;
	  for (my $i = 0; $i < @{$YHAIRETSU{$yomi0}}; $i++) {
	    if (defined $YHAIRETSU{$yomi0}->[$i] && $YHAIRETSU{$yomi0}->[$i] eq $tankanji) {
	      $pos = $i % 40;
	      last;
	    }
	  }
	  if (! defined $pos) {
	    die "Unreachable Code!. $yomi0 $tankanji " . join(",", @{$YHAIRETSU{$yomi0}});
	  }
	  foreach my $yomi (yomi_sort(keys %{$tbl->{$tankanji}})) {
	    $YHAIRETSU{$yomi} = [] if ! exists $YHAIRETSU{$yomi};
	    my $done = 0;
	    for (my $i = 0; $i < @{$YHAIRETSU{$yomi}}; $i++) {
	      if (defined $YHAIRETSU{$yomi}->[$i]
		  && $YHAIRETSU{$yomi}->[$i] eq $tankanji) {
		$done = 1;
		last;
	      }
	    }
	    next if $done;

	    for (my $page = 0; ; $page++) {
	      if (defined $YHAIRETSU{$yomi}->[$page * 40 + $pos]
		  && $YHAIRETSU{$yomi}->[$page * 40 + $pos] ne $tankanji) {
		next;
	      }
	      $YHAIRETSU{$yomi}->[$page * 40 + $pos] = $tankanji;
	      last;
	    }
	  }
	  next;
	}
      }

      my $pinfo = &make_pref_info($tankanji);
      my %pospref;
      foreach my $pos (@{$pinfo->{pref}}) {
	foreach my $yomi (yomi_sort(keys %{$tbl->{$tankanji}})) {
	  $YHAIRETSU{$yomi} = [] if ! exists $YHAIRETSU{$yomi};
	  for (my $page = 0; ; $page++) {
	    if (defined $YHAIRETSU{$yomi}->[$page * 40 + $pos]
		&& $YHAIRETSU{$yomi}->[$page * 40 + $pos] ne $tankanji) {
	      next;
	    }

	    $pospref{$pos} = [] if ! exists $pospref{$pos};
	    push(@{$pospref{$pos}}, [$yomi, $page]);
	    last;
	  }
	}
      }
      my @a = sort {pos_score($pospref{$a}) <=> pos_score($pospref{$b})} @{$pinfo->{pref}};
      if ($ukanji eq "科") {
      #  die join(",", @{$pinfo->{pref}}) . ":" . join(",", map {pos_score($pospref{$_})} @{$pinfo->{pref}}) . ":" . join(",", @a);
      }
      my $truepos = $a[0];
      foreach my $x (@{$pospref{$truepos}}) {
	my ($yomi, $page) = @$x;
	$YHAIRETSU{$yomi}->[$page * 40 + $truepos] = $tankanji;
      }
    }
  }
}

sub make_kaze_ytok {
  my %ytok;
  foreach my $kanji (sort keys %KAZE_TANKANJI) {
    foreach my $yomi (sort keys %{$KAZE_TANKANJI{$kanji}}) {
      $ytok{$yomi} = [] if ! exists $ytok{$yomi};
      my $pos = $KAZE_TANKANJI{$kanji}->{$yomi};
      my $page = int($pos / 40);
      $pos = ($pos % 40);
      #my $score = $page * 40 + $KAZE_ORDER[$pos] - 1;
      if ($yomi eq encode('euc-jp', "へい")
	  && $kanji eq encode('euc-jp', "平")) {
	#warn "hei: $pos";
      }
      my $score = $page * 40 + $pos -1;
      $ytok{$yomi}->[$score] = $kanji;
    }
  }
  %KAZE_YTOK = %ytok;
}

sub check_kaze_tankanji {
  foreach my $kanji (sort keys %KAZE_TANKANJI) {
    if (! exists $TANKANJI{$kanji}) {
      warn "KAZE: No kanji $kanji\n";
      next;
    }
    foreach my $yomi (sort keys %{$KAZE_TANKANJI{$kanji}}) {
      my $uyomi = decode('euc-jp', $yomi);
      if (grep {$uyomi eq $_} (".", "．ぎ", "．ろ", "゛ぎ", "゛ろ",
			      "、", "。", "，", "．", "゛", "゜")) {
	next;
      }
      if (! exists $TANKANJI{$kanji}->{$yomi}) {
	warn "KAZE: No yomi $kanji $yomi\n";
      }
    }
  }
}

sub merge_kaze_tankanji {
  foreach my $kanji (sort keys %KAZE_TANKANJI) {
    if (! exists $TANKANJI{$kanji}) {
      $TANKANJI{$kanji} = {};
    }
    foreach my $yomi (sort keys %{$KAZE_TANKANJI{$kanji}}) {
      my $uyomi = decode('euc-jp', $yomi);
      if (grep {$uyomi eq $_} (".", "．ぎ", "．ろ", "゛ぎ", "゛ろ", "．")){
#			      "、", "。", "，", "゛", "゜")) {
	next;
      }
      if (! exists $TANKANJI{$kanji}->{$yomi}) {
	$TANKANJI{$kanji}->{$yomi} = [$yomi, $kanji];
      }
    }
  }
}

sub score_k {
  my ($yomi, $kanji) = @_;
  return 40 if ! exists $KAZE_YTOK{$yomi};
  my @l = @{$KAZE_YTOK{$yomi}};
  for (my $i = 0; $i < @l && $i < 40; $i++) {
    if (defined $l[$i] && $l[$i] eq $kanji) {
      return $i;
    }
  }
  return 40;
}

sub swap_yhairetsu_by_yomi_hindo {
  #die join(",", grep {defined $_} @{$ytok{encode('euc-jp', "へい")}});

  foreach my $yomi (yomi_sort(keys %YHAIRETSU)) {
    my $uyomi = decode('euc-jp', $yomi);
    next if $uyomi =~ /^[\x20-\x7e]+/ || grep {$uyomi eq $_}
      ("きごう", "かっこ", "まーく", "けいせん", "．ぎ", "．ろ", "「", "」", "、", "。", "，", "．", "゛", "゜");

    for (my $pos = 0; $pos < 40; $pos++) {
      my @a;
      for (my $page = 0; ; $page++) {
	if (! defined $YHAIRETSU{$yomi}->[$page * 40 + $pos]) {
	  last;
	}
	push(@a, $YHAIRETSU{$yomi}->[$page * 40 + $pos]);
      }
      # sub score_k {
      # 	my ($yomi, $kanji) = @_;
      # 	return 40 if ! exists $YOMI_TO_KANJI{$yomi};
      # 	my @l = @{$YOMI_TO_KANJI{$yomi}};
      # 	for (my $i = 0; $i < @l; $i++) {
      # 	  if ($l[$i] eq $kanji) {
      # 	    return $i;
      # 	  }
      # 	}
      # 	return 40;
      # }

      my @b = sort {score_k($yomi, $a) <=> score_k($yomi, $b)} @a;
      my $swaped = 0;
      for (my $i = 0; $i < @a; $i++) {
	if ($a[$i] ne $b[$i]) {
	  $swaped = 1;
	  last;
	}
      }
      if ($swaped) {
	my $x = join("", @a);
	my $y = join("", @b);
	warn "swap $pos $yomi $x $y\n";
      }
      for (my $page = 0; $page < @b; $page++) {
	$YHAIRETSU{$yomi}->[$page * 40 + $pos] = $b[$page];
      }
    }
  }
}

sub score_k2 {
  my ($yomi, $kanji) = @_;
  return 0 if ! exists $YOMI_HINDO{$kanji}
    || ! exists $YOMI_HINDO{$kanji}->{$yomi};
  #return &max(@{$YOMI_HINDO{$kanji}->{$yomi}});
  return &sum(@{$YOMI_HINDO{$kanji}->{$yomi}});
}

sub compare_k2 {
  my ($yomi, $a, $b) = @_;
  my $k1a = score_k($yomi, $a);
  my $k1b = score_k($yomi, $b);
  my $k2a = score_k2($yomi, $a);
  my $k2b = score_k2($yomi, $b);
  my $r = 0;

  $r = (!!$k2b <=> !!$k2a);
  return $r if $r != 0;
  if ($k2a && $k2b) {
    $r = $k2b <=> $k2a;
  }
  return $r if $r != 0;
  return $k1a <=> $k1b;
}

sub swap_yhairetsu_by_yomi_hindo_2 {
  foreach my $yomi (yomi_sort(keys %YHAIRETSU)) {
    my $uyomi = decode('euc-jp', $yomi);
    next if $uyomi =~ /^[\x20-\x7e]+/ || grep {$uyomi eq $_}
      ("きごう", "かっこ", "まーく", "けいせん", "．ぎ", "．ろ", "「", "」", "、", "。", "，", "．", "゛", "゜");

    for (my $pos = 0; $pos < 40; $pos++) {
      my @a;
      for (my $page = 0; ; $page++) {
	if (! defined $YHAIRETSU{$yomi}->[$page * 40 + $pos]) {
	  last;
	}
	push(@a, $YHAIRETSU{$yomi}->[$page * 40 + $pos]);
      }

      my @b = sort {compare_k2($yomi, $a, $b)} @a;
      my $swaped = 0;
      for (my $i = 0; $i < @a; $i++) {
	if ($a[$i] ne $b[$i]) {
	  $swaped = 1;
	  last;
	}
      }
      if ($swaped) {
	my $x = join("", @a);
	my $y = join("", @b);
	warn "swap $pos $yomi $x $y\n";
      }
      for (my $page = 0; $page < @b; $page++) {
	$YHAIRETSU{$yomi}->[$page * 40 + $pos] = $b[$page];
      }
    }
  }
}

sub diff_tankanji {
  my ($IDA, $TMPA, $IDB, $TMPB) = @_;
  my (%A) = %{$TMPA};
  my (%B) = %{$TMPB};

  my (%UNCHECKED) = %A;
  foreach my $tankanji (sort keys %B) {
    next if $tankanji !~ /^$TRUEKANJI$/o;
    if (! exists $A{$tankanji}) {
      print "New Kanji to $IDA: $tankanji\n";
      next;
    }
    my ($t) = $B{$tankanji};
    my ($k) = $A{$tankanji};
    delete $UNCHECKED{$tankanji};
    my (%u) = %{$k};
    foreach my $yomi (sort keys %{$t}) {
      if (exists $k->{$yomi}) {
	delete $u{$yomi};
      } else {
	print "New Yomi to $IDA: $tankanji $yomi\n";
      }
    }
    foreach my $yomi (sort keys %u) {
      print "New Yomi to $IDB: $tankanji $yomi\n";
    }
  }
  foreach my $tankanji (sort keys %UNCHECKED) {
    next if $tankanji !~ /^$TRUEKANJI$/o;
    print "New Kanji to $IDB: $tankanji\n";
  }
}

sub dump_tankanji {
  my ($tbl) = @_;
  foreach my $tankanji (sort keys %{$tbl}) {
    print "$tankanji:";
    foreach my $yomi (sort keys %{$tbl->{$tankanji}}) {
      print " $yomi";
    }
    print "\n";
  }
}

sub dump_dic {
  my ($tbl) = @_;
  foreach my $w (sort keys %{$tbl}) {
    print "$w:\t";
    foreach my $yomi (sort keys %{$tbl->{$w}}) {
      print " $yomi";
    }
    print "\n";
  }
}

sub dump_kaze_tankanji {
  foreach my $tankanji (sort keys %KAZE_TANKANJI) {
    print "$tankanji:";
    my ($pos);
    my (%pos) = ();
    foreach my $yomi (sort keys %{$KAZE_TANKANJI{$tankanji}}) {
      $pos = $KAZE_TANKANJI{$tankanji}->{$yomi};
      $pos{$pos} = [] if ! exists $pos{$pos};
      push(@{$pos{$pos}}, $yomi);
    }
    if ((keys %pos) >= 2) {
      print " multiple";
    }
    foreach my $pos (keys %pos) {
      printf " (%i: %s)", $pos, join(" ", @{$pos{$pos}});
    }
    print "\n";
  }
}

sub dump_hindo {
  my ($tbl) = \%HINDO;
  foreach my $tankanji (sort {&compare_tankanji_hindo($b,$a)} (keys %{$tbl})) {
    print "$tankanji:";
    foreach my $hindo (sort @{$tbl->{$tankanji}}) {
      print " $hindo";
    }
    print "\n";
  }
}

sub dump_khairetsu {
  my ($tbl) = \%KHAIRETSU;
  foreach my $tankanji (sort {&compare_tankanji_hindo($b,$a)} (keys %{$tbl})) {
    print "$tankanji: $tbl->{$tankanji}\n";
  }
}

sub dump_yhairetsu {
  my ($tbl) = \%YHAIRETSU;
  foreach my $yomi (sort keys %{$tbl}) {
    my (@yomi) = @{$tbl->{$yomi}};
    my ($pos) = 1;
    print "#YOMI $yomi\n";
    while (@yomi) {
      my (@y) = splice(@yomi, 0, 40);
      $y[39] = undef if @y < 40;
      my (@page, $page, $loc);
      while (@y) {
	($page, $loc) = &postowin($pos);
	$page[$loc] = shift @y;
	$page[$loc] = $UNDEF_CODE if ! defined $page[$loc];
	$pos++;
      }
      print "#PAGE $page\n";
      while (@page) {
	print join("", splice(@page, 0, 10));
	print "\n";
      }
    }
    print "##\n";
  }
}

sub dump_yhairetsu_with_bushu_info {
  my ($tbl) = \%YHAIRETSU;
  foreach my $yomi (sort keys %{$tbl}) {
    my (@yomi) = @{$tbl->{$yomi}};
    my ($page) = 0;
    print "#YOMI $yomi\n";
    while (@yomi) {
      $page++;
      my (@y) = splice(@yomi, 0, 40);
      for (my $i = 0; $i < 40; $i++) {
	$y[$i] = $UNDEF_CODE if ! exists $y[$i] || ! defined $y[$i];
      }
      print "#PAGE $page\n";
      while (@y) {
	print join("", splice(@y, 0, 10));
	print "\n";
      }
    }
    print "##\n";
  }
}

sub analyze_hairetsu {
  my ($tbl) = \%YHAIRETSU;
  foreach my $yomi (sort {@{$tbl->{$b}} <=> @{$tbl->{$a}}}
		    (keys %{$tbl})) {
    my (@yomi) = @{$tbl->{$yomi}};
    my ($pos) = 1;
    printf "#YOMI %s\n", &translit($yomi, \%H2R);
    while (@yomi) {
      my ($kanji) = shift @yomi;
      if (defined $kanji) {
	my ($sum, $max) = 0;
	if (exists $HINDO{$kanji}) {
	  my (@hindo) = @{$HINDO{$kanji}};
	  $sum = &sum(@hindo);
	  $max = &max(@hindo);
	}
	printf "%3d: $kanji %4d %3d %s\n", $pos, $sum, $max, &strtohex($kanji);
      }
      $pos++;
    }
    print "##\n";
  }
}

sub check_bushu_pref {
  my @page = ();
  foreach my $key (keys %BUSHU_PREF) {
    my $m = $BUSHU_PREF{$key}->[0];
    my (@l) = @{$BUSHU_PREF{$key}->[1]};
    for (my $i = 0; $i < @l; $i++) {
      $page[$l[$i]] = 0 if ! defined $page[$l[$i]];
      $page[$l[$i]] += $m - (($m / @l) * $i);
    }
  }

  while (@page) {
    my @a = splice(@page, 0, 10);
    map {$_ = sprintf("%6.6s", $_)} @a;
    print join(", ", @a) . "\n";
  }
}

sub minalloc {
  my ($y, $yall) = @_;
  return (($y/(int(($yall - 1)/40.0) + 1)) - 1)/5 + 1;
}

sub print_bushu_analysis {
  my ($tag, $tbl) = @_;
  my $sum = 0;

  foreach my $pos (sort {$tbl->{$b}->{"num"} <=> $tbl->{$a}->{"num"}} 
		   (keys %{$tbl})) {
    printf "#$tag\t%s\t%i\t%i\t%s %g\n", $pos, 
      $tbl->{$pos}->{"num"}, $tbl->{$pos}->{"max"}, 
      $tbl->{$pos}->{"minallocyomi"}, $tbl->{$pos}->{"minalloc"};
    $sum += $tbl->{$pos}->{"minalloc"};
    my (@bushu) = @{$tbl->{$pos}->{"rad"}};
    map {$_ = $BUSHUINFO{$_}->{"name"}} @bushu;
    print join(", ", @bushu) . "\n";
  }
  print "##sum Minalloc $sum\n";
  print "\n";
}

sub minalloc_bushu_analysis {
  my ($tag, $tbl) = @_;

  foreach my $pos (sort {$tbl->{$b}->{"num"} <=> $tbl->{$a}->{"num"}} 
		   (keys %{$tbl})) {
    my $ytbl = $tbl->{$pos}->{"yomi"};
    my $minalloc = 0;
    my ($minallocyomi, $max, $maxyomi, $x);
    foreach my $yomi (grep {$ytbl->{$_} > 1}
			   (sort {$ytbl->{$b} <=> $ytbl->{$a}} 
			    (keys %{$ytbl}))) {
      ($max = $ytbl->{$yomi}, $maxyomi = $yomi) if ! defined $maxyomi;
      $x = &minalloc($ytbl->{$yomi}, $YOMISUU{$yomi});
      ($minalloc = $x, $minallocyomi = $yomi) if $minalloc < $x;
    }
    $tbl->{$pos}->{"minallocyomi"} = $minallocyomi;
    $tbl->{$pos}->{"minalloc"} = $minalloc;
  }
}

sub add_bushu_analysis {
  my ($tbl, $ent, $rad) = @_;
  $tbl->{$ent} = {
    "num" => 0,
    "max" => 0,
    "rad" => [],
    "yomi" => {},
  } if ! exists $tbl->{$ent};
  $tbl->{$ent}->{"num"} += $BUSHUINFO{$rad}->{"num"};
  $tbl->{$ent}->{"max"} += $BUSHUINFO{$rad}->{"max"};
  push(@{$tbl->{$ent}->{"rad"}}, $rad);
  
  foreach my $yomi (keys %{$BUSHUINFO{$rad}->{"yomi"}}) {
    $tbl->{$ent}->{"yomi"}->{$yomi} = 0 
      if ! exists $tbl->{$ent}->{"yomi"}->{$yomi};
    $tbl->{$ent}->{"yomi"}->{$yomi} += $BUSHUINFO{$rad}->{"yomi"}->{$yomi};
  }
}

sub remove_bushu_analysis {
  my ($tbl, $rad) = @_;
  foreach my $ent (keys %{$tbl}) {
    if ((grep {$rad == $_} @{$tbl->{$ent}->{"rad"}})) {
      $tbl->{$ent}->{"num"} -= $BUSHUINFO{$rad}->{"num"};
      $tbl->{$ent}->{"max"} -= $BUSHUINFO{$rad}->{"max"};
      @{$tbl->{$ent}->{"rad"}} = (grep {$rad != $_} @{$tbl->{$ent}->{"rad"}});
      foreach my $yomi (keys %{$BUSHUINFO{$rad}->{"yomi"}}) {
	$tbl->{$ent}->{"yomi"}->{$yomi} -= $BUSHUINFO{$rad}->{"yomi"}->{$yomi};
      }
    }
  }
}

sub print_bushu_anal {
  my ($sum, $num, $minalloc) = 0;
  my (%need_rinsetsu) = ();
  my (%result);
  print "\nBushu Categories\n";
  foreach my $cat ("asis", @BUSHUANALORDER) {
    $minalloc = 0;
    if (exists $BUSHUANAL{$cat}) {
      my $tbl = $BUSHUANAL{$cat};
      foreach my $pos (sort {$tbl->{$b}->{"minalloc"} <=> $tbl->{$a}->{"minalloc"}} (keys %{$tbl})) {
	$num++;
	$sum += $tbl->{$pos}->{"minalloc"};
	$minalloc += $tbl->{$pos}->{"minalloc"};
	if (! exists $tbl->{$pos}->{"rad"}) {
	  printf "#$cat\t%s %s %d %g\n", $tbl->{$pos}->{"name"},
	    join("|", @{$tbl->{$pos}->{"pos"}}), $tbl->{$pos}->{"max"},
	    $tbl->{$pos}->{"minalloc"};
	  $result{"$cat:" . $tbl->{$pos}->{"name"}} = {
	    "max" => $tbl->{$pos}->{"max"},
	    "minalloc" => $tbl->{$pos}->{"minalloc"},
	    "first" => [$tbl->{$pos}->{"pos"}->[0]],
	    "occur" => $tbl->{$pos}->{"pos"}
	  }
	} else {
	  my %first = ();
	  my %occur = ();
	  printf "#$cat:%s %d %g\n", $pos, $tbl->{$pos}->{"max"},
	    $tbl->{$pos}->{"minalloc"};
	  foreach my $rad (@{$tbl->{$pos}->{"rad"}}) {
	    printf "#$cat:%s\t%s %s %d %g\n", $pos, 
	      $BUSHUINFO{$rad}->{"name"}, 
	      join("|", @{$BUSHUINFO{$rad}->{"pos"}}), 
	      $BUSHUINFO{$rad}->{"max"},
	      $BUSHUINFO{$rad}->{"minalloc"};
	    $first{$BUSHUINFO{$rad}->{"pos"}->[0]} = 1;
	    foreach my $o (@{$BUSHUINFO{$rad}->{"pos"}}) {
	      $occur{$o} = 1;
	    }
	  }
	  printf "##$cat first %s\n", join(", ", sort (keys %first));
	  foreach my $first (keys %first) {
	    $need_rinsetsu{$first} = {} if ! exists $need_rinsetsu{$first};
	    foreach my $r (keys %first) {
	      $need_rinsetsu{$first}->{$r} = 1 if $first ne $r;
	    }
	  }
	  $result{"$cat:" . $pos} = {
	    "max" => $tbl->{$pos}->{"max"},
	    "minalloc" => $tbl->{$pos}->{"minalloc"},
	    "first" => [sort keys %first],
	    "occur" => [sort keys %occur]
	  }
	}
      }
      print "##$cat sum Minalloc $minalloc\n";
     }
     print "\n";
  }
  print "##sum Minalloc $sum. num $num\n";
  print "##Result\n";
  foreach my $name (sort {$result{$b}->{"max"} <=> $result{$a}->{"max"}}
		    (keys %result)) {
    print "\"$name\"";
    print "\t";
    print "\t" if length($name) + 2 < 8;
    printf "%d\t%g\tfirst=\"%s\" occur=\"%s\"\n", $result{$name}->{"max"},
      $result{$name}->{"minalloc"}, join(", ", @{$result{$name}->{"first"}}),
      join(", ", @{$result{$name}->{"occur"}});;
  }
  print "##Need Rinsetsu\n";
  foreach my $first (sort {(keys %{$need_rinsetsu{$a}})
			     <=> (keys %{$need_rinsetsu{$b}})}
		     (keys %need_rinsetsu)) {
    printf "%s\t%s\n", $first, 
      join(", ", (sort keys %{$need_rinsetsu{$first}}));
  }
  print "\n";
}

sub analyze_bushu {
  my ($tbl) = @_;
  my (%num, %max, %sum);
  my (@pos);
  my (%first, %firsttwo, %all, %set, %occur, %occur2, %or);
  my $sum_num = 0;

  foreach my $kanji (keys %BUSHU) {
    foreach my $rad (@{$BUSHU{$kanji}}) {
      $num{$rad} = 0 if ! exists $num{$rad};
      $num{$rad}++;
      if (exists $HINDO{$kanji}) {
	$max{$rad} = 0 if ! exists $max{$rad};
	$sum{$rad} = 0 if ! exists $sum{$rad};
	$max{$rad} += &max(@{$HINDO{$kanji}});
	$sum{$rad} += &sum(@{$HINDO{$kanji}});
	$BUSHUINFO{$rad}->{"max"} += &max(@{$HINDO{$kanji}});
	$BUSHUINFO{$rad}->{"sum"} += &sum(@{$HINDO{$kanji}});
      }
      if (exists $tbl->{$kanji}) {
	foreach my $yomi (keys %{$tbl->{$kanji}}) {
	  $YOMISUU{$yomi} = 0 if ! exists $YOMISUU{$yomi};
	  $YOMISUU{$yomi}++;
	  my $ytbl = $BUSHUINFO{$rad}->{"yomi"};
	  $ytbl->{$yomi} = 0 if ! exists $ytbl->{$yomi};
	  $ytbl->{$yomi}++;
	}
      }
    }
  }
  print "Bushu Hindo\n";
  foreach my $rad (sort {$max{$b}<=>$max{$a}} (keys %BUSHUINFO)) {
    printf "%16s\t%d\t%4d\t%4d\t%g\t%g\n", $BUSHUINFO{$rad}->{"name"}, 
      $num{$rad}, $max{$rad}, $sum{$rad},
      $max{$rad}/$num{$rad}, $sum{$rad}/$num{$rad};
    $sum_num += $num{$rad};
    @pos = @{$BUSHUINFO{$rad}->{"pos"}};
    my @set = grep {$_ ne "InS*"} @pos;
    if (! (grep {$_ eq "IN"} @set) ) {
      push(@set, "IN");
    }
    my ($f, $ft, $a, $s) = ($pos[0], 
			    join("|", (@pos > 1)? ($pos[0], $pos[1]) : ($pos[0])),
			    join("|", @pos),
			    join("|", sort @set),
			    );
    &add_bushu_analysis(\%first, $f, $rad);
    &add_bushu_analysis(\%firsttwo, $ft, $rad);
    &add_bushu_analysis(\%all, $a, $rad);
    &add_bushu_analysis(\%set, $s, $rad);
    foreach my $o (@pos) {
      my $oo = $o;
      $oo = "IN" if $oo eq "InS*";
      next if $oo eq "IN";
      &add_bushu_analysis(\%occur, $oo, $rad);
    }
    my %visited = ();
    foreach my $o1 (@pos) {
      my $oo1 = $o1;
      $oo1 = "IN" if $oo1 eq "InS*";
      foreach my $o2 (@pos) {
	my $oo2 = $o2;
	$oo2 = "IN" if $oo2 eq "InS*";
	next if $oo1 eq $oo2;
	my $o = join("|", sort ($oo1, $oo2));
	next if $visited{$o};
	$visited{$o} = 1;
	&add_bushu_analysis(\%occur2, $o, $rad);
      }
    }
  }
  printf "%16s\t%d\n\n", "sum", $sum_num;
  print "Yomi Choufuku\n";
  foreach my $rad (sort {(keys %{$BUSHUINFO{$b}->{"yomi"}}) <=> (keys %{$BUSHUINFO{$a}->{"yomi"}})} (keys %BUSHUINFO)) {
    my $name = $BUSHUINFO{$rad}->{"name"};
    my $y = $BUSHUINFO{$rad}->{"yomi"};
    my $minalloc = 0;
    my ($maxyomi, $minallocyomi, $x);
    print "# choufuku $name : ";
    foreach my $yomi (grep {$y->{$_} > 1}
			   (sort {$y->{$b} <=> $y->{$a}} (keys %{$y}))) {
      print "$yomi:$y->{$yomi} ";
      $maxyomi = $y->{$yomi} if ! defined $maxyomi;
      $x = &minalloc($y->{$yomi}, $YOMISUU{$yomi});
      ($minalloc = $x, $minallocyomi = $yomi) if $minalloc < $x;
    }
    print "\n";
    print "Minalloc $minallocyomi $minalloc\n" if $minalloc > 1;
    $BUSHUINFO{$rad}->{"maxyomi"} = $maxyomi;
    $BUSHUINFO{$rad}->{"minalloc"} = $minalloc;
  }
  print "\nBushu Analysis\n";
  &minalloc_bushu_analysis("first", \%first);
  &minalloc_bushu_analysis("firsttwo", \%firsttwo);
  &minalloc_bushu_analysis("all", \%all);
  &minalloc_bushu_analysis("set", \%set);
  &minalloc_bushu_analysis("occur", \%occur);
  &minalloc_bushu_analysis("occur2", \%occur2);

  foreach my $or ("S|SB|SA|SL|SLR", 
		  "IN|SAB") {
    my $pos = join("|", sort split(/\|/, $or));
    foreach my $f (split(/\|/, $pos)) {
      foreach my $rad (@{$first{$f}->{"rad"}}) {
	&add_bushu_analysis(\%or, $pos, $rad);
      }
    }
  }
  &minalloc_bushu_analysis("or", \%or);
  if (0) {
  foreach my $pos (keys %first) {
    $or{$pos} = &copyref($first{$pos}) if $first{$pos}->{"minalloc"} <= 2;
  }
  my $ornum = 1;
  my $changed;
  do {
    $changed = 0;
    my (@del) = ();
    foreach my $pos (keys %or) {
      next if $or{$pos}->{"minalloc"} > 2.5;
      my (@or) = split(/\|/, $pos);
      next if @or < $ornum;
      foreach my $f (keys %first) {
	next if $first{$f}->{"minalloc"} > 2;
	if (! (grep {$f eq $_} @or) ) {
	  my $or = join("|", sort (@or, $f));
	  next if exists $or{$or};
	  $or{$or} = &copyref($or{$pos});
	  push(@del, $or);
	  $changed = 1;
	  foreach my $rad (@{$first{$f}->{"rad"}}) {
	    &add_bushu_analysis(\%or, $or, $rad);
	  }
	}
      }
    }
    foreach my $del (@del) {
      my (@or) = split(/\|/, $del);
      foreach my $i (@or) {
	my $d = join("|", sort (grep {$i ne $_} @or));
	delete $or{$d} if exists $or{$d};
      }
    }
    &minalloc_bushu_analysis("or", \%or);
    $ornum++;
  } while ($changed);
  }
  &print_bushu_analysis("first", \%first);
  &print_bushu_analysis("or", \%or);
  &print_bushu_analysis("firsttwo", \%firsttwo);
  &print_bushu_analysis("all", \%all);
  &print_bushu_analysis("set", \%set);
  &print_bushu_analysis("occur", \%occur);
  &print_bushu_analysis("occur2", \%occur2);

  print "\nBushu Analysis 2\n";
  foreach my $rad (keys %BUSHUINFO) {
    if ($BUSHUINFO{$rad}->{"minalloc"} > 2.5) {
      &remove_bushu_analysis(\%first, $rad);
      &remove_bushu_analysis(\%firsttwo, $rad);
      &remove_bushu_analysis(\%all, $rad);
      &remove_bushu_analysis(\%set, $rad);
      &remove_bushu_analysis(\%occur, $rad);
      $BUSHUANAL{"asis"}->{$rad} = &copyref($BUSHUINFO{$rad});
      $BUSHUINFO{$rad}->{"category"} = "asis:" . $BUSHUINFO{$rad}->{"name"};
    }
  }

  my %cat = ("occur" => [2.5, \%occur],
	     "occur2" => [2.5, \%occur2],
	     "first" => [2.5, \%first],
	     "set" => [2.5, \%set],
	     "firsttwo" => [2.5, \%firsttwo],
	     "all" => [$sum_num, \%all],
	     );
	     
  foreach my $cat (@BUSHUANALORDER) {
    my ($minalloc, $tbl) = @{$cat{$cat}};
    delete $cat{$cat};
    my $removed;
    do {
      $removed = 0;
      foreach my $pos (sort {$tbl->{$a}->{"num"} <=> $tbl->{$b}->{"num"}}
		       (keys %{$tbl})) {
	if ($tbl->{$pos}->{"num"} > 0 
	    && $tbl->{$pos}->{"minalloc"} <= $minalloc) {
	  $BUSHUANAL{$cat}->{$pos} = &copyref($tbl->{$pos});
	  foreach my $rad (@{$BUSHUANAL{$cat}->{$pos}->{"rad"}}) {
	    warn "Unreacheablecode." if exists $BUSHUINFO{$rad}->{"category"};
	    $BUSHUINFO{$rad}->{"category"} = "$cat:$pos";
	    $removed = 1;
	    &remove_bushu_analysis(\%first, $rad);
	    &remove_bushu_analysis(\%firsttwo, $rad);
	    &remove_bushu_analysis(\%all, $rad);
	    &remove_bushu_analysis(\%set, $rad);
	    &remove_bushu_analysis(\%occur, $rad);
	    &remove_bushu_analysis(\%occur2, $rad);
	  }
	  delete $tbl->{$pos};
	}
      }
      &minalloc_bushu_analysis("first", \%first);
      &minalloc_bushu_analysis("firsttwo", \%firsttwo);
      &minalloc_bushu_analysis("all", \%all);
      &minalloc_bushu_analysis("set", \%set);
      &minalloc_bushu_analysis("occur", \%occur);
      &minalloc_bushu_analysis("occur2", \%occur);
    } while ($removed);
    foreach my $c (@BUSHUANALORDER) {
      if (exists $cat{$c}) {
	&print_bushu_analysis($c, $cat{$c}->[1]);
      }
    }
  }
  &print_bushu_anal;
}

sub dump_bushu_info {
  open(OUT, ">$BUSHUINFO_TXT") or die;
  binmode(OUT);
  print OUT "#name\t\trad\tstroke\tpos\t\tnum\tmax\tsum\tminalloc\tcat\n";
  foreach my $rad (sort {$a <=> $b} keys %BUSHUINFO) {
    my $tbl = $BUSHUINFO{$rad};
    print OUT $tbl->{"name"};
    print OUT "\t";
    print OUT "\t" if length($tbl->{"name"}) < 8;
    print OUT "$rad\t";
    printf OUT "%d\t", $tbl->{"stroke"};
    my $pos = join("|", @{$tbl->{"pos"}});
    printf OUT "%s\t", $pos;
    print OUT "\t" if length($pos) < 8;
    printf OUT "%d\t", $tbl->{"num"};
    printf OUT "%d\t", $tbl->{"max"};
    printf OUT "%d\t", $tbl->{"sum"};
    printf OUT "%1.5g\t", $tbl->{"minalloc"};
    printf OUT "%s\n", $tbl->{"category"};
  }
  close(OUT);
}

sub check_order_tankanji {
  my ($tbl) = @_;
  my ($l, $r);
  my ($kanji);
  $l = 0xB0;
  while ($l < 0xF5) {
    $r = 0xA1;
    printf "%02X%02X-%02XFE:", $l, $r, $l;
    while ($r <= 0xFE) {
      last if $l == 0xF4 && $r == 0xF7;
      $kanji = pack("CC", $l, $r);
      if (! exists $tbl->{$kanji}) {
	printf " %02X:%s", $r, $kanji;
      }
      $r++;
    }
    print "\n";
    $l++;
  }
}

sub check_order_tankanji_x0213 {
  my ($tbl) = @_;
  my ($ss3, $l, $r);
  my ($kanji);
  my ($mid, $pr, $fkanji, $pkanji);
  $l = 0xAE;
  $ss3 = 0x00;
  while ($l < 0xFF || $ss3 == 0x00) {
    ($l = 0xA1, $ss3 = 0x8F) if $l == 0xFF;
    $r = 0xA1;
    $mid = $pr = 0x00;
    printf "%02X%02X%02X-%02XFE:", $ss3, $l, $r, $l;
    while ($r <= 0xFE) {
      $kanji = pack("CCC", $ss3, $l, $r) if $ss3;
      $kanji = pack("CC", $l, $r) if ! $ss3;
      if ($kanji =~ /^$NOT_AVAIL$/o) {
	$mid++ if $pr != 0x00;
	$r++;
	next;
      }
      if (! exists $tbl->{$kanji}) {
	if ($pr == 0x00) {
	  $pr = $r;
	  $mid = 0;
	  $fkanji = $kanji;
	} else {
	  $mid++;
	}
	$pkanji = $kanji;
      } else {
	if ($pr != 0x00) {
	  if ($mid == 0) {
	    printf " %02X:%s", $pr, $pkanji;
	  } elsif ($mid == 1) {
	    if ($pkanji =~ /^$NOT_AVAIL$/o) {
	      printf " %02X:%s %02X:UNDEF", $pr, $fkanji, $r - 1;
	    } else {
	      printf " %02X:%s %02X:%s", $pr, $fkanji, $r - 1, $pkanji;
	    }
	  } else {
	    if ($pkanji =~ /^$NOT_AVAIL$/o) {
	      printf " %02X:%s-%02X:UNDEF", $pr, $fkanji, $r - 1;
	    } else {
	      printf " %02X:%s-%02X:%s", $pr, $fkanji, $r - 1, $pkanji;
	    }
	  }
	  $pr = 0x00;
	}
      }
      $r++;
    }
    if ($pr != 0x00) {
      if ($mid == 0) {
	printf " %02X:%s", $pr, $pkanji;
      } elsif ($mid == 1) {
	if ($pkanji =~ /^$NOT_AVAIL$/o) {
	  printf " %02X:%s %02X:UNDEF", $pr, $fkanji, $r - 1;
	} else {
	  printf " %02X:%s %02X:%s", $pr, $fkanji, $r - 1, $pkanji;
	}
      } else {
	if ($pkanji =~ /^$NOT_AVAIL$/o) {
	  printf " %02X:%s-%02X:UNDEF", $pr, $fkanji, $r - 1;
	} else {
	  printf " %02X:%s-%02X:%s", $pr, $fkanji, $r - 1, $pkanji;
	}
      }
    }
    print "\n";
    $l++;
  }
}

sub check_order_symbols_x0213 {
  my ($tbl) = @_;
  my ($ss3, $l, $r);
  my ($kanji);
  my ($mid, $pr, $fkanji, $pkanji);
  $l = 0xA1;
  $ss3 = 0x00;
  while ($l < 0xFF || $ss3 == 0x00) {
    last if $l > 0xad;
    ($l = 0xA1, $ss3 = 0x8F) if $l == 0xFF;
    $r = 0xA1;
    $mid = $pr = 0x00;
    printf "%02X%02X%02X-%02XFE:", $ss3, $l, $r, $l;
    while ($r <= 0xFE) {
      $kanji = pack("CCC", $ss3, $l, $r) if $ss3;
      $kanji = pack("CC", $l, $r) if ! $ss3;
      if ($kanji =~ /^$NOT_AVAIL$/o) {
	$mid++ if $pr != 0x00;
	$r++;
	next;
      }
      if (! exists $tbl->{$kanji}) {
	if ($pr == 0x00) {
	  $pr = $r;
	  $mid = 0;
	  $fkanji = $kanji;
	} else {
	  $mid++;
	}
	$pkanji = $kanji;
      } else {
	if ($pr != 0x00) {
	  if ($mid == 0) {
	    printf " %02X:%s", $pr, $pkanji;
	  } elsif ($mid == 1) {
	    if ($pkanji =~ /^$NOT_AVAIL$/o) {
	      printf " %02X:%s %02X:UNDEF", $pr, $fkanji, $r - 1;
	    } else {
	      printf " %02X:%s %02X:%s", $pr, $fkanji, $r - 1, $pkanji;
	    }
	  } else {
	    if ($pkanji =~ /^$NOT_AVAIL$/o) {
	      printf " %02X:%s-%02X:UNDEF", $pr, $fkanji, $r - 1;
	    } else {
	      printf " %02X:%s-%02X:%s", $pr, $fkanji, $r - 1, $pkanji;
	    }
	  }
	  $pr = 0x00;
	}
      }
      $r++;
    }
    if ($pr != 0x00) {
      if ($mid == 0) {
	printf " %02X:%s", $pr, $pkanji;
      } elsif ($mid == 1) {
	if ($pkanji =~ /^$NOT_AVAIL$/o) {
	  printf " %02X:%s %02X:UNDEF", $pr, $fkanji, $r - 1;
	} else {
	  printf " %02X:%s %02X:%s", $pr, $fkanji, $r - 1, $pkanji;
	}
      } else {
	if ($pkanji =~ /^$NOT_AVAIL$/o) {
	  printf " %02X:%s-%02X:UNDEF", $pr, $fkanji, $r - 1;
	} else {
	  printf " %02X:%s-%02X:%s", $pr, $fkanji, $r - 1, $pkanji;
	}
      }
    }
    print "\n";
    $l++;
  }
}

sub remove_but_joyo {
  my ($tbl) = @_;
  foreach my $k (keys %$tbl) {
    next if ! defined $BUSHU{$k};
    my ($rad) = @{$BUSHU{$k}};
    my ($st) = 1;
    $st = $STROKE{$k} - $BUSHUINFO{$rad}->{stroke} if exists $STROKE{$k};
    delete $tbl->{$k} if ! exists $JOYO{$k} && $st;
    delete $HINDO{$k} if ! exists $JOYO{$k} && $st;
    delete $BUSHU{$k} if ! exists $JOYO{$k} && $st;
  }
}
