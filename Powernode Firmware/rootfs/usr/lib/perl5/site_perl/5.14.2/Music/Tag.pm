package Music::Tag;
use strict; use warnings; use utf8;
our $VERSION = '0.4103';

# Copyright © 2007,2008,2009,2010 Edward Allen III. Some rights reserved.
#
# You may distribute under the terms of either the GNU General Public
# License or the Artistic License, as specified in the README file.


use Carp;
use Locale::Country;
use File::Spec;
use Encode;
use Config::Options;
use Digest::SHA1;
use Time::Local;
use IO::File;
use IO::Dir;
use File::stat;
use File::Slurp;
use Readonly;
use Music::Tag::Generic;
use DateTimeX::Easy;

use utf8;

#use vars qw(%DataMethods);
my %DataMethods;
my $DefaultOptions;
my @PLUGINS;
my $PBP_METHODS = 1;
my $TRADITIONAL_METHODS = 1;
my %METHODS = ();
my ( $SHA1_SIZE, $SLURP_SIZE, $TENPRINT_SIZE );
Readonly::Scalar $SHA1_SIZE     => 4 * 4096;
Readonly::Scalar $SLURP_SIZE    => 1024;
Readonly::Scalar $TENPRINT_SIZE => 12;
sub default_options {
    my $self = shift;
    return $DefaultOptions;
}

sub LoadOptions {
    my $self    = shift;
    my $optfile = shift;
    if ( ref $self ) {
        return $self->options->fromfile_perl($optfile);
    }
    elsif ($self) {
        return $DefaultOptions->fromfile_perl($optfile);
    }
}

sub new {
    my $class    = shift;
    my $filename = shift;
    my $options  = shift || {};
    my $plugin   = shift || 'Auto';
    my $data     = shift || {};

    my $self = {};
    $self->{data} = $data;
    if ( ref $class ) {
        my $clone = { %{$class} };
        bless $clone, ref $class;
        return $clone;
    }
    else {
        bless $self, $class;
        $self->{_plugins} = [];
        $self->options($options);
        $self->filename($filename);
        $self->{changed} = 0;
    }

    $self->_test_modules();

    $self->add_plugin( $plugin, $options );
    return $self;

}

sub _test_modules {
    my $self       = shift;
    my %module_map = (
        'ANSIColor'     => 'Term::ANSIColor',
        'LevenshteinXS' => 'Text::LevenshteinXS',
        'Levenshtein'   => 'Text::Levenshtein',
        'Unaccent'      => 'Text::Unaccent::PurePerl',
        'Inflect'       => 'Lingua::EN::Inflect',
    );
    while ( my ( $k, $v ) = each %module_map ) {
        if (   ( $self->options->{$k} )
            && ( $self->_has_module($v) ) ) {
            $self->options->{$k} = 1;
        }
        else {
            $self->options->{$k} = 0;
        }
    }
    return;
}

sub _has_module {
    my $self    = shift;
    my $module  = shift;
    my $modfile = $module . '.pm';
    $modfile =~ s/\:\:/\//g;
    if ( eval { require $modfile; 1 } ) {
        return 1;
    }
    else {
        $self->status( 1, "Not loading $module: " . $@ );
        return 0;
    }
}

sub add_plugin {
    my $self    = shift;
    my $object  = shift;
    my $opts    = shift || {};
    my $options = $self->options->clone;
    $options->merge($opts);
    my $type = shift || 0;
    my $ref;
    if ( ref $object ) {
        $ref = $object;
        $ref->info($self);
        $ref->options($options);
    }
    else {
        my ( $plugin, $popts ) = split( /:/, $object );
        if ( $self->available_plugins($plugin) ) {
            if ($popts) {
                my @opts = split( /[;]/, $popts );
                foreach (@opts) {
                    my ( $k, $v ) = split( /=/, $_ );
                    $options->options( $k, $v );
                }
            }
            if (!eval {
                    if ( not $plugin =~ /::/ ) {
                        $plugin = 'Music::Tag::' . $plugin;
                    }
                    if ( $self->_has_module($plugin) ) {
                        $ref = $plugin->new( $self, $options );
                    }
                    return 1;
                }
                ) {
                croak "Error loading plugin ${plugin}: $@" if $@;
            }
        }
        else {
            croak "Error loading plugin ${plugin}: Not Found";
        }
    }
    if ($ref) {
        push @{ $self->{_plugins} }, $ref;
    }
    return $ref;
}

sub plugin {
    my $self   = shift;
    my $plugin = shift;
    if ( defined $plugin ) {
        foreach ( @{ $self->{_plugins} } ) {
            if ( ref($_) =~ /$plugin$/ ) {
                return $_;
            }
        }
    }
    return;
}

sub get_tag {
    my $self = shift;
    $self->_foreach_plugin( sub { $_[0]->get_tag } );
    return $self;
}

sub _foreach_plugin {
    my $self     = shift;
    my $callback = shift;
    foreach my $plugin ( @{ $self->{_plugins} } ) {
        if ( ref $plugin ) {
            &{$callback}($plugin);
        }
        elsif ($plugin) {
            $self->error("Invalid Plugin in list: '$plugin'");
        }
    }
    return $self;
}

sub set_tag {
    my $self = shift;
    $self->_foreach_plugin( sub { $_[0]->set_tag } );
    return $self;
}

sub strip_tag {
    my $self = shift;
    $self->_foreach_plugin( sub { $_[0]->strip_tag } );
    return $self;
}


# In retrospect, this was misnamed.  Too late now!
sub close {    ## no critic (ProhibitBuiltinHomonyms, ProhibitAmbiguousNames)
    my $self = shift;
    return $self->_foreach_plugin(
        sub {
            $_[0]->close();

            #$_->{info} = undef;
            #$_ = undef;
        }
    );
}

sub changed {
    my $self = shift;
    my $new  = shift;
    if ( defined $new ) {
        $self->{changed}++;
    }
    return $self->{changed};
}

sub data {
    my $self = shift;
    my $new  = shift;
    if ( defined $new ) {
        $self->{data} = $new;
    }
    return $self->{data};
}

sub options {    ## no critic (Subroutines::RequireArgUnpacking)
    my $self = shift;
    if ( not exists $self->{_options} ) {
        $self->{_options} = Config::Options->new( $self->default_options );
    }
    return $self->{_options}->options(@_);
}

sub setfileinfo {
    my $self = shift;
    if ( $self->filename ) {
        my $st = stat $self->filename;
        $self->mepoch( $st->mtime );
        $self->bytes( $st->size );
        return $st;
    }
    return;
}

sub sha1 {
    my $self = shift;
    if ( not( ( $self->filename ) && ( -e $self->filename ) ) ) {
        return undef;  ## no critic (Subroutines::ProhibitExplicitReturnUndef)
    }
    my $maxsize = $SHA1_SIZE;
    my $in      = IO::File->new();
    $in->open( $self->filename, '<' ) or die "Bad file: $self->filename\n";
    my $st   = stat $self->filename;
    my $sha1 = Digest::SHA1->new();
    $sha1->add( pack( 'V', $st->size ) );
    my $d;

    if ( $in->read( $d, $maxsize ) ) {
        $sha1->add($d);
    }
    $in->close();
    return $sha1->hexdigest;
}

