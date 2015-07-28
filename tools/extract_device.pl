#!/usr/bin/perl

use strict;
use warnings;

my $data = '';
foreach my $line ( <STDIN> ) {
	$data .= $line;
}

my ( $result ) = ( $data =~ /<textarea id="code" name="code">(.*?)<\/textarea>.*/s );

print $result;

