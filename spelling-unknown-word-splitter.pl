#!/usr/bin/perl -wT -Ilib

use 5.022;
use feature 'unicode_strings';
use strict;
use warnings;
use Encode qw/decode_utf8 FB_DEFAULT/;
use CheckSpelling::UnknownWordSplitter;

binmode STDIN;
binmode STDOUT, ':utf8';

# skip files that don't exist (including dangling symlinks)
if (scalar @ARGV) {
  @ARGV = grep {! -l && -f && -r} @ARGV;
  unless (scalar @ARGV) {
    print STDERR "::warning ::Was not provided any regular readable files\n";
    exit 0;
  }
}

CheckSpelling::UnknownWordSplitter::main(@ARGV);
