package DateTime::Format::Natural::Test;

use strict;
use warnings;
use base qw(Exporter);
use boolean qw(true);

use File::Find;
use File::Spec::Functions qw(abs2rel);
use List::MoreUtils qw(any);
use Module::Util qw(fs_path_to_module);
use Test::More;

our ($VERSION, @EXPORT_OK, %EXPORT_TAGS, %time, $case_strings, $time_entries);
my @set;

$VERSION = '0.10';

@set         =  qw(%time $case_strings $time_entries _run_tests _result_string _message);
@EXPORT_OK   = (qw(_find_modules _find_files), @set);
%EXPORT_TAGS = ('set' => [ @set ]);

%time = map { split /:/ }
        split /\n/,
        do { local $/ = '__END__';
             local $_ = <DATA>;
             chomp;
             $_ };

$case_strings = sub { ($_[0], lc $_[0], uc $_[0]) };
$time_entries = sub
{
    my ($string, $result) = @_;

    my $subst = sub
    {
        my ($str, $res, $entries) = @_;

        if ($str =~ /\{(?: |at)\}/) {
            my @strings;
            if ($str =~ /\{ \}/) {
                foreach my $space ('', ' ') {
                    (my $str_new = $str) =~ s/\{ \}/$space/;
                    push @strings, $str_new;
                }
            }
            if ($str =~ /\{at\}/) {
                @strings = ($str) unless @strings;
                my @strings_new;
                foreach my $string (@strings) {
                    foreach my $at ('', ' at') {
                        (my $str_new = $string) =~ s/ \{at\}/$at/;
                        push @strings_new, $str_new;
                    }
                }
                @strings = @strings_new;
            }
            push @$entries, [ $_, $res ] foreach @strings;
        }
        else {
            push @$entries, [ $str, $res ];
        }
    };

    my @entries;
    if ($string =~ /\{(?:min_)?sec\}/) {
        my ($desc, @values);
        my $sec = sprintf '%02d', int rand(60);
        local $1;
        if ($string =~ /\{(min_sec)\}/) {
            @values = (
                [ '',         '00:00'   ], # hour
                [ ':00',      '00:00'   ], # minute
                [ ":00:$sec", "00:$sec" ], # second
            );
            $desc = $1;
        }
        elsif ($string =~ /\{(sec)\}/) {
            @values = (
                [ '',      '00' ], # minute
                [ ":$sec", $sec ], # second
            );
            $desc = $1;
        }
        foreach my $value (@values) {
            (my $str = $string) =~ s/\{$desc\}/$value->[0]/;
            (my $res = $result) =~ s/\{$desc\}/$value->[1]/;
            $subst->($str, $res, \@entries);
        }
    }
    else {
        $subst->($string, $result, \@entries);
    }

    return @entries;
};

sub _run_tests
{
    my ($tests, $sets, $check) = @_;

    $tests *= 3; # case tests

    local $@;

    if (eval "require Date::Calc") {
        plan tests => $tests * 2;
        foreach my $set (@$sets) {
            $check->(@$set);
        }
    }
    else {
        plan tests => $tests;
    }

    $DateTime::Format::Natural::Compat::Pure = true;

    foreach my $set (@$sets) {
        $check->(@$set);
    }
}

sub _result_string
{
    my ($dt) = @_;

    my $string = sprintf(
        '%02d.%02d.%4d %02d:%02d:%02d',
        map $dt->$_, qw(day month year hour min sec)
    );

    return $string;
}

sub _message
{
    my ($msg) = @_;

    my $how = $DateTime::Format::Natural::Compat::Pure
      ? '(using DateTime)'
      : '(using Date::Calc)';

    return "$msg $how";
}

sub _find_modules
{
    my ($lib, $modules, $exclude) = @_;
    _gather_data($lib, undef, $modules, $exclude);
}

sub _find_files
{
    my ($lib, $files, $exclude) = @_;
    _gather_data($lib, $files, undef, $exclude);
}

sub _gather_data
{
    my ($lib, $files, $modules, $exclude) = @_;

    my ($save_files, $save_modules) = map defined, ($files, $modules);
    my $ext = qr/\.pm$/;

    find(sub {
        return unless $_ =~ $ext;
        my $rel_path = abs2rel($File::Find::name, $lib);
        my $module = fs_path_to_module($rel_path) or return;
        return if any { $module =~ /${_}$/ } @$exclude;
        if ($save_files) {
            push @$files, $File::Find::name;
        }
        elsif ($save_modules) {
            push @$modules, $module;
        }
    }, $lib);
}

1;
__DATA__
year:2006
month:11
day:24
hour:1
minute:13
second:8

__END__

=head1 NAME

DateTime::Format::Natural::Test - Common test routines/data

=head1 SYNOPSIS

 Please see the DateTime::Format::Natural documentation.

=head1 DESCRIPTION

The C<DateTime::Format::Natural::Test> class exports common test routines.

=head1 SEE ALSO

L<DateTime::Format::Natural>

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/>

=cut
