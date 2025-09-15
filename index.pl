#!/usr/bin/perl
#
# After login page
# started at 21/07/2026 by mcwees
#
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
use vars qw($dbh $auth_user $sth $q $s $quot_name %user_data %html_blocks
	    %form_data @qry $chat_link);

$chat_link = "http://dss.complete.ru:2223/chat";
%html_blocks = (
        auth => '',
        info => '',
	menu => '',
	caseinfo => '',
	querytime => '',
        main => '<h2>Вы не зарегистрированы в системе.</h2>',
);

#
# Subroutines
##################################################################
sub htmlout() {
#
# Formed html out
#
 use vars qw($html $auth);
# $auth = $html_blocks{auth};
 $html =<<HTML;
Content-type: text/html; charset="utf8"

<!DOCTYPE html>
<html><head>
 <title>Main user menu</title>
 <link rel=stylesheet href="/ps.css" />
</head>
<body><center>
<form method="GET" action="$ENV{SCRIPT_NAME}">
<table>
<tr class=bot><td><h2>DSS Servicedesk</h2></td>
    <td align=right>$html_blocks{auth}</td></tr>

<tr><td colspan=2 align=center>
<!-- Main menu -->
$html_blocks{menu}
</td></tr>
<tr><td colspan=2>
$html_blocks{main}
</td></tr>
</table>
<!--
$html_blocks{info}
-->
<!--
$html_blocks{querytime}
-->
</form>
</center></body>
</html>
HTML
 return $html
}

########################################################################
sub getcaselist_old() { # Можно удалить
# Get list of cases taking into account the user
 use vars qw($out $cust);
 $cust = '';
 if(defined $user_data{role} and $user_data{role} eq "customer"){
   $cust = "WHERE customer_id = $user_data{id}"
 }
 $q =<<LIST;
SELECT case_id, case_name, sn, pn, description, last_up::date,
       customer, cust_city, begin_supp, end_supp, sla,
       creator, status, message
  FROM caseinfo
  $cust
LIST
 $sth = &sql_exec($q);
 $out = "<table>\n";
 while ($s = $sth->fetchrow_hashref){
  $out .= "<tr><td rowspan=3 valign=top class=bot>";
  $out .= "<a href=chat.pl?sess_id=$user_data{session}&case_id=$s->{case_id}>$s->{case_name}</a>";
  $out .= "<br>$s->{creator}<br>$s->{last_up}</td>\n";
  $out .= "<td>$s->{sn} / $s->{pn} / $s->{sla}<br>";
  $out .= "<font size=-2>$s->{description}</font></td></tr>\n";
  $out .= "<tr><td><b>$s->{customer}, $s->{cust_city}</b>, $s->{begin_supp} -";
  $out .= " $s->{end_supp}</td></tr>\n";
  if(defined $s->{message} and $s->{message} ne ''){
    $out .= "<tr><td class=bot><br>$s->{message}</td></tr>\n"
  }else{
    $out .= "<tr><td class=bot><br>Описание проблемы отсутствует</td></tr>\n"
  }
 }
 $out .= "</table>\n";
 return $out;
}

########################################################################
sub getenv() {
# Get all environment (QUERY_STRING and POST Data)
 use vars qw($k $v $q $qsess);
 if(defined $ENV{QUERY_STRING}){
  @qry = split "&", $ENV{QUERY_STRING}}
 if(defined $ENV{CONTENT_LENGTH} and $ENV{CONTENT_LENGTH} > 0){
  read(STDIN, my $raw_post, $ENV{CONTENT_LENGTH});
  @qry = split "&", $raw_post}
 foreach(@qry){
  ($k, $v) = split "=", $_;
  $v =~ s/\+/ /g;
  $form_data{$k} = decode('UTF-8',
        uri_decode($v)) if(defined $k && defined $v)
 }
 $html_blocks{info} .= "-- ENV:\n";
 foreach(sort keys %ENV){
  $html_blocks{info} .= "$_: $ENV{$_}\n";
 }
 $html_blocks{info} .= "-- FORM:\n";
 foreach(sort keys %form_data){
  $html_blocks{info} .= "$_: $form_data{$_}\n";
 }
}

