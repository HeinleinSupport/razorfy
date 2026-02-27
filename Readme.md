# Razorfy - razor verify over TCP socket

Small Perl Daemon to use razor over TCP sockets. Mainly to use razor in [Rspamd](https://github.com/rspamd/rspamd).

## State of Development

This Daemon is production tested but maybe not bug free. Feel free to test and
please report any issues.

## How it works

razorfy expects raw mails to be sent to the TCP socket. razorfy checks the mail against the Razor packages and returns ham or spam.

## Features

- **TCP socket interface** – Accepts raw email messages over a TCP socket, making it easy to integrate with mail filters like [Rspamd](https://github.com/rspamd/rspamd).
- **Razor spam detection** – Checks each email against the [Vipul's Razor](http://razor.sourceforge.net/) distributed spam detection network.
- **Multi-process** – Handles multiple concurrent connections using forked worker processes with a configurable limit.
- **Fail-safe classification** – If the Razor check fails or throws an exception, the message is classified as ham to prevent false positives.
- **Periodic statistics** – Logs aggregated stats (total, ham, spam, error counts, and timing) at a configurable interval.
- **Dual-stack networking** – Supports binding to IPv4, IPv6, or dual-stack addresses.
- **Systemd integration** – Ships with a systemd service unit including security hardening options.

## Configuration Options

Razorfy is configured through environment variables, typically set in `/etc/razorfy.conf` which is loaded by the systemd service unit.

| Variable | Default | Description |
|---|---|---|
| `RAZORFY_DEBUG` | `0` | Set to `1` to enable debug logging. |
| `RAZORFY_MAXTHREADS` | `200` | Maximum number of concurrent worker processes. |
| `RAZORFY_BINDADDRESS` | `127.0.0.1` | Address to bind the TCP listener to. Use `::` for dual-stack, `0.0.0.0` for all IPv4, `::1` for IPv6 localhost. |
| `RAZORFY_BINDPORT` | `11342` | TCP port to listen on. |
| `RAZORFY_RAZORHOME` | `~/.razor` | Path to the Razor configuration/home directory. |
| `RAZORFY_STATS_INTERVAL` | `900` | Interval in seconds between statistics log lines (default 15 min). |

## Future plans

The Perl Razor package is able to return more detailed results. We will maybe also return extended results to Rspamd.

## Razor

[http://razor.sourceforge.net/](http://razor.sourceforge.net/)

### What is Vipul's Razor?
> Vipul's Razor is a distributed, collaborative, spam detection and filtering network. Through user contribution, Razor establishes a distributed and constantly updating catalogue of spam in propagation that is consulted by email clients to filter out known spam. Detection is done with statistical and randomized signatures that efficiently spot mutating spam content. User input is validated through reputation assignments based on consensus on report and revoke assertions which in turn is used for computing confidence values associated with individual signatures.

# Default Installation

## Install Perl razor and perl-IO-Socket-IP

-   use cpan, apt, yum, zypper or the source to install the Perl version of razor and perl-IO-Socket-IP

~~~
apt install razor libio-socket-ip-perl
~~~

~~~
yum install perl-Razor-Agent perl-IO-Socket-IP
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

# Development
For development it's recommended to create a virtual environment using [perlbrew](https://perlbrew.pl/).

## Initialize environment
```
perlbrew --notest install perl-5.38.2
perlbrew lib create perl-5.38.2@razorfy
perlbrew use perl-5.38.2@razorfy
perlbrew install-cpanm
cpanm --with-develop --installdeps .
```

**Hint:** By using `perlbrew available` you can see the available Perl versions and adapt the previous commands if you wish to develop with another version of Perl.


## Enable environment in this terminal
```
perlbrew use perl-5.38.2@razorfy
```

## Disable environment
```
perlbrew switch-off
```

## See if environment is set
```
perlbrew switch
```



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