sub picture {
    my $self = shift;
    unless ( exists $self->{data}->{PICTURE} ) {
        $self->{data}->{PICTURE} = {};
    }
    $self->{data}->{PICTURE} = shift if @_;

    if (   ( exists $self->{data}->{PICTURE}->{filename} )
        && ( $self->{data}->{PICTURE}->{filename} ) ) {
        my $root = File::Spec->rootdir();
        if ( $self->filename ) {
            $root = $self->filedir;
        }
        my $picfile =
            File::Spec->rel2abs( $self->{data}->{PICTURE}->{filename},
            $root );
        if ( -f $picfile ) {
            if ( $self->{data}->{PICTURE}->{_Data} ) {
                delete $self->{data}->{PICTURE}->{_Data};
            }
            my %ret = %{ $self->{data}->{PICTURE} };    # Copy ref
            $ret{_Data} = read_file( $picfile, 'binmode' => ':raw' );
            return \%ret;
        }
    }
    elsif (( exists $self->{data}->{PICTURE}->{_Data} )
        && ( length $self->{data}->{PICTURE}->{_Data} ) ) {
        return $self->{data}->{PICTURE};
    }
    return {};
}

sub get_picture {
    my $self = shift;
    return $self->picture;
}

sub set_picture {
    my $self  = shift;
    my $value = shift;
    return $self->picture($value);
}

sub picture_filename {
    my $self = shift;
    my $new  = shift;
    if ($new) {
        if ( not exists $self->{data}->{PICTURE} ) {
            $self->{data}->{PICTURE} = {};
        }
        $self->{data}->{PICTURE}->{filename} = $new;
    }
    if (   ( exists $self->{data}->{PICTURE} )
        && ( $self->{data}->{PICTURE}->{filename} ) ) {
        return $self->{data}->{PICTURE}->{filename};
    }
    elsif (( exists $self->{data}->{PICTURE} )
        && ( $self->{data}->{PICTURE}->{_Data} )
        && ( length( $self->{data}->{PICTURE}->{_Data} ) ) ) {
        return 0;
    }

    # Value is undefined, so return undef.
    return undef;    ## no critic (Subroutines::ProhibitExplicitReturnUndef)
}

sub picture_exists { goto &has_picture; }
sub has_picture {
    my $self = shift;
    if (   ( exists $self->{data}->{PICTURE}->{filename} )
        && ( $self->{data}->{PICTURE}->{filename} ) ) {
        my $root = File::Spec->rootdir();
        if ( $self->filename ) {
            $root = $self->filedir;
        }
        my $picfile =
            File::Spec->rel2abs( $self->{data}->{PICTURE}->{filename},
            $root );
        if ( -f $picfile ) {
            return 1;
        }
        else {
            $self->status( 0, 'Picture: ', $picfile, ' does not exists' );
        }
    }
    elsif (( exists $self->{data}->{PICTURE}->{_Data} )
        && ( length $self->{data}->{PICTURE}->{_Data} ) ) {
        return 1;
    }
    return 0;
}

sub available_plugins {
    my $self  = shift;
    my $check = shift;
    if ($check) {
        foreach (@PLUGINS) {
            if ( $check eq $_ ) {
                return 1;
            }
        }
        return 0;
    }
    return @PLUGINS;
}


sub datamethods {
    my $package = shift;
    if (ref $package) { $package = ref $package; }
    my $add  = shift;
    if ($add) {
        my $new = lc($add);
        $DataMethods{$new} = 1;
        if ( !defined &{ 'get_' . $new } ) {
            $package->_make_accessor( $new => {} );
        }
    }
    return [ keys %DataMethods ];
}

sub used_datamethods {
    my $self = shift;
    my @ret  = ();
    foreach my $m ( @{ $self->datamethods } ) {
        if ($self->has_data($m)) {
            push @ret, $m;
        }
    }
    return \@ret;
}

sub wav_out {
    my $self = shift;
    my $fh   = shift;
    my $out;
    $self->_foreach_plugin(
        sub {
            $out = $_->wav_out($fh);
            return $out if ( defined $out );
        }
    );
    return $out;
}

# This method is far from perfect.  It can't be perfect.
# It won't mangle valid UTF-8, however.
# Just be sure to always return perl utf8 in plugins when possible.

