#!/usr/bin/perl -wT -Ilib

use strict;

use File::Temp qw/ tempfile tempdir /;
use Test::More;

plan tests => 3;
use_ok('CheckSpelling::Exclude');

my ($fh, $filename) = tempfile();
binmode( $fh, ":utf8" );
print $fh "# ignore
line
";
close $fh;
is(CheckSpelling::Exclude::file_to_re($filename, "fallback"), "(?:line)");
is(CheckSpelling::Exclude::file_to_re("nonexistent", "fallback"), "fallback");
