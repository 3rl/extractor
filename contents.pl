#!/usr/bin/perl
#
# Modified version of chaosreader0.94 by Fuad
# changelog - 17/01/2012:
# - add capability to output csv file
# - add/fix descriptions for documentation
# - and few tidbits
# 
# Original version by Brendan Gregg
# Licensed under GPLv2
#

 
#####################
# Modules that imported to this program:
# Getopt::Long for extended processing of command line options
# Benchmark to calculate running times of subroutines
# File::Basename for files operation
# URI for parsing uri scheme
use Getopt::Long;
use Benchmark;
use File::Basename;
use URI;

#####################
# --- Variables --- 
#

#
#  Some defaults
#
$PERL = "/usr/bin/perl";		# perl path for replay scripts
$integerSize = length(pack('I',0));	# can make a difference for tcpdumps
$the_date = scalar localtime();		# this is printed in the reports
$WRAP = 108;				# wordwrap chars
$BM = 0;				# benchmark counter
$| = 1;					# flush output

### variable to hold temporally url's value
$httpaddress = "http://example.net/";

#
#  The following is needed for old perl5 multiline matching. New perl5 uses
#  a "/s" on the RE (which is used in this program as well).
#
#$* = 1;					# old perl5

#
#  These ports have been selected to be saved as coloured 2-way HTML files
#
@Save_As_HTML_TCP_Ports = (21,23,25,79,80,109,110,119,143,513,514,1080,
 3128,4110,5000,5555,6660,6665,6666,6667,6668,7000,8000,8080,9000);
@Save_As_HTML_UDP_Ports = (53);

#
#  These ports have been selected to be saved as realtime playback scripts
#  (telnet, login, and numerous IRC ports)
#
@Save_As_TCP_Playback_Ports = (23,513,4110,5000,5555,6660,6666,6667,
 6668,7000,8000,9000);
@Save_As_UDP_Playback_Ports = (7);

#
#  These are the X11 ports to save as X11 playback scripts
#
@Save_As_X11_Playback_Ports = (6000,6001,6002,6003,6004,6005,6006,6007);

#
#  These X11 ports will have the text saved as coloured 2-way HTML files
#
@Save_As_HTML_X11_Ports = (6000,6001,6002,6003,6004,6005,6006,6007);

#
#  These are the VNC ports to save as VNC playback scripts
#
@Save_As_VNC_Playback_Ports = (5900,5901,5902,5903,5904,5905,5906,5907);


############################
# --- Arguments Handling ---
#
# directed to a function for process each argument
&Process_Command_Line_Arguments();

### Record program start  
$Bench{++$BM}{mark} = new Benchmark if $Arg{bench};
$Bench{$BM}{text} = "Program Start";

##########################################################
#  Load some lookup tables for number -> name translations
#
&Load_Etc_Services();
&Set_IP_Protocols();
&Set_ICMP_Types();
&Set_Result_Names();
&Set_X11_Codes();
&Set_X11_KeyCodes();
&Set_VNC_Codes();


###########################
# --- MODE 1 - Normal --- #
###########################

if ($Arg{normal}) {
	####################################
    # --- Normal - Process log files ---
    #
    
	#  Initial values
	#
	$frame = 0; $number = 0;
	%IP = (); %TCP = (); %UDP = (); %ICMP = (); %Count = (); %Hex = ();

	### Print version
	&Print_Welcome();

	######################################
	# --- INPUT - Read Packet Log(s) --- 
	#

	foreach $filename (@{$Arg{infiles}}) {
		#
		#  Check input file type and Open
		#
		&Open_Input_File($filename);

		#
		#  Read through the entire input file, saving all packet
		#  data in memory (mainly %TCP and %UDP).
		#
		&Read_Input_File();
	}


	#############################################
	# --- OUTPUT - Process TCP/UDP Sessions ---
	#

	### cd to output
	&Chdir($Arg{output_dir});
	&Print_Header2();

	### Determine Session and Stream time order
	%Index = (); %Image = (); %GETPOST = (); 
	&Sort_Index();

	#
	#  Initiate creating output.csv
	#
	open(FILECSV,">output.csv") || die "ERROR59: creating output.csv file: $!\n";
	print FILECSV "transport_protocol; apps_prot; src_ipaddr; src_port; dst_ipaddr; dst_port; url; directory; filename; network_prot;\n";
	close FILECSV;
	
	#
	#  Process %TCP and create session* output files, write %Index
	#
	&Process_TCP_Sessions();

	#
	#  Process %UDP and create session* output files, write %Index
	#
	&Process_UDP_Streams();

	#
	# Process %ICMP 
	#
	&Process_ICMP();

	#
	#  Create Index Files from %Index
	#
	&Create_Index_Files();
	&Create_Log_Files();

	###############
	# --- END ---
	#
	&Print_Footer1();
} 


###############################
# --- MODE 2 - Standalone --- #
###############################

elsif ($Arg{standalone}) {

   ############################################################
   # --- STANDALONE - Create Packet Logs and Process them ---
   #

   $limit = $Arg{count};
   $filenum = 0;

   ### Check for the sniffer command
   &Check_Command();

   ### cd to output
   &Chdir($Arg{output_dir});

   ### Print welcome
   &Print_Welcome();

   #
   #  MAIN LOOP
   #
   while ($limit != 0) {
	#
	#  Create a meaningful directory and filename
	#
	@Times = localtime();
	$dirname = sprintf("out_%d%02d%02d-%02d%02d",($Times[5]+1900),
	 $Times[4],$Times[3],$Times[2],$Times[1]);
	$filename = "$dirname.log";

	#
	#  Initial values
	#
	$frame = 0; $number = 0;
	%IP = (); %TCP = (); %UDP = (); %ICMP = (); %Count = (); %Hex = ();

	#
	#  Record details in a Master Index
	#
	$Master[$filenum]{starttime} = scalar localtime();
	$Master[$filenum]{duration} = - time();			# will +end time
	$Master[$filenum]{dir} = $dirname;
	$Master[$filenum]{file} = $filename;

	#
	#  Create and cd to output dir
	# 
	mkdir ("$dirname",0755) || die "ERROR01: Couldn't mkdir (perms?): $!\n";
	chdir "$dirname" || die "ERROR02: Couldn't cd $dirname: $!\n";

	print "\nCreating log: $dirname/$filename\n" unless $Arg{quiet};

	#	
	#  fork, so that one process can exec tcpdump/snoop while the other 
	#  sleeps and then kills it.
	#
	$pid = fork();
	die "ERROR03: Can't fork (resources?): $!\n" if (! defined $pid);

	if ($pid == 0) {
		###############################
		# --- CREATE - Packet Log ---
		#

		print "Running: $command $filename $Arg{filter}\n"
		 unless $Arg{quiet};
		### exec, so $pid points to sniffer
		exec("$command $filename $Arg{filter}") && 
			die "ERROR04: couldn't run $command file: $!\n";
	} else {
		### Wait for logfile to be populated
		sleep($Arg{mins} * 60);

		### Kill child (TERM, INT)
		kill 15, $pid;
		kill 2, $pid;
	}
	exit if $pid == 0;	# check for impossibility


	### Record end time, duration, size
	$Master[$filenum]{endtime} = scalar localtime();
	$Master[$filenum]{duration} += time();
	# finish writing the log before reading it's size
	system("sync") if (($^O eq "linux") || ($^O eq "solaris"));
	$Master[$filenum]{size} = -s "$filename";

	print "\nProcessing:   $dirname/$filename\n" unless $Arg{quiet};
	$bak = $Arg{quiet}; $Arg{quiet} = 1;

	###############################
	# --- INPUT - Process Log ---
	#
	&Open_Input_File($filename);

	### Populate memory (%TCP, %UDP, ...).
	&Read_Input_File();

	#############################################
	# --- OUTPUT - Process TCP/UDP Sessions ---
	#

	### Determine Session and Stream time order
	%Index = (); %Image = (); %GETPOST = (); 
	&Sort_Index();

	### Process %TCP, %UDP, ..., create output fies, write %Index
	&Process_TCP_Sessions();
	&Process_UDP_Streams();
	&Process_ICMP();

	### Create Index Files from %Index
	&Create_Index_Files();
	&Create_Log_Files();


	chdir ".." || die "ERROR05: Couldn't cd ..: $!\n";

	$Arg{quiet} = $bak;

	### Create Master Index from @Master
	&Create_Index_Master();

	$limit--;
	$filenum++;
   }

} 


###########################
## --- MODE 3 - Redo  --- #
###########################

elsif ($Arg{redo}) {

   #############################################################
   # --- STANDALONE REDO - Redo last run from sniffer logs ---
   #

   $filenum = 0;

   ### Read index.file for logs to process
   &Load_Index_File();

   ### Print welcome
   &Print_Welcome();

   #
   #  MAIN LOOP
   #
   for ($index=0; $index <= $#Master; $index++) {

	### Get previous run values
	$dirname = $Master[$index]{dir};
	$filename = $Master[$index]{file};

	### Initial values
	$frame = 0; $number = 0;
	%IP = (); %TCP = (); %UDP = (); %ICMP = (); %Count = (); %Hex = ();

	### Create and cd to output dir
	chdir "$dirname" || die "ERROR06: Couldn't cd $dirname: $!\n";

	print "Processing:   $dirname/$filename\n" unless $Arg{quiet};
	$bak = $Arg{quiet}; $Arg{quiet} = 1;

	###############################
	# --- INPUT - Process Log ---
	#
	&Open_Input_File($filename);

	### Populate memory (%TCP, %UDP, ...).
	&Read_Input_File();

	#############################################
	# --- OUTPUT - Process TCP/UDP Sessions ---
	#

	### Determine Session and Stream time order
	%Index = (); %Image = (); %GETPOST = (); 
	&Sort_Index();

	### Process %TCP, %UDP, ..., create output fies, write %Index
	&Process_TCP_Sessions();
	&Process_UDP_Streams();
	&Process_ICMP();

	### Create Index Files from %Index
	&Create_Index_Files();
	&Create_Log_Files();

	chdir ".." || die "ERROR07: Couldn't cd ..: $!\n";
	$Arg{quiet} = $bak;

	$limit--;
	$filenum++;
   }
   ### Create Master Index from @Master
   &Create_Index_Master();
}


#
#  BENCHMARK REPORT
#
if ($Arg{bench}) {
	$Bench{++$BM}{mark} = new Benchmark;
	$Bench{$BM}{text} = "Program End";

	print "\nBenchmarks,\n\n";
	for ($bm=1; $bm <= $BM; $bm++) {
		$bdiff = timediff($Bench{$bm}{mark},$Bench{1}{mark});
		printf(" %-32s %s\n",$Bench{$bm}{text},timestr($bdiff));
	}
}


#####################
# --- SUBROUTINES ---
# (Most of these subroutines are used as shortcuts to code, not traditional 
#  scoped subroutines as with other languages)



# Open_Input_File - open the packet log specified. This checks the header
#	of the file to determine whether it is a tcpdump/libpcap or snoop
#	log (including several styles of tcpdump/libpcap). #1
#

sub Open_Input_File {
    #debug
    print "\n Open_Input_File subroutine called \n" unless $Arg{quiet};

	my $infile = shift;
	my ($length,$size);

	$Bench{++$BM}{mark} = new Benchmark if $Arg{bench};
	$Bench{$BM}{text} = "Open Input File";

	print "Opening, $infile\n\n" unless $Arg{quiet};

	#
	#  Open packet log
	#
	open(INFILE,$infile) || die "Can't open $infile: $!\n";
	binmode(INFILE);	# for backward OSs
	
	#
	#  Fetch header
	#
	$length = read(INFILE,$header,8);
	die "ERROR08: Can't read from $infile\n" if $length < 8;

	### Print status
	print "Reading file contents,\n" unless $Arg{quiet};
	$SIZE = -s $infile;

	#
	#  Try to determine if this is a tcpdump or a snoop file
	#
	($ident) = unpack('a8',$header);

	if ($ident =~ /^\241\262\303\324|^\324\303\262\241/ ||
		 $ident =~ /^\241\262\315\064|^\064\315\262\241/) {

		$TYPE = "tcpdump";
		$ident = unpack('a4',$header);  # try again
		# standard/modified defines style, 1/2 defines endian
		if ($ident =~ /^\241\262\303\324/) { $STYLE = "standard1"; }
		if ($ident =~ /^\324\303\262\241/) { $STYLE = "standard2"; }
		if ($ident =~ /^\241\262\315\064/) { $STYLE = "modified1"; }
		if ($ident =~ /^\064\315\262\241/) { $STYLE = "modified2"; }
		if ($STYLE =~ /1$/) {
			# reread in big-endian
			($ident,$major,$minor) = unpack('a4nn',$header); 
		} else {
			# reread in little-endian
			($ident,$major,$minor) = unpack('a4vv',$header); 
		}

		#
		#  Check tcpdump header carefully to ensure this is ver 2.4.
		#
		if ($major != 2 && $minor != 4) {
			#
			#  Die if this is an unknown version. (there could
			#  be new vers of tcpdump/libpcap in the future).
			#
			print STDERR "ERROR09: Wrong tcpdump version ";
			print STDERR "($version.$type).\n(expected 2.4).\n";
			exit 1;
		}
		#
		#  Nudge the filehandle past the rest of the header...
		#
		$length = read(INFILE,$header_rest,16);
	
	}
	elsif ($ident =~ /^snoop/) {
	
		$TYPE = "snoop";
		$length = read(INFILE,$header,8);
		($version,$type) = unpack('NN',$header);
	}
	else {
		#
		#  Die - unknown file format
		#
		print STDERR "ERROR10: Input dosen't look like a tcpdump or ";
		print STDERR "snoop output file.\n\tIf it is tcpdump, it ";
		print STDERR "may be a wrong or new version.\n";
		exit 1;
	}

	### Record the filename into the global %Arg
	$Arg{infile} = $infile;
}



# Read_Input_File - this subroutine loops through the records in the packet 
#  log, storing all the TCP and UDP data into %TCP and %UDP. (see the end 
#  of the program for the structure of these data types). %Count is also
#  populated with various frequency counts. #2
#
sub Read_Input_File {
   #debug
   print "\n Read_Input_File subroutine called \n" unless $Arg{quiet};

   my ($trailers,$pppoe_verNtype,$pppoe_code,$pppoe_id,$pppoe_length,
    $ppp_protocol,$wless_fc,$wless_version,$wless_type,$wless_duration,
    $wless_subtype,$wless_from,$wless_to,$wless_flag,$wless_WEP,
    $wless_bss,$wless_src,$wless_dest,$wless_cksum,$llc_head,$llc_control,
    $llc_org,$llc_type,$wless_OK,$bytes,$counter,$packets);

   $Bench{++$BM}{mark} = new Benchmark if $Arg{bench};
   $Bench{$BM}{text} = "Read Input File - start";

   local $packet = 0;			# counter
   if ($TYPE eq "snoop") {
   	$bytes = 16;
   } else {
	$bytes = 24;
   }

   ###############################################
   # --- Phase #1, Store IP data in memory (%IP) --
   #
   while (1) {
	#
	# --- Read Record from Log ---
	#
	if ($TYPE eq "snoop") {
		&Read_Snoop_Record();		# will "last" on error
		$packet_data = $snoop_data;
		$packet_time = $snoop_seconds;
		$packet_timefull = $snoop_seconds + $snoop_msecs/1000000;
		$record_size = $snoop_length_rec;
	} else {
		&Read_Tcpdump_Record();		# will "last" on error
		$packet_data = $tcpdump_data;
		$packet_time = $tcpdump_seconds;
		$packet_timefull = $tcpdump_seconds + $tcpdump_msecs/1000000;
		$record_size = $tcpdump_length + ($integerSize * 2 + 8);
	}

	### Print status summary
	unless ($Arg{quiet}) {
		$bytes += $record_size;
		if (($packet % 16) == 0) {
			printf("%s %2.0f%% (%d/%d)","\b"x24,
			 (100*$bytes/$SIZE),$bytes,$SIZE);
		}
	}

	#
	# --- Parse TCP/IP layers (a little ;) ---
	#

	#-------------------------------------------------------------------
	#
	#  Wireless, 802.11b
	#

	$decoded = 0;		# this flag is true if wireless was found

	# unpack a little first, (efficiency)
	($wless_fc) = unpack('H4',$packet_data);

	# this matches on possible send or receive wireless traffic, however
	# this could also be the start of an 802.3 frame - making this part
	# of a MAC address. (The IEEE list on OUIs had these as unassigned).
	if ($wless_fc =~ /^080[1256]/) {
		# now dig deeper,
		# (this is one form of 802.11 - the form we are interested 
		# in, however note that there is a lot more to 802.11).
		($wless_fc,$wless_duration,$wless_bss,$wless_src,
		 $wless_dest,$wless_cksum,$llc_head,$llc_control,$llc_org,
		 $llc_type,$ether_data) 
		 = unpack('nnH12H12H12na2CH6H4a*',$packet_data);
	
		$wless_to = $wless_fc & 1;

		# Check this is IP and encapsulated Ethernet,
		if (($llc_type eq "0800") && ($llc_org eq "000000")) {

		   ### Populate ether variables for use later on
		   $ether_type = $llc_type;
		   if ($wless_to) {
			$ether_dest = $wless_dest;
			$ether_src = $wless_src;
		   } else {
			$ether_dest = $wless_src;
			$ether_src = $wless_dest;
		   }

		   $decoded = 1;	# remember we did this
		}
		# (else try redecoding this using 802.3)
	}

	#-------------------------------------------------------------------
	#
	#  Tun device
	#

	# unpack a little first, (efficiency)
	($tun_id) = unpack('H8',$packet_data);

	# this checks if the frame looks like a tun device frame
	if ($tun_id eq "02000000") {
		# now dig deeper,
		($tun_id,$ether_data) = unpack('a4a*',$packet_data);
		$ether_src = "0";
		$ether_dest = "0";
		$ether_type = "0800";

		$decoded = 1;		# remember we did this
	}

	#-------------------------------------------------------------------
	#
	#  Ethernet, 802.3
	#

	### Unpack ether data
	($ether_dest,$ether_src,$ether_type,$ether_data) =
	 unpack('H12H12H4a*',$packet_data) unless $decoded;

	### Count ether types seen
	$Count{EtherType}{$ether_type}++;
	$CountMaster{EtherType}{$ether_type}++;
	
	#
	#  Process extended Ethernet types (wireless, PPPoE)
	#

	### PPPoE
	if ($ether_type eq "8864") {
		($pppoe_verNtype,$pppoe_code,$pppoe_id,$pppoe_length,
		 $ppp_protocol,$ether_data) = unpack("CCnnna*",$ether_data);
		
		### Skip anything but data (we just want data - code 0)
		next if $pppoe_code != 0;

		# (May like to add code here later to process $ppp_protocol,
		# eg, to process LCP).
	}

	elsif (($ether_type ne "0800") && ($ether_type ne "86dd")) {
		next;
	}

	#-------------------------------------------------------------------
	#
	#  IP
	#
	
	### Check for IP ver
	($ip_verNihl,$ip_rest) = unpack('Ca*',$ether_data);
	$ip_ver = $ip_verNihl & 240;
	$ip_ver = $ip_ver >> 4;

	if ($ip_ver == 4) {

		#-----------------------------------------------------------
		#
		#  IPv4
		#

		### Unpack IP data
		($ip_verNihl,$ip_tos,$ip_length,$ip_ident,$ip_flagNfrag,
		 $ip_ttl,$ip_protocol,$ip_checksum,@ip_src[0..3],
		 @ip_dest[0..3],$ip_data) = unpack('CCnnnCCa2CCCCCCCCa*',
		 $ether_data);

		### Get frag and flag data
		$ip_frag = $ip_flagNfrag & 8191;
		$ip_flag = $ip_flagNfrag & 57344;
		$ip_flag = $ip_flag >> 13;
		$ip_MF = $ip_flag & 1;

		### Strip off IP options if present
		$ip_ihl = $ip_verNihl & 15;
		$ip_ihl = $ip_ihl << 2;
		$ip_options_num = $ip_ihl - 20;
		if ($ip_options_num > 0) {
			($ip_options,$ip_data) = 
			 unpack("a${ip_options_num}a*",$ip_data);
		}

		### Strip off Ethernet trailers
		$ip_dlength = $ip_length - $ip_options_num - 20;
		($ip_data,$trailers) = unpack("a${ip_dlength}a*",$ip_data);

		### Build text strings of IP addresses
		$ip_src = sprintf("%u.%u.%u.%u",@ip_src);
		$ip_dest = sprintf("%u.%u.%u.%u",@ip_dest);

	} elsif ($ip_ver == 6) {

		#-----------------------------------------------------------
		#
		#  IPv6
		#
		($ip_verNihl,$ip_flow,$ip_length,$ip_next,$ip_hop,
		 @ip_src[0..15],@ip_dest[0..15],$ip_data) = 
		 unpack('Ca3nCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCa*',
		 $ether_data);
		$ip_protocol = $ip_next;

		### Build text strings of IP addresses
		$ip_src = sprintf("%x%x:%x%x:%x%x:%x%x:%x%x:%x%x:%x%x:%x%x",
		 @ip_src);
		$ip_dest = sprintf("%x%x:%x%x:%x%x:%x%x:%x%x:%x%x:%x%x:%x%x",
		 @ip_dest);
	
		### Compress IPv6 text Address
		$ip_src =~ s/:00:/:0:/g;
		$ip_src =~ s/:00:/:0:/g;
		$ip_dest =~ s/:00:/:0:/g;
		$ip_dest =~ s/:00:/:0:/g;
		$ip_src =~ s/(:0)+/::/;
		$ip_dest =~ s/(:0)+/::/;


		#
		#  Check for IPv6 Fragmentation (embedded)
		#
		if ($ip_protocol == 44) {
			($ip_next,$ip_reserved,$ip_fragNmf,$ip_ident,$ip_data)
			 = unpack('CCnNa*',$ip_data);
			 $ip_protocol = $ip_next;
			$ip_MF = $ip_fragNmf & 1;
			$ip_frag = $ip_fragNmf >> 3;
		} else {
			$ip_MF = 0;
			$ip_ident = 0;
			$ip_frag = 0;
		}
		
	} else {
		### Not IPv4 or IPv6 - could be LCP (skip for now)
		next;
	}

	### Count IP Protocols seen
	$Count{IPprotocol}{$ip_protocol}++;
	$CountMaster{IPprotocol}{$ip_protocol}++;

	### Count IP Addresses seen
	$Count{IP}{$ip_src}++;
	$CountMaster{IP}{$ip_src}++;

	### Generate unique IP id (not just the ident)
	$ip_id = &Generate_IP_ID($ip_src,$ip_dest,$ip_ident);
	
	#
	#  Store IP data in %IP so we can do frag reassembly next
	#
	if (! defined $IP{id}{$ip_id}{StartTime}) {
		$IP{time}{$packet_timefull}{ver} = $ip_ver;
		$IP{time}{$packet_timefull}{src} = $ip_src;
		$IP{time}{$packet_timefull}{dest} = $ip_dest;
		$IP{time}{$packet_timefull}{protocol} = $ip_protocol;
		$IP{time}{$packet_timefull}{frag}{$ip_frag} = $ip_data;
		if ($snoop_drops || $tcpdump_drops) {
			$IP{time}{$packet_timefull}{drops} = 1;
		}
		#
		#  If there are more fragments, remember this starttime
		#
		unless (($ip_MF == 0) && ($ip_frag == 0)) {
			$IP{id}{$ip_id}{StartTime} = $packet_timefull;
		}
		if (($ip_MF == 1) || ($ip_frag > 0)) {
			$IP{time}{$packet_timefull}{fragged} = 1;
		}
	} else {
		$start_time = $IP{id}{$ip_id}{StartTime};
		$IP{time}{$start_time}{frag}{$ip_frag} = $ip_data;
		if ($snoop_drops || $tcpdump_drops) {
			$IP{time}{$packet_timefull}{drops} = 1;
		}
		if ($ip_MF == 0) {
			#
			#  Comlpete this IP packet. This assumes that the
			#  last frag arrives last.
			#
			undef $IP{ident}{StartTime}{$ip_id};
		}
	}
	$packet++;
   }

   close INFILE;

   ### Print status summary
   unless ($Arg{quiet}) {
	printf("%s %2.0f%% (%d/%d)","\b"x24,
	 100,$bytes,$SIZE);
	print "\nReassembling packets,\n";
   }



   ###################################################################
   #  --- Phase #2, Reassemble IP data in %IP; create %TCP and %UDP ---
   #
   
   &Print_Header1() if $Arg{debug};
   $packets = $packet;
   $packet = 0;
   @Times = sort { $a <=> $b } ( keys(%{$IP{time}}) );
   foreach $time (@Times) {
	
	### Print status summary
	unless ($Arg{quiet}) {
		if (($packet % 16) == 0) {
			printf("%s %2.0f%% (%d/%d)","\b"x32,
			 (100*$packet/$packets),$packet,$packets);
		}
	}

	#
	#  Get IP data from %IP
	#
	$ip_ver = $IP{time}{$time}{ver};
	$ip_src = $IP{time}{$time}{src};
	$ip_dest = $IP{time}{$time}{dest};
	$ip_protocol = $IP{time}{$time}{protocol};
	$drops = $IP{time}{$time}{drops};
	undef $ip_data;

	#
	#  Reassemble IP frags
	#
	if (defined $IP{time}{$time}{fragged}) {
		@IP_Frags = sort {$a <=> $b} (keys(%{$IP{time}{$time}{frag}}));

		### If never recieved the start of the packet, skip
		if ($IP_Frags[0] != 0) { next; }

		foreach $ip_frag (@IP_Frags) {
			$ip_data .= $IP{time}{$time}{frag}{$ip_frag};
		}
	} else {
		$ip_data = $IP{time}{$time}{frag}{0};
	}
	$length = length($ip_data);

	#
	# --- UDP ---
	#
	if ($ip_protocol == 17 && $Arg{output_UDP}) {
		&Process_UDP_Packet($ip_data,$ip_src,$ip_dest,$time,$drops);
	}

	#
	# --- TCP ---
	#
	if ($ip_protocol == 6 && $Arg{output_TCP}) {
		&Process_TCP_Packet($ip_data,$ip_src,$ip_dest,$time,$drops);
	}

	#
	# --- ICMP ---
	#
	if ($ip_protocol == 1 && $Arg{output_ICMP}) {
		&Process_ICMP_Packet($ip_data,$ip_src,$ip_dest,$time,$drops,
		 "ICMP");
	}

	#
	# --- ICMPv6 ---
	#
	if ($ip_protocol == 58 && $Arg{output_ICMP}) {
		&Process_ICMP_Packet($ip_data,$ip_src,$ip_dest,$time,$drops,
		 "ICMPv6");
	}

	#
	#  Skip packet if it isn't TCP (protocol = 6). (Will add routines for
	#  ICMP, ARP, RARP later on)...
	#

	$packet++;

	### Memory Cleanup
	delete $IP{time}{$time};

   }

   ### Memory Cleanup
   undef %IP;

   ### Print status summary
   unless ($Arg{quiet}) {
	printf("%s %2.0f%% (%d/%d)\n","\b"x24,
	 100,$packet,$packets);
   }

   $Bench{++$BM}{mark} = new Benchmark if $Arg{bench};
   $Bench{$BM}{text} = "Read Input File - end";
}