sub _isutf8 {
    my $self = shift;
    my $in   = shift;

    # If it is a proper utf8, with tag, just return it.
    if ( Encode::is_utf8( $in, 1 ) ) {
        return $in;
    }

    my $has7f = 0;
    foreach ( split( //, $in ) ) {
        if ( ord($_) >= 0x7f ) {    ## no critic (ProhibitMagicNumbers)
            $has7f++;
        }
    }

    # No char >7F it is prob. valid ASCII, just return it.
    if ( !$has7f ) {
        utf8::upgrade($in);
        return $in;
    }

    # See if it is a valid UTF-16 encoding.
    #my $out;
    #eval {
    #    $out = decode('UTF-16', $in, 1);
    #};
    #return $out unless $@;

    # See if it is a valid UTF-16LE encoding.
    #my $out;
    #eval {
    #    $out = decode('UTF-16LE', $in, 1);
    #};
    #return $out unless $@;

    # See if it is a valid UTF-8 encoding.
    my $out;
    if ( eval { $out = decode( 'UTF-8', $in, 1 ); return 1 } ) {
        utf8::upgrade($out);
        return $out;
    }

    # Finally just give up and return it.

    utf8::upgrade($in);
    return $in;
}

sub _add_to_namespace {
    my ( $package, $attrname, $reader, $writer, $predicate ) = @_;
    $METHODS{$attrname} = {reader => $reader};
    if ($predicate) {
        $METHODS{$attrname}->{predicate} = $predicate;
    }
    {
        ## no critic (ProhibitProlongedStrictureOverride,ProhibitNoStrict)
        no strict 'refs';

        if ($TRADITIONAL_METHODS) {
            my $readwriter;
            if ($writer) {
                $readwriter = _generate_readwriter( $package, $reader, $writer );
                $METHODS{$attrname}->{writer} = $writer;
            } elsif ($reader) {
                $readwriter = $reader;
            }
            $METHODS{$attrname}->{readwriter} = $readwriter;
            if ($readwriter) { *{ $package . '::' . $attrname } = $readwriter; }
        }
        if ($PBP_METHODS) {
            if ($writer)    { *{ $package . '::set_' . $attrname } = $writer; }
            if ($reader)    { *{ $package . '::get_' . $attrname } = $reader; }
        }
        if ($TRADITIONAL_METHODS || $PBP_METHODS) {
            if ($predicate) { *{ $package . '::has_' . $attrname } = $predicate; }
        }
        ## use critic
    }
}

sub _get_method {
    my $self = shift;
    my $method = shift;
    my $attr = shift;
    if ((exists $METHODS{$attr}) && (ref $METHODS{$attr})) {
        return $METHODS{$attr}->{$method};
    }
    else {
        return sub {};
    }
}

sub _get_reader {
    my $self = shift;
    my $attr = shift;
    $self->_get_method('reader',$attr);
}

sub _get_writer {
    my $self = shift;
    my $attr = shift;
    $self->_get_method('writer',$attr);
}

sub _get_predicate {
    my $self = shift;
    my $attr = shift;
    $self->_get_method('predicate',$attr);
}

sub _do_method {
    my $self = shift;
    my $method = shift;
    my $attr = shift;
    my @p = @_;
    &{$self->_get_method($method,$attr)}($self,@p);
}

sub get_data {
    my $self = shift;
    my @opts = @_;
    $self->_do_method('reader',@opts);
}

sub set_data {
    my $self = shift;
    my @opts = @_;
    $self->_do_method('writer',@opts);
}

sub has_data {
    my $self = shift;
    my @opts = @_;
    $self->_do_method('predicate',@opts);
}

sub _generate_reader {
    my ( $package, $attr, $options ) = @_;
    my $default   = $options->{default}     || undef;
    my $trigger   = $options->{readtrigger} || undef;
    my $outfilter = $options->{outfilter}   || undef;
    my $builder   = $options->{builder}     || undef;
    return sub {
        my $self = shift;
        if (   ( not exists $self->{data}->{$attr} )
            or ( not defined $self->{data}->{$attr} ) ) {
            if ($builder) {
                $self->{data}->{$attr} = &{$builder}($self);
            }
            else {
                return $default;
            }
        }
        if ($trigger) { &{$trigger}( $self, $self->{data}->{$attr} ); }
        return $outfilter
            ? &{$outfilter}( $self, $self->{data}->{$attr} )
            : $self->{data}->{$attr};
        }
}

sub _generate_writer {
    my ( $package, $attr, $options ) = @_;
    my $trigger   = $options->{trigger}   || undef;
    my $filter    = $options->{filter}    || undef;
    my $validator = $options->{validator} || undef;

    return sub {
        my ( $self, $value ) = @_;
        my $setvalue = $filter ? &{$filter}( $self, $value ) : $value;
        if ( ($validator) && ( !&{$validator}( $self, $value ) ) ) {
            $self->status(
                0,
                "Invalid value for $attr: ",
                ( defined $setvalue ) ? $setvalue : 'UNDEFINED'
            );
            return;
        }
        if ( $self->options('verbose') ) {
            $self->status(
                1,
                "Setting $attr to ",
                ( defined $setvalue ) ? $setvalue : 'UNDEFINED'
           );
        }
        $self->{data}->{$attr} = $setvalue;
        if ($trigger) { &{$trigger}( $self, $setvalue ); }
        return $self->{data}->{$attr};
        }
}

sub _generate_readwriter {
    my ( $package, $reader, $writer ) = @_;
    return sub {
        my ( $self, $value ) = @_;
        if ( defined $value ) {
            return &{$writer}( $self, $value );
        }
        else {
            return &{$reader}($self);
        }
    };
}

sub _generate_predicate {
    my ( $package, $attr, $options ) = @_;
    return sub {
        my $self = shift;
        return (   ( exists $self->{data}->{$attr} )
                && ( defined $self->{data}->{$attr} ) );
    };
}

sub _make_accessor {
    my ( $package, $attrname, $options ) = @_;
    my $attr = $options->{attr} || uc($attrname);
    my $reader = _generate_reader( $package, $attr, $options );
    my $writer;
    if ( !( ( exists $options->{readonly} ) && ( $options->{readonly} ) ) ) {
        $writer = _generate_writer( $package, $attr, $options );
    }
    my $predicate = _generate_predicate( $package, $attr, $options );
    _add_to_namespace( $package, $attrname, $reader, $writer, $predicate );
    return;
}

sub _make_datetime_accessor {
    my ( $package, $attrname, $options ) = @_;
    my $attr = $options->{attr} || uc($attrname);
    my $filter = sub {
        my ( $self, $value ) = @_;
        if ( defined $value ) {
            if ( $value =~ /^\-?\d+$/ ) {
                return DateTime->from_epoch( epoch => $value );
            }
            else {
                return DateTimeX::Easy->new($value);
            }
            $self->status( 0, "Invalid date set for ${attr}: ${value}" );
        }
        return;
    };
    $options->{filter}  = $filter;

    my $predicate = _generate_predicate( $package, $attr, $options );
    my $writer = _generate_writer( $package, $attr, $options );
    my $dt_reader = _generate_reader( $package, $attr, $options );
    _add_to_namespace( $package,
        ( $options->{dtname} ? $options->{dtname} : $attrname . 'dt' ),
        $dt_reader, $writer, $predicate );

    $options->{outfilter} = sub { my ( $self, $val ) = @_; return $val->ymd };
    my $date_reader = _generate_reader( $package, $attr, $options );
    _add_to_namespace(
        $package,
        ( $options->{datename} ? $options->{datename} : $attrname . 'date' ),
        $date_reader,
        $writer,
        $predicate
    );

    $options->{outfilter} =
        sub { my ( $self, $val ) = @_; return $val->ymd . ' ' . $val->hms };
    my $time_reader = _generate_reader( $package, $attr, $options );
    _add_to_namespace(
        $package,
        ( $options->{timename} ? $options->{timename} : $attrname . 'time' ),
        $time_reader,
        $writer,
        $predicate
    );

    $options->{outfilter} =
        sub { my ( $self, $val ) = @_; return $val->epoch };
    my $epoch_reader = _generate_reader( $package, $attr, $options );
    _add_to_namespace(
        $package,
        (     $options->{epochname}
            ? $options->{epochname}
            : $attrname . 'epoch'
        ),
        $epoch_reader,
        $writer,
        $predicate
    );
    return;
}

sub _make_ordinal_accessor {
    my ( $package, $attrname, $options ) = @_;
    my $attr = uc($attrname);
    my $pos  = $options->{pos_attr};
    if ( !$pos ) { croak("pos_attr required\n"); return }
    my $total = $options->{total_attr};
    if ( !$total ) { croak("total_attr required\n"); return }
    my $writer = sub {
        my ( $self, $new ) = @_;
        my ( $t, $tt ) = split( m{/}, $new );
        if ($t) {
            &{$self->_get_writer($pos)}($self,$t);
        }
        if ($tt) {
            &{$self->_get_writer($total)}($self,$tt);
        }
        return $new;
    };
    my $reader = sub {
        my $self = shift;
        my $m    = '_get_' . $pos;
        my $t    = &{$self->_get_reader($pos)}($self);
        my $tt    = &{$self->_get_reader($total)}($self);
        my $r  = '';
        if ($t) {
            $r .= $t;
        }
        if ($tt) {
            $r .= '/' . $tt;
        }
        return $r;
    };
    my $predicate = sub {
        my $self = shift;
        my ( $pp, $pt ) = ( 'has_' . $pos, 'has_' . $total );
        if ( $self->$pp || $self->$pt ) {
            return 1;
        }
        return;
    };
    _add_to_namespace( $package, $attrname, $reader, $writer, $predicate );
    return;
}

sub _make_list_accessor {
    my ( $package, $attrname, $options ) = @_;
    $options->{filter} = sub {
        my ( $self, $value ) = @_;
        my @ret = ();
        if ( ref $value ) {
            push @ret, @{$value};
        }
        else {
            push @ret, split( /\s*,\s*/, $value );
        }
        return \@ret;
    };
    _make_accessor( $package, $attrname, $options );
}

sub status {    ## no critic (Subroutines::RequireArgUnpacking)
    my $self = shift;
    if ( not $self->options('quiet') ) {
        my $name = ref($self);
        if ( $_[0] =~ /\:\:/ ) {
            $name = shift;
        }
        my $level = 0;
        if ( $_[0] =~ /^\d+$/ ) {
            $level = shift;
        }
        my $verbose = $self->options('verbose') || 0;
        if ( $level <= $verbose ) {
            $name =~ s/^Music::Tag:://g;
            print $self->_tenprint( $name, 'bold white', $TENPRINT_SIZE ), @_,
                "\n";
        }
    }
    return;
}

sub _tenprint {
    my $self   = shift;
    my $text   = shift;
    my $_color = shift || 'bold yellow';
    my $size   = shift || $TENPRINT_SIZE;
    return
          $self->_color($_color)
        . sprintf( '%' . $size . 's: ', substr( $text, 0, $size ) )
        . $self->_color('reset');
}

sub _color {    ## no critic (Subroutines::RequireArgUnpacking)
    my $self = shift;
    if ( $self->options->{ANSIColor} ) {
        return Term::ANSIColor::color(@_);
    }
    else {
        return '';
    }
}

sub error {     ## no critic (Subroutines::RequireArgUnpacking)
    my $self = shift;

    # unless ( $self->options('quiet') ) {
    carp( ref($self), ' ', @_ );

    # }
    return;
}

sub _create_attributes {
    my $package = shift;
    my $params = shift;

    if ($params->{pbp}) {
        $PBP_METHODS = 1;
        $TRADITIONAL_METHODS = 0;
    }
    if ($params->{traditional}) {
        $TRADITIONAL_METHODS = 1;
    }
    
    if (ref $package) { $package = ref $package; }
    my @datamethods = qw(
        album album_type albumartist albumartist_sortname albumid appleid
        artist artist_end artist_start artist_start_time artist_start_epoch
        artist_end_time artist_end_epoch artist_type artistid asin bitrate
        booklet bytes codec comment compilation composer copyright country
        countrycode disc discnum disctitle duration encoded_by encoder filename
        frames framesize frequency gaplessdata genre ipod ipod_dbid
        ipod_location ipod_trackid label lastplayedtime lastplayeddate
        lastplayedepoch lyrics mb_albumid mb_artistid mb_trackid mip_puid
        mtime mdate mepoch originalartist performer path picture playcount
        postgap pregap rating albumrating recorddate recordtime releasedate
        releasetime recordepoch releaseepoch samplecount secs songid sortname
        stereo tempo title totaldiscs totaltracks track tracknum url user vbr
        year upc ean jan filetype mip_fingerprint artisttags albumtags
        tracktags);

    %DataMethods = map { $_ => { readwrite => 1 } } @datamethods;

    ## no critic (ProtectPrivateSubs)

    $package->_make_accessor(
        'albumartist' => {
            builder => sub { my $self = shift; return $self->artist() }
        }
    );
    $package->_make_accessor(
        'albumartist_sortname' => {
            builder => sub { my $self = shift; return $self->sortname() }
        }
    );
    $package->_make_list_accessor( 'albumtags'  => {} );
    $package->_make_list_accessor( 'artisttags' => {} );
    $package->_make_accessor(
        'country' => {
            attr   => 'COUNTRYCODE',
            filter => sub {
                my ( $self, $new ) = @_;
                return country2code($new);
            },
            outfilter => sub {
                my ( $self, $value ) = @_;
                return code2country($value);
                }
        }
    );
    $package->_make_ordinal_accessor(
        'discnum',
        {   pos_attr   => 'disc',
            total_attr => 'totaldiscs',
        }
    );
    $package->_make_accessor(
        'secs',
        {   attr   => 'DURATION',
            filter => sub {
                my ( $self, $new ) = @_;
                return $new * 1000;
            },
            outfilter => sub {
                my ( $self, $value ) = @_;
                return int( $value / 1000 );
                }
        }
    );
    $package->_make_accessor(
        'ean',
        {   validator => sub {
                my ( $self, $value ) = @_;
                return $value =~ /^\d{13}$/;
            },
            alias => [qw(jan)],
        }
    );
    $package->_make_accessor(
        'filename',
        {   filter => sub {
                my ( $self, $new ) = @_;
                return File::Spec->rel2abs($new);
                }
        }
    );
    $package->_make_accessor(
        'filedir',
        {   attr      => 'FILENAME',
            outfilter => sub {
                my ( $self, $value ) = @_;
                my ( $vol, $path, $file ) = File::Spec->splitpath($value);
                return File::Spec->catpath( $vol, $path, '' );
            },
            readonly => 1,
        }
    );
    $package->_make_accessor( 'artist', { alias => [qw(performer)] } );

    $package->_make_list_accessor( 'tracktags' => {} );

    $package->_make_ordinal_accessor(
        'tracknum',
        {   pos_attr   => 'track',
            total_attr => 'totaltracks',
        }
    );

    $package->_make_accessor(
        'upc',
        {   attr      => 'EAN',
            validator => sub {
                my ( $self, $value ) = @_;
                return $value =~ /^\d{13}$/;
            },
            filter => sub {
                my ( $self, $value ) = @_;
                return ( '0' . $value );
            },
            outfilter => sub {
                my ( $self, $value ) = @_;
                $value =~ s/^0//;
                return $value;
                }
        }
    );

    $package->_make_datetime_accessor(
        'record' => {
            trigger => sub {
                my ( $self, $value ) = @_;
                if ( $value->isa('DateTime') ) {
                    $self->set_year( $value->year );
                }
                }
        }
    );
    $package->_make_datetime_accessor( 'release' => {} );
    $package->_make_datetime_accessor( 'm'       => {} );
    $package->_make_datetime_accessor('lastplayed');
    $package->_make_datetime_accessor(
        'artist_start' => {
            timename  => 'artist_start_time',
            datename  => 'artist_start',
            epochname => 'artist_start_epoch',
            dtname    => 'artist_start_dt',
        }
    );
    $package->_make_datetime_accessor(
        'artist_end' => {
            timename  => 'artist_end_time',
            datename  => 'artist_end',
            epochname => 'artist_end_epoch',
            dtname    => 'artist_end_dt',
        }
    );

    $package->_make_accessor(
        'year' => {
            builder => sub {
                my $self = shift;
                if ( $self->has_releasedt ) {
                    return $self->releasedt->year;
                }
                }
        }
    );

    $METHODS{'picture'} = {
        reader => \&get_picture,
        writer => \&set_picture,
        predicate => \&has_picture,
    };


    foreach my $m (@datamethods) {
        if ( ! exists $METHODS{$m}) {
            $package->_make_accessor( $m => {} );
        }
    }
    ## use critic
}

sub _find_plugins {
    my $package = shift;
    if (ref $package) { $package = ref $package; }
    my $me = $package;
    $me =~ s{::}{/}g;
    @PLUGINS = ();
    foreach my $d (@INC) {
        chomp $d;
        if ( -d "$d/$me/" ) {
            my $fdir = IO::Dir->new("$d/$me");
            if ( defined $fdir ) {
                while ( my $m = $fdir->read() ) {
                    next if $m eq 'Test.pm';
                    if ( $m =~ /^(.*)\.pm$/ ) {
                        my $mod = $1;
                        push @PLUGINS, $mod;
                    }
                }
            }
            $fdir->close();
        }
    }

}

sub import {
    my $package = shift;
    my $params = {};
    if    ( ref $_[0] )      { $params = $_[0]; }
    elsif ( !scalar @_ % 2 ) { $params = {@_}; }
    $package->_create_attributes($params);
    $package->_find_plugins($params);
    return 1;
}

BEGIN {
    $DefaultOptions = Config::Options->new(
        {   verbose       => 0,
            quiet         => 0,
            ANSIColor     => 0,
            LevenshteinXS => 1,
            Levenshtein   => 1,
            Unaccent      => 1,
            Inflect       => 0,
            optionfile =>
                [ '/etc/musictag.conf', $ENV{HOME} . '/.musictag.conf' ],
        }
    );
}

sub DESTROY {
    my $self = shift;
    $self->_foreach_plugin( sub { $_[0]->{info} = undef } );
    return;
}

1;
__END__
=pod

=head1 NAME

Music::Tag - Interface for collecting information about music files.

=head1 VERSION

Music-Tag-0.4103

=for readme stop

=head1 SYNOPSIS

    use Music::Tag (traditional => 1);

    my $info = Music::Tag->new($filename);
   
    # Read basic info

    $info->get_tag();
   
    print 'Performer is ', $info->artist();
    print 'Album is ', $info->album();
    print 'Release Date is ', $info->releasedate();

    # Change info
   
    $info->artist('Throwing Muses');
    $info->album('University');
   
    # Augment info from an online database!
   
    $info->add_plugin('MusicBrainz');
    $info->add_plugin('Amazon');

    $info->get_tag();

    print 'Record Label is ', $info->label();

    # Save back to file

    $info->set_tag();
    $info->close();

=for readme continue

=head1 DESCRIPTION

Extendable module for working with Music Tags. Music::Tag Is powered by 
various plugins that collect data about a song based on whatever information
has already been discovered.  

The motivation behind this was to provide a convenient method for fixing broken
tags in music files. This developed into a universal interface to various music 
file tagging schemes and a convenient way to augment this from online databases.

Several plugin modules to find information about a music file and write it back 
into the tag are available. These modules will use available information 
(B<REQUIRED DATA VALUES> and B<USED DATA VALUES>) and set various data values 
back to the tag.

=begin readme

=head1 INSTALLATION

To install this module type the following:

   perl Makefile.PL
   make
   make test
   make install

=head2 IMPORTANT NOTE

If you have installed older versions (older than .25) PLEASE delete the 
following scripts from your bin folder: autotag, safetag, quicktag, 
musicsort, musicinfo.  

If you used any of these scripts, create a symbolic link to musictag for each.

=head2 QUICK INSTALL OF ALL PACKAGES

A bundle is available to quickly install Music::Tag with all plugins. To
install it use:

   perl -MCPAN -eshell

At the cpan shell prompt type:

   install Bundle::Music::Tag

=head1 DEPENDENCIES

This module requires these other modules and libraries:

   Encode
   File::Spec
   Locale::Country
   Digest::SHA1
   Config::Options
   Time::Local
   Test::More
   File::Copy
   File::Slurp
   File::stat
   IO::File
   Scalar::Util
   DateTimeX::Easy

I strongly recommend the following to improve web searches:

   Lingua::EN::Inflect
   Text::LevenshteinXS
   Text::Unaccent::PurePerl

The following just makes things pretty:

   Term::ANSIColor

=end readme

=head1 EXECUTABLE SCRIPT

An executable script, L<musictag> is included.  This script allows quick 
tagging of MP3 files and access to the plugins.  To learn more, use:

   musictag --help 
   musictag --longhelp

=for readme stop

=head1 METHODS

=over 4

=item B<new()>

Takes a filename, an optional hashref of options, and an optional first plugin
and returns a new Music::Tag object.  For example: 

    my $info = Music::Tag->new($filename, { quiet => 1 }, 'MP3' ) ;

If no plugin is listed, then it will automatically add the appropriate file 
plugin based on the extension. It does this by using the L<Music::Tag::Auto> 
plugin. If no plugin is appropriate, it will return.  

Options are global (apply to all plugins) and default (can be overridden by 
a plugin).

Plugin specific options can be applied here, if you wish. They will be ignored
by plugins that don't know what to do with them. See the POD for each of the 
plugins for more details on options a particular plugin accepts.

B<Current global options include:>

=over 4

=item B<verbose>

Default is false. Setting this to true causes plugin to generate a lot of noise.

=item B<quiet>

Default is false. Setting this to true prevents the plugin from giving status 
messages.  This default may be changed in the future, so always set it.

=item B<autoplugin>

Option is a hash reference mapping file extensions to plugins. Technically, 
this option is for the L<Music::Tag::Auto> plugin. Default is: 

    {   mp3   => 'MP3',
        m4a   => 'M4A',
        m4p   => 'M4A',
        mp4   => 'M4A',
        m4b   => 'M4A',
        '3gp' => 'M4A',
        ogg   => 'OGG',
        flac  => 'FLAC'   }

=item B<optionfile>

Array reference of files to load options from. Default is:

    [   '/etc/musictag.conf',   
        $ENV{HOME} . '/.musictag.conf'  ]

Note that this is only used if the 'load_options' method is called. 

Option file is a pure perl config file using L<Config::Options>.

=item B<ANSIColor>

Default false. Set to true to enable color status messages.

=item B<LevenshteinXS>

Default true. Set to true to use Text::LevenshteinXS to allow approximate 
matching with Amazon and MusicBrainz Plugins. Will reset to false if module 
is missing.

=item B<Levenshtein>

Default true. Same as LevenshteinXS, but with Text::Levenshtein. Will not use 
if Text::Levenshtein can be loaded. Will reset to false if module is missing.

=item B<Unaccent>

Default true. When true, allows accent-neutral matching with 
Text::Unaccent::PurePerl. Will reset to false if module is missing.

=item B<Inflect>

Default false. When true, uses Lingua::EN::Inflect to perform approximate 
matches. Will reset to false if module is missing.

=back

=item B<available_plugins()>

Class method. Returns list of available plugins. For example:

    foreach (Music::Tag->available_plugins) {
        if ($_ eq 'Amazon') {
            print "Amazon is available!\n";
            $info->add_plugin('Amazon', { locale => 'uk' });
        }
    }

This method can also be used to check for a particular plugin, by passing
an option.  For example:

    if (Music::Tag->avaialble_plugins('Amazon') {
        print "Amazon is available!\n";
        $info->add_plugin('Amazon', { locale => 'uk' });
    }

=item B<default_options()>

Class method. Returns default options as a L<Config::Options|Config::Options>
object.

=item B<LoadOptions()>

Load options stated in optionfile from file. Default locations are 
/etc/musictag.conf and ~/.musictag.conf.  Can be called as class method or 
object method. If called as a class method the default values for all future
Music::Tag objects are changed.  

=item B<add_plugin()>

Takes a plugin name and optional set of options. Returns reference to a new 
plugin object. For example:

    my $plugin = $info->add_plugin('MusicBrainz', 
								   { preferred_country => 'UK' });

$options is a hashref that can be used to override the global options for a 
plugin.

First option can be a string such as "MP3" in which case 
Music::Tag::MP3->new($self, $options) is called, an object name such as 
"Music::Tag::Custom::MyPlugin" in which case 
Music::Tag::MP3->new($self, $options) is called,
or an object, which is added to the list.

Current plugins include L<MP3|Music::Tag::MP3>, L<OGG|Music::Tag::OGG>, 
L<FLAC|Music::Tag::FLAC>, L<M4A|Music::Tag::M4A>, L<Amazon|Music::Tag::Amazon>, 
L<File|Music::Tag::File>, L<MusicBrainz|Music::Tag::MusicBrainz>, 
and L<LyricsFetcher|Music::Tag::LyricsFetcher>.  

Additional plugins can be created and may be available on CPAN.  
See L<Music::Tag::Generic|Music::Tag::Generic> for base class for plugins.

Options can also be included in the string, as in Amazon;locale=us;trust_title=1.
This was added to make calling from L<musictag|musictag> easier.

=item B<plugin()>

my $plugin = $item->plugin('MP3')->strip_tag();

The plugin method takes a regular expression as a string value and returns the
first plugin whose package name matches the regular expression. Used to access 
package methods directly. Please see L</"PLUGINS"> section for more details on 
standard plugin methods.

=item B<get_tag()>

get_tag applies all active plugins to the current Music::Tag object in the 
order that the plugin was added. Specifically, it runs through the list of 
plugins and performs the get_tag() method on each.  For example:

    $info->get_tag();

=item B<set_tag()>

set_tag writes info back to disk for all Music::Tag plugins, or submits info 
if appropriate. Specifically, it runs through the list of plugins and performs 
the set_tag() method on each. For example:

    $info->set_tag();

=item B<strip_tag()>

strip_tag removes info from on disc tag for all plugins. Specifically, it 
performs the strip_tag method on all plugins in the order added. For example:

    $info->strip_tag();

=item B<close()>

Closes active filehandles on all plugins. Should be called before object 
destroyed or frozen. For example: 

    $info->close();

=item B<changed()>

Returns true if changed. Optional value $new sets changed set to True of $new 
is true. A "change" is any data-value additions or changes done by MusicBrainz, 
Amazon, File, or Lyrics plugins. For example:

    # Check if there is a change:
    $ischanged = $info->changed();

    # Force there to be a change
    $info->changed(1);


=item B<data()>

Returns a reference to the hash which stores all data about a track and 
optionally sets it.  This is useful if you want to freeze and recreate a track, 
or use a shared data object in a threaded environment. For example;

    use Data::Dumper;
    my $bighash = $info->data();
    print Dumper($bighash);

Please note that some values, specifically date values, will be objects.

=item B<options()>

This method is used to access or change the options. When called with no 
options, returns a reference to the options hash. When called with one string 
option returns the value for that key. When called with one hash value, merges 
hash with current options. When called with 2 options, the first is a key and 
the second is a value and the key gets set to the value. This method is for 
global options. For example:

    # Get value for "verbose" option
    my $verbose = $info->options('verbose');

    # or...
    my $verbose = $info->options->{verbose};

    # Set value for "verbose" option
    $info->options('verbose', 0);

    # or...
    $info->options->{verbose} = 0;

=item B<setfileinfo>

Sets the mtime and bytes attributes for you from filename. This may be
moved to the L<File|Music::Tag::File> plugin in the future. 

=item B<sha1()>

Returns a sha1 digest of the file size in little endian then the first 16K of 
the music file. Should be fairly unique. 

=item B<datamethods()>

Returns an array reference of all data methods supported.  Optionally takes a 
method which is added.  Data methods should be all lower case and not conflict 
with existing methods. Data method additions are global, and not tied to an 
object. Array reference should be considered read only. For example:


    # Print supported data methods:
    my $all_methods = Music::Tag->datamethods();
    foreach (@{$all_methods}) {
        print '$info->'. $_ . " is supported\n";
    }

    # Add is_hairband data method:
    Music::Tag->datamethods('is_hairband');

=item B<used_datamethods()>

Returns an array reference of all data methods that have values set.
For example:

    my $info = Music::Tag->new($filename);
    $info->get_tag();
    foreach (@{$info->used_datamethods}) {
        print $_ , ': ', $info->$_, "\n";
    }


=item B<wav_out($fh)>

Pipes audio data as a wav file to filehandle $fh. Returns true on success, false on failure, undefined if no plugin supports this.

This is currently experimental.

=back

=head2 Data Access Methods

These methods are used to access the Music::Tag data values. Not all methods are supported by all plugins. In fact, no single plugin supports all methods (yet). Each of these is an accessor function. If you pass it a value, it will set the variable. It always returns the value of the variable.

There are three distinct ways of calling these methods: Traditional, PBP, and using the L</"get_data">, L</"set_data">, and L</"has_data"> methods. 

Damian Conway in his book "Perl Best Practices" states that data access methods should be called with separate methods for getting and setting values.  This can be configured by passing pbp => 1 to the use option, e.g.
    
    use Music::Tag ( pbp => 1 );

Once set, data can be accessed by adding get_ as a suffix to the method, written to by adding set__ as a suffix, and checked by adding has_ as a suffix. For example:


    use Music::Tag ( pbp => 1 );

    use feature qw(say);

    my $info = Music::Tag->new($filename);
   
    # Read basic info

    $info->get_tag();
  
    if ($info->has_artist()) {
        say 'Performer is ', $info->get_artist();
    }
   
    $info->set_artist('Throwing Muses');

    if ($info->has_artist()) {
        say 'Performer is now: ', $info->get_artist();
        # Will print 'Throwing Muses'
    }

    $info->set_tag();
    $info->close();

To force Traditional, add traditional => 1 as an option, e.g.

    use Music::Tag (traditional => 1);

You can have pbp and traditional set to get both, if you want.  Please note that calling it more than once in the same program, or set of programs, will have the affect of reading the methods.  For example


    use Music::Tag (traditional => 1);
    use Music::Tag (pbp => 1);

    # is the same as
    
    use Music::Tag (traditional =>1, pbp=>1)

When using the traditional methods, an undefined function will return undef.  This means that in list context, it will be true even when empty. This also means that the following code works:

	my %important = (
		artist		=> $info->artist,
		album		=> $info->album,
		filename	=> $info->filename,
	);

The best way to determine if a method is defined, is to use the predicate method (e.g. has_album).  This is defined if either traditional or pbp is set to true.

The final way to access data is to use the L</"get_data">, L</"set_data">, and L</"has_data"> methods. These will work even if pbp and traditional are both set to 0.  This is how plugins should access data methods.

Here is a list of the current supported data methods:

=over 4

=item B<album>, get_album, set_album, has_album

The title of the release.

=item B<album_type>, get_album_type, set_album_type, has_album_type

The type of the release. Specifically, the MusicBrainz type (ALBUM OFFICIAL, etc.) 

=item B<albumartist>, get_albumartist, set_albumartist, has_albumartist

The artist responsible for the album. Usually the same as the artist, and will return the value of artist if unset.

=item B<albumartist_sortname>, get_albumartist_sortname, set_albumartist_sortname, has_albumartist_sortname

The name of the sort-name of the albumartist (e.g. Hersh, Kristin or Throwing Muses, The)

=item B<albumtags>, get_albumtags, set_albumtags, has_albumtags

A array reference or comma separated list of tags in plain text for the album.

=item B<albumrating>, get_albumrating, set_albumrating, has_albumrating

The rating (value is 0 - 100) for the album (not supported by any plugins yet).

=item B<artist>, get_artist, set_artist, has_artist

The artist responsible for the track. This should be the performer.

=item B<artist_start>, get_artist_start, set_artist_start, has_artist_start

The date the artist was born or a group was founded. Sets artist_start_time and artist_start_epoch.

=item B<artist_start_dt>, get_artist_start_dt, set_artist_start_dt, has_artist_start_dt

The DateTime object used internally. 

=item B<artist_start_time>, get_artist_start_time, set_artist_start_time, has_artist_start_time

The time the artist was born or a group was founded. Sets artist_start and artist_start_epoch

=item B<artist_start_epoch>, get_artist_start_epoch, set_artist_start_epoch, has_artist_start_epoch

The number of seconds since the epoch when artist was born or a group was founded. Sets artist_start and artist_start_time

See release_epoch.

=item B<artist_end>, get_artist_end, set_artist_end, has_artist_end

The date the artist died or a group was disbanded. Sets artist_end_time and artist_end_epoch.

=item B<artist_end_dt>, get_artist_end_dt, set_artist_end_dt, has_artist_end_dt

The DateTime object used internally. 

=item B<artist_end_time>, get_artist_end_time, set_artist_end_time, has_artist_end_time

The time the artist died or a group was disbanded. Sets artist_end and artist_end_epoch

=item B<artist_end_epoch>, get_artist_end_epoch, set_artist_end_epoch, has_artist_end_epoch

The number of seconds since the epoch when artist died or a group was disbanded. Sets artist_end and artist_end_time

See release_epoch.

=item B<artisttags>, get_artisttags, set_artisttags, has_artisttags

A array reference or comma separated list of tags in plain text for the artist. Always returns a list.

=item B<artist_type>, get_artist_type, set_artist_type, has_artist_type

The type of artist. Usually Group or Person. 

=item B<asin>, get_asin, set_asin, has_asin

The Amazon ASIN number for this album.

=item B<bitrate>, get_bitrate, set_bitrate, has_bitrate

Bitrate of file (average).

=item B<booklet>, get_booklet, set_booklet, has_booklet

URL to a digital booklet. Usually in PDF format. iTunes passes these out sometimes, or you could scan a booklet
and use this to store value. B<URL is assumed to be relative to file location>.

=pod

=item B<bytes>, get_bytes, set_bytes, has_bytes

Filesize in bytes

=item B<comment>, get_comment, set_comment, has_comment

A comment about the track.

=item B<compilation>, get_compilation, set_compilation, has_compilation

True if album is Various Artist, false otherwise. I don't set this to true for Best Hits, iTunes sometimes does.

=item B<composer>, get_composer, set_composer, has_composer

Composer of song.

=item B<copyright>, get_copyright, set_copyright, has_copyright

A copyright message can be placed here.

=item B<country>, get_country, set_country, has_country

Return the country that the track was released in. Stored as countrycode, so must be a valid country.

=item B<countrycode>, get_countrycode, set_countrycode, has_countrycode

The two digit country code. 

=item B<disc>, get_disc, set_disc, has_disc

In a multi-volume set, the disc number.

=item B<disctitle>, get_disctitle, set_disctitle, has_disctitle

In a multi-volume set, the title of a disc.

=item B<discnum>, get_discnum, set_discnum, has_discnum

The disc number and optionally the total number of discs, separated by a slash. Setting it sets the disc and totaldiscs values.

=item B<duration>, get_duration, set_duration, has_duration

The length of the track in milliseconds. Returns secs * 1000 if not set. Changes the value of secs when set.

=item B<ean>, get_ean, set_ean, has_ean

The European Article Number on the package of product.  Must be the EAN-13 (13 digits 0-9).

=item B<encoded_by>, get_encoded_by, set_encoded_by, has_encoded_by

Person or company responsible for making the music file.

=item B<encoder>, get_encoder, set_encoder, has_encoder

The codec used to encode the song.

=item B<filename>, get_filename, set_filename, has_filename

The filename of the track.

=item B<filedir>, get_filedir, set_filedir, has_filedir

The path that music file is located in.

=item B<filetype>, get_filetype, set_filetype, has_filetype

Name of plugin used to read and store data directly to file.


=item B<genre>, get_genre, set_genre, has_genre

The genre of the song. Various music tagging schemes use this field differently.  It should be text and not a code.  As a result, some
plugins may be more restrictive in what can be written to disk,

=item B<jan>, get_jan, set_jan, has_jan

Same as ean.

=item B<label>, get_label, set_label, has_label

The label responsible for distributing the recording.

=item B<lastplayeddate>, get_lastplayeddate, set_lastplayeddate, has_lastplayeddate

The date the song was last played.

=item B<lastplayeddt>, get_lastplayeddt, set_lastplayeddt, has_lastplayeddt

The DateTime object used internally. 

=item B<lastplayedtime>, get_lastplayedtime, set_lastplayedtime, has_lastplayedtime

The time the song was last played.

=item B<lastplayedepoch>, get_lastplayedepoch, set_lastplayedepoch, has_lastplayedepoch

The number of seconds since the epoch the time the song was last played.

See release_epoch.

=item B<lyrics>, get_lyrics, set_lyrics, has_lyrics

The lyrics of the recording.

=item B<originalartist>, get_originalartist, set_originalartist, has_originalartist

Original artist who recorded the song, e.g. for a cover song.

=item B<mdate>, get_mdate, set_mdate, has_mdate

The date the file was last modified.

=item B<mdt>, get_mdt, set_mdt, has_mdt

The DateTime object used internally. 

=item B<mtime>, get_mtime, set_mtime, has_mtime

The time the file was last modified.

=item B<mepoch>, get_mepoch, set_mepoch, has_mepoch

The number of seconds since the epoch the time the file was last modified.

=item B<mb_albumid>, get_mb_albumid, set_mb_albumid, has_mb_albumid

The MusicBrainz database ID of the album or release object.

=item B<mb_artistid>, get_mb_artistid, set_mb_artistid, has_mb_artistid

The MusicBrainz database ID for the artist.

=item B<mb_trackid>, get_mb_trackid, set_mb_trackid, has_mb_trackid

The MusicBrainz database ID for the track.

=item B<mip_puid>, get_mip_puid, set_mip_puid, has_mip_puid

The MusicIP puid for the track.

=item B<mip_fingerprint>, get_mip_fingerprint, set_mip_fingerprint, has_mip_fingerprint

The Music Magic fingerprint

=item B<performer>, get_performer, set_performer, has_performer

The performer. This is an alias for artist.

=item B<picture>, get_picture, set_picture, has_picture

A hashref that contains the following:

     {
       'MIME type'     => The MIME Type of the picture encoding
       'Picture Type'  => What the picture is off.  Usually set to 'Cover (front)'
       'Description'   => A short description of the picture
       '_Data'         => The binary data for the picture.
       'filename'      => A filename for the picture.  Data overrides '_Data' and will
                          be returned as _Data if queried.  Filename is calculated as relative
                          to the path of the music file as stated in 'filename' or root if no
                          filename for music file available.
    }


Note hashref MAY be generated each call.  Do not modify and assume data-value in object will be modified!  Passing a value
will modify the data-value as expected. In other words:

    # This works:
    $info->picture( { filename => 'cover.jpg' } ) ;

    # This may not:
    my $pic = $info->picture;
    $pic->{filename} = 'back_cover.jpg';

=item B<picture_filename>, get_picture_filename, set_picture_filename, has_picture_filename

Returns filename used for picture data.  If no filename returns 0.  If no picture returns undef. 
If a value is passed, sets the filename. The filename is path relative to the music file.

=item B<picture_exists>, get_picture_exists, set_picture_exists, has_picture_exists

Returns true if Music::Tag object has picture data (or filename), false if not. Convenience method to prevent reading the file. 
Will return false of filename listed for picture does not exist.

=item B<playcount>, get_playcount, set_playcount, has_playcount

Playcount

=item B<rating>, get_rating, set_rating, has_rating

The rating (value is 0 - 100) for the track.

=item B<recorddate>, get_recorddate, set_recorddate, has_recorddate

The date track was recorded (not release date).  See notes in releasedate for format.

=item B<recorddt>, get_recorddt, set_recorddt, has_recorddt

The DateTime object used internally. 

=item B<recordepoch>, get_recordepoch, set_recordepoch, has_recordepoch

The recorddate in seconds since epoch.  See notes in releaseepoch for format.

=item B<recordtime>, get_recordtime, set_recordtime, has_recordtime

The time and date track was recoded.  See notes in releasetime for format.

=item B<releasedate>, get_releasedate, set_releasedate, has_releasedate

The release date in the form YYYY-MM-DD.  The day or month values may be left off.  Please keep this in mind if you are parsing this data.

Because of bugs in my own code, I have added 2 sanity checks.  Will not set the time and return if either of the following are true:

=over 4

=item 1) Time is set as 0000-00-00

=item 2) Time is set as 1900-00-00

