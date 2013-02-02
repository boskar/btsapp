#!/usr/bin/perl 
# (C) by boskar 2011,2012
use strict;
use warnings;
use Net::DBus::GLib;
use Format::Human::Bytes;
use Glib qw/TRUE FALSE/;
#use utf8;
#BEGIN { $ENV{LC_ALL} = "pl_PL.utf8"; }

#use utf8;   # Needed for Hebrew

use Gtk2 '-init';
use Gtk2::TrayIcon;
#use utf8;
use DBI;
use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error);
use LWP::Simple;
my $notyfikacje = TRUE;
my $signal_stats = FALSE;
my $aktualizuj_baze = TRUE;
my $bazabts = "bts";
#my $bazaplik = $ENV{"HOME"} . "/.btsapp.sqlite";
my $bazaplik = "./btsapp.sqlite";

if ($notyfikacje) {
use Gtk2::Notify '-init', "LAC/CID";
}


if (-e $bazaplik) {
(my $content_type_bazy, my $dlugosc_bazy, my $czas_mod_bazy, my $expires_bazy, my $server_bazy) = head ("http://obsolete/btsapp/btsapp.sqlite");
unless ($dlugosc_bazy != -s $bazaplik) { 
$aktualizuj_baze = FALSE;

}}
if ($aktualizuj_baze) {
my $temp_bz2 = $ENV{"HOME"} . "/.btsapp.sqlite.bz2";
$| = TRUE;
print "Aktualizuję bazę BTSów!\n";
getstore("http://obsolete/btsapp/btsapp.sqlite.bz2",$temp_bz2);
bunzip2 $temp_bz2 => $bazaplik;
unlink $temp_bz2;
}


my $icon = Gtk2::TrayIcon->new("LAC/CID");

my $hbox = Gtk2::HBox->new(0,0);

my $vbox = Gtk2::VBox->new(0,0);
my $vbox_ppp = Gtk2::VBox->new(0,0);

my $bus = Net::DBus::GLib->system;


my $service_nm = $bus->get_service("org.freedesktop.NetworkManager"); 

# find proper device
my $obj_devlist_nm = $service_nm->get_object("/org/freedesktop/NetworkManager");
sub flatten { map @$_, @_ }
my @devlist_nm = flatten($obj_devlist_nm->GetDevices());
my @devlist_cell;
foreach (@devlist_nm)
{
#	print $_ . "\n";
	my $object_nm = $service_nm->get_object($_);
#	print $object_nm->Get("org.freedesktop.NetworkManager.Device","DeviceType");
	if ($object_nm->Get("org.freedesktop.NetworkManager.Device","DeviceType") == "8")
	{
#	print $_;
		push (@devlist_cell, $_);
	}
}
my $device_proper_nm;
if (@devlist_cell == "1") { $device_proper_nm = $devlist_cell[0]; }
elsif (@devlist_cell > "1") { $device_proper_nm = $devlist_cell[0]; } 
else { die "Nie wykryto modemu!";}
use Data::Dumper; print Dumper @devlist_cell;
print  $device_proper_nm ;
my $object_nm = $service_nm->get_object($device_proper_nm);
my $device_proper_mm = $object_nm->Get("org.freedesktop.NetworkManager.Device","Udi"); 
print $device_proper_mm;
if ($signal_stats) {
my $interface_nm = $object_nm->as_interface("org.freedesktop.NetworkManager.Device");
$object_nm->connect_to_signal("PppStats",\&update_pppstats);
}

#print $object_nm->Get("org.freedesktop.NetworkManager.Device","Udi"); 
#print $interface_nm->("Udi");
#print $object_nm->Get(undef,"Udi");
#my $properties = $bus->get_service("org.freedesktop.DBus");
#my $prop2 = $properties->get_object("/org/freedesktop/DBus");
#my $prop3 = $prop2->gas_interface("org.freedesktop.DBus.Properties");
#$prop3->Get("org.freedesktop.NetworkManager.Device");

my $service = $bus->get_service("org.freedesktop.ModemManager");
my $object = $service->get_object($device_proper_mm);  
my $object_mod = $object->as_interface("org.freedesktop.ModemManager.Modem");
$object_mod->Enable("1");
my $object_loc = $object->as_interface("org.freedesktop.ModemManager.Modem.Location");
$object_loc->Enable("1","1");
my $laccid = $object_loc->GetLocation();


my $laccid_znane;
my $lac;
my $lcid;
my $cid;
my $rnc;
my $mccmnc;
if (defined ${$laccid}{2}) { $laccid_znane = "1"; } else { $laccid_znane = "0"; print "NIEZNANE";}

if ($laccid_znane) {
my @laccidy = split ( /,/, ${$laccid}{2}); #or die("Dane LAC/CID niedostępne.");
$lac =  hex($laccidy[2]) ;
$lcid =  hex($laccidy[3]) ;
$cid = $lcid % "65535";
$rnc = int($lcid/"65535");
#$rnc = "00000";
$mccmnc = $laccidy[0] . $laccidy[1];
}
unless ($laccid_znane) {
	$lac = "NIE";
	$cid = "ZNANE";
	$mccmnc = "NIE";
}
my $laclabel = Gtk2::Label->new;
$laclabel->set_markup("<span size=\"x-small\">LAC: $lac </span>");
my $cidlabel = Gtk2::Label->new;
$cidlabel->set_markup("<span size=\"x-small\">CID: $cid </span>");
$vbox->pack_start($laclabel,1,1,0);
$vbox->pack_start($cidlabel,0,0,0);


