package DateTime::Format::Natural::Lang::Base;

use strict;
use warnings;

our ($VERSION, $AUTOLOAD);

$VERSION = '1.08';

sub __new
{
    my $class = shift;

    no strict 'refs';

    my $obj = {};
    $obj->{weekdays}        = \%{"${class}::data_weekdays"};
    $obj->{weekdays_abbrev} = \%{"${class}::data_weekdays_abbrev"};
    $obj->{weekdays_all}    = \@{"${class}::data_weekdays_all"};
    $obj->{months}          = \%{"${class}::data_months"};
    $obj->{months_abbrev}   = \%{"${class}::data_months_abbrev"};
    $obj->{months_all}      = \@{"${class}::data_months_all"};
    $obj->{conversion}      = \%{"${class}::data_conversion"};
    $obj->{helpers}         = \%{"${class}::data_helpers"};
    $obj->{duration}        = \%{"${class}::data_duration"};
    $obj->{aliases}         = \%{"${class}::data_aliases"};
    $obj->{rewrite}         = \%{"${class}::data_rewrite"};

    return bless $obj, $class;
}

AUTOLOAD
{
    my ($self, $exp) = @_;

    my ($caller, $sub) = $AUTOLOAD =~ /^(.+)::(.+)$/;

    if (substr($sub, 0, 2) eq '__') {
        $sub =~ s/^__//;
        no strict 'refs';
        if (defined $exp && length $exp) {
            return ${$caller.'::'.$sub}{$exp};
        }
        else {
            return \%{$caller.'::'.$sub};
        }
    }
}

1;
__END__

=head1 NAME

DateTime::Format::Natural::Lang::Base - Base class for DateTime::Format::Natural::Lang::

=head1 SYNOPSIS

 Please see the DateTime::Format::Natural::Lang:: documentation.

=head1 DESCRIPTION

The C<DateTime::Format::Natural::Lang::Base> class defines the core functionality for
C<DateTime::Format::Natural::Lang::> grammar classes.

=head1 SEE ALSO

L<DateTime::Format::Natural>

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/>

=cut
