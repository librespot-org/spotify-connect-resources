package DateTime::Format::Flexible;
use strict;
use warnings;

our $VERSION = '0.23';

use base 'DateTime::Format::Builder';

use DateTime::Format::Flexible::lang;
use DateTime::Infinite;

use Carp 'croak';

my $DELIM  = qr{(?:\\|\/|-|\.|\s)};
my $HMSDELIM = qr{(?:\.|:)};
my $YEAR = qr{(\d{1,4})};
my $MON = qr{(\d\d?)};
my $DAY = qr{(\d\d?)};
my $HOUR = qr{(\d\d?)};
my $HM = qr{(\d\d?)$HMSDELIM(\d\d?)};
my $HMS = qr{(\d\d?)$HMSDELIM(\d\d?)$HMSDELIM(\d\d?)};
my $HMSNS = qr{T?(\d\d?)$HMSDELIM(\d\d?)$HMSDELIM(\d\d?)$HMSDELIM(\d+)T?};
my $AMPM = qr{(a\.?m?|p\.?m?)\.?}i;

my $MMDDYYYY = qr{(\d{1,2})$DELIM(\d{1,2})$DELIM(\d{1,4})};
my $YYYYMMDD = qr{(\d{4})$DELIM(\d{1,2})$DELIM(\d{1,2})};
my $MMYY = qr{(\d{1,2})${DELIM}(\d{1,2})}; # YEAR must be > 31 unless MMYY
my $MMDD = qr{(\d{1,2})$DELIM(\d{1,2})};
my $XMMXDD = qr{X(\d{1,2})X${DELIM}?(\d{1,2})};
my $DDXMMX = qr{(\d{1,2})${DELIM}?X(\d{1,2})X};
my $DDXMMXYYYY = qr{(\d{1,2})${DELIM}X(\d{1,2})X$DELIM(\d{1,4})};
my $MMYYYY = qr{(\d{1,2})$DELIM(\d{4})};
my $XMMXYYYY = qr{X(\d{1,2})X${DELIM}(\d{4})};
my $XMMXDDYYYY = qr{X(\d{1,2})X${DELIM}?(\d{1,2})${DELIM}?(\d{1,4})};

my $HMSMD = [ qw( hour minute second month day ) ];
my $HMSMDY = [ qw( hour minute second month day year ) ];
my $HMSNSMDY = [ qw( hour minute second nanosecond month day year ) ];
my $HMSDM = [ qw( hour minute second day month ) ];
my $HMMDY = [ qw( hour minute month day year ) ];
my $HMMD = [ qw( hour minute month day ) ];
my $HMAPMMDD = [ qw( hour minute ampm month day ) ];
my $HMAPMMDDYYYY = [ qw( hour minute ampm month day year ) ];
my $DM = [ qw( day month ) ];
my $DMY = [ qw( day month year ) ];
my $DMHM = [ qw( day month hour minute ) ];
my $DMHMS = [ qw( day month hour minute second ) ];
my $DMHMSAP = [ qw( day month hour minute second ampm ) ];
my $DMYHM = [ qw( day month year hour minute ) ];
my $DMYHMS = [ qw( day month year hour minute second ) ];
my $DMYHMSNS = [ qw( day month year hour minute second nanosecond ) ];
my $DMYHMSAP = [ qw( day month year hour minute second ampm ) ];

my $M = [ qw( month ) ];
my $MD = [ qw( month day ) ];
my $MY = [ qw( month year ) ];
my $MDY = [ qw( month day year ) ];
my $MDHMS = [ qw( month day hour minute second ) ];
my $MDHMSAP = [ qw( month day hour minute second ampm ) ];
my $MYHMS = [ qw( month year hour minute second ) ];
my $MYHMSAP = [ qw( month year hour minute second ampm ) ];
my $MDYHMS = [ qw( month day year hour minute second ) ];
my $MDYHMAP = [ qw( month day year hour minute ampm ) ];
my $MDYHMSAP = [ qw( month day year hour minute second ampm ) ];
my $MDHMSY = [ qw( month day hour minute second year ) ];

my $Y = [ qw( year ) ];
my $YM = [ qw( year month ) ];
my $YMD = [ qw( year month day ) ];
my $YMDH = [ qw( year month day hour ) ];
my $YHMS = [ qw( year hour minute second ) ];
my $YMDHM = [ qw( year month day hour minute ) ];
my $YMHMS = [ qw( year month hour minute second ) ];
my $YMDHAP = [ qw( year month day hour ampm ) ];
my $YMDHMS = [ qw( year month day hour minute second ) ];
my $YMDHMAP = [ qw( year month day hour minute ampm ) ];
my $YMHMSAP = [ qw( year month hour minute second ampm ) ];
my $YMDHMSAP = [ qw( year month day hour minute second ampm ) ];
my $YMDHMSNS = [ qw( year month day hour minute second nanosecond ) ];
my $YMDHMSNSAP = [ qw( year month day hour minute second nanosecond ampm ) ];

use DateTime;
use DateTime::TimeZone;
use DateTime::Format::Builder 0.74;

my $base_dt;
sub base
{
    my ( $self , $dt ) = @_;
    $base_dt = $dt if ( $dt );
    return $base_dt || DateTime->now;
}

