package Normalize::Text::Music_Fields;	# Music_Normalize_Fields
$VERSION = '0.02';
use strict;
use Config;
#use utf8;			# Needed for 5.005...

my %tr;
my %short;

sub translate_dots ($) {
  my $a = shift;
  $a =~ s/^\s+//;
  $a =~ s/\s+$//;
  $a =~ s/\s+/ /g;
  $a =~ s/\b(\w)\.\s*/$1 /g;
  $a =~ s/(\w\.)\s*/$1 /g;
  lc $a
}

sub translate_tr ($) {
  my $a = shift;
  $a = $tr{translate_dots $a} or return;
  return $a;
}

sub strip_years ($) {		# strip dates
  my ($a) = (shift);
  my @rest;
  return $a unless $a =~ s/\s+((?:\([-\d,]+\)(\s+|$))+)$//;
  @rest = split /\s+/, $1;
  return $a, @rest;
}

sub strip_duplicate_dates {	# Remove $d[0] if it matches $d_r
  my ($d_r, @d) = @_;
  return unless @d;
  $d_r   = substr $d_r,  1, length($d_r)  - 2; # Parens
  my $dd = substr $d[0], 1, length($d[0]) - 2; # Parens
  my @dates_r = split /,|--|-(?=\d\d\d\d)/, $d_r;
  my @dates   = split /,|--|-(?=\d\d\d\d)/, $dd;
  for my $d (@dates) {
    return @d unless grep /^\Q$d\E(-|$)/, @dates_r;
  }
  return @d[1..$#d];
}

sub __split_person ($) {
  # Non-conflicting ANDs (0x438 is cyrillic "i", word is cyrillic "per")
  split /([,;:]\s+(?:\x{043f}\x{0435}\x{0440}\.\s+)?|\s+(?:[-&\x{0438}ei]|and|et)\s+|\x00)/, shift;
}

sub _translate_person ($$$);
sub _translate_person ($$$) {
  my ($self, $aa, $with_year) = (shift, shift, shift);
  my $fail = ($with_year & 2);
  $with_year &= 1;
  my $ini_a = $aa;
  $aa = $aa->[0] if ref $aa;		# [value, handler]
  $aa =~ s/\s+$//;
  load_lists() unless %tr;
  # Try early fixing:
  my $a1 = translate_tr $aa;
  return ref $ini_a ? [$a1, $ini_a->[1]] : $a1 if $a1 and $with_year;
  my ($a, @date) = strip_years($aa);
  my $tr_a = translate_tr $a;
  if (not defined $tr_a and $a =~ /(.*?)\s*,\s*(.*)/s) { # Schumann, Robert
    $tr_a = translate_tr "$2 $1";
  }
  if (not defined $tr_a) {
    return if $fail;
    my $ini = $aa;
    # Normalize "translated" to "transl."
    # echo "¯¥à¥¢®¤" | perl -wnle 'BEGIN{binmode STDIN, q(encoding(cp866))}printf qq(\\x{%04x}), ord $_ for split //'
    $aa =~ s/(\s\x{043f}\x{0435}\x{0440})\x{0435}\x{0432}\x{043e}\x{0434}\x{0435}?(\s)/$1.$2/g;
    $aa =~ s/(\s+)\x{0432}\s+(?=\x{043f}\x{0435}\x{0440}\.)/;$1/g; # v per. ==> , per.
    $aa =~ s/[,;.]\s+(\x{043f}\x{0435}\x{0440}\.)\s*/; $1 /g; # normalize space, punct
    $aa =~ s/\b(transl)ated\b/$1./g;

    my @parts = __split_person $aa;
    if (@parts <= 1) {		# At least normalize spacing:
      # Add dots after initials
      $aa =~ s/\b(\w)\s+(?=(\w))/
	       ($1 ne lc $1 and $2 ne lc $2) ? "$1." : "$1 " /eg;
      # Separate initials by spaces unless in a group of initials
      $aa =~ s/\b(\w\.)(?!$|[-\s]|\w\.)/$1 /g;
      return ref $ini_a ? [$aa, $ini_a->[1]] : $aa;
    }
    for my $i (0..$#parts) {
      next if $i % 2;		# Separator
      my $val = _translate_person($self, $parts[$i], $with_year | 2); # fail
      # Deal with cases (currently, in Russian only, after "transl.")
      if (not defined $val and $i
	  and $parts[$i-1] =~ /^;\s+\x{043f}\x{0435}\x{0440}\.\s+$/ # per
	  and $parts[$i] =~ /(.*)\x{0430}$/s) {
	$val = _translate_person($self, "$1", $with_year | 2); # fail
      }
      $val ||= _translate_person($self, $parts[$i], $with_year); # cosmetic too
      $parts[$i] = $val if defined $val;
    }
    $tr_a = join '', @parts;
    return $ini_a if $tr_a eq $ini;
    @date = ();			# Already taken into account...
  }
  my ($short, @date_r) = strip_years($tr_a); # Real date
  @date = strip_duplicate_dates($date_r[0], @date) if @date_r == 1 and @date;
  $tr_a = $short unless $with_year;
  $a = join ' ', $tr_a, @date;
  return ref $ini_a ? [$a, $ini_a->[1]] : $a;
}

sub normalize_person ($$) {
  return _translate_person(shift, shift, 1);
}

for my $field (qw(artist artist_collection)) {
  no strict 'refs';
  *{"normalize_$field"} = \&normalize_person;
}

sub short_person ($$);
sub short_person ($$) {
  my ($self, $a) = (shift, shift);
  my $ini_a = $a;
  $a = $a->[0] if ref $a;		# [value, handler]
  $a = _translate_person($self, $a, 0); # Normalize, no dates of life
  $a =~ s/\s+$//;
  ($a, my @date) = strip_years($a);
  my @parts;
  if (exists $short{$a}) {
    $a = $short{$a};
  } elsif (@parts = __split_person $a and @parts > 1) {
    for my $i (0..$#parts) {
      next if $i % 2;		# Separator
      $parts[$i] = short_person($self, $parts[$i]);
    }
    $a = join '', @parts;
  } else {
    # Drop years of life
    shift @date if @date and $date[0] =~ /^\(\d{4}-[-\d,]*\d{4,}[-\d,]*\)$/;
    # Add dots after initials
    $a =~ s/\b(\w)\s+(?=(\w))/
            ($1 ne lc $1 and $2 ne lc $2) ? "$1." : "$1 " /eg;
    # Separate initials by spaces unless in a group of initials
    $a =~ s/\b(\w\.)(?!$|[-\s]|\w\.)/$1 /g;
    my @a = split /\s+/, $a;
    # Skip shorting if there are strange non upcased parts (e.g., "-") or '()')
    my @check = @a;
    my $von = (@a > 2 and $a[-2] =~ /^[a-z]+$/);
    splice @check, $#a - 1, 1 if $von;
    # Ignore mid parts (skip if there are non upcased parts (e.g., "-") or '()')
    unless (grep lc eq $_, @check or @a <= 1 or $a =~ /\(|[,;]\s/) {
      my $i = substr($a[0], 0, 1);
      $a[0] =  "$i." if $a[0] =~ /^\w\w/ and lc($i) ne $i;
      # Keep "from" in L. van Beethoven, M. di Falla, I. von Held, J. du Pre
      @a = @a[0,($von ? -2 : ()),-1];
    }
    $a = join ' ', @a;
  }
  $a = join ' ', $a, @date;
  return ref $ini_a ? [$a, $ini_a->[1]] : $a;
}

my %comp;

sub normalize_file_lines ($$) {	# Normalizing speeds up load_composer()
  my ($self, $fn) = @_;
  open my $f, '<', $fn or die "Can't open file $fn for read";
  local $_;
  print "# normalized\n";
  while (<$f>) {
    next if /^#\s*normalized\s*$/;
    chomp;
    $_ = normalize_piece($self, $_) unless /^\s*#/;
    print "$_\n";
  }
  close $f or die "Can't close file $fn for read";
}

sub _significant ($$$) {	# Try to extract "actual name" of the piece
  my ($tbl, $l, $r) = (shift, shift, shift);
  my ($pre, $opus);
  if ($tbl->{no_opus_no}) {	# Remove year-like comment
    ($pre) = ($l =~ /^(.*\S)\s*\(\d{4}\b[^()]*\)$/s);
  } else {
    ($pre, $opus) = ($l =~ /$r/);
  }
  $pre = $l unless $pre;
  my ($significant) = ($pre =~ /^(.*?\bNo[.]?\s*\d+)/is); # Up to No. NN
  ($significant) = ($pre =~ /^(.*?);/s) unless $significant;
  ($significant) = $pre unless $significant;
  (lc $significant, $opus);
}

my $def_opus_rx = qr/\b(?:Op(?:us\b|\.)|WoO)\s*\d+[a-d]?(?:[.,;\s]\s*No\.\s*\d+(?:\.\d+)*)?/;

sub _read_composer_file ($$*$$) {
  my($self, $f, $fh, $tbl, $aka) = (shift,shift,shift,shift,shift);
  my($normalized, $l, @works, %aka, $opened);
  my $opus_rx = $tbl->{opus_rx} || $def_opus_rx;
  my $opus_pref = $tbl->{opus_prefix} || 'Op.';
  local $/ = "\n";		# allow customization
  if (defined $fh) {
    $f |= "composer's file" . (eval {' for ' . $self->name_for_field_normalization} || '');
  } else {
    open COMP, "< $f" or die "Can't read $f: $!";
    $fh = \*COMP;
    $f = "`$f'";
    $opened = 1;
  }
  while (defined ($l = <$fh>)) {
    next if $l =~ /^\s*(?:##|$)/;
    if ($l =~ /^#\s*normalized\s*$/) {
      $normalized++;	# Very significant optimization (unless mail-header)
    } elsif ($l =~ /^#\s*opus_rex\s(.*?)\s*$/) {
      $opus_rx = $tbl->{opus_rx} = qr/$1/;
    } elsif ($l =~ /^#\s*dup_opus_rex\s(.*?)\s*$/) {
      $tbl->{dup_opus_rx} = qr/$1/;
    } elsif ($l =~ /^#\s*opus_prefix\s(.*?)\s*$/) {
      $opus_pref = $tbl->{opus_prefix} = $1;
    } elsif ($l =~ /^#\s*no_opus_no\s*$/) {
      $tbl->{no_opus_no} = 1;
    } elsif ($l =~ /^#\s*opus_dup\s+(.*?)\s*$/) {
      $tbl->{dup_opus}{lc $1} = 1;
    } elsif ($l =~ /^#\s*prev_aka\s+(.*?)\s*$/) {
      $aka->{$1} = $works[-1];	# recognize also alternative names
    } elsif ($l =~ /^#\s*format\s*=\s*(line|mail-header)\s*$/) {
      $/ = ($1 eq 'line' ? "\n" : '');
    } elsif ($l =~ /^#[^#]/) {
      warn "Unrecognized line of $f: $l"
    } elsif ($l !~ /^##/) {	# Recursive call to ourselves...
      if ($normalized) {
	$l =~ s/\s*$//;		# chomp...
      } elsif ($/) {
	$l = normalize_piece($self, $l);
      } else {
	$l = normalize_piece_mail_header($self, $l, $opus_rx, $opus_pref);
      }
      push @works, $l;
    }
  }
  not $opened or close $fh or die "Error reading $f: $!";
  @works;
}

sub read_composer_file ($$;*) {
  my($self, $f, $fh) = (shift,shift,shift);
  $self = prepare_tag_object_comp($self) unless ref $self;
  _read_composer_file($self, $f, $fh,{},{});
}

my @path;
@path = ("$ENV{HOME}/.music_fields")
  if defined $ENV{HOME} and -d "$ENV{HOME}/.music_fields";
push @path, '-';
@path = split /\Q$Config{path_sep}/, $ENV{MUSIC_FIELDS_PATH}
  if defined $ENV{MUSIC_FIELDS_PATH};

sub set_path {
  @path = @_;
}

(my $myself = __PACKAGE__) =~ s,::,/,g; # 'Normalize/Text/Music_Fields.pm'
my @f = $INC{"$myself.pm"};
warn("panic: can't find myself"), @f = () unless -r $f[0];
s(\.pm$)()i or (@f=(), warn "panic: misformed myself") for @f;

sub get_path () {
  map +($_ eq '-' ? @f : $_), @path;
}

sub load_composer ($$) {
  my ($self, $c) = @_;
  eval {$c = $self->shorten_person($c)};
  my $ini = $c;
  return $comp{$ini} if exists $comp{$ini};
  $c =~ s/[^-\w]/_/g;
  $c =~ s/__/_/g;
  # XXX See Wikipedia "Opus number" for more complete logic
  $comp{$ini}{opus_rx} = $def_opus_rx;
  $comp{$ini}{opus_prefix} = 'Op.';
  my @dirs = get_path();
  my @files = grep -r $_, map "$_/$c.comp", @dirs or return 0;
  my $f = $files[0];
#  $f = $c =~ tr( ¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ\x80-\x9F)
#	  ( !cLXY|S"Ca<__R~o+23'mP.,1o>...?AAAAAAACEEEEIIIIDNOOOOOx0UUUUYpbaaaaaaaceeeeiiiidnooooo:ouuuuyPy_)
#	    unless -r $f;
  #warn "file looked up is $f";
  return $comp{$ini} unless -r $f;
  my $tbl = $comp{$ini};
  my ($normalized);
  my @works = _read_composer_file($self, $f, undef, $tbl, \my %aka);
  return unless @works;
  # Piano Trio No. 8 (Arrangement of the Septet; Op. 20)); Op. 38 (1820--1823)
  # so can't m/.*?/
  my $r = qr/^(.*($tbl->{opus_rx}))/s;
  # Name "as in Wikipedia:Naming conventions (pieces of music)"
  my (%opus, %name, %dup, %dupop);
  for my $l (@works) {
    my ($significant, $opus) = _significant($tbl, $l, $r);
    if ($significant and $name{$significant}) {
      $dup{$significant}++;
      warn "Duplicate name `$significant': <$l> <$name{$significant}>"
	if $ENV{MUSIC_DEBUG_TABLE};
    }
    $name{$significant} = $l if $significant;
    $opus or next;
    $opus = lc $opus;
    if ($opus{$opus}) {
      $dupop{$opus}++;
      warn "Duplicate opus number `$opus': <$l> <$opus{$opus}>"
	unless $tbl->{dup_opus_rx} and $opus =~ /$tbl->{dup_opus_rx}/
	  or $tbl->{dup_opus}{$opus};
    }
    $opus{$opus} = $l;
  }
  delete $name{$_} for keys %dup;
  delete $opus{$_} for keys %dupop;
  for my $s (keys %aka) {
    my ($n) = _significant($tbl, $s, $r);
    warn "Duplicate and/or unnecessary A.K.A. name `$s' for <$aka{$s}>"
      if $name{$n};
    $name{$n} = $aka{$s};
    $name{"\0$s"} = "\0$n";	# put into values(), see normalize_person()
  }
  $tbl->{works} = \@works;
  $tbl->{opus} = \%opus if %opus;
  $tbl->{name} = \%name if %name;
  $tbl;
}

sub translate_signature ($$$$) { # One should be able to override this
  shift;
  join '', @_;
}
$Normalize::Text::Music_Fields::translate_signature = \&translate_signature;

my %alteration = (dur => 'major', moll => 'minor');
my %mod = (is => 'sharp', es => 'flat', s => 'flat',	# since Es means Ees
	   '#' => 'sharp', b => 'flat');

# XXXX German ==> English (nontrivial): H ==> B, His ==> B sharp, B ==> B flat
# XXXX Do not touch B (??? Check "Klavier" etc to detect German???)
my %key = (H => 'B');

sub normalize_signature ($$$$) {
  my ($self, $key, $mod, $alteration) = @_;
  $alteration ||= ($key =~ /[A-Z]/) ? ' major' : ' minor';
  $alteration = lc $alteration;
  $alteration =~ s/^-?\s*/ /;
  $alteration =~ s/(\w+)/ $alteration{$1} || $1 /e;
  $mod =~ s/^-?\s*/ / if $mod;		# E-flat, Cb
  $mod = lc $mod;
  $mod =~ s/(\w+|#)/ $mod{$1} || $1 /e;
  $key = uc $key;
  $key = $key{$key} || $key;
  &$Normalize::Text::Music_Fields::translate_signature($self,$key,$mod,$alteration);
}

my $post_opus_rex = qr/(?:[\-\/](?=\d)|(?:[,;.]?|\s)\s*(?:\bN(?:[or]|(?=\d))\.?|#|\x{2116}\.?))\s*(?=\d)/;

sub normalize_opus ($$$) {
  my ($self, $op, $no) = (shift, shift, shift);
  my $have_no = ( $op =~ s/\b(?:[,;.]?|\s)\s*(?=No\.\s*\d+)/, / );
  $no = '' unless defined $no;
  # nr12 n12 12 -12 #12 Numero_Sign 12 - but only if $op has no number already!
  $no =~ s/^$post_opus_rex/, No. / unless $have_no;
  # Now the tricky part: normalize the stuff in unknown format;
  # XXXX Now support only "B. NNN" stuff
  $op =~ s/^(\w)(\b|(?=\d))\.?\s*/\U$1. /;
  "$op$no"
}

# 1: prefix ("in" etc.), 2: letter, 3: modifier ("b" etc), 4: alteration: minor etc.
my $signature_rex = qr/(\s*(?:\bin\b|[,;.:]|^|\((?:in\s+)?(?=[-a-zA-Z#\s]+\)))\s*)([a-h])(\s*[b#]|(?:\s+|-)(?:flat|sharp)|[ie]s|(?<=e)s|)((?:(?:\s+|-)(?:major|minor|dur|moll))?)\)?(?=\s*[-;":]|$)/i;

# All these should match in
# mp3info2 -D -a beethoven -t "# 28" ""
#  (should give the same results): "wind in C" "tattoo" "WoO 20"
# "sonata in F#" "piano in F#" "op78" "Op. 10-2" "Op. 10, #2" "sonata #22" "WoO 205-1"

sub find_person ($) {
 my $self = shift;
 eval {$self->name_for_field_normalization} || eval {$self->composer}
   || $self->artist;
}

# See test_normalize_piece()
sub _normalize_piece ($$$$) {
  my ($self, $n, $improve_opus, $by_opus) = (shift, shift, shift, shift);
  my $ini_n = $n;
  $n = $n->[0] if ref $n;		# [value, handler]
  return $ini_n unless $n;
  $n =~ s/^\s+//;
  $n =~ s/\s+$//;
  return $ini_n unless $n;
  $n =~ s/\s{2,}/ /g;

  # Opus numbers
  $n =~ s/\bOp(us\s+(?=\d)|[.\s]\s*|\.?(?=\d))/Op. /gi;	# XXXX posth.???
  $n =~ s/\bN(?:[or]|(?=\d))\.?\s*(?=\d)/No. /gi; # nr12 n12
  $n =~ s/(?<!\w)[#\x{2116}]\s*(?=\d)/No. /gi;	# #12, Numero Sign 12

  my $c = find_person $self;
  my $tbl = ($c and load_composer($self, $c)) || {};
  my $opus_rx = $tbl->{opus_rx} || $def_opus_rx;

  # XXXX Is this `?' for good?
  $n =~ s/(?<=[^(.,;\s])(\s*[.,;])?\s*\b(?=$opus_rx)/; /gi
    if $improve_opus;		# punctuation before Op.

  # punctuation between Op. and No (as in Wikipedia for most expanded listings)
  # $n =~ s/\b((Op\.|WoO)\s+\d+[a-d]?)(?:[,;.]?|\s)\s*(?=No\.\s*\d+)/$1, /gi;
  $n =~ s/($opus_rx)($post_opus_rex\d+)?/ normalize_opus($self, $1, $2) /gie;

  # Tricky part: normalize "In b#"; allow just b# after punctuation too
  $n =~ s/$signature_rex/
    ((not $1 or 'i' eq substr($1,0,1)) ? '' : ' ') . "in "
     . normalize_signature($self,"$2","$3","$4")/ie;
  my $canon;
  {
    $tbl or last;
    # Convert Op. 23-3 to Op. and No
#    my ($o, $no) = ($n =~ /\b(Op\.\s+\d+[a-d]?[-\/]\d+[a-d]?)((?:[,;.]?|\s)\s*(?:No\.\s*\d+))?/);
#    $n =~ s/\b(Op\.\s+\d+[a-d]?)[-\/](\d+[a-d]?)/$1, No. $2/i
#      if $o and not $no and $o !~ /^$opus_rx$/;
    $tbl->{works} or last;
    # XXX See Wikipedia "Opus number" for more complete logic
    my ($opus) = ($n =~ /^.*($opus_rx)/); # at the end (one not in comments!)
    if ($opus and $by_opus) {
      $canon = $tbl->{opus}{lc $opus} or last;
    } else { # $significant: Up to the first "No. NNN.N", or to the first ";"
      my ($significant, $pre, $no, $post) =
	($n =~ /^((.*?)\bNo\b[.]?\s*(\d+(?:\.\d+)*))\s*(.*)/is);
      ($significant) = ($n =~ /^(.*?);/s) unless $significant;
      $significant ||= $n;
      $canon = $tbl->{name}{lc $significant}; # Try exact match
      if (not $canon) {	# Try harder: match word-for-word
	my ($ton, $rx_pre, $rx_post) = ('') x 3;
	my $nn = $n;
	if ($nn =~ s/\b(in\s+[A-H](?:\s+(?:flat|sharp))?\s+(?:minor|major))\b//) {
	  $ton = $1;
	  ($significant, $pre, $no, $post) = # Redo with $nn
	    ($nn =~ /^((.*?)\bNo\b[.]?\s*(\d+(?:\.\d+)*))\s*(.*)/is);
	  ($significant) = ($nn =~ /^(.*?);/s) unless $significant;
	  $significant ||= $nn;
	  $ton = '.*\b' . (quotemeta $ton) . '\b';
	}
	$pre = $significant unless defined $pre;	# Same with No removed
	# my @parts2 = split '\W+', $post;
	if ($pre and $pre =~ /\w/) {
	  $rx_pre = '\b' . join('\b.*\b', split /\W+/, $pre) . '\b';
	}
	if ($post and $post =~ /\w/) {
	  $rx_post = '.*' . join '\b.*\b', split /\W+/, $post;
	}
	# warn "<$no> <$n> <$nn> <$ton> <$rx_pre> <$rx_post>";
	$no = '.*\bNo\.\s*' . (quotemeta $no) . '\b(?!\.\d)' if $no;
	$no = '' unless defined $no;
	last unless "$rx_pre$no$ton$rx_post";
	my $sep = $tbl->{no_opus_no} ? '' : '.*;';
	my $rx = qr/$rx_pre$no$ton$rx_post$sep/is;
	my @matches = grep /$rx/, values %{$tbl->{name}};
	if (@matches == 1) {
	  $canon = $matches[0];
	} elsif (!@matches) {
	  last;
	} else { # Many matches; maybe the shortest is substr of the rest?
	  my ($l, $s, $diff) = 1e100;
	  $l > length and ($s = $_, $l = length) for @matches;
	  $s eq substr $_, 0, $l or ($diff = 1, last) for @matches;
	  last if $diff;
	  $canon = $s;
	}
	$canon = $tbl->{name}{$canon} if $canon =~ s/^\0//s; # short name
      }
    }
#    if ($canon) {
#      my (%w, %w1);
#      for my $w (split /[-.,;\s]+/, $canon) {
#	$w{lc $w}++;
#      }
#      for my $w (split /[-.,;\s]+/, $n) {
#	$w1{lc $w}++ unless $w{lc $w};
#      }
#      if (%w1) {
#	warn "Unknown words in title: `", join("` '", sort keys %w1), "'"
#	  unless $ENV{MUSIC_TRANSLATE_FIELDS_SKIP_WARNINGS};
#	last
#      }
#    }
    $n = $canon;	# XXXX Simple try (need to compare word-for-word)
  }
  return ref $ini_n ? [$n, $ini_n->[1]] : $n;
}

sub normalize_piece ($$) {
  _normalize_piece(shift, shift, 'improve opus', 'by opus');
}

sub opus_parser ($) {
  my $tag = shift;
  my $c = find_person $tag;
  my $tbl = ($c and load_composer($tag, $c));
  my $opus_rx = $tbl->{opus_rx} || $def_opus_rx;
  my $opus_pre = $tbl->{opus_prefix} || 'Op.';
  ($opus_rx, $opus_pre, $c)
}

sub full_opus ($$;$$) {
  my ($tag, $short, $opus_rx, $opus_pref) = (shift, shift, shift, shift);
  ($opus_rx, $opus_pref) = opus_parser($tag) unless $opus_rx;

  $short = "$opus_pref $short" if $short =~ /^\d/ and not $short =~ /$opus_rx/;
  $short =~ s/^($opus_rx)($post_opus_rex\d+)?/ normalize_opus($tag, $1, $2) /gie;
  $short
}

# Currently used Title-* fields: RAW, Opus, Dates, Key, Name, Related-Name,
# Alternative-Name, Punct, Type, Count, For, Type-After-Name, In-Movements
# Related-On, Comment, Related-After, Name-By-First-Row
## [When new added, change also the "merging" logic in merge_info().]
sub normalize_mail_header_line ($$;$$) {
  my ($tag, $in, $opus_rx, $opus_pref) = (shift, shift, shift, shift);
  my ($t, $v) = $in =~ /^([-\w]+):\s*(.*)$/s or die;
  $v = "($v)" if $t eq 'Title-Dates';
  $v = full_opus $tag, $v, $opus_rx, $opus_pref
    if $t eq 'Title-Opus' and $v =~ /(^\d|[\-\/])/;
  $v = "; $v" if $t eq 'Title-Opus';
  $v = qq("$v") if $t =~ /^Title(-Related)?-Name$/;
  $v = qq(["$v"]) if $t =~ /^Title-Name-By-First-Row$/;
  $v = qq(; "$v") if $t eq 'Title-Alternative-Name';
  $v =~ s/^(in\s+)?/in /i if $t =~ 'Title-Key';
  $v = "No. $v" if $t eq 'Title-No';
  $v = "for $v" if $t eq 'Title-For';
  $v = "on $v" if $t eq 'Title-Related-On';
  $v = "(lyrics by $v)" if $t eq 'Title-Lyrics-By';
  $v = ", $v" if $t eq 'Title-Type-After-Name';
  $v;
}

## perl -wple "BEGIN {print q(# format = mail-header)} s/#\s*normalized\s*$//; $_ = qq(Title: $_) unless /^\s*(#|$)/; $_ = qq(\n$_) if $p and not /^##/; $_ .= qq(\n) unless $p = /^##/" Normalize::Text::Music_Fields-G_Gershwin.comp >Music_Fields-G_Gershwin.comp-mail
sub normalize_piece_mail_header ($$;$$) {
  my ($tag, $in, $opus_rx, $opus_pref) = (shift, shift, shift, shift);
  return $1 if $in =~ /^Title:\s*(.*?)\s*$/m;
  my @pieces = map normalize_mail_header_line($tag, $_, $opus_rx, $opus_pref),
    grep /^Title-[-\w]+:\s/, split /\n/, $in;
  for my $i (1 .. @pieces - 1) {
    $pieces[$i-1] .= ' '
      unless $pieces[$i-1] =~ /[\(\[\{]$/ or $pieces[$i] =~ /^[\)\]\}.,;:?!]/;
  }
  return join '', @pieces;
}

sub shorten_opus ($$$$) {		# $mp3, $str, $pre
  my ($tag, $op, $pref, $rx) = (shift, shift, shift, shift);
  my ($out, $cut) = ($op, '');
  if ($out =~ s/^\Q$pref\E\s*(?=\d)//) {
    if ($out =~ $rx) {	# back up if shortened version causes confusion
      $out = $op;
    } else {
      $cut = $pref;
    }
  }
  my $out1 = $out;
  if ($out =~ s/(\d[a-i]?),\s+No\.\s*(?=\d)/$1-/) {
    my $o = full_opus($tag, $out, $rx, $pref);
    if ($op ne $o or $out =~ /^$rx$/) {	# check again
      $out = $out1;
      unless ($out eq $op) {			# Extra sanity check
	$o = full_opus($tag, $out, $rx, $pref);
	$out = $op unless $op eq $o;
      }
    }
  }
  $out
}

my $main_instr = join '|', qw(Piano Violin Viola Cello Horn String Wind Harp
			      Instrument Clarinet Alto);
my $for_instr = join '|', qw(Mandolin Harpsichord chorus soprano alt bass
    basses tenor mezzo-soprano \(mezzo\)soprano baritone contralto hand
    soli soloists woodwinds celesta accordion instrumentalists large small
    double violoncello clarinet oboe english french bassoon trombone organ
    flute voice orchestra military band chamber symphonic symphony electric
    percussion double-bass vibraphone pantomime instrumental ensemble tape
    timpani bells keyboard guitar triple percussionist counter-tenor alto
    counter-alto male female children's boys' mixed a capella cappella choir
    basssoli chamberorchestra metronome triangle harmonium trumpet);
my $multiplets = join '|', qw(solo duo duet trio quartet quintet sextet septet octet);
my $pieces = join '|', qw(Serenada Serenade Romance Song Notturno Aria Mass
    Allemande Chorus Allegretto Rondo Opera Fantasia Polonaise Contredanse
    Prelude Andante Cadenza Bagatelle Cantata Aria Joke Waltz Waltzes Minuet
    Ländler March Rondino Variations Equali Fugue Piece Symphony Sonata
    Concerto Sonatina Dance Mignon Fantasy Scherzo Polka Moderato Fragment
    Transcription Orchestration Suite Music Reduction Passacaglia Arrangement
    accompaniment choral score Operetta Ballet oratorio Choruses Intermezzo
    Overture Dialogue Epilogue Aphorism Monologue Gallop Interlude
    Re-orchestration Reorchestration Cycle Potpourri Nocturne Capriccio
    Mazurek Mazurka Impromptu Humoresque Ballade Ballads Gavotte Requiem
    Fanfares Motet Rhapsodies Rhapsody Intermezzi Poem Marches Theme
    Melody);

my $numb_rx = qr/one|two|three|four|five|six|seven|eight|nine/i;

my $count_rx = qr/ \d+
		 | (?:$numb_rx)(?:teen)?
		 | ten|eleven|twelve|thirteen|fifteen|eighteen
		 | (?:twenty|thirty|fourty|fifty|sixty|seventy|eighty|ninety)
		   (?: (?:\s+ | -) (?:$numb_rx) )? /ix;

#no utf8;			# `use' is needed by 5.005

my $for_rx = qr/ (?:\s+|^)
		 for
		 (?: (?:\s+|(?<=\/)) \(?
		     (?:and|or|&|vocal\s+soloist|$main_instr|$for_instr|prepared\s+piano|magnetic\s+tape|stage\s+orchestra|jazz\s+ensemble|(?:vocal\s+)?(?:$multiplets)|$count_rx|[23456789]|[12345]\d|Große Fuge)
		     (?:s|\(s\))? \)?
		     [,\/]?
		   )+
	       /ix;

my $piece_rx = qr/ (?: (?:Transcription|Orchestration|Reduction|Arrangement|Suite|Instrumentation|Re-?orchestration)
		     \s+ of
		     (?: \s+ (?: $main_instr | the | $count_rx ) )?
		     \s+ )? # Mod
		   (?:
		     (?: $main_instr | Vocal | secular | sacred
		     | Double | Triple | Easy | Trio | Symphonic )
		     \s+ )?	# Prefix
		   (?:Concerto\s+grosso | $multiplets
		   | Ecossaise?
		   | (?:[123456]-part\s+)? (?:riddle\s+)? Canon
		   | (?:sets\s+of\s+)? (?: chorale\s+preludes? | $pieces )
                     (?: s? \s* (?:\band\b|&) \s* (?:$pieces))?
		   | Incidental\s+music | electronic\s+composition
		   | chorale\s+prelude
		   | Musical\s+greetings? | choral\s+score | vocal\s+quartet
		   | (?:heroic|comic|tragic|historical)\s+opera
		   | scenic\s+composition | symphonic\s+poem ) # Main type
		   (?: s? \s+ in \s+ (?:$numb_rx) \s+ act )?
		 /ix;

#use utf8;			# needed by 5.005

my $name_rx = qr/ (?: [A-Z]\w* \.? \s+)* [A-Z][-\'\w]+ /x;

my $rel_piece_rx = # Two Pieces for Erwin Dressel's Opera "Armer Columbus"
  qr/ \b
      (?:to|from|of|a\s+fter|for|on(?:\s+motives\s+of)?)
      (?:
	\s+ (?: \s+ music \s+ to)? (?: the | $name_rx\'s ) # Erwin Dressel's
	(?: \s+ (?: (?:(?:silent|animated)\s+)? film | spectacle | comedy
	  | TV[-\s]+production | music\s+to\s+the\s+film
	  | play | (?:Chamber-?\s*)? opera | stage \s+ revue | novel))?)? \b
    /ix;


sub strip_known_from_end ($$$) {
  my ($tag, $in, $try_key, @tail) = (shift, shift, shift);
  # E.g., when the second name is based on the first line of lyrics:
  unshift @tail, "Title-Lyrics-By: $1" if $in =~ s/\s+\(lyrics\s+by\s+([^()]+)\)$//;
  unshift @tail, "Title-Alternative-Name: $4"
    while $in =~ s/^(.*?".*?".*)(\s*[.:,;])?\s+(?(2)|(?=\())(\()?"([^\"]+)"(?(3)\)|)$/$1/;

  # Too much recognized as this if ???
  while ( $in =~ s/ \s* ( $rel_piece_rx | (?!$) [.:,;]? )
		    (?: \s+
		      ( (\[)? ["\x{201E}]([^\"\x{201C}\x{201E}]+)["\x{201C}] (?(3) \] | )
                      | \(["\x{201E}]([^\"\x{201C}\x{201E}]+)["\x{201C}]\) )) $
		  //xo ) {
    if (length $1 <= 1) {
      unshift @tail, "Title-Name: $+";
    } else {
      unshift @tail, "Title-Related-Name: $+" if $2;
      unshift @tail, "Title-Related-How: $1";
    }
  }
  unshift @tail, "Title-Related-By: after $1"
    if $in =~ s/ \s* after \s+ ($name_rx) $//xo;

  unshift @tail, "Title-Related-On: $+"	# Variation and Fugue
    if $in =~ s/ ( \b variations? (?: \s+ and \s+ $piece_rx)? (?:$for_rx)? )
		 \s+ on \s+	# on a Hungarian melody
                 (an? \s+ (?: (?: $name_rx | original ) \s+)? $piece_rx
                   (?: \s+ by \s+ $name_rx)? )$/$1/xio;	# XXXX Why $+ needed?

  unshift @tail, "Title-In-Movements: $1"
    if $in =~ s/\s*(in\s+(a\s+single|$numb_rx|\d)\s+(movement|episode)s?)$//;

  unshift @tail, "Title-Key: " . normalize_signature($tag, "$2", "$3", "$4")
    if $in =~ s/\s*$signature_rex$//;
  if ($in =~ s/\s*([.,;:])?\s+No\.\s*(\d+[a-d]?(\.\d+)?)$//i) {
    unshift @tail, "Title-No: $2";
    unshift @tail, "Title-Punct: $1" if $1;
  }

  unshift @tail, "Title-Key: " . normalize_signature($tag, "$2", "$3", "$4")
    if $try_key and $in =~ s/[:;,]?\s*$signature_rex$//;

  my $f;
  ($f = $1) =~ s/^\s*for\s*//, unshift @tail, "Title-For: $f"
    if $in =~ s/($for_rx)$//io;	# XXXX: foo arranged for piano ???

  if ($in =~ s/\s*([.,;:])?\s+No.\s*(\d+[a-d]?(\.\d+)?)$//i) {	# Repeat
    unshift @tail, "Title-No: $2";
    unshift @tail, "Title-Punct: $1" if $1;
  }

  ($in, @tail);
}

sub parse_piece ($$$$$$$);	# Predeclaration for recursive call without ()
sub parse_piece ($$$$$$$) {
  my ($after_name, $at_end, $at_start, $tag, $in, $opus_pref, $opus_rx, @tail)
    = (shift, shift, shift, shift, shift, shift, shift);
  if ($at_end) {
    unshift @tail, "Title-Dates: $2"
      if $in =~ s/(.*\S)\s*\(([^()]*\b\d{4}\b[^()]*)\)$/$1/ # $1 makes greedy
	or $at_end and not $at_start and
	  $in =~ s/^()\s*\(([^()]*\b\d{4}\b[^()]*)\)$/$1/; # $1 makes greedy
    unshift @tail, "Title-Opus: " . shorten_opus($tag, "$2", $opus_pref, $opus_rx)
      while $in =~ s/(.*);\s+($opus_rx)\s*$/$1/;
    unshift @tail, "Title-Key: " . normalize_signature($tag, "$2", "$3", "$4")
      if $in =~ s/\s*$signature_rex$//;
  }
  ($in, my @r) = strip_known_from_end($tag, $in, 'look for key');
  unshift @tail, @r;

  # Now recognize comment as everything after a key (except, maybe, name)
  if ($in =~ /^(.*\S)\s*$signature_rex\s*(?:"([^\"]+)"\s*)?(?:([.,:;])\s)?(.*)$/) {
    $in = $1;
    my $k = normalize_signature($tag, "$3", "$4", "$5");
    my($n,$rest) = ($6, $8);
    if (length $rest) {{		# Localize match
      unshift @tail,
	'Title-'. ($8 =~ /^[^\s\w]$/ ? 'Punct' : 'Comment'). ": $rest";
    }}
    unshift @tail, "Title-Punct: $7" if $7;
    my $alt = ($in =~ /".*"/ ? '-Alternative' : '');
    unshift @tail, "Title$alt-Name: $n" if defined $n and length $n;
    unshift @tail, "Title-Key: $k";
  }

  # Now repeat looking for known fields
  ($in, @r) = strip_known_from_end($tag, $in, not 'look for key');
  unshift @tail, @r;

  if ($at_start) {		#  and (@tail or not $at_end)
    unshift @tail, "Title-Type: $1" if $in =~ s/^($piece_rx s?)\s*$//iox;
    unshift @tail, "Title-Count: $1" , "Title-Type: $2"
      if $in =~ s/^($count_rx)\s+( $piece_rx s?)\s*$//iox;
    unshift @tail, "Title-Count: $1"
      if $in =~ s/^($count_rx)\s*$//iox;
  }
  if (not @tail and $at_start and $at_end) {
    unshift @tail, "Title: $in";
  } elsif (not length $in) {	# Do nothing
  } elsif ($in =~ /^\s*[-,:;.()\[\]{}]\s*$/) {
    unshift @tail, "Title-Punct: $in";
  } elsif ($after_name and $in =~ /^(by|after)((\s+and)?\s+[A-Z][-\'\w]+)+\s*$/) {
    unshift @tail, "Title-Related-By: $in";
  } elsif ($after_name and $in =~ /^([-,;:])\s+($piece_rx s?)\s*$/iox) {
    unshift @tail, "Title-Type-After-Name: $2";
  } elsif ($at_start and $in =~ /^"([^\"]+)"\s*$/iox) {
    unshift @tail, "Title-Name: $1";
  } else {
    if ($at_start and $in =~ /^"([^\"]+)"[,.;:]\s*(\S.*?)\s*$/) {
      my $name = $1;		# Pretend we are at start:
      my @rest = parse_piece 'after_name', ($at_end and not @tail), 'start',
	$tag, "$2", $opus_pref, $opus_rx;
      unshift @rest, "Title-Punct: ,"
	unless $rest[0] =~ s/^Title-Type:/Title-Type-After-Name:/;
      return("Title-Name: $name", @rest, @tail)
	unless (join "\n", '', @rest) =~ /\nTitle-RAW:/;
    }
    unshift @tail, "Title-RAW: $in";
  }
  @tail;
}

my %html_esc = qw( amp & lt < gt > );

sub naive_format ($$$) { # Used to find glaring errors in conversion only
  my ($tag, $in, $opus_rx, $opus, @out) = (shift,shift,shift);
  $in =~ s/^($opus_rx)\n/$1: /;
  my @in = split /\s*\n\s*/, $in;
  if ($in[0] =~ s/^($opus_rx)[:,]\s*/Title-RAW: /) {
    ($opus = $1) =~ s/^Opus\b/Op./;
  }
  for my $l (@in) {
    if ($l =~ s/^Title-Bold:\s*//) {
      push @out, qq("$l");
    } elsif ($l =~ s/^Title-Opus:\s*//) {
      push @out, '; ' . full_opus $tag, "$l";
    } elsif ($l =~ s/^Title-Dates:\s*//) {
      push @out, "($l)";
    } elsif ($l =~ s/^X-\w[-\w]*:\s*//) { # Do nothing
    } elsif ($l =~ s/^Title-(RAW|Comment):\s*//) {
      push @out, $l if length $l;
    } else {
      warn "Naive formatting: Unknown line format `$l'"
    }
  }
  if (defined $opus) {
    my @year;
    @year = $1 if @out and $out[-1] =~ s/\s*(\([^()]*\b\d{4}\b[^()]*\))$//;
    pop @out unless @out and length $out[-1];
    push @out, "; $opus", @year;
  }
  for my $n (1..$#out) {
    $out[$n] =~ s/^(?![.,;:])/ /;
  }
  join '', @out
}

# Convert from line-format to mail-header format:
## perl -MNormalize::Text::Music_Fields -wlne   "BEGIN {$tag = Normalize::Text::Music_Fields::prepare_tag_object_comp(shift @ARGV); print q(# format = mail-header)} print Normalize::Text::Music_Fields::emit_as_mail_header($tag,$_, 0,$pre)" gershwin Music_Fields-G_Gershwin.comp-line >Music_Fields-G_Gershwin.comp-mail1
# (inverse transformation:) Dump pieces listed in mail-header format
## perl -MNormalize::Text::Music_Fields -wle "print for Normalize::Text::Music_Fields::read_composer_file(shift, shift)" gershwin Music_Fields-G_Gershwin.comp-mail > o
#
## perl -MNormalize::Text::Music_Fields -00wnle "BEGIN {$tag = Normalize::Text::Music_Fields::prepare_tag_object_comp(shift @ARGV); print q(# format = mail-header)} print Normalize::Text::Music_Fields::emit_as_mail_header($tag,$_, q(bold,xml,opus),$pre)" shostakovich  o-xslt-better >Music_Fields-D_Shostakovich.comp-mail1
## perl -MNormalize::Text::Music_Fields -wnle "BEGIN {$tag = Normalize::Text::Music_Fields::prepare_tag_object_comp(shift @ARGV); print qq(# format = mail-header\n)} print Normalize::Text::Music_Fields::emit_as_mail_header($tag,$_, q(opus), $pre)" schnittke  o-schnittke-better  >Music_Fields-A_Schnittke.comp-mail2
sub emit_as_mail_header ($$$$) { # $mp3, $str, $has_bold_parts_etc, $pre [R/W]
  my ($tag, $in, $preformatted) = (shift, shift, shift);
  $in =~ s/#\s*normalized\s*$//;
  #return "\n" if $in =~ /^\s*$/;
  my @out;
  unless ($in =~ /^\s*(#|$)/) {
    return "\n\n" if $preformatted and $in =~ /^<\?xml\b/;
    my $ini = my $ini_raw = $in;
    $in =~ s/&(amp|lt|gt);/$html_esc{$1}/g if $preformatted =~ /\bxml\b/;
    $in =~ s/&#x([\da-f]+);/chr hex $1/gei if $preformatted =~ /\bxml\b/;

    my ($opus_rx, $opus_pre) = opus_parser($tag);

    my $have_op = ($in =~ /^$opus_rx:/);
    # When $use_only_opus, all the text but Opus-No is ignored; bad for update
    my $use_only_opus = ($preformatted =~ /\bonly_by_opus\b/);
    $in = _normalize_piece($tag, $in, !$have_op, $use_only_opus)
      unless $preformatted =~ /\bbold\b/;

    $ini = naive_format($tag, $in, $opus_rx) if $preformatted =~ /\b(opus|bold)\b/;
    my @op;
    my $prefix = ($preformatted =~ /\bbold\b/ ? 'Title-RAW: ' : '');
    if ($in =~ s/^($opus_rx)(?:[:,](?:[ \t]+|(?=\n))|\n\s*)/$prefix/) {
      my $op = $1;
      my $o_pre = $opus_pre;
      $o_pre = 'Opus' if $op =~ /^Opus\b/;
      @op = "Title-Opus: " . shorten_opus($tag, $op, $o_pre, $opus_rx);
    } elsif ($preformatted =~ /\bopus\b/) {
      warn "Expected to start with `Opus NUMBER: ': <<<$in>>>";
    }
    if ($preformatted =~ /\bbold\b/) {
      my @parts = split /\s*\n\s*/, $in;
      my ($after_for, $after_name);
      for my $n (0..$#parts) {
	my $p = $parts[$n];
	$p =~ s/\s+$//;
	if ($p =~ s/^Title-Bold:\s*//) {
	  my $rel = $after_for ? '-Related' : '';
	  push @out, "Title$rel-Name: $p";
	  $after_for = 0, $after_name = 1;
	  next;
	} elsif ($p =~ /^Title-RAW:\s*$/) { # Do nothing
	  next;
	} elsif ($after_for =
		 ($n != $#parts and $parts[$n+1] =~ /^Title-Bold:\s*/
		  and $parts[$n] =~ /^Title-RAW:\s*/
		  # Title-RAW: Two Pieces for Erwin Dressel's Opera "Armer Columbus"
		  and $p =~ s/ \s* ( $rel_piece_rx \s*$ )//ixo)) {
	  my $how = $1;
	  $p =~ s/^Title-RAW:\s+//
	    or warn "Expected to start with Title-RAW: <<<$p>>>";
	  push @out,
	    parse_piece $after_name,!'end', !$n, $tag, $p, $opus_pre, $opus_rx;
	  push @out, "Title-Related-How: $how";
	} elsif ($p =~ s/^Title-Opus:\s+// ) {
	  push @out, 'Title-Opus: ' . full_opus $tag, $p, $opus_rx, $opus_pre;
	  $after_name = 0;
	} elsif ($p =~ /^(Title-(Opus|Comment|Dates)|X-Title-Opus-Alt):\s+/ ) { # Keep intact
	  push @out, $p;
	  $after_name = 0;
	} else {
	  $p =~ s/^Title-RAW:\s+// or warn "Expected to start with `Title-RAW: ': <<<$p>>>";
	  push @out, parse_piece $after_name, $n==$#parts, !$n, $tag, $p, $opus_pre, $opus_rx;
	  $after_name = 0;
	}
      }
    } else {
      @out = parse_piece 0, 'at_end', 'at_start', $tag, $in, $opus_pre, $opus_rx;
    }
    my @y;
    unshift @y, pop @out while $out[-1] =~ /^Title-Dates:\s/;
    push @out, @op, @y;
    $out[0] =~ s/^Title:/Title-RAW:/ if @out > 1; # Opus 1: foo
    $in = join "\n", @out, ($preformatted =~ /\bbold\b/ ? ('','') : ()); # \n\n

    my $res = normalize_piece_mail_header($tag, $in, $opus_rx, $opus_pre);
    warn "# Mismatch:\n# in  = $ini\n# out = $res\n#rawin= $ini_raw\n" unless $res eq $ini;
  }
  $in = "\n$in" if $in !~ /^\s*##/ and $_[0] and not $preformatted =~ /\bbold\b/;
  $in .= qq(\n) unless $preformatted =~ /\bbold\b/ or $_[0] = ($in =~ /^##/);
  $in;			# Caller appends extra \n
}

## perl -MNormalize::Text::Music_Fields -wnle "BEGIN {$tag = Normalize::Text::Music_Fields::prepare_tag_object_comp(shift @ARGV); print qq(# format = mail-header\n)} next unless s/^\s*\+\+\s*//; print Normalize::Text::Music_Fields::merge_info($tag,$_, q(opus))" brahms o-brahms-op-no1-xslt
sub merge_info ($$$;$$) {	# $update not fully implemented
  my ($tag, $in, $preformatted, $soft, $update) = (shift, shift, shift, shift, shift);
  my $parsed = emit_as_mail_header($tag, $in, $preformatted, my $pre);
  my $op_n = ($parsed =~ /^Title-Opus: (.*)/m and $1);
  die "Can't find opus number in `$in'" unless defined $op_n;
  my $op_no = full_opus $tag, $op_n;

  $parsed =~ s/^Title-Punct:\s*-\nTitle-Name:/Title-Name-By-First-Row:/;
  $soft ||= qr(^(?!));		# Never match
  warn "Opus [$op_n]: Type `$1' interpreted as Title-Name\n"
    if $op_n =~ $soft and $parsed =~ s/^Title-Type:/Title-Name:/m
      and $parsed =~ /^Title-Name:\s*(.*)/;
  warn("Too many fields in `$parsed', skipping"), return ''
    if $parsed =~ /^(?=.)(?!Title-(?:Opus|RAW|Name(?:-By-First-Row)?|Key|Dates):)/m;

  my $name = normalize_piece $tag, $op_no; # expand opus+no to the full name

  if ($name eq $op_no) {	# No current information
    my ($opus_rx, $opus_pre) = opus_parser($tag);
    die "No subopus number in `$op_no' (from `$in')"
      unless $op_no =~ /^($opus_rx)\s*[.,:;]\s*No/;
    my $op = $1;
    $name = normalize_piece $tag, $op; # Expands opus to the full name
    $update = 0;
  } elsif (not $update) {
    die "Opus `$op_no' already known: `$name'";
  }

  my $parsed_op = emit_as_mail_header($tag, $name, 'only_by_opus', my $pre1);
  warn("Prior knowledge not found for `$in'\n"),
    return $parsed if $parsed_op =~ /^Title:/; # Not found, or not parsable

  unless ($update) {		# Handling "a group name"
    $parsed_op =~ s/^Title-Count:.*\n//; # Four ballades for piano
    if ($parsed_op =~ /^Title-Type:\s*(.*)\n/) { # Strip the plural
      my $type = $1;
      $type =~ s/^ Sets \s+ of \s+/Set of /x
	or $type =~ s/^ ($piece_rx) (?:s | es) $/$1/x; # Strip the plural
      $parsed_op =~ s/^.*/Title-Type: $type/;
    }
    $parsed_op =~ s/^Title-Opus:.*/Title-Opus: $op_n/m
      or die "Can't find Opus: `$parsed_op'";
  }
  if ($parsed =~ /^Title-Dates:\s*(.*)/m) {
    my $d = $1;			# (?<!.) does as /^/m, but matches at end too
    $parsed_op =~ s/(?<!.)(Title-Dates:.*\n|\Z)/Title-Dates: $d\n/ or die;
  }
  if ($parsed =~ /^Title-Key:\s*(.*)/m) {
    my $k = $1;
    die "Key mismatch: $k vs $1"
      if $parsed_op =~ /^Title-Key:\s*(.*)/m and $1 ne $k;
    # XXXX Where put the key?  STD orders: Type/No/Key/For or Type/For/No/Key
    # There is also (beeth) Type/For/Related-On/Key???  Type/For/Key???
    $parsed_op =~ s/(?<!.)(?=Title-(?!(?:Type|For|Related-On|No):)|\Z)/Title-Key: $k\n/ or die;
  }
  if ($parsed =~ s/^Title-RAW:/Title-Name:/m) {
    (my $n) = ($parsed =~ /^Title-Name:\s*(.*)/m);
    warn "Title-RAW `$n' interpreted as Title-Name in `$in'\n";
  }
  if ($parsed =~ /^(Title-Name(?:[-\w]*):\s*.*)/m) { # pre: Type-After-Name, In-Movements
    my $n = $1;			# Related-On, Comment, Related-After
    $parsed_op =~ s/(?<!.)(?=Title-(?:Type-After-Name|In-Movements|Related-On|Comment|Related-After|Opus|Dates):|\Z)/$n\n/ or die;
  }
  $parsed_op
}

for my $field (qw(album title title_track)) {
  no strict 'refs';
  *{"normalize_$field"} = \&normalize_piece;
}

# perl -Ii:/zax/bin -MNormalize::Text::Music_Fields -wle "BEGIN{binmode $_, ':encoding(cp866)' for \*STDIN, \*STDOUT, \*STDERR}print Normalize::Text::Music_Fields->check_persons"
sub check_persons ($) {
  my $self = shift;
  my %seen;
  $seen{$_}++ for values %tr;
  for my $l (keys %seen) {
    my $s = short_person($self, $l);
    my $ll = normalize_person($self, $s);
    warn "`$l' => `$s' => `$ll'" unless $ll eq $l;
  }
  %seen = ();
  $seen{$_}++ for values %short;
  for my $s (values %seen) {
    my $l = normalize_person($self, $s);
    my $ss = short_person($self, $l);
    warn "`$s' => `$l' => `$ss'" unless $ss eq $s;
  }
}

my %aliases;

sub load_lists () {
 my @dirs = get_path();
 my @lists = map <$_/*.lst>, @dirs;
 #warn "dirs=`@dirs', lists=`@lists'\n";
 warn("panic: can't find name lists in `@dirs'"), return 0 unless @lists;

 for my $f (@lists) {
  local $/ = "\n";
  open F, "< $f" or warn("Can't open `$f' for read: $!"), next;
  my @in = <F>;
  close F or warn("Can't close `$f' for read: $!"), next;
  my $charset;
  for (@in) {
   next if /^\s*$/;
   if ( /^ \s* \# \s* (?:charset|encoding) \s* = \s* ("?) (.*?) \1 \s* $/ix) {
     $charset = $2;
     require Encode;
     next;
   }
   $_ = Encode::decode($charset, $_) if $charset; # Make empty to disable
   s/^\s+//, s/\s+$//, s/\s+/ /g;
   next if /^##/;
   if (/^ \# \s* (alias|fix|shortname_for) \s+ (.*?) \s* => \s* (.*)/x) {
     if ($1 eq 'alias') {
       $aliases{$2} = [split /\s*,\s*/, $3];
     } elsif ($1 eq 'fix') {
       my ($old, $ok) = ($2, $3);
       $tr{translate_dots $old} = $tr{translate_dots $ok} || $ok;
       #print "translating `",translate_dots $old,"' to `",translate_dots $ok,"'\n";
     } elsif ($1 eq 'shortname_for') {
       my ($long, $short) = ($2, $3);
       $tr{translate_dots $short} = $long;
       ($long) = strip_years($long);
       $short{$long} = $short;
     }
     next;
   }
   if (/^ \# \s* fix_firstname \s+ (.*\s(\S+))$/x) {
     $tr{translate_dots $1} = $tr{translate_dots $2};
     next;
   }
   if (/^ \# \s* keep \s+ (.*?) \s* $/x) {
     $tr{translate_dots $1} = $1;
     next;
   }
   if (/^ \# \s* shortname \s+ (.*?) \s* $/x) {
     my $in = $1;
     my $full = __PACKAGE__->_translate_person($in, 0);
     unless (defined $full and $full ne $in) {
       my @parts = split /\s+/, $in;
       $full = __PACKAGE__->_translate_person($parts[-1], 0);
       warn("Can't find translation for `@parts'"), next
         unless defined $full and $full ne $parts[-1];
       # Add the normalization
       my $f = __PACKAGE__->normalize_person($parts[-1]);
       $tr{translate_dots $in} = $f;
     }
     $short{$full} = $in;
     ($full) = strip_years($full);
     $short{$full} = $in;
     next;
   }
   warn("Do not understand directive: `$_'"), next if /^#/;
   #warn "Doing `$_'";
   my ($pre, $post) = /^(.*?)\s*(\(.*\))?$/;
   my @f = split ' ', $pre or warn("`$pre' won't split"), die;
   my $last = pop @f;
   my @last = $last;

 #  no utf8;			# `use' is needed by 5.005
   (my $ascii = $last) =~
         tr( ¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ\x80-\x9F)
           ( !cLXY|S"Ca<__R~o+23'mP.,1o>...?AAAAAAACEEEEIIIIDNOOOOOx0UUUUYpbaaaaaaaceeeeiiiidnooooo:ouuuuyPy_);
   push @last, $ascii unless $ascii eq $last;
   my $a = $aliases{$last[0]} ? $aliases{$last[0]} : [];
   $a = [$a] unless ref $a;
   push @last, @$a;
   for my $last (@last) {
     my @comp = (@f, $last);
     $tr{"\L@comp"} ||= $_;
     $tr{lc $last} ||= $_;		# Two Bach's
     if (@f) {
       $tr{"\L$f[0] $last"} ||= $_;	# With the first of pre-names only
       my @ini = map substr($_, 0, 1), @f;
       $tr{"\L$ini[0] $last"} ||= $_;	# One initial
       $tr{"\L@ini $last"} ||= $_;	# All initials
     }
   }
  }
 }
}

#$tr{lc 'Tchaikovsky, Piotyr Ilyich'} = $tr{lc 'Tchaikovsky'};

sub prepare_tag_object_comp ($;$) {
  my ($comp, $piece) = @_;
  require MP3::Tag;
  my $tag = MP3::Tag->new_fake('settable');

  for my $elt ( qw( title track artist album comment year genre
                    title_track artist_collection person ) ) {
    no strict 'refs';
    MP3::Tag->config("translate_$elt", \&{"Normalize::Text::Music_Fields::normalize_$elt"})
      if defined &{"Normalize::Text::Music_Fields::normalize_$elt"};
    # This is needed to expand albums, since pieces file is named so...
    MP3::Tag->config("short_person", \&Normalize::Text::Music_Fields::short_person)
        if defined &Normalize::Text::Music_Fields::short_person;
  }
  $tag->config('parse_data', ['mi', $comp, '%a'], ($piece ? ['mi', $piece, '%l'] : () ));
  $tag;
}

## perl -MNormalize::Text::Music_Fields -e Normalize::Text::Music_Fields::test_normalize_piece
sub test_normalize_piece {
  for (split /\n/, <<EOS) {
beethoven # 28
beethoven wind in C
beethoven tattoo
beethoven WoO 20
beethoven sonata in F#
beethoven piano in F#
beethoven op78
beethoven Op. 10-2
beethoven Op. 10, #2
beethoven sonata #22
beethoven WoO 205-1
beethoven WoO 205, No 1
beethoven WoO 205, No. 1
beethoven WoO 205, no 1
beethoven WoO 205;#1
beethoven WoO 205, no1
beethoven WoO 205 #1
beethoven WoO 205#1
beethoven WoO 205. #1
- beethoven WoO 205,-1
- beethoven WoO 205, -1
- beethoven WoO 205 -1
- beethoven WoO 205 1
- beethoven WoO 205;1
EOS
    my $match = (s/^-\s*// ? '-' : '+');
    s/^(\w+)\s+//;
    my $tag = prepare_tag_object_comp("$1", $_);
    print "$match ", find_person($tag), " ", $tag->album, "\n";
  }
}

for my $elt ( qw( title track artist album comment year genre
		  title_track artist_collection person ) ) {
  no strict 'refs';		# backward compatibility layer:
  *{"translate_$elt"} = \&{"normalize_$elt"} if defined &{"normalize_$elt"};
}

1;

=head1 NAME

Normalize::Text::Music_Fields - normalize names of people's and (musical) works.

=head1 SYNOPSIS

   $name = $obj->Normalize::Text::Music_Fields::normalize_person($name);
   $work = $obj->Normalize::Text::Music_Fields::normalize_piece($work);
 # $obj should have methods `name_for_field_normalization', 'shorted_person'

=head1 DESCRIPTION

Databases of names and of works-per-name are taken from plain-text
files (optionally in mail-header format).  Names are stored in F<*.lst> files.
Works are stored in F<.comp> files named after the shortened name
of the composer.

The directories of these files are looked in the environment variable
C<MUSIC_FIELDS_PATH> (if defined, split the same way as C<PATH>), or in
C<$ENV{HOME}/.music_fields>, and C<-> (and C<-> is replaced by the directory
named as the module file with F<.pm> dropped).  At runtime, one can
replace the list by calling function Normalize::Text::Music_Fields::set_path()
with the list of directories as the argument.

(Since parsed files are cached, replacing the directory list should be done
as early as possible.)

Files may be managed with utility subroutines provided with the module:

 # Translate from one-per-line to mail-header format:
 perl -wple "BEGIN {print q(# format = mail-header)} s/#\s*normalized\s*$//; $_ = qq(Title: $_) unless /^\s*(#|$)/; $_ = qq(\n$_) if $p and not /^##/; $_ .= qq(\n) unless $p = /^##/" Normalize::Text::Music_Fields-G_Gershwin.comp >Music_Fields-G_Gershwin.comp-mail

 # (inverse transformation:) Dump pieces listed in mail-header format
 perl -MNormalize::Text::Music_Fields -wle "print for Normalize::Text::Music_Fields::read_composer_file(shift, shift)" gershwin Music_Fields-G_Gershwin.comp-mail > o

 # Normalize data in 1-line-per piece format
 perl -MNormalize::Text::Music_Fields -wle "Normalize::Text::Music_Fields::prepare_tag_object_comp(shift)->Normalize::Text::Music_Fields::normalize_file_lines(shift)"

 # Create a mail-header file from a semi-processed (with "bold" fields)
 # mail-header file (with xml escapes, preceded by opus number)
 perl -MNormalize::Text::Music_Fields -00wnle "BEGIN {$tag = Normalize::Text::Music_Fields::prepare_tag_object_comp(shift @ARGV); print q(# format = mail-header)} print Normalize::Text::Music_Fields::emit_as_mail_header($tag,$_, q(bold,xml,opus),$pre)" shostakovich  o-xslt-better >Music_Fields-D_Shostakovich.comp-mail1

 # Likewise, from work-per-line with opus-numbers:
 perl -MNormalize::Text::Music_Fields -wnle "BEGIN {$tag = Normalize::Text::Music_Fields::prepare_tag_object_comp(shift @ARGV); print qq(# format = mail-header\n)} print Normalize::Text::Music_Fields::emit_as_mail_header($tag,$_, q(opus), $pre)" schnittke  o-schnittke-better  >Music_Fields-A_Schnittke.comp-mail2

 # A primitive tool for merging additional info into the database:
 perl -MNormalize::Text::Music_Fields -wnle "BEGIN {$tag = Normalize::Text::Music_Fields::prepare_tag_object_comp(shift @ARGV); print qq(# format = mail-header\n)} next unless s/^\s*\+\+\s*//; print Normalize::Text::Music_Fields::merge_info($tag,$_, q(opus,xml), qr(^(58|70|76|116|118|119)($|-)))" brahms o-brahms-op-no1-xslt

 # Minimal consistency check of persons database.
 perl -MNormalize::Text::Music_Fields -wle "BEGIN{binmode $_, ':encoding(cp866)' for \*STDIN, \*STDOUT, \*STDERR} print Normalize::Text::Music_Fields->check_persons"

 # Minimal testing code:
 perl -MNormalize::Text::Music_Fields -e Normalize::Text::Music_Fields::test_normalize_piece

It may be easier to type these examples if one uses C<manage_M_N_F.pm>, which
exports the mentioned subroutines to the main namespace (available in
F<examples> directory of a distribution of C<MP3::Tag>).  E.g., the last
example becomes:

 perl -Mmanage_M_N_F -e test_normalize_piece


=cut