=back

All times should be GMT.

=item B<releasedt>, get_releasedt, set_releasedt, has_releasedt

The DateTime object used internally. 


=item B<releaseepoch>, get_releaseepoch, set_releaseepoch, has_releaseepoch

The release date of an album in terms "UNIX time", or seconds since the SYSTEM 
epoch (usually Midnight, January 1, 1970 GMT). This can be negative or > 32 bits,
so please use caution before assuming this value is a valid UNIX date. This value 
will update releasedate and vice-versa.  Since this accurate to the second and 
releasedate only to the day, setting releasedate will always set this to 12:00 PM 
GMT the same day. 

Please note that this has some limitations. In 32bit Linux, the only supported
dates are Dec 1901 to Jan 2038. In windows, dates before 1970 will not work. 
Refer to the docs for Time::Local for more details.

=item B<releasetime>, get_releasetime, set_releasetime, has_releasetime

Like releasedate, but adds the time.  Format should be YYYY-MM-DD HH::MM::SS.  Like releasedate, all entries but year
are optional.

All times should be GMT.

=item B<secs>, get_secs, set_secs, has_secs

The number of seconds in the recording.

=item B<sortname>, get_sortname, set_sortname, has_sortname

The name of the sort-name of the artist (e.g. Hersh, Kristin or Throwing Muses, The)

