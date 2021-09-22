#! -*-perl-*-

# ~/bin/w
# Search for potentially misspelled words
# Output is:
# misspellled
# woord (WOORD, Woord, woord, woord's)
package CheckSpelling::UnknownWordSplitter;

use 5.022;
use feature 'unicode_strings';
use strict;
use warnings;
use Encode qw/decode_utf8 FB_DEFAULT/;
use File::Basename;
use Cwd 'abs_path';
use File::Temp qw/ tempfile tempdir /;

my ($longest_word, $shortest_word, $word_match, $forbidden_re, $patterns_re);
my ($shortest, $longest) = (255, 0);
my %dictionary = ();
my %unique;
my %unique_unrecognized;
my ($last_file, $temp_dir, $words, $unrecognized) = ('', '', 0, 0);

sub file_to_re {
  my ($re) = @_;
  return '$^' unless open(FILE, '<:utf8', $re);
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

sub valid_word {
  # shortest_word is an absolute
  our ($shortest, $longest, $shortest_word, $longest_word);
  $shortest = $shortest_word if $shortest_word;
  if ($longest_word) {
    # longest_word is an absolute
    $longest = $longest_word;
  } elsif (defined $longest && $longest ne '') {
    # we allow for some sloppiness (a couple of stuck keys per word)
    # it's possible that this should scale with word length
    $longest += 2;
  }
  return qr/\w{3}/ if (defined $shortest && defined $longest && $longest ne '') && ($shortest > $longest);
  $shortest = 3 unless defined $shortest;
  $longest = '' unless defined $longest;
  $word_match = "\\w{$shortest,$longest}";
  return qr/\b$word_match\b/;
}

sub load_dictionary {
  my ($dict) = @_;
  our ($word_match, $longest, $shortest, $longest_word, $shortest_word, %dictionary);
  $longest_word = get_val_from_env('INPUT_LONGEST_WORD', undef);
  $shortest_word = get_val_from_env('INPUT_SHORTEST_WORD', undef);
  %dictionary = ();

  open(DICT, '<:utf8', $dict);
  while (!eof(DICT)) {
    my $word = <DICT>;
    chomp $word;
    next unless $word =~ $word_match;
    my $l = length $word;
    $longest = -1 unless defined $longest and $longest ne '';
    $longest = $l if $l > $longest;
    $shortest = $l if $l < $shortest;
    $dictionary{$word}=1;
  }
  close DICT;

  $word_match = valid_word();
}

sub get_val_from_env {
  my ($var, $fallback) = @_;
  return $fallback unless defined $ENV{$var};
  $ENV{$var} =~ /^(\d+)$/;
  return $1 || $fallback;
}

sub init {
  my ($dirname) = @_;
  our ($word_match, %unique);
  our $patterns_re = file_to_re "$dirname/patterns.txt";
  our $forbidden_re = file_to_re "$dirname/forbidden.txt";

  $word_match = valid_word();

  my $dict = "$dirname/words";
  $dict = '/usr/share/dict/words' unless -e $dict;
  load_dictionary($dict);
}

sub split_file {
  my ($file) = @_;
  our ($unrecognized, $temp_dir, $longest_word, $shortest_word, $words, $word_match, %unique, %unique_unrecognized, $forbidden_re, $patterns_re, %dictionary);
  open FILE, '<', $file;
  binmode FILE;
  $temp_dir = tempdir();
  ($words, $unrecognized) = (0, 0);
  %unique = ();
  %unique_unrecognized = ();
  open(WARNINGS, '>:utf8', "$temp_dir/warnings");
  while (<FILE>) {
    $_ = decode_utf8($_, FB_DEFAULT);
    next unless /./;
    my $raw_line = $_;
    while (s/($forbidden_re)/ /g) {
      my ($begin, $end, $match) = ($-[0] + 1, $+[0], $1);
      print WARNINGS "line $., columns $begin-$end, Warning - `$match` matches a line_forbidden.patterns entry. (forbidden-pattern)\n";
    }
    # hook for custom line based text exclusions:
    s/$patterns_re/ /g;
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
  close FILE;

  if ($unrecognized) {
    open(STATS, '>:utf8', "$temp_dir/stats");
      print STATS "{words: $words, unrecognized: $unrecognized, unknown: ".(keys %unique_unrecognized).", unique: ".(keys %unique)."}";
    close STATS;
    open(UNKNOWN, '>:utf8', "$temp_dir/unknown");
      print UNKNOWN join "\n", sort keys %unique_unrecognized;
    close UNKNOWN;
    close WARNINGS;
  }

  open(NAME, '>:utf8', "$temp_dir/name");
    print NAME $file;
  close NAME;
  return $temp_dir;
}

sub main {
  my @ARGV = @_;
  our %dictionary;
  unless (%dictionary) {
    my $dirname = dirname(abs_path(__FILE__)).'/../..';
    init($dirname);
  }

  # read all input
  my @reports;

  for my $file (@ARGV) {
    my $temp_dir = split_file($file);
    push @reports, "$temp_dir\n";
  }
  print join '', @reports;
}

1;
