#!/usr/bin/env perl

# Copyright (c) 2025, Mirko Ludeke <m.ludeke@heinlein-support.de>
# Copyright (c) 2026, Carsten Rosenberg <c.rosenberg@heinlein-support.de>
# Copyright (c) 2023, Andreas Boesen <boesen@belwue.de>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;
use IO::Socket::IP;
use IO::Select;
use Data::Dumper;
use POSIX qw(setlocale strftime :sys_wait_h);
use Time::HiRes qw(gettimeofday tv_interval);
use Razor2::Client::Agent;

sub generate_request_id
{
    return sprintf("%08x", int(rand(0xFFFFFFFF)));
}

# set to 1 to enable debug logging
my $debug       = defined($ENV{'RAZORFY_DEBUG'}) ? $ENV{'RAZORFY_DEBUG'} : 0;

# max number of worker processes
my $maxworkers  = defined($ENV{'RAZORFY_MAXTHREADS'}) ? $ENV{'RAZORFY_MAXTHREADS'} : 200;

# bind razorfy by default to v4only localhost address
# use :: for all (dual stack), 0.0.0.0 for all (v4only), ::1 for localhost (v6only), 127.0.0.1 for localhost (v4only)
my $bindaddress = defined($ENV{'RAZORFY_BINDADDRESS'}) ? $ENV{'RAZORFY_BINDADDRESS'} : '127.0.0.1';

# tcp port to use
my $bindport    = defined($ENV{'RAZORFY_BINDPORT'}) ? $ENV{'RAZORFY_BINDPORT'} : '11342';

# razor home directory (default: ~/.razorfy)
my $razorhome   = defined($ENV{'RAZORFY_RAZORHOME'}) ? $ENV{'RAZORFY_RAZORHOME'} : "$ENV{'HOME'}/.razorfy";

# stats interval in seconds (default: 900 = 15 min)
my $stats_interval = defined($ENV{'RAZORFY_STATS_INTERVAL'}) ? $ENV{'RAZORFY_STATS_INTERVAL'} : 900;

# stats counters (parent process only)
my $stats_ham    = 0;
my $stats_spam   = 0;
my $stats_error  = 0;
my $stats_total_time = 0;
my $stats_min_time   = 0;
my $stats_max_time   = 0;


sub record_stats
{
    my ($result, $elapsed) = @_;

    if    ($result eq 'spam')  { $stats_spam++; }
    elsif ($result eq 'ham')   { $stats_ham++; }
    else                       { $stats_error++; }

    $stats_total_time += $elapsed;
    my $total = $stats_ham + $stats_spam + $stats_error;
    if ($total == 1 || $elapsed < $stats_min_time) { $stats_min_time = $elapsed; }
    if ($elapsed > $stats_max_time) { $stats_max_time = $elapsed; }
}

sub maybe_print_stats
{
    my ($last_stats_time) = @_;
    my $now = time();
    return $last_stats_time if ($now - $last_stats_time) < $stats_interval;

    my $ham = $stats_ham;   $stats_ham = 0;
    my $spam = $stats_spam;  $stats_spam = 0;
    my $error = $stats_error; $stats_error = 0;
    my $total_time = $stats_total_time; $stats_total_time = 0;
    my $min_time = $stats_min_time;     $stats_min_time = 0;
    my $max_time = $stats_max_time;     $stats_max_time = 0;

    my $total = $ham + $spam + $error;
    my $avg_time = $total > 0 ? $total_time / $total : 0;

    ErrorLog(sprintf(
        "STATS period=%ds total=%d ham=%d spam=%d error=%d avg=%.3fs min=%.3fs max=%.3fs",
        $stats_interval, $total, $ham, $spam, $error, $avg_time, $min_time, $max_time
    ));

    return $now;
}

sub create_agent
{
    my $agent = new Razor2::Client::Agent('razor-check') or die "Failed to create Razor2 agent";
    my %read_opts;
    $read_opts{'home'} = $razorhome if defined $razorhome;
    $agent->read_options(%read_opts) or die $agent->errstr ."\n";
    $agent->do_conf()      or die $agent->errstr ."\n";
    return $agent;
}

# Validate that agent creation works at startup
create_agent();

my %logret = ( 0 => 'spam', 1 => 'ham', 2 => 'error' );

