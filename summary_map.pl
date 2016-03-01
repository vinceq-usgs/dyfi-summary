#! /usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use XML::Simple;
use Plot_summary;
use File::Copy;
use JSON::Tiny;

use lib '/home/shake/ciim3/perl';
use Common;
use File;
use DB;
use Parameters;
use Region;
use Cdi;

my $ciimdir = "/home/shake/ciim3";
my $cdidir = "/home/shake/PROJECTS/summary/cdi_zip";

my $URL = 'http://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&eventid=%s';

my $badfile = "./badfiles.txt";
my $STARTDATE = 1991;
my $ENDDATE = 2015;

# For Art
#$STARTDATE = 2003; $ENDDATE = 2013;

my $EVENT;

unless (@ARGV) {
  print << "USAGE";
Usage: 
$0 time|start|sequence [usonly]
  time  \t- date (e.g. 2010 or 2010-01)
  start \t- all events in the database
  yearly \t- step through each year
  monthly \t- step through each year by month

  map=us \t- don't do Global map
  map=global \t- don't do US map
  map=nocal \t- NoCal map 
  -noplot \t- Don't run GMT
USAGE

 exit;
}

my $outdir = './output';
my $db = new DB;

print "Reading events from DB (for filtering).\n";
my $EVENTS = $db->db_query('event',"invisible = 0 or invisible is null");
unlink "./filter_cdi.txt" if (-e "filter_cdi.txt");

my $sequence;

my $date = shift @ARGV;
my $dates;
my $start;

($date eq 'start') ?  $start = 1 :
($date eq 'yearly') ? $sequence = 'yearly' :
($date eq 'sequence') ? $sequence = 'monthly' : 
($date =~ /^\d{4}/) ? print "Doing $date only.\n" : 
die "Unknown date $date";

my $USONLY = grep /usonly/, @ARGV;
my $NOPLOT = grep /-noplot/,@ARGV;

$NOPLOT = 1;

my $map = '';
foreach (@ARGV) {
  next unless (/^map=(.*?)$/);
  $map = $1;
  last;
}


my %bounds;
if ($map eq 'alaska') {
  $USONLY = 1;
  %bounds = ( 
    lat_span => 19,
    lon_span => 45.0,
    center_lat => 61.75,
    center_lon => -149.9,
    proj => 'Q-147.9/62.75/6.5',
    jpeg_xspan => 612,
    jpeg_yspan => 684,
    border_flags => '-N1/2/0 -A1000 -N2/2/0',
    plot_width => 6.5,
  );
}
if ($map eq 'hawaii') {
  $USONLY = 1;
  %bounds = ( 
    lat_span => 4,
    lon_span => 6.25,
    center_lat => 20.7,
    center_lon => -157.5,
    proj => 'Q-157.0/20.7/6.5',
    jpeg_xspan => 612,
    jpeg_yspan => 684,
    border_flags => '-N1/2/0 -A1000 -N2/2/0',
    plot_width => 6.5,
  );
}
if ($map eq 'puerto_rico') {
  $USONLY = 1;
  %bounds = ( 
    lat_span => .8,
    lon_span => 3,
    center_lat => 18.2,
    center_lon => -66.5,
    proj => 'Q-66.45/18.2/6.5',
    jpeg_xspan => 612,
    jpeg_yspan => 684,
    border_flags => '-N1/2/0 -A1000 -N2/2/0',
    plot_width => 6.5,
  );
}
if ($map eq 'nocal') {
  $USONLY = 1;
  %bounds = ( 
    lat_span => 1.15,
    lon_span => 1.0,
    center_lat => 37.85,
    center_lon => -122.25,
    proj => 'Q-122/37.75/6.5',
    jpeg_xspan => 612,
    jpeg_yspan => 684,
    border_flags => '-N1/2/0 -A1000 -N2/2/0',
    plot_width => 6.5,
  );
}
 
