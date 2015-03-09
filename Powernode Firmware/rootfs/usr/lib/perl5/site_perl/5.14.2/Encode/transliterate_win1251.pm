#!/usr/bin/perl -w
$VERSION = '1.00';
use strict;
package Encode::transliterate_win1251;

my $debug;

# Assume that FROM are 1-char, and have no REx charclass special characters
my $uc = "ß ÂÅÐÒÛÓÈÎÏØ Ù  ÀÑÄÔÃÕÉÊËÇÜ ÖÆ ÁÍÌÝÞ × ¨Ú";
my $ul = "YAVERTYUIOPSHSCHASDFGHJKLZ''CZHBNMEYUCHE'";

# titlecase and random alternative translations
my $tc = "ß Ø Ù  Æ Þ Þ Þ þ × ×  ×  ÷  ß ß ÿ ß ß ÿ Ù  Ù  ù  ¨ ¨ ¸ ";
my $tl = "YaShSchZhYuIUIuiuChTchTCHtchIAIaiaJAJajaTCHTchtchJOJojo";

# Assume that 1-char parts of TO have no REx charclass special characters

my $lc = "ÿ âåðòûóèîïø ù  àñäôãõéêëçüöæ áíìýþ ÷ ¸ú¹";
my $ll = "yavertyuiopshschasdfghjklz'czhbnmeyuche'N";

sub prepare_translation {
  my ($from, $to) = @_;
  die "Mismatch of length:\nfrom: '$from'\nto:   '$to'\n" unless length($from) == length $to;
  my @from = ($from =~ /(\S\s*)/g);
  my (%hash_from, %hash_to);
  for my $chunk (@from) {
    my $chunk_to = substr($to, 0, length $chunk);
    substr($to, 0, length $chunk) = "";
    $chunk =~ s/\s+$//;
    $hash_from{$chunk} = $chunk_to;
    # Prefer earlier definition for reverse translation
    $hash_to{$chunk_to} = $chunk unless exists $hash_to{$chunk_to};
  }
  (\%hash_from, \%hash_to)
}

sub make_translator {
  my ($hash) = @_;
  die unless keys %$hash;
  my @keys2 =          grep length > 1,  keys %$hash;
  my $keys1 = join '', grep length == 1, keys %$hash;
  my $rex = '';
  $rex .= (join('|', sort {length $b <=> length $a} @keys2) . '|')
    if @keys2;
  $rex .= "[\Q$keys1\E]" if length $keys1;
  warn "rex = '$rex'\n" if $debug;
  eval "sub {s/($rex)/\$hash->{\$1}/g}" or die;
}

sub cyr_table {"$uc$lc$tc"}
sub lat_table {"$ul$ll$tl"}

#my $to = make_translator( (prepare_translation("$uc$lc$tc", "$ul$ll$tl"))[0] );

1;
