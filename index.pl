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
	    %form_data @qry $chat_link %role_perm);

$chat_link = "http://dss.complete.ru:2222/chat";
%html_blocks = (
        auth => '',
        info => '',
	menu => '',
	form => '',
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
 <title>Кондуктор&trade;</title>
 <link rel=stylesheet href="/ps.css" />
</head>
<body><center>
<form method="POST" action="$ENV{SCRIPT_NAME}">
<table width=60% class=shadow>
<tr class=bot><td><img src=/icons/dss-logo.png></td>
  <td><h1>DSS ServiceDesk</h1></td>
    <td align=right>$html_blocks{auth}</td></tr>

<tr><td colspan=3 align=center>
<!-- Main menu -->
$html_blocks{menu}
</td></tr>
<tr><td colspan=3>
$html_blocks{main}
$html_blocks{form}
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
sub getenv() {
# Get all environment (QUERY_STRING and POST Data)
 use vars qw($k $v $q $qsess);
 if(defined $ENV{QUERY_STRING}){
  @qry = split "&", $ENV{QUERY_STRING}
 }
 if(defined $ENV{CONTENT_LENGTH} and $ENV{CONTENT_LENGTH} > 0){
  read(STDIN, my $raw_post, $ENV{CONTENT_LENGTH});
  @qry = split "&", $raw_post}
 foreach(@qry){
  ($k, $v) = split "=", $_;
  $v =~ s/\+/ /g;
  $form_data{$k} = decode('UTF-8',
        uri_decode($v)) if(defined $k && defined $v);
  if($k eq "act" or $k eq "case_id"){ # set inputs for form
   $html_blocks{form} .=<<SETFORM;
<input type=hidden name="$k" id="$k" value="$v">
SETFORM
  }
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
# Validation of logged user
 use vars qw($ret $s_count);
 $ret = 0;
 $auth_user = lc $ENV{REMOTE_USER};
 if(!defined $form_data{sess_id}){
  # Firstly need check session valid (found in DB)
#  $quot_name = "'" . $form_data{sess_id} . "'";
#  $q =<<CHECKSESS;
#SELECT count(*) from get_sess_owner($quot_name) WHERE NOT is_expire;
#CHECKSESS
#  $sth = &sql_exec($q);
#  while ($s = $sth->fetchrow_hashref){
#	$s_count = $s->{count}
#  }
#  if($s_count == 1){ # current session is valid
#  }else{ # current session isn't valid
#  } 
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
	<a href=$ENV{SCRIPT_NAME}?act=create>
	Создать кейс для оборудования</a></td>
   <td class=menu width=33%>
	<a href=$ENV{SCRIPT_NAME}?act=list>
	Просмотр списка кейсов</a></td>
   <td class=menu width=33%>
	<a href=$ENV{SCRIPT_NAME}?act=defchat>
	Написать в поддержку</a></td></tr>
 </table>
MENU
}

######################################################################
sub getcaselist() {
#
# Get cases list
 use vars qw($out $cust $sid %close_state $state_sql %own_state $llen);
 $llen = 60;
 $sid = $form_data{sess_id};
 $cust = $state_sql = '';
 %close_state = (
	'unclosed' => 'checked',
	'closed'   => '',
	'all'	   => '');
 %own_state = (
	'self_own' => '',
	'no_own' => '',
	'all'	 => 'checked');
 if(!defined $form_data{w_status} or $form_data{w_status} eq 'unclosed'){
   $form_data{w_status} = 'unclosed';
   $state_sql = "AND NOT is_closed";
 }elsif($form_data{w_status} eq 'closed'){
   %close_state = ( 'unclosed' => '', 'closed' => 'checked', 'all' => '');
   $state_sql = "AND is_closed";
 }elsif($form_data{w_status} eq 'all'){
   %close_state = ( 'unclosed' => '', 'closed' => '', 'all' => 'checked');
 }
 if(!defined $form_data{w_owner} or $form_data{w_owner} eq 'all'){
   $form_data{w_owner} = 'all';
 }elsif($form_data{w_owner} eq 'no_own'){
   %own_state = ('self_own' => '', 'no_own' => 'checked', 'all' => '');
   $state_sql .= " AND creator IS NULL";
 }elsif($form_data{w_owner} eq 'self_own'){
   %own_state = ('self_own' => 'checked', 'no_own' => '', 'all' => '');
   $state_sql .= " AND creator = '" . $user_data{name} . "'";
 }

 if(defined $user_data{role} and $user_data{role} eq "customer"){
   $cust = "AND customer_id = $user_data{id}"
 }
 $q =<<LIST;
SELECT DISTINCT case_id, case_name, sn, pn, description::varchar(20),
       last_up::date, customer, cust_city, begin_supp, end_supp, sla,
       ext_name, creator, status, message, created_at::date
  FROM caseinfo
  WHERE status != 'hidden'
  $cust
  $state_sql
  ORDER BY created_at
LIST
 $sth = &sql_exec($q);
 $out .= <<THEAD;
 <table width=100%>
 <tr>
  <th colspan=13>
    <fieldset style="width:20%;display:inline; float:right;min-width:300px">
	<legend>Фильтрация по владельцу:</legend>
    <input type=radio id=w_owner name=w_owner value=self_own
	$own_state{self_own} onChange="this.form.submit()"> Свои |
    <input type=radio id=w_owner name=w_owner value=no_own
	$own_state{no_own} onChange="this.form.submit()"> Без владельца |
    <input type=radio id=w_owner name=w_owner value=all
	$own_state{all} onChange="this.form.submit()"> Все
    </fieldset>
    <fieldset style="width:20%; display: inline; float:right;min-width:300px">
	<legend>Фильтрация по статусу:</legend>
    <input type=radio id=w_status name=w_status value=unclosed
     $close_state{unclosed} onChange="this.form.submit()"> Незакрытые |
    <input type=radio id=w_status name=w_status value=closed
     $close_state{closed} onChange="this.form.submit()">Закрытые |
    <input type=radio id=w_status name=w_status value=all
     $close_state{all} onChange="this.form.submit()">Все
    </fieldset>
  </th>
 </tr>
 <tr>
  <th colspan=6 class="bb_thin">Информация о кейсе</th>
  <th colspan=3 class="bb_thin lb_thin">Оборудование</th>
  <th rowspan=2 class="lb_thin">Issue</th>
  <th colspan=2 class="bb_thin lb_thin">Заказчик</th>
  <th rowspan=2 class="lb_thin">SLA</th>
 </tr>
 <tr>
  <th>#</th><th>Ext</th><th>Created</th><th>Last Up</th>
	<th>Status</th><th>Owner</th>
  <th class="lb_thin">SN</th><th>PN</th><th>HW Desc</th>
<!--  <th class="lb_thin">Issue</th> -->
  <th class="lb_thin">Customer</th><th>City</th>
<!--  <th class="lb_thin">SLA</th> -->
 </tr>
THEAD
 while ($s = $sth->fetchrow_hashref){
  foreach("ext_name", "sn", "pn", "description", "customer", "cust_city",
	  "sla", "end_supp", "begin_supp", "creator"){
    if(!defined $s->{$_}){ $s->{$_} = '' }
  }
  $out .= "<tr><td class=bot>";
  $out .= "<a href=$ENV{SCRIPT_NAME}?act=casechat&case_id=";
    $out .=  $s->{case_id} . ">";
  $out .= "$s->{case_name}</a></td>\n";
  $out .= "<td class=bot>$s->{ext_name}</td>";
  $out .= "<td class=bot>$s->{created_at}</td>";
  $out .= "<td class=bot>$s->{last_up}</td>";
  $out .= "<td class=bot align=center>$s->{status}</td>\n";
  $out .= "<td class=bot>$s->{creator}</td>\n";
  $out .= "<td class=\"bot lb_thin\">$s->{sn}</td><td class=bot>$s->{pn}</td>";
  $out .= "<td class=bot><font size=-2>$s->{description}</font></td>\n";
  $out .= "<td class=\"bot lb_thin\">";
  if(defined $s->{message} and $s->{message} ne ''){
   if(length($s->{message}) > $llen){
   my $beg = substr $s->{message}, 0, $llen;
   my $tail = substr $s->{message}, $llen;
   $out .= <<LONG;
 <details class=stdtext closed><summary
	class=stdtext>$beg</summary>$tail</details>
LONG
   }else{
    $out .= "$s->{message}"
   }
  }else{
    $out .= "Описание проблемы отсутствует"
  }
  $out .= "</td>\n";
  $out .= "<td class=\"bot lb_thin\">$s->{customer}</td>";
  $out .= "<td class=bot>$s->{cust_city}</td>\n";
  $out .= "<td class=\"bot lb_thin\">$s->{sla}</td>";
  $out .= "<!-- <td class=bot>$s->{begin_supp}</td>";
  $out .= "<td class=bot>$s->{end_supp}</td> --></tr>\n";
 }
 $out .= "</table>\n";
 return $out;
}

sub gethwinfo () {
#
# Get hardware info from contract base
 use vars qw($cust_rest $out $count $likes $retval $sel $is_active $red);
 $count = 0;
 $cust_rest = $likes = $retval = "";
 if($user_data{role} eq "customer"){
   $cust_rest = "AND t2.id = $user_data{user_id}"
 }
 if(defined $form_data{sn} and $form_data{sn} ne ""){
  $likes = "'%" . $form_data{sn} . "%'";
  $q =<<SNSEL;
SELECT t1.sn, t1.id, cust_name, cust_city, cust_city, sla, begin_supp,
       end_supp, description,
       (begin_supp,end_supp) overlaps (now(),now()) AS in_range
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
   $sel = $is_active = $red = '';
   if(!$s->{in_range}){
	$is_active = 'disabled';
	$red = 'style="color:red"';
   }else{$count++;
   }
   if($form_data{selected} eq $s->{sn} and $s->{in_range}){
	$sel = 'checked disabled' };
   $retval .=<<HARD;
<table width=95%>
<tr><th align=left><input type=radio id=$s->{sn}
	$is_active $sel name=selected value=$s->{sn}> Serial Number</th>
  <th align=left>$s->{sn}</th></tr>
<tr><td>Customer</td><td>$s->{cust_name}</td></tr>
<tr><td width=20%>Product Number</td><td>$s->{id}</td></tr>
<tr><td>Description</td><td>$s->{description}</td></tr>
<tr><td>Cust. city</td><td>$s->{cust_city}</td></tr>
<tr><td>SLA</td><td>$s->{sla}</td></tr>
<tr><td>Begin support</td><td $red>$s->{begin_supp}</td></tr>
<tr><td>End support</td><td $red>$s->{end_supp}</td></tr>
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
 use vars qw($qmsg $qname $c_name $ret $sess $c_id $ext_n $m_id);
 $qname = "'" . $form_data{sn} . "'";
 $ext_n = "''";
 if(defined $form_data{extname}){
	$ext_n = "'" . $form_data{extname} . "'";
 }
 $q =<<CREAT; # 1. Создаём кейс
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
 $form_data{msg} =~ s/\'/\'\'/gm;
 $qmsg = "'" . $form_data{msg} . "'" if(defined $form_data{msg});
 $q =<<ADDMSG; # 2. Записываем сообщение в чат
INSERT INTO sd_chat (case_id, message, is_internal, user_id)
VALUES($form_data{case_id}, $qmsg, FALSE, $user_data{id})
RETURNING id;
ADDMSG
 $sth = &sql_exec($q); #тут бы надо проверить, что всё сработало
 while ($s = $sth->fetchrow_hashref){
   $m_id = $s->{id} if(defined $s->{id})
 }
 # А тут надо дополнить таблицу истории кейса или переоформить триггер в БД.
 $q =<<HIST;
INSERT INTO case_status_history (case_id, status, updated_by, related_chat_id)
VALUES($form_data{case_id}, 'created', $user_data{id}, $m_id)
HIST
 $sth = &sql_exec($q); # обновляем историю.

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
<a href=$ENV{SCRIPT_NAME}?act=casechat&case_id=$c_id>
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
 if($count == 1 and $form_data{selected} = $form_data{sn}){
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

sub sel_owners() {
 use vars qw($q %owners $out);
 $q = <<OWNERS;
SELECT DISTINCT id, name FROM sd_users t1
 LEFT JOIN roles t2 ON t1.role = t2.role OR t2.role = ANY (t1.add_roles)
 WHERE can_own ORDER BY name
OWNERS
 $sth = &sql_exec($q);
 while ($s = $sth->fetchrow_hashref){
  $owners{ $s->{name} } = $s->{id}
 }
 $out = <<S_OWN;
<select name=sel_owner id=sel_owner>
 <option value=0>--Выбрать владельца</option>
S_OWN
 foreach(sort keys %owners){
  $out .= "<option value=$owners{$_}>$_</option>\n";
 }
 $out .= <<S_OWNFIN;
</select>
<input type=button value=Назначить onClick=this.form.submit()>
S_OWNFIN
 return $out;
}

#####################################################################
sub set_owner(){
# Checks and set owner for case
 use vars qw($q $of $o_valid $o_name);
 $q =<<SET2;
SELECT owner_id FROM sd_cases WHERE id = $form_data{case_id}
SET2
 $sth = &sql_exec($q);
 $of = 1; $o_valid = 0;
 while ($s = $sth->fetchrow_hashref){
  if(!defined $s->{owner_id}){ $of = 0 }
 }
 if($of == 0){ #Owner not set
  $q = <<SET3;
SELECT DISTINCT id, name FROM sd_users t1
 LEFT JOIN roles t2 ON t1.role = t2.role OR t2.role = ANY (t1.add_roles)
 WHERE can_own AND id = $form_data{sel_owner}
SET3
  $sth = &sql_exec($q);
  while ($s = $sth->fetchrow_hashref){
   if(defined $s->{id} and $s->{id} == $form_data{sel_owner}){
	$o_valid = 1;
	$o_name = $s->{name}
   }
  }
  if($o_valid == 1){ # Устанавливаем владельца кейсу
   $o_name = "'Владельцем кейса назначен " . $o_name . "'";
   $q = <<SET4;
BEGIN;
UPDATE sd_cases SET owner_id = $form_data{sel_owner}
 WHERE id = $form_data{case_id};
SELECT * FROM status_change($user_data{id}, $form_data{case_id},
  'setowner', $o_name);
COMMIT;
SET4
   $sth = &sql_exec($q);
  }
 }
}

######################################
sub getnextstatus(){
# Get next statuses
 use vars qw($q $qstat $sqlh $src $out @states $f_found %stat_desc $sel
	     %stat_msgreq $js);
 $qstat = shift;
 $f_found = 0;
 $qstat = "'" . $qstat . "'";
 $q =<<GETNEXT;
SELECT next_status, next_desc, need_msg, layer FROM nextstatusfull
 WHERE current_status = $qstat
GETNEXT
 $sqlh = &sql_exec($q);
 $js = "const msgneed = {\n";
 while ($src = $sqlh->fetchrow_hashref){
  push @states, $src->{next_status};
  $stat_desc{$src->{next_status}} = $src->{next_desc};
  $stat_msgreq{$src->{next_status}} = $src->{need_msg};
  $js .= "   $src->{next_status}: $src->{need_msg},\n";
  $f_found = 1
 }
 $js .= "  };\n";
 if($f_found > 0){ # next statuses found
  $sel =<<SELECT;
<select name=nextstate id=nextstate ><option value=''>--Выбрать</option>
SELECT
  foreach(@states){
   $sel .= "<option value=$_>$stat_desc{$_}</option>\n";
  }
  $sel .= "</select>\n";
  $out = <<FIN02;

<!-- Popup window with change status new -->
<center>
<button onclick="openchstatus()" type="button"
	class=butt1>Дальнейшие действия</button>
</center>
 <div id="popup_my" class="popup_my">
  <table class=invis width=100%>
   <tr><th align=left width=93%>Изменение статуса</th>
       <th align=center><span onclick="closechstatus()"
	style="cursor:default; font-size:16pt;">×</span></th></tr>
   <tr><td colspan=2>
   <br>$sel<br></td></tr>
   <tr><td colspan=2 align=center>
   <label for=textmsg>Введите связанное сообщение</label><br>
   <textarea cols=40 rows=10 id=textmsg name=textmsg
	placeholder="Введите связанное сообщение здесь..."></textarea>
   </td></tr>
   <tr><td colspan=2 align=center><button onclick="closechstatus()" id=modbtn
	name=modbtn disabled>Изменить</button>
   </td></tr>
  </table>
 </div>
 <script>
  $js
  const popup_my = document.getElementById('popup_my');
  const text_my = document.getElementById('textmsg');
  const toggle_my = document.getElementById('modbtn');
  var msglen = 10;
  function openchstatus(){
   popup_my.classList.add("popup_my-open");
  }
  function closechstatus(){
   popup_my.classList.remove("popup_my-open");
  }
  nextstate.addEventListener("change", (e) => {
   msglen = msgneed[e.target.value] * 10;
   if(msgneed[e.target.value] == 0){
	toggle_my.disabled = false;
   }else{
	toggle_my.disabled = true;
   }
  });
  text_my.addEventListener("selectionchange", () => {
   if(text_my.textLength > msglen || msgneed[e.target.value] == 0){
	toggle_my.disabled = false;
   }else{
	toggle_my.disabled = true;
   }
  });
 </script>
FIN02
 }
 return $out;
}

#################################################
sub setnextstatus(){
 use vars qw($q $sf $s_valid $qstr $textval);
 $qstr = "'" . $form_data{nextstate} . "'";
 $q =<<SET01;
SELECT next_status FROM sd_cases t1
 LEFT JOIN nextstatusshort t2 ON lower(t1.status) = current_status
 WHERE id = $form_data{case_id} AND next_status = $qstr
SET01
 $sth = &sql_exec($q);
 while ($s = $sth->fetchrow_hashref){
   $sf = $s->{next_status} || ""
 }
 if($sf ne ""){
  $sf = "'" . $sf . "'"; $textval = "'" . $form_data{textmsg} . "'";
  $q =<<SET02;
SELECT * FROM status_change($user_data{id}, $form_data{case_id},
  $sf, $textval)
SET02
  $sth = &sql_exec($q);
  # ...and check return value. Should be TRUE
 }
}

sub get_caseinfo() {
#
# Get case info
#
 use vars qw($q $qsess $out $cust_f $c_found $s_owner $next_st);
 $c_found = 0;
 $s_owner = &sel_owners;
 if(defined $form_data{case_id} and $form_data{case_id} > 0){
  if(defined $form_data{sel_owner} and $form_data{sel_owner} > 0){
   &set_owner; # с морды пришел запрос на установку владельца
  }
#  if(defined $form_data{nextstate} and $form_data{nextstate} ne ""){
#   &setnextstatus; # с морды пришел запрос на смену статуса
#  }
  $cust_f = "";
  if(defined $user_data{role} and $user_data{role} eq "customer"){
    $cust_f = "AND customer_id = $user_data{id}";
  }
  $q =<<CFOUND;
SELECT count(DISTINCT case_id) FROM caseinfo
 WHERE case_id = $form_data{case_id} $cust_f
CFOUND
  $sth = &sql_exec($q);
  while ($s = $sth->fetchrow_hashref){
    $c_found = $s->{count} || 0
  }
  if($c_found == 1){ # Case found
   if(defined $form_data{nextstate} and $form_data{nextstate} ne ""){
    &setnextstatus;
   }
   # get status and get possible next statuses
  $q = <<GETST;
SELECT shortstatus FROM caseinfo
 WHERE case_id = $form_data{case_id} $cust_f
GETST
  $sth = &sql_exec($q);
  while ($s = $sth->fetchrow_hashref){
	$next_st = $s->{shortstatus}
  }
  $next_st = &getnextstatus(lc($next_st));
  $q =<<CASE;
SELECT case_id, case_name, sn, pn, t1.description, last_up::date,
       customer, cust_city, begin_supp, end_supp, sla,
       creator, t2.status, message, ext_name, t2.description AS status_desc
  FROM caseinfo t1
  LEFT JOIN case_statuses t2 ON t2.status = t1.shortstatus
  WHERE case_id = $form_data{case_id} $cust_f
CASE
  $sth = &sql_exec($q);
  while ($s = $sth->fetchrow_hashref){
   foreach("creator", "customer", "cust_city", "ext_name"){
	if(!defined $s->{$_}){$s->{$_} = ""}
   }
   $out =<<CASE_DET;
<details open><summary>Детали по кейсу $s->{case_name}</summary>
<table width=98%>
<tr><th class=bb_thin>Номер во внешней<br>системе</th>
  <td class=bb_thin>$s->{ext_name}</td>
<tr><th class=bb_thin>Заказчик</th>
  <td class=bb_thin>$s->{customer}, $s->{cust_city}</td></tr>
<tr><th class=bb_thin>Оборудование</th>
  <td class=bb_thin><b>$s->{sn}, $s->{pn}</b><br>
        $s->{description}</td></tr>
<tr><th class=bb_thin>Неисправность</th>
  <td class=bb_thin>$s->{message}</td></tr>
<tr><th class=bb_thin>Последнее изменение</th>
  <td class=bb_thin>$s->{last_up}</td></tr>
<tr><th class=bb_thin>SLA</th><td class=bb_thin>$s->{sla}</td></tr>
<tr><th class=bb_thin>Владелец</th>
CASE_DET
   if($s->{creator} eq ""){ # Owner not set
     $out .= <<SETOWNER1;
<td>Назначить: $s_owner</td></tr>
SETOWNER1
     if(!defined $form_data{act}){
       $out .= "<input type=hidden name=act id=act value=casechat>\n";
     }
     if(!defined $form_data{case_id}){
	$out .= "<input type=hidden name=case_id id=case_id value=$form_data{case_id}>\n";
     }
   }else{
     $out .= "<td class=bb_thin>$s->{creator}</td></tr>\n";
   }
   $out .=<<STATUS;
<tr><th class=bb_thin>Статус</th>
  <td class=bb_thin>$s->{status_desc}</td><tr>
STATUS
  }
  $out .= "</table></details><br>$next_st\n";
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
$html
<h3>Чат по кейсу</h3><center>
  <iframe id="Chat" title="Inline chat" width=900 height=750
   src="$chat_link?$url"></iframe></center>
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
   $html_blocks{main} = "<h2>Здесь будет просто чат</h2>\n";
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