$STARTDATE = 1990 if ($USONLY and $STARTDATE<1990);

#my $HISTORIC = read_inputfiles();
my $HISTORIC;

if ($start) {
  my $allentries = {};
  add_historic_entries($allentries);
  foreach my $idate ($STARTDATE..$ENDDATE) {
    add_entries($allentries,$idate);
  }
  $allentries = aggregate($allentries);
  plot('all',$allentries);
}

elsif ($sequence) {

  my $allentries = {};
  add_historic_entries($allentries);

  # LOOP OVER EACH MAP
  my $date;
  foreach my $end_date ($STARTDATE+1..$ENDDATE) {
  foreach my $month (1..12) {
    if ($sequence eq 'yearly') {
      last if ($month > 1);
      $date = $end_date;
    }
    else {
      $month = "0$month" if ($month<10);
      $date = "${end_date}-$month";
    }
    print "Trying $date.\n";

    add_entries($allentries,$date) or next;
    $allentries = aggregate($allentries);
    plot("${STARTDATE}_$date",$allentries);
  }
  }
}

else {

  my $allentries = {};
  add_historic_entries($allentries);
  add_entries($allentries,$date);

  my $n_city = scalar keys %{$allentries->{'city'}};
  my $n_zip = scalar keys %{$allentries->{'zip'}};

  print "Now plotting $n_zip zips and $n_city cities.\n";
  $allentries = aggregate($allentries); 
  plot($date,$allentries);
}

exit;

sub prep_entries {
  my $date = shift;
  my $file = input_file($date);
  print "Checking for file $file.\n";
  return $file if (-e $file);

  print "Creating new file $file.\n";
  my $dates = ($date) ? get_dates($date) : undef;
  print "Date: $dates (was $date)\n";
  my $eventlist = get_eventlist($dates);
  return unless (@$eventlist);

  my $raw = read_events($eventlist);
  my $sorted = sort_entries($raw);

  print "Writing to file $file.\n";
  write_to_xml($file,$date,$sorted);

  sleep 1; # Let file write finish
  return $file;
} 

sub get_eventlist {
  my $dates = shift;

  print "Date range: $dates->[0],$dates->[1].\n";
  my @wheres;
  push @wheres,"eventdatetime >= '$dates->[0]' and eventdatetime <= '$dates->[1]'"
 if ($dates);
  push @wheres, "nresponses >= 5";
  push @wheres, "invisible != 1";
  push @wheres, "eventid NOT RLIKE '_se'";
  push @wheres, "loc NOT RLIKE 'Virtual'";
  push @wheres, "loc NOT RLIKE 'Scenario'";
  push @wheres, "loc NOT RLIKE 'SCENARIO'";

  my $where = join ' AND ' ,@wheres;

  print "Querying database for: $where\n";
  my $result = $db->db_query('event',$where,'eventid');
  my @eventlist = sort keys %$result;
  my $count = scalar @eventlist;
  print "Got $count events.\n";

  return \@eventlist;
}

sub get_dates {
  my $date = shift || (localtime)[5] + 1900;
  my ($start,$end);

  print "get_dates got $date.\n";

  if ($date =~ /^(\d+)-(\d+)$/) {
    my ($yr,$mo) = ($1,$2);
    $start = "${yr}-${mo}-01 00:00:00";
    $mo++;
    if ($mo > 12) {
      $mo = 1; $yr++;
    }
    $end = "${yr}-${mo}-01 00:00:00";
  }
  elsif ($date =~ /^(\d+)_(\d+)$/) {
    my ($yr1,$yr2) = ($1,$2);
    $start = "${yr1}-01-01 00:00:00";
    $end = "${yr2}-12-31 23:59:59";
  }
  elsif ($date =~ /^\d\d\d\d$/) {
    $start = "${date}-01-01 00:00:00";
    $end = "${date}-12-31 23:59:59";
  }
    
  print "Date range is $start to $end.\n--\n";

  my $result = [$start,$end];
  return $result;
}