########################################################################
sub checkuser(){
# Validation of login user
 use vars qw($ret $s_count);
 $ret = 0;
 $auth_user = lc $ENV{REMOTE_USER};
 if(!defined $form_data{sess_id}){
  # Firstly need check session valid (found in DB)
  # ..
  $quot_name = "'" . $form_data{sess_id} . "'";
  $q =<<CHECKSESS;
SELECT count(*) from get_sess_owner($quot_name) WHERE NOT is_expire;
CHECKSESS
  $sth = &sql_exec($q);
  while ($s = $sth->fetchrow_hashref){
	$s_count = $s->{count}
  }
  if($s_count == 1){ # current session is valid
  }else{ # current session isn't valid
  }
  
  $quot_name = "'" . $auth_user . "'";
  $q =<<GETUSER;
SELECT id, name, email, role FROM sd_users
WHERE name = $quot_name AND is_active LIMIT 1;
GETUSER
  $sth = &sql_exec($q);
  while ($s = $sth->fetchrow_hashref){
   foreach("id", "name", "email", "role"){
     if(defined $s->{$_}){$user_data{$_} = $s->{$_}}
     else{$user_data{$_} = ''}
   }
  }
  $user_data{session} = '';
  if($auth_user eq $user_data{name}){ #User registered and active
   $q = "SELECT * FROM get_sess(" . $user_data{id} . ");";
   $sth = &sql_exec($q);
   while ($s = $sth->fetchrow_hashref){
     if(defined $s->{get_sess}){
       $user_data{session} = $s->{get_sess};
       if(!defined $form_data{sess_id}){
	$form_data{sess_id} = $user_data{session}
       }
     }
   }
  }
 } else {
  # User has been authorized and unchecked(!) session exists
  $quot_name = "'" . $form_data{sess_id} . "'";
  $user_data{session} = $form_data{sess_id};
  $q =<<GETINFO;
SELECT user_id AS id, name, email, role
  FROM get_sess_owner($quot_name);
GETINFO
   $sth = &sql_exec($q);
   while ($s = $sth->fetchrow_hashref){
   foreach("id", "name", "email", "role"){
     if(defined $s->{$_}){$user_data{$_} = $s->{$_}}
     else{$user_data{$_} = ''}
   }
  }
 }
 $html_blocks{auth} =<<AUTH;
<table class=invis>
<tr><td align=right>Пользователь</td><td>$user_data{name}</td></tr>
<tr><td align=right>Электропочта</td><td>$user_data{email}</td></tr>
<tr><td align=right>Роль</td><td>$user_data{role}</td></tr>
<!--
<tr><td align=right>Session</td><td>$user_data{session}</td></tr> -->
</table>
<input type=hidden id=sess_id name=sess_id value=$user_data{session}>
AUTH
 if(defined $user_data{id}){ $ret = 1 }
 return $ret;
}

#####################################################################
sub sql_exec {
#
# execute SQL request with timings
 use vars qw($start $end $query $ret $elapsed);
 $query = shift;
 $start = DateTime->now;
 $ret = $dbh->prepare($query);
 $ret->execute();
 $end = DateTime->now;
 $elapsed = ($end->subtract_datetime($start))->seconds;
 $query = join " ", split "\n", $query;
 $query =~ s/ +/ /g;
 $html_blocks{querytime} .= <<OUT;
Request: $query
Time: $elapsed
OUT
 return $ret
}

#####################################################################
sub menuform(){
 use vars qw($sid);
 $sid = $form_data{sess_id};
 $html_blocks{menu} =<<MENU;
 <table class=invis width=95%>
  <tr><td class=menu width=33%>
	<a href=$ENV{SCRIPT_NAME}?sess_id=$sid&act=create>
	Создать кейс для оборудования</a></td>
   <td class=menu width=33%>
	<a href=$ENV{SCRIPT_NAME}?sess_id=$sid&act=list>
	Просмотр списка кейсов</a></td>
   <td class=menu width=33%>
	<a href=$ENV{SCRIPT_NAME}?sess_id=$sid&act=defchat>
	Написать в поддержку</a></td></tr>
 </table>
MENU
}

