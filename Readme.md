# Razorfy - oletools verify over TCP socket

Small Perl Daemon to use razor over TCP sockets. Mainly to use razor in [Rspamd](https://github.com/rspamd/rspamd).

## State of Development

This Daemon is production tested but maybe not bug free. Feel free to test and
please report any issues.

## How it works

razorfy expects raw mails to be send to the TCP socket. razorfy checks the mail against the Razor packages and returns ham or spam

## Future plans

The Perl Razor package is able to return more detailed results. We will maybe also return extended results to Rspamd.

## Razor

[http://razor.sourceforge.net/](http://razor.sourceforge.net/)

### What is Vipul's Razor?
Vipul's Razor is a distributed, collaborative, spam detection and filtering network. Through user contribution, Razor establishes a distributed and constantly updating catalogue of spam in propagation that is consulted by email clients to filter out known spam. Detection is done with statistical and randomized signatures that efficiently spot mutating spam content. User input is validated through reputation assignments based on consensus on report and revoke assertions which in turn is used for computing confidence values associated with individual signatures.

# Default Installation

## Install Perl razor

-   use cpan, apt, yum, zypper or the source to install the Perl version of razor

~~~
apt install razor
~~~

~~~
yum install perl-Razor-Agent
~~~

## Install razorfy

-   clone or download this repo
-   **add the user and group razorfy** or edit razorfy.service to use any other existing user/group
-   edit razorfy.conf to fit your needs
-   copy razorfy.pl daemon file to /usr/local/bin
-   copy razorfy.conf to /etc
-   copy the systemd service file razorfy.service to /etc/systemd/system
-   enable and unmask the Service
~~~
systemctl daemon-reload
systemctl unmask razorfy.service
systemctl enable razorfy.service
~~~

# Settings

Have a look to the commented razorfy.conf.

# Debugging

Set `RAZORFY_DEBUG=1` and have a look to the logs `journalctl -u razorfy`

# License

Apache-2.0

# Author Information

*   **[Mirko Ludeke](mailto:m.ludeke@heinlein-support.de)** - [mludeke](https://github.com/mludeke)
*   **[Carsten Rosenberg](mailto:c.rosenberg@heinlein-support.de)** - [c-rosenberg](https://github.com/c-rosenberg)

~~~
Heinlein Support GmbH
Schwedter Str. 8/9b, 10119 Berlin

https://www.heinlein-support.de

Tel: +4930 / 405051-110

Amtsgericht Berlin-Charlottenburg - HRB 93818 B
Geschäftsführer: Peer Heinlein - Sitz: Berlin
~~~
