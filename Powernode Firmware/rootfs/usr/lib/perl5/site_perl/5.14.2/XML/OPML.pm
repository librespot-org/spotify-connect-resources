# $Id: OPML.pm,v 0.26 2004/03/06 09:19:00 szul Exp $
package XML::OPML;

use strict;
use Carp;
use XML::Parser;
use XML::SimpleObject;
use Fcntl qw(:DEFAULT :flock);
use vars qw($VERSION $AUTOLOAD @ISA $modules $AUTO_ADD);

$VERSION = '0.26';

$AUTO_ADD = 0;

my %opml_fields = (
    head => {
		title		=> '',
		dateCreated	=> '',
		dateModified	=> '',
		ownerName	=> '',
		ownerEmail	=> '',
		expansionState	=> '',
		vertScrollState	=> '',
		windowTop	=> '',
		windowLeft	=> '',
		windowBottom	=> '',
		windowRight	=> ''
	},
    body  => {
		outline => [],
	},
);

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->_initialize(@_);
    return $self;
}

sub _initialize {
    my $self = shift;
    my %hash = @_;

    # internal hash
    $self->{_internal} = {};

    # initialize number of outlines to 0
    $self->{num_items} = 0;

    # initialize outlines
    $self->{outline} = [];

    # encode output from as_string?
    (exists($hash{encode_output}))
    ? ($self->{encode_output} = $hash{encode_output})
    : ($self->{encode_output} = 1);

    # get version information
    (exists($hash{version}))
    ? ($self->{version} = $hash{version})
    : ($self->{version} = '1.0');

    # set default output
    (exists($hash{output}))
    ? ($self->{output} = $hash{output})
    : ($self->{output} = "");

    # encoding
    (exists($hash{encoding}))
    ? ($self->{encoding} = $hash{encoding})
    : ($self->{encoding} = 'UTF-8');

    # opml version 1.1 -- version 1.0 not supported
    if ($self->{version} eq '1.1') {
	foreach my $i (qw(head body)) {
	    my %template = %{$opml_fields{$i}};
	    $self->{$i} = \%template;
        }
    }
}

sub add_outline {
    my $self = shift;
    my $hash = {@_};
    push (@{$self->{outline}}, $hash);
    return $self->{outline};
}

sub insert_outline {
  my $self = shift;
  my $hash = {@_};
  $self->{group} = $hash->{group};
  delete($hash->{group});
  $self->{add_on} = $hash;
}

