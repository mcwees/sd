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

$to = 'dss.remote@complete.ru; Gorlov@complete.ru';
$cc = 'alexs@complete.ru; hpsupport@dss.complete.ru';

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
<ul>
 <li><h3>Загрузка квалификаторов</h3>
<table border=1 cellspacing=0 width=80%>
 <tr>
  <th rowspan=2>Владелец</th>
  <th rowspan=2>К-во</th>
  <th rowspan=2>В день</th>
  <th width=10%>Время жизни</th>
  <th width=10%>Время до fix</th>
  <th width=10%>Время диагностики</th>
  <th width=10%>Макс. время диагностики</th>
  <th rowspan=2>Parallel</th>
 </tr>
 <tr>
  <td colspan=4 align=center>в днях</td>
 </tr>
THEAD
 $q =<<DAILY;
SELECT owner, count(*), round(count(*)::numeric/20,1) as per_day,
       round(avg(livetime),1) as avg_live,
       round(avg(fixtime),1) as avg_fix,
       round(avg(diagtime),1) as avg_diag,
       round(max(diagtime),1) as max_diag,
       round(count(*)::numeric/20 * avg(diagtime),1) as parallel
  FROM stat_monthly
  WHERE owner not in ('lyanguzov_dv', 'sokko_aa')
  GROUP BY owner ORDER by count desc;
DAILY
 $sth = &sql_exec($q);
 while ($s = $sth->fetchrow_hashref){
  foreach("owner", "per_day", "avg_live", "avg_fix", "avg_diag", "max_diag",
	  "parallel", "count"){
    if(!defined $s->{$_}){$s->{$_} = "&nbsp;"}
  }
  $daily .=<<STRING;
 <tr>
  <td>$s->{owner}</td>
  <td align=center>$s->{count}</td>
  <td align=center>$s->{per_day}</td>
  <td align=center>$s->{avg_live}</td>
  <td align=center>$s->{avg_fix}</td>
  <td align=center>$s->{avg_diag}</td>
  <td align=center>$s->{max_diag}</td>
  <td align=center>$s->{parallel}</td>
 </tr>
STRING
 }
 $daily .=<<NEXTBLOCK;
</table>
</li>
<li><h3>Закрытые кейсы по зазчикам</h3>
<table border=1 cellspacing=0 width=80%>
 <tr>
  <th rowspan=2>Заказчик</th>
  <th rowspan=2>К-во</th>
  <th width=12%>Время жизни</th>
  <th width=12%>Время fix</th>
  <th width=12%>Время диагностики</th>
  <th width=12%>Max. время жизни</th>
 </tr>
 <tr><td colspan=4 align=center>В днях</td></tr>
NEXTBLOCK
 $q =<<CUSTREQ;
SELECT customer, count(*), round(avg(livetime),1) as avg_live,
       round(avg(fixtime),1) as avg_fix,
       round(avg(diagtime),1) as avg_diag,
       round(max(livetime),1) as max_live
  FROM stat_monthly
  WHERE shortstatus = 'closed' AND diagtime is not null AND livetime is not null
  GROUP BY customer ORDER BY customer;
CUSTREQ
 $sth = &sql_exec($q);
 while ($s = $sth->fetchrow_hashref){
  foreach("customer","count","avg_live","avg_fix","avg_diag","max_live"){
	if(!defined $s->{$_}){$s->{$_} = "&nbsp;"}
  }
  $daily .=<<CUST;
 <tr>
  <td>$s->{customer}</td>
  <td align=center>$s->{count}</td>
  <td align=center>$s->{avg_live}</td>
  <td align=center>$s->{avg_fix}</td>
  <td align=center>$s->{avg_diag}</td>
  <td align=center>$s->{max_live}</td>
 </tr>
CUST
 }
 $daily .=<<NEXTSTEP;
</table>
</li>
</ul>
NEXTSTEP
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
<h2>Статистика по кейсам за 31 день</h2>
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
	Subject	=> 'Monthly report form',
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

