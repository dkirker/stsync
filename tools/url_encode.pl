#!/usr/bin/perl

use strict;
use warnings;
use URI::Escape;

my $data = '';
foreach my $line ( <STDIN> ) {
	$data .= $line;
}

print uri_escape( $data );