sub as_opml_1_1 {
    my $self = shift;
    my $output;

    # XML declaration
    $output .= '<?xml version="1.0" encoding="'.$self->{encoding}.'"?>'."\n";

    # DOCTYPE: No official DocType for version 1.1

    # OPML root element
    $output .= '<opml version="1.1">'."\n";

    ################
    # Head Element #
    ################
    $output .= '<head>'."\n";
    $output .= '<title>'. $self->encode($self->{head}->{title}) .'</title>'."\n";
    $output .= '<dateCreated>'. $self->encode($self->{head}->{dateCreated}) .'</dateCreated>'."\n";
    $output .= '<dateModified>'. $self->encode($self->{head}->{dateModified}) .'</dateModified>'."\n";
    $output .= '<ownerName>'. $self->encode($self->{head}->{ownerName}) .'</ownerName>'."\n";
    $output .= '<ownerEmail>'. $self->encode($self->{head}->{ownerEmail}) .'</ownerEmail>'."\n";
    $output .= '<expansionState>'. $self->encode($self->{head}->{expansionState}) .'</expansionState>'."\n";
    $output .= '<vertScrollState>'. $self->encode($self->{head}->{vertScrollState}) .'</vertScrollState>'."\n";
    $output .= '<windowTop>'. $self->encode($self->{head}->{windowTop}) .'</windowTop>'."\n";
    $output .= '<windowLeft>'. $self->encode($self->{head}->{windowLeft}) .'</windowLeft>'."\n";
    $output .= '<windowBottom>'. $self->encode($self->{head}->{windowBottom}) .'</windowBottom>'."\n";
    $output .= '<windowRight>'. $self->encode($self->{head}->{windowRight}) .'</windowRight>'."\n";
    $output .= '</head>' . "\n";
    $output .= '<body>' . "\n";

    ###################
    # outline element #
    ###################

    foreach my $outline (@{$self->{outline}}) {
            if(($outline->{opmlvalue}) && ($outline->{opmlvalue} eq "embed")) {
              my $embed_text = "";
              $embed_text .= "dateAdded=\"$outline->{dateAdded}\" " if($outline->{dateAdded});
              $embed_text .= "date_added=\"$outline->{date_added}\" " if($outline->{date_added});
              $embed_text .= "dateDownloaded=\"$outline->{dateDownloaded}\" " if($outline->{dateDownloaded});
              $embed_text .= "date_downloaded=\"$outline->{date_downloaded}\" " if($outline->{date_downloaded});
              $embed_text .= "description=\"$outline->{description}\" " if($outline->{description});
              $embed_text .= "email=\"$outline->{email}\" " if($outline->{email});
              $embed_text .= "filename=\"$outline->{filename}\" " if($outline->{filename});
              $embed_text .= "htmlUrl=\"$outline->{htmlUrl}\" " if($outline->{htmlUrl});
              $embed_text .= "htmlurl=\"$outline->{htmlurl}\" " if($outline->{htmlurl});
              $embed_text .= "keywords=\"$outline->{keywords}\" " if($outline->{keywords});
              $embed_text .= "text=\"$outline->{text}\" " if($outline->{text});
              $embed_text .= "title=\"$outline->{title}\" " if($outline->{title});
              $embed_text .= "type=\"$outline->{type}\" " if($outline->{type});
              $embed_text .= "version=\"$outline->{version}\" " if($outline->{version});
              $embed_text .= "xmlUrl=\"$outline->{xmlUrl}\" " if($outline->{xmlUrl});
              $embed_text .= "xmlurl=\"$outline->{xmlurl}\" " if($outline->{xmlurl});
              if($embed_text eq "") {
                $output .= "<outline>\n";
              }
              else {
                $output .= "<outline $embed_text>\n";
                if(($self->{group}) && ($outline->{text} eq "$self->{group}")) {
                  $outline->{time()} = $self->{add_on};
                }
              }
              $output .= return_embedded($self, $outline);
              $output .= "</outline>\n";
              next;
            }
	    $output .= "<outline ";
          foreach my $atts (sort {$a cmp $b} keys %{$outline}) {
            $output .= "$atts=\"" . $self->encode($outline->{$atts}) . "\" ";
          }
          $output .= " />";
          $output .= "\n";
    }
    $output .= '</body>' . "\n";
    $output .= '</opml>' . "\n";

    return $output;
}

# Global array for capturing embedded outlines
my @return_values = ();

