#!/usr/bin/perl

use strict;
use warnings;
use JSON;

my $data;
$data = <>;
my %pre = ('code' => $data);
print encode_json( \%pre );