=item B<tempo>, get_tempo, set_tempo, has_tempo

The tempo of the track

=item B<title>, get_title, set_title, has_title

The name of the song.

=item B<totaldiscs>, get_totaldiscs, set_totaldiscs, has_totaldiscs

The total number of discs, if a multi volume set.

=item B<totaltracks>, get_totaltracks, set_totaltracks, has_totaltracks

The total number of tracks on the album.

=item B<track>, get_track, set_track, has_track

The track number

=item B<tracktags>, get_tracktags, set_tracktags, has_tracktags

A array reference or comma separated list of tags in plain text for the track.

=pod

=item B<tracknum>, get_tracknum, set_tracknum, has_tracknum

The track number and optionally the total number of tracks, separated by a slash. Setting it sets the track and totaltracks values (and vice-versa).

=item B<upc>, get_upc, set_upc, has_upc

The Universal Product Code on the package of a product. Returns same value as ean without initial 0 if ean has an initial 0. If set and ean is not set, sets ean and adds initial 0.  It is possible for ean and upc to be different if ean does not have an initial 0.

=item B<url>, get_url, set_url, has_url

A URL associated with the track (often a link to the details page on Amazon).

=item B<year>, get_year, set_year, has_year

The year a track was released. Returns year set in releasedate if available. Does not set releasedate.

