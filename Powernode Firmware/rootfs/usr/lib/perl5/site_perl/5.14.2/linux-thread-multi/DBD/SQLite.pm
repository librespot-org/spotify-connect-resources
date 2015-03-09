package DBD::SQLite;

use 5.006;
use strict;
use DBI   1.57 ();
use DynaLoader ();

our $VERSION = '1.39';
our @ISA     = 'DynaLoader';

# sqlite_version cache (set in the XS bootstrap)
our ($sqlite_version, $sqlite_version_number);

# not sure if we still need these...
our ($err, $errstr);

__PACKAGE__->bootstrap($VERSION);

# New or old API?
use constant NEWAPI => ($DBI::VERSION >= 1.608);

# global registry of collation functions, initialized with 2 builtins
our %COLLATION;
tie %COLLATION, 'DBD::SQLite::_WriteOnceHash';
$COLLATION{perl}       = sub { $_[0] cmp $_[1] };
$COLLATION{perllocale} = sub { use locale; $_[0] cmp $_[1] };

our $drh;
my $methods_are_installed = 0;

sub driver {
    return $drh if $drh;

    if (!$methods_are_installed && DBD::SQLite::NEWAPI ) {
        DBI->setup_driver('DBD::SQLite');

        DBD::SQLite::db->install_method('sqlite_last_insert_rowid');
        DBD::SQLite::db->install_method('sqlite_busy_timeout');
        DBD::SQLite::db->install_method('sqlite_create_function');
        DBD::SQLite::db->install_method('sqlite_create_aggregate');
        DBD::SQLite::db->install_method('sqlite_create_collation');
        DBD::SQLite::db->install_method('sqlite_collation_needed');
        DBD::SQLite::db->install_method('sqlite_progress_handler');
        DBD::SQLite::db->install_method('sqlite_commit_hook');
        DBD::SQLite::db->install_method('sqlite_rollback_hook');
        DBD::SQLite::db->install_method('sqlite_update_hook');
        DBD::SQLite::db->install_method('sqlite_set_authorizer');
        DBD::SQLite::db->install_method('sqlite_backup_from_file');
        DBD::SQLite::db->install_method('sqlite_backup_to_file');
        DBD::SQLite::db->install_method('sqlite_enable_load_extension');
        DBD::SQLite::db->install_method('sqlite_load_extension');
        DBD::SQLite::db->install_method('sqlite_register_fts3_perl_tokenizer');
        DBD::SQLite::db->install_method('sqlite_trace', { O => 0x0004 });
        DBD::SQLite::db->install_method('sqlite_profile', { O => 0x0004 });
        DBD::SQLite::db->install_method('sqlite_table_column_metadata', { O => 0x0004 });
        DBD::SQLite::db->install_method('sqlite_db_filename', { O => 0x0004 });
        DBD::SQLite::db->install_method('sqlite_db_status', { O => 0x0004 });

        DBD::SQLite::st->install_method('sqlite_st_status', { O => 0x0004 });

        $methods_are_installed++;
    }

    $drh = DBI::_new_drh( "$_[0]::dr", {
        Name        => 'SQLite',
        Version     => $VERSION,
        Attribution => 'DBD::SQLite by Matt Sergeant et al',
    } );

    return $drh;
}

sub CLONE {
    undef $drh;
}


package DBD::SQLite::dr;

sub connect {
    my ($drh, $dbname, $user, $auth, $attr) = @_;

    # Default PrintWarn to the value of $^W
    # unless ( defined $attr->{PrintWarn} ) {
    #    $attr->{PrintWarn} = $^W ? 1 : 0;
    # }

    my $dbh = DBI::_new_dbh( $drh, {
        Name => $dbname,
    } );

    my $real = $dbname;
    if ( $dbname =~ /=/ ) {
        foreach my $attrib ( split(/;/, $dbname) ) {
            my ($key, $value) = split(/=/, $attrib, 2);
            if ( $key =~ /^(?:db(?:name)?|database)$/ ) {
                $real = $value;
            } else {
                $attr->{$key} = $value;
            }
        }
    }

    # To avoid unicode and long file name problems on Windows,
    # convert to the shortname if the file (or parent directory) exists.
    if ( $^O =~ /MSWin32/ and $real ne ':memory:' and $real ne '') {
        require Win32;
        require File::Basename;
        my ($file, $dir, $suffix) = File::Basename::fileparse($real);
        my $short = Win32::GetShortPathName($real);
        if ( $short && -f $short ) {
            # Existing files will work directly.
            $real = $short;
        } elsif ( -d $dir ) {
            # We are creating a new file.
            # Does the directory it's in at least exist?
            $real = join '', grep { defined } Win32::GetShortPathName($dir), $file, $suffix;
        } else {
            # SQLite can't do mkpath anyway.
            # So let it go through as it and fail.
        }
    }

    # Hand off to the actual login function
    DBD::SQLite::db::_login($dbh, $real, $user, $auth, $attr) or return undef;

    # Register the on-demand collation installer, REGEXP function and
    # perl tokenizer
    if ( DBD::SQLite::NEWAPI ) {
        $dbh->sqlite_collation_needed( \&install_collation );
        $dbh->sqlite_create_function( "REGEXP", 2, \&regexp );
        $dbh->sqlite_register_fts3_perl_tokenizer();
    } else {
        $dbh->func( \&install_collation, "collation_needed"  );
        $dbh->func( "REGEXP", 2, \&regexp, "create_function" );
        $dbh->func( "register_fts3_perl_tokenizer" );
    }

    # HACK: Since PrintWarn = 0 doesn't seem to actually prevent warnings
    # in DBD::SQLite we set Warn to false if PrintWarn is false.

    # NOTE: According to the explanation by timbunce,
    # "Warn is meant to report on bad practices or problems with
    # the DBI itself (hence always on by default), while PrintWarn
    # is meant to report warnings coming from the database."
    # That is, if you want to disable an ineffective rollback warning
    # etc (due to bad practices), you should turn off Warn,
    # and to silence other warnings, turn off PrintWarn.
    # Warn and PrintWarn are independent, and turning off PrintWarn
    # does not silence those warnings that should be controlled by
    # Warn.

    # unless ( $attr->{PrintWarn} ) {
    #     $attr->{Warn} = 0;
    # }

    return $dbh;
}

sub install_collation {
    my $dbh       = shift;
    my $name      = shift;
    my $collation = $DBD::SQLite::COLLATION{$name};
    unless ($collation) {
        warn "Can't install unknown collation: $name" if $dbh->{PrintWarn};
        return;
    }
    if ( DBD::SQLite::NEWAPI ) {
        $dbh->sqlite_create_collation( $name => $collation );
    } else {
        $dbh->func( $name => $collation, "create_collation" );
    }
}

# default implementation for sqlite 'REGEXP' infix operator.
# Note : args are reversed, i.e. "a REGEXP b" calls REGEXP(b, a)
# (see http://www.sqlite.org/vtab.html#xfindfunction)
sub regexp {
    use locale;
    return if !defined $_[0] || !defined $_[1];
    return scalar($_[1] =~ $_[0]);
}

package DBD::SQLite::db;

sub prepare {
    my $dbh = shift;
    my $sql = shift;
    $sql = '' unless defined $sql;

    my $sth = DBI::_new_sth( $dbh, {
        Statement => $sql,
    } );

    DBD::SQLite::st::_prepare($sth, $sql, @_) or return undef;

    return $sth;
}

sub do {
    my ($dbh, $statement, $attr, @bind_values) = @_;

    my @copy = @{[@bind_values]};
    my $rows = 0;

    while ($statement) {
        my $sth = $dbh->prepare($statement, $attr) or return undef;
        $sth->execute(splice @copy, 0, $sth->{NUM_OF_PARAMS}) or return undef;
        $rows += $sth->rows;
        # XXX: not sure why but $dbh->{sqlite...} wouldn't work here
        last unless $dbh->FETCH('sqlite_allow_multiple_statements');
        $statement = $sth->{sqlite_unprepared_statements};
    }

    # always return true if no error
    return ($rows == 0) ? "0E0" : $rows;
}

sub ping {
    my $dbh = shift;

    # $file may be undef (ie. in-memory/temporary database)
    my $file = DBD::SQLite::NEWAPI ? $dbh->sqlite_db_filename
                                   : $dbh->func("db_filename");

    return 0 if $file && !-f $file;
    return $dbh->FETCH('Active') ? 1 : 0;
}

sub _get_version {
    return ( DBD::SQLite::db::FETCH($_[0], 'sqlite_version') );
}

my %info = (
    17 => 'SQLite',       # SQL_DBMS_NAME
    18 => \&_get_version, # SQL_DBMS_VER
    29 => '"',            # SQL_IDENTIFIER_QUOTE_CHAR
);

sub get_info {
    my($dbh, $info_type) = @_;
    my $v = $info{int($info_type)};
    $v = $v->($dbh) if ref $v eq 'CODE';
    return $v;
}

sub _attached_database_list {
    my $dbh = shift;
    my @attached;

    my $sth_databases = $dbh->prepare( 'PRAGMA database_list' );
    $sth_databases->execute;
    while ( my $db_info = $sth_databases->fetchrow_hashref ) {
        push @attached, $db_info->{name} if $db_info->{seq} >= 2;
    }
    return @attached;
}