# Recurse down the outline elements to build proper tree structure
sub return_embedded {
  my ($self, $outline) = @_;
  foreach my $inner_out (keys %{$outline}) {
    next if($inner_out eq "opmlvalue");
    next if($inner_out eq "dateAdded");
    next if($inner_out eq "date_added");
    next if($inner_out eq "dateDownloaded");
    next if($inner_out eq "date_downloaded");
    next if($inner_out eq "description");
    next if($inner_out eq "email");
    next if($inner_out eq "filename");
    next if($inner_out eq "htmlUrl");
    next if($inner_out eq "htmlurl");
    next if($inner_out eq "keywords");
    next if($inner_out eq "text");
    next if($inner_out eq "title");
    next if($inner_out eq "type");
    next if($inner_out eq "version");
    next if($inner_out eq "xmlUrl");
    next if($inner_out eq "xmlurl");
    if(($outline->{$inner_out}->{'opmlvalue'}) && ($outline->{$inner_out}->{'opmlvalue'} eq "embed")) {
      my @elems = keys(%{$outline->{$inner_out}});
      my $pop_num = scalar(@elems);
      foreach my $elems (@elems) {
        $pop_num-- if(($elems eq "opmlvalue") || ($elems eq "dateAdded") || ($elems eq "date_added") || ($elems eq "dateDownloaded") || ($elems eq "date_downloaded") || ($elems eq "description") || ($elems eq "email") || ($elems eq "filename") || ($elems eq "htmlUrl") || ($elems eq "htmlurl") || ($elems eq "keywords") || ($elems eq "text") || ($elems eq "title") || ($elems eq "type") || ($elems eq "version") || ($elems eq "xmlUrl") || ($elems eq "xmlurl"));
      }
      $pop_num = 1 if($pop_num == 0);
      my $return_output = "";
      my $embed_text = "";
      $embed_text .= "dateAdded=\"$outline->{$inner_out}->{dateAdded}\" " if($outline->{$inner_out}->{dateAdded});
      $embed_text .= "date_added=\"$outline->{$inner_out}->{date_added}\" " if($outline->{$inner_out}->{date_added});
      $embed_text .= "dateDownloaded=\"$outline->{$inner_out}->{dateDownloaded}\" " if($outline->{$inner_out}->{dateDownloaded});
      $embed_text .= "date_downloaded=\"$outline->{$inner_out}->{date_downloaded}\" " if($outline->{$inner_out}->{date_downloaded});
      $embed_text .= "description=\"$outline->{$inner_out}->{description}\" " if($outline->{$inner_out}->{description});
      $embed_text .= "email=\"$outline->{$inner_out}->{email}\" " if($outline->{$inner_out}->{email});
      $embed_text .= "filename=\"$outline->{$inner_out}->{filename}\" " if($outline->{$inner_out}->{filename});
      $embed_text .= "htmlUrl=\"$outline->{$inner_out}->{htmlUrl}\" " if($outline->{$inner_out}->{hmtlUrl});
      $embed_text .= "htmlurl=\"$outline->{$inner_out}->{htmlurl}\" " if($outline->{$inner_out}->{htmlurl});
      $embed_text .= "keywords=\"$outline->{$inner_out}->{keywords}\" " if($outline->{$inner_out}->{keywords});
      $embed_text .= "text=\"$outline->{$inner_out}->{text}\" " if($outline->{$inner_out}->{text});
      $embed_text .= "title=\"$outline->{$inner_out}->{title}\" " if($outline->{$inner_out}->{title});
      $embed_text .= "type=\"$outline->{$inner_out}->{type}\" " if($outline->{$inner_out}->{type});
      $embed_text .= "version=\"$outline->{$inner_out}->{version}\" " if($outline->{$inner_out}->{version});
      $embed_text .= "xmlUrl=\"$outline->{$inner_out}->{xmlUrl}\" " if($outline->{$inner_out}->{xmlUrl});
      $embed_text .= "xmlurl=\"$outline->{$inner_out}->{xmlurl}\" " if($outline->{$inner_out}->{xmlurl});
      if($embed_text eq "") {
        $return_output .= "<outline>\n";
      }
      else {
        $return_output .= "<outline $embed_text>\n";
        if(($self->{group}) && ($outline->{$inner_out}->{text} eq "$self->{group}")) {
          $outline->{$inner_out}->{time()} = $self->{add_on};
        }
      }
      return_embedded($self, $outline->{$inner_out});
      while($pop_num > 0) {
      	$return_output .= pop(@return_values);
        $pop_num--;
      }
      $return_output .= "</outline>\n";
      push(@return_values, $return_output);
      next;
    }
    else {
      my $return_output = "";
      $return_output .= "<outline ";
      foreach my $atts (sort {$a cmp $b} keys %{$outline->{$inner_out}}) {
        $return_output .= "$atts=\"" . $self->encode($outline->{$inner_out}->{$atts}) . "\" ";
      }
      $return_output .= " />\n";
      push(@return_values, $return_output);
    }
  }
  my $return_value = join('', @return_values);
  return $return_value;
}