# Process_TCP_Packet - process a TCP packet and store it in memory. It takes
#	the raw ip data and populates the data structure %TCP. (and %Count). #3
#
sub Process_TCP_Packet {
    #debug
    print "\n Process_TCP_Packet subroutine called \n" unless $Arg{quiet};

	my $ip_data = shift;
	my $ip_src = shift;
	my $ip_dest = shift;
	my $time = shift;
	my $drops = shift;
	my $copy;

	#-------------------------------------------------------------------
	#
	#  TCP
	#

	### Unpack TCP data
	($tcp_src_port,$tcp_dest_port,$tcp_seq,$tcp_ack,$tcp_offset,$tcp_flags,
	 $tcp_header_rest,$tcp_data) = unpack('nnNNCCa6a*',$ip_data);

	### Strip off TCP options, if present
	$tcp_offset = $tcp_offset >> 4;		# chuck out reserved bits
	$tcp_offset = $tcp_offset << 2;		# now times by 4
	$tcp_options_num = $tcp_offset - 20;
	if ($tcp_options_num > 0) {
		($tcp_options,$tcp_data) = 
		 unpack("a${tcp_options_num}a*",$tcp_data);
	}

	### Fetch length and FIN,RST flags
	$tcp_length_data = length($tcp_data);
	$tcp_fin = $tcp_flags & 1;
	$tcp_syn = $tcp_flags & 2;
	$tcp_rst = $tcp_flags & 4;
	$tcp_ack = $tcp_flags & 16;

	$copy = $tcp_data;

	#
	#  Generate $session_id as a unique id for this stream
	#  (this is built from host:port,host:port - sorting on port).
	#
	($session_id,$from_server) = &Generate_SessionID($ip_src,$tcp_src_port,
	 $ip_dest,$tcp_dest_port,"TCP");

	### Record direction if single SYN was seen
	if ($tcp_syn && ! $tcp_ack) {
		$TCP{id}{$session_id}{source} = $ip_src;
		# better repeat this,
		($session_id,$from_server) = &Generate_SessionID($ip_src,
		 $tcp_src_port,$ip_dest,$tcp_dest_port,"TCP");
	}

	### Count TCP Ports seen
	if ($from_server) {
		$Count{TCPport}{$tcp_src_port}++;
		$CountMaster{TCPport}{$tcp_src_port}++;
	} else {
		$Count{TCPport}{$tcp_dest_port}++;
		$CountMaster{TCPport}{$tcp_dest_port}++;
	}

	#
	#  Flag this session as a Partial if either tcpdump or snoop
	#  confesses to dropping packets.
	# 
	$TCP{id}{$session_id}{Partial}++ if $drops;

	### Store size
	$TCP{id}{$session_id}{size} += length($tcp_data);

	### Store the packet timestamp for the first seen packet
	if (! defined $TCP{id}{$session_id}{StartTime}) {
		$TCP{id}{$session_id}{StartTime} = $time;

		### Store other info once
		if ($from_server) {
			$TCP{id}{$session_id}{src} = $ip_dest;
			$TCP{id}{$session_id}{dest} = $ip_src;
			$TCP{id}{$session_id}{src_port} = $tcp_dest_port;
			$TCP{id}{$session_id}{dest_port} = $tcp_src_port;
		} else {
			$TCP{id}{$session_id}{src} = $ip_src;
			$TCP{id}{$session_id}{dest} = $ip_dest;
			$TCP{id}{$session_id}{src_port} = $tcp_src_port;
			$TCP{id}{$session_id}{dest_port} = $tcp_dest_port;
		}
	}

	### Store the packet timestamp in case this is the last packet
	$TCP{id}{$session_id}{EndTime} = $time;

	### Print status line
	printf "%6s  %-45s  %s\n",$packet,$session_id,$length
	 if $Arg{debug};


	#
	# --- Store Session Data in Memory ---
	#
	# Since TCP is usually the bulk of the data, we minimise 
	# the number of copies of data in memory. UDP and ICMP
	# are handled differently.

	if ($from_server) {
		#
		#  Populate %TCP{id}{}{time} with raw traffic by time.
		#  This is the master structure to store the data.
		#
		$TCP{id}{$session_id}{time}{$time}{data} .= $tcp_data;
		$TCP{id}{$session_id}{time}{$time}{dir} .= "A";

		#
		#
		#  Populate %TCP{id}{}{Aseq} with server to client 
		#  1-way raw traffic, with the TCP sequence number as
		#  the key (for future reassembly). 
		#
		#  This is a pointer to the time structure above,
		#  to save on memory used (originally stored a 
		#  duplicate copy of the data).
		#
		if ((! defined $TCP{id}{$session_id}{Aseq}{$tcp_seq}) ||
		 (length(${$TCP{id}{$session_id}{Aseq}{$tcp_seq}}) < 
		 length($tcp_data))) {
			$TCP{id}{$session_id}{Aseq}{$tcp_seq} =
			 \$TCP{id}{$session_id}{time}{$time}{data};
		} 

		#
		#  Populate %Hex{TCP}{} with coloured HTML 2-way
		#  traffic, if needed.
		#
		if ($Arg{output_hex}) {
			&Process_Hex("TCP",$session_id,$tcp_data,"blue");
		}

	   } else {
		#
		#  Populate %TCP{id}{}{Btime} with raw 1-way traffic by time.
		#  This is the master structure to store the data.
		#
		$TCP{id}{$session_id}{time}{$time}{data} .= $tcp_data;
		$TCP{id}{$session_id}{time}{$time}{dir} .= "B";

		#
		#
		#  Populate %TCP{id}{}{Bseq} with client to server 
		#  1-way raw traffic, with the TCP sequence number as 
		#  the key (for future reassembly).
		#
		#  This is a pointer to the time structure above,
		#  to save on memory used (originally stored a 
		#  duplicate copy of the data).
		#
		if ((! defined $TCP{id}{$session_id}{Bseq}{$tcp_seq}) ||
		 (length(${$TCP{id}{$session_id}{Bseq}{$tcp_seq}}) < 
		 length($tcp_data))) {
			$TCP{id}{$session_id}{Bseq}{$tcp_seq} =
			 \$TCP{id}{$session_id}{time}{$time}{data};
		}

		#
		#  Populate %Hex{TCP}{} with coloured HTML 2-way
		#  traffic, if needed.
		#
		if ($Arg{output_hex}) {
			&Process_Hex("TCP",$session_id,$tcp_data,"red");
		}

	}

}



# Process_UDP_Packet - process a UDP packet and store it in memory. It takes
#	the raw ip data and populates the data structure %UDP. #4
#
sub Process_UDP_Packet {
    #debug
    print "\n Process_UDP_Packet subroutine called \n" unless $Arg{quiet};

	my $ip_data = shift;
	my $ip_src = shift;
	my $ip_dest = shift;
	my $time = shift;
	my $drops = shift;
	my $copy;

	#-------------------------------------------------------------------
	#
	#  UDP
	#

	### Unpack UDP data
	($udp_src_port,$udp_dest_port,$udp_length,$udp_checksum,
	 $udp_data) = unpack('nnnna*',$ip_data);

	#
	#  Generate $session_id as a unique id for this stream
	#  (this is built from host:port,host:port - sorting on port).
	#
	($session_id,$from_server) = &Generate_SessionID($ip_src,$udp_src_port,
	 $ip_dest,$udp_dest_port,"UDP");

	#
	#  Flag this session as a Partial if either tcpdump or snoop
	#  confesses to dropping packets.
	# 
	$UDP{id}{$session_id}{Partial}++ if $drops;

	### Store size
	$UDP{id}{$session_id}{size} += length($udp_data);

	### Count UDP ports seen
	if ($from_server) {
		$Count{UDPport}{$udp_src_port}++;
		$CountMaster{UDPport}{$udp_src_port}++;
	} else {
		$Count{UDPport}{$udp_dest_port}++;
		$CountMaster{UDPport}{$udp_dest_port}++;
	}

	#
	# --- Store Stream Data in Memory ---
	#

	if ($from_server) {
		#
		#  Populate %UDP{id}{}{RawA} with server to client 
		#  1-way raw traffic
		#
		$UDP{id}{$session_id}{RawA} .= $udp_data;	

		#
		#  Populate %UDP{id}{}{BothHTML} with coloured HTML 
		#  2-way traffic, blue for server to client
		#
		$copy = &Desex_HTML($udp_data);
		$UDP{id}{$session_id}{BothHTML} .= 
			"<font color=\"blue\">$copy</font>";

		#
		#  Populate %Hex{UDP}{} with coloured HTML 2-way
		#  traffic, if needed.
		#
		if ($Arg{output_hex}) {
			&Process_Hex("UDP",$session_id,$udp_data,"blue");
		}

	} else {
		#
		#  Populate %UDP{id}{}{RawB} with client to server 
		#  1-way raw traffic
		#
		$UDP{id}{$session_id}{RawB} .= $udp_data;	

		#
		#  Populate %UDP{id}{}{BothHTML} with coloured HTML 
		#  2-way traffic, red for client to server
		#
		$copy = &Desex_HTML($udp_data);
		$UDP{id}{$session_id}{BothHTML} .= 
			"<font color=\"red\">$copy</font>";
		#
		#  Populate %Hex{UDP}{} with coloured HTML 2-way
		#  traffic, if needed.
		#
		if ($Arg{output_hex}) {
			&Process_Hex("UDP",$session_id,$udp_data,"red");
		}

	}
	#
	#  Populate %UDP{id}{}{time}{} with raw 1-way traffic by time
	#
	$UDP{id}{$session_id}{time}{$time} .= $udp_data;

	### Store the packet timestamp for the first seen packet
	if (! defined $UDP{id}{$session_id}{StartTime}) {
		$UDP{id}{$session_id}{StartTime} = $time;

		### Store other info once
		if ($from_server) {
			$UDP{id}{$session_id}{src} = $ip_dest;
			$UDP{id}{$session_id}{dest} = $ip_src;
			$UDP{id}{$session_id}{src_port} = $udp_dest_port;
			$UDP{id}{$session_id}{dest_port} = $udp_src_port;
		} else {
			$UDP{id}{$session_id}{src} = $ip_src;
			$UDP{id}{$session_id}{dest} = $ip_dest;
			$UDP{id}{$session_id}{src_port} = $udp_src_port;
			$UDP{id}{$session_id}{dest_port} = $udp_dest_port;
		}
	}

	### Store the packet timestamp in case this is the last packet
	$UDP{id}{$session_id}{EndTime} = $time;

	### Print status line
	printf "%6s  %-45s  %s\n",$packet,$session_id,$length
	 if $Arg{debug};
	
}



# Process_ICMP_Packet - process a ICMP packet and store it in memory. It takes
#	the raw ip data and populates the data structure %ICMP. #5
#	time is the session_id.
#
sub Process_ICMP_Packet {
    #debug
    print "\n Process_ICMP_Packet subroutine called \n" unless $Arg{quiet};

	my $ip_data = shift;
	my $ip_src = shift;
	my $ip_dest = shift;
	my $time = shift;
	my $drops = shift;
	my $ver = shift;

	#-------------------------------------------------------------------
	#
	#  ICMP
	#

	### Unpack ICMP data
	($icmp_type,$icmp_code,$icmp_cksum,$icmp_rest) =
	 unpack('CCna*',$ip_data);

	#
	# --- Store ICMP data in memory ---
	#

	### Store Fields
	$ICMP{time}{$time}{type} = $icmp_type;
	$ICMP{time}{$time}{code} = $icmp_code;
	$ICMP{time}{$time}{src} = $ip_src;
	$ICMP{time}{$time}{dest} = $ip_dest;
	$ICMP{time}{$time}{ver} = $ver;

	#
	#  Flag this session as a Partial if either tcpdump or snoop
	#  confesses to dropping packets.
	# 
	$ICMP{time}{$time}{Partial}++ if $drops;

	#
	#  Save data if ICMP echo/reply
	#
	if (($icmp_type == 0) || ($icmp_type == 8) ||
	 ($icmp_type == 128) || ($icmp_type == 129) || 1) {
		### Unpack some more
		($icmp_type,$icmp_code,$icmp_cksum,$icmp_id,$icmp_seq,
		 $icmp_data) = unpack('CCnnna*',$ip_data);
		### Save extra fields
		$ICMP{time}{$time}{id} = $icmp_id;
		$ICMP{time}{$time}{seq} = $icmp_seq;
		$ICMP{time}{$time}{data} = $icmp_data;
	}

	### Store size
	$ICMP{time}{$time}{size} += length($icmp_data);

	if ($icmp_data ne "") {
		#
		#  Populate %ICMP{time}{}{BothHTML} with coloured HTML 
		#  1-way traffic, blue
		#
		$copy = &Desex_HTML($icmp_data);
		$ICMP{time}{$time}{BothHTML} .= 
			"<font color=\"blue\">$copy</font>";
	}

	#
	#  Populate %Hex{ICMP}{} with coloured HTML 
	#  traffic, if needed.
	#
	if ($Arg{output_hex}) {
		&Process_Hex("ICMP",$time,$icmp_data,"blue");
	}

	### Print status line
	printf "%6s  %-45s  %s\n",$packet,"$ip_src,$ip_dest",$length
	 if $Arg{debug};
}



# Process_TCP_Sessions - this subroutine processes %TCP, saving the 
# 	sessions to various "session*" files on disk. It populates %Index 
#	with information on files that it has created. It also checks
#	the application port numbers and triggers further processing - 
#	eg telnet replay files. Min/Max size checks are also done here. #6
#
sub Process_TCP_Sessions {
   #debug
   print "\n Process_TCP_Sessions subroutine called \n" unless $Arg{quiet};

   my ($randomid,$rawdir,$dirname,$filename,$id_text,$id_html,$rawboth,$time,$raw,$uri);
   my @Time;
   my @chars = ( "A" .. "Z", "a" .. "z", 0 .. 9 );

   $Bench{++$BM}{mark} = new Benchmark if $Arg{bench};
   $Bench{$BM}{text} = "Process TCP Sessions - start";

   #
   #  Loop through all TCP sessions
   #
   foreach $session_id (keys %{$TCP{id}}) {
	$number = $Index{Sort_Lookup}{"TCP:$session_id"};
	
	#
	#  Determine the service - usually by the lowest numbered port, eg,
	#  ports 51321 and 23 would give 23 (telnet). 
	#
	$ip_src = $TCP{id}{$session_id}{src};
	$ip_dest = $TCP{id}{$session_id}{dest};
	$tcp_src_port = $TCP{id}{$session_id}{src_port};
	$tcp_dest_port = $TCP{id}{$session_id}{dest_port};
	($service,$client) = &Pick_Service_Port("TCP",$session_id,
	 $tcp_src_port,$tcp_dest_port);

	### Fetch text name for this port
	$service_name = $Services_TCP{$service} || $service || "0";

	### Create a directory to save content for every session_id
	$randomid = join("", @chars[ map { rand @chars } ( 1 .. 17 ) ]);
	$dirname = "session_${session_id}.${service_name}.${randomid}";
	
	mkdir ("$dirname",0755) || die "ERROR60: Couldn't mkdir (perms?): $!\n";
	chdir "$dirname" || die "ERROR61: Couldn't cd $dirname: $!\n";
	
	
	#
	#  Don't actually save any files if CLI args say not to
	#
	if ($Arg{port_reject} && $Arg{Port_Rejected}{$service}) { next; }
	if ($Arg{port_accept} && !$Arg{Port_Accepted}{$service}) { next; }
	if ($Arg{ip_reject}) {
		if ($Arg{IP_Rejected}{$ip_src} || $Arg{IP_Rejected}{$ip_dest}) {
			next; 
		}
	}
	if ($Arg{ip_accept}) {
		unless ($Arg{IP_Accepted}{$ip_src} || 
		 $Arg{IP_Accepted}{$ip_dest}) { 
			next; 
		}
	}

	#
	# --- Fetch RawBoth ---
	#
	# rawboth will contain the raw data in time order. 
	$rawboth = "";
	foreach $time (sort {$a <=> $b} 
	 (keys (%{$TCP{id}{$session_id}{time}}))) {
		$rawboth .= $TCP{id}{$session_id}{time}{$time}{data};
	}
	$length = length($rawboth);

	#
	# --- Check for Min and Max size ---
	#
	next if $length < $Arg{minbytes};
	next if (($Arg{maxbytes} != 0) && ($length > $Arg{maxbytes}));


    ### output's steps:
    ###
	### 1. Print status line (Num - Session - Service) to shell
	$numtext = sprintf("%04d",$number);
	printf "%6s  %-45s  %s\n",$numtext,$session_id,$service_name 
	 unless $Arg{quiet};

	#
	# 2. --- Save Info File to Disk (default)---
	#
	if ($Arg{output_info}) {
		$filename = "session_${numtext}.info";
		$firsttime = localtime($TCP{id}{$session_id}{StartTime});
		$lasttime = localtime($TCP{id}{$session_id}{EndTime});
		$duration = ($TCP{id}{$session_id}{EndTime} -
	 	 $TCP{id}{$session_id}{StartTime});
		$duration = sprintf("%.0f",$duration);
		if ($TCP{id}{$session_id}{Partial}) { $partial = "yes"; }
		 else { $partial = "no"; }
    
		### Build output text
		$outtext = "$numtext===$session_id===$service===" .
		 "$service_name===$length\n\n" .
		 "Source addr : $ip_src\n" .
		 "Source port : $tcp_src_port\n" .
		 "Dest addr   : $ip_dest\n" .
		 "Dest port   : $tcp_dest_port\n" .
		 "Dest service: $service_name\n" .
		 "Length bytes: $length\n" .
		 "First time  : $firsttime\n" . 
		 "Last time   : $lasttime\n" . 
		 "Duration    : $duration seconds\n" .
		 "Partial     : $partial\n";
    
		### Write info file
		open (OUT,">$filename") || 
		 die "ERROR11: creating $filename $!\n";
		print OUT $outtext;
		close OUT;
	}

    

	#
	# 3. --- Save Index data to Memory ---
	#

	## Fetch times
	$starttime = scalar localtime($TCP{id}{$session_id}{StartTime});
	$duration = ($TCP{id}{$session_id}{EndTime} - 
	 $TCP{id}{$session_id}{StartTime});
	$duration = sprintf("%.0f",$duration);

	### Generate session strings
	($id_text,$id_html) = &Generate_TCP_IDs($session_id);

	### Construct HTML table row containing session data
	$Index{HTML}[$number] = "<tr><td><i>$number.</i></td>" .
	 "<td><b>$starttime</b></td><td>$duration s</td><td> " .
	 "<font color=\"blue\">$id_html " .
	 "</font></td><td> <font color=\"red\">" .
	 "$service_name</font></td><td> <font color=\"green\"> " .
	 "$length bytes</font></td><td>\n";

	### Construct text line containing session data
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",$number,
	 $id_text,"($service_name)",$length);

	### Construct image info line (in case it is needed)
	$Image{HTML}[$number]{info} = "<tr><td><i>$number.</i>" .
	 "</td><td><b>$starttime</b></td><td> " .
	 "<font color=\"blue\">$id_html </font></td><td><td>\n";

	### Construct GETPOST info line (in case it is needed)
	# starttime and host:port... are formatted differently so that
	# they are narrow and leave more room for the sub table.
	$GETPOST{HTML}[$number]{info} = "<tr><td><i>$number.</i>" .
	 "</td><td><b>$starttime</b></td><td> " .
	 "<font color=\"blue\">$id_html </font></td><td><td>\n";


	#
	# 4. --- Save Raw Sessions to Disk ---
	#

	if ($Arg{output_raw}) {
		
		$rawdir = "raw.${session_id}.${service_name}";
		mkdir ("$rawdir",0755) || die "ERROR62: Couldn't mkdir (perms?): $!\n";
		chdir "$rawdir" || die "ERROR63: Couldn't cd $rawdir: $!\n";
	
		#
		#  Save ".raw" file, all raw 2-way data time-sorted.
		#
		$filename = "session_${numtext}.${service_name}.raw";
		open (OUT,">$filename") || 
		 die "ERROR12: creating $filename $!\n";
		binmode(OUT);		# for backward OSs
		print OUT $rawboth;
		close OUT;

		### Update HTML index table with link
		$Index{HTML}[$number] .= "<li><a href=\"$filename\">raw</a> ";

		#
		#  Save ".raw1" file, server->client 1-way data assembled.
		#
		$filename = "session_${numtext}.${service_name}.raw1";
		open (OUT,">$filename") || 
		 die "ERROR13: creating $filename $!\n";
		binmode(OUT);		# for backward OSs
		print OUT &TCP_Follow_RawA($session_id);
		close OUT;

		### Update HTML index table with link
		$Index{HTML}[$number] .= "<a href=\"$filename\">raw1</a> ";

		#
		#  Save ".raw2" file, client->server 1-way data assembled.
		#
		$filename = "session_${numtext}.${service_name}.raw2";
		open (OUT,">$filename") || 
		 die "ERROR14: creating $filename $!\n";
		binmode(OUT);		# for backward OSs
		print OUT &TCP_Follow_RawB($session_id);
		close OUT;

		### Update HTML index table with link
		$Index{HTML}[$number] .= "<a href=\"$filename\">raw2</a></li> ";
	}

	chdir "../";
	
	next unless $Arg{output_apps};
	
	#
	# 5. --- Save Session as HTML ---
	#
	if ($Arg{Save_As_TCP_HTML}{$service} || $Arg{output_allhtml}) { 
		&Save_Both_HTML("TCP",$session_id,$number,$service_name,
		 $id_html); 
	}

	#
	# 6. --- Save X11 Session as HTML ---
	#
	if ($Arg{Save_As_X11_HTML}{$service}) { 
		#
		#  HTML Postprocessing can go here
		#
		&Generate_X11_HTML($session_id);
		&Process_BothHTML("TCP",$session_id,1); 

		&Save_Both_HTML("TCP",$session_id,$number,"text$service_name",
		 $id_html); 
	}


	#
	# 7. --- Save Hex Dump as HTML ---
	#
	if ($Arg{output_hex}) {
		&Process_Hex_Finish("TCP",$session_id);
		&Save_Hex_HTML("TCP",$session_id,$number,$service_name,
		 $id_html);
		&Save_Hex_Text("TCP",$session_id,$number,$service_name,
		 $id_text);
	}

	#
	# 8. --- Process Application Data ---
	#

	if ($service == 20) {
		&Save_FTP_File($session_id,$number); 
	}
	if ($service == 22) { 
		&Save_Session_textSSH_files($session_id,$number,
		 "SSH",$id_html);
	}
	if ($Arg{keydata} && $Arg{Save_As_TCP_Playback}{$service}) {
		# The following is for special analysis,
		&Save_Session_Keydata($session_id,$number,
		 $service_name,$id_html);
	}
	if ($service == 25) { 
		&Save_SMTP_Emails($session_id,$number); 
	}
	if ($service == 80 or $service == 8080 or 
	 $service == 3127 or $service == 1080)  { 
		&Save_HTTP_Files($session_id,$number,$service_name); 
		&Process_HTTP($session_id);
		$uri = URI->new($httpaddress);
		$fpath = $uri->path;
		($filename, $directories) = fileparse($fpath);
	}

	if ($Arg{Save_As_X11_Playback}{$service}) {
		&Save_Session_XReplay($session_id,$number,$service_name); 
	}

	if ($Arg{Save_As_VNC_Playback}{$service}) {
		&Save_Session_VNCReplay_andHTML($session_id,$number,
		 $service_name,$id_html); 
	}
	
	$raw = &TCP_Follow_RawB($session_id);
	
	if ($raw =~ /^\200\0\0p0\211/) {
		&Save_NFS_File($session_id,$number);
	}

	if ($Arg{Save_As_TCP_Playback}{$service}) { 
		&Save_Session_Replay($session_id,$number,$service_name); 
	}
	
	Chdir($Arg{output_dir});
	
	### Summary information to csv file
    if ($Arg{output_csv}) {
        ### Build output line
		#transport_protocol; apps_prot; src_ipaddr; src_port; dst_ipaddr; dst_port; uri; directory; filename; network_prot;
        $outtext = "tcp; $service_name; $ip_src; $tcp_src_port; $ip_dest; $tcp_dest_port; $uri; $dirname; $filename; ;\n"; 

        ### Write info file
        open (FILECSV,">>output.csv") || die "ERROR59: opening output.csv $!\n";
        print FILECSV $outtext;
        close FILECSV;
    }
	
   }

   $Bench{++$BM}{mark} = new Benchmark if $Arg{bench};
   $Bench{$BM}{text} = "Process TCP Sessions - end";
}


# Process_UDP_Streams - this subroutine processes %UDP, saving the 
# 	sessions to various "session*" files on disk. It populates %Index
#	with information on the files that were created. It also checks
#	the application port numbers and triggers further processing - 
#	eg DNS html output files. #7
#
sub Process_UDP_Streams {
   #debug
   print "\n Process_UDP_Streams subroutine called \n" unless $Arg{quiet};

   my ($randomid,$rawdir,$dirname,$filename,$id_html,$id_text,$time,$rawboth,$uri);
   my @chars = ( "A" .. "Z", "a" .. "z", 0 .. 9 );

   $Bench{++$BM}{mark} = new Benchmark if $Arg{bench};
   $Bench{$BM}{text} = "Process UDP Sessions - start";

   #
   #  Loop through all UDP Streams
   #
   foreach $session_id (keys %{$UDP{id}}) {
	$number = $Index{Sort_Lookup}{"UDP:$session_id"};

        #
        #  Determine the service - usually by the lowest numbered port, eg,
        #  ports 51327 and 53 would give 53 (dns). (big assumption!)
        #
	$ip_src = $UDP{id}{$session_id}{src};
	$ip_dest = $UDP{id}{$session_id}{dest};
	$udp_src_port = $UDP{id}{$session_id}{src_port};
	$udp_dest_port = $UDP{id}{$session_id}{dest_port};
	($service,$client) = &Pick_Service_Port("UDP",$session_id,
	 $udp_src_port,$udp_dest_port);

	### Fetch text name for this port
	$service_name = $Services_UDP{$service} || $service || "0";
	
	### Create a directory to save content for every session_id
	$randomid = join("", @chars[ map { rand @chars } ( 1 .. 17 ) ]);
	$dirname = "stream_${session_id}.${service_name}.${randomid}";
	
	mkdir ("$dirname",0755) || die "ERROR63: Couldn't mkdir (perms?): $!\n";
	chdir "$dirname" || die "ERROR65: Couldn't cd $dirname: $!\n";

    #
    #  Don't actually save any files if CLI args say not to
    #
	if ($Arg{port_reject} && $Arg{Port_Rejected}{$service}) { next; }
	if ($Arg{port_accept} && !$Arg{Port_Accepted}{$service}) { next; }
	if ($Arg{ip_reject}) {
		if ($Arg{IP_Rejected}{$ip_src} || $Arg{IP_Rejected}{$ip_dest}) { 
			next; 
		}
	}
	if ($Arg{ip_accept}) {
		unless ($Arg{IP_Accepted}{$ip_src} || 
		 $Arg{IP_Accepted}{$ip_dest}) { 
			next; 
		}
	}

	#
	# --- Fetch RawBoth ---
	#
	# rawboth will contain the raw data in time order. 
	$rawboth = "";
	foreach $time (sort {$a <=> $b} 
	 (keys (%{$UDP{id}{$session_id}{time}}))) {
		$rawboth .= $UDP{id}{$session_id}{time}{$time};
	}
	$length = length($rawboth);

	#
	# --- Check for Min and Max Size ---
	#
	next if $length < $Arg{minbytes};
	next if (($Arg{maxbytes} != 0) && ($length > $Arg{maxbytes}));

	### output's steps:
    ###
	### 1. Print status line (Num - Stream - Service) to shell
	$numtext = sprintf("%04d",$number);
	printf "%6s  %-45s  %s\n",$numtext,$session_id,$service_name 
	 unless $Arg{quiet};

	#
	# 2. --- Save Info File to Disk ---
	#
	if ($Arg{output_info}) {
		$filename = "stream_${numtext}.info";
                $firsttime = localtime($UDP{id}{$session_id}{StartTime});
                $lasttime = localtime($UDP{id}{$session_id}{EndTime});
                $duration = ($UDP{id}{$session_id}{EndTime} -
                 $UDP{id}{$session_id}{StartTime});
		$duration = sprintf("%.0f",$duration);
		if ($UDP{id}{$session_id}{Partial}) { $partial = "yes"; }
		 else { $partial = "no"; }
	
                ### Build output text
                $outtext = "$numtext===$session_id===$service===" .
                 "$service_name===$length\n\n" .
                 "Source addr : $ip_src\n" .
                 "Source port : $udp_src_port\n" .
                 "Dest addr   : $ip_dest\n" .
                "Dest port   : $udp_dest_port\n" .
                 "Dest service: $service_name\n" .
                 "Length bytes: $length\n" .
                 "First time  : $firsttime\n" . 
                 "Last time   : $lasttime\n" . 
                 "Duration    : $duration seconds\n" .
                 "Partial     : $partial\n";
	
                ### Write info file
                open (OUT,">$filename") || 
                 die "ERROR15: creating $filename $!\n";
                print OUT $outtext;
                close OUT;
	}


	#
	# 3. --- Save Index data in Memory ---
	#

	### Fetch Times
	$starttime = scalar localtime($UDP{id}{$session_id}{StartTime});
	$duration = ($UDP{id}{$session_id}{EndTime} - 
	 $UDP{id}{$session_id}{StartTime});
	$duration = sprintf("%.0f",$duration);

	### Construct HTML table row containing stream data
	$id_html = "$ip_src:$udp_src_port &lt;-&gt; $ip_dest:$udp_dest_port";
	$Index{HTML}[$number] = "<tr><td><i>$number.</i></td>" .
	 "<td><b>$starttime</b></td><td>$duration s</td><td> " .
	 "<font color=\"blue\">$id_html " .
	 "</font></td><td> <font color=\"red\">" .
	 "<i>$service_name</i></font></td><td> <font color=\"green\"> " .
	 "$length bytes</font></td><td>\n";

	### Construct text line containing session data
	$id_text = "$ip_src:$udp_src_port <-> $ip_dest:$udp_dest_port";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",$number,
	 $id_text,"($service_name)",$length);


	#
	# 4. --- Save Raw Stream to Disk ---
	#

	if ($Arg{output_raw}) {

		$rawdir = "raw.${session_id}.${service_name}";
		mkdir ("$rawdir",0755) || die "ERROR62: Couldn't mkdir (perms?): $!\n";
		chdir "$rawdir" || die "ERROR63: Couldn't cd $rawdir: $!\n";
		
		#
		#  Save ".raw" file, all raw 2-way data time-sorted.
		#
		$filename = "stream_${numtext}.${service_name}.raw";
		open (OUT,">$filename") || 
		 die "ERROR16: creating $filename $!\n";
		binmode(OUT);		# for backward OSs
		print OUT $rawboth;
		close OUT;

		### Update HTML index table with link
		$Index{HTML}[$number] .= "<li><a href=\"$filename\">raw</a> ";

		#
		#  Save ".raw1" file, server->client 1-way data time-sorted.
		#
		$filename = "stream_${numtext}.${service_name}.raw1";
		open (OUT,">$filename") || 
		 die "ERROR17: creating $filename $!\n";
		binmode(OUT);		# for backward OSs
		print OUT $UDP{id}{$session_id}{RawA};
		close OUT;

		### Update HTML index table with link
		$Index{HTML}[$number] .= "<a href=\"$filename\">raw1</a> ";

		#
		#  Save ".raw2" file, client->server 1-way data time-sorted.
		#
		$filename = "stream_${numtext}.${service_name}.raw2";
		open (OUT,">$filename") || 
		 die "ERROR18: creating $filename $!\n";
		binmode(OUT);		# for backward OSs
		print OUT $UDP{id}{$session_id}{RawB};
		close OUT;

		### Update HTML index table with link
		$Index{HTML}[$number] .= "<a href=\"$filename\">raw2</a></li> ";
	}

	chdir "../";
	
	next unless $Arg{output_apps};

	#
	# 5. --- Save Stream as HTML ---
	#

	if ($Arg{Save_As_UDP_HTML}{$service} || $Arg{output_allhtml}) { 
		#
		#  HTML Postprocessing can go here
		#
		&Process_BothHTML("UDP",$session_id);

		&Save_Both_HTML("UDP",$session_id,$number,$service_name); 
	}

	#
	# 6. --- Save Hex Dump as HTML ---
	#
	if ($Arg{output_hex}) {
		&Process_Hex_Finish("UDP",$session_id);
		&Save_Hex_HTML("UDP",$session_id,$number,$service_name,
		 $id_html);
		&Save_Hex_Text("UDP",$session_id,$number,$service_name,
		 $id_text);
	}


	#
	# 7. --- Process Application Data ---
	#
	if ($Arg{Save_As_UDP_Playback}{$service}) { 
		&Save_Stream_Replay($session_id,$number,$service_name); 
	}
	
	Chdir($Arg{output_dir});
	
	### Summary information to csv file
    if ($Arg{output_csv}) {
        ### Build output line
		#transport_protocol; apps_prot; src_ipaddr; src_port; dst_ipaddr; dst_port; url; directory; filename; network_prot;
        $outtext = "udp; $service_name; $ip_src; $udp_src_port; $ip_dest; $udp_dest_port; ; $dirname; ; ;\n"; 

        ### Write info file
        open (FILECSV,">>output.csv") || die "ERROR59: opening output.csv $!\n";
        print FILECSV $outtext;
        close FILECSV;
    }

   }

   $Bench{++$BM}{mark} = new Benchmark if $Arg{bench};
   $Bench{$BM}{text} = "Process UDP Sessions - end";
}



