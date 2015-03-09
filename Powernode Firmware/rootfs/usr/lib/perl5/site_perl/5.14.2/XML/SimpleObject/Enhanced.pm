package XML::SimpleObject::Enhanced;

use strict;
use warnings;
our $VERSION = '0.53';

use XML::SimpleObject 0.53;
our @ISA = qw(XML::SimpleObject);

my $shiftwidth = 2;

sub _space($)
{
    my $offset = shift || 0;
    return " " x ($offset * $shiftwidth);
}

sub output($;$);

sub output($;$)
{
    my $self = shift;
    my $indent = shift || 0;
    my %attribs = $self->attributes;
    my $xml = _space($indent) . "<" . $self->name;
    $xml .= " $_=\"" . $attribs{$_} . '"' foreach (keys %attribs);
    my @data = split /\n/, $self->value;
    my ($nl, $in, $in1);
    if (@data > 1)
    {
	$nl = "\n";
	$in = _space($indent);
	$in1 = _space($indent + 1);
    }
    else {
	$nl = $in = $in1 = '';
    }
    $xml .= ">$nl";
    $xml .= $in1 . "$_$nl" foreach (grep s/^\s*(\S.*?)\s*/$1/, @data);
    $xml .= output($_, $indent + 1) foreach $self->children;
    $xml .=  $in . "</" . $self->name. ">\n";
    return $xml;
}

sub append
{
    my $self = shift;
    while (my $new = shift)
    {
	my @array = ($new);
	$self->{$new->{_NAME}} = \@array;
    }
}

1;
