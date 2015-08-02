#!/usr/bin/perl

use strict;
use warnings;

if ($#ARGV ne 0) {
	die "ERROR: Need base path for includes"
}

my $base = $ARGV[0];

sub processLine {
	our $line = shift;

	if ( $line =~ /^#include "([^"]+)"/ ) {
		loadFile($1);
	} else {
		print $line;
	}
}

sub loadFile {
	our $file = shift;
	open my $fh, "$base/$file" or die "ERROR: Couldn't open file include file \"$base/$file\"";
	while (<$fh>) {
		processLine($_);
	}
	close $fh;
}

while ( <STDIN> ) {
	processLine($_);
}