my $ipstatlabel_in;
my $ipstatlabel_out;
if ($signal_stats) {
$ipstatlabel_in = Gtk2::Label->new;
$ipstatlabel_in->set_markup("<span size=\"x-small\">DL: czekaj...</span>");
$ipstatlabel_out = Gtk2::Label->new;
$ipstatlabel_out->set_markup("<span size=\"x-small\">UL: czekaj...</span>");

$vbox_ppp->pack_start($ipstatlabel_in,1,1,0);
$vbox_ppp->pack_start($ipstatlabel_out,0,0,0);
}

$hbox->pack_start($vbox,1,1,0);

if ($signal_stats) { $hbox->pack_start($vbox_ppp,0,0,0); }

my $eventbox = Gtk2::EventBox->new;
$eventbox->add($hbox);

$eventbox->signal_connect ('button-press-event' => \&button_callback, my $user_data);




#DBI part
my $comment;
my $dbh = DBI->connect ("dbi:SQLite:dbname=$bazaplik",undef, undef, {sqlite_unicode => 1});
#$dbh->{sqlite_encoding = "utf8"} ;
 
 if ($laccid_znane) {
my $sth = $dbh-> prepare("SELECT DESCRIPTION FROM \"$bazabts\" WHERE MCCMNC=\"$mccmnc\" AND CID=\"$cid\" AND RNC=\"$rnc\"");
$sth->execute;
my $counter = "0";
while (my @data = $sth->fetchrow_array()) {
$comment = $data[0];
print $comment;
$counter++
}
#if ($counter = "1") { $comment = $sth; }
if ($counter != "1")  { $comment = "Nie znaleziono BTSa w bazie"; } 
}
else { $comment = "Interfejs Dbus ModemManagera nie podaje LAC/CID"; }
my $tooltip = Gtk2::Tooltips->new;
$tooltip->set_tip($eventbox, $comment);
#print $comment;


$icon->add($eventbox);
$icon->show_all;
Glib::Timeout-> add(1000, sub{ &update_laccid() });
Gtk2->main();
sub update_laccid {
	$laccid = $object_loc->GetLocation();
	if (defined ${$laccid}{2}) { $laccid_znane = "1"; } else { $laccid_znane = "0"; }
	if ($laccid_znane) {
	my @laccidy = split ( /,/, ${$laccid}{2});
	
	if (($lac != hex($laccidy[2])) || ($cid != (hex($laccidy[3]) % "65535")))
	{
	$lac =  hex($laccidy[2]) ;
	$lcid =  hex($laccidy[3]) ;
	$cid = $lcid % "65535";
	$rnc = int($lcid/"65535");
	$laclabel->set_markup("<span size=\"x-small\" foreground=\"red\">LAC: $lac </span>");
	$cidlabel->set_markup("<span size=\"x-small\" foreground=\"red\">CID: $cid </span>");
	my $sth = $dbh-> prepare("SELECT DESCRIPTION FROM \"$bazabts\" WHERE MCCMNC=\"$mccmnc\" AND CID=\"$cid\" AND RNC=\"$rnc\"");
	$sth->execute;
	while (my $data = $sth->fetchrow_arrayref()) {
	$comment = $data->[0]; }
	$tooltip->set_tip($eventbox, $comment);
	if ($notyfikacje == TRUE) {
	my $notification = Gtk2::Notify->new("Nowy BTS/nodeB", $comment);
	$notification->show; }
	}
	
	else
	{
	$laclabel->set_markup("<span size=\"x-small\">LAC: $lac </span>");
	$cidlabel->set_markup("<span size=\"x-small\">CID: $cid </span>");
	}
}
else
	{
	$laclabel->set_markup("<span size=\"x-small\">LAC: NIE </span>");
	$cidlabel->set_markup("<span size=\"x-small\">CID: ZNANE </span>");
}
	return 1;
}

sub button_callback  {
my ($widget, $event) = @_;
if ($event->button == 1) { 
	my $sth = $dbh-> prepare("SELECT * FROM $bazabts WHERE MCCMNC=\"$mccmnc\" AND CID=\"$cid\"");
	$sth->execute;
	my $pos_lat;
	my $pos_lon;
	my $counter = "0";
	while (my $data = $sth->fetchrow_arrayref()) {
	$pos_lat = $data->[4]; 
	$pos_lon = $data->[5];
	$counter++; }
	if ($counter == "1") {
	system("xdg-open http://mapa.btsearch.pl/gps/ll/$pos_lat,$pos_lon/z/17"); }
	else {
	system("xdg-open http://mapa.btsearch.pl/"); }
	
	 };

if ($event->button == 3) { Gtk2->main_quit; return 1; };
#else { return FALSE; };
}

sub update_pppstats {
	my ($in,$out) = @_;
	my $in_kb = Format::Human::Bytes->base2($in);
	$ipstatlabel_in->set_markup("<span size=\"x-small\">DL: $in_kb</span>");  
	my $out_kb = Format::Human::Bytes->base2($out);
	$ipstatlabel_out->set_markup("<span size=\"x-small\">UL: $out_kb</span>");  
}
