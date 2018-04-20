#!/usr/bin/perl
#################
#Marcel Spark
#maze@mzhost.de
#Version 1.5.1
#
#Requirements:
#	- for Net::Telnet apt-get install libdate-calc-perl libnet-telnet-perl (debian based Systems
#	- for Config::Simple sudo cpan ; install Config::Simple
#Todo:
#	- Documentation
#	- Uhrzeit einfügen (Zeile *)
# 	- Nickname einfügen (Zeile *)
#	- ID Bugs beheben (Zeile *, *). Bei einigen ID's stüzt der Bot ab.
#		- Escape zeichen. Aus 7p50YiMKv/kwxqLBCc8mWF1pObI= wird 7p50YiMKv\/kwxqLBCc8mWF1pObI= in der Winners.txt
#		- Wenn die ID ein + vorne dran hat
#	- Konsolen Output
#	- mehr fehlerbehebung
##################

use strict; # Auskommentieren 
use warnings; # Auskommentieren
use Net::Telnet;
use File::Copy;
use Fcntl qw(:flock); 
use Config::Simple;	

#///
my $performance = 0; # Einstellungsmöglichkeit für Performance
my $debug = 0; # Einstellungsmöglichkeit für eine Log Datei | Noch nicht implementiert
#///

my $ownid; #### Entfernen #####
my $gotError ++= 0; # Sollte die Variable den Wert 1 annehmen, wird das Skript bei gelegenheit beendet.  Führt nicht zum sofortigen Abbruch

# Teste den ersten start. 
open INI, "<", "settings.ini" or &createINI; # Prüfe ob eine INI Datei vorhanden ist. Wenn nicht, erstelle sie
open CREATE, "<", "running.txt" or &createData(0);
close INI;
close CREATE;


# READ CONF.
my %config;
Config::Simple->import_from('settings.ini', \%config); # Lese die Konfigurationsdatei
my @requirements = qw< default.queryname default.querypw default.nickname default.serverid default.usechannelid default.server_ip default.queryport default.raetsel default.maxtrys default.helptext default.loesung default.loesung2 default.send_welcome default.send_win1 default.send_win2 >; # Gibt die benötigten Argumente für die Konfig. vor. 
for ( @requirements ) {  # Verify
    warn( "Parameter '$_' is missing from INI" ) # Wirf Error falls etwas nicht vorhanden ist.
      unless exists $config{$_};
}

my $query = &qlogin;

while ($gotError == 0) { 
	# Der Mainloop wird erneut aufgerufen wenn dieser nicht durch ein goto zurückgesetzt wird.
	# Dies geschieht wenn mit dem Bot interagiert wird
	mainloop();
}