######################################################################
sub getcaselist() {
#
# Get cases list
 use vars qw($out $cust $sid);
 $sid = $form_data{sess_id};
 $cust = '';
 if(defined $user_data{role} and $user_data{role} eq "customer"){
   $cust = "WHERE customer_id = $user_data{id}"
 }
 $q =<<LIST;
SELECT case_id, case_name, sn, pn, description::varchar(20), last_up::date,
       customer, cust_city, begin_supp, end_supp, sla, ext_name,
       creator, status, message
  FROM caseinfo
  $cust
LIST
 $sth = &sql_exec($q);
 $out = "<table>\n";
 $out .= <<THEAD;
 <tr>
  <th>N</th>
  <th>Ext</th>
  <th>Last Up</th>
  <th>Status</th>
  <th>SN</th>
  <th>PN</th>
  <th>HW Desc</th>
  <th>Issue</th>
  <th>Customer</th>
  <th>City</th>
  <th>SLA</th>
<!--  <th>Start</th>
  <th>End</th> -->
 </tr>
THEAD
 while ($s = $sth->fetchrow_hashref){
  foreach("ext_name", "sn", "pn", "description", "customer", "cust_city",
	  "sla", "end_supp", "begin_supp"){
    if(!defined $s->{$_}){ $s->{$_} = '' }
  }
  $out .= "<tr><td class=bot>";
  $out .= "<a href=$ENV{SCRIPT_NAME}?sess_id=$sid&act=casechat&case_id=" . $s->{case_id} . ">";
  $out .= "$s->{case_name}</a></td>\n";
  $out .= "<td class=bot>$s->{ext_name}</td>";
  $out .= "<td class=bot>$s->{last_up}</td>";
  $out .= "<td class=bot>$s->{status}</td>\n";
  $out .= "<td class=bot>$s->{sn}</td><td class=bot>$s->{pn}</td>";
  $out .= "<td class=bot><font size=-2>$s->{description}</font></td>\n";
  if(defined $s->{message} and $s->{message} ne ''){
    $out .= "<td class=bot>$s->{message}</td>"
  }else{
    $out .= "<td class=bot>Описание проблемы отсутствует</td>";
  }
  $out .= "<td class=bot>$s->{customer}</td>";
  $out .= "<td class=bot>$s->{cust_city}</td>\n";
  $out .= "<td class=bot>$s->{sla}</td>";
  $out .= "<!-- <td class=bot>$s->{begin_supp}</td>";
  $out .= "<td class=bot>$s->{end_supp}</td> --></tr>\n";
 }
 $out .= "</table>\n";
 return $out;
}

sub gethwinfo () {
#
# Get hardware info from contract base
 use vars qw($cust_rest $out $count $likes $retval);
 $count = 0;
 $cust_rest = $likes = $retval = "";
 if($user_data{role} eq "customer"){
   $cust_rest = "AND t2.id = $user_data{user_id}"
 }
 if(defined $form_data{sn} and $form_data{sn} ne ""){
  $likes = "'%" . $form_data{sn} . "%'";
  $q =<<SNSEL;
SELECT t1.sn, t1.id, cust_name, cust_city, cust_city, sla, begin_supp,
       end_supp, description
  FROM contract_base t1
  LEFT JOIN sn_to_customer t2 USING (sn)
  WHERE sn ilike $likes $cust_rest
SNSEL
  $sth = &sql_exec($q);
  while ($s = $sth->fetchrow_hashref){
   foreach("cust_name", "id", "description", "cust_city", "sla",
	   "begin_supp", "end_supp"){
	if(!defined $s->{$_}){ $s->{$_} = "Undefined" }
   }
   $count++;
   $retval .=<<HARD;
<table width=95%>
<tr><th align=left><input type=radio id=$s->{sn} name=selected value=$s->{sn}
  onChange="this.form.submit()"> Serial Number</th>
  <th align=left>$s->{sn}</th></tr>
<tr><td>Customer</td><td>$s->{cust_name}</td></tr>
<tr><td width=20%>Product Number</td><td>$s->{id}</td></tr>
<tr><td>Description</td><td>$s->{description}</td></tr>
<tr><td>Cust. city</td><td>$s->{cust_city}</td></tr>
<tr><td>SLA</td><td>$s->{sla}</td></tr>
<tr><td>Begin support</td><td>$s->{begin_supp}</td></tr>
<tr><td>End support</td><td>$s->{end_supp}</td></tr>
</table>
<br>
HARD
   }
  }
 return $count, $retval
}