sub as_string {
    my $self = shift;
    my $version = ($self->{output} =~ /\d/) ? $self->{output} : $self->{version};
    my $output;
    $output = &as_opml_1_1($self);
    return $output;
}

sub save {
    my ($self,$file) = @_;
    open(OUT,">$file") || croak "Cannot open file $file for write: $!";
    flock(OUT, LOCK_EX);
    print OUT $self->as_string();
    flock(OUT, LOCK_UN);
    close OUT;
}

# Parser the OPML with XML::Parser and XML::SimpleObject to add additional outlines.

sub parse {
  my $self = shift;
  my $content = shift;
  $self->_initialize((%$self));
  @return_values = ();
  my $xmlobj;
  my $bool;
  eval {
    $bool = "true" if(-e $content);
  };
  if($bool) {
    my $parser = XML::Parser->new(ErrorContext => 2, Style => "Tree");
    $xmlobj = XML::SimpleObject->new($parser->parsefile($content));
   }
   else {
    my $parser = XML::Parser->new(ErrorContext => 2, Style => "Tree");
    $xmlobj = XML::SimpleObject->new($parser->parse($content));
  }
  my $head = $xmlobj->child('opml')->child('head');
  my @head_children = $head->children();
  my $head_hash = {};
  foreach my $head_child (@head_children) {
    my $elem_value = $head_child->value() || "";
    $head_hash->{$head_child->name()} = $elem_value;
  }
  my $body = $xmlobj->child('opml')->child('body');
  my @outlines = $body->children('outline');
  my $outline_list = [];
  foreach my $outlines (@outlines) {
    my $outline_holder = {};
    my %atts = $outlines->attributes();
    foreach my $atts (keys(%atts)) {
      $outline_holder->{$atts} = $outlines->attribute($atts);
    }
    unless($outlines->children()) {
      push(@{$outline_list}, $outline_holder);
    }
    else {
      my $new_hash = return_outlines($outline_holder, $outlines);
      push(@{$outline_list}, $new_hash);
    } 
  }
  $self->{head} = $head_hash;
  $self->{outline} = $outline_list;
}

sub return_outlines {
  my($outline_holder, $outlines) = @_;
  $outline_holder->{'opmlvalue'} = 'embed';
  my @outlines = $outlines->children('outline');
  my $out_count = 0;
  foreach my $outs (@outlines) {
    $out_count++;
    my $new_outline_holder = {};
    my %atts = $outs->attributes();
    foreach my $atts (keys(%atts)) {
      $new_outline_holder->{$atts} = $outs->attribute($atts);
    }
    my $var_name = time() . $out_count;
    unless($outs->children()) {
      $outline_holder->{$var_name} = $new_outline_holder;
    }
    else {
      my $new_hash = return_outlines($new_outline_holder, $outs);
      $outline_holder->{$var_name} = $new_hash;
    }
  }
  return $outline_holder;
}

sub strict {
    my ($self,$value) = @_;
    $self->{'strict'} = $value;
}

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self) || croak "$self is not an object\n";
    my $name = $AUTOLOAD;
    $name =~ s/.*://;
    return if $name eq 'DESTROY';

    croak "Unregistered entity: Can't access $name field in object of class $type"
		unless (exists $self->{$name});

    # return reference to OPML structure
    if (@_ == 1) {
	return $self->{$name}->{$_[0]} if defined $self->{$name}->{$_[0]};

    # we're going to set values here
    } elsif (@_ > 1) {
	my %hash = @_;
    	# return value
      foreach my $key (keys(%hash)) {
        $self->{$name}->{$key} = $hash{$key};
      }
	return $self->{$name};

    # otherwise, just return a reference to the whole thing
    } else {
	return $self->{$name};
    }
    return 0;
}

