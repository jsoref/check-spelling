#!/usr/bin/perl -wT

use CheckSpelling::DictionaryCoverage;

CheckSpelling::DictionaryCoverage::main(shift, glob("*"));
