#!/usr/bin/perl
use strict;
use warnings;
use URI::Encode qw(uri_encode uri_decode);
use utf8;
use Encode;
use DBI;
use DBD::Pg;
# use Data::Dumper;
use DateTime;
use open qw( :std :encoding(UTF-8) );
use vars qw($dbh $auth_user $sth $q %html_blocks %user_data $cookie_case
	    $chat_link $s %form_data @qry);

$chat_link = "http://dss.complete.ru:2223/chat";
$cookie_case = '';

sub htmlout() {
#
# Formed html out
#
 use vars qw($html $url);
 $url = "sess_id=$form_data{sess_id}&case_id=$form_data{case_id}";
 $html =<<OUT;
Content-type: text/html; charset="utf8"

<!DOCTYPE html>
<html><head>
 <title>DSS SD Chat</title>
 <link rel=stylesheet href="/ps.css" />
</head>
<body><center>
<table width=60%>
<tr class=bot><td><h2>DSS Service Chat</h2></td>
   <td align=right>
   $html_blocks{auth}
</td></tr>
<tr><td>Информация по кейсу</td>
  <td>
   $html_blocks{caseinfo}
   </td></tr>
<tr><td colspan=2>
  <iframe id="Chat" title="Inline chat" width=900 height=750
   src="$chat_link?$url">
  </iframe>
</td></tr>
</table></center>
<!--
$html_blocks{info}
-->
</body>

</html>

OUT

 return $html;
}

sub get_cookie() {
# Get cookies
 use vars qw(@getcookie $k $v $ret);
 if(defined $ENV{HTTP_COOKIE}){
   @getcookie = split "; ", $ENV{HTTP_COOKIE};
   foreach(@getcookie){
        ($k, $v) = split "=", $_;
        $user_data{$k} = $v;
   };
   $ret = 1
 } else {
   $ret = 0
 }
 return $ret
}

sub check_user(){
#
# Get and check user info. Returns status of checks.
#
  use vars qw($q $qsess $ret);
  $ret = 0;
  &getquery;
  if(defined $form_data{sess_id} and $form_data{sess_id} ne ''){
    $qsess = "'" . $form_data{sess_id} . "'";
    $q = "SELECT * FROM get_sess_owner($qsess)";
    $sth = &sql_exec($q);
    while ($s = $sth->fetchrow_hashref){
      $user_data{sess_id} = $form_data{sess_id};
      $user_data{email} = $s->{email} || '';
      $user_data{role} = $s->{role} || '';
      $user_data{is_expire} = $s->{is_expire} || 0;
      $user_data{user_id} = $s->{user_id} || 0;
      if(defined $s->{name}){
        $user_data{name} = $s->{name};
        $auth_user = $s->{name};
        $html_blocks{auth} =<<AUTH;
<table class=invis>
<tr><td align=right>User</td><td>$user_data{name}</td></tr>
<tr><td align=right>Email</td><td>$user_data{email}</td></tr>
<tr><td align=right>Role</td><td>$user_data{role}</td></tr>
<!--
<tr><td align=right>Session</td><td>$user_data{sess_id}</td></tr> -->
</table>
AUTH
        $ret = 1;
    }}
 }
  return $ret;
}

sub getquery() {
#
# Fill %form_data from POST and QUERY_STRING
#
 use vars qw($k $v);
 if(defined $ENV{QUERY_STRING}){
   @qry = split "&", $ENV{QUERY_STRING}}
 if(defined $ENV{CONTENT_LENGTH} and $ENV{CONTENT_LENGTH} > 0){
   read(STDIN, my $raw_post, $ENV{CONTENT_LENGTH});
   @qry = split "&", $raw_post
 }
 foreach(@qry){
   ($k, $v) = split "=", $_;
   $v =~ s/\+/ /g;
   $form_data{$k} = decode('UTF-8',
	uri_decode($v)) if(defined $k && defined $v)
 }
}

sub get_caseinfo() {
#
# Get case info
#
 use vars qw($q $qsess);
 if(defined $form_data{case_id} and
    $form_data{case_id} > 0){
  $q =<<CASE;
SELECT case_id, case_name, sn, pn, description, last_up::date,
       customer, cust_city, begin_supp, end_supp, sla,
       creator, status, message
  FROM caseinfo
  WHERE case_id = $form_data{case_id}
CASE
  $sth = &sql_exec($q);
  $html_blocks{caseinfo} = "<table class=invis>\n";
  while ($s = $sth->fetchrow_hashref){
   $html_blocks{caseinfo} .= "<tr><th colspan=2>$s->{case_name}</th></tr>\n";
   $html_blocks{caseinfo} .= "<tr><th>Заказчик</th>";
   $html_blocks{caseinfo} .= "<td>$s->{customer}, $s->{cust_city}</td></tr>\n";
   $html_blocks{caseinfo} .= "<tr><th>Оборудование</th>";
   $html_blocks{caseinfo} .= "<td><b>$s->{sn}, $s->{pn}</b><br>\n";
   $html_blocks{caseinfo} .= "$s->{description}</td></tr>\n";
   $html_blocks{caseinfo} .= "<tr><th>SLA</th><td>$s->{sla}</td></tr>\n";
   $html_blocks{caseinfo} .= "<tr><th>Статус</th><td>$s->{status}</td></tr>\n";
  }
  $html_blocks{caseinfo} .= "</table>\n";
 }
}

sub getenv() {
#
# Get all environment
#
 use vars qw($k $v $q $qsess);
 &getquery;
 &get_caseinfo;
 if(check_user()){ #Auth success
 } else { # Auth fail
 }

### 2. Get query string and POST data
#
 foreach(sort keys %ENV){
  $html_blocks{info} .= "$_: $ENV{$_}\n";
 }
}

sub sql_exec {
#
# execute SQL request with timings
#
 use vars qw($query $ret $state);
 $query = shift;
 $ret = $dbh->prepare($query);
 $state = $ret->execute();
 if($state){ return $ret }
 else{ return $dbh->errstr }
}

##########################################################
#
#             M A I N
#
##########################################################

$dbh = DBI->connect("dbi:Pg:dbname=sddb","sdadm","ywTsPhO6f",
{ pg_utf8_flag => 1, pg_enable_utf8 => 1, AutoCommit => 1,
  RaiseError => 0, PrintError => 0,});

&getenv();
print &htmlout();

