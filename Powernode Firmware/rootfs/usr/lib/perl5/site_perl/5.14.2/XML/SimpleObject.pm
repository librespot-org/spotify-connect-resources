package XML::SimpleObject;

use strict;
use XML::Parser;

our $VERSION = '0.53';

sub attributes {
    my $self = shift;
    my $name = shift;
    if ($self->{_ATTRS}) {
        return (%{$self->{_ATTRS}});
    }
}

sub attribute {
    my $self = shift;
    my $name = shift;
    if ($self->{_ATTRS}) {
        return ${$self->{_ATTRS}}{$name};
    }
}

sub value {
    $_[0]->{_VALUE};
}

sub name {
    $_[0]->{_NAME};
}

sub child {
    my $self = shift;
    my $tag  = shift;
    if (ref($self->{$tag}) eq "ARRAY")
    {
        if (wantarray)
        {
            return (@{$self->{$tag}});
        }
        else
        {
            return (${$self->{$tag}}[0]);
        }
    }
    return;
}

sub children_names {
    my $self = shift;
    my @elements;
    foreach my $key (keys %{$self})
    {
        if (ref($self->{$key}) eq "ARRAY")
        {
            push @elements, $key;
        }
    }
    return (@elements);
}

sub children {
    my $self = shift;
    my $tag  = shift;
    if ($tag) {
        if (ref($self->{$tag}) eq "ARRAY")
        {
            return (@{$self->{$tag}});
        }
    }
    else
    {
        my @children;
        foreach my $key (keys %{$self})
        {
            if (ref($self->{$key}) eq "ARRAY")
            {
                push @children, @{$self->{$key}};
            }
        }
        return @children;
    }
}

sub convert {
    my $self = shift;
    my $array = shift;
    unless (ref($array) eq "ARRAY") { die "not an array: $array\n" }

    # first element will always be a hashref
    if (ref $array->[0] eq "HASH") { $self->{_ATTRS} = shift @$array; }

    while (defined (my $tag = shift @$array)) {
        my $content = shift @$array;
        if ($tag eq "0") {
            $self->{_VALUE} .= $content;
        } elsif (ref $content eq "ARRAY") {
          my $class = ref $self;
          push @{$self->{$tag}}, new $class ($content, $tag);
        }
    }
}

sub new {
    my $class = shift;
    if (ref $_[0] eq "ARRAY") {
        my $table = shift;
        my $name  = shift;
        my $self = {};
        bless ($self,$class);
        $self->{_NAME} = $name;
        $self->convert($table);
        return $self;
    } else {
        my %args = @_;
        my $parser = new XML::Parser (ErrorContext => $args{ErrorContext},
                                      Style        => 'Tree');
        my $table = $parser->parse($args{XML});
        my $self = {};
        bless ($self,$class);
        $self->{_NAME} = "";
        $self->convert($table);
        return $self;
    }
}


1;
__END__

=head1 NAME

XML::SimpleObject - Perl extension allowing a simple object representation of a parsed XML::Parser tree.

=head1 SYNOPSIS

  use XML::SimpleObject;

  # Construct with the key/value pairs as argument; this will create its 
  # own XML::Parser object.
  my $xmlobj = new XML::SimpleObject(XML => $XML, ErrorContext => 2);

  # ... or construct with the parsed tree as the only argument, having to 
  # create the XML::Parser object separately.
  my $parser = new XML::Parser (ErrorContext => 2, Style => "Tree");
  my $xmlobj = new XML::SimpleObject ($parser->parse($XML));

  my $filesobj = $xmlobj->child("files")->child("file");

  $filesobj->name;
  $filesobj->value;
  $filesobj->attribute("type");
  
  %attributes    = $filesobj->attributes;
  @children      = $filesobj->children;
  @some_children = $filesobj->children("some");
  @chilren_names = $filesobj->children_names;

=head1 DESCRIPTION

This is a short and simple class allowing simple object access to a parsed XML::Parser tree, with methods for fetching children and attributes in as clean a manner as possible. My apologies for further polluting the XML:: space; this is a small and quick module, with easy and compact usage. See XML::SimpleObject::LibXML for the same interface for XML::LibXML.

=head1 USAGE

=item $xmlobj = new XML::SimpleObject($parser->parse($XML))


$parser is an XML::Parser object created with Style "Tree":

    my $parser = new XML::Parser (ErrorContext => 2, Style => "Tree");

After creating $xmlobj, this object can now be used to browse the XML tree with the following methods.

=item $xmlobj->child('NAME')


This will return a new XML::SimpleObject object using the child element NAME.


=item $xmlobj->children('NAME')


Called with an argument NAME, children() will return an array of XML::SimpleObject objects of element NAME. Thus, if $xmlobj represents the top-level XML element, 'children' will return an array of all elements directly below the top-level that have the element name NAME.


=item $xmlobj->children

Called without arguments, 'children()' will return an array of XML::SimpleObject
s for all children elements of $xmlobj. These are not in the order they occur in
 the XML document.


=item $xmlobj->children_names


This will return an array of all the names of child elements for $xmlobj. You can use this to step through all the children of a given element (see EXAMPLES). Each name will occur only once, even if multiple children exist with that name. 


=item $xmlobj->value


If the element represented by $xmlobj contains any PCDATA, this method will return that text data.

=item $xmlobj->attribute('NAME')


This returns the text for an attribute NAME of the XML element represented by $xmlobj.

=item $xmlobj->attributes


This returns a hash of key/value pairs for all elements in element $xmlobj.

=head1 EXAMPLES

Given this XML document:

  <files>
    <file type="symlink">
      <name>/etc/dosemu.conf</name>
      <dest>dosemu.conf-drdos703.eval</dest>
    </file>
    <file>
      <name>/etc/passwd</name>
      <bytes>948</bytes>
    </file>
  </files>

You can then interpret the tree as follows:

  my $parser = new XML::Parser (ErrorContext => 2, Style => "Tree");
  my $xmlobj = new XML::SimpleObject ($parser->parse($XML));

  print "Files: \n";
  foreach my $element ($xmlobj->child("files")->children("file"))
  {
    print "  filename: " . $element->child("name")->value . "\n";
    if ($element->attribute("type"))
    {
      print "    type: " . $element->attribute("type") . "\n";
    }
    print "    bytes: " . $element->child("bytes")->value . "\n";
  }  

This will output:

  Files:
    filename: /etc/dosemu.conf
      type: symlink
      bytes: 20
    filename: /etc/passwd
      bytes: 948

You can use 'children()' without arguments to step through all children of a given element:

  my $filesobj = $xmlobj->child("files")->child("file");
  foreach my $child ($filesobj->children) {
    print "child: ", $child->name, ": ", $child->value, "\n";
  }

For the tree above, this will output:

  child: bytes: 20
  child: dest: dosemu.conf-drdos703.eval
  child: name: /etc/dosemu.conf

Using 'children_names()', you can step through all children for a given element:

  my $filesobj = $xmlobj->child("files");
  foreach my $childname ($filesobj->children_names) {
      print "$childname has children: ";
      print join (", ", $filesobj->child($childname)->children_names), "\n";
  }

This will print:

    file has children: bytes, dest, name

By always using 'children()', you can step through each child object, retrieving them with 'child()'.

=head1 AUTHOR

Dan Brian <dbrian@brians.org>

=head1 SEE ALSO

perl(1), XML::Parser.

=cut

