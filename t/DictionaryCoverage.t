#!/usr/bin/perl -wT -Ilib

use strict;

use File::Temp qw/ tempfile tempdir /;
use Test::More;
plan tests => 6;
use_ok('CheckSpelling::DictionaryCoverage');

my $name = '/dev/null';
my $object = CheckSpelling::DictionaryCoverage::entry($name);
isa_ok($object->{'handle'}, 'GLOB');
is($object->{'name'}, $name);
is($object->{'word'}, 0);
is($object->{'covered'}, 0);

my ($fh, $filename, $dict);
($fh, $dict) = tempfile();
print $fh 'does
this
what
';
close $fh;
my $output;
open(my $outputFH, '>', \$output) or die; # This shouldn't fail
my $oldFH = select $outputFH;
($fh, $filename) = tempfile();
print $fh 'this
what
';
close $fh;
$ENV{'aliases'}="s{$dict}{test:case}";
$ENV{'extra_dictionaries'} = $dict;
my @files = grep{/.*/} glob($dict);
CheckSpelling::DictionaryCoverage::main($filename, @files);
select $oldFH;
is($output, "2 [$dict](test:case) (3) covers 2 of them
");
