#!/usr/bin/perl
#
# Decodes the JSON which explains the layout of a smartapp
#

use strict;
use warnings;
use JSON;
use Data::Dumper;

my $input = '';
foreach my $line ( <STDIN> ) {
    $input .= $line;
}

my $json;

my %layout = ();

$json = decode_json($input);

# Iterate the initial array
foreach (@$json) {
    %layout = (%layout, getFileAndId("", $_));
}

while ( my ($k, $v) = each %layout ) {
    print "$k \"$v\"\n"
}

sub getFileAndId {
    my $path = shift;
    my $data = shift;
    my %result = ();

    if ($data->{"children"} and @{$data->{"children"}}) {
        foreach ( @{$data->{"children"}} ) {
            %result = (%result, getFileAndId($path . "/" . $data->{"text"}, $_));
        }
    } elsif ($data->{"type"} and $data->{"type"} eq "file") {
        $result{$data->{"id"}} = $path . "/" . $data->{"text"};
        $result{$data->{"id"}} = substr $result{$data->{"id"}}, 1;
    }
    return %result;
}

sub printHash {
    my $data = shift;
    while ( my ($k, $v) = each %$data ) {
        print "$k : ";
        printItem($v);
    }
}

sub printArray {
    my $data = shift;
    foreach ( @$data ) {
        printItem($_);
    }
}

sub printItem {
    my $v = shift;

    if (ref($v) eq 'ARRAY') {
        print "[\n";
        printArray($v);
        print "]\n";
    } elsif (ref($v) eq "HASH") {
        print "{\n";
        printHash($v);
        print "}\n";
    } else {
        print "$v\n";
    }

}