#!/usr/bin/perl

use strict;
use warnings;
use JSON;

my $field = 'code';
my $data = '';
foreach my $line ( <STDIN> ) {
	$data .= $line;
}

if ($#ARGV == 0) {
	if ($ARGV[0] ne "") {
		$field = $ARGV[0];
	}
}

my $result;

$result = decode_json($data)->{ $field };

if (ref($result) eq "ARRAY") {
	printArray($result);
} else {
	print $result;
}

sub printArray {
	my ($data) = @_;
	foreach ( @$data ) {
		if (ref($_) eq 'ARRAY') {
			printArray($_);
		} else {
			print "$_";
		}
	}
}