sub read_events {
  my $list = shift;

  my $all_entries = {};
  my $nevids = 0;
  my $nentries = 0;
  my $n = 0;
  my $ntotal = scalar @$list;

  foreach my $eventid (@$list) {
    $n++;
    $EVENT = $eventid;
    my $dir = File::event_dir($eventid);

    my $input = "$dir/cdi_zip.xml";
    my $data;
    if (-s $input) {
#      print "Using existing event.\n";
    }
    elsif (-s ($input = "$cdidir/$eventid.xml")) {
#        print "Using $eventidi precomputed.\n";
    }
    elsif (($input = get_cdi_xml_from_web($eventid)) and -s $input) {
      print "($n / $ntotal) Using $eventid from web.\n";
    }
    else {
      print "($n / $ntotal) Rerunning $eventid.\n";
      $input = create_cdi_xml($eventid);
      unless ($input and -s $input) {
        print "Could not create data for $eventid, skipping.\n";
        system("echo $eventid >> missing_cdi.txt");
        next;
      }
    }
    $data = read_cdi_xml($input);
    unless ($data) {
      print "Could not get data for $eventid, skipping.\n";
      system("echo $eventid >> missing_cdi.txt");
      next;
    }
    
    $nevids++;
    foreach my $loc (keys %$data) {
      my $cdi = $data->{$loc}{cdi};
      my $nresp = $data->{$loc}{nresp};

      # FILTER
      next if (cdifilter($eventid,$loc,$cdi,$nresp));

      $all_entries->{$loc}{cdi} = $cdi unless
        (exists $all_entries->{$loc} and
         $all_entries->{$loc}{cdi} > $cdi);
      $all_entries->{$loc}{nresp} += $nresp;
      $nentries+= $nresp;


    }
    print "$nevids : got $nentries entries so far.\n"
      unless ($nevids % 100);
  #  last if ($nevids > 500); ### DEBUG
  }

  print "Got $nevids events and $nentries entries.\n";
  return $all_entries;
}

sub read_cdi_xml {
  my $file = shift;
  my $data;
  my $output = {};

  eval { $data = XMLin($file) };

  if ($@) {
    print $@;
    system "echo $file >> $badfile";
    return;
  }
  return unless ($data);

  my $ref = $data->{'cdi'};
  unless ($ref) {
    print "Malformed $file, skipping.\n";
    return;
  }
  my $rr = ref $ref;

  if ($rr =~ /ARRAY/) {
    foreach my $dataset (@$ref) {
      my $list = $dataset->{'location'};
      load($output,$list);
    }
  }
  elsif ($rr =~ /HASH/) {
    my $list = $ref->{'location'};
    load($output,$list);
  }
  else {
    Common::dump($ref,1);
    die "Could not get ref for $ref.\n";
  }
  my $c = scalar keys %$output;
#  print "File $file had $c locs.\n";
  return $output;
}

sub get_cdi_xml_from_web {
  my $evid = shift;
  die "Invalid evid" unless ($evid);

  my $url = sprintf $URL,$evid;

  my $resultfile = "./tmp.$$";
  unlink $resultfile if (-e $resultfile);

  print "Trying to grab $evid from web.\n";
  print "URL: $url\n";
  system("/usr/bin/wget -a wget.log -O $resultfile '$url'");
  return unless (-s $resultfile);

  my $results = File::slurp($resultfile);
  my $json = JSON::Tiny::decode_json($results);
  my $dyfi = $json->{'properties'}{'products'}{'dyfi'};
  my $product;
  if (defined $dyfi->[1]) {
    my %resps;
    my @sorted = sort { $b->{'properties'}{'numResp'} <=> $a->{'properties'}{'numResp'} } @$dyfi;
    foreach my $product (@sorted) {
      my $id = $product->{'code'};
      my $nresps = $product->{'properties'}{'numResp'};
      print "Sorted $id got $nresps responses.\n";
    }
    $product = $sorted[0];
  }  
  else {
    $product = $dyfi->[0];  
  }
  my $link = $product->{'contents'}{'cdi_zip.xml'}{'url'};
  print "Got link: $link.\n";

  my $dest = "$cdidir/$evid.xml";
  my $command = "/usr/bin/wget -a wget.log -O $dest $link"; 
  system($command);
  return $dest;
}
  
