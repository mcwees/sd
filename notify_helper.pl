#!/usr/bin/perl
#
# Postgres notify helper daemon
# by mcwees, started at 22.01.26
#
use strict;
use warnings;
use Proc::Daemon;

use vars qw($logger);
$logger = "/usr/bin/logger";
while(<>){
 `$logger -t "sd-notifier" $_`
}

