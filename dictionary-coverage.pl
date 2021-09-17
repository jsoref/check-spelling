#!/usr/bin/perl -wT -Ilib

use CheckSpelling::DictionaryCoverage;

CheckSpelling::DictionaryCoverage::main(shift, glob("*"));