sub inject () {
#
# Insert case and firs message
 use vars qw($qmsg $qname $c_name $ret $sess $c_id $ext_n);
 $qname = "'" . $form_data{sn} . "'";
 $ext_n = "''";
 if(defined $form_data{extname}){
	$ext_n = "'" . $form_data{extname} . "'";
 }
 $q =<<CREAT;
INSERT INTO sd_cases (user_id, sn, customer_id, sla, ext_name)
SELECT $user_data{id} AS user_id, t1.sn, t2.id as customer_id, sla,
       $ext_n AS ext_name
  FROM contract_base t1
  LEFT JOIN sn_to_customer t2 USING (sn)
 WHERE t1.sn = $qname
RETURNING id;
CREAT
 $sth = &sql_exec($q);
 while ($s = $sth->fetchrow_hashref){
  $form_data{case_id} = $s->{id} if(defined $s->{id});
 }
 $qmsg = "''";
 $qmsg = "'" . $form_data{msg} . "'" if(defined $form_data{msg});
 $q =<<ADDMSG;
INSERT INTO sd_chat (case_id, message, is_internal, user_id)
VALUES($form_data{case_id}, $qmsg, FALSE, $user_data{id});
ADDMSG
 $sth = &sql_exec($q);
 $q =<<GETNAME;
SELECT case_name FROM sd_cases WHERE id = $form_data{case_id}
GETNAME
 $sth = &sql_exec($q);
 while ($s = $sth->fetchrow_hashref){
  $c_name = $s->{case_name}
 }
 $sess = $form_data{sess_id}; $c_id = $form_data{case_id};
 # !!! Поменять линк на чат, переписав его!!
 $ret =<<SUMMARY;
<!-- msg:
$qmsg
-->
<p>Кейс $c_name для оборудования $form_data{sn} создан.</p>
<a href=/sd/chat.pl?sess_id=$sess&case_id=$c_id>
Перейти к чату по кейсу</a>
SUMMARY
 return $ret
}

###################################################################
sub createcase () {
#
# Нудная процедура создания кейса
 use vars qw($out $curr $sn $count $cust_rest $disabled $selected $tmp
	     $f_lookup $state);
 $count = $f_lookup = 0;
 $curr = $cust_rest = $disabled = $out = $tmp = $selected = "";
 if(defined $form_data{selected} and $form_data{selected} ne ""){
   $curr = $form_data{selected};
   $form_data{sn} = $form_data{selected};
   $f_lookup = 1;
 }
 if(defined $form_data{sn} and $form_data{sn} ne ""){
   $curr = $form_data{sn};
   $f_lookup = 1;
 }
 if($f_lookup == 1){
   ($count, $tmp) = &gethwinfo;
 }
 if($count == 1){
   $state = "success"; $disabled = "disabled"; $selected = "checked";
 }
 elsif($count > 1 or $count == 0){
   $state = "snselect"
 }
 $out =<<CREAT0;
<input type=hidden id=act name=act value=create>
CREAT0

# main steps but reverse --------------
 if(defined $form_data{c_st} and $form_data{c_st} eq "finmsg"){
  # final - create case and first message records in DB
  $out .= &inject;
  $out .= <<CREAT3;
  
CREAT3
 }
 elsif(defined $form_data{c_st} and $form_data{c_st} eq "success"){
  # Entering first message text for case creation
  $out .= $tmp;
  $out .= <<CREAT2;
<input type=hidden id=c_st name=c_st value=finmsg>
<input type=hidden name=sn id=sn value=$form_data{sn}>
<p>Название кейса во внешней системе
<input name=extname id=extname size=15 type=text></p>
<h3>Описание проблемы</h3>
<textarea id=msg name=msg rows=12 cols=62 required
  placeholder="Введите описание проблемы">
</textarea>
<br>
<input type=submit value="Создать">
CREAT2
 }
 elsif(!defined $form_data{c_st} or $form_data{c_st} eq "snselect"){
 # First step or choice SN
  $out .= <<CREAT1;
Введите серийный номер оборудования
 <input name=sn id=sn value="$curr" size=16>
 <input type=button value="Lookup" onClick="this.form.submit()">
 <input type=hidden id=c_st name=c_st value=$state>
CREAT1
  $out .= $tmp;
 }
 return $out;
}