sub create_cdi_xml {
  my $evid = shift;
  die "Invalid evid" unless ($evid);
  print "Could not get data for $evid.\n";
  return;

  system("cd $ciimdir; $ciimdir/ciimfast.pl event=$evid");
  my $file = "$ciimdir/data/$evid/cdi_zip.xml";
  unless (-e $file) { 
    print "Could not create $file\n";
    return;
  }

  my $newfile = "$cdidir/$evid.xml";
  move($file,$newfile);
  system("/bin/rmdir $ciimdir/data/$evid");
 
  die "Could not find $newfile" unless (-e $newfile);
  return $newfile;
}
 
sub load {
  my ($data,$list) = @_;
  my $entries = $list;
  if ((ref $list) =~ /HASH/) {
    $entries = [ $list ];
  }

  foreach my $entry (@$entries) {
    my ($index,$cdi,$nresp,$suspect) = extract($entry);
    next if (defined $suspect and $suspect);
    my $d = {
      cdi => $cdi,
      nresp => $nresp,
    };
    if ($cdi > 8) {
    $suspect = 0 unless ($suspect);
    printf "ID: %s LOC: %s CDI: %s (%s responses) [$suspect]\n",
      $EVENT,
      $index,
      $cdi,
      $nresp,
    }
# Intensity filter
#    if ($cdi > 8 and $nresp <= 5) {
#      print "Skipping this.\n";
#      next;
#    }
    $data->{$index} = $d;
  }
  return $data;
}

sub extract {
  my $data = shift;

  my $name = $data->{'name'}[0];
  $name = sprintf "%.2f,%.2f", $data->{'lat'},$data->{'lon'}
    unless ($name =~ /^\d{5}/);

  my $cdi = $data->{'cdi'} or die "Could not find CDI.\n";
  my $nresp = $data->{'nresp'};
  my $suspect = $data->{'suspect'};
  $suspect = %$suspect if (ref $suspect);
  return ($name,$cdi,$nresp,$suspect);
}

sub sort_entries {
  my $data = shift;
  my @alldata;

  print "Getting locations...\n";
  my $results = $db->db_query('city_2009','population > 0',
    'id, population, latitude, longitude' );

  my %cities;
  foreach my $loc (values %$results) {
    my $index = sprintf "%.2f,%.2f", $loc->{'latitude'},$loc->{'longitude'};
    $cities{$index} = $loc->{'population'};
  }

  print "Done with locations.\n";

  foreach my $loc (sort keys %$data) {
    my $cdi = $data->{$loc}{cdi};
    my $nresp = $data->{$loc}{'nresp'};

    if ($loc =~ /^\d{5}/) {
      next unless valid_zip($loc);
      push @alldata, { zip => $loc, cdi => $cdi , type => 'zip', nresp => $nresp };
      next;
    }

    my $pop = $cities{$loc} if (exists $cities{$loc});
    unless ($pop) {
      print "No data found for $loc!\n";
      next;
    }

    my ($lat,$lon) = split /,/,$loc;
    push @alldata, { lat => $lat, lon => $lon, pop => $pop, cdi => $cdi, type => 'city', nresp => $nresp };
  }

  return \@alldata;
}

sub write_to_xml {
  my ($file,$date,$data) = @_;

  $date = '' unless ($date);
  my $ref = { loc => $data, date => $date };
  my $xml = XMLout($ref,
    AttrIndent => 1,
    KeyAttr => { 'location' => 1 },
    );
  print "Writing to $file.\n";
  open OUT, ">$file";
  print OUT $xml;
  close OUT;

}

