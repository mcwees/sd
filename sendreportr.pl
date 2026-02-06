#!/usr/bin/perl
#
# Sending daily call-agent activity report
# Started at 19.12.2025 by mcwees
#
use strict;
use warnings;
use URI::Encode qw(uri_encode uri_decode);
use utf8;
use Encode;
use MIME::Lite;
use DBI;
use DBD::Pg;
# use Data::Dumper;
use DateTime;
use POSIX qw(strftime);
use open qw( :std :encoding(UTF-8) );
use vars qw($dbh $sth $q $s $to $days $cc);

$to = 'Belova.T@complete.ru, Vinogradova@lanamar.ru';
$cc = 'hpsupport@dss.complete.ru';

if(defined $ARGV[0]){$days = $ARGV[0]}else{$days = 1};

sub sql_exec {
#
# execute SQL request with timings
 use vars qw($start $end $query $ret $elapsed);
 $query = shift;
 $ret = $dbh->prepare($query);
 $ret->execute();
 return $ret
}

sub daily_report (){
 use vars qw($daily);
 $daily =<<THEAD;
<table border=1 cellspacing=0>
 <tr>
  <th>Номер</th>
  <th>Имя во внешней системе</th>
  <th>Создан</th>
  <th>Кем</th>
  <th>SN оборудования</th>
  <th>Заказчик</th>
  <th>Текст обращения</th>
 </tr>
THEAD
 $q =<<DAILY;
SELECT case_name, ext_name, to_char(created_at, 'DD Mon YY HH24:MI:SS')
       AS created, t2.name AS agent, sn, t3.name, message
  FROM sd_cases t1
  LEFT JOIN sd_users t2 ON user_id = t2.id
  LEFT JOIN customers t3 ON customer_id = userid
  LEFT JOIN case_status_history t4 ON t4.case_id = t1.id
            AND LOWER(t4.status) = 'created'
  LEFT JOIN sd_chat t5 ON t5.id = related_chat_id
  WHERE role = 'call_agent'
    AND t1.created_at <= CONCAT(now()::date, ' 09:00')::timestamp
    AND t1.created_at > CONCAT(now()::date - $days, ' 09:00')::timestamp
  ORDER BY created_at
DAILY
 $sth = &sql_exec($q);
 while ($s = $sth->fetchrow_hashref){
  foreach("case_name", "ext_name", "created", "agent", "sn", "name",
	  "message"){
    if(!defined $s->{$_}){$s->{$_} = "&nbsp;"}
  }
  $daily .=<<STRING;
 <tr>
  <td>$s->{case_name}</td>
  <td>$s->{ext_name}</td>
  <td>$s->{created}</td>
  <td>$s->{agent}</td>
  <td>$s->{sn}</td>
  <td>$s->{name}</td>
  <td><pre>$s->{message}</pre></td>
 </tr>
STRING
 }
 $daily .= "</table>";
 return $daily;
}

sub htmlout (){
 use vars qw($d $out $date);
 $date = strftime "%d-%m-%Y", localtime;
 $d = &daily_report();
 $out =<<HTML;
<html>
<head><meta charset="UTF-8"></head>
<body>
<h2>Отчет о заявках, заведенных за $days дня/дней до $date</h2>
$d
</body>
</html>
HTML
}

sub mailform() {
 use vars qw($msg $att);
 $msg = MIME::Lite->new(
	From	=> 'lyanguzov@complete.ru',
	To	=> $to,
	Cc	=> $cc,
	Subject	=> 'Daily report form',
	Type	=> 'multipart/mixed',
 );
 $msg->attach(
	Type	=> 'text/html',
	Data	=> &htmlout,
 );
 return $msg->as_string;
}

###### MAIN #####
$dbh = DBI->connect("dbi:Pg:dbname=sddb","reader","canread",
{ pg_utf8_flag => 1, pg_enable_utf8 => 1, AutoCommit => 1,
  RaiseError => 0, PrintError => 0,});

print &mailform;