sub Main
{
    # flush after every write
    $| = 1;

    # Create pipe for stats communication from children to parent
    pipe(my $stats_reader, my $stats_writer) or die "pipe: $!";
    $stats_writer->autoflush(1);

    my ( $socket, $client_socket );

    # Bind to listening address and port
    $socket = new IO::Socket::IP (
        LocalHost => $bindaddress,
        LocalPort => $bindport,
        Proto     => 'tcp',
        Listen    => 10,
        ReuseAddr => 1
    ) or die "Could not open socket: ".$!."\n";

    ErrorLog( "RAZORFY started, PID: $$ Waiting for client connections..." );
    ErrorLog( "  bind_address: $bindaddress" );
    ErrorLog( "  bind_port:    $bindport" );
    ErrorLog( "  max_workers:  $maxworkers" );
    ErrorLog( "  razorhome:    $razorhome" );
    ErrorLog( "  debug:        $debug" );
    ErrorLog( "  stats_interval: ${stats_interval}s" );

    my $last_stats_time = time();
    my $last_worker_warn_time = 0;
    my %children;
    my $stats_buf = '';

    my $sel = IO::Select->new($socket, $stats_reader);

    # start infinity loop
    while(1)
    {
        # Reap finished children
        while ((my $pid = waitpid(-1, WNOHANG)) > 0)
        {
            delete $children{$pid};
        }

        my $child_count = scalar keys %children;

        # Warn when more than 90% of max workers are active (at most once per minute)
        if ($child_count >= int($maxworkers * 0.9) && (time() - $last_worker_warn_time) >= 60)
        {
            ErrorLog(sprintf("WARNING: worker usage high: %d/%d active workers (%.0f%%)",
                $child_count, $maxworkers, ($child_count / $maxworkers) * 100));
            $last_worker_warn_time = time();
        }

        my @ready = $sel->can_read(1);

        for my $fh (@ready)
        {
            if ($fh == $stats_reader)
            {
                # Read stats data from children
                my $data;
                my $bytes = sysread($stats_reader, $data, 4096);
                if (defined $bytes && $bytes > 0)
                {
                    $stats_buf .= $data;
                    while ($stats_buf =~ s/^([^\n]*?)\n//)
                    {
                        my $line = $1;
                        my ($result, $elapsed) = split(' ', $line);
                        record_stats($result, $elapsed) if defined $result && defined $elapsed;
                    }
                }
            }
            elsif ($fh == $socket)
            {
                $client_socket = $socket->accept();
                next unless $client_socket;

                $child_count = scalar keys %children;
                if ($child_count >= $maxworkers)
                {
                    ErrorLog("WARNING: max workers reached ($maxworkers), rejecting connection");
                    $client_socket->close();
                    next;
                }

                my $pid = fork();
                if (!defined $pid)
                {
                    ErrorLog("fork failed: $!");
                    $client_socket->close();
                    next;
                }

                if ($pid == 0)
                {
                    # Child process
                    close $stats_reader;
                    $socket->close();
                    clientHandler($client_socket, $stats_writer);
                    exit(0);
                }
                else
                {
                    # Parent process
                    $client_socket->close();
                    $children{$pid} = 1;
                    ErrorLog("active workers: " . scalar(keys %children)) if $debug;
                }
            }
        }

        $last_stats_time = maybe_print_stats($last_stats_time);
    }
    $socket->close();
    return 1;
}

sub clientHandler
{
    my ($client_socket, $stats_writer) = @_;
    my $t0 = [gettimeofday];

    my $req_id = generate_request_id();

    # Create hash for user connection/session information and set initial connection information.
    my %user = ();
    $user{peer_address} = $client_socket->peerhost();
    $user{peer_port}    = $client_socket->peerport();

    ErrorLog( $req_id, "accepted connection from ".$user{peer_address}.":".$user{peer_port}, $t0 ) if $debug;

    my $agent = create_agent();
    ErrorLog( $req_id, "agent created", $t0 ) if $debug;

    # Read email data from socket first to isolate read time from check time
    my $mail_data = '';
    {
        local $/;
        $mail_data = <$client_socket>;
    }
    ErrorLog( $req_id, sprintf("mail data read, %d bytes", length($mail_data)), $t0 ) if $debug;

    # Pass data as in-memory filehandle since checkit() requires 'fh'
    open(my $mem_fh, '<', \$mail_data) or die "Failed to open in-memory filehandle: $!";
    my %hashr;
    $hashr{'fh'} = $mem_fh;

    my $ret;
    my $string;

    # Wrap checkit in eval to catch exceptions (e.g. connection refused to Razor servers)
    eval {
        $ret = $agent->checkit(\%hashr);
    };
    ErrorLog( $req_id, "checkit done", $t0 ) if $debug;

    if ( $@ )
    {
        $string = 'ham'; # always ham when razor fails to prevent a lot of false positives.
        ErrorLog($req_id, "Razor2::Client::Agent threw an exception: $@. The E-Mail has been classified as ham to prevent false positives.", $t0);
        $ret = 2;
    }
    # If Razor2::Client::Agent returned an error, usually EXIT_CODE 2 but to be sure classify everything except 0 and 1 as an error.
    elsif ( $ret > 1 or $ret < 0 )
    {
        $string = 'ham'; # always ham when razor fails to prevent a lot of false positives.
        ErrorLog($req_id, "Razor2::Client::Agent returned Error! See the Razor2::Client::Agent Log for details. EXIT_CODE of Razor2::Client::Agent equals '$ret'. The E-Mail has been classified as ham to prevent false positives.", $t0);
        $ret = 2;
    }
    else
    {
        $string = $logret{$ret};
    }

    print $client_socket $string;

    my $elapsed = tv_interval($t0);
    # Send stats to parent process via pipe
    print $stats_writer "$logret{$ret} $elapsed\n";
    ErrorLog( $req_id, sprintf("result: %s", $logret{$ret}), $t0 ) if $debug;

    $client_socket->shutdown(2);
    ErrorLog( $req_id, "connection closed", $t0 ) if $debug;
}

sub ErrorLog
{
    my ($req_id, $msg, $t0);
    if (@_ >= 2) {
        ($req_id, $msg, $t0) = @_;
    } else {
        $msg = shift;
        $req_id = '-';
    }
    my ($s, $usec) = gettimeofday;
    my $timestamp = strftime("%Y-%m-%dT%H:%M:%S", localtime($s)) . sprintf(".%03d", $usec / 1000);
    my $elapsed_str = '';
    if (defined $t0) {
        my $elapsed = tv_interval($t0);
        $elapsed_str = sprintf(" [%.3fs]", $elapsed);
    }
    print STDERR "[$timestamp] [$req_id]$elapsed_str $msg\n";
}

# Start the Main loop
Main();