sub mainloop {
 
	next_line: # Flag setzten

	my $line = $query->getline(Timeout => 250); 
	$line =~ s/[\r\n]//g;
	if ($line =~ / msg=/) {
		if ($line =~ /msg=!help/) {
			SendText ($config{'default.helptext'}); 
			goto next_line;
		}
		if (!($line =~ / msg=!/) && !($line =~ / msg=#/) && $performance == 1) {
			# Wenn kein ! oder # vor einem Wort steht, wird es ignoriert. 
			# Sollte $performance auf 0 stehen, wird jede Antwort geprüft
			goto next_line;
		}
	} elsif ( $line =~ /notifyclientmoved ctid=$config{'default.usechannelid'} reasonid=0/) {
		# Wenn ein Client den eigenen Channel betritt
		SendText ($config{'default.send_welcome'});
		goto next_line;
	} else { # Wenn kein msg= oder kein move in $line ist
		if (!$line) {
			$query = &qlogin; 	
		}
		goto next_line;
	}
	
	my $msg;
	my $invokeruid;
	my $invokerid;	
	my @line_values = split(" ",$line);
	foreach my $e (@line_values) {
		if ($e =~ /invokeruid?/) {
			$e =~s/invokeruid=//; # Aus der aktuellen Seite rausfiltern, sodass nur die ID übrig bleibt
			$invokeruid = $e; # in die Variable Schreiben
		}
		if ($e =~ /invokerid?/) {
			$e =~s/invokerid=//; 
			$invokerid = $e;
		}
		if ($e =~ /msg=?/) {
			$e =~s/msg=//; 
			$msg = $e;
		}
	}
	if ($ownid eq $invokerid) { # Reagiere nicht wenn es die eigenen Nachricht ist.
		goto next_line;
	}

	my $win = wincheck($invokeruid); # Prüft ob die Person schon einmal gewonnen hat
	my $dbid = clientInfo($invokerid);
	my $versuche = counterVersuche($dbid);

	unless ($win == 1 || ($versuche >= $config{'default.maxtrys'} && $config{'default.maxtrys'} != 0)) { #Betrete nur wenn kein Win oder noch Versuche das sind. 	
		if ($msg eq "!play") {
			# Wenn der Client !play schreibt, wird eine Datei beschrieben und ein Privater Chat geöffnet
	
			open PLAYER, ">>", "$dbid.txt" or throwError("info","Die Datei eines Spielers konnte nicht beschrieben werden: $!");
			close (PLAYER);
			SendPrivat($config{'default.raetsel'},$invokerid); # Schicke Spieler eine Nachricht mit dem "Rasetsel"
			goto next_line;
		} elsif ($line =~ /notifytextmessage targetmode=1/) {	
			# Wenn der Bot eine Privatenachricht bekommt, wird die Nachricht in die Client Datei geschrieben. Außerdem werden diese Nachrichten auf Lösungen geprüft-
			open CLIENT, ">>", "$dbid.txt" or throwError("info","Die Datei eines Spielers konnte nicht beschrieben werden: $!");
			print CLIENT "$msg\n"; # Hier evtl noch Uhrzeit hineinschreiben
			close CLIENT;
			if ($msg eq $config{'default.loesung'}) {  # Wenn Lösung 1 eingegeben wurde
				SendPrivat($config{'default.send_win1'},$invokerid);
				&wincounter;
				setwinner(1, $dbid, $invokeruid, &wincounter, counterVersuche($dbid)); # Setzt den Gewinner um. Mode, Datenbankid, UID, welcher Platz er ist, und wie viele Versuche er gebraucht hat. 
			} elsif ($msg eq $config{'default.loesung2'} && !$config{'default.loesung2'} == 0) { # Wenn Lösung 2 eingegeben wurde, welche nicht 0 ist (0 = Disable)
                SendPrivat($config{'default.send_win2'},$invokerid);
				mkdir "winner/group2" or throwError("sigKill", "Ordner konnte nicht erstellt werden: $!");
				&wincounter;
				setwinner(2, $dbid, $invokeruid, &wincounter, counterVersuche($dbid));
			} else {
				SendPrivat("Leider falsch",$invokerid);
				goto next_line;
			}
		}
	} else {
		SendText ("Bereits auf der Liste, oder maximale Versuche erreicht."); 
		goto next_line;
	}	
}


sub createINI {  # void
	my $cfg = new Config::Simple (syntax => 'ini');
	$cfg->param("queryname", "serveradmin");
	$cfg->param("querypw", "1234567");
	$cfg->param("nickname", "Bot");
	$cfg->param("serverid", "1");
	$cfg->param("usechannelid", "1");
	$cfg->param("server_ip", "localhost");
	$cfg->param("queryport", "10011");
	$cfg->param("raetsel", "DeinText");
	$cfg->param("maxtrys", "0 #disable=0");
	$cfg->param("helptext", "DeinText");
	$cfg->param("loesung", "DeineLoesung");
	$cfg->param("loesung2", "0 #disable=0");
	$cfg->param("send_welcome", "Hi! Schreibe !play zum mitmachen, oder !help für Hilfe");
	$cfg->param("send_win1", "Du bist als Gewinner für Level 1 eingetragen");
	$cfg->param("send_win2", "Du bist als Gewinner für Level 2 eingetragen");
	$cfg->write("settings.ini");
	throwError("sigKill","INI Datei wurde erstellt. Bitte bearbeiten." ); # Beende..
}

# Erstellt alle benötigten Dateien abhängig davon, welcher Parameter übergeben wurde.
sub createData {
	my $mode = shift;
	
	# Wenn eine andere Zahl außer 1,2,3 übergeben wird, werden alle ausgeführt
	if ($mode != 2 && $mode != 3) { # bei 1
		open DATEI, ">","winners.txt" or throwError("critical",$!);
		close DATEI;	
	}
	if ($mode != 1 && $mode != 3) { # bei 2
		open DATEI, ">", "counter.txt" or throwError("critical",$!);;
		print DATEI "0";
		close DATEI;	
	}
	if ($mode != 2 && $mode != 1) { # bei 3
		mkdir "winner";
	}
	if ($mode == 0) { # bei 0
		open CREATE, ">", "running.txt" or throwError("critical",$!);
		print CREATE "If your remove this file, the Bot will overrite all other files";
	}
}

# Der Query Login in die ServerQuery vom Teamspeak Server. 
sub qlogin{
	my $line;
	$query = new Net::Telnet (Timeout => undef); 
	$query->open(Host => $config{'default.server_ip'}, 
				 Port => $config{'default.queryport'});
	$query->errmode( sub { sleep 0.1 } );
	sleep 0.5;
	CheckResult($query->getline(),"TS3","Verbindung zum Sever fehlgeschlagen!!"); # TS3 
	$query->getline();
	$query->print("login $config{'default.queryname'} $config{'default.querypw'}"); #login
	CheckResult($query->getline(),"error id=.*? msg=ok","Login fehlgeschlagen!!");
	$query->print("use $config{'default.serverid'}"); 
	CheckResult($query->getline(),"error id=.*? msg=ok","Use auf ServerID '$config{'default.serverid'}' fehlgeschlagen!!");
	$query->print("clientupdate client_nickname=$config{'default.nickname'}");  
	CheckResult($query->getline(),"error id=.*? msg=ok","Nickname 'config{'nickname'}' konnte nicht gesetzt werden!!");
	$query->print("whoami"); 
	$line= $query->getline(); 
	CheckResult($query->getline(),"error id=.*? msg=ok","Whoami fehlgeschlagen!!");
	$line =~ s/[\r\n\t]//gi;
	$line =~ s/= /# /gi;
	my %hash = split /[=\s]/, $line;
	$ownid = $hash{client_id}; #### ????
	$query->print("clientmove clid=$hash{client_id} cid=$config{'default.usechannelid'}"); # move own id to channel 
	CheckResult($query->getline(),"error id=.*? msg=(ok|alre)","Move fehlgeschlagen!!");
	$query->print("servernotifyregister id=$config{'default.usechannelid'} event=channel");  
	CheckResult($query->getline(),"error id=.*? msg=ok","NotifyRegister Textchannel fehlgeschlagen!!");
	$query->print("servernotifyregister event=textprivate");
	CheckResult($query->getline(),"error id=.*? msg=ok","NotifyRegister Textprivat fehlgeschlagen!!");
	$query->print("servernotifyregister event=textchannel");  
	CheckResult($query->getline(),"error id=.*? msg=ok","NotifyRegister Textchannel fehlgeschlagen!!");
	return $query;
}

# Prüft die Ausgaben
sub CheckResult{
	my $line =shift;
	my $check = shift;
	my $msg=shift;
	$line =~ s/\r\n\t//gi;
	
	if( $line =~ /$check/) {
		return;
	}
}

# Prüft ob die Person, welche übergeben wird, bereits einmal gewonnen hat. Gibt 1 oder 0 zurück
sub wincheck {
	my $idd = shift;
	my $daten = "";
	my $win = 0;
	if (!idd) {throwError("info", "ein Fehler ist aufgetreten");}

	open DATEI, "winners.txt" or &createData(1);
	while(<DATEI>){
		$daten = $daten.$_;
	}
	if ($daten =~ $idd) {
		$win=1;
	}
	close DATEI;
	return $win;
}

# Sucht sich die Datenbank ID heraus und gibt diese zurück. An dieser Stelle ist es möglich noch weitere Daten rauszufiltern!
sub clientInfo {
	my $invokerid = shift; # Lokale Variable!
	my $dbid; # Lokale Variable

	$query->print("clientinfo clid=$invokerid");
	my $check= $query->getline();
	CheckResult($query->getline(),"error id=.*? msg=ok","clientinfo fehlgeschlagen!!");
	my @line_values = split(" ",$check);
       foreach my $e (@line_values)
       {
		if ($e =~ /client_database_id=?/){
			$e =~ s/client_database_id=?//;
			$dbid = $e;
		}
	}
	if (!$dbid) {
		throwError("info","Datenbankid konnte nicht gefiltert werden!");
	}
	return $dbid;
}

# Zählt alle Versuche durch, die eine Person hatte und schreibt sie in eine Datei
sub counterVersuche {
	my $dbid = shift;
	my $versuche = 0;

	open DATEI, "$dbid.txt" or return 0; # Wenn die Person noch keine Versuche hatte, gehe zurück
	my @daten = <DATEI>;
	close (DATEI);
	$versuche = @daten; # Hier bleibt die Anzahl der Zeilen ürbig. Ist gleich der Anzahl der Versuche, da Versuche mit einem Zeilenumbruch getrennt sind
	return $versuche;
}

# Erhöht den Zähler der Gewinner um +1 und schreibt es in die counter.txt 
sub wincounter {
	open DATEI,"<" ,"counter.txt" or createData(2); # CreateData 2 erstellt Counter.txt
	my $counter=<DATEI>;
	close DATEI;
	$counter=$counter+1;
	open DATEI,">", "counter.txt" or throwError("sigKill","Counter.txt konnte nicht beschrieben werden: $!");
	print DATEI $counter;
	close DATEI;
	return $counter;
}

## !!!! Handlungsbedarf
# Setz den Gewinner in dem er seine Logdatei, in einen anderen Ordner verschiebt und dort Informationen einfügt.
sub setwinner {
	my $mode = shift; # Steht für die Lösung
	my $dbid = shift; 
	my $invokeruid = shift; 
	my $counter = shift;
	my $versuche = shift;

	open WINNER, ">>", "winners.txt" or throwError("sigKill", "Winners Datei konnte nicht beschrieben werden:$!");
    print WINNER "$invokeruid\n"; # Evtl noch Nickname einfügen
    close (WINNER);

	my $name="$dbid-$counter-$versuche";
	#print `mv  ./$dbid.txt ./winner/$name.txt`; # Depricated
	open CCC, ">>", "$dbid.txt" || throwError("sigKill", "DBID Datei konnte nicht beschrieben werden: $!");
        #open (CCC, ">>./winner/$name.txt") || die &create_data(3);
        print CCC "\n\n$invokeruid\n"; # Nickname einfügen
        close (CCC);

	if ($mode == 1) {
		move("./$dbid.txt","./winner/$name.txt"); ## Keine Fehlerbehandlung
	} elsif ($mode == 2) {
		move("./$dbid.txt","./winner/group2/$name.txt");
	}
}

# Sendet Text in den Channel mit gefiltertem Leerzeichen
sub SendText {
        my $out =shift;
        
        $out =~ s/ /\\s/gi;
        $query->print("sendtextmessage targetmode=2 msg=$out"); 
		# Antwort abgreifen
}

# Sendet eine Private Nachricht an eine bestimmte ID. 
sub SendPrivat {
        my $out =shift;
        my $iddd = shift;
        
        $out =~ s/ /\\s/gi;
        $query->print("sendtextmessage targetmode=1 target=$iddd msg=$out");
		# Antwort abgreifen
}

# Hier werden Fehler aufgefangen und können bearbeitet werden. 
sub throwError {
	my $errorType = shift; # definiert den Error Typ. Definiert sind "critical", "sigKill" und "info".
	my $errorMessage = shift; # Wird direkt weitergegeben
	
	warn "$errorType - Message: $errorMessage";
	if ($errorType eq "critical") {
		exit();
	} elsif ($errorType eq "sigKill") {
		SendText("Ein Fehler ist aufgetreten. Bitte informiere einen Admin");
		$gotError = 1; #Wird bei der nächsten Gegenheit abbrechen
	} elsif ($errorType eq "info") {
		SendText($errorMessage);
	}
}