sub valid_zip {
  my $zip = File::zip_file($_);
  return (-e $zip);
}

sub input_file {
  my $date = shift;
  
  my $file = "./entries/entries.$date";
  $file .= ".xml";
  return $file;
}

sub output_file {
  my ($d1,$d2) = @_;
  my $label = (defined $d2) ? "$d1.$d2" : $d1;
  my $file = "$outdir/summary.$label";
  $file .= ($map) ? ".$map"
         : ($USONLY) ? ".usonly"
         : '';
  $file .= ".ps";

  return $file;
}

sub add_historic_entries {

  print "SKIPPING HISTORIC ENTRIES\n";
  return;
  my $out = shift;
  my $n_added = 0;
  my $n_new = 0; 
  foreach my $bydate (values %$HISTORIC) {
  foreach my $data (values %$bydate) { 
    my $type = $data->{'type'};
    next if ($USONLY and $type ne 'zip');

    my $loc = $data->{'zip'} || 
      (sprintf "%.2f,%.2f",$data->{'lat'},$data->{'lon'});

    my $nresp = $data->{'nresp'} || 1;
    my $cdi = $data->{'cdi'} || $data->{'ii'};

    if (exists $out->{$type}{$loc}) {
      $n_added++;
      $out->{$type}{$loc}{'nresp'} += $nresp;
      $out->{$type}{$loc}{'cdi'} = $cdi 
        if ($cdi > $out->{$type}{$loc}{'cdi'});
      next;
    }

    $n_new++;
    my $newdata = {
      nresp => $nresp,
      type => $type,
      cdi => $cdi,
      loc => $loc,
    };
    $newdata->{'pop'} = $data->{'pop'} if ($data->{'pop'} and $type eq 'city');
    $out->{$type}{$loc} = $newdata;
  }} 
  print "Got $n_added existing and $n_new new locs from historic.\n";
  return $out;
}

  

sub add_entries {
  my ($out,$date) = @_;

  print "Prepping entries for $date.\n";
  my $file = prep_entries($date);
  return $out unless ($file);

  my $n_added = 0;
  my $n_new = 0;

  print "Reading $file.\n";
  my $input = XMLin($file);
  return unless ($input);
  my $locs = $input->{'loc'};

  unless (ref $locs eq 'ARRAY') {
    $locs = [ $input->{'loc'} ];
  }

  foreach my $data (@$locs) {
    my $type = $data->{'type'};
    my $zip = $data->{'zip'};
    next if ($USONLY and $type ne 'zip');
    next if (defined $map and $map eq 'nocal' and defined $zip and ($zip <90000 or $zip>99999));

    my $loc = $data->{'zip'} || 
      (sprintf "%.2f,%.2f",$data->{'lat'},$data->{'lon'});
#      (sprintf "%.1f,%.1f",$data->{'lat'},$data->{'lon'});

    my $nresp = $data->{'nresp'};
    my $cdi = $data->{'cdi'};

    if (exists $out->{$type}{$loc}) {
      $n_added++;
      $out->{$type}{$loc}{'nresp'} += $nresp;
      $out->{$type}{$loc}{'cdi'} = $cdi 
        if ($cdi > $out->{$type}{$loc}{'cdi'});
      next;
    }

    $n_new++;
    my $newdata = {
      nresp => $nresp,
      type => $type,
      cdi => $cdi,
      loc => $loc,
    };
    $newdata->{'pop'} = $data->{'pop'} if ($type eq 'city');
    $out->{$type}{$loc} = $newdata;
  } 
  print "Got $n_added existing and $n_new new locs from this file.\n";

  return $out;
}