# Process_ICMP - this subroutine processes %ICMP. #8
#
sub Process_ICMP {
    #debug
    print "\n Process_ICMP subroutine called \n" unless $Arg{quiet};

   my ($filename,$id_text,$id_html);

   $Bench{++$BM}{mark} = new Benchmark if $Arg{bench};
   $Bench{$BM}{text} = "Process ICMP Sessions - start";

   #
   #  Loop through all ICMP Streams
   #
   foreach $time (keys %{$ICMP{time}}) {
	$number = $Index{Sort_Lookup}{"ICMP:$time"};

	
	### Fetch Data
	$icmp_type = $ICMP{time}{$time}{type};
	$icmp_code = $ICMP{time}{$time}{code};
	$icmp_ver = $ICMP{time}{$time}{ver};
	$ip_src = $ICMP{time}{$time}{src};
	$ip_dest = $ICMP{time}{$time}{dest};
	$session_id = "$ip_src,$ip_dest";

	### Fetch text name for this port
	$type_name = $ICMP_Types{$icmp_type} || $icmp_type || "0";
	$service_name = $icmp_type;

        #
        #  Don't actually save any files if CLI args say not to
        #
	if ($Arg{ip_reject}) {
		if ($Arg{IP_Rejected}{$ip_src} || $Arg{IP_Rejected}{$ip_dest}){ 
			next; 
		}
	}
	if ($Arg{ip_accept}) {
		unless ($Arg{IP_Accepted}{$ip_src} || 
		 $Arg{IP_Accepted}{$ip_dest}) { 
			next; 
		}
	}

	#
	# --- Check for Min and Max Size ---
	#
	$length = length($ICMP{time}{$time}{data});
	next if $length < $Arg{minbytes};
	next if (($Arg{maxbytes} != 0) && ($length > $Arg{maxbytes}));

	### output's steps:
    ###
	### 1. Print status line (Num - ICMP's direction - Service) to shell
	$numtext = sprintf("%04d",$number);
	printf "%6s  %-45s  ICMP %s\n",$numtext,$session_id,$type_name 
	 unless $Arg{quiet};

	#
	# 2. --- Save Info File to Disk ---
	#
	if (($Arg{output_info}) && ($length > 0)) {
		$filename = "icmp_${numtext}.${service_name}.info";
		if ($ICMP{time}{$time}{Partial}) { $partial = "yes"; }
		 else { $partial = "no"; }
		$starttime = scalar localtime($time);
	
                ### Build output text
                $outtext = "$numtext===$session_id===$icmp_type===" .
                 "$type_name===$length\n\n" .
                 "Source addr : $ip_src\n" .
                 "Dest addr   : $ip_dest\n" .
                 "ICMP version: $icmp_ver\n" .
                 "ICMP type   : $icmp_type\n" .
                 "ICMP code   : $icmp_code\n" .
                 "ICMP name   : $type_name\n" .
                 "Length bytes: $length\n" .
                 "Time        : $starttime\n" . 
                 "Partial     : $partial\n";
	
                ### Write info file
                open (OUT,">$filename") || 
                 die "ERROR19: creating $filename $!\n";
                print OUT $outtext;
                close OUT;
	}

	#
	# 3. --- Save Index data in Memory ---
	#

	### Fetch Times
	$starttime = scalar localtime($time);

	### Construct HTML table row containing stream data
	$id_html = "$ip_src -&gt; $ip_dest";
	$Index{HTML}[$number] = "<tr><td><i>$number.</i></td>" .
	 "<td><b>$starttime</b></td><td>0 s</td><td> " .
	 "<font color=\"blue\">$id_html" .
	 "</font></td><td> <font color=\"red\">" .
	 "<i>$icmp_ver</i></font></td><td> <font color=\"green\"> " .
	 "$length bytes</font></td><td>$type_name\n";

	### Construct text line containing session data
	$id_text = "$ip_src -> $ip_dest";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",$number,
	 $id_text, "($icmp_ver $type_name)",$length);


	#
	# 4. --- Save Raw Stream to Disk ---
	#

	if (($Arg{output_raw}) && ($length > 0)) {

		#
		#  Save ".raw" file, all raw 2-way data time-sorted.
		#
		#$filename = "icmp_${numtext}.${service_name}.raw";
		#open (OUT,">$filename") || 
		# die "ERROR20: creating $filename $!\n";
		#binmode(OUT);		# for backward OSs
		#print OUT $ICMP{time}{$time}{data};
		#close OUT;
		print "ICMP's raw data not need to be saved.\n" unless $Arg{quiet}; 

		### Update HTML index table with link
		$Index{HTML}[$number] .= "<li><a href=\"$filename\">raw</a> ";

	}

	#
	# 5. --- Save Stream as HTML ---
	#

	if ($Arg{output_allhtml}) { 
		#
		#  HTML Postprocessing can go here
		#
		&Process_BothHTML("ICMP",$time);

		&Save_Both_HTML("ICMP",$time,$number,$service_name,$id_html);
	}

	#
	# 6. --- Save Hex Dump as HTML ---
	#
	if ($Arg{output_hex}) {
		&Process_Hex_Finish("ICMP",$time);
		&Save_Hex_HTML("ICMP",$time,$number,$service_name,$id_html);
		&Save_Hex_Text("ICMP",$time,$number,$service_name,$id_text);
	}
		
	### Summary information to csv file
    if ($Arg{output_csv}) {
        ### Build output line
		#transport_protocol; apps_prot; src_ipaddr; src_port; dst_ipaddr; dst_port; url; directory; filename; network_prot;
        $outtext = " ; ; $ip_src; ; $ip_dest; ; ; ; ; $icmp_ver;\n"; 

        ### Write info file
        open (FILECSV,">>output.csv") || die "ERROR59: opening output.csv $!\n";
        print FILECSV $outtext;
        close FILECSV;
    }

   }

   $Bench{++$BM}{mark} = new Benchmark if $Arg{bench};
   $Bench{$BM}{text} = "Process ICMP Sessions - end";
}


# Process_HTTP - HTTP processing. Looks for GETs and POSTs, and process them
#		into %GETPOST. Constructs a HTTP log in %HTTPlog. #9
#
sub Process_HTTP {
    #debug
    print "\n Process_HTTP subroutine called \n" unless $Arg{quiet};
    
	my ($junk,$var,$value,$term,$data,$request,$site,$post,$get,$reply);
	my ($start,$src,$num,$req,$recv,$type,$status,$time1,$duration,$dest);
	my @Terms;	
	my $index = 0;
	my $indexA = 0;
	my $indexB = 0;

	### Input
	my $session_id = shift;

	$src = $TCP{id}{$session_id}{src};
	$dest = $TCP{id}{$session_id}{dest};

	#
	#  Process 
	#

	### Get packet times (may need to use seqs instead)
	@Times = sort{$a <=> $b} (keys(%{$TCP{id}{$session_id}{time}})); 

	### Step through each packet
    for ($i=0; $i <= $#Times; $i++) {

		### Fetch data from mem
        $time = $Times[$i];
        $request = $TCP{id}{$session_id}{time}{$time}{data};
	    $request =~ s/^\0\0*//;

	    #
	    # --- Do HTTPlog Processing ---
	    #

	    next unless $request =~ /^(GET|POST)\s/; # speed

	    ### Calc duration
        $time1 = $Times[$i+1] || $time;
	    $duration = $time1 - $time;

	    # some magic
	    $reply = "";
	    foreach $inc (1..16) {
			$next = $TCP{id}{$session_id}{time}{$Times[$i+$inc]}{data};
			$next =~ s/^\0\0*//;
			if ($next =~ /^U*\0*HTTP/) {
				$reply = $next;
				$time1 = $Times[$i+$inc] || $time;
				$duration = $time1 - $time;
				last;
			} else {
				$request .= $next;
			}
	    }
		$i++; # speed

	    if ($request =~ /^GET \S* HTTP/) {

			### Get the site string
			($site) = $request =~ /^GET (\S*)\s/;
			if ($site =~ m:^/:) {
				# assume this was a http, missing the "http://host"
				$site = "http://${dest}$site";
			}
			
			$httpaddress = $site;
		
			### Get the status and mime type from reply
			($status)  = $reply =~ /HTTP\/\S*\s(\S*)/s;
			($type) = $reply =~ /Content-Type:\s(\S*)/s;
			($size) = $reply =~ /Content-Length:\s(\S*)/s;
			$type = "-" if $type eq "";
			$size = 0 if $size eq "";
			$result = $Result_Names{$status} || "TCP_HIT";
		
			### Store the log entry
			$HTTPlog{time}{$time} = 
			 sprintf("%9d.%03d %6d %s %s/%03d %d %s %s %s %s%s/%s %s\n",
			 int($time),(($time - int($time))*1000),($duration*1000),
			 $src,$result,$status,$size,"GET",$site,"-","NONE","",
			 "-",$type);
			$HTTPlog{notempty} = 1;

	    } elsif ($request =~ /^POST .* HTTP/) {
			
			### Get the site string
			($site) = $request =~ /^POST (\S*)\s/;
			if ($site =~ m:^/:) {
			# assume this was a http, missing the "http://host"
			$site = "http://${dest}$site";
			}

			### Get the status and mime type
			($status)  = $reply =~ /HTTP\/\S*\s(\S*)/s;
			($type) = $reply =~ /Content-Type:\s(\S*)/s;
			($size) = $reply =~ /Content-Length:\s(\S*)/s;
			$type = "-" if $type eq "";
			$size = length($TCP{id}{$session_id}) if $size eq "";
			$result = $Result_Names{$status} || "TCP_HIT";
		
			### Store the log entry
			$HTTPlog{time}{$time} = 
			 sprintf("%9d.%03d %6d %s %s/%03d %d %s %s %s %s%s/%s %s\n",
			 int($time),(($time - int($time))*1000),($duration*1000),
			 $src,$result,$status,$size,"POST",$site,"-","NONE","",
			 "-",$type);
			$HTTPlog{notempty} = 1;

	    }

	    #
	    # --- Do GETPOST Processing ---
	    #
	    if ($request =~ /^GET \S*\?\S* HTTP/) {
	    
			### Get the GET string
			($site,$get) = $request =~ /^GET (\S*)\?(\S*)\s/;

			# check it looks like a GET,
			if ($get =~ /=/) {
		
				#
				#  Populate %GETPOST with a table containing the GET data
				#
				if (! defined $GETPOST{HTML}[$number]{query}) {
					$GETPOST{HTML}[$number]{info} .=
					 "<font color=\"red\">GET</font></td><td width=70%>";
					$GETPOST{notempty} = 1;
				} else {
					$GETPOST{HTML}[$number]{query} .= "<hr>\n";
				}
			
				#
				#  Generate table of query key value pairs
				#
				$GETPOST{HTML}[$number]{query} .= "$site<br><table border=1>\n";
				@Terms = split(/&/,$get);
				foreach $term (@Terms) {
					($var,$value) = split(/=/,$term);
					$value =~ tr/+/ /;
					$value =~ s/%([a-f0-9][a-f0-9])/pack("C",hex($1))/egi;
					$value =~ s/</&lt;/g;
					$value =~ s/>/&gt;/g;
					$value =~ s/\n/<br>\n/g;
					$GETPOST{HTML}[$number]{query} .=
					 "<tr><td><b>$var</b></td>" .
					 "<td><font face=\"Courier\">$value</font></td></tr>\n";
				}
				$GETPOST{HTML}[$number]{query} .= "</table>\n";
			}

	    } elsif ($request =~ /^POST .* HTTP/) {

			### Get the POST strings
			($junk,$post,$junk1) = split(/\n\n|\r\n\r\n/,$request);

			# check it looks like a POST
			if ($post =~ /=/) {

				#
				#  Populate %GETPOST with a table containing the POST data
				#
				if (! defined $GETPOST{HTML}[$number]{query}) {
				$GETPOST{HTML}[$number]{info} .=
				 "<font color=\"red\">POST</font></td><td width=70%>";
				$GETPOST{notempty} = 1;
				} else {
					$GETPOST{HTML}[$number]{query} .= "<hr>\n";
				}
			
				($site) = $request =~ /^POST (\S*)\s/;
	
				$post =~ s/HTTP .*//s;

				#
				#  Generate table of query key value pairs
				#
				$GETPOST{HTML}[$number]{query} .= "$site<br><table border=1>\n";
				@Terms = split(/&/,$post);
				foreach $term (@Terms) {
					($var,$value) = split(/=/,$term);
					$value =~ tr/+/ /;
					$value =~ 
					 s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
					$value =~ s/</&lt;/g;
					$value =~ s/>/&gt;/g;
					$value =~ s/\n/<br>/g;
					$GETPOST{HTML}[$number]{query} .=
					 "<tr><td><b>$var</b></td>" .
					 "<td><font face=\"Courier\">$value</font></td></tr>\n";
				}
				$GETPOST{HTML}[$number]{query} .= "</table>\n";
			}
	    }
	}
}


# Sort_Index - this creates a sort order for the master index.html, based
#	on the sort argument (defaults to sort by time). #10
#

sub Sort_Index {
    #debug
    print "\n Sort_Index subroutine called \n" unless $Arg{quiet};

	if ($Arg{sort} eq "size") {
		&Sort_Index_By_Size();
	} elsif ($Arg{sort} eq "type") {
		&Sort_Index_By_Type();
	} elsif ($Arg{sort} eq "ip") {
		&Sort_Index_By_IP();
	} else {
		&Sort_Index_By_Time();
	}
}


# Sort_Index_By_Time - this calculates an appropriate order for the index
#	files based on session start time. #11
#
sub Sort_Index_By_Time {
    #debug
    print "\n Sort_Index_By_Time subroutine called \n" unless $Arg{quiet};
    
	my ($session_id,$time,$number);

	#
	#  Determine Session and Stream time order
	#
	foreach $session_id (keys %{$TCP{id}}) {
		$Index{Time_Order}{"TCP:$session_id"} =
		 $TCP{id}{$session_id}{StartTime};
	}
	foreach $session_id (keys %{$UDP{id}}) {
		$Index{Time_Order}{"UDP:$session_id"} =
		 $UDP{id}{$session_id}{StartTime};
	}
	foreach $time (keys %{$ICMP{time}}) {
		$Index{Time_Order}{"ICMP:$time"} = $time;
	}
	$number = 0;
	foreach $session (sort {$Index{Time_Order}{$a} <=> 
	 $Index{Time_Order}{$b}} keys %{$Index{Time_Order}}) {
		$number++;
		$Index{Sort_Lookup}{$session} = $number;
	}
}


# Sort_Index_By_Size - this calculates an appropriate order for the index
#	files based on session size. #12
#
sub Sort_Index_By_Size {
    #debug
    print "\n Sort_Index_By_Size subroutine called \n" unless $Arg{quiet};
    
	my ($session_id,$time,$number);

	#
	#  Determine Session and Stream size order
	#
	foreach $session_id (keys %{$TCP{id}}) {
		$Index{Size_Order}{"TCP:$session_id"} =
		 $TCP{id}{$session_id}{size};
	}
	foreach $session_id (keys %{$UDP{id}}) {
		$Index{Size_Order}{"UDP:$session_id"} =
		 $UDP{id}{$session_id}{size};
	}
	foreach $time (keys %{$ICMP{time}}) {
		$Index{Size_Order}{"ICMP:$time"} = 
		 $ICMP{time}{$time}{size};
	}
	$number = 0;
	foreach $session (sort {$Index{Size_Order}{$b} <=> 
	 $Index{Size_Order}{$a}} keys %{$Index{Size_Order}}) {
		$number++;
		$Index{Sort_Lookup}{$session} = $number;
	}
}


# Sort_Index_By_Type - this calculates an appropriate order for the index
#	files based on session type, followed by time. #13
#
sub Sort_Index_By_Type {
    #debug
    print "\n Sort_Index_By_Type subroutine called \n" unless $Arg{quiet};
    
	my ($service,$tcp_src_port,$tcp_dest_port,$client,$udp_src_port,
	 $udp_dest_port,$session_id,$time,$number);

	#
	#  Determine Session and Stream time order
	#
	foreach $session_id (keys %{$TCP{id}}) {
		# Determine the service - usually by the lowest numbered port
		$tcp_src_port = $TCP{id}{$session_id}{src_port};
		$tcp_dest_port = $TCP{id}{$session_id}{dest_port};
		($service,$client) = &Pick_Service_Port("TCP",$session_id,
		 $tcp_src_port,$tcp_dest_port);

		$Index{Type_Order}{"TCP:$session_id"}{1} = 1;
		$Index{Type_Order}{"TCP:$session_id"}{2} = $service;
		$Index{Type_Order}{"TCP:$session_id"}{3} = 
		 $TCP{id}{$session_id}{StartTime};
	}
	foreach $session_id (keys %{$UDP{id}}) {
        	# Determine the service - usually by the lowest numbered port
		$udp_src_port = $UDP{id}{$session_id}{src_port};
		$udp_dest_port = $UDP{id}{$session_id}{dest_port};
		($service,$client) = &Pick_Service_Port("UDP",$session_id,
		 $udp_src_port,$udp_dest_port);

		$Index{Type_Order}{"UDP:$session_id"}{1} = 2;
		$Index{Type_Order}{"UDP:$session_id"}{2} = $service;
		$Index{Type_Order}{"UDP:$session_id"}{3} = 
		 $UDP{id}{$session_id}{StartTime};
	}
	foreach $time (keys %{$ICMP{time}}) {
		$Index{Type_Order}{"ICMP:$time"}{1} = 3;
		$Index{Type_Order}{"ICMP:$time"}{2} = 0;
		$Index{Type_Order}{"ICMP:$time"}{3} = $time;
	}

	# now we sort by TCP->UDP->IP then port then time.
	$number = 0;
	foreach $session (sort {
		$Index{Type_Order}{$a}{1} <=> $Index{Type_Order}{$b}{1} ||
		$Index{Type_Order}{$a}{2} <=> $Index{Type_Order}{$b}{2} ||
		$Index{Type_Order}{$a}{3} <=> $Index{Type_Order}{$b}{3}
	 } keys %{$Index{Type_Order}}) {
		$number++;
		$Index{Sort_Lookup}{$session} = $number;
	}
}


# Sort_Index_By_IP - this calculates an appropriate order for the index
#	files based on client IP, followed by time. #14
#
sub Sort_Index_By_IP {
	#debug
        print "\n Sort_Index_By_IP subroutine called \n" unless $Arg{quiet};
        
        my ($service,$ip,$ip_dest,$ip_src,$client,
	 $session_id,$time,$number,$text,$html,$rest);
	my @IP;

	#
	#  Determine Session and Stream time order
	#
	foreach $session_id (keys %{$TCP{id}}) {
		# Determine source IP
		# here we use the same subroutine as the index.html
		# so that they match up.
		($text,$html) = &Generate_TCP_IDs($session_id);
		($ip,$rest) = split(/:/,$text,2);

		# Split on IPv4 or IPv6
		$IP = ();
		if ($ip =~ /\./) { @IP = split(/\./,$ip); } 
		 else { $IP[0] = $ip; }

		$Index{Type_Order}{"TCP:$session_id"}{1} = $IP[0];
		$Index{Type_Order}{"TCP:$session_id"}{2} = $IP[1];
		$Index{Type_Order}{"TCP:$session_id"}{3} = $IP[2];
		$Index{Type_Order}{"TCP:$session_id"}{4} = $IP[3];
		$Index{Type_Order}{"TCP:$session_id"}{5} = 
		 $TCP{id}{$session_id}{StartTime};
	}
	foreach $session_id (keys %{$UDP{id}}) {
		# Determine source IP
		$ip = $UDP{id}{$session_id}{src};

		# Split on IPv4 or IPv6
		$IP = ();
		if ($ip =~ /\./) { @IP = split(/\./,$ip); } 
		 else { $IP[0] = $ip; }

		$Index{Type_Order}{"UDP:$session_id"}{1} = $IP[0];
		$Index{Type_Order}{"UDP:$session_id"}{2} = $IP[1];
		$Index{Type_Order}{"UDP:$session_id"}{3} = $IP[2];
		$Index{Type_Order}{"UDP:$session_id"}{4} = $IP[3];
		$Index{Type_Order}{"UDP:$session_id"}{5} = 
		 $UDP{id}{$session_id}{StartTime};
	}
	foreach $time (keys %{$ICMP{time}}) {
		# Determine source IP
		$ip = $ICMP{time}{$time}{src};

		# Split on IPv4 or IPv6
		$IP = ();
		if ($ip =~ /\./) { @IP = split(/\./,$ip); } 
		 else { $IP[0] = $ip; }

		$Index{Type_Order}{"ICMP:$time"}{1} = $IP[0];
		$Index{Type_Order}{"ICMP:$time"}{2} = $IP[1];
		$Index{Type_Order}{"ICMP:$time"}{3} = $IP[2];
		$Index{Type_Order}{"ICMP:$time"}{4} = $IP[3];
		$Index{Type_Order}{"ICMP:$time"}{5} = $time;
	}

	# now we sort by IP then time
	$number = 0;
	foreach $session (sort {
		$Index{Type_Order}{$a}{1} <=> $Index{Type_Order}{$b}{1} ||
		$Index{Type_Order}{$a}{2} <=> $Index{Type_Order}{$b}{2} ||
		$Index{Type_Order}{$a}{3} <=> $Index{Type_Order}{$b}{3} ||
		$Index{Type_Order}{$a}{4} <=> $Index{Type_Order}{$b}{4} ||
		$Index{Type_Order}{$a}{1} cmp $Index{Type_Order}{$b}{1} ||
		$Index{Type_Order}{$a}{5} <=> $Index{Type_Order}{$b}{5} 
	 } keys %{$Index{Type_Order}}) {
		$number++;
		$Index{Sort_Lookup}{$session} = $number;
	}
}


# Print_Welcome - print short program welcome message. #15
#
sub Print_Welcome {
        #debug
        #print "\n Welcome subroutine called \n";
	
        unless ($Arg{quiet}) {
		print "\n Hello, This's Extractor Welcome Message \n" unless $Arg{quiet};
	}
}


# Print_Header1 - print program welcome message. #16
#
sub Print_Header1 {
    #debug
    print "\n Print_Header1 subroutine called \n" unless $Arg{quiet};
        
	unless ($Arg{quiet}) {
		print "Reading $TYPE log...\n";
		printf "%6s  %-45s  %s\n","Packet",
			"Session (host:port <=> host:port)","Length";
	}
}


# Print_Header2 - print header before loading the file. #17
#
sub Print_Header2 {
    #debug
    print "\n Print_Header2 subroutine called \n" unless $Arg{quiet};
        
	print "\nCreating files...\n" unless $Arg{quiet};
	printf "%6s  %-45s  %s\n","Num","Session (host:port <=> host:port)",
	 "Service" unless $Arg{quiet};
}


# Print_Footer1 - print footer at end of program. #18
#
sub Print_Footer1 {
    #debug
    print "\n Print_Footer1 subroutine called \n" unless $Arg{quiet};
        
	if ($Arg{output_index}) {
		print "\nindex.html created.\n" unless $Arg{quiet};
	}
}


# Chdir - change directory with error. #19
#
sub Chdir {
    #debug
    print "\n Chdir subroutine called \n" unless $Arg{quiet};
    
	my $dir = shift;
	#
	#  This can be invoked with $Arg{output_dir}, so $dir won't
	#  always be defined - which is okay.
	#
	if (defined $dir) { 
		chdir "$dir" || 
		 die "ERROR21: Can't cd to $dir: $!\n";
	}
}


