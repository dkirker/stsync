#!/usr/bin/perl

use strict;
use warnings;
use JSON;

my $data;
$data = <>;
print decode_json($data)->{'code'};