# SQL/CLI (ISO/IEC JTC 1/SC 32 N 0595), 6.63 Tables
# Based on DBD::Oracle's
# See also http://www.ch-werner.de/sqliteodbc/html/sqlite3odbc_8c.html#a213
sub table_info {
    my ($dbh, $cat_val, $sch_val, $tbl_val, $typ_val, $attr) = @_;

    my @where = ();
    my $sql;
    if (  defined($cat_val) && $cat_val eq '%'
       && defined($sch_val) && $sch_val eq ''
       && defined($tbl_val) && $tbl_val eq '')  { # Rule 19a
        $sql = <<'END_SQL';
SELECT NULL TABLE_CAT
     , NULL TABLE_SCHEM
     , NULL TABLE_NAME
     , NULL TABLE_TYPE
     , NULL REMARKS
END_SQL
    }
    elsif (  defined($cat_val) && $cat_val eq ''
          && defined($sch_val) && $sch_val eq '%'
          && defined($tbl_val) && $tbl_val eq '') { # Rule 19b
        $sql = <<'END_SQL';
SELECT NULL      TABLE_CAT
     , t.tn      TABLE_SCHEM
     , NULL      TABLE_NAME
     , NULL      TABLE_TYPE
     , NULL      REMARKS
FROM (
     SELECT 'main' tn
     UNION SELECT 'temp' tn
END_SQL
        for my $db_name (_attached_database_list($dbh)) {
            $sql .= "     UNION SELECT '$db_name' tn\n";
        }
        $sql .= ") t\n";
    }
    elsif (  defined($cat_val) && $cat_val eq ''
          && defined($sch_val) && $sch_val eq ''
          && defined($tbl_val) && $tbl_val eq ''
          && defined($typ_val) && $typ_val eq '%') { # Rule 19c
        $sql = <<'END_SQL';
SELECT NULL TABLE_CAT
     , NULL TABLE_SCHEM
     , NULL TABLE_NAME
     , t.tt TABLE_TYPE
     , NULL REMARKS
FROM (
     SELECT 'TABLE' tt                  UNION
     SELECT 'VIEW' tt                   UNION
     SELECT 'LOCAL TEMPORARY' tt
) t
ORDER BY TABLE_TYPE
END_SQL
    }
    else {
        $sql = <<'END_SQL';
SELECT *
FROM
(
SELECT NULL         TABLE_CAT
     ,              TABLE_SCHEM
     , tbl_name     TABLE_NAME
     ,              TABLE_TYPE
     , NULL         REMARKS
     , sql          sqlite_sql
FROM (
    SELECT 'main' TABLE_SCHEM, tbl_name, upper(type) TABLE_TYPE, sql
    FROM sqlite_master
UNION ALL
    SELECT 'temp' TABLE_SCHEM, tbl_name, 'LOCAL TEMPORARY' TABLE_TYPE, sql
    FROM sqlite_temp_master
END_SQL

        for my $db_name (_attached_database_list($dbh)) {
            $sql .= <<"END_SQL";
UNION ALL
    SELECT '$db_name' TABLE_SCHEM, tbl_name, upper(type) TABLE_TYPE, sql
    FROM "$db_name".sqlite_master
END_SQL
        }

        $sql .= <<'END_SQL';
UNION ALL
    SELECT 'main' TABLE_SCHEM, 'sqlite_master'      tbl_name, 'SYSTEM TABLE' TABLE_TYPE, NULL sql
UNION ALL
    SELECT 'temp' TABLE_SCHEM, 'sqlite_temp_master' tbl_name, 'SYSTEM TABLE' TABLE_TYPE, NULL sql
)
)
END_SQL
        $attr = {} unless ref $attr eq 'HASH';
        my $escape = defined $attr->{Escape} ? " ESCAPE '$attr->{Escape}'" : '';
        if ( defined $sch_val ) {
            push @where, "TABLE_SCHEM LIKE '$sch_val'$escape";
        }
        if ( defined $tbl_val ) {
            push @where, "TABLE_NAME LIKE '$tbl_val'$escape";
        }
        if ( defined $typ_val ) {
            my $table_type_list;
            $typ_val =~ s/^\s+//;
            $typ_val =~ s/\s+$//;
            my @ttype_list = split (/\s*,\s*/, $typ_val);
            foreach my $table_type (@ttype_list) {
                if ($table_type !~ /^'.*'$/) {
                    $table_type = "'" . $table_type . "'";
                }
            }
            $table_type_list = join(', ', @ttype_list);
            push @where, "TABLE_TYPE IN (\U$table_type_list)" if $table_type_list;
        }
        $sql .= ' WHERE ' . join("\n   AND ", @where ) . "\n" if @where;
        $sql .= " ORDER BY TABLE_TYPE, TABLE_SCHEM, TABLE_NAME\n";
    }
    my $sth = $dbh->prepare($sql) or return undef;
    $sth->execute or return undef;
    $sth;
}

sub primary_key_info {
    my ($dbh, $catalog, $schema, $table, $attr) = @_;

    my $databases = $dbh->selectall_arrayref("PRAGMA database_list", {Slice => {}});

    my @pk_info;
    for my $database (@$databases) {
        my $dbname = $database->{name};
        next if defined $schema && $schema ne '%' && $schema ne $dbname;

        my $quoted_dbname = $dbh->quote_identifier($dbname);

        my $master_table =
            ($dbname eq 'main') ? 'sqlite_master' :
            ($dbname eq 'temp') ? 'sqlite_temp_master' :
            $quoted_dbname.'.sqlite_master';

        my $sth = $dbh->prepare("SELECT name, sql FROM $master_table WHERE type = ?");
        $sth->execute("table");
        while(my $row = $sth->fetchrow_hashref) {
            my $tbname = $row->{name};
            next if defined $table && $table ne '%' && $table ne $tbname;

            my $quoted_tbname = $dbh->quote_identifier($tbname);
            my $t_sth = $dbh->prepare("PRAGMA $quoted_dbname.table_info($quoted_tbname)");
            $t_sth->execute;
            my @pk;
            while(my $col = $t_sth->fetchrow_hashref) {
                push @pk, $col->{name} if $col->{pk};
            }

            # If there're multiple primary key columns, we need to
            # find their order from one of the auto-generated unique
            # indices (note that single column integer primary key
            # doesn't create an index).
            if (@pk > 1 and $row->{sql} =~ /\bPRIMARY\s+KEY\s*\(\s*
                (
                    (?:
                        (
                            [a-z_][a-z0-9_]*
                          | (["'`])(?:\3\3|(?!\3).)+?\3(?!\3)
                          | \[[^\]]+\]
                        )
                        \s*,\s*
                    )+
                    (
                        [a-z_][a-z0-9_]*
                      | (["'`])(?:\5\5|(?!\5).)+?\5(?!\5)
                      | \[[^\]]+\]
                    )
                )
                    \s*\)/six) {
                my $pk_sql = $1;
                @pk = ();
                while($pk_sql =~ /
                    (
                        [a-z_][a-z0-9_]*
                      | (["'`])(?:\2\2|(?!\2).)+?\2(?!\2)
                      | \[([^\]]+)\]
                    )
                    (?:\s*,\s*|$)
                        /sixg) {
                    my($col, $quote, $brack) = ($1, $2, $3);
                    if ( defined $quote ) {
                        # Dequote "'`
                        $col = substr $col, 1, -1;
                        $col =~ s/$quote$quote/$quote/g;
                    } elsif ( defined $brack ) {
                        # Dequote []
                        $col = $brack;
                    }
                    push @pk, $col;
                }
            }

            my $key_seq = 0;
            foreach my $pk_field (@pk) {
                push @pk_info, {
                    TABLE_SCHEM => $dbname,
                    TABLE_NAME  => $tbname,
                    COLUMN_NAME => $pk_field,
                    KEY_SEQ     => ++$key_seq,
                    PK_NAME     => 'PRIMARY KEY',
                };
            }
        }
    }

    my $sponge = DBI->connect("DBI:Sponge:", '','')
        or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
    my @names = qw(TABLE_CAT TABLE_SCHEM TABLE_NAME COLUMN_NAME KEY_SEQ PK_NAME);
    my $sth = $sponge->prepare( "primary_key_info", {
        rows          => [ map { [ @{$_}{@names} ] } @pk_info ],
        NUM_OF_FIELDS => scalar @names,
        NAME          => \@names,
    }) or return $dbh->DBI::set_err(
        $sponge->err,
        $sponge->errstr,
    );
    return $sth;
}


our %DBI_code_for_rule = ( # from DBI doc; curiously, they are not exported
                           # by the DBI module.
  # codes for update/delete constraints
  'CASCADE'             => 0,
  'RESTRICT'            => 1,
  'SET NULL'            => 2,
  'NO ACTION'           => 3,
  'SET DEFAULT'         => 4,

  # codes for deferrability
  'INITIALLY DEFERRED'  => 5,
  'INITIALLY IMMEDIATE' => 6,
  'NOT DEFERRABLE'      => 7,
 );


my @FOREIGN_KEY_INFO_ODBC = (
  'PKTABLE_CAT',       # The primary (unique) key table catalog identifier.
  'PKTABLE_SCHEM',     # The primary (unique) key table schema identifier.
  'PKTABLE_NAME',      # The primary (unique) key table identifier.
  'PKCOLUMN_NAME',     # The primary (unique) key column identifier.
  'FKTABLE_CAT',       # The foreign key table catalog identifier.
  'FKTABLE_SCHEM',     # The foreign key table schema identifier.
  'FKTABLE_NAME',      # The foreign key table identifier.
  'FKCOLUMN_NAME',     # The foreign key column identifier.
  'KEY_SEQ',           # The column sequence number (starting with 1).
  'UPDATE_RULE',       # The referential action for the UPDATE rule.
  'DELETE_RULE',       # The referential action for the DELETE rule.
  'FK_NAME',           # The foreign key name.
  'PK_NAME',           # The primary (unique) key name.
  'DEFERRABILITY',     # The deferrability of the foreign key constraint.
  'UNIQUE_OR_PRIMARY', # qualifies the key referenced by the foreign key
);

# Column names below are not used, but listed just for completeness's sake.
# Maybe we could add an option so that the user can choose which field
# names will be returned; the DBI spec is not very clear about ODBC vs. CLI.
my @FOREIGN_KEY_INFO_SQL_CLI = qw(
  UK_TABLE_CAT 
  UK_TABLE_SCHEM
  UK_TABLE_NAME
  UK_COLUMN_NAME
  FK_TABLE_CAT
  FK_TABLE_SCHEM
  FK_TABLE_NAME
  FK_COLUMN_NAME
  ORDINAL_POSITION
  UPDATE_RULE
  DELETE_RULE
  FK_NAME
  UK_NAME
  DEFERABILITY
  UNIQUE_OR_PRIMARY
 );

sub foreign_key_info {
    my ($dbh, $pk_catalog, $pk_schema, $pk_table, $fk_catalog, $fk_schema, $fk_table) = @_;

    my $databases = $dbh->selectall_arrayref("PRAGMA database_list", {Slice => {}});

    my @fk_info;
    my %table_info;
    for my $database (@$databases) {
        my $dbname = $database->{name};
        next if defined $fk_schema && $fk_schema ne '%' && $fk_schema ne $dbname;

        my $quoted_dbname = $dbh->quote_identifier($dbname);
        my $master_table =
            ($dbname eq 'main') ? 'sqlite_master' :
            ($dbname eq 'temp') ? 'sqlite_temp_master' :
            $quoted_dbname.'.sqlite_master';

        my $tables = $dbh->selectall_arrayref("SELECT name FROM $master_table WHERE type = ?", undef, "table");
        for my $table (@$tables) {
            my $tbname = $table->[0];
            next if defined $fk_table && $fk_table ne '%' && $fk_table ne $tbname;

            my $quoted_tbname = $dbh->quote_identifier($tbname);
            my $sth = $dbh->prepare("PRAGMA $quoted_dbname.foreign_key_list($quoted_tbname)");
            $sth->execute;
            while(my $row = $sth->fetchrow_hashref) {
                next if defined $pk_table && $pk_table ne '%' && $pk_table ne $row->{table};

                unless ($table_info{$row->{table}}) {
                    my $quoted_tb = $dbh->quote_identifier($row->{table});
                    for my $db (@$databases) {
                        my $quoted_db = $dbh->quote_identifier($db->{name});
                        my $t_sth = $dbh->prepare("PRAGMA $quoted_db.table_info($quoted_tb)");
                        $t_sth->execute;
                        my $cols = {};
                        while(my $r = $t_sth->fetchrow_hashref) {
                            $cols->{$r->{name}} = $r->{pk};
                        }
                        if (keys %$cols) {
                            $table_info{$row->{table}} = {
                                schema  => $db->{name},
                                columns => $cols,
                            };
                            last;
                        }
                    }
                }

                next if defined $pk_schema && $pk_schema ne '%' && $pk_schema ne $table_info{$row->{table}}{schema};

                push @fk_info, {
                    PKTABLE_CAT   => undef,
                    PKTABLE_SCHEM => $table_info{$row->{table}}{schema},
                    PKTABLE_NAME  => $row->{table},
                    PKCOLUMN_NAME => $row->{to},
                    FKTABLE_CAT   => undef,
                    FKTABLE_SCHEM => $dbname,
                    FKTABLE_NAME  => $tbname,
                    FKCOLUMN_NAME => $row->{from},
                    KEY_SEQ       => $row->{seq} + 1,
                    UPDATE_RULE   => $DBI_code_for_rule{$row->{on_update}},
                    DELETE_RULE   => $DBI_code_for_rule{$row->{on_delete}},
                    FK_NAME       => undef,
                    PK_NAME       => undef,
                    DEFERRABILITY => undef,
                    UNIQUE_OR_PRIMARY => $table_info{$row->{table}}{columns}{$row->{to}} ? 'PRIMARY' : 'UNIQUE',
                };
            }
        }
    }

    my $sponge_dbh = DBI->connect("DBI:Sponge:", "", "")
        or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
    my $sponge_sth = $sponge_dbh->prepare("foreign_key_info", {
        NAME          => \@FOREIGN_KEY_INFO_ODBC,
        rows          => [ map { [@{$_}{@FOREIGN_KEY_INFO_ODBC} ] } @fk_info ],
        NUM_OF_FIELDS => scalar(@FOREIGN_KEY_INFO_ODBC),
    }) or return $dbh->DBI::set_err(
        $sponge_dbh->err,
        $sponge_dbh->errstr,
    );
    return $sponge_sth;
}

sub type_info_all {
    return; # XXX code just copied from DBD::Oracle, not yet thought about
#    return [
#        {
#            TYPE_NAME          =>  0,
#            DATA_TYPE          =>  1,
#            COLUMN_SIZE        =>  2,
#            LITERAL_PREFIX     =>  3,
#            LITERAL_SUFFIX     =>  4,
#            CREATE_PARAMS      =>  5,
#            NULLABLE           =>  6,
#            CASE_SENSITIVE     =>  7,
#            SEARCHABLE         =>  8,
#            UNSIGNED_ATTRIBUTE =>  9,
#            FIXED_PREC_SCALE   => 10,
#            AUTO_UNIQUE_VALUE  => 11,
#            LOCAL_TYPE_NAME    => 12,
#            MINIMUM_SCALE      => 13,
#            MAXIMUM_SCALE      => 14,
#            SQL_DATA_TYPE      => 15,
#            SQL_DATETIME_SUB   => 16,
#            NUM_PREC_RADIX     => 17,
#        },
#        [ 'CHAR', 1, 255, '\'', '\'', 'max length', 1, 1, 3,
#            undef, '0', '0', undef, undef, undef, 1, undef, undef
#        ],
#        [ 'NUMBER', 3, 38, undef, undef, 'precision,scale', 1, '0', 3,
#            '0', '0', '0', undef, '0', 38, 3, undef, 10
#        ],
#        [ 'DOUBLE', 8, 15, undef, undef, undef, 1, '0', 3,
#            '0', '0', '0', undef, undef, undef, 8, undef, 10
#        ],
#        [ 'DATE', 9, 19, '\'', '\'', undef, 1, '0', 3,
#            undef, '0', '0', undef, '0', '0', 11, undef, undef
#        ],
#        [ 'VARCHAR', 12, 1024*1024, '\'', '\'', 'max length', 1, 1, 3,
#            undef, '0', '0', undef, undef, undef, 12, undef, undef
#        ]
#    ];
}

my @COLUMN_INFO = qw(
    TABLE_CAT
    TABLE_SCHEM
    TABLE_NAME
    COLUMN_NAME
    DATA_TYPE
    TYPE_NAME
    COLUMN_SIZE
    BUFFER_LENGTH
    DECIMAL_DIGITS
    NUM_PREC_RADIX
    NULLABLE
    REMARKS
    COLUMN_DEF
    SQL_DATA_TYPE
    SQL_DATETIME_SUB
    CHAR_OCTET_LENGTH
    ORDINAL_POSITION
    IS_NULLABLE
);

sub column_info {
    my ($dbh, $cat_val, $sch_val, $tbl_val, $col_val) = @_;

    if ( defined $col_val and $col_val eq '%' ) {
        $col_val = undef;
    }

    # Get a list of all tables ordered by TABLE_SCHEM, TABLE_NAME
    my $sql = <<'END_SQL';
SELECT TABLE_SCHEM, tbl_name TABLE_NAME
FROM (
    SELECT 'main' TABLE_SCHEM, tbl_name
    FROM sqlite_master
    WHERE type IN ('table','view')
UNION ALL
    SELECT 'temp' TABLE_SCHEM, tbl_name
    FROM sqlite_temp_master
    WHERE type IN ('table','view')
END_SQL

    for my $db_name (_attached_database_list($dbh)) {
        $sql .= <<"END_SQL";
UNION ALL
    SELECT '$db_name' TABLE_SCHEM, tbl_name
    FROM "$db_name".sqlite_master
    WHERE type IN ('table','view')
END_SQL
    }

    $sql .= <<'END_SQL';
UNION ALL
    SELECT 'main' TABLE_SCHEM, 'sqlite_master' tbl_name
UNION ALL
    SELECT 'temp' TABLE_SCHEM, 'sqlite_temp_master' tbl_name
)
END_SQL

    my @where;
    if ( defined $sch_val ) {
        push @where, "TABLE_SCHEM LIKE '$sch_val'";
    }
    if ( defined $tbl_val ) {
        push @where, "TABLE_NAME LIKE '$tbl_val'";
    }
    $sql .= ' WHERE ' . join("\n   AND ", @where ) . "\n" if @where;
    $sql .= " ORDER BY TABLE_SCHEM, TABLE_NAME\n";
    my $sth_tables = $dbh->prepare($sql) or return undef;
    $sth_tables->execute or return undef;

    # Taken from Fey::Loader::SQLite
    my @cols;
    while ( my ($schema, $table) = $sth_tables->fetchrow_array ) {
        my $sth_columns = $dbh->prepare(qq{PRAGMA "$schema".table_info("$table")});
        $sth_columns->execute;

        for ( my $position = 1; my $col_info = $sth_columns->fetchrow_hashref; $position++ ) {
            if ( defined $col_val ) {
                # This must do a LIKE comparison
                my $sth = $dbh->prepare("SELECT '$col_info->{name}' LIKE '$col_val'") or return undef;
                $sth->execute or return undef;
                # Skip columns that don't match $col_val
                next unless ($sth->fetchrow_array)[0];
            }

            my %col = (
                TABLE_SCHEM      => $schema,
                TABLE_NAME       => $table,
                COLUMN_NAME      => $col_info->{name},
                ORDINAL_POSITION => $position,
            );

            my $type = $col_info->{type};
            if ( $type =~ s/(\w+) ?\((\d+)(?:,(\d+))?\)/$1/ ) {
                $col{COLUMN_SIZE}    = $2;
                $col{DECIMAL_DIGITS} = $3;
            }

            $col{TYPE_NAME} = $type;

            if ( defined $col_info->{dflt_value} ) {
                $col{COLUMN_DEF} = $col_info->{dflt_value}
            }

            if ( $col_info->{notnull} ) {
                $col{NULLABLE}    = 0;
                $col{IS_NULLABLE} = 'NO';
            } else {
                $col{NULLABLE}    = 1;
                $col{IS_NULLABLE} = 'YES';
            }

            push @cols, \%col;
        }
        $sth_columns->finish;
    }
    $sth_tables->finish;

    my $sponge = DBI->connect("DBI:Sponge:", '','')
        or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
    $sponge->prepare( "column_info", {
        rows          => [ map { [ @{$_}{@COLUMN_INFO} ] } @cols ],
        NUM_OF_FIELDS => scalar @COLUMN_INFO,
        NAME          => [ @COLUMN_INFO ],
    } ) or return $dbh->DBI::set_err(
        $sponge->err,
        $sponge->errstr,
    );
}

#======================================================================
# An internal tied hash package used for %DBD::SQLite::COLLATION, to
# prevent people from unintentionally overriding globally registered collations.

package DBD::SQLite::_WriteOnceHash;

require Tie::Hash;

our @ISA = qw(Tie::StdHash);

sub TIEHASH {
    bless {}, $_[0];
}

sub STORE {
    ! exists $_[0]->{$_[1]} or die "entry $_[1] already registered";
    $_[0]->{$_[1]} = $_[2];
}

sub DELETE {
    die "deletion of entry $_[1] is forbidden";
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

DBD::SQLite - Self-contained RDBMS in a DBI Driver

=head1 SYNOPSIS

  use DBI;
  my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","");

=head1 DESCRIPTION

SQLite is a public domain file-based relational database engine that
you can find at L<http://www.sqlite.org/>.

B<DBD::SQLite> is a Perl DBI driver for SQLite, that includes
the entire thing in the distribution.
So in order to get a fast transaction capable RDBMS working for your
perl project you simply have to install this module, and B<nothing>
else.

SQLite supports the following features:

=over 4

=item Implements a large subset of SQL92

See L<http://www.sqlite.org/lang.html> for details.

=item A complete DB in a single disk file

Everything for your database is stored in a single disk file, making it
easier to move things around than with L<DBD::CSV>.

=item Atomic commit and rollback

Yes, B<DBD::SQLite> is small and light, but it supports full transactions!

=item Extensible

User-defined aggregate or regular functions can be registered with the
SQL parser.

=back

There's lots more to it, so please refer to the docs on the SQLite web
page, listed above, for SQL details. Also refer to L<DBI> for details
on how to use DBI itself. The API works like every DBI module does.
However, currently many statement attributes are not implemented or
are limited by the typeless nature of the SQLite database.

=head1 NOTABLE DIFFERENCES FROM OTHER DRIVERS

=head2 Database Name Is A File Name

SQLite creates a file per a database. You should pass the C<path> of
the database file (with or without a parent directory) in the DBI
connection string (as a database C<name>):

  my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","");

The file is opened in read/write mode, and will be created if
it does not exist yet.

Although the database is stored in a single file, the directory
containing the database file must be writable by SQLite because the
library will create several temporary files there.

If the filename C<$dbfile> is ":memory:", then a private, temporary
in-memory database is created for the connection. This in-memory
database will vanish when the database connection is closed.
It is handy for your library tests.

Note that future versions of SQLite might make use of additional
special filenames that begin with the ":" character. It is recommended
that when a database filename actually does begin with a ":" character
you should prefix the filename with a pathname such as "./" to avoid
ambiguity.

If the filename C<$dbfile> is an empty string, then a private,
temporary on-disk database will be created. This private database will
be automatically deleted as soon as the database connection is closed.

=head2 DBD::SQLite And File::Temp

When you use L<File::Temp> to create a temporary file/directory for
SQLite databases, you need to remember:

=over 4

=item tempfile may be locked exclusively

You may want to use C<tempfile()> to create a temporary database
filename for DBD::SQLite, but as noted in L<File::Temp>'s POD,
this file may have an exclusive lock under some operating systems
(notably Mac OSX), and result in a "database is locked" error.
To avoid this, set EXLOCK option to false when you call tempfile().

  ($fh, $filename) = tempfile($template, EXLOCK => 0);

=item CLEANUP may not work unless a database is disconnected

When you set CLEANUP option to true when you create a temporary
directory with C<tempdir()> or C<newdir()>, you may have to
disconnect databases explicitly before the temporary directory
is gone (notably under MS Windows).

=back

(The above is quoted from the pod of File::Temp.)

If you don't need to keep or share a temporary database,
use ":memory:" database instead. It's much handier and cleaner
for ordinary testing.

=head2 Accessing A Database With Other Tools

To access the database from the command line, try using C<dbish>
which comes with the L<DBI::Shell> module. Just type:

  dbish dbi:SQLite:foo.db

On the command line to access the file F<foo.db>.

Alternatively you can install SQLite from the link above without
conflicting with B<DBD::SQLite> and use the supplied C<sqlite3>
command line tool.

=head2 Blobs

As of version 1.11, blobs should "just work" in SQLite as text columns.
However this will cause the data to be treated as a string, so SQL
statements such as length(x) will return the length of the column as a NUL
terminated string, rather than the size of the blob in bytes. In order to
store natively as a BLOB use the following code:

  use DBI qw(:sql_types);
  my $dbh = DBI->connect("dbi:SQLite:dbfile","","");
  
  my $blob = `cat foo.jpg`;
  my $sth = $dbh->prepare("INSERT INTO mytable VALUES (1, ?)");
  $sth->bind_param(1, $blob, SQL_BLOB);
  $sth->execute();

And then retrieval just works:

  $sth = $dbh->prepare("SELECT * FROM mytable WHERE id = 1");
  $sth->execute();
  my $row = $sth->fetch;
  my $blobo = $row->[1];
  
  # now $blobo == $blob

=head2 Functions And Bind Parameters

As of this writing, a SQL that compares a return value of a function
with a numeric bind value like this doesn't work as you might expect.

  my $sth = $dbh->prepare(q{
    SELECT bar FROM foo GROUP BY bar HAVING count(*) > ?;
  });
  $sth->execute(5);

This is because DBD::SQLite assumes that all the bind values are text
(and should be quoted) by default. Thus the above statement becomes
like this while executing:

  SELECT bar FROM foo GROUP BY bar HAVING count(*) > "5";

There are three workarounds for this.

=over 4

=item Use bind_param() explicitly

As shown above in the C<BLOB> section, you can always use
C<bind_param()> to tell the type of a bind value.

  use DBI qw(:sql_types);  # Don't forget this
  
  my $sth = $dbh->prepare(q{
    SELECT bar FROM foo GROUP BY bar HAVING count(*) > ?;
  });
  $sth->bind_param(1, 5, SQL_INTEGER);
  $sth->execute();

=item Add zero to make it a number

This is somewhat weird, but works anyway.

  my $sth = $dbh->prepare(q{
    SELECT bar FROM foo GROUP BY bar HAVING count(*) > (? + 0);
  });
  $sth->execute(5);

=item Set C<sqlite_see_if_its_a_number> database handle attribute

As of version 1.32_02, you can use C<sqlite_see_if_its_a_number>
to let DBD::SQLite to see if the bind values are numbers or not.

  $dbh->{sqlite_see_if_its_a_number} = 1;
  my $sth = $dbh->prepare(q{
    SELECT bar FROM foo GROUP BY bar HAVING count(*) > ?;
  });
  $sth->execute(5);

You can set it to true when you connect to a database.

  my $dbh = DBI->connect('dbi:SQLite:foo', undef, undef, {
    AutoCommit => 1,
    RaiseError => 1,
    sqlite_see_if_its_a_number => 1,
  });

This is the most straightforward solution, but as noted above,
existing data in your databases created by DBD::SQLite have not
always been stored as numbers, so this *might* cause other obscure
problems. Use this sparingly when you handle existing databases.
If you handle databases created by other tools like native C<sqlite3>
command line tool, this attribute would help you.

=back

=head2 Placeholders

SQLite supports several placeholder expressions, including C<?>
and C<:AAAA>. Consult the L<DBI> and sqlite documentation for
details. 

L<http://www.sqlite.org/lang_expr.html#varparam>

Note that a question mark actually means a next unused (numbered)
placeholder. You're advised not to use it with other (numbered or
named) placeholders to avoid confusion.

  my $sth = $dbh->prepare(
    'update TABLE set a=?1 where b=?2 and a IS NOT ?1'
  );
  $sth->execute(1, 2); 

=head2 Foreign Keys

B<BE PREPARED! WOLVES APPROACH!!>

SQLite has started supporting foreign key constraints since 3.6.19
(released on Oct 14, 2009; bundled in DBD::SQLite 1.26_05).
To be exact, SQLite has long been able to parse a schema with foreign
keys, but the constraints has not been enforced. Now you can issue
a pragma actually to enable this feature and enforce the constraints.

To do this, issue the following pragma (see below), preferably as
soon as you connect to a database and you're not in a transaction:

  $dbh->do("PRAGMA foreign_keys = ON");

And you can explicitly disable the feature whenever you like by
turning the pragma off:

  $dbh->do("PRAGMA foreign_keys = OFF");

As of this writing, this feature is disabled by default by the
sqlite team, and by us, to secure backward compatibility, as
this feature may break your applications, and actually broke
some for us. If you have used a schema with foreign key constraints
but haven't cared them much and supposed they're always ignored for
SQLite, be prepared, and B<please do extensive testing to ensure
that your applications will continue to work when the foreign keys
support is enabled by default>. It is very likely that the sqlite
team will turn it default-on in the future, and we plan to do it
NO LATER THAN they do so.

See L<http://www.sqlite.org/foreignkeys.html> for details.

=head2 Pragma

SQLite has a set of "Pragma"s to modify its operation or to query
for its internal data. These are specific to SQLite and are not
likely to work with other DBD libraries, but you may find some of
these are quite useful, including:

=over 4

=item journal_mode

You can use this pragma to change the journal mode for SQLite
databases, maybe for better performance, or for compatibility.

Its default mode is C<DELETE>, which means SQLite uses a rollback
journal to implement transactions, and the journal is deleted
at the conclusion of each transaction. If you use C<TRUNCATE>
instead of C<DELETE>, the journal will be truncated, which is
usually much faster.

A C<WAL> (write-ahead log) mode is introduced as of SQLite 3.7.0.
This mode is persistent, and it stays in effect even after
closing and reopening the database. In other words, once the C<WAL>
mode is set in an application or in a test script, the database
becomes inaccessible by older clients. This tends to be an issue
when you use a system C<sqlite3> executable under a conservative
operating system.

To fix this, You need to issue C<PRAGMA journal_mode = DELETE>
(or C<TRUNCATE>) beforehand, or install a newer version of
C<sqlite3>.

=item legacy_file_format

If you happen to need to create a SQLite database that will also
be accessed by a very old SQLite client (prior to 3.3.0 released
in Jan. 2006), you need to set this pragma to ON before you create
a database.

=item reverse_unordered_selects

You can set this pragma to ON to reverse the order of results of
SELECT statements without an ORDER BY clause so that you can see
if applications are making invalid assumptions about the result
order.

Note that SQLite 3.7.15 (bundled with DBD::SQLite 1.38_02) enhanced
its query optimizer and the order of results of a SELECT statement
without an ORDER BY clause may be different from the one of the
previous versions.

=item synchronous

You can set set this pragma to OFF to make some of the operations
in SQLite faster with a possible risk of database corruption
in the worst case. See also L</"Performance"> section below.

=back

See L<http://www.sqlite.org/pragma.html> for more details.

=head2 Transactions

DBI/DBD::SQLite's transactions may be a bit confusing. They behave
differently according to the status of the C<AutoCommit> flag:

=over 4

=item When the AutoCommit flag is on

You're supposed to always use the auto-commit mode, except you
explicitly begin a transaction, and when the transaction ended,
you're supposed to go back to the auto-commit mode. To begin a
transaction, call C<begin_work> method, or issue a C<BEGIN>
statement. To end it, call C<commit/rollback> methods, or issue
the corresponding statements.

  $dbh->{AutoCommit} = 1;
  
  $dbh->begin_work; # or $dbh->do('BEGIN TRANSACTION');
  
  # $dbh->{AutoCommit} is turned off temporarily during a transaction;
  
  $dbh->commit; # or $dbh->do('COMMIT');
  
  # $dbh->{AutoCommit} is turned on again;

=item When the AutoCommit flag is off

You're supposed to always use the transactional mode, until you
explicitly turn on the AutoCommit flag. You can explicitly issue
a C<BEGIN> statement (only when an actual transaction has not
begun yet) but you're not allowed to call C<begin_work> method
(if you don't issue a C<BEGIN>, it will be issued internally).
You can commit or roll it back freely. Another transaction will
automatically begins if you execute another statement.

  $dbh->{AutoCommit} = 0;
  
  # $dbh->do('BEGIN TRANSACTION') is not necessary, but possible
  
  ...
  
  $dbh->commit; # or $dbh->do('COMMIT');
  
  # $dbh->{AutoCommit} stays intact;
  
  $dbh->{AutoCommit} = 1;  # ends the transactional mode

=back

This C<AutoCommit> mode is independent from the autocommit mode
of the internal SQLite library, which always begins by a C<BEGIN>
statement, and ends by a C<COMMIT> or a <ROLLBACK>.

=head2 Transaction and Database Locking

The default transaction behavior of SQLite is C<deferred>, that
means, locks are not acquired until the first read or write
operation, and thus it is possible that another thread or process
could create a separate transaction and write to the database after
the C<BEGIN> on the current thread has executed, and eventually
cause a "deadlock". To avoid this, DBD::SQLite internally issues
a C<BEGIN IMMEDIATE> when you begin a transaction by
C<begin_work> or under the C<AutoCommit> mode (since 1.38_01).

If you really need to turn off this feature for some reasons,
set C<sqlite_use_immediate_transaction> database handle attribute
to false, and the default C<deferred> transaction will be used.

  my $dbh = DBI->connect("dbi:SQLite::memory:", "", "", {
    sqlite_use_immediate_transaction => 0,
  });

See L<http://sqlite.org/lockingv3.html> for locking details.

=head2 C<< $sth->finish >> and Transaction Rollback

As the L<DBI> doc says, you almost certainly do B<not> need to
call L<DBI/finish> method if you fetch all rows (probably in a loop).
However, there are several exceptions to this rule, and rolling-back
of an unfinished C<SELECT> statement is one of such exceptional
cases. 

SQLite prohibits C<ROLLBACK> of unfinished C<SELECT> statements in
a transaction (See L<http://sqlite.org/lang_transaction.html> for
details). So you need to call C<finish> before you issue a rollback.

  $sth = $dbh->prepare("SELECT * FROM t");
  $dbh->begin_work;
  eval {
      $sth->execute;
      $row = $sth->fetch;
      ...
      die "For some reason";
      ...
  };
  if($@) {
     $sth->finish;  # You need this for SQLite
     $dbh->rollback;
  } else {
     $dbh->commit;
  }

=head2 Processing Multiple Statements At A Time

L<DBI>'s statement handle is not supposed to process multiple
statements at a time. So if you pass a string that contains multiple
statements (a C<dump>) to a statement handle (via C<prepare> or C<do>),
L<DBD::SQLite> only processes the first statement, and discards the
rest.

Since 1.30_01, you can retrieve those ignored (unprepared) statements
via C<< $sth->{sqlite_unprepared_statements} >>. It usually contains
nothing but white spaces, but if you really care, you can check this
attribute to see if there's anything left undone. Also, if you set
a C<sqlite_allow_multiple_statements> attribute of a database handle
to true when you connect to a database, C<do> method automatically
checks the C<sqlite_unprepared_statements> attribute, and if it finds
anything undone (even if what's left is just a single white space),
it repeats the process again, to the end.

=head2 Performance

SQLite is fast, very fast. Matt processed his 72MB log file with it,
inserting the data (400,000+ rows) by using transactions and only
committing every 1000 rows (otherwise the insertion is quite slow),
and then performing queries on the data.

Queries like count(*) and avg(bytes) took fractions of a second to
return, but what surprised him most of all was:

  SELECT url, count(*) as count
  FROM access_log
  GROUP BY url
  ORDER BY count desc
  LIMIT 20

To discover the top 20 hit URLs on the site (L<http://axkit.org>),
and it returned within 2 seconds. He was seriously considering
switching his log analysis code to use this little speed demon!

Oh yeah, and that was with no indexes on the table, on a 400MHz PIII.

For best performance be sure to tune your hdparm settings if you
are using linux. Also you might want to set:

  PRAGMA synchronous = OFF

Which will prevent sqlite from doing fsync's when writing (which
slows down non-transactional writes significantly) at the expense
of some peace of mind. Also try playing with the cache_size pragma.

The memory usage of SQLite can also be tuned using the cache_size
pragma.

  $dbh->do("PRAGMA cache_size = 800000");

The above will allocate 800M for DB cache; the default is 2M.
Your sweet spot probably lies somewhere in between.

=head1 DRIVER PRIVATE ATTRIBUTES

=head2 Database Handle Attributes

=over 4

=item sqlite_version

Returns the version of the SQLite library which B<DBD::SQLite> is using,
e.g., "2.8.0". Can only be read.

=item sqlite_unicode

If set to a true value, B<DBD::SQLite> will turn the UTF-8 flag on for all
text strings coming out of the database (this feature is currently disabled
for perl < 5.8.5). For more details on the UTF-8 flag see
L<perlunicode>. The default is for the UTF-8 flag to be turned off.

Also note that due to some bizarreness in SQLite's type system (see
L<http://www.sqlite.org/datatype3.html>), if you want to retain
blob-style behavior for B<some> columns under C<< $dbh->{sqlite_unicode} = 1
>> (say, to store images in the database), you have to state so
explicitly using the 3-argument form of L<DBI/bind_param> when doing
updates:

  use DBI qw(:sql_types);
  $dbh->{sqlite_unicode} = 1;
  my $sth = $dbh->prepare("INSERT INTO mytable (blobcolumn) VALUES (?)");
  
  # Binary_data will be stored as is.
  $sth->bind_param(1, $binary_data, SQL_BLOB);

Defining the column type as C<BLOB> in the DDL is B<not> sufficient.

This attribute was originally named as C<unicode>, and renamed to
C<sqlite_unicode> for integrity since version 1.26_06. Old C<unicode>
attribute is still accessible but will be deprecated in the near future.

=item sqlite_allow_multiple_statements

If you set this to true, C<do> method will process multiple
statements at one go. This may be handy, but with performance
penalty. See above for details.

=item sqlite_use_immediate_transaction

If you set this to true, DBD::SQLite tries to issue a C<begin
immediate transaction> (instead of C<begin transaction>) when
necessary. See above for details.

As of version 1.38_01, this attribute is set to true by default.
If you really need to use C<deferred> transactions for some reasons,
set this to false explicitly.

=item sqlite_see_if_its_a_number

If you set this to true, DBD::SQLite tries to see if the bind values
are number or not, and does not quote if they are numbers. See above
for details.

=back

=head2 Statement Handle Attributes

=over 4

=item sqlite_unprepared_statements

Returns an unprepared part of the statement you pass to C<prepare>.
Typically this contains nothing but white spaces after a semicolon.
See above for details.

=back

=head1 METHODS

See also to the L<DBI> documentation for the details of other common
methods.

=head2 table_info

  $sth = $dbh->table_info(undef, $schema, $table, $type, \%attr);

Returns all tables and schemas (databases) as specified in L<DBI/table_info>.
The schema and table arguments will do a C<LIKE> search. You can specify an
ESCAPE character by including an 'Escape' attribute in \%attr. The C<$type>
argument accepts a comma separated list of the following types 'TABLE',
'VIEW', 'LOCAL TEMPORARY' and 'SYSTEM TABLE' (by default all are returned).
Note that a statement handle is returned, and not a direct list of tables.

The following fields are returned:

B<TABLE_CAT>: Always NULL, as SQLite does not have the concept of catalogs.

B<TABLE_SCHEM>: The name of the schema (database) that the table or view is
in. The default schema is 'main', temporary tables are in 'temp' and other
databases will be in the name given when the database was attached.

B<TABLE_NAME>: The name of the table or view.

B<TABLE_TYPE>: The type of object returned. Will be one of 'TABLE', 'VIEW',
'LOCAL TEMPORARY' or 'SYSTEM TABLE'.

=head2 primary_key, primary_key_info

  @names = $dbh->primary_key(undef, $schema, $table);
  $sth   = $dbh->primary_key_info(undef, $schema, $table, \%attr);

You can retrieve primary key names or more detailed information.
As noted above, SQLite does not have the concept of catalogs, so the
first argument of the methods is usually C<undef>, and you'll usually
set C<undef> for the second one (unless you want to know the primary
keys of temporary tables).


=head2 foreign_key_info

  $sth = $dbh->foreign_key_info(undef, $pk_schema, $pk_table,
                                undef, $fk_schema, $fk_table);

Returns information about foreign key constraints, as specified in
L<DBI/foreign_key_info>, but with some limitations : 

=over

=item *

information in rows returned by the C<$sth> is incomplete with
respect to the L<DBI/foreign_key_info> specification. All requested fields
are present, but the content is C<undef> for some of them.

=back

The following nonempty fields are returned :

B<PKTABLE_NAME>:
The primary (unique) key table identifier.

B<PKCOLUMN_NAME>:
The primary (unique) key column identifier.

B<FKTABLE_NAME>:
The foreign key table identifier.

B<FKCOLUMN_NAME>:
The foreign key column identifier.

B<KEY_SEQ>:
The column sequence number (starting with 1), when
several columns belong to a same constraint.

B<UPDATE_RULE>:
The referential action for the UPDATE rule.
The following codes are defined:

  CASCADE              0
  RESTRICT             1
  SET NULL             2
  NO ACTION            3
  SET DEFAULT          4

Default is 3 ('NO ACTION').

B<DELETE_RULE>:
The referential action for the DELETE rule.
The codes are the same as for UPDATE_RULE.

Unfortunately, the B<DEFERRABILITY> field is always C<undef>;
as a matter of fact, deferrability clauses are supported by SQLite,
but they can't be reported because the C<PRAGMA foreign_key_list>
tells nothing about them.

B<UNIQUE_OR_PRIMARY>:
Whether the column is primary or unique.

B<Note>: foreign key support in SQLite must be explicitly turned on through
a C<PRAGMA> command; see L</"Foreign keys"> earlier in this manual.

=head2 ping

  my $bool = $dbh->ping;

returns true if the database file exists (or the database is in-memory), and the database connection is active.

=head1 DRIVER PRIVATE METHODS

The following methods can be called via the func() method with a little
tweak, but the use of func() method is now discouraged by the L<DBI> author
for various reasons (see DBI's document
L<http://search.cpan.org/dist/DBI/lib/DBI/DBD.pm#Using_install_method()_to_expose_driver-private_methods>
for details). So, if you're using L<DBI> >= 1.608, use these C<sqlite_>
methods. If you need to use an older L<DBI>, you can call these like this:

  $dbh->func( ..., "(method name without sqlite_ prefix)" );

Exception: C<sqlite_trace> should always be called as is, even with C<func()>
method (to avoid conflict with DBI's trace() method).

  $dbh->func( ..., "sqlite_trace");

=head2 $dbh->sqlite_last_insert_rowid()

This method returns the last inserted rowid. If you specify an INTEGER PRIMARY
KEY as the first column in your table, that is the column that is returned.
Otherwise, it is the hidden ROWID column. See the sqlite docs for details.

Generally you should not be using this method. Use the L<DBI> last_insert_id
method instead. The usage of this is:

  $h->last_insert_id($catalog, $schema, $table_name, $field_name [, \%attr ])

Running C<$h-E<gt>last_insert_id("","","","")> is the equivalent of running
C<$dbh-E<gt>sqlite_last_insert_rowid()> directly.

=head2 $dbh->sqlite_db_filename()

Retrieve the current (main) database filename. If the database is in-memory or temporary, this returns C<undef>.

=head2 $dbh->sqlite_busy_timeout()

Retrieve the current busy timeout.

=head2 $dbh->sqlite_busy_timeout( $ms )

Set the current busy timeout. The timeout is in milliseconds.

=head2 $dbh->sqlite_create_function( $name, $argc, $code_ref )

This method will register a new function which will be usable in an SQL
query. The method's parameters are:

=over

=item $name

The name of the function. This is the name of the function as it will
be used from SQL.

=item $argc

The number of arguments taken by the function. If this number is -1,
the function can take any number of arguments.

=item $code_ref

This should be a reference to the function's implementation.

=back

For example, here is how to define a now() function which returns the
current number of seconds since the epoch:

  $dbh->sqlite_create_function( 'now', 0, sub { return time } );

After this, it could be use from SQL as:

  INSERT INTO mytable ( now() );

=head3 REGEXP function

SQLite includes syntactic support for an infix operator 'REGEXP', but
without any implementation. The C<DBD::SQLite> driver
automatically registers an implementation that performs standard
perl regular expression matching, using current locale. So for example
you can search for words starting with an 'A' with a query like

  SELECT * from table WHERE column REGEXP '\bA\w+'

If you want case-insensitive searching, use perl regex flags, like this :

  SELECT * from table WHERE column REGEXP '(?i:\bA\w+)'

The default REGEXP implementation can be overridden through the
C<create_function> API described above.

Note that regexp matching will B<not> use SQLite indices, but will iterate
over all rows, so it could be quite costly in terms of performance.

=head2 $dbh->sqlite_create_collation( $name, $code_ref )

This method manually registers a new function which will be usable in an SQL
query as a COLLATE option for sorting. Such functions can also be registered
automatically on demand: see section L</"COLLATION FUNCTIONS"> below.

The method's parameters are:

=over

=item $name

The name of the function exposed to SQL.

=item $code_ref

Reference to the function's implementation.
The driver will check that this is a proper sorting function.

=back

=head2 $dbh->sqlite_collation_needed( $code_ref )

This method manually registers a callback function that will
be invoked whenever an undefined collation sequence is required
from an SQL statement. The callback is invoked as

  $code_ref->($dbh, $collation_name)

and should register the desired collation using
L</"sqlite_create_collation">.

An initial callback is already registered by C<DBD::SQLite>,
so for most common cases it will be simpler to just
add your collation sequences in the C<%DBD::SQLite::COLLATION>
hash (see section L</"COLLATION FUNCTIONS"> below).

=head2 $dbh->sqlite_create_aggregate( $name, $argc, $pkg )

This method will register a new aggregate function which can then be used
from SQL. The method's parameters are:

=over

=item $name

The name of the aggregate function, this is the name under which the
function will be available from SQL.

=item $argc

This is an integer which tells the SQL parser how many arguments the
function takes. If that number is -1, the function can take any number
of arguments.

=item $pkg

This is the package which implements the aggregator interface.

=back

The aggregator interface consists of defining three methods:

=over

=item new()

This method will be called once to create an object which should
be used to aggregate the rows in a particular group. The step() and
finalize() methods will be called upon the reference return by
the method.

=item step(@_)

This method will be called once for each row in the aggregate.

=item finalize()

This method will be called once all rows in the aggregate were
processed and it should return the aggregate function's result. When
there is no rows in the aggregate, finalize() will be called right
after new().

=back

Here is a simple aggregate function which returns the variance
(example adapted from pysqlite):

  package variance;
  
  sub new { bless [], shift; }
  
  sub step {
      my ( $self, $value ) = @_;
  
      push @$self, $value;
  }
  
  sub finalize {
      my $self = $_[0];
  
      my $n = @$self;
  
      # Variance is NULL unless there is more than one row
      return undef unless $n || $n == 1;
  
      my $mu = 0;
      foreach my $v ( @$self ) {
          $mu += $v;
      }
      $mu /= $n;
  
      my $sigma = 0;
      foreach my $v ( @$self ) {
          $sigma += ($v - $mu)**2;
      }
      $sigma = $sigma / ($n - 1);
  
      return $sigma;
  }
  
  $dbh->sqlite_create_aggregate( "variance", 1, 'variance' );

The aggregate function can then be used as:

  SELECT group_name, variance(score)
  FROM results
  GROUP BY group_name;

For more examples, see the L<DBD::SQLite::Cookbook>.

=head2 $dbh->sqlite_progress_handler( $n_opcodes, $code_ref )

This method registers a handler to be invoked periodically during long
running calls to SQLite.

An example use for this interface is to keep a GUI updated during a
large query. The parameters are:

=over

=item $n_opcodes

The progress handler is invoked once for every C<$n_opcodes>
virtual machine opcodes in SQLite.

=item $code_ref

Reference to the handler subroutine.  If the progress handler returns
non-zero, the SQLite operation is interrupted. This feature can be used to
implement a "Cancel" button on a GUI dialog box.

Set this argument to C<undef> if you want to unregister a previous
progress handler.

=back

=head2 $dbh->sqlite_commit_hook( $code_ref )

This method registers a callback function to be invoked whenever a
transaction is committed. Any callback set by a previous call to
C<sqlite_commit_hook> is overridden. A reference to the previous
callback (if any) is returned.  Registering an C<undef> disables the
callback.

When the commit hook callback returns zero, the commit operation is
allowed to continue normally. If the callback returns non-zero, then
the commit is converted into a rollback (in that case, any attempt to
I<explicitly> call C<< $dbh->rollback() >> afterwards would yield an
error).

=head2 $dbh->sqlite_rollback_hook( $code_ref )

This method registers a callback function to be invoked whenever a
transaction is rolled back. Any callback set by a previous call to
C<sqlite_rollback_hook> is overridden. A reference to the previous
callback (if any) is returned.  Registering an C<undef> disables the
callback.

=head2 $dbh->sqlite_update_hook( $code_ref )

This method registers a callback function to be invoked whenever a row
is updated, inserted or deleted. Any callback set by a previous call to
C<sqlite_update_hook> is overridden. A reference to the previous
callback (if any) is returned.  Registering an C<undef> disables the
callback.

The callback will be called as

  $code_ref->($action_code, $database, $table, $rowid)

where

=over

=item $action_code

is an integer equal to either C<DBD::SQLite::INSERT>,
C<DBD::SQLite::DELETE> or C<DBD::SQLite::UPDATE>
(see L</"Action Codes">);

=item $database

is the name of the database containing the affected row;

=item $table

is the name of the table containing the affected row;

=item $rowid

is the unique 64-bit signed integer key of the affected row within
that table.

=back

=head2 $dbh->sqlite_set_authorizer( $code_ref )

This method registers an authorizer callback to be invoked whenever
SQL statements are being compiled by the L<DBI/prepare> method.  The
authorizer callback should return C<DBD::SQLite::OK> to allow the
action, C<DBD::SQLite::IGNORE> to disallow the specific action but
allow the SQL statement to continue to be compiled, or
C<DBD::SQLite::DENY> to cause the entire SQL statement to be rejected
with an error. If the authorizer callback returns any other value,
then C<prepare> call that triggered the authorizer will fail with
an error message.

An authorizer is used when preparing SQL statements from an untrusted
source, to ensure that the SQL statements do not try to access data
they are not allowed to see, or that they do not try to execute
malicious statements that damage the database. For example, an
application may allow a user to enter arbitrary SQL queries for
evaluation by a database. But the application does not want the user
to be able to make arbitrary changes to the database. An authorizer
could then be put in place while the user-entered SQL is being
prepared that disallows everything except SELECT statements.

The callback will be called as

  $code_ref->($action_code, $string1, $string2, $database, $trigger_or_view)

where

=over

=item $action_code

is an integer that specifies what action is being authorized
(see L</"Action Codes">).

=item $string1, $string2

are strings that depend on the action code
(see L</"Action Codes">).

=item $database

is the name of the database (C<main>, C<temp>, etc.) if applicable.

=item $trigger_or_view

is the name of the inner-most trigger or view that is responsible for
the access attempt, or C<undef> if this access attempt is directly from
top-level SQL code.

=back

=head2 $dbh->sqlite_backup_from_file( $filename )

This method accesses the SQLite Online Backup API, and will take a backup of
the named database file, copying it to, and overwriting, your current database
connection. This can be particularly handy if your current connection is to the
special :memory: database, and you wish to populate it from an existing DB.

=head2 $dbh->sqlite_backup_to_file( $filename )

This method accesses the SQLite Online Backup API, and will take a backup of
the currently connected database, and write it out to the named file.

=head2 $dbh->sqlite_enable_load_extension( $bool )

Calling this method with a true value enables loading (external)
sqlite3 extensions. After the call, you can load extensions like this:

  $dbh->sqlite_enable_load_extension(1);
  $sth = $dbh->prepare("select load_extension('libsqlitefunctions.so')")
  or die "Cannot prepare: " . $dbh->errstr();

=head2 $dbh->sqlite_load_extension( $file, $proc )

Loading an extension by a select statement (with the "load_extension" sqlite3 function like above) has some limitations. If you need to, say, create other functions from an extension, use this method. $file (a path to the extension) is mandatory, and $proc (an entry point name) is optional. You need to call C<sqlite_enable_load_extension> before calling C<sqlite_load_extension>.

=head2 $dbh->sqlite_trace( $code_ref )

This method registers a trace callback to be invoked whenever
SQL statements are being run.

The callback will be called as

  $code_ref->($statement)

where

=over

=item $statement

is a UTF-8 rendering of the SQL statement text as the statement
first begins executing.

=back

Additional callbacks might occur as each triggered subprogram is
entered. The callbacks for triggers contain a UTF-8 SQL comment
that identifies the trigger.

See also L<DBI/TRACING> for better tracing options.

=head2 $dbh->sqlite_profile( $code_ref )

This method registers a profile callback to be invoked whenever
a SQL statement finishes.

The callback will be called as

  $code_ref->($statement, $elapsed_time)

where

=over

=item $statement

is the original statement text (without bind parameters).

=item $elapsed_time

is an estimate of wall-clock time of how long that statement took to run (in milliseconds).

=back

This method is considered experimental and is subject to change in future versions of SQLite.

See also L<DBI::Profile> for better profiling options.

=head2 $dbh->sqlite_table_column_metadata( $dbname, $tablename, $columnname )

is for internal use only.

=head2 DBD::SQLite::compile_options()

Returns an array of compile options (available since sqlite 3.6.23,
bundled in DBD::SQLite 1.30_01), or an empty array if the bundled
library is old or compiled with SQLITE_OMIT_COMPILEOPTION_DIAGS.

=head2 DBD::SQLite::sqlite_status()

Returns a hash reference that holds a set of status information of SQLite runtime such as memory usage or page cache usage (see L<http://www.sqlite.org/c3ref/c_status_malloc_count.html> for details). Each of the entry contains the current value and the highwater value.

  my $status = DBD::SQLite::sqlite_status();
  my $cur  = $status->{memory_used}{current};
  my $high = $status->{memory_used}{highwater};

You may also pass 0 as an argument to reset the status.

=head2 $dbh->sqlite_db_status()

Returns a hash reference that holds a set of status information of database connection such as cache usage. See L<http://www.sqlite.org/c3ref/c_dbstatus_options.html> for details. You may also pass 0 as an argument to reset the status.

=head2 $sth->sqlite_st_status()

Returns a hash reference that holds a set of status information of SQLite statement handle such as full table scan count. See L<http://www.sqlite.org/c3ref/c_stmtstatus_counter.html> for details. Statement status only holds the current value.

  my $status = $sth->sqlite_st_status();
  my $cur = $status->{fullscan_step};

You may also pass 0 as an argument to reset the status.

=head1 DRIVER CONSTANTS

A subset of SQLite C constants are made available to Perl,
because they may be needed when writing
hooks or authorizer callbacks. For accessing such constants,
the C<DBD::SQLite> module must be explicitly C<use>d at compile
time. For example, an authorizer that forbids any
DELETE operation would be written as follows :

  use DBD::SQLite;
  $dbh->sqlite_set_authorizer(sub {
    my $action_code = shift;
    return $action_code == DBD::SQLite::DELETE ? DBD::SQLite::DENY
                                               : DBD::SQLite::OK;
  });

The list of constants implemented in C<DBD::SQLite> is given
below; more information can be found ad
at L<http://www.sqlite.org/c3ref/constlist.html>.

=head2 Authorizer Return Codes

  OK
  DENY
  IGNORE

=head2 Action Codes

The L</set_authorizer> method registers a callback function that is
invoked to authorize certain SQL statement actions. The first
parameter to the callback is an integer code that specifies what
action is being authorized. The second and third parameters to the
callback are strings, the meaning of which varies according to the
action code. Below is the list of action codes, together with their
associated strings.

  # constant              string1         string2
  # ========              =======         =======
  CREATE_INDEX            Index Name      Table Name
  CREATE_TABLE            Table Name      undef
  CREATE_TEMP_INDEX       Index Name      Table Name
  CREATE_TEMP_TABLE       Table Name      undef
  CREATE_TEMP_TRIGGER     Trigger Name    Table Name
  CREATE_TEMP_VIEW        View Name       undef
  CREATE_TRIGGER          Trigger Name    Table Name
  CREATE_VIEW             View Name       undef
  DELETE                  Table Name      undef
  DROP_INDEX              Index Name      Table Name
  DROP_TABLE              Table Name      undef
  DROP_TEMP_INDEX         Index Name      Table Name
  DROP_TEMP_TABLE         Table Name      undef
  DROP_TEMP_TRIGGER       Trigger Name    Table Name
  DROP_TEMP_VIEW          View Name       undef
  DROP_TRIGGER            Trigger Name    Table Name
  DROP_VIEW               View Name       undef
  INSERT                  Table Name      undef
  PRAGMA                  Pragma Name     1st arg or undef
  READ                    Table Name      Column Name
  SELECT                  undef           undef
  TRANSACTION             Operation       undef
  UPDATE                  Table Name      Column Name
  ATTACH                  Filename        undef
  DETACH                  Database Name   undef
  ALTER_TABLE             Database Name   Table Name
  REINDEX                 Index Name      undef
  ANALYZE                 Table Name      undef
  CREATE_VTABLE           Table Name      Module Name
  DROP_VTABLE             Table Name      Module Name
  FUNCTION                undef           Function Name
  SAVEPOINT               Operation       Savepoint Name

=head1 COLLATION FUNCTIONS

=head2 Definition

SQLite v3 provides the ability for users to supply arbitrary
comparison functions, known as user-defined "collation sequences" or
"collating functions", to be used for comparing two text values.
L<http://www.sqlite.org/datatype3.html#collation>
explains how collations are used in various SQL expressions.

=head2 Builtin collation sequences

The following collation sequences are builtin within SQLite :

=over

=item B<BINARY>

Compares string data using memcmp(), regardless of text encoding.

=item B<NOCASE>

The same as binary, except the 26 upper case characters of ASCII are
folded to their lower case equivalents before the comparison is
performed. Note that only ASCII characters are case folded. SQLite
does not attempt to do full UTF case folding due to the size of the
tables required.

=item B<RTRIM>

The same as binary, except that trailing space characters are ignored.

=back

In addition, C<DBD::SQLite> automatically installs the
following collation sequences :

=over

=item B<perl>

corresponds to the Perl C<cmp> operator

=item B<perllocale>

Perl C<cmp> operator, in a context where C<use locale> is activated.

=back

=head2 Usage

You can write for example

  CREATE TABLE foo(
      txt1 COLLATE perl,
      txt2 COLLATE perllocale,
      txt3 COLLATE nocase
  )

or

  SELECT * FROM foo ORDER BY name COLLATE perllocale

=head2 Unicode handling

If the attribute C<< $dbh->{sqlite_unicode} >> is set, strings coming from
the database and passed to the collation function will be properly
tagged with the utf8 flag; but this only works if the
C<sqlite_unicode> attribute is set B<before> the first call to
a perl collation sequence . The recommended way to activate unicode
is to set the parameter at connection time :

  my $dbh = DBI->connect(
      "dbi:SQLite:dbname=foo", "", "",
      {
          RaiseError     => 1,
          sqlite_unicode => 1,
      }
  );

=head2 Adding user-defined collations

The native SQLite API for adding user-defined collations is
exposed through methods L</"sqlite_create_collation"> and
L</"sqlite_collation_needed">.

To avoid calling these functions every time a C<$dbh> handle is
created, C<DBD::SQLite> offers a simpler interface through the
C<%DBD::SQLite::COLLATION> hash : just insert your own
collation functions in that hash, and whenever an unknown
collation name is encountered in SQL, the appropriate collation
function will be loaded on demand from the hash. For example,
here is a way to sort text values regardless of their accented
characters :

  use DBD::SQLite;
  $DBD::SQLite::COLLATION{no_accents} = sub {
    my ( $a, $b ) = map lc, @_;
    tr[àâáäåãçðèêéëìîíïñòôóöõøùûúüý]
      [aaaaaacdeeeeiiiinoooooouuuuy] for $a, $b;
    $a cmp $b;
  };
  my $dbh  = DBI->connect("dbi:SQLite:dbname=dbfile");
  my $sql  = "SELECT ... FROM ... ORDER BY ... COLLATE no_accents");
  my $rows = $dbh->selectall_arrayref($sql);

The builtin C<perl> or C<perllocale> collations are predefined
in that same hash.

The COLLATION hash is a global registry within the current process;
hence there is a risk of undesired side-effects. Therefore, to
prevent action at distance, the hash is implemented as a "write-only"
hash, that will happily accept new entries, but will raise an
exception if any attempt is made to override or delete a existing
entry (including the builtin C<perl> and C<perllocale>).

If you really, really need to change or delete an entry, you can
always grab the tied object underneath C<%DBD::SQLite::COLLATION> ---
but don't do that unless you really know what you are doing. Also
observe that changes in the global hash will not modify existing
collations in existing database handles: it will only affect new
I<requests> for collations. In other words, if you want to change
the behaviour of a collation within an existing C<$dbh>, you
need to call the L</create_collation> method directly.

=head1 FULLTEXT SEARCH

The FTS extension module within SQLite allows users to create special
tables with a built-in full-text index (hereafter "FTS tables"). The
full-text index allows the user to efficiently query the database for
all rows that contain one or more instances of a specified word (hereafter
a "token"), even if the table contains many large documents.

=head2 Short introduction to FTS

The first full-text search modules for SQLite were called C<FTS1> and C<FTS2>
and are now obsolete. The latest recommended module is C<FTS4>; however
the former module C<FTS3> is still supporter. 
Detailed documentation for both C<FTS4> and C<FTS3> can be found
at L<http://www.sqlite.org/fts3.html>, including explanations about the
differences between these two versions.

Here is a very short example of using FTS :

  $dbh->do(<<"") or die DBI::errstr;
  CREATE VIRTUAL TABLE fts_example USING fts4(content)
  
  my $sth = $dbh->prepare("INSERT INTO fts_example(content) VALUES (?))");
  $sth->execute($_) foreach @docs_to_insert;
  
  my $results = $dbh->selectall_arrayref(<<"");
  SELECT docid, snippet(content) FROM fts_example WHERE content MATCH 'foo'
  

The key points in this example are :

=over

=item *

The syntax for creating FTS tables is 

  CREATE VIRTUAL TABLE <table_name> USING fts4(<columns>)

where C<< <columns> >> is a list of column names. Columns may be
typed, but the type information is ignored. If no columns
are specified, the default is a single column named C<content>.
In addition, FTS tables have an implicit column called C<docid>
(or also C<rowid>) for numbering the stored documents.

=item *

Statements for inserting, updating or deleting records 
use the same syntax as for regular SQLite tables.

=item *

Full-text searches are specified with the C<MATCH> operator, and an
operand which may be a single word, a word prefix ending with '*', a
list of words, a "phrase query" in double quotes, or a boolean combination
of the above.

=item *

The builtin function C<snippet(...)> builds a formatted excerpt of the
document text, where the words pertaining to the query are highlighted.

=back

There are many more details to building and searching
FTS tables, so we strongly invite you to read
the full documentation at L<http://www.sqlite.org/fts3.html>.

B<Incompatible change> : 
starting from version 1.31, C<DBD::SQLite> uses the new, recommended
"Enhanced Query Syntax" for binary set operators (AND, OR, NOT, possibly 
nested with parenthesis). Previous versions of C<DBD::SQLite> used the
"Standard Query Syntax" (see L<http://www.sqlite.org/fts3.html#section_3_2>).
Unfortunately this is a compilation switch, so it cannot be tuned
at runtime; however, since FTS3 was never advertised in versions prior
to 1.31, the change should be invisible to the vast majority of 
C<DBD::SQLite> users. If, however, there are any applications
that nevertheless were built using the "Standard Query" syntax,
they have to be migrated, because the precedence of the C<OR> operator
has changed. Conversion from old to new syntax can be 
automated through L<DBD::SQLite::FTS3Transitional>, published
in a separate distribution.

=head2 Tokenizers

The behaviour of full-text indexes strongly depends on how
documents are split into I<tokens>; therefore FTS table
declarations can explicitly specify how to perform
tokenization: 

  CREATE ... USING fts4(<columns>, tokenize=<tokenizer>)

where C<< <tokenizer> >> is a sequence of space-separated
words that triggers a specific tokenizer. Tokenizers can
be SQLite builtins, written in C code, or Perl tokenizers.
Both are as explained below.

=head3 SQLite builtin tokenizers

SQLite comes with three builtin tokenizers :

=over

=item simple

Under the I<simple> tokenizer, a term is a contiguous sequence of
eligible characters, where eligible characters are all alphanumeric
characters, the "_" character, and all characters with UTF codepoints
greater than or equal to 128. All other characters are discarded when
splitting a document into terms. They serve only to separate adjacent
terms.

All uppercase characters within the ASCII range (UTF codepoints less
than 128), are transformed to their lowercase equivalents as part of
the tokenization process. Thus, full-text queries are case-insensitive
when using the simple tokenizer.

=item porter

The I<porter> tokenizer uses the same rules to separate the input
document into terms, but as well as folding all terms to lower case it
uses the Porter Stemming algorithm to reduce related English language
words to a common root.

=item icu

If SQLite is compiled with the SQLITE_ENABLE_ICU
pre-processor symbol defined, then there exists a built-in tokenizer
named "icu" implemented using the ICU library, and taking an
ICU locale identifier as argument (such as "tr_TR" for
Turkish as used in Turkey, or "en_AU" for English as used in
Australia). For example:

  CREATE VIRTUAL TABLE thai_text USING fts4(text, tokenize=icu th_TH)

The ICU tokenizer implementation is very simple. It splits the input
text according to the ICU rules for finding word boundaries and
discards any tokens that consist entirely of white-space. This may be
suitable for some applications in some locales, but not all. If more
complex processing is required, for example to implement stemming or
discard punctuation, use the perl tokenizer as explained below.

=back

=head3 Perl tokenizers

In addition to the builtin SQLite tokenizers, C<DBD::SQLite>
implements a I<perl> tokenizer, that can hook to any tokenizing
algorithm written in Perl. This is specified as follows :

  CREATE ... USING fts4(<columns>, tokenize=perl '<perl_function>')

where C<< <perl_function> >> is a fully qualified Perl function name
(i.e. prefixed by the name of the package in which that function is
declared). So for example if the function is C<my_func> in the main 
program, write

  CREATE ... USING fts4(<columns>, tokenize=perl 'main::my_func')

That function should return a code reference that takes a string as
single argument, and returns an iterator (another function), which
returns a tuple C<< ($term, $len, $start, $end, $index) >> for each
term. Here is a simple example that tokenizes on words according to
the current perl locale

  sub locale_tokenizer {
    return sub {
      my $string = shift;

      use locale;
      my $regex      = qr/\w+/;
      my $term_index = 0;

      return sub { # closure
        $string =~ /$regex/g or return; # either match, or no more token
        my ($start, $end) = ($-[0], $+[0]);
        my $len           = $end-$start;
        my $term          = substr($string, $start, $len);
        return ($term, $len, $start, $end, $term_index++);
      }
    };
  }

There must be three levels of subs, in a kind of "Russian dolls" structure,
because :

=over

=item *

the external, named sub is called whenever accessing a FTS table
with that tokenizer

=item *

the inner, anonymous sub is called whenever a new string
needs to be tokenized (either for inserting new text into the table,
or for analyzing a query).

=item *

the innermost, anonymous sub is called repeatedly for retrieving
all terms within that string.

=back

Instead of writing tokenizers by hand, you can grab one of those
already implemented in the L<Search::Tokenizer> module. For example,
if you want ignore differences between accented characters, you can
write :

  use Search::Tokenizer;
  $dbh->do(<<"") or die DBI::errstr;
  CREATE ... USING fts4(<columns>, 
                        tokenize=perl 'Search::Tokenizer::unaccent')

Alternatively, you can use L<Search::Tokenizer/new> to build
your own tokenizer.


=head2 Incomplete handling of utf8 characters

The current FTS implementation in SQLite is far from complete with
respect to utf8 handling : in particular, variable-length characters
are not treated correctly by the builtin functions
C<offsets()> and C<snippet()>.

=head2 Database space for FTS

By default, FTS stores a complete copy of the indexed documents, together with
the fulltext index. On a large collection of documents, this can
consume quite a lot of disk space. However, FTS has some options
for compressing the documents, or even for not storing them at all
-- see L<http://www.sqlite.org/fts3.html#fts4_options>.

=head1 R* TREE SUPPORT

The RTREE extension module within SQLite adds support for creating
a R-Tree, a special index for range and multidimensional queries.  This
allows users to create tables that can be loaded with (as an example)
geospatial data such as latitude/longitude coordinates for buildings within
a city :

  CREATE VIRTUAL TABLE city_buildings USING rtree(
     id,               -- Integer primary key
     minLong, maxLong, -- Minimum and maximum longitude
     minLat, maxLat    -- Minimum and maximum latitude
  );

then query which buildings overlap or are contained within a specified region:

  # IDs that are contained within query coordinates
  my $contained_sql = <<"";
  SELECT id FROM try_rtree
     WHERE  minLong >= ? AND maxLong <= ?
     AND    minLat  >= ? AND maxLat  <= ?
  
  # ... and those that overlap query coordinates
  my $overlap_sql = <<"";
  SELECT id FROM try_rtree
     WHERE    maxLong >= ? AND minLong <= ?
     AND      maxLat  >= ? AND minLat  <= ?
  
  my $contained = $dbh->selectcol_arrayref($contained_sql,undef,
                        $minLong, $maxLong, $minLat, $maxLat);
  
  my $overlapping = $dbh->selectcol_arrayref($overlap_sql,undef,
                        $minLong, $maxLong, $minLat, $maxLat);  

For more detail, please see the SQLite R-Tree page
(L<http://www.sqlite.org/rtree.html>). Note that custom R-Tree
queries using callbacks, as mentioned in the prior link, have not been
implemented yet.

=head1 FOR DBD::SQLITE EXTENSION AUTHORS

Since 1.30_01, you can retrieve the bundled sqlite C source and/or
header like this:

  use File::ShareDir 'dist_dir';
  use File::Spec::Functions 'catfile';
  
  # the whole sqlite3.h header
  my $sqlite3_h = catfile(dist_dir('DBD-SQLite'), 'sqlite3.h');
  
  # or only a particular header, amalgamated in sqlite3.c
  my $what_i_want = 'parse.h';
  my $sqlite3_c = catfile(dist_dir('DBD-SQLite'), 'sqlite3.c');
  open my $fh, '<', $sqlite3_c or die $!;
  my $code = do { local $/; <$fh> };
  my ($parse_h) = $code =~ m{(
    /\*+[ ]Begin[ ]file[ ]$what_i_want[ ]\*+
    .+?
    /\*+[ ]End[ ]of[ ]$what_i_want[ ]\*+/
  )}sx;
  open my $out, '>', $what_i_want or die $!;
  print $out $parse_h;
  close $out;

You usually want to use this in your extension's C<Makefile.PL>,
and you may want to add DBD::SQLite to your extension's C<CONFIGURE_REQUIRES>
to ensure your extension users use the same C source/header they use
to build DBD::SQLite itself (instead of the ones installed in their
system).

=head1 TO DO

The following items remain to be done.

=head2 Leak Detection

Implement one or more leak detection tests that only run during
AUTOMATED_TESTING and RELEASE_TESTING and validate that none of the C
code we work with leaks.

=head2 Stream API for Blobs

Reading/writing into blobs using C<sqlite2_blob_open> / C<sqlite2_blob_close>.

=head2 Flags for sqlite3_open_v2

Support the full API of sqlite3_open_v2 (flags for opening the file).

=head2 Support for custom callbacks for R-Tree queries

Custom queries of a R-Tree index using a callback are possible with
the SQLite C API (L<http://www.sqlite.org/rtree.html>), so one could
potentially use a callback that narrowed the result set down based
on a specific need, such as querying for overlapping circles.

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=DBD-SQLite>

Note that bugs of bundled sqlite library (i.e. bugs in C<sqlite3.[ch]>)
should be reported to the sqlite developers at sqlite.org via their bug
tracker or via their mailing list.

=head1 AUTHORS

Matt Sergeant E<lt>matt@sergeant.orgE<gt>

Francis J. Lacoste E<lt>flacoste@logreport.orgE<gt>

Wolfgang Sourdeau E<lt>wolfgang@logreport.orgE<gt>

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

Max Maischein E<lt>corion@cpan.orgE<gt>

Laurent Dami E<lt>dami@cpan.orgE<gt>

Kenichi Ishigaki E<lt>ishigaki@cpan.orgE<gt>

=head1 COPYRIGHT

The bundled SQLite code in this distribution is Public Domain.

DBD::SQLite is copyright 2002 - 2007 Matt Sergeant.

Some parts copyright 2008 Francis J. Lacoste.

Some parts copyright 2008 Wolfgang Sourdeau.

Some parts copyright 2008 - 2013 Adam Kennedy.

Some parts copyright 2009 - 2013 Kenichi Ishigaki.

Some parts derived from L<DBD::SQLite::Amalgamation>
copyright 2008 Audrey Tang.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