# Create_Index_Files - Create the HTML and text index files. This reads
#	%Index and creates the files on disk. #20
#
sub Create_Index_Files {
   #debug
   print "\n Create_Index_Files subroutine called \n" unless $Arg{quiet};
    
   my ($html_index,$html_line,$html_links,$image_empty,$getpost_empty);
   $getpost_empty = $image_empty = "";

   if ($Arg{output_index}) {


	######################
	# --- index.html ---

	$image_empty = "(Empty) " unless $Image{notempty};
	$getpost_empty = "(Empty) " unless $GETPOST{notempty};
	$httplog_empty = "(Empty) " unless $HTTPlog{notempty};
	#
	#  Create HTML Index file containing all reports
	#
	open(FILE,">index.html") || die "ERROR22: creating index: $!\n";
	print FILE <<END_HTML;
<html>
<head><title>Chaosreader Report, $Arg{infile}</title></head>
<body bgcolor="white" textcolor="black">
<font size=+3>Chaosreader Report</font><br>
<font size=+1>File: $Arg{infile}, Type: $TYPE, Created at: $the_date</font><p>
<a href="image.html"><font color="blue"><b>Image Report</b></font></a> 
 $image_empty - Click here for a report on captured images.<br>
<a href="getpost.html"><font color="blue"><b>GET/POST Report</b></font></a> 
 $getpost_empty - Click here for a report on HTTP GETs and POSTs.<br>
<a href="httplog.text"><font color="blue"><b>HTTP Proxy Log</b></font></a> 
 $httplog_empty - Click here for a generated proxy style HTTP log.<p>
<font size=+2>TCP/UDP/... Sessions</font><br>
<table border=2>
END_HTML
	for ($html_index=0; $html_index <= $#{$Index{HTML}}; $html_index++) {
		$html_line = $Index{HTML}[$html_index];
		next unless defined $html_line;
		print FILE "$html_line </td></tr>\n";
	}
	print FILE <<END_HTML;
</table><p>
<font size=+2>IP Count</font><br>
<table border=2>
END_HTML
	foreach $IP (sort {$Count{IP}{$b} <=> $Count{IP}{$a}} 
	 keys %{$Count{IP}}) {
		print FILE "<tr><td>$IP</td><td>$Count{IP}{$IP}</td></tr>\n";
	}
	print FILE <<END_HTML;
</table><p>
<font size=+2>TCP Port Count</font><br>
<table border=2>
END_HTML
	foreach $port (sort {$Count{TCPport}{$b} <=> $Count{TCPport}{$a}} 
	 keys %{$Count{TCPport}}) {
		$port_text = $Services_TCP{$port} || $port || "0";
		print FILE "<tr><td>$port_text</td><td>$Count{TCPport}{$port}" .
		 "</td></tr>\n";
	}
	print FILE <<END_HTML;
</table><p>
<font size=+2>UDP Port Count</font><br>
<table border=2>
END_HTML
	foreach $port (sort {$Count{UDPport}{$b} <=> $Count{UDPport}{$a}} 
	 keys %{$Count{UDPport}}) {
		$port_text = $Services_UDP{$port} || $port || "0";
		print FILE "<tr><td>$port_text</td><td>$Count{UDPport}{$port}" .
		 "</td></tr>\n";
	}
	print FILE <<END_HTML;
</table><p>
<font size=+2>IP Protocol Count</font><br>
<table border=2>
END_HTML
	foreach $protocol (sort {$Count{IPprotocol}{$b} <=> 
	 $Count{IPprotocol}{$a}} keys %{$Count{IPprotocol}}) {
		$protocol_text = $IP_Protocols{$protocol};
		print FILE "<tr><td>$protocol_text</td><td>" .
		 "$Count{IPprotocol}{$protocol}</td></tr>\n";
	}
	print FILE <<END_HTML;
</table><p>
<font size=+2>Ethernet Type Count</font><br>
<table border=2>
END_HTML
	foreach $type (sort {$Count{EtherType}{$b} <=> $Count{EtherType}{$a}} 
	 keys %{$Count{EtherType}}) {
		print FILE "<tr><td>$type</td><td>$Count{EtherType}{$type}" .
		 "</td></tr>\n";
	}
	print FILE <<END_HTML;
</table>
</body>
</html>
END_HTML
	

	######################
	# --- index.text ---

	# 
	#  Create Text index file
	#
	open(FILE,">index.text") || die "ERROR23: creating index: $!\n";
	print FILE "TCP/UDP/... Sessions\nFile: $Arg{infile}, "
	 . "Type: $TYPE, Created at: $the_date\n\n";
	print FILE @{$Index{Text}};
	close FILE;


	######################
	# --- image.html ---

	#
	#  Create HTML Image Index file to display images
	#
	open(FILE,">image.html") || die "ERROR24: creating index: $!\n";
	print FILE <<END_HTML;
<html>
<head><title>Chaosreader Image Report</title></head>
<body bgcolor="white" textcolor="black">
<font size=+3>Chaosreader Image Report</font><br>
<font size=+1>Created at: $the_date, Type: $TYPE</font><p>
<font size=+2>Images</font><br>
<table border=2>
END_HTML
	for ($html_index=0; $html_index <= $#{$Index{HTML}}; $html_index++) {
		$html_line = $Image{HTML}[$html_index]{info};
		$html_links = $Image{HTML}[$html_index]{links};
		next unless defined $html_links;
		print FILE "$html_line $html_links </td></tr>\n";
	}
	print FILE <<END_HTML;
</table><p>
</body>
</html>
END_HTML


	######################
	# --- getpost.html ---

	#
	#  Create HTML GETPOST Index file to show HTTP GETs and POSTs
	#
	open(FILE,">getpost.html") || die "ERROR25: creating index: $!\n";
	print FILE <<END_HTML;
<html>
<head><title>Chaosreader GET/POST Report</title></head>
<body bgcolor="white" textcolor="black">
<font size=+3>Chaosreader GET/POST Report</font><br>
<font size=+1>Created at: $the_date, Type: $TYPE</font><p>
<font size=+2>HTTP GETs and POSTs</font><br>
<table border=2>
END_HTML
	for ($html_index=0; $html_index <= $#{$GETPOST{HTML}}; $html_index++) {
		$html_line = $GETPOST{HTML}[$html_index]{info};
		$html_links = $GETPOST{HTML}[$html_index]{query};
		next unless defined $html_links;
		print FILE "$html_line $html_links </td></tr>\n";
	}
	print FILE <<END_HTML;
</table><p>
</body>
</html>
END_HTML

   }
}



# Create_Index_Master - Create the HTML and text master index files. This 
#	reads @Master and creates the files on disk. #21
#
sub Create_Index_Master {
   #debug
   print "\n Create_Index_Master subroutine called \n" unless $Arg{quiet};

   my ($start,$end,$dir,$file,$index,$duration);

   if ($Arg{output_index}) {

	#
	#  Create most recent link
	#

	$dir = $Master[$#Master]{dir};
	$recentname = "most_recent_index";
	unlink("$recentname");
	# don't die on symlink error, it's not essential
	symlink("$dir","$recentname");

	#
	#  Create HTML Index file containing all reports
	#
	open(FILE,">index.html") || die "ERROR26: creating index: $!\n";
	print FILE <<END_HTML;
<html>
<head><title>Chaosreader Master Index</title></head>
<body bgcolor="white" textcolor="black" vlink="blue">
<font size=+3>Chaosreader Master Index</font><br>
<font size=+1>Created at: $the_date, Type: $TYPE</font><p>
<a href="$recentname/index.html"><font color="red">
<b>Most Recent Report</b></font></a> 
 - Click here for the most recent index, and click reload for updates.<p>
<font size=+2>Chaosreader Reports</font><br>
<table border=2>
END_HTML
	for ($index=0; $index <= $#Master; $index++) {
		$start = $Master[$index]{starttime};
		$end = $Master[$index]{endtime};
		$dir = $Master[$index]{dir};
		$file = $Master[$index]{file};
		$size = $Master[$index]{size};
		$duration = $Master[$index]{duration};
		$html_line = "<tr><td><i>". ($index+1) . "</i></td>" .
		 "<td><b>$start</b></td><td><b>$end</b></td>\n" .
		 "<td>$duration s</td>" . "<td><font color=\"green\"> " .
		 "$size bytes</font></td>" .
		 "<td><a href=\"$dir/index.html\">$dir/$file</a></td></tr>\n";
		print FILE "$html_line </td></tr>\n";
	}
	print FILE <<END_HTML;
</table><p>
<font size=+2>IP Count</font><br>
<table border=2>
END_HTML
	foreach $IP (sort {$CountMaster{IP}{$b} <=> $CountMaster{IP}{$a}} 
	 keys %{$CountMaster{IP}}) {
		print FILE "<tr><td>$IP</td><td>$CountMaster{IP}{$IP}" .
		 "</td></tr>\n";
	}
	print FILE <<END_HTML;
</table><p>
<font size=+2>TCP Port Count</font><br>
<table border=2>
END_HTML
	foreach $port (sort {$CountMaster{TCPport}{$b} <=> 
	 $CountMaster{TCPport}{$a}} keys %{$CountMaster{TCPport}}) {
		$port_text = $Services_TCP{$port} || $port || "0";
		print FILE "<tr><td>$port_text</td><td>" .
		 "$CountMaster{TCPport}{$port}</td></tr>\n";
	}
	print FILE <<END_HTML;
</table><p>
<font size=+2>UDP Port Count</font><br>
<table border=2>
END_HTML
	foreach $port (sort {$CountMaster{UDPport}{$b} <=> 
	 $CountMaster{UDPport}{$a}} keys %{$CountMaster{UDPport}}) {
		$port_text = $Services_UDP{$port} || $port || "0";
		print FILE "<tr><td>$port_text</td><td>" . 
		 "$CountMaster{UDPport}{$port}</td></tr>\n";
	}
	print FILE <<END_HTML;
</table><p>
<font size=+2>IP Protocol Count</font><br>
<table border=2>
END_HTML
	foreach $protocol (sort {$CountMaster{IPprotocol}{$b} <=> 
	 $CountMaster{IPprotocol}{$a}} keys %{$CountMaster{IPprotocol}}) {
		$protocol_text = $IP_Protocols{$protocol};
		print FILE "<tr><td>$protocol_text</td><td>" .
		 "$CountMaster{IPprotocol}{$protocol}</td></tr>\n";
	}
	print FILE <<END_HTML;
</table><p>
<font size=+2>Ethernet Type Count</font><br>
<table border=2>
END_HTML
	foreach $type (sort {$CountMaster{EtherType}{$b} <=>
	 $CountMaster{EtherType}{$a}} keys %{$CountMaster{EtherType}}) {
		print FILE "<tr><td>$type</td><td>" .
		 "$CountMaster{EtherType}{$type}</td></tr>\n";
	}
	print FILE <<END_HTML;
</table>
</body>
</html>
END_HTML
	
	# 
	#  Create Text index file
	#
	open(FILE,">index.text") || die "ERROR27: creating index: $!\n";
	print FILE "Master Indexes\nCreated at: $the_date, Type: $TYPE\n\n";
	for ($index=0; $index <= $#Master; $index++) {
		$start = $Master[$index]{starttime};
		$end = $Master[$index]{endtime};
		$dir = $Master[$index]{dir};
		$file = $Master[$index]{file};
		$size = $Master[$index]{size};
		$duration = $Master[$index]{duration};
		printf FILE "%-25s %3s s %8s b  %s\n",$start,$duration,
		 $size,"$dir/index.text";
	}
	close FILE;


	# 
	#  Create index.file for redos
	#
	open(FILE,">index.file") || die "ERROR28: creating index: $!\n";
	for ($index=0; $index <= $#Master; $index++) {
		$dir = $Master[$index]{dir};
		$file = $Master[$index]{file};
		$start = $Master[$index]{starttime};
		$end = $Master[$index]{endtime};
		$duration = $Master[$index]{duration};
		print FILE "$dir\t$file\t$duration\t$start\t$end\n";
	}
	close FILE;
   }
}


# Create_Log_Files - create log files such as the HTTP log. #22
#
sub Create_Log_Files {
    #debug
    print "\n Create_Log_Files subroutine called \n" unless $Arg{quiet};

	#BDG some memory debug
	#system("pmap -x $$");

	#
	#  Create HTTPlog.text
	#
	open(FILE,">httplog.text") || die "ERROR29: creating HTTP log: $!\n";

	foreach $time (sort { $a <=> $b }(keys (%{$HTTPlog{time}}))) {
		print FILE $HTTPlog{time}{$time};
	}

	close FILE;
}



# File_Type - return file extension for given data, else "data". #23
#
sub File_Type {
    #debug
    print "\n File_Type subroutine called \n" unless $Arg{quiet};
    
	my $data = $_[0];
	my $type = "";

	if ($data =~ /^GIF8[7-9]/) 		{ $type = "gif"; }
	elsif ($data =~ /^\377.....(JPEG|JFIF)/) 	{ $type = "jpeg"; }
	elsif ($data =~ /^PK\003\004/) 		{ $type = "zip"; }
	elsif ($data =~ /^\%PDF/) 		{ $type = "pdf"; }
	elsif ($data =~ /^\037\213/) 		{ $type = "gz"; }
	elsif ($data =~ /^BZh/) 		{ $type = "bz2"; }
	elsif ($data =~ /^\177ELF/) 		{ $type = "elf"; }
	elsif ($data =~ /^\%!/) 		{ $type = "ps"; }
	elsif ($data =~ /<html>/i) 		{ $type = "html"; }
	else { $type = "data"; }

	return $type;
}


# Is_Image - returns true if extension is for an image. #24
#
sub Is_Image {
    #debug
    print "\n Is_Image subroutine called \n" unless $Arg{quiet};
	
    my $ext = shift;

	return 1 if ($ext eq "jpeg");
	return 1 if ($ext eq "gif");

	return 0;
}


# Desex_HTML - Removes HTML tags ("<" and ">") from data, so that it no 
#		longer interferes when printed as HTML. #25
#
sub Desex_HTML {
    #debug
    print "\n Desex_HTML subroutine called \n" unless $Arg{quiet};
    
	### Input
	my $data = shift;

	### Process
	# remove "<" and ">"s
	$data =~ s/</&lt;/g;
	$data =~ s/>/&gt;/g;

	### Return
	return $data;
}



# Process_BothHTML - Process the HTML 2-way session. Remove binary junk
#			that dosen't render well in a browser. #26
#
sub Process_BothHTML {
    #debug
    print "\n Process_BothHTML subroutine called \n" unless $Arg{quiet};
        
	### Input
	my $type = shift;
	my $session_id = shift;
	my $plain = shift;
	my $wrapped = "";
	my $index = 0;
	my $counter = 0;
	my $intag = 0;
	my ($char,$data);

	if ($type eq "TCP") {
		$data = $TCP{id}{$session_id}{BothHTML};
	} elsif ($type eq "UDP") {
		$data = $UDP{id}{$session_id}{BothHTML};
	} elsif ($type eq "ICMP") {
		$data = $ICMP{time}{$session_id}{BothHTML};
	}

	### Process (order dependant)
	$data =~ s/font color="red">     \0</font color="red"></g;
	$data =~ tr/\040-\176\n\r\f/./c;		# max 376, was 245
	if (defined $plain) {
	   # This is a plain style of line wrap
	   $data =~ s/([^\n\f<>]{$WRAP})/$&\n/g;
	} else {
	   # This is a fancy line wrap, a green ">" starts the wrapped lines
	   $data =~ s/([^\n\f<>]{$WRAP})/$&\n<font color="green">&gt;<\/font>/g;
	}

	### Save
	if ($type eq "TCP") {
		$TCP{id}{$session_id}{BothHTML} = $data;
	} elsif ($type eq "UDP") {
		$UDP{id}{$session_id}{BothHTML} = $data;
	} elsif ($type eq "ICMP") {
		$ICMP{time}{$session_id}{BothHTML} = $data;
	}

}

# Process_This_HTML - Process the HTML 2-way session. Remove binary junk
#			that dosen't render well in a browser. #27
#
sub Process_This_HTML {
    #debug
    print "\n Process_This_HTML subroutine called \n" unless $Arg{quiet};
    
	### Input
	my $data = shift;
	my $plain = shift;
	my $wrapped = "";
	my $index = 0;
	my $counter = 0;
	my $intag = 0;
	my ($char);

	### Process (order dependant)
	$data =~ s/font color="red">     \0</font color="red"></g;
	$data =~ tr/\040-\176\n\r\f/./c;		# max 376, was 245
	if (defined $plain) {
	   # This is a plain style of line wrap
	   $data =~ s/([^\n\f<>]{$WRAP})/$&\n/g;
	} else {
	   # This is a fancy line wrap, a green ">" starts the wrapped lines
	   $data =~ s/([^\n\f<>]{$WRAP})/$&\n<font color="green">&gt;<\/font>/g;
	}

	return $data;
}


# Process_Hex - Create the coloured HTML 2-way hex dump, and a text dump.
#		For code reuse it uses it's own data structure %Hex.
#		(Originally used %TCP{id}{$session_id}{hex}). #28
#
sub Process_Hex {
    #debug
    print "\n Process_Hex subroutine called \n" unless $Arg{quiet};
        
	### Input
	my $type = shift;
	my $session_id = shift;
	my $data = shift;
	my $colour = shift;
	my $pos = $Hex{$type}{$session_id}{pos};
	my $offset = $Hex{$type}{$session_id}{offset};
	my $hexhtml = $Hex{$type}{$session_id}{hexhtml};
	my $viewhtml = $Hex{$type}{$session_id}{viewhtml};
	my $hextext = $Hex{$type}{$session_id}{hextext};
	my $viewtext = $Hex{$type}{$session_id}{viewtext};
	my (@Bytes,$byte,$view,$view2);
	

	$pos = 1 unless defined $pos;
	$offset = 0 unless defined $offset;
	$hexhtml .= "<font color=\"$colour\">";
	$viewhtml .= "<font color=\"$colour\">";

	### Process
	@Bytes = unpack("C*",$data);
	foreach $byte (@Bytes) {
		$view = chr($byte);
		$view =~ tr/\040-\176/./c;
		$view2 = $view;
		$view2 =~ s/</&lt;/g;
		$view2 =~ s/>/&gt;/g;
		$viewhtml .= $view2;
		$viewtext .= $view;
		$hexhtml .= sprintf("%2.2x",$byte);
		$hextext .= sprintf("%2.2x",$byte);
		$pos++;
		if ($pos > 16) {
			### Save text version
			$Hex{$type}{$session_id}{text} .= 
			 sprintf("%6.08x",$offset) . "  $hextext  $viewtext\n";

			### Save HTML version
			$Hex{$type}{$session_id}{HTML} .= 
			 '<font color="green">' . sprintf("%6.08x",$offset) . 
			 "</font>  $hexhtml  $viewhtml\n";

			$pos = 1;
			$offset += 16;
			$hexhtml = "</font><font color=\"$colour\">";
			$viewhtml = "</font><font color=\"$colour\">";
			$hextext = $viewtext = "";
		}
		if ( ($pos != 1) && (($pos %2) == 1) ) {
			$hexhtml .= " ";
			$hextext .= " ";
		}
	}
	$hexhtml .= "</font>";
	$viewhtml .= "</font>";

	$Hex{$type}{$session_id}{pos} = $pos;
	$Hex{$type}{$session_id}{offset} = $offset;
	$Hex{$type}{$session_id}{hexhtml} = $hexhtml;
	$Hex{$type}{$session_id}{viewhtml} = $viewhtml;
	$Hex{$type}{$session_id}{hextext} = $hextext;
	$Hex{$type}{$session_id}{viewtext} = $viewtext;
}



# Process_Hex_Finish - Finish the hex dumps. #29
#
sub Process_Hex_Finish {
    #debug
    print "\n Process_Hex_Finish subroutine called \n" unless $Arg{quiet};
    
	### Input
	my $type = shift;
	my $session_id = shift;
	my $pos = $Hex{$type}{$session_id}{pos};
	my $offset = $Hex{$type}{$session_id}{offset};
	my $hexhtml = $Hex{$type}{$session_id}{hexhtml};
	my $viewhtml = $Hex{$type}{$session_id}{viewhtml};
	my $hextext = $Hex{$type}{$session_id}{hextext};
	my $viewtext = $Hex{$type}{$session_id}{viewtext};
	my ($short);

	return unless defined $pos;
	return if $pos == 1;

	$short = 39 - length($hextext);
	$hexhtml .= " " x $short;
	$hextext .= " " x $short;

	### Save text version
	$Hex{$type}{$session_id}{text} .= 
	 sprintf("%6.08x",$offset) . "  $hextext  $viewtext\n";

	### Save HTML version
	$Hex{$type}{$session_id}{HTML} .= 
	 '<font color="green">' . sprintf("%6.08x",$offset) . 
	 "</font>  $hexhtml  $viewhtml\n";

}


# Generate_X11_HTML - fetch the text from an X11 session and save
# 	as bidirectional 2-way coloured HTML.
#
# Todo: check if a text or keypress event can be split during 
#  transmission and add code similar to X11 replay to handle this. #30
#
sub Generate_X11_HTML {
    #debug
    print "\n Generate_X11_HTML subroutine called \n" unless $Arg{quiet};
    
	my ($filename,$data,$copy,$xcode,$xbyte,$xlength,$xrest,$d,
	 $xlv,$xvalue,$pad,$y,$yold,$chars,$colour,$session_data,
	 $service_name,$colourold,$store,$keytype,$gotsome);
	my @Times;

	$session_data = "";

	### Input
	my $session_id = shift;
	$data = "";
	$service_name = "X11";

	### Processing
	my $session_text = $session_id;
	$session_text =~ s/,/ <-> /;

	### Fetch raw data
	$xserver = &TCP_Follow_RawA($session_id);

	#
	#  Determine endian of this transfer.
	#
	($xjunk,$xvalue,$xjunk) = unpack('nna*',$xserver);
	#
	#  Create aliases for "n" and "N".
	#
	if ($xvalue < 256) {
		$n = "n"; $N = "N";
	} else {
		$n = "v"; $N = "V";
	}
	#
	#  Determine keymap style - see &Set_X11_KeyCodes()
	#
	if ($xserver =~ 
	 /q...Q.*w...W.*e...E.*r...R.*t...T.*y...Y.*u...U.*i...I.*o...O.*p/) {
		$keytype = "linux";
	} else {
		$keytype = "sun";
	}

	#
	#  Fetch data from both directions, sorting on timestamps
	#
	@Times = sort{$a <=> $b} (keys %{$TCP{id}{$session_id}{time}});

	#
	# --- Main Loop ---
	#
	# (this needs to be a for loop!)
	for ($i=0; $i <= $#Times; $i++) {
	   $time = $Times[$i];

	   ### Fetch X11 data and direction as a colour
	   if (defined $TCP{id}{$session_id}{time}{$time}{dir}) {
		$copy = $TCP{id}{$session_id}{time}{$time}{data};
		if ($TCP{id}{$session_id}{time}{$time}{dir} eq "A") {
			$colour = "red";
		} else {
			$colour = "blue";
		}
	   }

	   $xrest = $copy;
	   #
	   #  Process through X11 codes
	   #
	   while (length($xrest) > 0) {
		### Fetch xcode and other values
		($xcode,$xbyte,$xlength,$xrest) = unpack("CC${n}a*",$xrest);
		$chars = "";

		#
		#  Fetch code values from $xrest, and trim
		#  $xrest. For most requests, the value length
		#  is a field (bytes 3,4) except for XErrors 
		#  (code 0) where the total length is always 32.
		#
		if ($xcode == 0) {
			$xlv = 28;
		} else {
			$xlv = ($xlength - 1) * 4;
			$xlv = -$xlv if $xlv < 0;
		}

		### Fetch values for this xcode
		($xvalue,$xrest) = unpack("a${xlv}a*",$xrest); 

		$store = 0;

		#
		#  Process a draw text event (76, 77)
		#
		if (($colour eq "blue") && (($xcode == 76)||($xcode == 77))) {
			# Check if this is a xImageText16Req
			if ($xcode == 77) { $xbyte *= 2; }

			($pad,$y,$chars) = unpack("a10${n}a$xbyte",$xvalue);
			if ($yold != $y) { $chars = "\n$chars"; }
			$chars =~ s/\0//g;

			$store = 1;
			$yold = $y;
		}

		#
		#  Process a key pressed event (2)
		#
		if (($colour eq "red") && ($xcode = "2")) {
			($pad,$caps,$pad) = unpack("a24${n}a*",$xvalue);

			#
			#  Translate the X11 KeyCode to the actual char
			#  (try "xmodmap -pke")
			#
			$chars = $KeyCode{$keytype}{$caps}{$xbyte};

			### Don't keep red \n's for neatness (keep blue ones)
			unless ($chars eq "\n") {
				$store = 1;
			}
		}
		
		#
		#  Process a text scroll event (by using 62 - copy area)
		#
		if (($colour eq "blue") && ($xcode == 62)) {
			$chars = "\n";
			$store = 1;
		}

		### Store data
		if ($store) {
			if ($colour ne $colourold) {
				$session_data .= 
				 "</font><font color=\"$colour\">$chars";
			} else {
				$session_data .= $chars;
			}
			$colourold = $colour;
		}
	   }
	}

	$TCP{id}{$session_id}{BothHTML} = $session_data;
}


# Save_Both_HTML - Save bidirectional (coloured) data into a html file. #31
#
sub Save_Both_HTML {
    #debug
    print "\n Save_Both_HTML subroutine called \n" unless $Arg{quiet};
    
	my ($filename);

	### Input
	my $type = shift;
	my $session_id = shift;
	my $number = shift;
	my $service_name = shift;
	my $session_text = shift;
	my $numtext = sprintf("%04d",$number);
	my ($base,$raw);

	$session_text = $session_id unless defined $session_text;

	### Processing
	$session_text =~ s/,/ <-> /;

	### Checks
	$ext = "";
	$session_data = "";
	if ($type eq "TCP") {
	   $base = "session";
	   #
	   # Note, the following is similar code for TCP, UDP and ICMP.
	   # However UDP and ICMP use a simple strategy to store and fetch
	   # the processed HTML; whereas TCP uses a complex yet memory 
	   # efficient strategy. This is intentional - the way TCP has
	   # been stored has been tuned to reduce memory usage, as TCP has
	   # the bulk of the data (and the bulk of the memory problem). This 
	   # has not been necessary with UDP and ICMP (yet).
	   #
	   if ($TCP{id}{$session_id}{BothHTML} ne "") {
		#
		#  If the BothHTML report has already been calculated, fetch
		#
		$session_data = $TCP{id}{$session_id}{BothHTML};
	   } else {
		#
		#  Generate a BothHTML report by following packets by time
		#
		foreach $time (sort {$a <=> $b} 
		 (keys (%{$TCP{id}{$session_id}{time}}))) {
		   $raw = $TCP{id}{$session_id}{time}{$time}{data};
		   $raw = &Desex_HTML($raw);
		   next unless length($raw);
		   if ($TCP{id}{$session_id}{time}{$time}{dir} eq "A") {
			$session_data .= "<font color=\"blue\">$raw</font>";
		   } else {
			$session_data .= "<font color=\"red\">$raw</font>";
		   }
	   	}
	   	$session_data = &Process_This_HTML($session_data);
	   	$base = "session";
	   	if ($TCP{id}{$session_id}{Partial}) { $ext = ".partial"; } 
	   }

	} elsif ($type eq "UDP") {
		$base = "stream";
		$session_data = $UDP{id}{$session_id}{BothHTML};
		if ($UDP{id}{$session_id}{Partial}) { $ext = ".partial"; } 
	} elsif ($type eq "ICMP") {
		$base = "icmp";
		$session_data = $ICMP{time}{$session_id}{BothHTML};
		if ($ICMP{time}{$session_id}{Partial}) { $ext = ".partial"; } 
	} else {
		$base = "are_belong_to_us";
	}

	### Do nothing if there is no data ("26" is mostly due to colour tags)
	return unless ((defined $session_data)&&(length($session_data) > 26));

	### Output
        $filename = "${base}_${numtext}.${service_name}${ext}.html";
	open (OUT,">$filename") || die "ERROR30: file create, $filename: $!\n";
	binmode(OUT);
	print OUT "<HTML>\n<HEAD><TITLE>$number</TITLE></HEAD>" .
	 "<BODY bgcolor=\"white\">\n" .
	 "<H1>$service_name: $session_text</H1>\n" .
	 "<H2>File $Arg{infile}, Session $number</H2>\n" .
	 "<PRE WRAP=\"virtual\">\n" .
         $session_data . "</PRE>\n</BODY>\n</HTML>\n";
        close OUT;

	### Global Vars
	my $length = length($session_data);
	$Index{HTML}[$number] .= "<li><a href=\"$filename\">as_html</a></li>\n";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",
	 '"' , "   $filename","",$length);
}



