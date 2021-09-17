#!/usr/bin/perl -wT -Ilib


# ~/bin/w
# Search for potentially misspelled words
# Output is:
# misspellled
# woord (WOORD, Woord, woord, woord's)

use 5.022;
use feature 'unicode_strings';
use strict;
use warnings;
use Encode qw/decode_utf8 FB_DEFAULT/;
binmode STDIN;
binmode STDOUT, ':utf8';

use File::Basename;
use Cwd 'abs_path';
use File::Temp qw/ tempfile tempdir /;

my $dirname = dirname(abs_path(__FILE__));

# skip files that don't exist (including dangling symlinks)
if (scalar @ARGV) {
  @ARGV = grep {! -l && -f && -r} @ARGV;
  unless (scalar @ARGV) {
    print STDERR "::warning ::Was not provided any regular readable files\n";
    exit 0;
  }
}

sub file_to_re {
  my ($re) = @_;
  return '$^' unless open(FILE, '<:utf8', "$dirname/$re");
  my @file;
  local $/=undef;
  my $file=<FILE>;
  close FILE;
  for (split /\R/, $file) {
    next if /^#/;
    chomp;
    next unless s/^(.+)/(?:$1)/;
    push @file, $_;
  }
  return join "|", @file if scalar @file;
}

my $patterns_re = file_to_re('patterns.txt');
my $forbidden_re = file_to_re('forbidden.txt');

my $longest_word = get_val_from_env('INPUT_LONGEST_WORD', '');
my $shortest_word = get_val_from_env('INPUT_SHORTEST_WORD', '');

my ($shortest, $longest) = (undef, undef);
sub valid_word {
  # shortest_word is an absolute
  our ($shortest, $longest, $word_match);
  $shortest = $shortest_word if $shortest_word;
  if ($longest_word) {
    # longest_word is an absolute
    $longest = $longest_word;
  } elsif (defined $longest) {
    # we allow for some sloppiness (a couple of stuck keys per word)
    # it's possible that this should scale with word length
    $longest = 0 unless $longest;
    $longest += 2;
  }
  return qr/\w{3}/ if (defined $shortest && defined $longest) && ($shortest > $longest);
  $shortest = 3 unless defined $shortest;
  $longest = '' unless defined $longest;
  $word_match = "\\w{$shortest,$longest}";
  return qr/\b$word_match\b/;
}

my $word_match = valid_word();
($shortest, $longest) = (255, 0);
# load dictionary
my $dict = "$dirname/words";
$dict = '/usr/share/dict/words' unless -e $dict;
open(DICT, '<:utf8', $dict);
my %dictionary=();
while (my $word = <DICT>) {
  chomp $word;
  next unless $word =~ $word_match;
  my $l = length $word;
  $longest = $l if $l > $longest;
  $shortest = $l if $l < $shortest;
  $dictionary{$word}=1;
}
close DICT;

sub get_val_from_env {
  my ($var, $fallback) = @_;
  return $fallback unless defined $ENV{$var};
  $ENV{$var} =~ /^(\d+)$/;
  return $1 || $fallback;
}

$word_match = valid_word();

# read all input
my ($last_file, $temp_dir, $words, $unrecognized) = ('', '', 0, 0);
my %unique;
my %unique_unrecognized;
my @reports;

sub report_stats() {
  if ($unrecognized) {
    open(STATS, '>:utf8', "$temp_dir/stats");
      print STATS "{words: $words, unrecognized: $unrecognized, unknown: ".(keys %unique_unrecognized).", unique: ".(keys %unique)."}";
    close STATS;
    open(UNKNOWN, '>:utf8', "$temp_dir/unknown");
      print UNKNOWN join "\n", sort keys %unique_unrecognized;
    close UNKNOWN;
    close WARNINGS;
  }
}

while (<<>>) {
  $_ = decode_utf8($_, FB_DEFAULT);
  if ($last_file ne $ARGV) {
    $. = 1;
    $last_file = $ARGV;
    report_stats();

    $temp_dir = tempdir();
    push @reports, "$temp_dir\n";
    open(NAME, '>:utf8', "$temp_dir/name");
      print NAME $last_file;
    close NAME;
    ($words, $unrecognized) = (0, 0);
    %unique = ();
    %unique_unrecognized = ();
    open(WARNINGS, '>:utf8', "$temp_dir/warnings");
  }
  next unless /./;
  my $raw_line = $_;
  # hook for custom line based text exclusions:
  s/($patterns_re)/" "x length($1)/ge;
  while (s/($forbidden_re)/ /g) {
    my ($begin, $end, $match) = ($-[0] + 1, $+[0], $1);
    print WARNINGS "line $., columns $begin-$end, Warning - `$match` matches a line_forbidden.patterns entry. (forbidden-pattern)\n";
  }
  # This is to make it easier to deal w/ rules:
  s/^/ /;
  while (s/([^\\])\\[rtn]/$1 /g) {}
  # https://www.fileformat.info/info/unicode/char/2019/
  my $rsqm = "\xE2\x80\x99";
  s/$rsqm|&apos;|&#39;/'/g;
  s/[^a-zA-Z']+/ /g;
  while (s/([A-Z]{2,})([A-Z][a-z]{2,})/ $1 $2 /g) {}
  while (s/([a-z']+)([A-Z])/$1 $2/g) {}
  my %unrecognized_line_items = ();
  for my $token (split /\s+/, $_) {
    $token =~ s/^(?:'|$rsqm)+//g;
    $token =~ s/(?:'|$rsqm)+s?$//g;
    my $raw_token = $token;
    $token =~ s/^[^Ii]?'+(.*)/$1/;
    $token =~ s/(.*?)'+$/$1/;
    next unless $token =~ $word_match;
    if (defined $dictionary{$token}) {
      ++$words;
      $unique{$token}=1;
      next;
    }
    my $key = lc $token;
    $key =~ s/''+/'/g;
    $key =~ s/'[sd]$//;
    if (defined $dictionary{$key}) {
      ++$words;
      $unique{$key}=1;
      next;
    }
    ++$unrecognized;
    $unique_unrecognized{$raw_token}=1;
    $unrecognized_line_items{$raw_token}=1;
  }
  for my $token (keys %unrecognized_line_items) {
    $token =~ s/'/(?:'|$rsqm)+/g;
    my $before;
    if ($token =~ /^[A-Z][a-z]/) {
      $before = '(?<=.)';
    } elsif ($token =~ /^[A-Z]/) {
      $before = '(?<=[^A-Z])';
    } else {
      $before = '(?<=[^a-z])';
    }
    my $after = ($token =~ /[A-Z]$/) ? '(?=[^A-Za-z])|(?=[A-Z][a-z])' : '(?=[^a-z])';
    while ($raw_line =~ /(?:\b|$before)($token)(?:\b|$after)/g) {
      my ($begin, $end, $match) = ($-[0] + 1, $+[0], $1);
      next unless $match =~ /./;
      print WARNINGS "line $. cols $begin-$end: '$match'\n";
    }
  }
}
report_stats();
print join '', @reports;