sub plot {
  my ($date,$data) = @_;

  my $file = output_file($date);
  my $jpeg = $file;
  $jpeg =~ s/\.ps$/\.jpg/;

  my $xml = $file;
  $xml =~ s/\.ps$/\.xml/;

  write_to_xml($xml,$date,outformat($data));
  return if ($NOPLOT);

  my $plot = Plot_summary->new(get_map_params($date,$file,$data));
  $plot->execute;

  posterize($file);

#  my $flags = '-colorspace RGB -crop 2140x920+200+2020 -antialias';
  my $flags = '-colorspace RGB  -antialias';
  print "Convert flags: $flags\n";

  print "Converting $file to $jpeg.\n";
  unlink $jpeg if (-e $jpeg);
  Plot_summary::ps_to_jpeg($file,$jpeg,$flags);

#  system "scp $jpeg quake\@ehpdevel.cr.usgs.gov:/home/www/data/DYFI/events/us/SUMMARY/us/";
#  system "scp ./summary.pdf quake\@ehpdevel.cr.usgs.gov:/home/www/data/DYFI/events/";

}

sub get_map_params {
  my ($name,$file,$data) = @_;
  my $params = Parameters->new;

  $params->add_params( {
    eventid => 'SUMMARY',
    latitude => 0,
    longitude => 0,
    lat_span => 130,
    lon_span => 358,
    center_lat => 10,
    center_lon => 0,
    lat_offset => 0,
    lon_offset => 0,
    topo => 'NONE',
    proj => 'Q0/0/6.5',
    border_flags => '-N1/2/0 -A1000',
    plot_commands => 'basemap titles cdiplot timestamp close',
    link => $file,
    river_flags => '',
    mmiscale_file => undef,
    title_size => 8,
    timestamp_format => '0.0 -0.2 4 0 0 5 %s',
    jpeg_xspan => 612,
    jpeg_yspan => 684,
    cdi_outline_pen => '',
    plot_width => '6.5',

    cdidata => 'zip',
    CDI => reformat($data),
    year => $name,

    });
  if (%bounds) {
    $params->add_params(\%bounds);
  }
  elsif ($USONLY) {
    my $wb = -126;
    my $eb = -66.5;
    my $nb = 50;
    my $sb = 25;

    my $lat_span = abs($nb - $sb);
    my $lon_span = abs($wb - $eb);
    my $center_lat = ($nb + $sb)/2;
    my $center_lon = ($eb + $wb)/2;

    $params->add_params( {
      lat_span => $lat_span,
      lon_span => $lon_span,
      center_lat => $center_lat,
      center_lon => $center_lon,
      proj => 'Q-95/38/6.5',
#      proj => 'B-95/37/29.5/45.5/6.5',
      border_flags => '-A1000 -N2/2/0',
#      water_color => '255',
      water_color => '128/128/255',
    });
  }
 
  print "Link is $file\n"; 
  return $params;
}

sub posterize {
  my $file = shift;

  open FILE,$file or die "Could not posterize $file";
  my @out;
  while (my $line = <FILE>) {
    chomp $line;
    $line = '1.0 1.0 scale' if $line eq '0.24 0.24 scale';
    $line = '%%BoundingBox: 0 0 2592 3456' if $line =~ /BoundingBox/;
    $line = 'PSLevel 1 gt { << /PageSize [2592 3456] '
    . '/ImagingBBox null >> setpagedevice } if'
      if $line =~ /PageSize/;
   push @out,$line;
  }
  close FILE;
  open FILE, ">$file";
  foreach (@out) { print FILE "$_\n"; }
  close FILE;
}

sub reformat {
  my $in = shift;
  my $out = {};

  foreach my $ref (values %{$in->{'city'}},values %{$in->{'zip'}}) {
    my $index = $ref->{'loc'};
    my $d = { 
      cdi => $ref->{'cdi'}, 
      nresp => $ref->{'nresp'}, 
      loc => $index,
      type => $ref->{'type'},
    };

    if ($index =~ /,/) {
      my ($lat,$lon) = split /,/,$index;
      $d->{'loc'} = "${lat}::${lon}";
      $d->{'lon'} = $lat;
      $d->{'lat'} = $lon;
      $d->{'pop'} = $ref->{'pop'};
    }
    $out->{$index} = $d;
  }
  return $out;

}

