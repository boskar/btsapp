#!/usr/bin/perl 
# (C) by boskar 2011,2012,2013
use strict;
use warnings;
use Net::DBus::GLib;
use Glib qw/TRUE FALSE/;
use Gtk2 '-init';
use Gtk2::TrayIcon;
use DBI;
use utf8;
my $notyfikacje = TRUE;

my $bazabts = "bts";
my $bazaplik = "./btsapp.sqlite";

if ($notyfikacje) {
require Gtk2::Notify or $notyfikacje = FALSE; # '-init', "LAC/CID";
}
if ($notyfikacje) 
{
	Gtk2::Notify->init("LAC/CID");
	my $notification = Gtk2::Notify->new("btsapp", "uruchomił się poprawnie");
	$notification->show; 
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



$hbox->pack_start($vbox,1,1,0);


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