=back

=head2 Non Standard Data Access Methods

These methods are not currently used by any standard plugin.  They may be used in the future, or by other plugins (such as a SQL plugin).  Included here to standardize expansion methods.

=over 4

=item B<albumid, artistid, songid>, get_albumid, get_artistid, get_songid, set_albumid, set_artistid, set_songid, has_albumid, has_artistid, has_songid

These three values can be used by a database plugin. They should be GUIDs like the MusicBrainz IDs. I recommend using the same value as mb_albumid, mb_artistid, and mb_trackid by default when possible.

=item B<ipod, ipod_dbid, ipod_location, ipod_trackid>, get_ipod, get_ipod_dbid, get_ipod_location, get_ipod_trackid, set_ipod, set_ipod_dbid, set_ipod_location, set_ipod_trackid, has_ipod, has_ipod_dbid, has_ipod_location, has_ipod_trackid

Suggested values for an iPod plugin.

=pod

=item B<user>, get_user, set_user, has_user

Used for user data. Reserved. Please do not use this in any Music::Tag plugin published on CPAN.

=back

=head2 MP3 File information

=over 4

=item B<frequency>, get_frequency, set_frequency, has_frequency

The frequency of the recording (in Hz).

=item B<frames>, get_frames, set_frames, has_frames

Number of frames for an MP3 file.

