#!/usr/bin/perl
#####################################################################
# Copyright notice			
#																	
# Written by Marcel Spark <info@mzhost.de/>						
# (C) 2016 maze 													
#																	
# This script is distributed in the hope that it will be useful,	
# but WITHOUT ANY WARRANTY; without even the implied warranty of	
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.				
#																	
# This copyright notice MUST APPEAR in all copies of the script!	
#####################################################################
# beta 1.0 / Todo:
# -bessere Config (eigene Ini Datei)
# -optimierung
#####################################################################
use strict;
use warnings;
use Net::Telnet; # use cpan telnet
use Fcntl qw(:flock); 

#Config
my @client=('yov5kUyQD5QRMgGC55Ea/BK1Gv8=', 'H2RCdafwFn1j71pAAtiLeTwYAuE=');
#/Config
my $register= "notifycliententerview";

our $query="";
our $line="";
&qlogin;
$query->errmode( sub { exit(0) } );
mainloop ();
exit (0);
sub mainloop {
	my $client;
	my $clientname;
	next_line:
	$line = $query->getline(Timeout => 250);
	#$line =~ s/[\r\n]//g;
	if (!$line) {&qlogin;}
	if ($line=~ /notifycliententerview schandlerid=/) {
		for $client (@client) {	
			if ($line =~ /client_unique_identifier=$client/) {
				my @line_values = split(" ",$line);
      				foreach my $e (@line_values)
      				{
	       				$e =~s/(client_nickname=)(.*)//;
					if ($1) {
						$clientname=$2; 
						last;   
					}	
				}
				my $ownid = &whoami;
				&msg ($ownid,"$clientname ist auf den Server gejoint!");
			}
		}
	}
	goto next_line;
}
sub qlogin{
	my $ip="127.0.0.1";
	my $line="";
	$query = new Net::Telnet (Timeout => undef); 
	$query->open(Host => $ip,
				 Port => 25639);
	$query->errmode( sub { sleep 0.1 } );
	sleep 0.5;
	$line=$query->getline();
	if (!$line){$line="miiip";}	
	CheckResult($line,"TS3","Clientquery verbindung fehlgeschlafen");
	$query->print("clientnotifyregister schandlerid=0 event=$register");  
	#$query->getline();
	#$query->print("whoami"); 
	#$line= $query->getline(); 
	#CheckResult($query->getline(),"error id=.*? msg=ok","Whoami fehlgeschlagen!!");
	#$line =~ s/[\r\n\t]//gi;
	#$line =~ s/= /# /gi;
	#my %hash = split /[=\s]/, $line;
	#my $id = $hash{clid};
	#print "$id";	
	#CheckResult($query->getline(),"error id=.*? msg=ok","NotifyRegister fehlgeschlagen!!");
	#$query->print ("sendtextmessage targetmode=2 msg=Hello\sChannel");
	#return ($id);
}
sub whoami {
	$query->print("whoami");
	$line= $query->getline(); 
	$line =~ s/[\r\n\t]//gi;
	$line =~ s/= /# /gi;
	my %hash = split /[=\s]/, $line;
	my $id=$hash{clid};	
	return ($id);
}
sub msg {
	my $ownid= shift;	
	my $out =shift;
	
	$out =~ s/ /\\s/gi;
	$query->print("sendtextmessage targetmode=1 target=$ownid msg=$out");	
}
sub CheckResult{
	my $line =shift;
	my $check = shift;
	my $msg=shift;
	$line =~ s/\r\n\t//gi;
	
	if( $line =~ /$check/) {
		return;
	}
	print "\n".$msg."\n";
	exit(0);
}
