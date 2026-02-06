#!/usr/bin/perl
#
# Postgres notify helper daemon
# by mcwees, started at 22.01.26
#
use strict;
use warnings;
use Proc::Daemon;
use utf8;
use Encode;
use DBI;
use DBD::Pg;
use DateTime;
use open qw( :std :encoding(UTF-8) );
use vars qw($logger $channel $q $dbh $notify $pid $payload $con $mailsend);

#### C O N S T A N T S ####
$logger = "/usr/bin/logger";
$channel = "status_change";
$mailsend = "/home/hpsupport/git/complete_1/notification.py";

#### CHECKS AND INIT DAEMON ####
Proc::Daemon::Init;

$dbh = DBI->connect("dbi:Pg:dbname=sddb","reader","canread",
{ pg_utf8_flag => 1, pg_enable_utf8 => 1, AutoCommit => 1,
  RaiseError => 1, PrintError => 0,});

# or die $DBI::errstr;

$q = "LISTEN $channel";

#### MAIN LOOP ######
$con = 1;
$SIG{TERM} = sub{$con = 0};

$dbh->do($q);

while($con){
  while($notify = $dbh->pg_notifies){
   ($channel, $pid, $payload) = @$notify;
   `$logger -t "sd-notifier[$pid]" $payload`;
   `$mailsend $payload 2>/dev/null | /usr/sbin/sendmail -t`;
  }
  sleep 5;
}

$dbh->disconnect();
exit 0;

