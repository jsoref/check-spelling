#!/bin/sh
# apt-get install -y tre-agrep
# inputs:
#  $unrecognized (file with list of unrecognized words)
#  $recognized (file with list of recognized words)
# intermediate
#  $scratch
# output:
#  stderr:
#   `skipped ...` (debugging)
#  stdout:
#   unrecognized --> confident-replacement
#   unrecognized .> multiple replacements

scratch=$(mktemp)
for a in $(
  cat $unrecognized |\
    grep '.....' |\
    tr "'" '_'|\
    xargs -n 10 echo |\
    tr ' ' '|'
  ); do
  tre-agrep -i -1 -e '^('$a')$' $recognized > $scratch;
  if [ ! -s $scratch ]; then
    echo "skipped $a" >&2
  else
    for b in $(echo $a | tr '|' ' '|tr '_' "'"); do
      maybe=$(tre-agrep -i -2 -e '"^'$(echo $b | tr A-Z a-z)'$' $scratch)
      if [ -n "$maybe" ]; then
        count=$(echo "$maybe"|wc -l);
        if [ $count -eq 1 ]; then
          echo "$b --> $maybe"
        else
          echo "$b .> $(echo $maybe)"
        fi
      fi
    done
  fi
done
rm $scratch
