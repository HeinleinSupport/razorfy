#!/usr/bin/env perl

# Copyright (c) 2023, Mirko Ludeke <m.ludeke@heinlein-support.de>
# Copyright (c) 2023, Carsten Rosenberg <c.rosenberg@heinlein-support.de>
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
use threads;
use Data::Dumper;
use POSIX qw(setlocale);
use Razor2::Client::Agent;


# set to 1 to enable debug logging
my $debug       = defined($ENV{'RAZORFY_DEBUG'}) ? $ENV{'RAZORFY_DEBUG'} : 0;

# max number of threa to use
my $maxthreads  = defined($ENV{'RAZORFY_MAXTHREADS'}) ? $ENV{'RAZORFY_MAXTHREADS'} : 200;

# bind razorfy by default to v4only localhost address
# use :: for all (dual stack), 0.0.0.0 for all (v4only), ::1 for localhost (v6only), 127.0.0.1 for localhost (v4only)
my $bindaddress = defined($ENV{'RAZORFY_BINDADDRESS'}) ? $ENV{'RAZORFY_BINDADDRESS'} : '127.0.0.1';

# tcp port to use
my $bindport    = defined($ENV{'RAZORFY_BINDPORT'}) ? $ENV{'RAZORFY_BINDPORT'} : '11342';

# How should emails be classsified if razor breaks?
my $classification_when_razor_errors = defined($ENV{'CLASSIFICATION_WHEN_RAZOR_ERRORS'}) ? $ENV{'CLASSIFICATION_WHEN_RAZOR_ERRORS'} : 'ham';

my $agent = new Razor2::Client::Agent('razor-check') or die ;
    $agent->read_options() or die $agent->errstr ."\n";
    $agent->do_conf()      or die $agent->errstr ."\n";

my %logret = ( 0 => 'spam', 1 => 'ham', 2 => 'error' );

sub Main
{
    # flush after every write
    $| = 1;

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

    my @clients = ();

    # start infinity loop
    while(1)
    {
        # Limit threads
        my @threads = threads->list(threads::running);

        if( $#threads < $maxthreads )
        {
            # Waiting for new client connection.
            $client_socket = $socket->accept();

            # Push new client connection to it's own thread
            push ( @clients, threads->create( \&clientHandler, $client_socket ) );

            ErrorLog(  "active threads: $#threads") if $debug ;
            ErrorLog(  "client array length: " . scalar @clients) if $debug ;

            my $counter = 0;
            foreach ( @clients )
            {
                if( $_->is_joinable() )
                {
                    $_->join();
                }

                if( not $_->is_running() )
                {
                    splice(@clients,$counter,1);
                }

                $counter++;
            }
        }
    }
    $socket->close();
    return 1;
}

sub clientHandler
{
    # Socket is passed to thread as first (and only) argument.
    my ($client_socket) = @_;

    # Create hash for user connection/session information and set initial connection information.
    my %user = ();
    $user{peer_address} = $client_socket->peerhost();
    $user{peer_port}    = $client_socket->peerport();

    ErrorLog( "Accepted New Client Connection From:".$user{peer_address}.":".$user{peer_port} ) if $debug;

    my %hashr;
    $hashr{'fh'} = $client_socket;

    my $ret = $agent->checkit(\%hashr);
    my $string;

    # If Razor2::Client::Agent returned an error, usually EXIT_CODE 2 but to be sure classify everything except 0 and 1 as an error.
    if ( $ret > 1 or $ret < 0 )
    {
        $string = $classification_when_razor_errors;
        ErrorLog("Razor2::Client::Agent returned Error! See the Razor2::Client::Agent Log for details. EXIT_CODE of Razor2::Client::Agent equals '$ret'. The E-Mail has been classified as '$classification_when_razor_errors' as defined in your razorfy.conf");
        $ret = 2;
    }
    else
    {
        $string = $logret{$ret};
    }

    print $client_socket $string;

    ErrorLog( "return value: ". $logret{$ret} ) if $debug;

    $client_socket->shutdown(2);
    threads->exit();
}

sub ErrorLog
{
    setlocale(&POSIX::LC_ALL, "en_US");
    my $msg = shift;
    print STDERR $msg."\n";
}

# Start the Main loop
Main();
