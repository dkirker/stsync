#!/usr/bin/perl

use strict;
use warnings;
use File::Path;
use File::Basename;

if ($#ARGV lt 0) {
	die "ERROR: Need base path for includes"
}

my $base = $ARGV[0];
my $overwrite = 0;

if ($#ARGV eq 1) {
	$overwrite = $ARGV[1];
}

sub processLine {
	my $line = shift;

	if ( $line =~ /^#include "([^"]+)"/ ) {
		my $module = $1;
		print "/****[ include-start: $module ]****/\n";
		loadFile($module);
		print "/****[ include-end: $module ]****/\n";
	} elsif ( $line =~ /^\/\*\*\*\*\[ include-start: ([^ ]+) \]\*\*\*\*\// ) {
		print "#include \"$1\"\n";
		saveFile($1);
	} else {
		print $line;
	}
}

sub saveFile {
	my $name = shift;
	my $fh;

	mkpath($base . dirname($name));
	if ( ! -e "$base/$name" or $overwrite > 0) {
		open($fh, ">", "$base/$name") or die "ERROR: Couldn't open file \"$base/$name\" for saving";
	} else {
		$fh = 0;
	}
	while (<STDIN>) {
		our $line = $_;
		if ( $line =~ /^\/\*\*\*\*\[ include-start: ([^ ]+) \]\*\*\*\*\// ) {
			if ($fh) {
				print $fh "#include \"$1\"\n";
			}
			saveFile($1);
		} elsif ( $line =~ /^\/\*\*\*\*\[ include-end: ([^ ]+) \]\*\*\*\*\// ) {
			last;
		} else {
			if ($fh) {
				print $fh $line;
			}
		}
	}
	if ($fh) {
		close $fh;
	}
}

sub loadFile {
	my $file = shift;
	open my $fh, "$base/$file" or die "ERROR: Couldn't open include file \"$base/$file\"";
	while (<$fh>) {
		processLine($_);
	}
	close $fh;
}

while ( <STDIN> ) {
	processLine($_);
}
