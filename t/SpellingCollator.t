#!/usr/bin/perl -wT -Ilib

use strict;

use File::Temp qw/ tempfile tempdir /;

use Test::More;
plan tests => 8;

use_ok('CheckSpelling::SpellingCollator');

my ($fd, $expect) = tempfile;
$ENV{'expect'} = $expect;
print $fd "foo\n";
close $fd;
CheckSpelling::SpellingCollator::load_expect($expect);
is(CheckSpelling::SpellingCollator::expect_item('bar', 1), 0);
is(CheckSpelling::SpellingCollator::expect_item('foo', 1), 1);
is(CheckSpelling::SpellingCollator::expect_item('foo', 2), 2);
is($CheckSpelling::SpellingCollator::counters{'hi'}, undef);
CheckSpelling::SpellingCollator::count_warning('(hi)');
is($CheckSpelling::SpellingCollator::counters{'hi'}, 1);
CheckSpelling::SpellingCollator::count_warning('hi');
is($CheckSpelling::SpellingCollator::counters{'hi'}, 1);
CheckSpelling::SpellingCollator::count_warning('hello (hi)');
is($CheckSpelling::SpellingCollator::counters{'hi'}, 2);