=item B<framesize>, get_framesize, set_framesize, has_framesize

Average framesize for an MP3 file.

=item B<path>, get_path, set_path, has_path

Path of file, but not set by filename so could be used for a relative path.

=item B<stereo>, get_stereo, set_stereo, has_stereo

File is stereo.

=item B<vbr>, get_vbr, set_vbr, has_vbr

File has a variable bitrate.

=item B<pregap, postgap, gaplessdata, samplecount, appleid>, get_pregap, get_postgap, get_gaplessdata, get_samplecount, get_appleid, set_pregap, set_postgap, set_gaplessdata, set_samplecount, set_appleid, has_pregap, has_postgap, has_gaplessdata, has_samplecount, has_appleid

Used to store gapless data.  Some of this is supported by L<Music::Tag::MP3> as an optional value requiring a patched
L<MP3::Info>.

=item B<codec>, get_codec, set_codec, has_codec

Codec used for encoding file


=back

=head2 Semi-internal methods for use by plugins.

=over 4

=item B<status>

Semi-internal method for printing status.

=item B<error>

Semi-internal method for printing errors.

=item B<get_data()>

Calls the data access method for an attribute.  This is the recommended way to
access data from a plugin, as the user may have elected to have PBP attribute
methods, or not...

Example:

    # Get the album artist
    $info->get_data('albumartist');


