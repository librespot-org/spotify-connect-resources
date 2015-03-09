use XML::Parser; 
use XML::SimpleObject;

my $XML = <<EOF;

  <files>
    <file type="symlink">
      <name>/etc/dosemu.conf</name>
      <dest>dosemu.conf-drdos703.eval</dest>
      <bytes>20</bytes>
    </file>
    <file>
      <name>/etc/passwd</name>
      <bytes>948</bytes>
    </file>
  </files>

EOF

my $xmlobj = new XML::SimpleObject(XML => $XML, ErrorContext => 2);

#my $parser = new XML::Parser (ErrorContext => 2, Style => "Tree");
#my $xmlobj = new XML::SimpleObject ($parser->parse($XML));

print "\n";

{
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
}

print "\n";

{
  my $filesobj = $xmlobj->child("files")->child("file");
  foreach my $child ($filesobj->children) {
    print "child: ", $child->name, ": ", $child->value, "\n";
  }
}

print "\n";

{
  my $filesobj = $xmlobj->child("files");
  foreach my $childname ($filesobj->children_names) {
      print "$childname has children: ";
      print join (", ", $filesobj->child($childname)->children_names), "\n"; 
  }
}

print "\n";