# Entities for encoding
my %entity = (
	      nbsp   => "&#160;",
	      iexcl  => "&#161;",
	      cent   => "&#162;",
	      pound  => "&#163;",
	      curren => "&#164;",
	      yen    => "&#165;",
	      brvbar => "&#166;",
	      sect   => "&#167;",
	      uml    => "&#168;",
	      copy   => "&#169;",
	      ordf   => "&#170;",
	      laquo  => "&#171;",
	      not    => "&#172;",
	      shy    => "&#173;",
	      reg    => "&#174;",
	      macr   => "&#175;",
	      deg    => "&#176;",
	      plusmn => "&#177;",
	      sup2   => "&#178;",
	      sup3   => "&#179;",
	      acute  => "&#180;",
	      micro  => "&#181;",
	      para   => "&#182;",
	      middot => "&#183;",
	      cedil  => "&#184;",
	      sup1   => "&#185;",
	      ordm   => "&#186;",
	      raquo  => "&#187;",
	      frac14 => "&#188;",
	      frac12 => "&#189;",
	      frac34 => "&#190;",
	      iquest => "&#191;",
	      Agrave => "&#192;",
	      Aacute => "&#193;",
	      Acirc  => "&#194;",
	      Atilde => "&#195;",
	      Auml   => "&#196;",
	      Aring  => "&#197;",
	      AElig  => "&#198;",
	      Ccedil => "&#199;",
	      Egrave => "&#200;",
	      Eacute => "&#201;",
	      Ecirc  => "&#202;",
	      Euml   => "&#203;",
	      Igrave => "&#204;",
	      Iacute => "&#205;",
	      Icirc  => "&#206;",
	      Iuml   => "&#207;",
	      ETH    => "&#208;",
	      Ntilde => "&#209;",
	      Ograve => "&#210;",
	      Oacute => "&#211;",
	      Ocirc  => "&#212;",
	      Otilde => "&#213;",
	      Ouml   => "&#214;",
	      times  => "&#215;",
	      Oslash => "&#216;",
	      Ugrave => "&#217;",
	      Uacute => "&#218;",
	      Ucirc  => "&#219;",
	      Uuml   => "&#220;",
	      Yacute => "&#221;",
	      THORN  => "&#222;",
	      szlig  => "&#223;",
	      agrave => "&#224;",
	      aacute => "&#225;",
	      acirc  => "&#226;",
	      atilde => "&#227;",
	      auml   => "&#228;",
	      aring  => "&#229;",
	      aelig  => "&#230;",
	      ccedil => "&#231;",
	      egrave => "&#232;",
	      eacute => "&#233;",
	      ecirc  => "&#234;",
	      euml   => "&#235;",
	      igrave => "&#236;",
	      iacute => "&#237;",
	      icirc  => "&#238;",
	      iuml   => "&#239;",
	      eth    => "&#240;",
	      ntilde => "&#241;",
	      ograve => "&#242;",
	      oacute => "&#243;",
	      ocirc  => "&#244;",
	      otilde => "&#245;",
	      ouml   => "&#246;",
	      divide => "&#247;",
	      oslash => "&#248;",
	      ugrave => "&#249;",
	      uacute => "&#250;",
	      ucirc  => "&#251;",
	      uuml   => "&#252;",
	      yacute => "&#253;",
	      thorn  => "&#254;",
	      yuml   => "&#255;",
	      );

my $entities = join('|', keys %entity);

sub encode {
	my ($self, $text) = @_;
	return $text unless $self->{'encode_output'};
	my $encoded_text = '';
	while ( $text =~ s/(.*?)(\<\!\[CDATA\[.*?\]\]\>)//s ) {
		$encoded_text .= encode_text($1) . $2;
	}
	$encoded_text .= encode_text($text);
	return $encoded_text;
}