sub get_caseinfo() {
#
# Get case info
#
 use vars qw($q $qsess $out $cust_f $c_found);
 $c_found = 0;
 if(defined $form_data{case_id} and $form_data{case_id} > 0){
  $cust_f = "";
  if(defined $user_data{role} and $user_data{role} eq "customer"){
    $cust_f = "AND customer = '" . $user_data{name} . "'";
  }
  $q =<<CFOUND;
SELECT count(*) FROM caseinfo WHERE case_id = $form_data{case_id} $cust_f
CFOUND
  $sth = &sql_exec($q);
  while ($s = $sth->fetchrow_hashref){
    $c_found = $s->{count} || 0
  }
  if($c_found == 1){
  $q =<<CASE;
SELECT case_id, case_name, sn, pn, description, last_up::date,
       customer, cust_city, begin_supp, end_supp, sla,
       creator, status, message, ext_name
  FROM caseinfo
  WHERE case_id = $form_data{case_id} $cust_f
CASE
  $sth = &sql_exec($q);
  $out = "<table class=invis>\n";
  while ($s = $sth->fetchrow_hashref){
   foreach("creator", "customer", "cust_city", "ext_name"){
	if(!defined $s->{$_}){$s->{$_} = ""}
   }
   $out .= "<tr><th colspan=2>$s->{case_name}</th></tr>\n";
   $out .= "<tr><th>Имя во внешней<br>системе</th>";
     $out .= "<td>$s->{ext_name}</td>\n";
   $out .= "<tr><th>Заказчик</th>";
   $out .= "<td>$s->{customer}, $s->{cust_city}</td></tr>\n";
   $out .= "<tr><th>Оборудование</th>";
   $out .= "<td><b>$s->{sn}, $s->{pn}</b><br>\n";
   $out .= "$s->{description}</td></tr>\n";
   $out .= "<tr><th>SLA</th><td>$s->{sla}</td></tr>\n";
   $out .= "<tr><th>Статус</th><td>$s->{status}</td></tr>\n";
   $out .= "<tr><th>Владелец</th><td>$s->{creator}</td></tr>\n";
  }
  $out .= "</table>\n";
  }else{
   $out = "<p>Case $form_data{case_id} not accessible</p>";
  }
 }else{
  $out = "<p>Parameter case_id not defined</p>";
 }
 return $c_found, $out
}

sub get_casechat(){
# Chat with some case
 use vars qw($case_found $html $out $url);
 ($case_found, $html) = &get_caseinfo;
 $out = $html;
 $url = "sess_id=$form_data{sess_id}&case_id=$form_data{case_id}";
 if($case_found == 1){ # case found
   $out =<<CHAT;
<table width=60%>
<tr class=bot><td><h3>Информация по кейсу</h3></td>
 <td>
$html
 </td></tr>
<tr><td colspan=2><h3>Чат по кейсу</h3></td></tr>
<tr><td colspan=2>
  <iframe id="Chat" title="Inline chat" width=900 height=750
   src="$chat_link?$url"></iframe>
</td></tr>
</table>
CHAT
 }
 return $out;
}

###################################################################
sub mainform(){
 use vars qw();
 $html_blocks{main} = "<h3>Здесь будет приветственная страница</h3>";
 if(defined $form_data{act}){ # Not default page
  if($form_data{act} eq "create"){ # There should be create case proc
   $html_blocks{main} = &createcase;
  }
  elsif($form_data{act} eq "list"){ # There should be list of cases
   $html_blocks{main} = &getcaselist;
  }
  elsif($form_data{act} eq "defchat"){ # There should be jump to default chat
  }
  elsif($form_data{act} eq "casechat"){ # There is chat with case
   $html_blocks{main} = &get_casechat;
  }
 }
}

###############################
#
#  M A I N
#
###############################

$dbh = DBI->connect("dbi:Pg:dbname=sddb","sdadm","ywTsPhO6f",
{ pg_utf8_flag => 1, pg_enable_utf8 => 1, AutoCommit => 1,
  RaiseError => 0, PrintError => 0,});

&getenv();
&checkuser();
if(defined $user_data{session} and $user_data{session} ne ""){
 &menuform();
 &mainform();
}
print &htmlout;