# Save_Hex_HTML - Save bidirectional (coloured) hex data into a html file. #32
#
sub Save_Hex_HTML {
    #debug
    print "\n Save_Hex_HTML subroutine called \n" unless $Arg{quiet};
        
	my ($filename);

	### Input
	my $type = shift;
	my $session_id = shift;
	my $number = shift;
	my $service_name = shift;
	my $session_text = shift;
	my $session_data = $Hex{$type}{$session_id}{HTML};
	my $numtext = sprintf("%04d",$number);
	my ($base);

	$session_text = $session_id unless defined $session_text;
	$session_data = "" unless defined $session_data;
	

	### Processing
	$session_text =~ s/,/ <-> /;

	### Checks
	$ext = "";
	if ($type eq "TCP") {
		$base = "session";
		if ($TCP{id}{$session_id}{Partial}) { $ext = ".partial"; } 
	} elsif ($type eq "UDP") {
		$base = "stream";
		if ($UDP{id}{$session_id}{Partial}) { $ext = ".partial"; } 
	} elsif ($type eq "ICMP") {
		$base = "icmp";
		if ($ICMP{id}{$session_id}{Partial}) { $ext = ".partial"; } 
	}

	### Output
        $filename = "${base}_${numtext}.${service_name}${ext}.hex.html";
	open (OUT,">$filename") || die "ERROR31: file create, $filename: $!\n";
	binmode(OUT);
	print OUT "<HTML>\n<HEAD><TITLE>$number</TITLE></HEAD>" .
	 "<BODY bgcolor=\"white\">\n" .
	 "<H1>$service_name: $session_text</H1>\n" .
	 "<H2>File $Arg{infile}, Session $number</H2>\n" .
	 "<PRE WRAP=\"virtual\">\n" .
         $session_data . "</PRE>\n</BODY>\n</HTML>\n";
        close OUT;

	### Global Vars
	my $length = length($session_data);
	$Index{HTML}[$number] .= "<li>";
	$Index{HTML}[$number] .= "<a href=\"$filename\">hex</a></li>\n";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",
	 '"' , "   $filename","",$length);
}



# Save_Hex_Text - Save bidirectional hex data into a text file. #33
#
sub Save_Hex_Text {
    #debug
    print "\n Save_Hex_Text subroutine called \n" unless $Arg{quiet};
        
	my ($filename);

	### Input
	my $type = shift;
	my $session_id = shift;
	my $number = shift;
	my $session_text = shift;
	my $session_data = $Hex{$type}{$session_id}{text};
	my $numtext = sprintf("%04d",$number);
	my ($base);

	$session_text = $session_id unless defined $session_text;
	$session_data = "" unless defined $session_data;

	### Processing
	$session_text =~ s/,/ <-> /;

	### Checks
	$ext = "";
	if ($type eq "TCP") {
		$base = "session";
		if ($TCP{id}{$session_id}{Partial}) { $ext = ".partial"; } 
	} elsif ($type eq "UDP") {
		$base = "stream";
		if ($UDP{id}{$session_id}{Partial}) { $ext = ".partial"; } 
	} elsif ($type eq "ICMP") {
		$base = "icmp";
		if ($ICMP{id}{$session_id}{Partial}) { $ext = ".partial"; } 
	}

	### Output
        $filename = "${base}_${numtext}.${service_name}${ext}.hex.text";
	open (OUT,">$filename") || die "ERROR32: file create, $filename: $!\n";
	binmode(OUT);
	print OUT "$service_name: $session_text\n" .
	 "File $Arg{infile}, Session $number\n\n$session_data\n";
        close OUT;

	### Global Vars
	my $length = length($session_data);
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",
	 '"' , "   $filename","",$length);
}


# Save_FTP_File - Save files from an active FTP session. #34
#
sub Save_FTP_File {
    #debug
    print "\n Save_FTP_File subroutine called \n" unless $Arg{quiet};
    
	my ($filename,$ftp_data,$length);
	my $session_id = shift;
	my $number = shift;
	my $numtext = sprintf("%04d",$number);
	my $service_name = "ftp-data";

	### Input
	$ftp_data = &TCP_Follow_RawB($session_id);
	if (! defined $ftp_data) {
		$ftp_data = &TCP_Follow_RawA($session_id);
	}

	### Checks
	$ftp_type = &File_Type($ftp_data);
	if ($TCP{id}{$session_id}{Partial}) { $ext = ".partial"; } 
	 else { $ext = ""; }

	### Output
        $filename = "session_${numtext}.part_01.$service_name${ext}.$ftp_type";
        open (OUT,">$filename") || die "ERROR33: file create, $filename: $!\n";
	binmode(OUT);		# for backward OSs
        print OUT $ftp_data;
        close OUT;

	### Global Vars
	$length = length($ftp_data);
	$Index{HTML}[$number] .= 
	 "<li><a href=\"$filename\">$filename</a> $length bytes</li>\n";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",
	 '"' , "   $filename","",$length);
	if (&Is_Image($ftp_type)) {
		$Image{HTML}[$number]{links} .= 
		 "<img src=\"$filename\"> ";
		$Image{notempty} = 1;
	}
}

# NOTE On Replays
#
# The essence of these is to playback the client/server data so that
# the original session can be replayed. There are two styles,
# 	
# Text Replays. These playback the text component to the application
# data to the screen. These usally work well. The actual text data is not 
# cleaned up in any way, so to preserve escape sequences necessary to
# redisplay in the original style. Eg, telnet.
#
# GUI Replays, or Server/Client Replays. These often use TCP/IP to send
# the data back to the server or client to playback the session. These
# are less robust, mainly becuase negotiation can occur slightly differently 
# causing nothing to be displayed. There is code here to redo the 
# negotiation - but it is very difficult for this to be 100% robust.
# The main reasons the GUI replays fail are colour depth mismatch
# and dropped packets. Eg, X11.
#
# Both styles print the binary data within single quotes ' '. This 
# creates perl programs that can't be "cat" (use cat -vet), or edited
# in vi (use vim) due to the raw binary data. A neater style would be to
# translate the binary data into octal or hex text streams, eg
# 'print "\015\012\087\012"'... Currently this is not used, as it would 
# roughly increase the file size by a factor of 4. However plopping
# data in the middle of perl programs creates problems of it's own
# (see the unusual seds). At some point I may opt for the easier,
# although lengthier, method.


# Save_Session_Replay - Save a replay program for this session. eg, telnet.
# #35
sub Save_Session_Replay {
    #debug
    print "\n Save_Session_Replay subroutine called \n" unless $Arg{quiet};
    
	my ($filename,$duration,$time);
	my $session_id = shift;
	my $number = shift;
	my $service_name = shift;
	my $numtext = sprintf("%04d",$number);

	### Output
	$filename = "session_${numtext}.${service_name}.replay";
	$duration = ($TCP{id}{$session_id}{EndTime} - 
	 $TCP{id}{$session_id}{StartTime});
	$duration = sprintf("%.0f",$duration);
	open (REPLAY,">$filename") || 
	 die "ERROR34: creating $filename $!\n";
	binmode(REPLAY);	# for backward OSs

	#
	#  Create a perl program, that when run itself will print out
	#  the contents of the server 1-way stream, with pauses based on
	#  the packet arrival times (replay the session in realtime).
	#
	print REPLAY "#!$PERL\n";
	print REPLAY <<'END';
#
# This is a telnet/login replay program. It will replay a session using
# the timestamps from the packet log.
#
# USAGE: run the script as normal. You can provide a factor as an
#	argument, eg "2" to run twice as fast, or "0.5" to run
#	at half time. eg,
# 		./session_0002.telnet.replay 2
#
# Auto generated by Chaosreader.
#
$| = 1;
$factor = $ARGV[0] || 1;
sub ms {
	$ms = shift;
	$ms = $ms / $factor;
	select(undef, undef, undef, $ms);
}
END

	#
	#  Sort the data on the timestamps, calculating timestamp differences
	#  to record in the replay program.
	#
	@Times = ();
	foreach $time (keys (%{$TCP{id}{$session_id}{time}})) {
		if ($TCP{id}{$session_id}{time}{$time}{dir} eq "A") {
			push(@Times,$time) 
		}
	}
	@Times = sort { $a <=> $b } @Times;

	for ($i=0; $i <= $#Times; $i++) {		# required

		### Calculate time diff if possible
		if ($i == $#Times) {
			$timediff = 0;
		} else {
			$timediff = $Times[$i+1] - $Times[$i];
			if ($timediff < 0) { $timediff = 0; }
		}
		$time = $Times[$i];

		### Fetch data from mem
		$data = $TCP{id}{$session_id}{time}{$time}{data};

		#
		#  Clean the data a little (order important)
		#
		$data =~ s/\\/\\\\/g;	# backslash the backslashes
		$data =~ s/'/\\'/g;	# backslash single quotes

		#
		#  Now output the data in the replay program
		#
		print REPLAY "print '" . $data . "';\n";

		#
		#  This causes the replay program to pause
		#
		print REPLAY "ms($timediff);\n";
	}
	close REPLAY;

	### Better make it executable
	chmod (0755, "$filename");

	### Global Vars
	$Index{HTML}[$number] .= "<li><a href=\"$filename\">$filename" .
	 "</a> $duration seconds</li>\n";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s seconds\n",
	 '"' , "   $filename","",$duration);
}