=item B<set_data()>

Calls the data writer method for an attribute.

Example:

    # Set the album artist
    $info->set_data('albumartist','Sarah Slean');

=item B<has_data()>

Calls the data predicate method for an attribute.

Example:

    # Does it have an album artist?
    if ( not $info->has_data('albumartist')) {
        $info->set_data('albumartist','Sarah Slean');
    }

=back

=head1 PLUGINS

See L<Music::Tag::Generic|Music::Tag::Generic> for base class for plugins.

=head1 BUGS

No method for evaluating an album as a whole, only track-by-track method.  
Several plugins do not support all data values. Has not been tested in a 
threaded environment.

Please use github for bug tracking: L<http://github.com/riemann42/Music-Tag/issues|http://github.com/riemann42/Music-Tag/issues>.


=head1 SEE ALSO 

L<Music::Tag::Amazon>, L<Music::Tag::File>, L<Music::Tag::FLAC>, 
L<Music::Tag::Lyrics>, L<Music::Tag::LyricsFetcher>, L<Music::Tag::M4A>, 
L<Music::Tag::MP3>, L<Music::Tag::MusicBrainz>, L<Music::Tag::OGG>, 
L<Music::Tag::Option>, L<Term::ANSIColor>, L<Text::LevenshteinXS>, 
L<Text::Unaccent::PurePerl>, L<Lingua::EN::Inflect>

=for readme continue

=head1 SOURCE

Source is available at github: L<http://github.com/riemann42/Music-Tag|http://github.com/riemann42/Music-Tag>.

=head1 AUTHOR 

Edward Allen III <ealleniii _at_ cpan _dot_ org>

=head1 COPYRIGHT

Copyright © 2007,2008,2010 Edward Allen III. Some rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either:

a) the GNU General Public License as published by the Free
Software Foundation; either version 1, or (at your option) any
later version, or

b) the "Artistic License" which comes with Perl.

=begin readme

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either
the GNU General Public License or the Artistic License for more details.

You should have received a copy of the Artistic License with this
Kit, in the file named "Artistic".  If not, I'll be glad to provide one.

You should also have received a copy of the GNU General Public License
along with this program in the file named "Copying". If not, write to the
Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
Boston, MA 02110-1301, USA or visit their web page on the Internet at
http://www.gnu.org/copyleft/gpl.html.

=end readme

=cut