my $formats =
[
 [ preprocess => \&_fix_alpha ] ,

 { length => [18..22] , params => $YMDHMSAP , regex => qr{\A(\d{4})$DELIM(\d{2})$DELIM(\d{2})\s$HMS\s?$AMPM\z} , postprocess => \&_fix_ampm } ,

 # 2011-06-16-17.43.30.000000
 { length => [26] , params => $YMDHMSNS , regex => qr{\A(\d{4})$DELIM(\d{2})$DELIM(\d{2})${DELIM}$HMSNS\z} } ,

 ########################################################
 ##### Month/Day/Year
 # M/DD/Y, MM/D/Y, M/D/Y, MM/DD/Y, M/D/YY, M/DD/YY, MM/D/Y, MM/SS/YY,
 # M/D/YYYY, M/DD/YYYY, MM/D/YYYY, MM/DD/YYYY

 { length => [5..10],  params => $MDY,      regex => qr{\A${MON}${DELIM}${DAY}${DELIM}${YEAR}\z},               postprocess => \&_fix_year },
 { length => [12..14], params => $MDY,      regex => qr{\AX${MON}X${DELIM}n${DAY}n${DELIM}${YEAR}\z} },
 { length => [11..19], params => $MDYHMS,   regex => qr{\A${MON}${DELIM}${DAY}${DELIM}${YEAR}\s$HMS\z},         postprocess => \&_fix_year },
 { length => [11..20], params => $MDYHMAP,  regex => qr{\A${MON}${DELIM}${DAY}${DELIM}${YEAR}\s$HM\s?$AMPM\z},  postprocess => [ \&_fix_ampm , \&_fix_year ] } ,
 { length => [14..22], params => $MDYHMSAP, regex => qr{\A${MON}${DELIM}${DAY}${DELIM}${YEAR}\s$HMS\s?$AMPM\z}, postprocess => [ \&_fix_ampm , \&_fix_year ] } ,

 ########################################################
 ##### Year/Month/Day
 ##### Can't have 1,2 digit years in this format, would get confused
 ##### with MM-DD-YY
 # YYYY/M/D, YYYY/M/DD, YYYY/MM/D, YYYY/MM/DD
 # YYYY/MM/DD HH:MM:SS
 # YYYY-MM HH:MM:SS
 { length => [6,7],    params => $YM,       regex => qr{\A(\d{4})$DELIM$MON\z} },
 { length => [12..16], params => $YMHMS,    regex => qr{\A(\d{4})$DELIM$MON\s$HMS\z} },
 { length => [14..19], params => $YMHMSAP,  regex => qr{\A(\d{4})$DELIM$MON\s$HMS\s?$AMPM\z} , postprocess => \&_fix_ampm },
 { length => [8..10],  params => $YMD,      regex => qr{\A$YYYYMMDD\z} },
 { length => [10..12], params => $YMDH,     regex => qr{\A${YYYYMMDD}\s${HOUR}z} },
 { length => [13..15], params => $YMDHAP,   regex => qr{\A${YYYYMMDD}\s${HOUR}\s?${AMPM}\z} , postprocess => \&_fix_ampm },
 { length => [11..16], params => $YMDHM,    regex => qr{\A$YYYYMMDD\s$HM\z} },
 { length => [14..19], params => $YMDHMAP,  regex => qr{\A$YYYYMMDD\s$HM\s?$AMPM\z}, postprocess => \&_fix_ampm },
 { length => [14..19], params => $YMDHMS,   regex => qr{\A$YYYYMMDD\s$HMS\z} },
 { length => [17..21], params => $YMDHMSAP, regex => qr{\A$YYYYMMDD\s$HMS\s?$AMPM\z}, postprocess => \&_fix_ampm },

 ########################################################
 ##### YYYY-MM-DDTHH:MM:SS
 # this is what comes out of the database
 { length => 19, params => $YMDHMS, regex => qr{\A(\d{4})$DELIM(\d{2})$DELIM(\d{2})T(\d{2}):(\d{2}):(\d{2})\z} },

 { length => 16, params => $YMDHMS, regex => qr{\A(\d{4})(\d{2})(\d{2})(\d{2}):(\d{2}):(\d{2})\z} },
 { length => 13, params => $YMDHM , regex => qr{\A(\d{4})(\d{2})(\d{2})(\d{2}):(\d{2})\z} },

 { length => 10 , params => $YMD   , regex => qr{\AY(\d{2})Y$DELIM(\d{2})$DELIM(\d{2})\z} , postprocess => \&_fix_year } ,
 # 96-06-1800:00:00
 { length => 18 , params => $YMDHMS , regex => qr{\AY(\d{2})Y$DELIM(\d{2})$DELIM(\d{2})$HMS\z} , postprocess => \&_fix_year } ,
 # 96-06-1800:00
 { length => 15 , params => $YMDHM , regex => qr{\AY(\d{2})Y$DELIM(\d{2})$DELIM(\d{2})$HM\z} , postprocess => \&_fix_year } ,
 # 9931201 at 05:30:25 pM GMT

 # 1993120105:30:25.05 am
 { length => 22 , params => $YMDHMSNSAP ,
   regex => qr{\A(\d{4})(\d{2})(\d{2})${HMSNS}\s${AMPM}\z} ,
   postprocess => \&_fix_ampm },

 # 1993120105:30:25 am
 { length => 19 , params => $YMDHMSAP ,
   regex => qr{\A(\d{4})(\d{2})(\d{2})${HMS}\s${AMPM}\z} ,
   postprocess => \&_fix_ampm },

 ########################################################
 ##### Month/Year
 ##### year must be 4 digits unless it is > 31
 ##### or MMYY is true
 # M/YYYY, MM/YYYY
 { length => [6,7], params => $MY, regex => qr{\A$MMYYYY\z} },
 { length => [3..5], params => $MY, regex => qr{\A$MMYY\z},
   postprocess => [sub {
       my %args = @_;
       if ( exists $args{args} )
       {
           my %original_args = @{$args{args}};
           return 1 if ( $original_args{MMYY} );
       }
       return 1 if ( $args{parsed}{year} > 31 );
       return 0;
   }, \&_fix_year] },
 ########################################################
 ##### Month/Day
 # M/D, M/DD, MM/D, MM/DD
 { length => [3..5], params => $MD, regex => qr{\A$MMDD\z},
   postprocess => sub { my %args = @_; $args{parsed}{year} = __PACKAGE__->base->year } },

 { length => [9..14], params => $MDHMS, regex => qr{\A$MMDD\s$HMS\z},
   postprocess => sub { my %args = @_; $args{parsed}{year} = __PACKAGE__->base->year } },
 { length => [12..17], params => $MDHMSAP, regex => qr{\A$MMDD\s$HMS\s?$AMPM\z},
   postprocess => [sub { my %args = @_; $args{parsed}{year} = __PACKAGE__->base->year },\&_fix_ampm] },


 ########################################################
 ##### Dates with at in their name: 12-10-65 at 5:30:25
 # the language plugins should wrap the time like this: T5:30:25T
 # 2005-06-12 T3Tp (15)
 { length => [16],     params => $MDYHMS,   regex => qr{\A${MON}${DAY}${YEAR}T${HMS}T\z},                               postprocess => \&_fix_year } ,
 { length => [17,18],  params => $MDYHMS,   regex => qr{\A${MON}${DELIM}${DAY}${DELIM}${YEAR}\s?T${HMS}T\z},            postprocess => \&_fix_year } ,
 { length => [20],     params => $MDYHMS,   regex => qr{\AX${MON}X${DELIM}${DAY}${DELIM}${YEAR}\s?T${HMS}T\z},          postprocess => \&_fix_year } ,
 { length => [20,21],  params => $YMDHMAP,  regex => qr{\A${YYYYMMDD}\s?T${HM}T\s${AMPM}\z},                            postprocess => \&_fix_ampm } ,
 { length => [21,22],  params => $YMDHMSAP, regex => qr{\A${YEAR}${MON}${DAY}\s?T${HMS}T\s${AMPM}\z},                   postprocess => \&_fix_ampm } ,
 { length => [15],     params => $YMDHAP,   regex => qr{\A${YEAR}${DELIM}${MON}${DELIM}${DAY}\s?T${HOUR}T\s?${AMPM}\z}, postprocess => \&_fix_ampm } ,
 { length => [16..18], params => $YMDHM,    regex => qr{\A${YEAR}${DELIM}${MON}${DELIM}${DAY}\s?T${HM}T\z},             postprocess => \&_fix_year } ,
 { length => [21],     params => $YMDHMS,   regex => qr{\A${YEAR}${DELIM}${MON}${DELIM}${DAY}\s?T${HMS}T\z},            postprocess => \&_fix_year } ,
 { length => [16],     params => $MDYHMS,   regex => qr{\A${MON}${DAY}(\d\d)\s?T${HMS}T\z},                             postprocess => \&_fix_year } ,
 { length => [16],     params => $YMDHAP,   regex => qr{\A${YEAR}${DELIM}${MON}${DELIM}${DAY}\s?T${HOUR}T${AMPM}\z},    postprocess => \&_fix_ampm } ,

 { length => [15,16],  params => $MDHMS,    regex => qr{\A${MON}${DELIM}${DAY}\s?T${HMS}T\z},
   postprocess => sub { my %args = @_; $args{parsed}{year} = __PACKAGE__->base->year } } ,
 { length => [17,18],  params => $MDHMS,    regex => qr{\AX${MON}X${DELIM}${DAY}\s?T${HMS}T\z},
   postprocess => sub { my %args = @_; $args{parsed}{year} = __PACKAGE__->base->year } } ,

 ########################################################
 # YYYY HH:MM:SS
 { length => [13], params => $YHMS, regex => qr{\A$YEAR\s$HMS\z} } ,

 ########################################################
 # time first
 # (5:30 12-10)
 { length => [8..11], params => $HMMD, regex => qr{\A${HM}\s${MMDD}\z}, postprocess => \&_set_default_year },
 # 5:30:25:05/1/1/65
 # 12:30:25:05/10/10/65
 { length => [17..20], params => $HMSNSMDY, regex => qr{\A${HMSNS}${DELIM}${MMDDYYYY}\z}, postprocess => \&_fix_year },
 # 5:30:25 12101965
 { length => [14..16], params => $HMSMDY, regex => qr{\A${HMS}${DELIM}${MON}${DAY}${YEAR}\z}, postprocess => \&_fix_year },
 { length => [14..19], params => $HMSMDY, regex => qr{\A${HMS}${DELIM}${MMDDYYYY}\z}, postprocess => \&_fix_year },
 # 5:30 pm 121065 => 2065-12-01T17:30:00
 { length => [14,18], params => $HMAPMMDDYYYY, regex => qr{\A${HM}\s${AMPM}\s${MON}${DAY}${YEAR}},postprocess => [\&_fix_ampm, \&_fix_year] },
 { length => [16,19], params => $HMAPMMDDYYYY, regex => qr{\A${HM}\s${AMPM}\s${MMDDYYYY}},postprocess => [\&_fix_ampm, \&_fix_year] },

 ########################################################
 ##### Alpha months
 # _fix_alpha changes month name to "XMX"
 # 18-XMX, X1X-18, 08-XMX-99, XMY-08-1999, 1999-X1Y-08, 1999-X10X-08

 # DD-mon, D-mon, D-mon-YY, DD-mon-YY, D-mon-YYYY, DD-mon-YYYY, D-mon-Y, DD-mon-Y
 { length => [5..7], params => $DM, regex => qr{\A${DDXMMX}\z},
   postprocess => sub { my %args = @_; $args{parsed}{year} = __PACKAGE__->base->year } },
 { length => [9..15], params => $DMHM, regex => qr{\A${DDXMMX}\s${HM}\z},
   postprocess => sub { my %args = @_; $args{parsed}{year} = __PACKAGE__->base->year } },
 { length => [9..18], params => $DMHMS, regex => qr{\A${DDXMMX}\s${HMS}\z},
   postprocess => sub { my %args = @_; $args{parsed}{year} = __PACKAGE__->base->year } },
 { length => [11..21], params => $DMHMSAP, regex => qr{\A${DDXMMX}\s${HMS}\s?$AMPM\z},
   postprocess => [sub { my %args = @_; $args{parsed}{year} = __PACKAGE__->base->year }, \&_fix_ampm] } ,

 { length => [7..12],  params => $DMY,      regex => qr{\A${DDXMMXYYYY}\z},                 postprocess => \&_fix_year },
 { length => [12..18], params => $DMYHM,    regex => qr{\A${DDXMMXYYYY}\s${HM}\z},          postprocess => \&_fix_year },
 { length => [12..21], params => $DMYHMS,   regex => qr{\A${DDXMMXYYYY}\s${HMS}\z},         postprocess => \&_fix_year },
 { length => [16..25], params => $DMYHMSNS, regex => qr{\A${DDXMMXYYYY}\s${HMSNS}\z},       postprocess => \&_fix_year },
 { length => [14..24], params => $DMYHMSAP, regex => qr{\A${DDXMMXYYYY}\s${HMS}\s?$AMPM\z}, postprocess => [ \&_fix_year , \&_fix_ampm ] },
 { length => [9..15] , params => $HMSMD,    regex => qr{\A${HMS}${XMMXDD}\z},               postprocess => \&_set_default_year },
 { length => [9..15] , params => $HMSDM,    regex => qr{\A${HMS}${DELIM}?${DDXMMX}\z},      postprocess => \&_set_default_year },
 { length => [11..17], params => $HMSMDY,   regex => qr{\A${HMS}${XMMXDDYYYY}\z},           postprocess => \&_fix_year },
 { length => [6..11],  params => $HMMD,     regex => qr{\A${HM}${XMMXDD}\z},                postprocess => \&_set_default_year },

 # mon
 { length => [3,4], params => $M, regex => qr{\AX${MON}X\z},
   postprocess => sub { my %args = @_;$args{parsed}{year} = __PACKAGE__->base->year;$args{parsed}{day} = 1; } },

 # mon-D , mon-DD,  mon-YYYY, mon-D-Y, mon-DD-Y, mon-D-YY, mon-DD-YY
 # mon-D-YYYY, mon-DD-YYYY
 { length => [8,9],    params => $MY,       regex => qr{\A${XMMXYYYY}\z} },
 { length => [14..18], params => $MYHMS,    regex => qr{\A${XMMXYYYY}\s${HMS}\z} },
 { length => [16..21], params => $MYHMSAP,  regex => qr{\A${XMMXYYYY}\s${HMS}\s?$AMPM\z}, postprocess => \&_fix_ampm },

 { length => [5..7], params => $MD, regex => qr{\A$XMMXDD\z},
   postprocess => sub { my %args = @_; _set_year( @_ ) } },
 { length => [10..18], params => $MDHMS, regex => qr{\A$XMMXDD\s$HMS\z},
   postprocess => sub { my %args = @_; $args{parsed}{year} = __PACKAGE__->base->year } },
 { length => [12..21], params => $MDHMSAP, regex => qr{\A$XMMXDD\s$HMS\s?$AMPM\z} ,
   postprocess => [sub { my %args = @_; $args{parsed}{year} = __PACKAGE__->base->year }, \&_fix_ampm] },

 { length => [7..12],  params => $MDY,      regex => qr{\A$XMMXDDYYYY\z},                 postprocess => \&_fix_year },
 { length => [12..21], params => $MDYHMS,   regex => qr{\A$XMMXDDYYYY\s$HMS\z},           postprocess => \&_fix_year },
 { length => [14..24], params => $MDYHMSAP, regex => qr{\A$XMMXDDYYYY\s$HMS\s?$AMPM\z},   postprocess => [ \&_fix_year , \&_fix_ampm ] },

 # YYYY-mon-D, YYYY-mon-DD, YYYY-mon
 { length => [8,9],    params => $YM,       regex => qr{\A(\d{4})${DELIM}X(\d{1,2})X\z} },
 { length => [13..18], params => $YMHMS,    regex => qr{\A(\d{4})${DELIM}X(\d{1,2})X\s$HMS\z} },
 { length => [15..21], params => $YMHMSAP,  regex => qr{\A(\d{4})${DELIM}X(\d{1,2})X\s$HMS\s?$AMPM\z}                , postprocess => \&_fix_ampm },
 { length => [9..12],  params => $YMD,      regex => qr{\A(\d{4})${DELIM}X(\d{1,2})X$DELIM(\d{1,2})\z} },
 { length => [15..21], params => $YMDHMS,   regex => qr{\A(\d{4})${DELIM}X(\d{1,2})X$DELIM(\d{1,2})\s$HMS\z} },
 { length => [18..24], params => $YMDHMSAP, regex => qr{\A(\d{4})${DELIM}X(\d{1,2})X$DELIM(\d{1,2})\s$HMS\s?$AMPM\z} , postprocess => \&_fix_ampm },
 # month D, Y | month D, YY | month D, YYYY | month DD, Y | month DD, YY
 # month DD, YYYY
 { length => [9..13], params => $MDY,      regex => qr{\AX(\d{1,2})X\s(\d{1,2}),\s(\d{1,4})\z} },
 { length => [5..22], params => $MDYHMS,   regex => qr{\AX(\d{1,2})X\s(\d{1,2}),\s(\d{1,4})\s$HMS\z} },
 { length => [7..25], params => $MDYHMSAP, regex => qr{\AX(\d{1,2})X\s(\d{1,2}),\s(\d{1,4})\s$HMS\s?$AMPM\z} , postprocess => \&_fix_ampm },

 # D month, Y | D month, YY | D month, YYYY | DD month, Y | DD month, YY
 # DD month, YYYY
 # nDDn XMMX
 { length => [8..13],  params => $DMY,      regex => qr{\A(\d{1,2})\sX(\d{1,2})X,?\s(\d{1,4})\z} },
 { length => [13..21], params => $DMYHMS,   regex => qr{\A(\d{1,2})\sX(\d{1,2})X,?\s(\d{1,4})\s$HMS\z} },
 { length => [16..27], params => $DMYHMSAP, regex => qr{\A(\d{1,2})\sX(\d{1,2})X,?\s(\d{1,4})\s$HMS\s?$AMPM\z}, postprocess => \&_fix_ampm },
 { length => [7..9],   params => $DM,       regex => qr{\An(\d{1,2})n\sX(\d{1,2})X\z},                          postprocess => \&_set_default_year },

 # Dec 03 20:53:10 2009
 { length => [16..21], params => $MDHMSY , regex => qr{\AX(\d{1,2})X\s(\d{1,2})\s$HMS\s(\d{4})\z} } ,
 { length => [10..18], params => $HMMDY  , regex => qr{\A$HM\sX${MON}X\s$DAY\s$YEAR\z} },
 # 8:00 pm Dec 10th => 8:00pm X12X n10n
 { length => [14..19]    , params => $HMAPMMDD , regex => qr{\A$HM\s?$AMPM\sX${MON}X\sn${DAY}n\z} ,
   postprocess => [sub { my %args = @_; $args{parsed}{year} = __PACKAGE__->base->year }, \&_fix_ampm] },
 # 5:30 DeC 1
 { length => [11], params => $HMMD, regex => qr{\A${HM}\sX${MON}X\s${DAY}\z}m, postprocess => \&_set_default_year },

 ########################################################
 ##### Bare Numbers
 # 20060518T051326, 20060518T0513, 20060518T05, 20060518, 200608
 # 20060518 12:34:56
 { length => [16..20], params => $YMDHMSAP, regex => qr{\A(\d{4})(\d{2})(\d{2})\s$HMS\s?$AMPM\z} , postprocess => \&_fix_ampm },
 { length => [14..17], params => $YMDHMS,   regex => qr{\A(\d{4})(\d{2})(\d{2})\s$HMS\z} },
 # 19960618000000 => 1996-06-18T00:00:00
 { length => 14,       params => $YMDHMS,   regex => qr{\A(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\z} },
 { length => 15,       strptime => '%Y%m%dT%H%M%S' } ,
 { length => 13,       strptime => '%Y%m%dT%H%M' } ,
 { length => 11,       strptime => '%Y%m%dT%H' } ,
 { length => 8,        strptime => '%Y%m%d' } ,
 { length => 6,        strptime => '%Y%m' } ,
 { length => 4,        strptime => '%Y' } ,

 ########################################################
 ##### bare times
 # HH:MM:SS
 { length => [5..8],
   params => [ qw( hour minute second ) ] ,
   regex => qr{\A$HMS\z} ,
   postprocess => sub {
       my %args = @_;
       $args{parsed}{year} = __PACKAGE__->base->year;
       $args{parsed}{month} = __PACKAGE__->base->month;
       $args{parsed}{day} = __PACKAGE__->base->day;
   }
 },
 # HH:MM
 { length => [3..5],
   params => [ qw( hour minute ) ] ,
   regex => qr{\A$HM\z} ,
   postprocess => sub {
       my %args = @_;
       $args{parsed}{year} = __PACKAGE__->base->year;
       $args{parsed}{month} = __PACKAGE__->base->month;
       $args{parsed}{day} = __PACKAGE__->base->day;
   }
 },
 # HH:MM am
 { length => [5..10],
   params => [ qw( hour minute ampm ) ] ,
   regex => qr{\A$HM\s?$AMPM\z} ,
   postprocess => [sub {
       my %args = @_;
       $args{parsed}{year} = __PACKAGE__->base->year;
       $args{parsed}{month} = __PACKAGE__->base->month;
       $args{parsed}{day} = __PACKAGE__->base->day;
   }, \&_fix_ampm ]
 } ,

 # HH am
 { length => [2..5],
   params => [ qw( hour ampm ) ] ,
   regex => qr{\A$HOUR\s?$AMPM\z} ,
   postprocess => [sub {
       my %args = @_;
       $args{parsed}{year} = __PACKAGE__->base->year;
       $args{parsed}{month} = __PACKAGE__->base->month;
       $args{parsed}{day} = __PACKAGE__->base->day;
   }, \&_fix_ampm ]
 } ,

 # Day of year
 # 1999345 => 1999, 345th day of year
 { length => [5,7],    params => [ qw( year doy ) ] ,
   regex => qr{\A$YEAR(?:$DELIM)?(\d{3})\z} ,
   postprocess => [ \&_fix_year , \&_fix_day_of_year ] } ,
 { length => [10..18], params => [ qw( year doy hour minute second ) ] ,
   regex => qr{\A$YEAR(?:$DELIM)?(\d{3})\s$HMS\z} ,
   postprocess => [ \&_fix_year , \&_fix_day_of_year ] } ,
 { length => [12..21], params => [ qw( year doy hour minute second ampm ) ] ,
   regex => qr{\A$YEAR(?:$DELIM)?(\d{3})\s$HMS\s?$AMPM\z} ,
   postprocess => [ \&_fix_year , \&_fix_day_of_year , \&_fix_ampm ]} ,

 # this is the format for Websphere mq
 # http://publib.boulder.ibm.com/infocenter/wmqv6/v6r0/index.jsp?topic=/com.ibm.mq.csqzak.doc/js01396.htm
 # hundreths are not a valid parameter to DateTime->new, so we turn them into nanoseconds
 { length => [16], params => $YMDHMSNS , regex => qr{\A(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\z} ,
   postprocess => sub {
       my %args = @_;
       my $t = sprintf( '%s0' , $args{parsed}{nanosecond} ) * 1_000_000;
       $args{parsed}{nanosecond} = $t;
   }
 },

 {
     params => [],
     length => [8],
     regex  => qr{\Ainfinity\z},
     constructor => sub {
         return DateTime::Infinite::Future->new;
     },
 },
 {
     params => [],
     length => [9],
     regex  => qr{\A\-infinity\z},
     constructor => sub {
         return DateTime::Infinite::Past->new;
     },
 },

 # nanoseconds. no length here, we do not know how many digits they will use for nanoseconds
 { params => [ qw( year month day hour minute second nanosecond ) ] , regex => qr{\A$YYYYMMDD(?:\s|T)T?${HMS}${HMSDELIM}(\d+)T?\z} } ,

 # epochtime
 {
   params => [] , # we specifically set the params below
   regex => qr{\A\d+\.?\d+?\z} ,
   postprocess => sub {
       my %args = @_;
       my $dt = DateTime->from_epoch( epoch => $args{input} );
       $args{parsed}{year} = $dt->year;
       $args{parsed}{month} = $dt->month;
       $args{parsed}{day} = $dt->day;
       $args{parsed}{hour} = $dt->hour;
       $args{parsed}{minute} = $dt->minute;
       $args{parsed}{second} = $dt->second;
       $args{parsed}{nanosecond} = $dt->nanosecond;
       return 1;
   }
 },
];

DateTime::Format::Builder->create_class( parsers => { parse_datetime => $formats } );

sub build
{
    my $self = shift;
    return $self->parse_datetime( @_ );
}

sub _fix_day_of_year
{
    my %args = @_;

    my $doy = $args{parsed}{doy};
    delete $args{parsed}{doy};

    my $dt = DateTime->from_day_of_year(
        year => $args{parsed}{year} ,
        day_of_year => $doy
    );
    $args{parsed}{month} = $dt->month;
    $args{parsed}{day} = $dt->day;

    return 1;
}

sub _fix_alpha
{
    my %args = @_;
    my ($date, $p) = @args{qw( input parsed )};
    my %extra_args = @{$args{args}} if exists $args{args};

    if ( exists $extra_args{strip} )
    {
        my @strips = ref( $extra_args{strip} ) eq 'ARRAY' ? @{$extra_args{strip}} : ($extra_args{strip});
        foreach my $strip ( @strips )
        {
            if ( ref( $strip ) eq 'Regexp' )
            {
                $date =~ s{$strip}{}mx;
            }
            else
            {
                croak( "parameter strip requires a regular expression" );
            }
        }
    }

    if ( exists $extra_args{base} )
    {
        __PACKAGE__->base( $extra_args{base} );
    }

    ( $date , $p ) = _parse_timezone( $date , $p , \%extra_args );

    $date = _clean_whitespace( $date );

    my $lang = DateTime::Format::Flexible::lang->new(
        lang => $extra_args{lang},
        base => __PACKAGE__->base,
    );

    my $stripped = $date;
    $stripped =~ s{$DELIM|$HMSDELIM}{}gm;

    if ( $stripped =~ m{(\D)} )
    {
        printf( "# before lang: %s\n", $date ) if $ENV{DFF_DEBUG};
        ( $date , $p ) = $lang->_cleanup( $date , $p );
        printf( "# after lang: %s\n", $date ) if $ENV{DFF_DEBUG};
    }
    else
    {
        printf( "# ignoring languages, no non numbers (%s)\n", $stripped ) if $ENV{DFF_DEBUG};
    }

    $date =~ s{($DELIM)+}{$1}mxg;   # make multiple delimeters into one
    # remove any leading delimeters unless it is -infinity
    $date =~ s{\A$DELIM+}{}mx if ( not $date eq '-infinity' );
    $date =~ s{$DELIM+\z}{}mx;      # remove any trailing delimeters
    $date =~ s{\,+}{}gmx;           # remove commas

    # if we have two digits at the beginning of our date that are greater than 31,
    # we have a possible two digit year
    if ( my ( $possible_year , $remaining ) = $date =~ m{\A(\d\d)($DELIM.+)}mx )
    {
        if ( $possible_year > 31 )
        {
            $date =~ s{\A(\d\d)}{Y$1Y}mx;
        }
    }

    # try and detect DD-MM-YYYY
    if ( $extra_args{european} )
    {
        if ( my ( $m , $d , $y ) = $date =~ m{\A$MMDDYYYY}mx )
        {
            $date =~ s{\A$MMDDYYYY}{$2-$1-$3}mx;
        }
    }

    printf( "#-->%s<-- (%s) [%s] \n" , $date , length( $date ) , $p->{time_zone}||q{none} ) if $ENV{DFF_DEBUG};
    return $date;
}

sub _parse_timezone
{
    my ( $date , $p , $extra_args ) = @_;

    while ( my ( $abbrev , $tz ) = each( %{ $extra_args->{tz_map} } ) )
    {
        if ( $date =~ m{$abbrev} )
        {
            $date =~ s{\Q$abbrev\E}{};
            $p->{time_zone} = $tz;
            return ( $date , $p );
        }
    }

    # search for GMT inside the string
    # must be surrounded by spaces
    # 5:30 pm GMT 121065
    if ( my ( $tz ) = $date =~ m{\s(GMT)\s}mx )
    {
        $date =~ s{\Q$tz\E}{};
        $p->{time_zone} = 'UTC';
        return ( $date , $p );
    }

    # remove any trailing 'Z' => UTC
    if ( $date =~ m{Z\z}mx )
    {
        $date =~ s{Z\z}{}mx;
        $p->{time_zone} = 'UTC';
        return ( $date , $p );
    }

    # set any trailing string timezones.  they cannot start with a digit
    if ( my ( $tz ) = $date =~ m{.+\s+(\D[^\s]+)\z} )
    {
        my $orig_tz = $tz;
        if ( exists $extra_args->{tz_map}->{$tz} )
        {
            $tz = $extra_args->{tz_map}->{$tz};
        }
        if ( DateTime::TimeZone->is_valid_name( $tz ) )
        {
            $date =~ s{\Q$orig_tz\E}{};
            $p->{time_zone} = $tz;
            return ( $date , $p );
        }
    }

    # set any trailing offset timezones
    if ( my ( $tz ) = $date =~ m{((?:\s+)?\+\d{2,4}|\s+\-\d{4})\.?\z}mx )
    {
        $date =~ s{\Q$tz\E}{};
        # some timezones are 2 digit hours, add the minutes part
        $tz = _clean_whitespace( $tz );
        $tz .= '00' if ( length( $tz ) == 3 );
        $p->{time_zone} = $tz;
        return ( $date , $p );
    }

    # search for positive/negative 4 digit timezones that are inside the string
    # must be surrounded by spaces
    # Mon Apr 05 17:25:35 +0000 2010
    if ( my ( $tz ) = $date =~ m{\s([\+\-]\d{4})\s}mx )
    {
        $date =~ s{\Q$tz\E}{};
        $p->{time_zone} = $tz;
        return ( $date , $p );
    }

    return ( $date , $p );
}

sub _do_math
{
    my ( $string ) = @_;
    if ( $string =~ m{ago}mx )
    {
        my $base_dt = __PACKAGE__->base;
        if ( my ( $amount , $unit ) = $string =~ m{(\d+)\s([^\s]+)}mx )
        {
            $unit .= 's' if ( $unit !~ m{s\z} ); # make sure the unit ends in 's'
            return $base_dt->subtract( $unit => $amount );
        }
    }
    return $string;
}

sub _clean_whitespace
{
    my ( $string ) = @_;
    $string =~ s{\A\s+}{}mx;    # trim front
    $string =~ s{\s+\z}{}mx;    # trim back

    $string =~ s{\s+}{ }gmx;    # remove extra whitespace from the middle
    return $string;
}

sub _fix_ampm
{
    my %args = @_;

    return if not defined $args{parsed}{ampm};

    my $ampm = $args{parsed}{ampm};
    delete $args{parsed}{ampm};

    if ( $ampm =~ m{a\.?m?\.?}mix )
    {
        if( $args{parsed}{hour} == 12 )
        {
            $args{parsed}{hour} = 0;
        }
        return 1;
    }
    elsif ( $ampm =~ m{p\.?m?\.?}mix )
    {
        $args{parsed}{hour} += 12;
        if ( $args{parsed}{hour} == 24 )
        {
            $args{parsed}{hour} = 12;
        }
        return 1;
    }
    return 1;
}

sub _set_default_year
{
    my %args = @_;
    $args{parsed}{year} = __PACKAGE__->base->year;
    return 1;
}

sub _set_year
{
    my %args = @_;
    my %constructor_args = $args{args} ? @{$args{args}} : ();
    return 1 if defined $args{parsed}{year}; # year is already set

    if ( $constructor_args{prefer_future} )
    {
        if ( $args{parsed}{month} < __PACKAGE__->base->month or
             ( $args{parsed}{month} eq __PACKAGE__->base->month and
               $args{parsed}{day} < __PACKAGE__->base->day ) )
        {
            $args{parsed}{year} = __PACKAGE__->base->clone->add( years => 1 )->year;
            return 1;
        }
    }
    $args{parsed}{year} = __PACKAGE__->base->year;
    return 1;
}

sub _fix_year
{
    my %args = @_;
    return 1 if( length( $args{parsed}{year} ) == 4 );
    my $now = DateTime->now;
    $args{parsed}{year} = __PACKAGE__->_pick_year( $args{parsed}{year} , $now );
    return 1;
}

sub _pick_year
{
    my ( $self , $year , $dt ) = @_;

    if( $year > 69 )
    {
        if( $dt->strftime( '%y' ) > 69 )
        {
            $year = $dt->strftime( '%C' ) . sprintf( '%02s' , $year );
        }
        else
        {
            $year = $dt->subtract( years => 100 )->strftime( '%C' ) .
                    sprintf( '%02s' , $year );
        }
    }
    else
    {
        if( $dt->strftime( '%y' ) > 69 )
        {
            $year = $dt->add( years => 100 )->strftime( '%C' ) .
                    sprintf( '%02s' , $year );
        }
        else
        {
            $year = $dt->strftime( '%C' ) . sprintf( '%02s' , $year );
        }
    }
    return $year;
}

1;

__END__

=encoding utf-8

=head1 NAME

DateTime::Format::Flexible - DateTime::Format::Flexible - Flexibly parse strings and turn them into DateTime objects.

=head1 SYNOPSIS

  use DateTime::Format::Flexible;
  my $dt = DateTime::Format::Flexible->parse_datetime(
      'January 8, 1999'
  );
  # $dt = a DateTime object set at 1999-01-08T00:00:00

=head1 DESCRIPTION

If you have ever had to use a program that made you type in the
date a certain way and thought "Why can't the computer just figure
out what date I wanted?", this module is for you.

F<DateTime::Format::Flexible> attempts to take any string you give
it and parse it into a DateTime object.

=head1 USAGE

This module uses F<DateTime::Format::Builder> under the covers.

=head2 parse_datetime

Give it a string and it attempts to parse it and return a DateTime
object.

If it cannot it will throw an exception.

 my $dt = DateTime::Format::Flexible->parse_datetime( $date );

 my $dt = DateTime::Format::Flexible->parse_datetime(
     $date,
     strip    => [qr{\.\z}],                  # optional, remove a trailing period
     tz_map   => {EDT => 'America/New_York'}, # optional, map the EDT timezone to America/New_York
     lang     => ['es'],                      # optional, only parse using spanish
     european => 1,                           # optional, catch some cases of DD-MM-YY
 );

=over 4

=item * C<base> (optional)

Does the same thing as the method C<base>.  Sets a base datetime for
incomplete dates.  Requires a valid DateTime object as an argument.

example:

 my $base_dt = DateTime->new( year => 2005, month => 2, day => 1 );
 my $dt = DateTime::Format::Flexible->parse_datetime(
    '18 Mar',
     base => $base_dt,
 );
 # $dt is now 2005-03-18T00:00:00

=item * C<strip> (optional)

Remove a substring from the string you are trying to parse.
You can pass multiple regexes in an arrayref.

example:

 my $dt = DateTime::Format::Flexible->parse_datetime(
     '2011-04-26 00:00:00 (registry time)',
     strip => [qr{\(registry time\)\z}],
 );
 # $dt is now 2011-04-26T00:00:00

This is helpful if you have a load of dates you want to normalize
and you know of some weird formatting beforehand.

=item * C<tz_map> (optional)

Map a given timezone to another recognized timezone
Values are given as a hashref.

example:

 my $dt = DateTime::Format::Flexible->parse_datetime(
     '25-Jun-2009 EDT',
     tz_map => {EDT => 'America/New_York'},
 );
 # $dt is now 2009-06-25T00:00:00 with a timezone of America/New_York

This is helpful if you have a load of dates that have timezones that
are not recognized by F<DateTime::Timezone>.

=item * C<lang> (optional)

Specify the language map plugins to use.

When DateTime::Format::Flexible parses a date with a string in it,
it will search for a way to convert that string to a number.  By
default it will search through all the language plugins to search
for a match.

NOTE: as of 0.22, it will only do this search if it detects a string
in the given date.

Setting C<lang> this lets you limit the scope of the search.

example:

 my $dt = DateTime::Format::Flexible->parse_datetime(
     'Wed, Jun 10, 2009',
     lang => ['en'],
 );
 # $dt is now 2009-06-10T00:00:00

Currently supported languages are english (en), spanish (es) and
german (de). Contributions, corrections, requests and examples
are VERY welcome.

See the F<DateTime::Format::Flexible::lang::en>,
F<DateTime::Format::Flexible::lang::es>, and
F<DateTime::Format::Flexible::lang::de>
for examples of the plugins.

=item * C<european> (optional)

If european is set to a true value, an attempt will be made to parse
as a DD-MM-YYYY date instead of the default MM-DD-YYYY.  There is a
chance that this will not do the right thing due to ambiguity.

example:

 my $dt = DateTime::Format::Flexible->parse_datetime(
     '16/06/2010' , european => 1,
 );
 # $dt is now 2010-06-16T00:00:00

=item * C<MMYY> (optional)

By default, this module parse 12/10 as December 10th of the current
year (MM/DD).

If you want it to parse this as MM/YY instead, you can enable the
C<MMYY> option.

example:

 my $dt = DateTime::Format::Flexible->parse_datetime('12/10');
 # $dt is now [current year]-12-10T00:00:00

 my $dt = DateTime::Format::Flexible->parse_datetime(
     '12/10', MMYY => 1,
 );
 # $dt is now 2010-12-01T00:00:00

This is useful if you know you are going to be parsing a credit card
expiration date.

=back

=head2 base

gets/sets the base DateTime for incomplete dates.  Requires a valid
DateTime object as an argument when setting.  This defaults to
DateTime->now.

example:

 DateTime::Format::Flexible->base( DateTime->new(
     year => 2009, month => 6, day => 22
 ));
 my $dt = DateTime::Format::Flexible->parse_datetime( '23:59' );
 # $dt is now 2009-06-22T23:59:00

=head2 build

an alias for parse_datetime

=head2 Example formats

A small list of supported formats:

=over 4

=item YYYYMMDDTHHMMSS

=item YYYYMMDDTHHMM

=item YYYYMMDDTHH

=item YYYYMMDD

=item YYYYMM

=item MM-DD-YYYY

=item MM-D-YYYY

=item MM-DD-YY

=item M-DD-YY

=item YYYY/DD/MM

=item YYYY/M/DD

=item YYYY/MM/D

=item M-D

=item MM-D

=item M-D-Y

=item Month D, YYYY

=item Mon D, YYYY

=item Mon D, YYYY HH:MM:SS

=item ... thousands more

=back

there are 9000+ variations that are detected correctly in the test
files (see t/data/* for most of them).  If you can think of any that
I do not cover, please let me know.

=head1 NOTES

As of version 0.11 you will get a DateTime::Infinite::Future object
if the passed in date is 'infinity' and a DateTime::Infinite::Past
object if the passed in date is '-infinity'.  If you are expecting
these types of strings, you might want to check for
'is_infinite()' from the object returned.

example:

 my $dt = DateTime::Format::Flexible->parse_datetime( 'infinity' );
 if ( $dt->is_infinite )
 {
      # you have a Infinite object.
 }

=head1 BUGS/LIMITATIONS

You cannot use a 1 or 2 digit year as the first field unless the
year is > 31:

 YY-MM-DD # not supported if YY is <= 31
 Y-MM-DD  # not supported

It gets confused with MM-DD-YY

=head1 AUTHOR

Tom Heady <cpan@punch.net>

=head1 COPYRIGHT & LICENSE

Copyright 2007-2012 Tom Heady.

This program is free software; you can redistribute it and/or
modify it under the terms of either:

=over 4

=item * the GNU General Public License as published by the Free
    Software Foundation; either version 1, or (at your option) any
    later version, or

=item * the Artistic License.

=back

=head1 SEE ALSO

F<DateTime::Format::Builder>, F<DateTime::Timezone>, F<DateTime::Format::Natural>

=cut
