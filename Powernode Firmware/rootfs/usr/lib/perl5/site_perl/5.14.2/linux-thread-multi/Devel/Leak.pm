package Devel::Leak;
use 5.005;
use vars qw($VERSION);
require DynaLoader;
use base qw(DynaLoader);
$VERSION = '0.03';

bootstrap Devel::Leak;

1;
__END__

=head1 NAME

Devel::Leak - Utility for looking for perl objects that are not reclaimed.

=head1 SYNOPSIS

  use Devel::Leak;
  ... setup code

  my $count = Devel::Leak::NoteSV($handle);

  ... code that may leak

  Devel::Leak::CheckSV($handle);

=head1 DESCRIPTION

Devel::Leak has two functions C<NoteSV> and C<CheckSV>.

C<NoteSV> walks the perl internal table of allocated SVs (scalar values) - (which
actually  contains arrays and hashes too), and records their addresses in a
table. It returns a count of these "things", and stores a pointer to the
table (which is obtained from the heap using malloc()) in its argument.

C<CheckSV> is passed argument which holds a pointer to a table created by
C<NoteSV>. It re-walks the perl-internals and calls sv_dump() for any "things"
which did not exist when C<NoteSV> was called. It returns a count of the number
of "things" now allocated.

=head1 CAVEATS

Note that you need a perl built with -DDEBUGGING for
sv_dump() to print anything, but counts are valid in any perl.

If new "things" I<have> been created, C<CheckSV> may (also) report additional
"things" which are allocated by the sv_dump() code.

=head1 HISTORY

This little utility module was part of Tk until the variable renaming
in perl5.005 made it clear that Tk had no business knowing this much
about the perl internals.

=head1 AUTHOR

Nick Ing-Simmons <nick@ni-s.u-net.com>

=cut