sub encode_text {
    my $text = shift;
    $text =~ s/&(?!(#[0-9]+|#x[0-9a-fA-F]+|\w+);)/&amp;/g;
    $text =~ s/&($entities);/$entity{$1}/g;
    $text =~ s/</&lt;/g;
    return $text;
}
1;
__END__

=head1 NAME

XML::OPML - creates and updates OPML (Outline Processor Markup Language) files

=head1 SYNOPSIS

# Create an OPML file

 use XML::OPML;

 my $opml = new XML::OPML(version => "1.1");

 $opml->head(
             title => 'mySubscription',
             dateCreated => 'Mon, 16 Feb 2004 11:35:00 GMT',
             dateModified => 'Sat, 05 Mar 2004 09:02:00 GMT',
             ownerName => 'michael szul',
             ownerEmail => 'opml-dev@blogenstein.com',
             expansionState => '',
             vertScrollState => '',
             windowTop => '',
             windowLeft => '',
             windowBottom => '',
             windowRight => '',
           );

 $opml->add_outline(
                 text => 'Warren Ellis Speaks Clever',
                 description => 'Warren Ellis\' Personal Weblog',
                 title => 'Warren Ellis Speaks Clever',
                 type => 'rss',
                 version => 'RSS',
                 htmlUrl => 'http://www.diepunyhumans.com ',
                 xmlUrl => 'http://www.diepunyhumans.com/index.rdf ',
               );

 $opml->add_outline(
                 text => 'raelity bytes',
                 descriptions => 'The raelity bytes weblog.',
                 title => 'raelity bytes',
                 type => 'rss',
                 version => 'RSS',
                 htmlUrl => 'http://www.raelity.org ',
                 xmlUrl => 'http://www.raelity.org/index.rss10 ',
               );

# Create embedded outlines

 $opml->add_outline(
                     opmlvalue => 'embed',
                     outline_one => {
                                      text => 'The first embedded outline',
                                      description => 'The description for the first embedded outline',
                                    },
                     outline_two => {
                                      text => 'The second embedded outline',
                                      description => 'The description for the second embedded outline',
                                    },
                     outline_three => {
                                        opmlvalue => 'embed',
                                        em_outline_one => {
                                                            text => 'I'm too lazy to come up with real examples',
                                                          },
                                        em_outline_two => {
                                                            text => 'so you get generic text',
                                                          },
                                      },
                   );

# Create an embedded outline with attributes in the encasing <outline> tag

 $opml->add_outline(
                     opmlvalue => 'embed',
                     description => 'now we can have attributes in this tag',
                     title => 'attributes',
                     outline_with_atts => {
                                            text => 'Eat Your Wheaties',
                                            description => 'Cereal is the breakfast of champion programmers',
                                          },
                   );

# Save it as a string.

 $opml->as_string();

# Save it to a file.

 $opml->save('mySubscriptions.opml');

# Update your OPML file.

 use XML::OPML;

 my $opml = new XML::OPML;

# Parse the file.

 $opml->parse('mySubscriptions.opml');

# Or optionally from a variable.

 my $content = $opml->as_string();
 $opml->parse($content);

# Update it appending to the end of the outline

 $opml->add_outline(
                    text => 'Neil Gaiman\'s Journal',
                    description =>'Neil Gaiman\'s Journal',
                    title => 'Neil Gaiman\'s Journal',
                    type => 'rss',
                    version => 'RSS',
                    htmlUrl => 'http://www.neilgaiman.com/journal/journal.asp ',
                    xmlUrl => 'http://www.neilgaiman.com/journal/blogger_rss.xml ',
                  );

# Update it inserting the outline into a specific group (note the group parameter)

 $opml->insert_outline(
                       group => 'occult',
                       text => 'madghoul.com',
                       description => 'the dark night of the soul',
                       title => 'madghoul.com',
                       type => 'rss',
                       version => 'RSS',
                       htmlUrl => 'http://www.madghoul.com ',
                       xmlUrl => 'http://www.madghoul.com/cgi-bin/fearsome/fallout/index.rss10 ',
                      );

=head1 DESCRIPTION

This experimental module is designed to allow for easy creation and manipulation of OPML files. OPML files are most commonly used for the sharing of blogrolls or subscriptions - an outlined list of what other blogs an Internet blogger reads. RSS Feed Readers such as AmphetaDesk ( http://www.disobey.com/amphetadesk ) use *.opml files to store your subscription information for easy access.

This is purely experimental at this point and has a few limitations. This module may now support attributes in the <outline> element of an embedded hierarchy, but these are limited to the following attributes: date_added, date_downloaded, description, email, filename, htmlurl, keywords, text, title, type, version, and xmlurl. Additionally, the following alternate spellings are also supported: dateAdded, dateDownloaded, htmlUrl, and xmlUrl.

Rather than reinvent the wheel, this module was modified from the XML::RSS module, so functionality works in a similar way.

=head1 METHODS

=over 4

=item new XML::OPML(version => '1.1')

This is the constructor. It returns a reference to an XML::OPML object. This will always be version 1.1 for now, so don't worry about it.

=item head(title => '$title', dateCreated => '$cdate', dateModified => '$mdate',ownerName => '$name', ownerEmail => '$email', expansionState => '$es', vertScrollState => '$vs', windowTop => '$wt', windowLeft => '$wl', windowBottom => '$wb',windowRight => '$wr',)

This method will create all the OPML tags for the <head> subset. For more information on these tags, please see the OPML documentation at http://www.opml.org .

=item add_outline(opmlvalue => '$value', %attributes)

This method adds the <outline> elements to the OPML document(see the example above). There are no statement requirements for the attributes in this tag. The ones shown in the example are the ones most commonly used by RSS Feed Readers, blogrolls, and subscriptions. The opmlvalue element is optional. Only use this with the value 'embed' if you wish to embed another outline within the current outline. You can now use attributes in <outline> tags that are used for embedded outlines, however, you cannot use any attribute you want. The embedded <outline> tag only supports the following: date_added, date_downloaded, description, email, filename, htmlurl, keywords, text, title, type, version, and xmlurl, as well as the alternate spellings: dateAdded, dateDownloaded, htmlUrl, and xmlUrl.

=item insert_outline(group => '$group', %attributes)

This method works in the same exact manner as add_outline() except that this will insert the outline element into the specified group. The $group variable must be the text presented in the "text" attribute of the outline that you wish to insert this one into. For example, if you have an outline element with the text attribute of "occult" that contains four outline subelements of occult web sites, your group parameter would be "occult."

=item as_string()

Returns a string containing the OPML document.

=item save($file)

Saves the OPML document to $file

=item parse($content)

Uses XML::Parser and XML::SimpleObject to parse the value of the string or file that is passed to it. This method prepares your OPML file for a possible update. Embedded outlines are supported.

=back

=head1 SOURCE AVAILABILITY

Source code is available at the development site at http://opml.blogenstein.com . Any contributions or improvements are greatly appreciated. You may also want to visit http://www.madghoul.com to see a whole lot of perl coding at work.

=head1 AUTHOR

 michael szul <opml-dev@blogenstein.com>

=head1 COPYRIGHT

copyright (c) 2004 michael szul <opml-dev@blogenstein.com>

XML::OPML is free software. It may be redistributed and/or modified under the same terms as Perl.

=head1 CREDITS

 michael szul <opml-dev@blogenstein.com>
 matt cashner <sungo@eekeek.org>
 ricardo signes <rjbs@cpan.org>
 gergely nagy <algernon@bonehunter.rulez.org>

=head1 SEE ALSO

perl(1), XML::Parser(3), XML::SimpleObject(3), XML::RSS(3).

=cut