sub read_inputfiles {
  my $dir = "./input";
  my %data;
 
  foreach my $file (glob "$dir/geocoded.*.csv") {
    my ($year) = ($file =~ /geocoded.([^.]*).csv$/);
    next unless ($year);
  
    print "Got year $year, opening file $file.\n";
    my $bad = 0;
 
    my $fh = File::new_fh($file,"<");
    while (my $line = <$fh>) {
      $line =~ s/\s*$//;
      my ($ii,$lon,$lat,$zip) = split /,/,$line;
      unless ($zip =~ /^\d{5}$/) {
        $bad++;
        next;
      }
      my $oldcdi = $data{$year}{$zip};
      next if (defined $oldcdi and $oldcdi >= $ii);

      $data{$year}{$zip} = {
        type => 'zip',
        ii => $ii, 
        lat => $lat,
        lon => $lon,
        zip => $zip,
      };
    }
    print "Got $bad bad ZIPs.\n";
  }
  
  return \%data;
}

sub outformat {
  my $data = shift;
  my @output;

  foreach my $type (keys %$data) {
    print "Reformatting type $type.\n";
    foreach my $base_key (sort keys %{$data->{$type}}) {
      my $orig_val = $data->{$type}{$base_key};

      my %val;
      foreach my $key (keys %$orig_val) {
        $val{$key} = $orig_val->{$key};
      }

      if ($type eq 'city') {
        my $loc = $val{'loc'};
        my ($lat,$lon) = split /,/,$val{'loc'};
        delete $val{'loc'};
        $val{'lat'} = $lat;
        $val{'lon'} = $lon;
      }
      else {
        $val{'zip'} = $val{'loc'};
        delete $val{'loc'}; 
      }
      push @output,\%val;
    } 

  }

  return \@output;
}

sub aggregate {
  my $allentries = shift;
  my $newentries = {};

  my $citydata = $allentries->{'city'};
  print "Reaggregating city data (",scalar keys %$citydata," cities).\n";
  foreach my $oldkey (sort keys %$citydata) {
    my $data = $citydata->{$oldkey};
    $data = makebin($data);
    my $key = $data->{'loc'};

    if (exists $newentries->{$key}) {
      if ($newentries->{$key}{'cdi'} < $data->{'cdi'}) {
        $newentries->{$key}{'cdi'} = $data->{'cdi'};
      }
      $newentries->{$key}{'nresp'} += $data->{'nresp'};
      next;
    }
    
    $newentries->{$key} = $data;
  }    

     
  $allentries->{'city'} = $newentries;
  print "Now ",scalar keys %$newentries," bins.\n"; 
  return $allentries;
}

sub makebin {
  my $data = shift;
  my $newdata = {
    type => $data->{'type'},
    cdi => $data->{'cdi'},
    nresp => $data->{'nresp'},
  };
  $newdata->{'pop'} = $data->{'pop'} if ($data->{'pop'});

  my ($lat,$lon) = (split /,/,$data->{'loc'});
  $newdata->{'loc'} = sprintf "%.1f,%.1f",$lat+0.5,$lon+0.5;

  return $newdata;
}

sub cdifilter {
  my ($evid,$loc,$cdi,$nresp) = @_;

  my $mag = $EVENTS->{$evid}{'mag'};
  $mag = 'UNKNOWN' unless ($mag);
  return if ($cdi < 6.5); 

  system("echo $evid,$mag,$loc,$cdi,$nresp >> filter_cdi.txt")
    if ($loc !~ /,/);
  return;   
}

1;

