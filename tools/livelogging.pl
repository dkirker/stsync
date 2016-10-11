#!/usr/bin/perl

use strict;
use warnings;
use JSON;
use AnyEvent::WebSocket::Client;
use POSIX qw(strftime);
use Scalar::Util 'refaddr';

if ($#ARGV < 1) {
	die("Cannot be used stand-alone $#ARGV");
}

$| = 0;

my $logging = undef;
if ($#ARGV == 2) {
	open $logging, '>>', $ARGV[2] or die("Unable to open logfile for writing.");
	printf STDERR "Logging to \"%s\"\n", $ARGV[2];
}

printf STDERR "Connecting...";
STDERR->flush();

my $host = $ARGV[0];
my $client = AnyEvent::WebSocket::Client->new;
my $ws = $client->connect($host)->recv;
my $timestamp = 0;
my $lasttime = 0;
my $pending = 0;
my $progress = 0;
my $bar = "\\|/-";

$ws->on(each_message => sub {
	my $msg = pop->decoded_body;
	# Ignore register
	if (substr($msg, 0, 9) eq "register ") {
		printf STDERR "OK!\n";
		printf "Live Logging started @ %s\n", (strftime "%a %b %e, %H:%M:%S %Y", localtime);
		if (defined $logging) {
			printf $logging "Live Logging started @ %s\n", (strftime "%a %b %e, %H:%M:%S %Y", localtime);
			$logging->flush();
		}
		$lasttime = $timestamp = time();
	} elsif ($msg eq "echo") {
		#printf "----- | ALIVE | %-25.25s | ----- |\n", "KeepAlive < Pong";
		$pending = 0;
	} elsif (substr($msg, 0, 1) eq "{") {
		my $t = time();
		my $delta = $t - $lasttime;
		my $offset = $t - $timestamp;
		$lasttime = $t;

		my $data = decode_json($msg);
		my $targetlabel = "";
		if ($data->{'logs'}) {
			my $prefix = sprintf "%5d | ", $offset;
			if ($data->{'target'}) {
				if ($data->{'target'}->{'type'} eq 'InstalledSmartApp') {
					$prefix .= "  APP | ";
				} elsif ($data->{'target'}->{'type'} eq 'Device') {
					$prefix .= "  DEV | ";
				} else {
					$prefix .= $data->{'target'}->{'type'};
				}
				$targetlabel = $data->{'target'}->{'label'};
			} elsif ($data->{'targets'}) {
				my $targets = $data->{'targets'};
				foreach (@$targets) {
					if ($_->{'type'} eq 'InstalledSmartApp') {
						$prefix .= "APP";
					} elsif ($_->{'type'} eq 'Device') {
						$prefix .= "DEV";
					} else {
						$prefix .= $_->{'type'};
					}
					$targetlabel .= $_->{'label'};
					if (ref($_) and ref(@$targets[-1]) and refaddr($_) != refaddr(@$targets[-1])) {
						$targetlabel .= ", ";
						$prefix .= ", ";
					} else {
						$prefix .= " ";
					}
				}
				$prefix .= "| ";
			} else {
				$prefix .= "  XXX | ";
			}
			$prefix .= sprintf "%-75.75s", $targetlabel;
			printLogArray( $prefix, $data->{'logs'});
		} elsif ( $data->{'event'} ) {
			printf "%5d | EVENT | Source: %-17.17s | ----- | %s\n", $offset, $data->{'event'}->{"eventSource"}, $data->{'event'}->{"value"};
			if (defined $logging) {
				printf $logging "%5d | EVENT | Source: %-17.17s | ----- | %s\n", $offset, $data->{'event'}->{"eventSource"}, $data->{'event'}->{"value"};
				$logging->flush();
			}
		} else {
			print $msg . "\n";
			if (defined $logging) {
				print $logging $msg . "\n";
				$logging->flush();
			}
		}
		printProgress();
	}
});

my $timer = AnyEvent->timer(after => 3, interval => 3, cb => sub {
	#printf "----- | ALIVE | %-25.25s | ----- |\n", "KeepAlive Ping >";
#	if ($progress % 10 == 0) {
#		if ($pending) {
#			printf "----- | DEAD! | %-25.25s | ----- | Server has stopped responding to keep alive requests @ %s\n", "KeepAlive", (strftime "%a %b %e, %H:%M:%S %Y", localtime);
#			if (defined $logging) {
#				printf $logging "----- | DEAD! | %-25.25s | ----- | Server has stopped responding to keep alive requests @ %s\n", "KeepAlive", (strftime "%a %b %e, %H:%M:%S %Y", localtime);
#				$logging->flush();
#			}
#			exit 15;
#		}
#		$pending = 1;
#		$ws->send('ping');
#	}
	printProgress();
	$progress = $progress + 1;
});
AnyEvent->condvar->recv;

sub printProgress {
	printf STDERR "%s\r", substr($bar, $progress % 4, 1);
	STDERR->flush();
}

sub printLogArray {
	my ($prefix, $data) = @_;
	foreach ( @$data ) {
		my $line = $_;
		printf "%s | %-5.5s | %s\n", $prefix, $line->{'level'}, $line->{'msg'};
		if (defined $logging) {
			printf $logging "%s | %-5.5s | %s\n", $prefix, $line->{'level'}, $line->{'msg'};
			$logging->flush();
		}
	}
}