# Save_Session_textSSH_files - Save a replay program to display the SSH
#	session in a text format, a html form of this, and a key delay
#	data file.
#
# The program "sshkeydata" will take the key delay data file and estimate
# the original typed commands. (It also needs a key delay data file 
# from a plaintext session such as telnet, which is generated by the
# Save_Session_Keydata subroutine).
#
# This has been designed with SSH ver 2 in mind. #36
#
sub Save_Session_textSSH_files {
    #debug
    print "\n Save_Session_textSSH subroutine called \n" unless $Arg{quiet};
    
	my ($filename1,$filename2,$filename3,$duration,$time,$data,$length,
	 $time0,$time1,$time2,$data0,$data1,$data2,$length0,$length1,$length2,
	 $dir0,$dir1,$dir2,$timediff,$timediff2,$outtime,$outsize,$datah,
	 $data00);
	my $session_id = shift;
	my $number = shift;
	my $service_name = shift;
	my $session_text = shift;
	my $numtext = sprintf("%04d",$number);
	my $delay = ""; 		# a text list of key delays
	my $html = "";			# a html form of output
	my $bytes = 0;			# data bytes of the connection
	my $minsize;			# The min client packet size
	my $state;

	$duration = ($TCP{id}{$session_id}{EndTime} - 
	 $TCP{id}{$session_id}{StartTime});
	$duration2 = sprintf("%.2f",$duration);
	$duration = sprintf("%.0f",$duration);

	### Output 
	$filename1 = "session_${numtext}.text${service_name}.replay";
	open (REPLAY,">$filename1") || 
	 die "ERROR35: creating $filename1 $!\n";
	binmode(REPLAY);	# for backward OSs

	#
	#  Create a perl program that replays details of the original
	#  SSH session. We print the direction of traffic and size, 
	#  paused using the original delays. 
	#
	print REPLAY "#!$PERL\n";
	print REPLAY <<'END';
#
# This is a text SSH replay program. It will replay details of the 
# original SSH session using timestamps from the packet capture log.
#
# USAGE: run the script as normal. You can provide a factor as an
#	argument, eg "2" to run twice as fast, or "0.5" to run
#	at half time. eg,
# 		./session_0002.textSSH.replay 2
#
# Auto generated by Chaosreader.
#
$| = 1;
$factor = $ARGV[0] || 1;
sub ms {
	$ms = shift;
	$ms = $ms / $factor;
	select(undef, undef, undef, $ms);
}
print <<'SUBEND';
SSH text analysis replay
------------------------
"*" is client traffic (including keystrokes), "." is the return text.
A number is a multiple of the previous char, eg ".32" is 32 return chars.

SUBEND
END

	#
	#  Sort the data on the timestamps, calculating timestamp differences
	#  to record in the replay program.
	#
	@Times = ();
	%PacketSize = ();
	foreach $time (keys (%{$TCP{id}{$session_id}{time}})) {
		if (length($TCP{id}{$session_id}{time}{$time}{data}) == 0) {
			next;
		}
		push(@Times,$time);
		if ($TCP{id}{$session_id}{time}{$time}{dir} eq "B") {
			### Frequency count sent sizes
			$data = $TCP{id}{$session_id}{time}{$time}{data};
			$length = length($data);
			$PacketSize{$length}++ if $length < 100;
		}
	}
	@Times = sort { $a <=> $b } @Times;
	$outtime = $Times[0];
	$outsize = 0;

	#
	#  Determine the client min size - this is the minimum length of 
	#  a data packet, eg a keystroke.
	#
	foreach $length (sort {$PacketSize{$b} <=> $PacketSize{$a}}
	 (keys(%PacketSize))) {
		$minsize = $length;
		last; 
	}

	# The very first packet
	$data00 = $TCP{id}{$session_id}{time}{$Times[0]}{data};

	### Process data
	for ($i=0; $i <= $#Times; $i++) {		# required

	   ### Calculate time diff if possible
	   $time0 = $Times[$i];
	   $time1 = $Times[$i+1];
	   $time2 = $Times[$i+2];
	   $time3 = $Times[$i+3];
	   if ($i == $#Times) {
		$timediff1 = 0;
		$timediff2 = 0;
	   } else {
	   	$timediff1 = $time1 - $time0;
	   	$timediff2 = $time2 - $time0;
	   	if ($timediff1 < 0) { $timediff1 = 0; }
	   }
   
	   ### Fetch data from mem, "0" is this packet...
	   $data0 = $TCP{id}{$session_id}{time}{$time0}{data};
	   $data1 = $TCP{id}{$session_id}{time}{$time1}{data};
	   $data2 = $TCP{id}{$session_id}{time}{$time2}{data};
	   $dir0 = $TCP{id}{$session_id}{time}{$time0}{dir};
	   $dir1 = $TCP{id}{$session_id}{time}{$time1}{dir};
	   $dir2 = $TCP{id}{$session_id}{time}{$time2}{dir};
	   $dir3 = $TCP{id}{$session_id}{time}{$time3}{dir};
	   $length0 = length($data0);
	   $length1 = length($data1);
	   $length2 = length($data2);

	   # working variables
	   $bytes += $length0;
	   $length = $length0;
	   $data = $data0;

	   ##################
	   #  Process Data
	   #
	   #  This is designed for a command line SSH session and
	   #  the calculations are based on many assumptions. 
	   #
	   #  For example: if the client sends a small packet (which 
	   #  we'll assume is a keystroke) and the server responds
	   #  with large packets (beyond merely echoing the keystroke),
	   #  then we can assume that this keystroke was the enter key,
	   #  and the large response was the output of the command.
	   #
	   #  There are two states - keystrokes and output text. 
	   #
	   #  The follow code works well most of the time, and provides
	   #  meaningful results for non command line sessions.
	   #
	
	   #
	   # --- Server to Client ---
	   #
	   if ($dir0 eq "A") {
		if ($i > 3 || $data00 !~ /^ssh/i) {
			# a "." represents an encrypted server to client packet
			$data = ".";
			$html .= '<font color="blue">' . $data;
		} else {
			### Process initial plaintext negotiation
			
			# first we clean up the data,
			$data =~ tr/\040-\176/./c;
			$data =~ s/\\/\\\\/g;
			$data =~ s/'/\\'/g;
			$data .= "\n";
			$hdata = $data;
			$hdata = &Desex_HTML($hdata);

	   		# This is a fancy line wrap, adds a green ">"
	   		$hdata =~ 
		   s/([^\n\f<>]{$WRAP})/$&\n<font color="green">&gt;<\/font>/g;
			$html .= '<font color="blue">' . $hdata;
		}

		if ($state eq "output") {
		   if ($length0 > $minsize && $i > 3) {
			# This prints the length in the replay files
			# as a number following the symbol, 
			# eg ".60" would mean a "." with length 60.
			# length actually means size beyond minsize.
			$length -= $minsize;
			$data .= "$length";
			$html .= "$length";
			$outsize += $length;
		   }

		### Data -> Keystrokes
		if ($dir1 eq "B" && $length1 == $minsize) {
			# Process the transition from command output back
			# to keystrokes. 
			$data .= "\n";
			$html .= "\n";
			$delay .= "s $outsize\n";
			$delay .= sprintf("t %.6f\n",$time0 - $outtime);
			$delay .= "  \n";	# command delimiter
			$outsize = 0;
			$outtime = $time0;
			$state = "key";
		   }
		}
		$html .= '</font>';
	   }

	   #
	   # --- Client to Server ---
	   #
	   else {
		if ($i == 1) {
		   # PuTTY appears to have an unusual way to send keystrokes
		   # to the server, that differs to OpenSSH and Sun's SSH.
		   # Remember if this is a PuTTY session.
		   $sshtype = "putty" if $data =~ /PuTTY/;
		}

		### Keystroke
		if ($sshtype eq "") {
		   # If the client is sending a minsize packet and the server
		   # then responds, we assume this is a keystroke.
		   if ($length0 == $minsize && $dir1 eq "A") {
			$delay .= "k \n";
		   }
		} elsif ($sshtype eq "putty") {
		   # if the client is sending a minsize packet, followed by 
		   # another packet, then a reply packet, and then a server 
		   # response; we assume that this is a keystroke.
		   # (This processes PuTTY's doubled keystrokes).
		   if ($length0 == $minsize && $dir1 eq "B" && $dir2 eq "A") {
			$delay .= "k \n";
		   } 
		}

		### Process initial plaintext negotiation
		if ($i > 3 || $data00 !~ /^ssh/i) {
			# a "*" represents an encrypted client to server packet
			$data = "*";
			$html .= '<font color="red">' . $data;
		} else {
			### Process initial plaintext negotiation
			
			# first we clean up the data,
			$data =~ tr/\040-\176/*/c;
			$data =~ s/\\/\\\\/g;
			$data =~ s/'/\\'/g;
			$data .= "\n";
			$hdata = $data;
			$hdata = &Desex_HTML($hdata);

   			# This is a fancy line wrap, adds a green ">"
   			$hdata =~ 
		   s/([^\n\f<>]{$WRAP})/$&\n<font color="green">&gt;<\/font>/g;
			$html .= '<font color="red">' . $hdata;
		}

		### Keystroke -> Keystroke delay
	 	if ($sshtype eq "") {
		   if ($length0 == $minsize && $dir1 eq "A" && $dir2 eq "B" &&
		    $length2 == $minsize) {
			# If this is a keystroke packet, and the next packet 
			# is a response, and then another keystroke packet 
			# is sent; then measure the keystroke delay.
			$timediff2 = $time2 - $time0;
			$delay .= sprintf("d %.6f\n",$timediff2);
			$outsize = 0;
			$outtime = $time0;
		   }
		} elsif ($sshtype eq "putty") {
		   if ($length0 == $minsize && $dir1 eq "A" && $dir2 eq "B" && 
		    $length2 == $minsize && $dir3 eq "B") {
			# This is the same idea as the above, but processes
			# PuTTY's doubled keystrokes.
			$timediff2 = $time2 - $time0;
			$delay .= sprintf("d %.6f\n",$timediff2);
			$outsize = 0;
			$outtime = $time0;
		   }
		}

		if ($length0 > $minsize && $i > 3) {
			#
			# This prints the length in the replay files
			# as a number following the symbol, 
			# eg ".60" would mean a "." with length 60.
			# length actually means size beyond minsize.
			$length -= $minsize;
			$data .= "$length";
			$html .= "$length";
		}
		$html .= '</font>';

		### Keystrokes -> Data
		if ( ($length0 == $minsize &&
		 (($length1 + $length2) > ($minsize * 2))) ||
		 ($dir1 eq "A" && $dir2 eq "A") ) {
			$data .= "\n";
			$html .= "\n";
			#
			# "r" describes the response packet. This value
			# may or may not be meaningful depending on the 
			# SSH software.
			if ($length1 > $minsize) {
			   $delay .= "r 1\n";
			   $delay .= sprintf("p %.6f\n",$timediff1);
			} else {
			   $delay .= "r 2\n";
			   $delay .= sprintf("p %.6f\n",$timediff2);
			}
			$state = "output";
		}
	   }

	   ### Now output the data in the replay program
	   print REPLAY "print '" . $data . "';\n";

	   ### This causes the replay program to pause
	   print REPLAY "ms($timediff1);\n";
	}
	$speed = sprintf("%.2f",$bytes / (1024 * $duration));
	print REPLAY "print \"\n\n" .
	 "Summary: $duration2 seconds, $bytes bytes, $speed Kb/sec\\n\";";
	close REPLAY;

	### Better make it executable
	chmod (0755, "$filename1");

	#
	#  HTML version of the replay script
	#
	$filename2 = "session_${numtext}.text${service_name}.html";
	open (HTML,">$filename2") || 
	 die "ERROR36: Can't write to file, $filename2 $!\n";
	$html = "<html><head><title>SSH text analysis</title></head>\n" .
	"<body bgcolor=\"white\">" .
	"<H1>$service_name: $session_text</H1>\n" .
	"<H2>File $Arg{infile}, Session $number</H2>\n" .
	"<h3>$duration2 seconds, $bytes bytes, $speed Kb/sec</h3>\n" . 
	'"*" is client traffic (including ' .
	'keystrokes), "." is the return ' .
	'text.<br>A number is a multiple of the previous char, eg ".32" ' .
	'is 32 return chars.<br>' .
	"\n<b><pre>$html</pre></b>\n</body>\n</html>\n";
	print HTML $html;
	close HTML;

	#
	#  Text Database of time delays between possible keystrokes
	#
	$filename3 = "session_${numtext}.text${service_name}.keydata";
	open (DELAY,">$filename3") || 
	 die "ERROR37: Can't write keydata file: $filename3 $!\n";
	$delay = "$delay  \n";
	print DELAY $delay;
	close DELAY;

	#
	#  Update Global Vars to remember new filenames
	#
	$Index{HTML}[$number] .= "<li><a href=\"$filename1\">$filename1" .
	 "</a> $duration seconds</li>\n";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s seconds\n",
	 '"' , "   $filename1","",$duration);
	$Index{HTML}[$number] .= "<li><a href=\"$filename2\">$filename2" .
	 "</a> </li>\n";
	$length = length($html);
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",
	 '"' , "   $filename2","",$length);
	$Index{HTML}[$number] .= "<li><a href=\"$filename3\">$filename3" .
	 "</a> </li>\n";
	$length = length($delay);
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",
	 '"' , "   $filename3","",$length);
}


# Save_Session_Keydata - Save a key delay data file to assist SSH analysis. 
#
# This code is intentionally designed to be similar to the SSH processing
# code, so that both their outputs can be compared. As a standalone
# subroutine this wouldn't make too much sense; instead bear in mind that
# I'd like the processing to mimic how SSH was processed. That way we
# run this on plenty of known text (telnet) and become familiar with
# exactly what will happen for the unknown text (SSH). #37
#
sub Save_Session_Keydata {
    #debug
    print "\n Save_Session_Keydata subroutine called \n" unless $Arg{quiet};
    
	my ($filename1,$filename2,$filename3,$duration,$time,$data,$length,
	 $time0,$time1,$time2,$data0,$data1,$data2,$length0,$length1,$length2,
	 $dir0,$dir1,$dir2,$timediff,$timediff2,$outtime,$outsize);
	my $session_id = shift;
	my $number = shift;
	my $service_name = shift;
	my $session_text = shift;
	my $numtext = sprintf("%04d",$number);
	my $delay = ""; 		# a text list of key delays
	my $minsize;			# The min client packet size
	my $state = "key";

	### Sort the data by timestamps
	@Times = ();
	%PacketSize = ();
	foreach $time (keys (%{$TCP{id}{$session_id}{time}})) {
		if (length($TCP{id}{$session_id}{time}{$time}{data}) == 0) {
			next;
		}
		push(@Times,$time);
	}
	@Times = sort { $a <=> $b } @Times;
	$outtime = $Times[0];
	$outsize = 0;
	$minsize = 1;				# known for telnet

	### Process data
	for ($i=0; $i <= $#Times; $i++) {		# required

	   ### Calculate time diff if possible
	   $time0 = $Times[$i];
	   $time1 = $Times[$i+1];
	   $time2 = $Times[$i+2];
	   if ($i == $#Times) {
		$timediff1 = 0;
		$timediff2 = 0;
	   } else {
		$timediff1 = $time1 - $time0;
		$timediff2 = $time2 - $time0;
		if ($timediff1 < 0) { $timediff1 = 0; }
	   }

	   ### Fetch data from mem, "0" is this packet...
	   $data0 = $TCP{id}{$session_id}{time}{$time0}{data};
	   $data1 = $TCP{id}{$session_id}{time}{$time1}{data};
	   $data2 = $TCP{id}{$session_id}{time}{$time2}{data};
	   $data0 = "\n" if $data0 eq "\r\n";
	   $data1 = "\n" if $data1 eq "\r\n";
	   $data2 = "\n" if $data2 eq "\r\n";
	   $data0 = "\n" if $data0 =~ /\r./;
	   $data1 = "\n" if $data1 =~ /\r./;
	   $data2 = "\n" if $data2 =~ /\r./;
	   $dir0 = $TCP{id}{$session_id}{time}{$time0}{dir};
	   $dir1 = $TCP{id}{$session_id}{time}{$time1}{dir};
	   $dir2 = $TCP{id}{$session_id}{time}{$time2}{dir};
	   $length0 = length($data0);
	   $length1 = length($data1);
	   $length2 = length($data2);

	   $length = $length0;
	   $data = $data0;

	   #
	   #  Process Data
	   #
	   if ($dir0 eq "A") {
		if ($state eq "output") {
			if ($length0 > $minsize) {
				$length -= $minsize;
				$outsize += $length;
			}

			### Data -> Keystrokes
			if ($dir1 eq "B" && $length1 == $minsize) {
				$delay .= "s $outsize\n";
				$delay .= sprintf("t %.6f\n",$time0 - $outtime);
				$delay .= "  \n";
				$outsize = 0;
				$outtime = $time0;
				$state = "key";
			}
		}
	   } else {
		### Keystroke
		if ($length0 == $minsize) {
			if ($data0 eq "\n") {
				$delay .= "k \\n\n";
			} else {
				$delay .= "k $data0\n";
			}
		}
		### Keystroke -> Keystroke delay
		if ($length0 == $minsize && $dir1 eq "A" && $dir2 eq "B" &&
		 $length2 == $minsize) {
			$timediff2 = $time2 - $time0;
			$delay .= sprintf("d %.6f\n",$timediff2);
			$outsize = 0;
			$outtime = $time0;
		}

		if ($length0 > $minsize) {
			$length -= $minsize;
		}

		### Keystrokes -> Data
		if ( ($length0 == $minsize &&
		 (($length1 + $length2) > ($minsize * 2))) ||
		 ($dir1 eq "A" && $dir2 eq "A") ) {
			if ($length1 > $minsize) {
			   $delay .= "r 1\n";
			   $delay .= sprintf("p %.6f\n",$timediff1);
			} else {
			   $delay .= "r 2\n";
			   $delay .= sprintf("p %.6f\n",$timediff2);
			}
			$state = "output";
		}
	   }
	}

	#
	#  Text Database of time delays between possible keystrokes
	#
	$filename3 = "session_${numtext}.${service_name}.keydata";
	open (DELAY,">$filename3") || 
	 die "ERROR38: A pink jelly hits you. You die. $filename3 $!\n";
	print DELAY "$delay  \n";
	close DELAY;

	#
	#  Update Global Vars to remember new filenames
	#
	$Index{HTML}[$number] .= "<li><a href=\"$filename3\">$filename3" .
	 "</a> </li>\n";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s\n",
	 '"' , "   $filename3","","");
}


# Save_Stream_Replay - Save a replay program for this stream. eg, dns. #38
#
sub Save_Stream_Replay {
    #debug
    print "\n Save_Stream_Replay subroutine called \n" unless $Arg{quiet};
    
	my ($filename,$duration);
	my $session_id = shift;
	my $number = shift;
	my $service_name = shift;
	my $numtext = sprintf("%04d",$number);

	### Output
	$filename = "stream_${numtext}.${service_name}.replay";
	$duration = ($UDP{id}{$session_id}{EndTime} - 
	 $UDP{id}{$session_id}{StartTime});
	$duration = sprintf("%.0f",$duration);
	open (REPLAY,">$filename") || 
	 die "ERROR39: creating $filename $!\n";
	binmode(REPLAY);	# for backward OSs

	#
	#  Create a perl program, that when run itself will print out
	#  the contents of the server 1-way stream, with pauses based on
	#  the packet arrival times (replay the stream in realtime).
	#
	print REPLAY "#!$PERL\n";
	print REPLAY <<'END';
#
# This is a UDP replay program. It will replay a stream using
# the timestamps from the packet log.
#
# USAGE: run the script as normal. You can provide a factor as an
#	argument, eg "2" to run twice as fast, or "0.5" to run
#	at half time. eg,
# 		./stream_0002.telnet.replay 2
#
# Auto generated by Chaosreader.
#
$| = 1;
$factor = $ARGV[0] || 1;
sub ms {
	$ms = shift;
	$ms = $ms / $factor;
	select(undef, undef, undef, $ms);
}
END

	#
	#  Sort the data on the timestamps, calculating timestamp differences
	#  to record in the replay program.
	#
	@Times = keys (%{$UDP{id}{$session_id}{time}});
	@Times = sort { $a <=> $b } @Times;

	for ($i=0; $i <= $#Times; $i++) {	# required

		### Calculate time diff if possible
		if ($i == $#Times) {
			$timediff = 0;
		} else {
			$timediff = $Times[$i+1] - $Times[$i];
			if ($timediff < 0) { $timediff = 0; }
		}
		$time = $Times[$i];

		### Fetch data from mem
		$data = $UDP{id}{$session_id}{time}{$time};
		delete $UDP{id}{$session_id}{time}{$time};

		#
		#  Clean the data a little (order important)
		#
		$data =~ s/\\/\\\\/g;	# backslash the backslashes
		$data =~ s/'/\\'/g;	# backslash single quotes

		#
		#  Now output the data in the replay program
		#
		print REPLAY "print '" . $data . "';\n";

		#
		#  This causes the replay program to pause
		#
		print REPLAY "ms($timediff);\n";
	}
	close REPLAY;

	### Better make it executable
	chmod (0755, "$filename");

	### Global Vars
	$Index{HTML}[$number] .= "<li><a href=\"$filename\">$filename" .
	 "</a> $duration seconds</li>\n";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s seconds\n",
	 '"' , "   $filename","",$duration);
}


# Save_Session_XReplay - Save a replay program for this session. eg, X11.
#	This processes far more of the X11 protocol than I was hoping.
#	(xscope and ethereal were used to analyse X11). #39
#
sub Save_Session_XReplay {
    #debug
    print "\n Save_Session_XReplay subroutine called \n" unless $Arg{quiet};
    
	my $session_id = shift;
	my $number = shift;
	my $service_name = shift;
	my $numtext = sprintf("%04d",$number);
	my ($filename,$duration,$xcode,$xres_old,$xrest,$xwnum,$xdiff,
	 $xlength,$xmsb,$xstart,$xjunk,$xvalue,$readnow,$data,$newdata,
	 $n,$N,$chars,$y,$timediff,$texttimediff,$checkdepth,$filename2,
	 $x11type);
	my @xWords;

	### Initials
	$xmsb = "";
	$readnow = 0;
	$xres_old = -1;
	$checkdepth = 0;

	#
	#  Output - Main X11 replay program
	#
	$filename = "session_${numtext}.${service_name}.replay";
	$duration = ($TCP{id}{$session_id}{EndTime} - 
	 $TCP{id}{$session_id}{StartTime});
	$duration = sprintf("%.0f",$duration);
	open (REPLAY,">$filename") || 
	 die "ERROR40: creating $filename $!\n";
	binmode(REPLAY);	# for backward OSs

	#
	#  Output - Text (keystroke replay)
	#
	$filename2 = "session_${numtext}.text${service_name}.replay";
	open (REPLAY2,">$filename2") || 
	 die "ERROR41: creating $filename2 $!\n";
	binmode(REPLAY2);	# for backward OSs


	#  --- textX11 ---
	#
	#  Create a perl program, that when run itself will print out
	#  the contents of the server 1-way stream, with pauses based on
	#  the packet arrival times (replay the session in realtime).
	#
	print REPLAY2 "#!$PERL\n";
	print REPLAY2 <<'END';
#
# This is an X11 text replay program. It will replay keystrokes and text
# of an X11 session using the timestamps from the packet log.
#
# USAGE: run the script as normal. You can provide a factor as an
#	argument, eg "2" to run twice as fast, or "0.5" to run
#	at half time. eg,
# 		./session_0002.textX11.replay 2
#
# Auto generated by Chaosreader.
#
$| = 1;
$factor = $ARGV[0] || 1;
sub ms {
	$ms = shift;
	$ms = $ms / $factor;
	select(undef, undef, undef, $ms);
}
END


	#  --- X11 ---
	#
	#  Create a perl program, that when run itself will print out
	#  the contents of the server 1-way stream, with pauses based on
	#  the packet arrival times (replay the session in realtime).
	#
	print REPLAY "#!$PERL\n";
	print REPLAY <<'END';
#
# This is a X11 replay program. It will replay a session using
# the timestamps from the packet log, and transpose the X11 protocol so
# that it can be redisplayed. You must have captured from the start
# of the connection for this to work.
#
# USAGE: ./session_0001.X11.replay [-d destination host] [-p port] factor 
#
#	just run the script as normal. You can provide a factor as an
#	argument, eg "2" to run twice as fast, or "0.5" to run
#	at half time. eg,
# 		./session_0002.X11.replay 2
#	a different host and port can be specified if needed. eg,
#		./session_0002.X11.replay -d 192.168.1.5 -p 6001
#
# PROBLEMS: you may need to authorise this connection to the X11 server
#	before it works. You could run "xhost +hostname" beforehand.
# 	The playback needs to have captured the start of the connection.
#	Check you support the same colour depth as the playback. And check
#	the playback file simply isn't too big! (more than 500 Kb is 
#	currently problematic).
#	
#
# Auto generated by Chaosreader.
#

use IO::Socket;
use Getopt::Std;

if ($ARGV[0] =~ /^-h$|^--help$/) { &help(); }

# Try fetching values from $DISPLAY
($hostdef,$portdef) = $ENV{DISPLAY} =~ /([^:]*):(\d*)/;
$hostdef = "127.0.0.1" if $hostdef eq "";
$portdef += 6000;

# Command line options take preference
&getopts('d:p:');
if (defined $opt_d) { $host = $opt_d; } else { $host = $hostdef; }
if (defined $opt_p) { $port = $opt_p; } else { $port = $portdef; }
$factor = $ARGV[0] || 1;
$DEBUG = 0;
$| = 1;

print "Chaosreader X11 Replay (experimental)\n\n";
print "Connecting to $host:$port\n";
print "(problems? try running \"xhost +hostname\" first).\n\n";


# --- Open Socket ---
#
$remote = IO::Socket::INET->new( Proto => "tcp",
				PeerAddr  => $host,
				PeerPort  => $port,
				);
unless ($remote) { die "ERROR42: Can't connect to X11 daemon on $host:$port"; }
$remote->autoflush(1);


# --- Subroutines ---
#

# ms - sleeps for specified milliseconds
#
sub ms {
	$ms = shift;
	$ms = $ms / $factor;
	select(undef, undef, undef, $ms);
}
# help - print help
#
sub help {
        open (MYSELF,"$0") || die "ERROR43: I can't see myself: $!\n";
        @Myself = <MYSELF>;
        close MYSELF;
        ### Print comment from top of code
        foreach $line (@Myself) {
                last if $line !~ /^#/;
                next if $line =~ m:^#!/usr/bin/perl:;
                $line =~ s/^#/ /;
                print $line;
        }
        print "\n";
        exit(0);
}
# R - recalculates and prints a resourse setting
#     The single character subroutine name saves on file space below.
#
sub R {
	#$offset = shift;
	#$new = $res + $offset;
	my $rid = shift;
	my $new;

	# final checks
	$diff = $rid - $ridbaseold;
	$diff = -$diff if $diff < 0;
	if ((($rid < $ridbaseold) && ($rid < 8196)) || ($diff > 8196)) {
	   if ($msb) { return pack('N',$rid); } 
		else { return pack('V',$rid); }
	}
	
	$new = $rid & $ridmaskold;
	$new = $new | $ridbase;
	if ($msb) { return pack('N',$new); } 
	     else { return pack('V',$new); }
}
# D - prints the new Drawable, usually the rootid.
#
sub D {
	my $rid = shift;
	
	# final checks
	if ($rid >= $ridbaseold) {
		# return mapped resource id
		return R($rid);
	}
	# return rootid
	if ($msb) { return pack('N',$rootid); } 
	     else { return pack('V',$rootid); }
}
# C - prints the new Colour map.
#
sub C {
	my $rid = shift;
	
	# final checks
	if ($rid >= $ridbaseold) {
		# return mapped resource id
		return R($rid);
	}
	# return colour map
	if ($msb) { return pack('N',$colour); }
	     else { return pack('V',$colour); }
}
# M - Returns a generic mapped id. Can be rootid, colour, or resource.
#     These are used in Xcodes involving a mask.
#
sub M {
	my $rid = shift;
	
	# final checks
	if ($rid >= $ridbaseold) {
		# return mapped resource id
		return R($rid);
	}
	# return rootid map
	if ($rid == $rootidold) {
	   if ($msb) { return pack('N',$rootid); } 
		else { return pack('V',$rootid); }
	}
	# return colour map
	if ($rid == $colourold) {
	   if ($msb) { return pack('N',$colour); } 
		else { return pack('V',$colour); }
	}
	# return other
	if ($msb) { return pack('N',$rid); } 
		else { return pack('V',$rid); }
}
# P - Check depth pixels, print warning if there is a mismatch.
#
sub P {
	my $depth = shift;
	if (! defined $Depth{$depth}) {
		print "\nWARNING: requested depth $depth may not be ". 
		 "supported by the server?\n";
	}
}
# debug - print out a value
#
sub debug {
	my $word = shift;
	my $num = shift;
	my $pack = pack("N",$num);
	print "$word: $num ",
	 sprintf("%2.2x%2.2x%2.2x%2.2x\n",unpack("C*",$pack));
}


# --- MAIN ---
#
print "Sending X11 traffic:";
END
	### Fetch raw data
	$xserver = &TCP_Follow_RawA($session_id);

	#
	#  Determine endian of this transfer. Reading the
	#  second short on MSB gives 11, and on LSB 2816
	#  (at least in testing). We split the difference 
	#  on 256 (is case there is a little variation).
	#
	($xjunk,$xvalue,$xjunk) = unpack('nna*',$xserver);
	#
	#  Create aliases for "n" and "N" so I can think
	#  in big endian.
	#
	if ($xvalue < 256) {
		$xmsb = 1;
		$n = "n";
		$N = "N";
	} else {
		$xmsb = 0;
		$n = "v";
		$N = "V";
	}
	my ($success,$major,$minor,$length,$release,$ridbase,
	 $ridmask,$mbsize,$vendor,$reqmax,$roots,$formats,$ibo,
	 $bbo,$bslu,$bslp,$keymin,$keymax,$pad,$rest) =
	 unpack("a2$n$n$n$N$N$N$N$n${n}CCCCCCCC${N}a*",$xserver);

	($x11type,$rest) = unpack("a${vendor}a*",$rest);
	$pad = ((4 - ($vendor % 4)) % 4);
	($junk,$rest) = unpack("a${pad}a*",$rest);

	foreach $i (1..$formats) {
		($junk,$rest) = unpack("a8a*",$rest);
	}
	($rootid,$colour,$junk) = unpack("$N${N}a*",$rest);

	#
	#  Sort the data on the timestamps, calculating timestamp differences
	#  to record in the replay program.
	#
	@Times = ();
	foreach $time (keys (%{$TCP{id}{$session_id}{time}})) {
		if ($TCP{id}{$session_id}{time}{$time}{dir} eq "B") {
			push(@Times,$time)
		}
	}
	@Times = sort { $a <=> $b } @Times;
	
	#
	# --- Main Loop ---
	#
	# (this needs to be a for loop!)
	for ($i=0; $i <= $#Times; $i++) {

		### Calculate time diff if possible
		if ($i == $#Times) {
			$timediff = 0;
		} else {
			$timediff = $Times[$i+1] - $Times[$i];
			# just in case,
			if ($timediff < 0) { $timediff = 0; }
		}
		$time = $Times[$i];
		$texttimediff += $timediff;

		### Fetch data from mem
		$data = $TCP{id}{$session_id}{time}{$time}{data};

		### If initial request was fetched,
		if ($readnow == 0) {
			### Populate $xstart with initial request
			$xstart .= $data;

			#
			#  This triggers the replay program to ask the X11
			#  server for the connection data - which
			#  needs to be processed so that various
			#  resource offsets can be used later on.
			#
			if (length($xstart) >= 12)  {
			   $readnow = 1;
			}

		} else {
		   #
		   #  Change resource offsets
		   #  (reads $data and writes to $data)
		   #
		   $xrest = $data;
		   $data = "";		# output stream of data & subs

		   #
		   #  Process through X11 codes
		   #
		   while (length($xrest) > 0) {
			($xcode,$xbyte,$xlength,$xrest) = 
			 unpack("CC${n}a*",$xrest);

			### Add xcode to output stream $data
			$d = pack("CC${n}",$xcode,$xbyte,$xlength);
			# the unusual seds
			$d =~ s/\\/\\\\/g;
			$d =~ s/'/\\'/g;
			$d =~ s/\015\012/'."\\015\\012".'/gs;
			$data .= $d;

			#
			#  Fetch code values from $xrest, and trim
			#  $xrest. For most requests, the value length
			#  is a field (bytes 3,4) except for XErrors 
			#  (code 0) where the total length is always 32.
			#
			if ($xcode == 0) {
				$xlv = 28;
			} else {
				$xlv = ($xlength - 1) * 4;
				$xlv = -$xlv if $xlv < 0;
			}
			while (length($xrest) < $xlv) { 
				# some more magic
				$i++;
				last if ($i > $#Times);

				$next = $Times[$i];

				### Fetch data from mem
				$xrest .=
				 $TCP{id}{$session_id}{time}{$next}{data};
			}

			($xvalue,$xrest) = unpack("a${xlv}a*",$xrest); 

			#$format = "%2.2x%2.2x " x ($xlv/2); 
			#printf("X$xcode: $xbyte,$xlength $format\n",
			# unpack("C*",$xvalue));   ### Debug
			
			$xwnum = 0;
			@xWords = unpack("${N}*",$xvalue);

			#
			#  If this is a text event, save the text to the
			#  textX11 replay program.
			#
			if (($xcode == 76) || ($xcode == 77)) {

				# Check if this is a xImageText16Req
				if ($xcode == 77) { $xbyte *= 2; }
				
				($pad,$y,$chars) = 
				 unpack("a10${n}a$xbyte",$xvalue);
				if ($yold != $y) { $chars = "\n$chars"; }

				### Clean the data a little (order important)
				$chars =~ s/\\/\\\\/g;
				$chars =~ s/'/\\'/g;
				$chars =~ s/\0//g;

				### Now output the data in the replay program
				print REPLAY2 "print '" . $chars . "';\n";

				### This causes the replay program to pause
				print REPLAY2 "ms($texttimediff);\n"
		 		 unless $texttimediff < 0.002;

				$yold = $y;
				$texttimediff = 0;
			}
			#
			#  Process a text scroll event (by using 62 - copy area)
			#
			if ($xcode == 62) {
				print REPLAY2 "print \"\\n\";\n"; 
				$chars = "\n";
			}


			#
			#  If this is a create window event, check the depth.
			#
			if (($xcode == 1) && ($checkdepth == 0)) {
				$data .= "',P($xbyte),'";
				$checkdepth = 1;
			}

			#
			#  Print the X11 data with embedded subroutines
			#  to transpose the resource IDs.
			#
			foreach $xw (@xWords) {
				$xwnum++;
				if ($X11_Codes[$xcode][$xwnum] == 1) {
					$data .= "',R($xw),'";
					#print "XCODER: $xcode, $xwnum\n";
				} elsif ($X11_Codes[$xcode][$xwnum] == 2) {
					$data .= "',D($xw),'";
					#print "XCODED: $xcode, $xwnum\n";
				} elsif ($X11_Codes[$xcode][$xwnum] == 3) {
					$data .= "',C($xw),'";
					#print "XCODEC: $xcode, $xwnum\n";
				} elsif ($X11_Codes[$xcode][$xwnum] == 4) {
					$data .= "',M($xw),'";
					#print "XCODEM: $xcode, $xwnum\n";
				} else {
					$d = pack("$N",$xw);
					$d =~ s/\\/\\\\/g;
					$d =~ s/'/\\'/g;
					$d =~ s/\015\012/'."\\015\\012".'/gs;
					$data .= $d;
				}
			}
		   }
		}
			
		#
		#  Now output the data in the replay program
		#
		print REPLAY "print '.';\n";
		print REPLAY "print \$remote '" . $data . "';\n";

		if ($readnow == 1) {
			$readnow = 2;
			print REPLAY "\$msb = $xmsb;\n";
			print REPLAY "\$ridbaseold = $ridbase;\n";
			print REPLAY "\$ridmaskold = $ridmask;\n";
			print REPLAY "\$rootidold = $rootid;\n";
			print REPLAY "\$colourold = $colour;\n";
			#
			#  The following code implements the client to
			#  server connection - we need to read the
			#  resource and window IDs which are necessary
			#  when transposing the replay traffic to
			#  these new values.
			#
			print REPLAY <<'END';
if ($msb) {
	$n = "n";
	$N = "N";
} else {
	$n = "v";
	$N = "V";
}


read($remote,$in,40);		# (xConnSetup)
($success,$major,$minor,$length,$release,$ridbase,$ridmask,$mbsize,$vendor,
$reqmax,$roots,$formats,$ibo,$bbo,$bslu,$bslp,$keymin,$keymax,$pad) =
unpack("a2$n$n$n$N$N$N$N$n${n}CCCCCCCC${N}a*",$in);

read($remote,$in,$vendor);
print "\nX11 Server Type: $in\n";
read($remote,$in,((4 - ($vendor % 4)) % 4));

foreach $i (1..$formats) {
	read($remote,$in,8);	# (xPixmapFormat)
	($depth,$junk) = unpack("Ca*",$in);
	$Depth{$depth} = 1;
	next if $depth == 1;
	print "X11 server supports $depth bit resolution\n";
}
read($remote,$in,8);	# (xWindowRoot)
($rootid,$colour,$junk) = unpack("$N$N",$in) unless defined $rootid;

if ($DEBUG) {
	debug("Resource ID new: ",$ridbase);
	debug("Resource ID old: ",$ridbaseold);
	debug("Root ID new: ",$rootid);
	debug("Root ID old: ",$rootidold);
	debug("Colour map new: ",$colour);
	debug("Colour map old: ",$colourold);
}
END
		}

		#
		#  This causes the replay program to pause
		#
		print REPLAY "ms($timediff);\n"
		 unless $timediff < 0.002;	# (efficiency).
	}
	print REPLAY "print \"\n\";\n";
	print REPLAY "close \$remote;\n";
	close REPLAY;

	### Better make it executable
	chmod (0755, "$filename");

	close REPLAY2;
	### Better make it executable
	chmod (0755, "$filename2");

	### Global Vars
	$Index{HTML}[$number] .= "<li><a href=\"$filename\">$filename" .
	 "</a> $duration seconds</li>\n";
	$Index{HTML}[$number] .= "<li><a href=\"$filename2\">$filename2" .
	 "</a> $duration seconds</li>\n";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s seconds\n",
	 '"' , "   $filename","",$duration);
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s seconds\n",
	 '"' , "   $filename2","",$duration);
}



# Save_Session_VNCReplay_andHTML - Save a replay program for this session.
#	This creates a program that is used in conjunction with vncviewer.
#	It also saves the HTML version (it would have been redundant to
# 	create a seperate subroutine for that). #40
#
sub Save_Session_VNCReplay_andHTML {
    #debug
    print "\n Save_Session_VNCReplay_andHTML subroutine called" unless $Arg{quiet};
    
	my $session_id = shift;
	my $number = shift;
	my $service_name = shift;
	my $session_text = shift;
	my $numtext = sprintf("%04d",$number);
	my ($filename,$filename2,$filename3,$duration,$code,$rest,$extra,
	 $length,$start,$junk,$down,$value,$data,$oldtimediff,$printed,$chars,
	 $char,$timediff,$checkdepth,$html);
	my @xWords;

	$oldtimediff = 0;
	$printed = 0;
	$html = "";


	#
	#  Output - Text (keystroke replay)
	#
	$filename2 = "session_${numtext}.text${service_name}.replay";
	open (REPLAY2,">$filename2") || 
	 die "ERROR44: creating $filename2 $!\n";
	binmode(REPLAY2);	# for backward OSs

	#
	#  --- textVNC ---
	#
	#  Create a perl program, that when run itself will print out
	#  the contents of the client 1-way stream, with pauses based on
	#  the packet arrival times (replay the session in realtime).
	#
	print REPLAY2 "#!$PERL\n";
	print REPLAY2 <<'END';
#
# This is an VNC text replay program. It will replay keystrokes from
# a VNC session using the timestamps from the packet log.
#
# USAGE: run the script as normal. You can provide a factor as an
#	argument, eg "2" to run twice as fast, or "0.5" to run
#	at half time. eg,
# 		./session_0002.textVNC.replay 2
#
# Auto generated by Chaosreader.
#
$| = 1;
$factor = $ARGV[0] || 1;
sub ms {
	$ms = shift;
	$ms = $ms / $factor;
	select(undef, undef, undef, $ms);
}
END

	#
	#  Sort the data on the timestamps, calculating timestamp differences
	#  to record in the replay program.
	#
	@Times = ();
	foreach $time (keys (%{$TCP{id}{$session_id}{time}})) {
		if ($TCP{id}{$session_id}{time}{$time}{dir} eq "B") {
			push(@Times,$time)
		}
	}
	@Times = sort { $a <=> $b } @Times;
	
	#
	# --- Main Loop ---
	#
	# (this needs to be a for loop!)
	for ($i=0; $i <= $#Times; $i++) {

		### Calculate time diff if possible
		if ($i == $#Times) {
			$timediff = 0;
		} else {
			$timediff = $Times[$i+1] - $Times[$i];
			# just in case,
			if ($timediff < 0) { $timediff = 0; }
		}
		$time = $Times[$i];

		### Fetch data from mem
		$data = $TCP{id}{$session_id}{time}{$time}{data};
		($code) = unpack("C",$data);
	
		$chars = "";

		# skip code 0's
		if ($code > 0) {
		   #
		   #  Process through VNC client codes
		   #
		   $chars = "";
		   while (length($data) > 0) {
			($code) = unpack("C",$data);
			$length = $VNC_Code_Size{$code};
			$length--;
			last if $length <= 0;

			# Fetch this code only
			($code,$value,$data) = unpack("Ca${length}a*",$data);

			### Process Key Pressed
			if ($code == 4) {
			   ($down,$junk,$extra,$char) = unpack("Ca4Ca",$value);
			
			   next if $down == 0;		# record key-ups

			   if ($extra == 0) {
				$chars .= $char;
			   } else {
				if (defined $KeyCode{vnc}{0}{$char}) {
				   $chars .= $KeyCode{vnc}{0}{$char};
				}
			   }
			   $html .= $chars;
			}
		   }
			
		}
			
		$chars =~ s/\\/\\\\/g;
		$chars =~ s/'/\\'/g;

		### Now output the data in the replay program
		unless (length($chars) == 0) {
			print REPLAY2 "ms($oldtimediff);\n"
	 		 unless $oldtimediff < 0.002;

			### Print the data
			print REPLAY2 "print '" . $chars . "';\n";

			# these counters are for efficiency, otherwise
			# we print too many sequiential sleeps
			$printed = 1;
			$oldtimediff = 0;
		} else {
			$printed = 0;
			$oldtimediff += $timediff;
			next;
		}

		### This causes the replay program to pause
		print REPLAY2 "ms($timediff);\n"
 		 unless $timediff < 0.002;
	}
	close REPLAY2;

	### Better make it executable
	chmod (0755, "$filename2");


	#  --- HTML ---
	#
	#  Create a HTML page showing the keystrokes

	### Clean up html
	$html = &Desex_HTML($html);

	### Output
        $filename3 = "session_${numtext}.text${service_name}${ext}.html";
	open (OUT,">$filename3") ||die "ERROR45: file create, $filename3: $!\n";
	binmode(OUT);
	print OUT "<HTML>\n<BODY bgcolor=\"white\">\n" .
	 "<H1>$service_name: $session_text</H1>\n" .
	 "<H2>File $Arg{infile}, Session $number</H2>\n" .
	 "<PRE WRAP=\"virtual\">\n" .
         "<font color=\"red\">" .$html. "</font></PRE>\n</BODY>\n</HTML>\n";
        close OUT;

	### Global Vars
	$length = length($html);
	$Index{HTML}[$number] .= 
	 "<li><a href=\"$filename3\">keystrokes</a></li>\n";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",
	 '"' , "   $filename3","",$length);


	#
	#  Output - Main VNC replay program
	#
	$filename = "session_${numtext}.${service_name}.replay";
	$duration = ($TCP{id}{$session_id}{EndTime} - 
	 $TCP{id}{$session_id}{StartTime});
	$duration = sprintf("%.0f",$duration);
	open (REPLAY,">$filename") || 
	 die "ERROR46: creating $filename $!\n";
	binmode(REPLAY);	# for backward OSs

	#
	#  --- VNC ---
	#
	#  Create a perl program, that when run itself will create a
	#  playback VNC server that listens on a port. When a vncviewer 
	#  connects, the contents of the server 1-way stream arew played back,
	#  with pauses.
	#
	print REPLAY "#!$PERL\n";
	print REPLAY <<'END';
#
# This is a VNC replay program. This runs as a server and listens on a port,
# then vncviewer is run to connect to that port - at which point the playback
# commences.
#
# USAGE: ./session_0001.VNC.replay [-p port] factor 
#
#	just run the script as normal. You can provide a factor as an
#	argument, eg "2" to run twice as fast, or "0.5" to run
#	at half time. eg,
# 		./session_0002.VNC.replay 2
#	a different host and port can be specified if needed. eg,
#		./session_0002.VNC.replay -p 5925
#
#	After the script is running, connect using vncviewer. eg,
#		vncviewer -viewonly localhost:25
#
# PROBLEMS: The playback needs to have captured the start of the connection,
# 	you need to be at the same colour depth as the playback (or more may
#	work), and your screen should be at least as big as the playback 
#	resolution. Newer versions of vncviewer may be tuned to match the
#	playback (eg "-8bit").
#
# Auto generated by Chaosreader.
#

use IO::Socket;
use Getopt::Std;
use Net::hostent;

$| = 1;

if ($ARGV[0] =~ /^-h$|^--help$/) { &help(); }

# Command line options take preference
&getopts('p:');
if (defined $opt_p) { $port = $opt_p; } else { $port = 5921; }
$vncport = $port - 5900;
if ($vncport < 0) { die "ERROR47: Port $port too low, use at least 5901.\n"; }
$factor = $ARGV[0] || 1;
$DEBUG = 0;

print "Chaosreader VNC Replay (experimental)\n\n";
print "Listening on port $port...\n";


# --- Open Socket ---
#
$server = IO::Socket::INET->new( Proto     => 'tcp',
                                 LocalPort => $port,
                                 Listen    => SOMAXCONN,
                                 Reuse     => 1);

die "can't setup server" unless $server;
unless ($server) { 
	die "ERROR48: Can't open port $port. Try a different port."; 
}

print <<WELCOME;
Port opened successfully.

Now run vncviewer and connect to this port. eg,
	vncviewer -viewonly localhost:$vncport

If you are prompted for a password, type any character and hit enter. 
Waiting for connection...
WELCOME


# --- Subroutines ---
#

# ms - sleeps for specified milliseconds
#
sub ms {
	$ms = shift;
	$ms = $ms / $factor;
	select(undef, undef, undef, $ms);
}
# help - print help
#
sub help {
        open (MYSELF,"$0") || die "ERROR49: I can't see myself: $!\n";
        @Myself = <MYSELF>;
        close MYSELF;
        ### Print comment from top of code
        foreach $line (@Myself) {
                last if $line !~ /^#/;
                next if $line =~ m:^#!/usr/bin/perl:;
                $line =~ s/^#/ /;
                print $line;
        }
        print "\n";
        exit(0);
}


#
# --- MAIN ---
#

### Wait for connection
$client = $server->accept();
$client->autoflush(1);

print "Sending VNC traffic:";

END

	#
	#  Sort the data on the timestamps, calculating timestamp differences
	#  to record in the replay program.
	#
	@Times = ();
	foreach $time (keys (%{$TCP{id}{$session_id}{time}})) {
		if ($TCP{id}{$session_id}{time}{$time}{dir} eq "A") {
			push(@Times,$time)
		}
	}
	@Times = sort { $a <=> $b } @Times;
	
	#
	# --- Main Loop ---
	#
	# (this needs to be a for loop!)
	for ($i=0; $i <= $#Times; $i++) {

		### Calculate time diff if possible
		if ($i == $#Times) {
			$timediff = 0;
		} else {
			$timediff = $Times[$i+1] - $Times[$i];
			# just in case,
			if ($timediff < 0) { $timediff = 0; }
		}
		$time = $Times[$i];

		### Fetch data from mem
		$data = $TCP{id}{$session_id}{time}{$time}{data};

		$data =~ s/\\/\\\\/g;
		$data =~ s/'/\\'/g;
		$data =~ s/\015\012/'."\\015\\012".'/gs;

		#
		#  Now output the data in the replay program
		#
		print REPLAY "print '.';\n";
		print REPLAY "print \$client '" . $data . "';\n";

		#
		#  This causes the replay program to pause
		#
		print REPLAY "ms($timediff);\n"
		 unless $timediff < 0.002;	# (efficiency).
	}
	print REPLAY "print \"\n\";\n";
	print REPLAY "close \$client;\n";
	close REPLAY;

	### Better make it executable
	chmod (0755, "$filename");

	### Global Vars
	$Index{HTML}[$number] .= "<li><a href=\"$filename\">$filename" .
	 "</a> $duration seconds</li>\n";
	$Index{HTML}[$number] .= "<li><a href=\"$filename2\">$filename2" .
	 "</a> $duration seconds</li>\n";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s seconds\n",
	 '"' , "   $filename","",$duration);
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s seconds\n",
	 '"' , "   $filename2","",$duration);
}



# Save_SMTP_Emails - Save emails from an SMTP session. #41
#
sub Save_SMTP_Emails {
    #debug
    print "\n Save_SMTP_Emails subroutine called \n" unless $Arg{quiet};
    
	my ($filename);
	my $session_id = shift;
	my $number = shift;
	my $service_name = "smtp";
	my $numtext = sprintf("%04d",$number);


	### Full - Input
	$snmp_data = &TCP_Follow_RawB($session_id);

	### Full - Processing
	@Snmp_parts = split(/\r\n\.\r\n|\n\.\n/,$snmp_data);

	### LOOP
	$partnum = 0;
	foreach $snmp_part (@Snmp_parts) {

		next unless $snmp_part =~ /DATA/;
		$partnum++;
		$parttext = sprintf("%02d",$partnum);

		### Part - Processing
		$snmp_part =~ s/^.*DATA\r?\n//s;	# '/s;' is new perl5, 
							# else '/;' with $* = 1

		### Part - Output
		if ($TCP{id}{$session_id}{Partial}) { $ext = ".partial"; } 
		 else { $ext = ""; }
	        $filename = "session_${numtext}.part_${parttext}." .
		 "${service_name}${ext}.email";
	        open (OUT,">$filename") || 
		 die "ERROR50: file create, $filename: $!\n";
		binmode(OUT);		# for backward OSs
	        print OUT $snmp_part;
	        close OUT;

		### Part - Global Vars
		my $length = length($snmp_part);
		$Index{HTML}[$number] .= "<li><a href=\"$filename\">$filename" .
		 "</a> $length bytes</li>\n";
		$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",
		 '"' , "   $filename","",$length);
	}
}


# Save_HTTP_Files - Save HTTP components. #42
#
sub Save_HTTP_Files {
    #debug
    print "\n Save_HTTP_Files subroutine called \n" unless $Arg{quiet};
    
	my ($filename);
	my $session_id = shift;
	my $number = shift;
	my $service_name = shift;
	my $numtext = sprintf("%04d",$number);

	### Full - Input
	$http_session = &TCP_Follow_RawA($session_id);

	### Full - Processing
	@HttpParts = split(/HTTP\/[0-9.]* /,$http_session);

	### LOOP
	$partnum = 0;
	foreach $http_part (@HttpParts) {

		### Part - Processing
		($http_header,$http_data) = split(/\r\n\r\n|\n\n/,$http_part,2);
		next if $http_data eq "";
		next if length($http_data) < 8;
		$partnum++;
		$parttext = sprintf("%02d",$partnum);

		### Part - Checks
		$http_type = &File_Type($http_data);
		if ($TCP{id}{$session_id}{Partial}) { $ext = ".partial"; } 
		 else { $ext = ""; }

		### Part - Output
	        $filename = "session_${numtext}.part_$parttext${ext}." .
		 "$http_type";
	        open (OUT,">$filename") || 
		 die "ERROR51: file create, $filename: $!\n";
		binmode(OUT);		# for backward OSs
	        print OUT $http_data;
	        close OUT;

		### Part - Global Vars
		my $length = length($http_data);
		$Index{HTML}[$number] .= "<li><a href=\"$filename\">$filename" .
		 "</a> $length bytes</li>\n";
		$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",
		 '"' , "   $filename","",$length);
		if (&Is_Image($http_type)) {
			$Image{HTML}[$number]{links} .= 
			 "<img src=\"$filename\"> ";
			$Image{notempty} = 1;
		}
	}
}


# Save_NFS_File - Save NFS file. Only works well for some files, if the NFS
#		header can't be processed, a "*.nfs.raw" file is created. #43
#
sub Save_NFS_File {
    #debug
    print "\n Save_NFS_File subroutine called \n" unless $Arg{quiet};
    
	my ($filename);
	my $session_id = shift;
	my $number = shift;
	my $service_name = "nfs";
	my $numtext = sprintf("%04d",$number);

	### Input
	my $nfs_raw = &TCP_Follow_RawB($session_id);

	### Processing
	($nfs_start,$nfs_size,$nfs_end) = unpack('a56a4a*',$nfs_raw);
	$nfs_sizeint = unpack("N",$nfs_size);
	($nfs_start,$nfs_data) = split(/$nfs_size....$nfs_size/,$nfs_end,2);

	### Checks
	if (($nfs_sizeint > 4) && (length($nfs_data) >= $nfs_sizeint)) {
		$nfs_type = &File_Type($nfs_data);
		if ($nfs_sizeint < length($nfs_data)) {
			$nfs_data = unpack("a${nfs_sizeint}a*",$nfs_data);
		}
	} else {
		$nfs_type = "raw";
		$nfs_data = $nfs_raw;
	}
	if ($TCP{id}{$session_id}{Partial}) { $ext = ".partial"; } 
	 else { $ext = ""; }

	### Output
        $filename = "session_${numtext}.part_01.${service_name}${ext}.nfs." .
	 "$nfs_type";
	open (OUT,">$filename") || die "ERROR52: file create, $filename: $!\n";
	binmode(OUT);		# for backward OSs
	print OUT $nfs_data;
	close OUT;

	### Global Vars
	my $length = length($nfs_data);
	$Index{HTML}[$number] .= "<li><a href=\"$filename\">$filename</a>" .
	 " $length bytes</li>\n";
	$Index{Text}[$number] .= sprintf("%-4s %-45s %-10s %8s bytes\n",
	 '"' , "   $filename","",$length);
}


# TCP_Follow_RawA - process session by TCP Seq numbers 1-way. #44
#			(TCP ASSEMBLY) 
#
sub TCP_Follow_RawA {
    #debug
    print "\n TCP_Follow_RawA subroutine called \n" unless $Arg{quiet};
    
	my $session_id = shift;		
	my $raw = "";

	#
	#  Assemble TCP Sessions. Each hash contains session_ids as keys,
	#  and the value points to another hash of sequence numbers and data.
	#  %TCP{id}{}{Aseq} is input, and %TCP{id}{}{RawA} is output.
	#
	@Seqs = keys (%{$TCP{id}{$session_id}{Aseq}});
	foreach $seq (sort { $a <=> $b } @Seqs) {
		$raw .= ${$TCP{id}{$session_id}{Aseq}{$seq}};
	}

	return $raw;
}


# TCP_Follow_RawB - process session by TCP Seq numbers 1-way. #45
#			(TCP ASSEMBLY)
#
sub TCP_Follow_RawB {
    #debug
    print "\n TCP_Follow_RawB subroutine called \n" unless $Arg{quiet};
    
	my $session_id = shift;		
	my $raw = "";

	#
	#  Assemble TCP Sessions. Each hash contains session_ids as keys,
	#  and the value points to another hash of sequence numbers and data.
	#  %TCP{id}{}{Aseq} is input, and %TCP{id}{}{RawA} is output.
	#
	@Seqs = keys (%{$TCP{id}{$session_id}{Bseq}});
	foreach $seq (sort { $a <=> $b } @Seqs) {
		$raw .= ${$TCP{id}{$session_id}{Bseq}{$seq}};
	}

	return $raw;
}


# Pick_Service_Port - pick which port is the server. Usually is the lower
#	number, however check if the direction is already known (eg SYN).
#	The port arguments will not often be needed. #46
#
# NOTE: This code is different to Generate_TCP_IPs - which does the "<->"'s
#
sub Pick_Service_Port {
    #debug
    print "\n Pick_Service_Port subroutine called \n" unless $Arg{quiet};
    
	my $type = shift;
	my $id = shift;
	my $porta = shift;
	my $portb = shift;
	my $from_server = 0;
	my ($hi,$low);

	# Catch active FTP, etc.
	($low,$hi) = sort { $a <=> $b } ($porta,$portb);
	if ($low < 100) {
		return ($low,$hi);
	}
	
	if ($type eq "TCP") {
	   if (defined $TCP{id}{$id}{source}) {
		if ($TCP{id}{$id}{source} eq $TCP{id}{$id}{src}) {
		   return ($TCP{id}{$id}{dest_port},$TCP{id}{$id}{src_port});
		} else {
		   return ($TCP{id}{$id}{src_port},$TCP{id}{$id}{dest_port});
		}
	   }
	} elsif ($type eq "UDP") {
	   return ($UDP{id}{$id}{dest_port},$UDP{id}{$id}{src_port});
	}

	# resort to a sort
	return sort { $a <=> $b } ($porta,$portb);
}


# Generate_SessionID - input source and dest IPs and ports, and generate
# 	a unique session_id based on them. this is done by sorting on
#	ports and then IPs. Also returns a flag if the packet may be 
#	assumed to be from_server - where the lowest port is assumed to
#	be the server (unless TCP SYNs have been observed). #47
#
sub Generate_SessionID {
    #debug
    print "\n Generate_SessionID subroutine called \n" unless $Arg{quiet};
    
	my $ip_src = shift;
	my $tcp_src_port = shift;
	my $ip_dest = shift;
	my $tcp_dest_port = shift;
	my $type = shift;
	my $from_server = 0;
	my $session_id;

	#
	#  Generate session_id string using host:port,host:port sorted on
	#  port (low port last).
	#
	if ($tcp_src_port < $tcp_dest_port) {
		$session_id = "$ip_dest:$tcp_dest_port,$ip_src:$tcp_src_port";
		$from_server = 1;
	} elsif ($tcp_src_port > $tcp_dest_port) {
		$session_id = "$ip_src:$tcp_src_port,$ip_dest:$tcp_dest_port";
		$from_server = 0;
	} else {
		$session_id =join(",",sort("$ip_src:$tcp_src_port",
					"$ip_dest:$tcp_dest_port"));
		$from_server = 1;
	}

	if ($type eq "TCP") {
		if (defined $TCP{id}{$session_id}{source}) {
			if ($TCP{id}{$session_id}{source} eq $ip_dest) {
				$from_server = 1;
			} else {
				$from_server = 0;
			}
		}
	}
	return ($session_id,$from_server);
}



# Generate_TCP_IDs - generate a text and html version of the session ID, that
#		displays direction of the TCP session if SYNs and ACKs were
#		observed, else uses a "<->" symbol to represent unknown
#		direction. TCP only. #48
#
sub Generate_TCP_IDs {
    #debug
    print "\n Generate_TCP_IDs subroutine called \n" unless $Arg{quiet};
    
	my $session_id = shift;
	my ($ip_src,$tcp_src_port,$ip_dest,$tcp_dest_port,$text,$html);

	# try this direction,
	$ip_src = $TCP{id}{$session_id}{src};
	$ip_dest = $TCP{id}{$session_id}{dest};
	$tcp_src_port = $TCP{id}{$session_id}{src_port};
	$tcp_dest_port = $TCP{id}{$session_id}{dest_port};

	if (defined $TCP{id}{$session_id}{source}) {
		if ($TCP{id}{$session_id}{source} eq $ip_dest) {
			# nope, switch ends
			$ip_src = $TCP{id}{$session_id}{dest};
			$ip_dest = $TCP{id}{$session_id}{src};
			$tcp_src_port = $TCP{id}{$session_id}{dest_port};
			$tcp_dest_port = $TCP{id}{$session_id}{src_port};
		}
		$text = "$ip_src:$tcp_src_port -> $ip_dest:$tcp_dest_port";
		$html = "$ip_src:$tcp_src_port -&gt; $ip_dest:$tcp_dest_port";
	} else {
		$text = "$ip_src:$tcp_src_port <-> $ip_dest:$tcp_dest_port";
		$html = "$ip_src:$tcp_src_port &lt;-&gt; " .
		 "$ip_dest:$tcp_dest_port";
	}

	return ($text,$html);
}



# Generate_IP_ID - input source IP, dest IP and ident, and generate a
#		unique ip_id based on them. This is necessary for IP 
#		fragmentation reassembely. Normally we would assume that
#		the IP_ident was unique - however this program could
#		process traffic from many different hosts over a long
#		period of time - idents alone could clash. #49
#
sub Generate_IP_ID {
    #debug
    print "\n Generate_IP_ID subroutine called \n" unless $Arg{quiet};
    
	my $ip_src = shift;
	my $ip_dest = shift;
	my $ip_ident = shift;
	my $ip_id;

	#
	#  Generate ip_id string using host:host:ident sorted on IP.
	#  
	#
	$ip_id = join(",",sort("$ip_src","$ip_dest")) . ",$ip_ident";

	return $ip_id;
}



# Read_Tcpdump_Record - Read the next tcpdump record, will "last" if
#			there are no more records. #50
#
sub Read_Tcpdump_Record {
        #debug
        print "\n Read_Tcpdump_Record subroutine called \n" unless $Arg{quiet};
	my $more;

	### Fetch record header
	$length = read(INFILE,$header_rec,($integerSize * 2 + 8));

	### Quit main loop if at end of file
	last if $length < 16;

	### Throw out extra info in tcpdump/modified1 format
	if ($STYLE =~ /^modified/) {
		$length = read(INFILE,$more,8);
	}

	$frame++;

	## Unpack header, endian sensitive
	if ($STYLE =~ /1$/) { 
		($tcpdump_seconds,$tcpdump_msecs,$tcpdump_length,
		 $tcpdump_length_orig)
		 = unpack('NNNN',$header_rec);
	} else {
		($tcpdump_seconds,$tcpdump_msecs,$tcpdump_length,
		 $tcpdump_length_orig)
		 = unpack('VVVV',$header_rec);
	}
	$length = read(INFILE,$tcpdump_data,$tcpdump_length);
	$tcpdump_drops = $tcpdump_length_orig - $tcpdump_length;
}


# Read_Snoop_Record - Read the next snoop record, will "last" if
#			there are no more records. #51
#
sub Read_Snoop_Record {
    #debug
    print "\n Read_Snoop_Record subroutine called \n" unless $Arg{quiet};

	### Fetch record header
	$length = read(INFILE,$header_rec,24);

	### Quit main loop if at end of file
	last if $length < 24;

	$frame++;

	### Unpack header
	($snoop_length_orig,$snoop_length_inc,$snoop_length_rec,$snoop_drops,
		$snoop_seconds,$snoop_msecs) = unpack('NNNNNN',$header_rec);
	$length = read(INFILE,$snoop_data,$snoop_length_inc);
	$skip = read(INFILE,$pad,($snoop_length_rec - $snoop_length_inc - 24));
}


# Load_Index_File - Load the master index file "index.file" into @Master #52
#
sub Load_Index_File {
    #debug
    print "\n Load_Index_File subroutine called \n" unless $Arg{quiet};

	my ($path,$dir,$file,$start,$end,$duration,$index);

	#
	#  Load index.file lines into memory
	#
	open (FILES,"index.file") || die "ERROR53: Can't read index.file: $!\n"
	 ."Standalone mode needs to have run recently from this directory.\n\n";

	chomp(@Files = <FILES>);
	close FILES;

	#
	#  Populate @Master
	#
	$index = 0;
	foreach $path (@Files) {
		($dir,$file,$duration,$start,$end) = split(/\t/,$path);
		$Master[$index]{starttime} = $start;
		$Master[$index]{endtime} = $end;
		$Master[$index]{dir} = $dir;
		$Master[$index]{file} = $file;
		$Master[$index]{duration} = $duration;
		$Master[$index]{size} = -s "$dir/$file";
		$index++;
	}
}


# Load_Etc_Services - load /etc/services lookup table into memory, 
#			into %Services_TCP and %Services_UDP. #53
#
sub Load_Etc_Services {
    #debug
    print "\n Load_Etc_Services subroutine called \n" unless $Arg{quiet};
    
	my ($line,$name,$service);

	### Hardcoded
	%Services_TCP = (20 => "ftp-data",
		         21 => "ftp",
		         23 => "telnet",
		         25 => "smtp",
		         80 => "web",
		         109 => "pop2",
		         110 => "pop3",
		         143 => "imap",
		         513 => "login",
		         514 => "shell",
		         3128 => "web",
		         4110 => "irc4110",
		         5000 => "irc5000",
		         6000 => "X11",
		         6660 => "irc",
		         6665 => "irc",
		         6666 => "irc",
		         6667 => "irc",
		         6668 => "irc",
		         6669 => "irc",
		         7000 => "irc7000",
		         8000 => "irc8000",
		         8080 => "web",
		         9000 => "irc9000");
	# non standard IRC ports include the number in their name

	foreach (@Save_As_X11_Playback_Ports) { 
		$Services_TCP{$_} = "X11";
	}

	foreach (@Save_As_VNC_Playback_Ports) { 
		$Services_TCP{$_} = "VNC";
	}

	%Services_UDP = (53 => "dns");
                                       
	### File input
	open(SERVICES,"/etc/services") || return;
	while ($line = <SERVICES>) {
		next if $line =~ /^#|^\s*$/;    # skip comments, blank lines.
		if ($line =~ /\d\/tcp/) {
			$is_tcp = 1;
		} else {
			$is_tcp = 0;
		}
		$line =~ s:/.*::;
		($name,$port) = split(' ',$line);
		if ($is_tcp) {
			$Services_TCP{$port} = $name;
		} else {
			$Services_UDP{$port} = $name;
		}
			
	}
	close SERVICES;
}


# Set_IP_Protocols - Set a lookup hash for IP Protocols to names. #54
# 		RFC790, RFC1700. 
#
sub Set_IP_Protocols {
    #debug
    print "\n Set_IP_Protocols subroutine called \n" unless $Arg{quiet};
        
	%IP_Protocols = (0 => "Reserved",
			1 => "ICMP",
			2 => "Unassigned",
			3 => "Gateway-to-Gateway",
			4 => "CCMC Gateway Monitoring Message",
			5 => "ST",
			6 => "TCP",
			7 => "UCL",
			8 => "Unassigned",
			9 => "Secure",
			10 => "BBN RCC Monitoring",
			11 => "NVP",
			12 => "PUP",
			13 => "Pluribus",
			14 => "Telenet",
			15 => "XNET",
			16 => "Chaos",
			17 => "UDP",
			18 => "Multiplexing",
			19 => "DCN",
			20 => "TAC Monitoring",
			37 => "DDP",
			41 => "SIP",
			42 => "SDRP",
			44 => "IPv6 Frag",
			50 => "SIPP-ESP",
			51 => "SIPP-AH",
			53 => "SWIPE",
			50 => "SDRP",
			58 => "ICMPv6",
			88 => "IGRP",
			94 => "IPIP"
	);
}

# Set_ICMP_Types - Set a lookup hash for ICMP Types. #55
#                  RFC792
sub Set_ICMP_Types {
    #debug
    print "\n Set_ICMP_Types subroutine called \n" unless $Arg{quiet};
    
	%ICMP_Types = (0 => "Echo Reply",
			3 => "Destination Unreachable",
			4 => "Source Quench",
			5 => "Redirect",
			8 => "Echo",
			11 => "Time Exceeded",
			12 => "Parameter Problem",
			13 => "Timestamp",
			14 => "Timestamp Reply",
			15 => "Information Request",
			16 => "Information Reply",
			128 => "Echo",
			129 => "Echo Reply",
			135 => "Neighbor solicitation",
			136 => "Neighbor advertisement"
	);
}

# Set_Result_Names - Set a lookup hash for squid result codes. #56
#		(This needs some fine tuning).
#
sub Set_Result_Names {
    #debug
    print "\n Set_Result_Names subroutine called \n" unless $Arg{quiet};
    
	%Result_Names = ("" => "TCP_MISS",
			000 => "TCP_MISS",
			200 => "TCP_HIT",
			302 => "TCP_HIT",
			304 => "TCP_REFRESH_HIT",
			404 => "TCP_NEGATIVE_HIT"
	);
}

# Set_X11_Codes - creates a lookup hash needed for X11 transposing. #57
#
sub Set_X11_Codes {
    #debug
    print "\n Set_X11_Codes subroutine called \n" unless $Arg{quiet};
	#
	#  This has a row per X11 code, the row describing the 16 bit 
	#  words that make up the values. "1" means resource id.
	#  (some values are 8 bit, but are fortunately padded).
	#

	@X11_Codes = (
[ 0 ],	# X_Error entry
[ 0, 2, 2, 0, 0, 0, 1, 0,4,4,4,4,4,4,4,4,4,4,4,4 ], # X_CreateWindow 1
[ 0, 1, 0 ], # X_ChangeWindowAttributes
[ 0, 1 ], # X_GetWindowAttributes
[ 0 ], # X_DestroyWindow?
[ 0 ], # X_DestroySubwindows?
[ 0, 1 ], # X_ChangeSaveSet
[ 0, 1, 1, 0 ], # X_ReparentWindow
[ 0, 1 ], # X_MapWindow
[ 0, 1 ], # X_MapSubwindows
[ 0, 1 ], # X_UnmapWindow 10
[ 0, 1 ], # X_UnmapSubwindows
[ 0, 1, 0, 4,4,4,4,4,4,4,4,4,4,4,4 ], # X_ConfigureWindow
[ 0, 1 ], # X_CirculateWindow
[ 0, 2 ], # X_GetGeometry
[ 0, 1 ], # X_QueryTree
[ 0, 1 ], # X_InternAtom (? else 0,0)
[ 0 ], # X_GetAtomName?
[ 0, 1, 0, 0, 1, 0 ], # X_ChangeProperty (? else 0,1,0,0,0,0)
[ 0, 1, 0 ], # X_DeleteProperty
[ 0, 2, 0, 0, 0, 0 ], # X_GetProperty 20
[ 0 ], # X_ListProperties?
[ 0, 1, 0, 0 ], # X_SetSelectionOwner
[ 0 ], # X_GetSelectionOwner
[ 0, 1, 0, 0, 0, 0 ], # X_ConvertSelection
[ 0, 1, 0 ], # X_SendEvent
[ 0, 1, 0, 1, 0, 0 ], # X_GrabPointer
[ 0, 1, 0 ], # X_UngrabPointer?
[ 0, 1, 0, 1, 0, 0 ], # X_GrabButton
[ 0, 1, 0 ], # X_UngrabButton
[ 0, 1, 0, 0 ], # X_ChangeActivePointerGrab 30
[ 0, 1, 0, 0 ], # X_GrabKeyboard
[ 0, 1, 0 ], # X_UngrabKeyboard?
[ 0, 1, 0, 0 ], # X_GrabKey
[ 0, 1, 0 ], # X_UngrabKey
[ 0, 0, 0 ], # X_AllowEvents
[ 0 ], # X_GrabServer?
[ 0 ], # X_UngrabServer?
[ 0 ], # X_QueryPointer?
[ 0, 1, 0, 0 ], # X_GetMotionEvents
[ 0, 1, 1, 0 ], # X_TranslateCoords 40
[ 0, 1, 1, 0, 0, 0 ], # X_WarpPointer
[ 0, 1, 0 ], # X_SetInputFocus
[ 0 ], # X_GetInputFocus?
[ 0 ], # X_QueryKeymap?
[ 0, 1, 0 ], # X_OpenFont
[ 0, 1 ], # X_CloseFont
[ 0, 1 ], # X_QueryFont
[ 0, 1 ], # X_QueryTextExtents
[ 0, 0 ], # X_ListFonts
[ 0, 0 ], # X_ListFontsWithInfo 50
[ 0, 0 ], # X_SetFontPath
[ 0 ], # X_GetFontPath?
[ 0, 1, 2, 0 ], # X_CreatePixmap
[ 0 ], # X_FreePixmap?
[ 0, 1, 2, 0, 4,4,4,4,4,4,4,4,4,4,4,4 ], # X_CreateGC ?(else 0,1,1,0)
[ 0, 1, 0, 4,4,4,4,4,4,4,4,4,4,4,4 ], # X_ChangeGC
[ 0, 1, 1, 0, 4,4,4,4,4,4,4,4,4,4,4,4 ], # X_CopyGC
[ 0, 1, 0 ], # X_SetDashes
[ 0, 1, 0 ], # X_SetClipRectangles
[ 0, 1 ], # X_FreeGC? 60
[ 0, 1, 0, 0 ], # X_ClearArea
[ 0, 2, 2, 1, 0, 0, 0 ], # X_CopyArea
[ 0, 2, 2, 1, 0, 0, 0, 0 ], # X_CopyPlane
[ 0, 2, 1 ], # X_PolyPoint
[ 0, 2, 1 ], # X_PolyLine
[ 0, 2, 1 ], # X_PolySegment
[ 0, 2, 1 ], # X_PolyRectangle
[ 0, 2, 1 ], # X_PolyArc
[ 0, 2, 1, 0 ], # X_FillPoly
[ 0, 2, 1 ], # X_PolyFillRectangle 70
[ 0, 2, 1 ], # X_PolyFillArc
[ 0, 2, 1, 0, 0, 0 ], # X_PutImage
[ 0, 2, 0, 0, 0 ], # X_GetImage
[ 0, 2, 1, 0 ], # X_PolyText8
[ 0, 2, 1, 0 ], # X_PolyText16
[ 0, 2, 1, 0 ], # X_ImageText8
[ 0, 2, 1, 0 ], # X_ImageText16
[ 0, 3, 1, 1 ], # X_CreateColormap
[ 0 ], # X_FreeColormap?
[ 0, 3, 3 ], # X_CopyColormapAndFree 80
[ 0 ], # X_InstallColormap?
[ 0 ], # X_UninstallColormap?
[ 0 ], # X_ListInstalledColormaps?
[ 0, 3, 0, 0 ], # X_AllocColor
[ 0, 3, 0 ], # X_AllocNamedColor
[ 0, 3, 0 ], # X_AllocColorCells
[ 0, 3, 0, 0 ], # X_AllocColorPlanes
[ 0, 3, 0 ], # X_FreeColors
[ 0, 3 ], # X_StoreColors
[ 0, 3, 0, 0 ], # X_StoreNamedColor 90
[ 0, 3 ], # X_QueryColors
[ 0, 3, 0 ], # X_LookupColor
[ 0, 1, 1, 1, 0, 0, 0, 0 ], # X_CreateCursor
[ 0, 1, 1, 1, 0, 0, 0, 0 ], # X_CreateGlyphCursor
[ 0 ], # X_FreeCursor?
[ 0, 1, 0, 0, 0 ], # X_RecolorCursor
[ 0, 2, 0 ], # X_QueryBestSize
[ 0, 1 ], # X_QueryExtension (? else 0,0)
[ 0, 0, 0 ], # X_ListExtensions?
[ 0, 1, 0 ], # X_ChangeKeyboardMapping 100
[ 0, 1, 0 ], # X_GetKeyboardMapping
[ 0, 0, 4,4,4,4,4,4,4,4,4,4,4,4 ], # X_ChangeKeyboardControl
[ 0, 0, 0 ], # X_GetKeyboardControl?
[ 0 ], # X_Bell
[ 0, 0, 0 ], # X_ChangePointerControl
[ 0, 0, 0 ], # X_GetPointerControl?
[ 0, 0, 0 ], # X_SetScreenSaver
[ 0, 0, 0 ], # X_GetScreenSaver?
[ 0, 0 ], # X_ChangeHosts
[ 0 ], # X_ListHosts 110
[ 0 ], # X_SetAccessControl
[ 0 ], # X_SetCloseDownMode
[ 0, 0, 0 ], # X_KillClient?
[ 0, 1, 0 ], # X_RotateProperties
[ 0 ], # X_ForceScreenSaver
[ 0 ], # X_SetPointerMapping
[ 0, 0, 0 ], # X_GetPointerMapping?
[ 0 ], # X_SetModifierMapping
[ 0, 0, 0 ], # X_GetModifierMapping?
[ 0 ], # undef 120
[ 0 ], # undef
[ 0 ], # undef
[ 0 ], # undef
[ 0 ], # undef
[ 0 ], # undef
[ 0 ], # undef
[ 0, 0, 0 ] # X_NoOperation 127
	);

}

# Set_X11_KeyCodes - creates a lookup hash of X11 Key codes needed
#	to generate coloured 2-way HTML X11 reports. #58
#
sub Set_X11_KeyCodes {
    #debug
    print "\n Set_X11_KeyCodes subroutine called \n" unless $Arg{quiet};

	my ($junk,$code,$char1,$char2,$line,
	 $sun_xmodmap_pke,$linux_xmodmap_pke);
	my %Alias;

	#
	# These are generated using "xmodmap -pke" (and trimmed a little).
	#
	$sun_xmodmap_pke = <<END;
keycode   8 = Control_L
keycode   9 = Control_R
keycode  10 = Shift_L
keycode  11 = Shift_R
keycode  12 = Meta_L
keycode  13 = Meta_R
keycode  14 = Alt_L
keycode  15 = Alt_R
keycode  16 = space
keycode  17 = 0 parenright
keycode  18 = 1 exclam
keycode  19 = 2 at
keycode  20 = 3 numbersign
keycode  21 = 4 dollar
keycode  22 = 5 percent
keycode  23 = 6 asciicircum
keycode  24 = 7 ampersand
keycode  25 = 8 asterisk
keycode  26 = 9 parenleft
keycode  27 = minus underscore
keycode  28 = equal plus
keycode  29 = bracketleft braceleft
keycode  30 = bracketright braceright
keycode  31 = semicolon colon
keycode  32 = apostrophe quotedbl
keycode  33 = grave asciitilde
keycode  34 = comma less
keycode  35 = period greater
keycode  36 = slash question
keycode  37 = backslash bar
keycode  38 = a A
keycode  39 = b B
keycode  40 = c C
keycode  41 = d D
keycode  42 = e E
keycode  43 = f F
keycode  44 = g G
keycode  45 = h H
keycode  46 = i I
keycode  47 = j J
keycode  48 = k K
keycode  49 = l L
keycode  50 = m M
keycode  51 = n N
keycode  52 = o O
keycode  53 = p P
keycode  54 = q Q
keycode  55 = r R
keycode  56 = s S
keycode  57 = t T
keycode  58 = u U
keycode  59 = v V
keycode  60 = w W
keycode  61 = x X
keycode  62 = y Y
keycode  63 = z Z
keycode  64 = BackSpace
keycode  65 = Return
keycode  66 = Tab
keycode  67 = Escape
keycode  68 = Delete
END

	#
	# These are generated using "xmodmap -pke" (and trimmed a little).
	#
	$linux_xmodmap_pke = <<END;
keycode   8 =
keycode   9 = Escape
keycode  10 = 1 exclam
keycode  11 = 2 at
keycode  12 = 3 numbersign
keycode  13 = 4 dollar
keycode  14 = 5 percent
keycode  15 = 6 asciicircum
keycode  16 = 7 ampersand
keycode  17 = 8 asterisk
keycode  18 = 9 parenleft
keycode  19 = 0 parenright
keycode  20 = minus underscore
keycode  21 = equal plus
keycode  22 = BackSpace Terminate_Server
keycode  23 = Tab ISO_Left_Tab
keycode  24 = q Q
keycode  25 = w W
keycode  26 = e E
keycode  27 = r R
keycode  28 = t T
keycode  29 = y Y
keycode  30 = u U
keycode  31 = i I
keycode  32 = o O
keycode  33 = p P
keycode  34 = bracketleft braceleft
keycode  35 = bracketright braceright
keycode  36 = Return
keycode  37 = Control_L
keycode  38 = a A
keycode  39 = s S
keycode  40 = d D
keycode  41 = f F
keycode  42 = g G
keycode  43 = h H
keycode  44 = j J
keycode  45 = k K
keycode  46 = l L
keycode  47 = semicolon colon
keycode  48 = apostrophe quotedbl
keycode  49 = grave asciitilde
keycode  50 = Shift_L
keycode  51 = backslash bar
keycode  52 = z Z
keycode  53 = x X
keycode  54 = c C
keycode  55 = v V
keycode  56 = b B
keycode  57 = n N
keycode  58 = m M
keycode  59 = comma less
keycode  60 = period greater
keycode  61 = slash question
keycode  62 = Shift_R
keycode  64 = Alt_L Meta_L
keycode  65 = space
keycode  94 = less greater
END
	%Alias = qw(exclam ! at @ dollar $ percent %
	 asciicircum ^ ampersand & asterisk * minus - underscore _
	 equal = plus + bracketleft [ bracketright ] braceleft {
	 braceright } semicolon ; colon : apostrophe ' quotedbl "
	 grave ` asciitilde ~ backslash \ bar | less <
	 period . greater > slash / question ?);

	# naughty chatacrers (some of these generate warnings)
	@Alias{"parenleft","parenright","space"} = ("(",")"," ");
	@Alias{"Tab","Return","numbersign","comma"} = ("\t","\n","#",",");
	

	#
	#  Populate KeyCode aliase
	#
	foreach $line (split(/\n/,$sun_xmodmap_pke)) {
		($junk,$code,$junk,$char1,$char2) = split(' ',$line);
		if (defined $Alias{$char1}) { $char1 = $Alias{$char1}; }
		if (defined $Alias{$char2}) { $char2 = $Alias{$char2}; }
		if (length($char1) > 1) { $char1 = "."; }
		if (length($char2) > 1) { $char2 = "."; }
		$KeyCode{sun}{0}{$code} = $char1;
		$KeyCode{sun}{1}{$code} = $char2;
	}
	foreach $line (split(/\n/,$linux_xmodmap_pke)) {
		($junk,$code,$junk,$char1,$char2) = split(' ',$line);
		if (defined $Alias{$char1}) { $char1 = $Alias{$char1}; }
		if (defined $Alias{$char2}) { $char2 = $Alias{$char2}; }
		if (length($char1) > 1) { $char1 = "."; }
		if (length($char2) > 1) { $char2 = "."; }
		$KeyCode{linux}{0}{$code} = $char1;
		$KeyCode{linux}{1}{$code} = $char2;
	}

}


# Set_VNC_Codes - set globals for VNC. #59
#
sub Set_VNC_Codes  {
    #debug
    print "\n Set_VNC_Codes subroutine called \n" unless $Arg{quiet};

	### set client code to request size hash.
	%VNC_Code_Size = ( 0 => 20,
			   1 => 6,
			   2 => 4,
			   3 => 10,
			   4 => 8,
			   5 => 6,
			   6 => 8 );

	### Some essential keysyms
	$KeyCode{vnc}{0}{"\010"} = "\b";
	$KeyCode{vnc}{0}{"\011"} = "\t";
	$KeyCode{vnc}{0}{"\015"} = "\n";

}
	


# Touch_Vars - This is stops perl -w warnings about vars used only once.
#		Part of my todo list is to cull this list. #60
#	
#
sub Touch_Vars {
    #debug
    print "\n Touch_Vars subroutine called \n" unless $Arg{quiet};
    
	#
	#  Perl < 5.6 code
	#
	#use vars qw($ip_ttl $udp_checksum $ip_ident $tcp_length_data
	#$ip_tos $tcp_options $opt_A $opt_D $tcp_header_rest $opt_J 
	#$opt_P $opt_U $opt_X $opt_e $opt_h $opt_i $pad $opt_j 
	#$snoop_length_orig $http_header $opt_p $opt_q $opt_r 
	#$header_rest $tcp_ack $ether_dest $ether_src $skip 
	#$ip_length $udp_length $ip_options $ip_checksum 
	#$opt_b $opt_B $opt_l $opt_L $ip_rest $ip_hop $ip_reserved 
	#$ip_flow $icmp_rest $opt_f $opt_z);
	#
	#  Perl 5.6 code
	#
	#our ($ip_ttl,$udp_checksum,$ip_ident,$tcp_length_data,
	#$ip_tos,$tcp_options,$opt_A,$opt_D,$tcp_header_rest,$opt_J,
	#$opt_P,$opt_U,$opt_X,$opt_e,$opt_h,$opt_i,$pad,$opt_j,
	#$snoop_length_orig,$http_header,$opt_p,$opt_q,$opt_r,
	#$header_rest,$tcp_ack,$ether_dest,$ether_src,$skip,
	#$ip_length,$udp_length,$ip_options,$ip_checksum,
	#$opt_b,$opt_B,$opt_l,$opt_L,$ip_rest,$ip_hop,$ip_reserved,
	#$ip_flow,$icmp_rest,$opt_f,$opt_z);
	#
	#  Perl < 5.6 and 5.6 code (but not elegant)
	#
	@Once_is_okay = ($ip_ttl,$udp_checksum,$ip_ident,$tcp_length_data,
	$ip_tos,$tcp_options,$opt_A,$opt_D,$tcp_header_rest,$opt_J,
	$opt_P,$opt_U,$opt_X,$opt_e,$opt_h,$opt_i,$pad,$opt_j,
	$snoop_length_orig,$http_header,$opt_p,$opt_q,$opt_r,
	$header_rest,$tcp_ack,$ether_dest,$ether_src,$skip,
	$ip_length,$udp_length,$ip_options,$ip_checksum,$tcp_rst,$tcp_fin,
	$opt_b,$opt_B,$opt_l,$opt_L,$ip_rest,$ip_hop,$ip_reserved,
	$ip_flow,$icmp_rest,$opt_f,$opt_z,$junk1,$opt_H,$opt_I,$opt_R);
}


# Check_Command - check which is the network sniffing command and save
#		it to $command. #61
#
sub Check_Command {
    #debug
    print "\n Check_Command subroutine called \n" unless $Arg{quiet};
	
	#
	#  Check which OS we are on, die if it looks incompatible
	#
	if ($^O eq "linux") {
		#
		#  The "-s9999" tells tcpdump to keep a packet up to this 
		#  size, otherwise the default is 68 bytes. Some versions of
		#  tcpdump allow using "-s0" for unlimited.
		#
		$command = "tcpdump -s9999 -w";
	} elsif ($^O eq "solaris") {
		$command = "snoop -o";
	} else {
		die "ERROR54: Can't find the sniffer command for \"$^O\".\n" .
		 "\t Please use log mode instead.\n";
	}

	#
	#  Check username
	#
	if ($ENV{LOGNAME} ne "root") {
		print STDERR "WARNING: Are you root? If not, this probably "
		 . "won't work. Trying anyway...\n";
	}
}


#
# Process_Command_Line_Arguments - this process the command line arguments
#	and sets various globals which are kept in %Arg. It also prints
#	usage and exists if need be. #62
#
sub Process_Command_Line_Arguments {
    
	my $result;

	#
	#  Process Global Defaults into %Arg
	#
	foreach (@Save_As_HTML_TCP_Ports) {
		$Arg{Save_As_TCP_HTML}{$_} = 1; 
	}
	foreach (@Save_As_HTML_UDP_Ports) { 
		$Arg{Save_As_UDP_HTML}{$_} = 1; 
	}
	foreach (@Save_As_TCP_Playback_Ports) { 
		$Arg{Save_As_TCP_Playback}{$_} = 1; 
	}
	foreach (@Save_As_UDP_Playback_Ports) { 
		$Arg{Save_As_UDP_Playback}{$_} = 1; 
	}
	foreach (@Save_As_X11_Playback_Ports) { 
		$Arg{Save_As_X11_Playback}{$_} = 1; 
	}
	foreach (@Save_As_HTML_X11_Ports) { 
		$Arg{Save_As_X11_HTML}{$_} = 1; 
	}
	foreach (@Save_As_VNC_Playback_Ports) { 
		$Arg{Save_As_VNC_Playback}{$_} = 1; 
	}

	if (defined $ARGV[0]) {
		### Dump full help if asked
		&Usage_Full if $ARGV[0] eq "--help";
	
		### Dump another info if asked
		&Usage_Info if $ARGV[0] eq "--help2";
	}

	#
	#  Command Line Defaults
	#
	$Arg{output_csv} = 1;
	$Arg{output_raw} = 1;
	$Arg{output_apps} = 1;
	$Arg{output_TCP} = 1;
	$Arg{output_UDP} = 1;
	$Arg{output_ICMP} = 1;
	$Arg{output_info} = 0;
	$Arg{output_hex} = 0;
	$Arg{output_index} = 0;
	$Arg{keydata} = 0;
	$Arg{debug} = 0;

	#
	#  Check correct switches were used
	#
	Getopt::Long::Configure ("bundling");
	$result = GetOptions (
				"application!" => \$opt_a,
				"a" => \$opt_a,
				"csv" => \$opt_c,
				"c" => \$opt_c,
				"everything" => \$opt_e,
				"e" => \$opt_e,
				"h" => \$opt_h,
				"info!" => \$opt_i,
				"i" => \$opt_i,
				"q|quiet" => \$opt_q,
				"raw!" => \$opt_r,
				"r" => \$opt_r,
				"v|verbose" => \$opt_v,
				"index!" => \$opt_x,
				"x" => \$opt_x,
				"A" => \$opt_A,
				"H|hex" => \$opt_H,
				"I" => \$opt_I,
				"R" => \$opt_R,
				"U|noudp" => \$opt_U,
				"T|notcp" => \$opt_T,
				"Y|noicmp" => \$opt_Y,
				"X" => \$opt_X,
				"D|dir=s" => \$opt_D,
				"b|playtcp=s" => \$opt_b,
				"B|playudp=s" => \$opt_B,
				"l|htmltcp=s" => \$opt_l,
				"L|htmludp=s" => \$opt_L,
				"m|min=s" => \$opt_m,
				"M|max=s" => \$opt_M,
				"o|sort=s" => \$opt_o,
				"p|port=s" => \$opt_p,
				"P|noport=s" => \$opt_P,
				"j|ipaddr=s" => \$opt_j,
				"J|noipaddr=s" => \$opt_J,
				"s|runonce=s" => \$opt_s,
				"S|runmany=s" => \$opt_S,
				"z|runredo" => \$opt_z,
				"f|filter=s" => \$opt_f,
				"k|keydata" => \$opt_k,
				"debug" => \$opt_debug,
				"bench" => \$opt_bench
	 );
	
	#
	#  Process switches
	#
	&Usage() if ($opt_h || ! $result);
	$Arg{output_csv} = 1 if $opt_c;
	$Arg{output_raw} = 1 if $opt_r or $opt_v;
	$Arg{output_hex} = 1 if $opt_H or $opt_e;
	$Arg{output_info} = 1 if $opt_i or $opt_v;
	$Arg{quiet} = 1 if $opt_q;
	$Arg{output_UDP} = 0 if $opt_U;
	$Arg{output_TCP} = 0 if $opt_T;
	$Arg{output_ICMP} = 0 if $opt_Y;
	$Arg{output_apps} = 0 if ($opt_A || (defined $opt_a && $opt_a eq "0"));
	$Arg{output_index} = 0 if ($opt_X || (defined $opt_x && $opt_x eq "0"));
	$Arg{output_allhtml} = 1 if $opt_e;
	my $extra_TCPplayback = $opt_b;
	my $extra_UDPplayback = $opt_B;
	my $extra_TCPhtml = $opt_l;
	my $extra_UDPhtml = $opt_L;
	my $ports_accepted = $opt_p;
	my $ports_rejected = $opt_P;
	my $ips_accepted = $opt_j;
	my $ips_rejected = $opt_J;
	$Arg{output_dir} = $opt_D;
	$Arg{filter} = $opt_f || "";
	$Arg{minbytes} = 0;
	$Arg{maxbytes} = 0;
	$Arg{sort} = "time";
	$Arg{keydata} = 1 if $opt_k;
	$Arg{debug} = 1 if $opt_debug;
	$Arg{bench} = 1 if $opt_bench;

	#
	#  Check for min/max bytes
	#
	if (defined $opt_m) {
		if ($opt_m =~ /k$/) {
			$opt_m =~ s/k$//;
			$opt_m *= 1024;
		}
		$Arg{minbytes} = $opt_m;
	}
	if (defined $opt_M) {
		if ($opt_M =~ /k$/) {
			$opt_M =~ s/k$//;
			$opt_M *= 1024;
		}
		$Arg{maxbytes} = $opt_M;
	}

	#
	#  Check for sort option
	#
	if (defined $opt_o) {
		if ($opt_o !~ /^(time|size|type|ip)$/) {
			print STDERR "ERROR55: Sort must be \"time\", " .
			 "\"size\", \"type\" or \"ip\".\n";
			&Usage();
		}
		$Arg{sort} = $opt_o;
	}
	
	#
	#  Check for standalone redo mode
	#
	if (defined $opt_z) {
		$Arg{redo} = 1;
		if (defined $Arg{output_dir}) {
			# bad luck
			die "ERROR56: Can't use an output dir "
			 . "$Arg{output_dir} in redo mode.\n\n";
		}
	}

	#
	#  Check for standalone mode
	#
	elsif (defined $opt_s || defined $opt_S) {
		$Arg{standalone} = 1;
		if (defined $opt_s) {
			if ($opt_s =~ /,/) {
				die "ERROR57: Unexpected comma found in " .
				 "\"-s$opt_s\" (did you mean \"-S$opt_s\"?)\n";
			}
			$Arg{mins} = $opt_s;
			$Arg{count} = 1;
		} elsif (defined $opt_S) {
			my ($mins,$count) = split(/,/,$opt_S);
			$Arg{mins} = $mins;
			### -1 means endless
			$Arg{count} = $count || -1;
		} 
	}

	#
	#  This is normal mode
	#  
	else {
		$Arg{normal} = 1;
	}
			
	#                    
	#  Build accepted or rejected port list as %Arg{Port_Accepted},...
	#
	if (defined $ports_accepted) {
		$Arg{port_accept} = 1;
		foreach $port (split(/,/,$ports_accepted)) {
			$Arg{Port_Accepted}{$port} = 1;
		}
	}
	if (defined $ports_rejected) {
		$Arg{port_reject} = 1;
		foreach $port (split(/,/,$ports_rejected)) {
			$Arg{Port_Rejected}{$port} = 1;
		}
	}
	
	#
	#  Build accepted or rejected IP list as %Arg{IP_Accepted},...
	#
	if (defined $ips_accepted) {
		$Arg{ip_accept} = 1;
		foreach $ip (split(/,/,$ips_accepted)) {
			$Arg{IP_Accepted}{$ip} = 1;
		}
	}
	if (defined $ips_rejected) {
		$Arg{ip_reject} = 1;
		foreach $ip (split(/,/,$ips_rejected)) {
			$Arg{IP_Rejected}{$ip} = 1;
		}
	}
	
	#
	#  Add extra ports to playback or HTML
	#
	if (defined $extra_TCPplayback) {
		foreach $port (split(/,/,$extra_TCPplayback)) {
			$Arg{Save_As_TCP_Playback}{$port} = 1; 
		}
	}
	if (defined $extra_UDPplayback) {
		foreach $port (split(/,/,$extra_UDPplayback)) {
			$Arg{Save_As_UDP_Playback}{$port} = 1; 
		}
	}
	if (defined $extra_TCPhtml) {
		foreach $port (split(/,/,$extra_TCPhtml)) {
			$Arg{Save_As_TCP_HTML}{$port} = 1; 
		}
	}
	if (defined $extra_UDPhtml) {
		foreach $port (split(/,/,$extra_UDPhtml)) {
			$Arg{Save_As_UDP_HTML}{$port} = 1; 
		}
	}
	
	#
	#  Check infile was provided, or print usage
	#
	if (! defined $ARGV[0] && ! ($Arg{standalone} || $Arg{redo})) { 
		&Usage(); 
	}
	@{$Arg{infiles}} = @ARGV;
	
	#debug
    print "\n Process_Command_Line_Arguments subroutine called \n" unless $Arg{quiet};
}


#
# Usage - print command usage and exit. #63
#
sub Usage {
        #debug
        print "\n Usage subroutine called \n" unless $Arg{quiet};
        
        print "USAGE: chaosreader [-acehikqrvxAHIRTUXY] [-D dir] 
	           [-b port[,...]] [-B port[,...]] 
	           [-j IPaddr[,...]] [-J IPaddr[,...]] 
 	           [-l port[,...]] [-L port[,...]] [-m bytes[k]]
	           [-M bytes[k]] [-o \"time\"|\"size\"|\"type\"|\"ip\"]
                   [-p port[,...]] [-P port[,...]] 
	           infile [infile2 ...]
       chaosreader -s [mins] | -S [mins[,count]]   
	           [-z] [-f 'filter']
   eg, chaosreader infile      # Create application session files, indexes
       chaosreader -v infile   # Verbose - Create ALL files
       chaosreader -i infile   # Create info files
       chaosreader -r infile   # Create raw files
       chaosreader -S 2,5      # Standalone - sniff network 5 times by 2 mins.
       chaosreader -h          # Print a brief help (this)
       chaosreader --help      # Print verbose help and version
       chaosreader --help2     # Print massive help\n\n";
        exit(0);
}


# Usage Full - print command usage and exit. #64
#
sub Usage_Full {
    #debug
    print "\n Usage_Full subroutine called \n" unless $Arg{quiet};
    
        print "Version 0.94, 01-May-2004

USAGE: chaosreader [-acehikqrvxAHIRTUXY] [-D dir] 
                   [-b port[,...]] [-B port[,...]] 
                   [-j IPaddr[,...]] [-J IPaddr[,...]] 
                   [-l port[,...]] [-L port[,...]] [-m bytes[k]]
                   [-M bytes[k]] [-o \"time\"|\"size\"|\"type\"|\"ip\"]
                   [-p port[,...]] [-P port[,...]] 
                   infile [infile2 ...]

       chaosreader -s [mins] | -S [mins[,count]]   
	           [-z] [-f 'filter']

   chaosreader           # Create application session files, indexes

   -a, --application     # Create application session files (default)
   -c, --csv			 # Create csv file
   -e, --everything      # Create HTML 2-way & hex files for everything
   -h                    # Print a brief help
   --help                # Print verbose help (this) and version
   --help2               # Print massive help
   -i, --info            # Create info file
   -q, --quiet           # Quiet, no output to screen
   -r, --raw             # Create raw files
   -v, --verbose         # Verbose - Create ALL files .. (except -e)
   -x, --index           # Create index files (default)
   -A, --noapplication   # Exclude application session files
   -H, --hex             # Include hex dumps (slow)
   -I, --noinfo          # Exclude info files
   -R, --noraw           # Exclude raw files
   -T, --notcp           # Exclude TCP traffic
   -U, --noudp           # Exclude UDP traffic
   -Y, --noicmp          # Exclude ICMP traffic
   -X, --noindex         # Exclude index files
   -k, --keydata         # Create extra files for keystroke analysis
   -D dir    --dir dir        # Output all files to this directory
   -b 25,79  --playtcp 25,79  # replay these TCP ports as well (playback)
   -B 36,42  --playudp 36,42  # replay these UDP ports as well (playback)
   -l 7,79   --htmltcp 7,79   # Create HTML for these TCP ports as well
   -L 7,123  --htmludp 7,123  # Create HTML for these UDP ports as well
   -m 1k     --min 1k         # Min size of connection to save (\"k\" for Kb)
   -M 1024k  --max 1k         # Max size of connection to save (\"k\" for Kb)
   -o size   --sort size      # sort Order: time/size/type/ip (Default time)
   -p 21,23  --port 21,23     # Only examine these ports (TCP & UDP)
   -P 80,81  --noport 80,81   # Exclude these ports (TCP & UDP)
   -s 5      --runonce 5      # Standalone. Run tcpdump/snoop for 5 mins
   -S 5,10   --runmany 5,10   # Standalone, many. 10 samples of 5 mins each
   -S 5      --runmany 5      # Standalone, endless. 5 min samples forever
   -z        --runredo        # Standalone, redo. Rereads last run's logs
   -j 10.1.2.1  --ipaddr 10.1.2.1    # Only examine these IPs
   -J 10.1.2.1  --noipaddr 10.1.2.1  # Exclude these IPs
   -f 'port 7'  --filter 'port 7'    # With standalone, use this dump filter

eg1, 
     tcpdump -s9000 -w output1          # create tcpdump capture file
     chaosreader output1                # extract recognised sessions, or, 
     chaosreader -ve output1            # gimme everything, or, 
     chaosreader -p 20,21,23 output1    # only ftp and telnet...
eg2,
     snoop -o output1                   # create snoop capture file instead
     chaosreader output1                # extract recognised sessions...
eg3,
     chaosreader -S 2,5		# Standalone, sniff network 5 times for 2 mins
				# each. View index.html for progress (or .text)
";
        exit(0);
}


# Usage_Info - print another information about this scripts #65
#
sub Usage_Info {
    #debug
    print "\n Usage_Info subroutine called \n" unless $Arg{quiet};
    
	open (MYSELF,"$0") || die "ERROR58: I can't see myself: $!\n";
	@Myself = <MYSELF>;
	close MYSELF;

	### Print comment from top of code
	foreach $line (@Myself) {
		last if $line !~ /^#/;
		last if $line =~ /^# Todo:/;
		next if $line =~ m:^#!/usr/bin/perl:;
		$line =~ s/^#/ /;
		print $line;
	}
	print "\n";

        exit(0);
}



__END__

Reminders for myself
====================
/s for multiline match


Comments style:

# Micro comment

### Tiny Comment

#
#  Small comment
#

#
# --- Meduim Comment ---
#

#########################
# --- Large Comment ---
#

########################
# --- Huge Comment --- #
########################


Error message style
===================

die "ERROR#: message: $!\n";



Data types,
===========
	%Arg
		-> @infiles
		-> output_raw
		-> output_hex
		-> output_UDP
		-> output_info
		-> output_apps
		-> output_index
		-> output_allhtml
		-> Save_As_TCP_HTML
			-> $port
		-> Save_As_UDP_HTML
			-> $port
		-> Save_As_TCP_Playback
			-> $port
		-> Save_As_UDP_Playback
			-> $port
		-> Port_Accepted
			-> $port
		-> Port_Rejected
			-> $port
		-> ip_accept
		-> ip_reject
		-> IP_Accepted
			-> $ip
		-> IP_Rejected
			-> $ip
		-> debug
		-> standalone
		-> redo
		-> normal
		-> mins
		-> count
		-> output_dir
		-> quiet
		-> infile
		-> minbytes
		-> maxbytes

	%IP
		-> time
			-> $packet_time
				-> ver
				-> src
				-> dest
				-> protocol
				-> frag
					-> $ip_frag
				-> fragged
				-> drops
		-> id
			-> $ip_id
				-> StartTime

	%TCP 
		-> id
			-> $session_id
				-> src
				-> dest
				-> source	# SYN seen
				-> src_port
				-> dest_port
				-> Aseq
					-> $$tcp_seq
				-> Bseq
					-> $$tcp_seq
				-> time
					-> $time
						-> dir
						-> data
				-> BothHTML
				-> StartTime
				-> EndTime
				-> size
				-> knowndir

	%UDP
		-> id
			-> $session_id
				-> src
				-> dest
				-> src_port
				-> dest_port
				-> RawA
				-> RawB
				-> time
					-> $time
				-> BothHTML
				-> StartTime
				-> EndTime
				-> size

	%ICMP
		-> time
			-> type
			-> code
			-> src
			-> dest
			-> Partial
			-> ver
			-> size

	%Count
		-> IP
		-> IPprotocols
		-> TCPports
		-> UDPports
		-> EtherType

	%CountMaster
		(as above)

	%Index
		-> @HTML
		-> @Text
		-> Time_Order
			-> $session_timeid
		-> Sort_Lookup
			-> $session_timeid

	%Image
		-> @HTML
			-> links
			-> info
		-> notempty

	%GETPOST
		-> @HTML
			-> query
			-> info
		-> notempty

	%Hex
		-> $type
			-> $session_id
				-> offset
				-> pos
				-> hextext
				-> hexhtml
				-> viewtext
				-> viewhtml

	%Filenames
		-> $time
			-> filename
			-> service
			-> session_id

	@Master
		-> starttime
		-> endtime
		-> duration
		-> size
		-> dir
		-> file
