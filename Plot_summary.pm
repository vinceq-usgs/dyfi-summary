package Plot_summary;

use strict;
use Carp;
use IO::File;
#use Smart::Comments '###';

use lib "./perl";
use Base;
use Common;
use Topo;

our $VERBOSE = undef;

my $run = \&Common::command;
my $gmt_bin = $Base::gmt_bin;

my @PLOT_PARAMS;
my @PLOT_SEQUENCE = qw( begin base data post close );

# Set up divisions for plotting city circles

my @POPULATION_DIVISIONS = (10_000,100_000,2_000_000);
my @POPULATION_PLOTSIZES = (0.01,   0.02,   0.03,     0.05);

sub new {
  my ($class,$p) = @_;
  my $self = {  
                params   => {},
                output   => {},
                dir      => '',
                text_block => {},
             };

  bless $self,$class; 

  my %params = %$p;
  $self->{params} = \%params;

  $self->_init;

  
  return $self;
}

#-----------------------------------------------------------------------

sub params {
  my $self = shift;
  
  return $self->{params};
}

#-----------------------------------------------------------------------

sub _init {
  my $self = shift; 

  my %sub = ();
  $self->{subroutines} = \%sub;

  $self->_calculate_params;
  $self->_validate_params;

  # Makes map ticks look better after convert
  $run->("$gmt_bin/gmtset PAGE_COLOR 254/254/254");

  return \%sub; 
}

push @PLOT_PARAMS,qw( plot_res plot_width proj plot_dpi lat_span lon_span );
sub _calculate_params {
  my $self = shift;
  my $p = $self->params;
  my $par = {};

  my $dir = File::event_dir($p->{eventid});
  $self->{dir} = $dir;

  my $link = $p->{'link'};
  my $outputfile = "$dir/$link";
  my $psfile = "$dir/" . File::product_link($p->{'link'},'ps');
  $self->{'output'} = { jpg => $outputfile, ps => $psfile };

  #-----------------------------------------------------
  # For all plotting functions 

  my ($proj,$bound,$epilat,$epilon,$clat,$clon,$latspan,$lonspan,
      $n,$s,$e,$w,$plot_flags,$res);

  my $proj = $p->{'proj'};

  $epilat = $p->{latitude};
  $epilon = $p->{longitude};

  $clat = $p->{'center_lat'};
  $clon = $p->{'center_lon'};

  # Compute basemap flags, if necessary

#  unless ($p->{'basemap_flags'}) {
    $p->{'basemap_flags'} = "-B" 
      . $self->get_basemap_ticks . "WS";

    $p->{'basemap_flags'} = '';
#  }

  my $lat_span = $p->{lat_span} / 2;
  my $lon_span = $p->{lon_span} / 2;

  my $n = $clat + $lat_span;
  my $s = $clat - $lat_span;
  my $w = $clon - $lon_span;
  my $e = $clon + $lon_span;

#  print "PLOT PROJ: $proj BOUNDS: $w $e $s $n\n";

  $bound = "$w/$e/$s/$n";
  $plot_flags = "-J$proj -R$bound";

  @{%$par}{qw( plot_nbound plot_sbound plot_ebound plot_wbound  
               plot_bound plot_proj plot_flags)} = 
    ($n,$s,$e,$w,$bound,$proj,$plot_flags);

  # lonlat2xy requires plot_flags
  $self->add_params( { plot_flags => $plot_flags } );
  (@$par{qw( plot_xmax plot_ymax )}) = $self->lonlat2xy($e,$n);

  #-----------------------------------------------------
  # For titles
  my $lat = (abs $epilat) . ( $epilat < 0 ? 'S' : 'N' );
  my $lon = (abs $epilon) . ( $epilon < 0 ? 'W' : 'E' );

  my ($title,$title2,$subtitle);
  $title = 'DYFI Summary: ';
  my $year = $p->{year};
  $title .= ($year) ? $year : "all dates";
  
  $par->{title_text} = $title;
  print "Skipping timestamp.\n"; $par->{timestamp} = ' ';
#  $par->{timestamp} = "Processed: ". scalar localtime();
  
  #-----------------------------------------------------
  # To be filled out by cdiplot
  $par->{n_areas} = 0;
  $par->{n_points} = 0;
  $par->{n_geos} = 0;
  $par->{n_resp} = 0;
  $par->{maxcdi} = 0;

  #-----------------------------------------------------
  # Misc.

  if (scalar keys %{$p->{'CDI'}} > 500) { 
#    print "Disabling topo areafill for large maps\n";
    $p->{'topo'} = 'NONE';
  }

  #-----------------------------------------------------

  $self->add_params($par);

  # Finally, record the mapproject function for Imap
  $self->add_params({ 
    mapproject_f => sub { return $self->lonlat2xy(@_); }
  });

}

sub add_params {
  my ($self,$p) = @_;

  foreach my $key (keys %$p) {
    $self->{'params'}{$key} = $p->{$key};
  }
}
 
sub _validate_params {
  my $self = shift;
  my $p = $self->params;

  foreach my $param (@PLOT_PARAMS) {
    croak "ERROR: Plot::new missing parameter $param"
      unless defined $p->{$param};

    if ($param =~ /_file$/ and $p->{$param} ne '') {
      $p->{$param} = File::validate($p->{eventid},$p->{$param});
    }
  }

}

#-----------------------------------------------------------------------

sub execute {
  my ($self,@products) = @_;
  my $p = $self->params;
  my ($psfile,$tmp,$command);

  $psfile = $self->{output}{ps};
  unlink $psfile if (-e $psfile);

  #-------------------------------------------------------------
  # Erase previous temp files

  foreach my $part (@PLOT_SEQUENCE) {
    $tmp = $psfile . ".$part";
    unlink $tmp if (-e $tmp);
  }

  #-------------------------------------------------------------
  # Create plots

  my $cmdlist = [ split /\s+/,$p->{plot_commands} ];
  foreach my $cmd (@$cmdlist) {
    
    #print "Plot::$cmd\n";
    $self->$cmd;
  } 

  #------------------------------------------------------------
  # Put them all together

  foreach my $part (@PLOT_SEQUENCE) {
    $tmp = $psfile . ".$part";
    next unless (-s $tmp); 

    $command = (-e $psfile) ? "cat $tmp >> $psfile" : "cp $tmp $psfile"; 
    $run->($command);
    unlink $tmp;
  }

  #$self->ps_to_products(@products);

  return;
} 

#-----------------------------------------------------------------------

sub run_ps {
  my ($self,$cmd,$part) = @_;
  if (defined $VERBOSE) {
    (ref $VERBOSE) ? print $VERBOSE "Running: $cmd\n"
                   : print "Running: $cmd\n";
  }
  my $file = $self->{output}{ps}.".$part"; 
  my $direct = (-e $file) ? '>>' : '>';

  my $results = `$cmd`;
  croak "ERROR: Plot::run_ps:\n$cmd\n$?" if ($?);
  
  my $fh = File::new_fh($file,$direct)
    or croak "ERROR: Plot::run_ps unable to open file $file"; 
  print $fh $results
    or croak "ERROR: Plot::run_ps unable to write to file $file";
  $fh->close
    or croak "ERROR: Plot::run_ps unable to close file $file";
  return $results;
}

#-----------------------------------------------------------------------

push @PLOT_PARAMS,qw( plot_flags basemap_flags basemap_color );
sub basemap {
  my ($self) = @_;
  my $p = $self->params;
  my $command;

  $run->("$gmt_bin/gmtset BASEMAP_TYPE PLAIN FRAME_PEN 2");
  $command = "$gmt_bin/psbasemap -Y2 -G$p->{basemap_color} "
           . "$p->{plot_flags} "
           . "$p->{basemap_flags} -K";
  $self->run_ps($command, 'begin');

}

#-----------------------------------------------------------------------

push @PLOT_PARAMS,qw( hiway_file hiway_pen );
sub hiways {
  my ($self) = @_;
  my $p = $self->params;
  return unless (my $file = $p->{'road_file'});

  my $flags = "$p->{plot_flags} -W$p->{hiway_width}/$p->{hiway_color} -M"; 
  my $command = "$gmt_bin/psxy $file $flags -O -K";
  $self->run_ps($command, 'base');
}

#-----------------------------------------------------------------------

push @PLOT_PARAMS,qw( fault_file fault_pen );
sub faults {
  my ($self) = @_;
  my $p = $self->params;
  return unless (my $file = $p->{'fault_file'});

  my $flags = "$p->{'plot_flags'} -W$p->{fault_pen} -M";
  my $command = "$gmt_bin/psxy $file $flags -O -K"; 
  $self->run_ps($command, 'base');
}

#-----------------------------------------------------------------------

push @PLOT_PARAMS,qw( ff_file ff_pen );
sub finite_fault {
  my ($self) = @_;
  my $p = $self->params;
  return unless (my $file = $p->{'ff_file'});

  my $flags = "$p->{'plot_flags'} -W$p->{ff_pen} -M";
  my $command = "$gmt_bin/psxy $file $flags -O -K"; 
  $self->run_ps($command, 'base');
}

#-----------------------------------------------------------------------

push @PLOT_PARAMS,qw( coast_res coast_width border_flags river_flags
                      water_color );
sub gmtcoast {
  ### Plotting gmtcoast

  my ($self) = @_;
  my $p = $self->params;
 
  my $res = substr($p->{coast_res},0,1);
  my $width = $p->{'coast_width'};
  my $flags;

  $flags .= " -D$res -W$width -A10" if ($res and $width);
  $flags .= " $p->{'border_flags'}" if ($p->{'border_flags'});
  $flags .= " $p->{'river_flags'}" if ($p->{'river_flags'});
  $flags .= " -S$p->{'water_color'}" if ($p->{'water_color'});
  return unless ($flags);

  $flags = "$p->{'plot_flags'} $flags";
  my $command = "$gmt_bin/pscoast $flags -O -K";

  $self->run_ps($command, 'base');
}

sub gmt_coast_postdata {
  ### Special redraw coast layer for geocodes ONLY
  ##  Run after plot_geocodes

  my ($self) = @_;
  my $p = $self->params;

  my $res = substr($p->{coast_res},0,1);
  my $width = $p->{'coast_width'};
  my $flags;

  $flags .= " -D$res -W$width -A10" if ($res and $width);
  $flags .= " $p->{'border_flags'}" if ($p->{'border_flags'});
  $flags .= " -S$p->{'water_color'}" if ($p->{'water_color'});
  return unless ($flags);

  $flags = "$p->{'plot_flags'} $flags";
  my $command = "$gmt_bin/pscoast $flags -O -K";

  $self->run_ps($command, 'data');
}


#-----------------------------------------------------------------------

sub addon {
  my ($self,$addon_params) = @_;
  my $p = $self->params;
  my ($command,$is_file);
  return unless (defined $addon_params and %$addon_params);

  my ($data,$type,$addon_flags) = @{%$addon_params}{'data','type','flags'};
  my $flags = $p->{'plot_flags'};
  $flags .= " $addon_flags" if ($addon_flags);

  # Is this addon a file? If so, then grab the file
  # This filename should already be expanded and checked if necessary 
  if ($data =~ /^file::(.*)$/) {
    my $file = $1;
    $flags .= " $file";
    $is_file = 1;
  }

  if    ($type eq 'xy')   { $command = 'psxy'; }
  elsif ($type eq 'text') { $command = 'pstext'; }
  else { croak "Plot::addon: unknown plot type $type"; }

  $command = "$gmt_bin/$command $flags -K -O";

  if ($is_file) {
    $command .= " <<END\n$data\nEND\n";
  }
  $self->run_ps($command, 'base');
}

#-----------------------------------------------------------------------

push @PLOT_PARAMS,qw( title_text title_size );
sub titles {
  my ($self) = @_;
  my $p = $self->params;
  my ($title_x,$title_y,$subtitle_y,$text,$command);

  $title_x    = $p->{plot_width};
  $title_x    = 1;
  $title_y    = $p->{plot_ymax} + 0.2;

  my $font = $p->{'font'};

  $text = '';
  if ($p->{title2_text}) {
    $text = "$title_x $title_y $p->{title_size} 0 $font CM "
          . "$p->{title2_text}\n";
    $title_y += 0.25; 
  }
  $text .= "$title_x $title_y $p->{title_size} 0 $font CM "
             . "$p->{title_text}\n"; 
#  $text .= "$title_x $subtitle_y $p->{subtitle_size} 0 $font CM "
#             . "$p->{subtitle_text}"; 

# -W adds white rectangle-- seems to make better looking text
#  my $flags = "-JX$p->{plot_ymax}/$p->{plot_width} "
  my $flags = "-JX$p->{plot_width} "
            . "-R0/$p->{plot_ymax}/0/$p->{plot_width} -N";
  my $command = "$gmt_bin/pstext $flags -O -K -W255 <<END\n"
              . "$text\nEND\n";
  $self->run_ps($command, 'base');
}
  
#-----------------------------------------------------------------------

sub city_labels {
  my ($self) = @_;
  my $p = $self->params;

  my $file = $p->{city_labels};
  my ($citylist,$is_label);

  if (0 and !defined $file or $file =~ /^db::(.*)$/) {
    my $dbtable = (defined $file) ? $1 : undef;

    my $db = DB->new;
    my %paramlist = (
      table  => $dbtable,
      sort   => 'population',
      );
    @paramlist{qw( n s e w )} = @{%$p}{qw( plot_nbound plot_sbound 
                                           plot_ebound plot_wbound )};
    my @citylist = $db->get_city_data_by_lookup(\%paramlist);
    $db->close;

    ### Disabling plot cities block
    #$self->_plot_cities_block(\@citylist);
  }
  else {
    $self->_plot_cities_simple($file);
  }
}     

#-----------------------------------------------------------------------

push @PLOT_PARAMS,qw( epicenter_width epicenter_pen epicenter_fillcolor );
sub epicenter {
  my ($self) = @_;
  my $p = $self->params;
  my ($epipen,$flags,$command);

  my $pen = $p->{'epicenter_pen'};
  if ($p->{'maxcdi'} > 6.0) {
    $pen = $p->{'epicenter_pen_hi'} || $pen;
  } 

  # Flags: -Sa star
  $epipen = sprintf "-W%s -Sa%s", $pen, $p->{epicenter_width};
  $epipen .= " -G$p->{epicenter_fillcolor}" if ($p->{epicenter_fillcolor});
  $flags = "$p->{plot_flags} $epipen ";

  $command = "$gmt_bin/psxy $flags -O -K <<END\n"
           . "$p->{longitude} $p->{latitude}\nEND\n";

  $self->run_ps($command, 'post');
}

#-----------------------------------------------------------------------

push @PLOT_PARAMS,qw( timestamp_format timestamp );
sub timestamp {
  my ($self) = @_;
  my $p = $self->params;

  # -W draw white rectangle (looks better with convert)

  my $flags = "-JX$p->{plot_ymax}/$p->{plot_width} "
            . "-R0/$p->{plot_ymax}/0/$p->{plot_width} -W255 -N";
  my $line  = sprintf $p->{timestamp_format},$p->{timestamp};
 
  my $command = "$gmt_bin/pstext $flags -O -K <<END\n"
              . "$line\nEND\n";
  
  $self->run_ps($command, 'base');
}

#-----------------------------------------------------------------------

sub topobase {
  my ($self) = @_;
  my $p = $self->params;
  my ($topo,$th,$flags,$command,@zips);
  my ($grad_file,$ii_file);

#  print "TOPO: $p->{'topo'}\n";
#  print "LONSPAN: $p->{'lon_span'}\n";

  return if ($p->{topo} eq 'NONE');

  if ($p->{'lat_span'} < 1.5 or $p->{'lat_span'} > 10) {
    print "Disabling topo for lat_span $p->{'lon_span'} (must be "
        . "between 1.5 and 10 degrees)";
    $p->{'topo'} = 'NONE';
    return;
  }
 
  my $cditype = $p->{'cdidata'};
  unless ($th = Topo->new($p)) {
    carp "WARNING: Plot::topobase could not create topo map, "
       . "switching to notopo";
    $p->{topo} = 'NONE'; 
    return;
  }

  $grad_file = $th->grad_file;
  $ii_file   = $th->ii_file; 

  $self->areafill($ii_file) if ($ii_file and $cditype eq 'zip');

  # Flags: -I shading gradient file; -C MMI colorscale
  $flags = "$p->{plot_flags} -I$grad_file -C$p->{cpt_file}";

  $command = "$gmt_bin/grdimage $flags $ii_file -O -K";
  $self->run_ps($command, 'base');

  unlink $ii_file;
}

#-----------------------------------------------------------------------

sub areafill {
  my ($self,$grd) = @_;
  my $p = $self->params;
  my ($maskfile,$flags,$basecommand);
  my $locs = $p->{'CDI'};

  return unless (defined $grd and -s $grd);
  return unless ($locs);

  $maskfile = ($self->{dir})."/maskfile.grd";

  # Topography might give us slightly different boundaries.
  # We need to use those for the maskfile instead of our bounds
  # so the topo and maskfile will mesh properly.

#  $flags = Topo::get_map_flags($grd);
#  $flags .= " -NNan/%s/%s";

  $flags = "-R$p->{plot_bound} -I$p->{plot_res} -NNaN/%s/%s";
  $basecommand = "$gmt_bin/grdmask $flags -G$maskfile -M -F %s";

  # Suppress grdmask's numerous useless warnings 
  open my $olderr, '>&', \*STDERR;

  foreach my $index (keys %$locs) { 

    next unless (_is_zip_area($index));
    my ($loc,$ii,$zipfile,$command);
    $zipfile = File::zip_file($index);

    $loc = $locs->{$index};
    $ii = $loc->{'cdi'};
    next unless ($ii);

    unlink $maskfile if (-e $maskfile);
    $command = sprintf $basecommand,$ii,$ii,$zipfile;

    open STDERR, '>/dev/null';
    $run->($command);
    open STDERR, '>&', $olderr;

  # -N be lenient with grdfile bounds
    $command = "$gmt_bin/grdmath $maskfile $grd MAX = $grd";
    $run->($command); 

  }
  return;
}

sub clip {
  my $self = shift;
  my $p = $self->params;
  my ($flags,$command,$maskfile);
  my $locs = $p->{'CDI'};

  return if ($p->{topo} eq 'NONE');
  return unless ($locs);

  $maskfile = ($self->{dir})."/maskfile.grd";
  unlink $maskfile if (-e $maskfile);
  
  foreach my $index (keys %$locs) { 
    next unless (_is_zip_area($index));
    my $zipfile = File::zip_file($index);
    
    $run->("cat $zipfile >> $maskfile");
  }
  unless (-s $maskfile) {
    carp "WARNING: Plot::clip could not create mask file $maskfile";
    return;
  }

  # Flags: -N clip outside polygons
  $flags = "$p->{plot_flags} -M -N";
  $command = "$gmt_bin/psclip $flags $maskfile -O -K";
  $self->run_ps($command, 'base');
  return;
}

sub unclip {
  my $self = shift;
  my $maskfile = ($self->{dir})."/maskfile.grd";
  return unless (-e $maskfile);
 
  # Flags: -C end clipping 
  my $command = "$gmt_bin/psclip -C -O -K";
  $self->run_ps($command, 'base');
   unlink $maskfile;
  return;
}

#-----------------------------------------------------------------------

push @PLOT_PARAMS,qw( cpt_file );
sub cdiplot {
  my $self = shift;
  my ($p,$locs,$cditype,$is_zip,$is_geo,$n_points,$maxcdi,$is_topo);
  my @areas;
  my @points;
  my @geos;

  $p = $self->params;
  $locs = $p->{'CDI'};
  return unless ($locs);

  $cditype = ($p->{'cdidata'});
  $is_zip = ($cditype =~ /^zip/);
  $is_geo = ($cditype =~ /^geo/);

  $is_topo = ($p->{'topo'} ne 'NONE');

  $maxcdi = 0;
  foreach my $index (keys %$locs) {
    my $ref = $locs->{$index};

    ($is_geo and $ref->{type} =~ /^geo/ and $ref->{lat} != -999) ?
      push @geos,$ref : 
    ($is_zip and $ref->{type} =~ /^zip|area/) ?
      push @areas,$ref : 
    ($ref->{type} =~ /zip|city/) ?
      push @points,$ref : die;

    $maxcdi = $ref->{'cdi'} if ($ref->{'cdi'} > $maxcdi); 
  }

  my $n_resp;
  foreach my $area (@areas,@points,@geos) {
    $n_resp += $area->{nresp};
  } 

  $p->{'n_areas'} = scalar @areas;
  $p->{'n_points'} = scalar @points;
  $p->{'n_geos'} = scalar @geos;
  $p->{'n_resp'} = $n_resp;
  $p->{'maxcdi'} = $maxcdi;

  if ($is_geo) {
#    print "Trying geocodes: " .(scalar @geos). ".\n";
  }

  if ($is_geo and @geos) {
    $self->_plot_geocodes(\@geos);
    $self->gmt_coast_postdata;
  }
  else {
    $self->_plot_polygons(\@areas) if (@areas);
    $self->_plot_circles(\@points) if (@points);
  }
  #$self->_plot_count();

  # postcdi
  my $res = substr($p->{coast_res},0,1);
  my $width = $p->{'coast_width'};
  my $flags = "$p->{'plot_flags'} -S$p->{'water_color'}";
  my $command = "$gmt_bin/pscoast -O -K -N1/4/0 -N2/4/0 -D$res $flags";
  $self->run_ps($command, 'data');

   
  return;
}

sub _plot_geocodes {
  ### plot_geocodes
  my ($self,$areas) = @_;
  my ($p,$is_topo,$allzipsfile,$flags,$command);

#  print "Plot::_plot_geocodes\n"; 

  $p = $self->params;
  $is_topo = ($p->{topo} ne 'NONE');

  my $allgeosfile = ($self->{dir})."/all_geos.xy";
  unlink $allgeosfile if (-e $allzipsfile);
  my $fh = File::new_fh($allgeosfile);

  my $func = $p->{'geocode_func'};
  croak "ERROR: Plot::_plot_geocodes could not find geocode func"
      . " (need Params::load_geo first)" unless ($func);
 
  ### Geocoding areas: scalar @$areas
 
  foreach my $area (@$areas) {
    my ($loc,$cdi,$nresp)  = @{%$area}{qw( loc cdi nresp )};

    my $b = $func->($loc);
    my $polytext = $b->{'polytext'};
    print $fh "> -Z$cdi\n$polytext";
  }
  $fh->close;
 
  #Flags: -C with -M: colors found in data file
  #Flags: -L Force closed polygons
  $flags = "$p->{plot_flags} -C$p->{cpt_file} -M -L";
  $flags .= " -W$p->{cdi_outline_pen}" if ($p->{cdi_outline_pen});

  $command = "$gmt_bin/psxy $allgeosfile $flags -O -K";
  $self->run_ps($command,'data'); 
 
  unlink $allgeosfile;
}


sub _plot_polygons {
  my ($self,$areas) = @_;
  my ($p,$is_topo,$allzipsfile,$flags,$command);

#  print "Plot::_plot_polygons\n"; 
  $p = $self->params;
  $is_topo = ($p->{topo} ne 'NONE');

  $allzipsfile = ($self->{dir})."/all_zips.xy";
  unlink $allzipsfile if (-e $allzipsfile);

  my ($cdi,$zip,$zipfile);
 
  foreach my $area (@$areas) { 
    $cdi = $area->{'cdi'};
    $zip = $area->{'loc'}; 
    $zipfile = File::zip_file($zip);
    next unless (-e $zipfile); 
    #-------------------------------------------------------
    # For topo mode, just plot polygon outlines
    # Otherwise, plot colored polygons; add '-Zcolor' 
    # to headers 
    #-------------------------------------------------------

    ($is_topo) ? $run->("cat $zipfile >> $allzipsfile") 
               : _mod_and_copy($zipfile,$cdi,$allzipsfile);
  }
 
  # Flags: -L Force closed polygons

  $flags = "$p->{plot_flags} -M -L";
  $flags .= " -C$p->{cpt_file}" unless ($is_topo);
  $flags .= " -W$p->{cdi_outline_pen}" if ($p->{cdi_outline_pen});

  $command = "$gmt_bin/psxy $flags $allzipsfile -O -K";
  $self->run_ps($command,'data'); 

  unlink $allzipsfile; 
}

sub _plot_circles {
  my ($self,$areas) = @_;
  my ($p,$allpointsfile,$flags,$command);

#  print "Plot::_plot_circles\n"; 
  $p = $self->params;
  $allpointsfile = ($self->{dir})."/all_points.xyz";

  foreach my $area (@$areas) {
    my ($loc,$x,$y,$cdi,$pop)  = @{%$area}{qw( loc lon lat cdi pop)};
    my $size = pop_plotsize($area->{pop});
    my $symbol = "c";
     
    $run->("echo $x $y $cdi ${symbol}${size} >> $allpointsfile"); 
     
  }
  return unless (-e $allpointsfile);
  #Flags: -S symbols found in data file
  $flags = "$p->{plot_flags} -C$p->{cpt_file} -S  ";
  $flags .= " -W$p->{cdi_outline_pen}" if ($p->{cdi_outline_pen});

  $command = "$gmt_bin/psxy $allpointsfile $flags -: -O -K";
  $self->run_ps($command,'data'); 
  print "Running $command\n";
  unlink $allpointsfile;
}

sub _plot_count {
  my $self = shift;
  my ($p,$flags,$command,$text);

  $p = $self->params;

  my $n_resp = $p->{'n_resp'};
  my $n_areas = $p->{'n_areas'};
  my $n_points = $p->{'n_points'};
  my $n_geos = $p->{'n_geos'};
  my $maxcdi = $p->{'maxcdi'};

  if ($n_geos) {
    $text = "$n_resp responses in $n_geos blocks";
  }
  elsif ($n_areas or $n_points) {
    $text = "$n_resp responses in ";
    $text .= ("$n_areas ZIP " . ($n_areas==1? "code" : "codes")) if ($n_areas);
    $text .= " and " if ($n_points and $n_areas);
    $text .= ("$n_points " . ($n_points==1? "city" : "cities")) if ($n_points);
  }
  else {
    $text = "No responses";
  }
  print "Text: $text\n";
#  $text .= " (Max CDI = ".Cdi::rom($maxcdi).")" if ($maxcdi);  

  # Flags: -N don't clip at map boundaries; -W rectangle (o outline)
  $flags = "-JX$p->{plot_ymax}/$p->{plot_width} "
            . "-R0/$p->{plot_ymax}/0/$p->{plot_width} -N";
  $flags .= " -W255o2/0 -N";
  my $command = "$gmt_bin/pstext $flags -O -K <<END\n"
              . "0.05 0.15 4 0 0 9 $text\n"
              . "END\n";

  $self->run_ps($command,'close'); 
}


sub _mod_and_copy {
  my ($zipfile,$cdi,$allzipsfile) = @_;
  my ($in,$out);

  $in = File::new_fh($zipfile,'<');
  $out = File::new_fh($allzipsfile,'>>');
  while (my $line = <$in>) {
    $line =~ s/^>.*$/> -Z$cdi\n/;
    print $out $line;
  }
  $in->close or 
    croak "WARNING: Plot::_mod_and_copy could not close $zipfile";
  $out->close or 
    croak "WARNING: Plot::_mod_and_copy could not close $allzipsfile";

}

sub pop_plotsize {
  my $pop = shift;

  $pop = 10_000 unless (defined $pop);

  # HACK FOR POPS FROM OLD DB ENTRIES
  $pop *= 1_000 if ($pop < 1_000);
  my $counter = 0;
  foreach my $div (@POPULATION_DIVISIONS) {
    return $POPULATION_PLOTSIZES[$counter] if ($pop < $div);
    $counter++;
  }
  return $POPULATION_PLOTSIZES[$counter];
} 

sub _is_zip_area {
  my $loc = shift;

  return if ($loc !~ /^\d+$/);
  my $file = File::zip_file($loc);
  return $file if (-s $file);
  return;
}

#-----------------------------------------------------------------------

push @PLOT_PARAMS, qw( latitude lat_offset );
sub close {
  my $self = shift;
  my $p = $self->params;
  my $command;

  if ($p->{'n_points'}) {
    $self->plot_citysizes;
  }

  my $mapscale_flag = $self->get_mapscale_flag;

  $run->("$gmt_bin/gmtset BASEMAP_TYPE PLAIN FRAME_PEN 1");
  $command = "$gmt_bin/psbasemap $p->{plot_flags} "
           . "$p->{basemap_flags} $mapscale_flag  -O";

  $self->run_ps($command,'close'); 

  my $file = $Base::mmiscale_ps;
#  $self->run_ps("cat $file",'close');

}

sub plot_citysizes {
  my $self = shift;
  my $p = $self->params;

  my @poptext = ("<10,000"," 10,000+"," 100,000+"," 2M+");
  my @diams   = @POPULATION_PLOTSIZES;
  my @popname_offset = (0.05,0.1,0.15,0.2);
  my @circle_offset = (0.05,0.1,0.15,0.2);

  my $command;

  my $width = $p->{'plot_width'};
  my $top = $p->{'plot_ymax'};

  # Change this corner to switch the legend location
  my $legend_corner = 'ne';
  my %cornerxy = ( nw => [ 0.15, $top - 0.2],
                   ne => [ $width - 0.35, $top - 1.0 ],
                   se => [ $width - 0.98, 0.8 ],
                   sw => [ 0.7, 1.9 ],
                 );

  my ($leg_x,$leg_y) = @{$cornerxy{$legend_corner}};

  my $ini_x = $leg_x - 0.025;
  my $ini_y = $leg_y + 0.05;
  my $cor_x = $leg_x + 0.30;
  my $cor_y = $ini_y - 0.35;

  my $rectangle = "$ini_x $ini_y\n"
                . "$ini_x $cor_y\n"
                . "$cor_x $cor_y\n"
                . "$cor_x $ini_y\n";
  my $boxcolor = "255/255/200";
  my $flags = "-JX$width/$top -R0/$width/0/$top -O -K";

  # Plot the legend box 
  $command = "$gmt_bin/psxy $flags -W1/0 -G$boxcolor -N "
           . "<< END\n"
           . "$rectangle\nEND\n";
 
  # Clip so circles stay inside the box
  $command .= "$gmt_bin/psclip $flags << END\n"
            . "$rectangle\nEND\n";

  # Plot legend title
  $leg_x += 0.0;
  $command .= "$gmt_bin/pstext $flags -N << END\n"
            . "$leg_x $leg_y 4 0 0 ML CITY SIZE\nEND\n";

  # Now loop through circles (backwards, biggest first)

  my $d = 3;
  $leg_x += 0.05;
  $leg_y -= 0.03;
  my $circle_y = $leg_y ;

  foreach my $diameter (reverse @diams) {
    my $ploty = $leg_y - $popname_offset[$d];
    my $pop = $poptext[$d];
    $command .= "$gmt_bin/pstext $flags -N << END\n"
              . "$leg_x $ploty 3 0 0 ML $pop\nEND\n";

    my $circle_x = $leg_x - 0.04;
    $ploty = $leg_y - $circle_offset[$d];
    $command .= "echo $circle_x $ploty | $gmt_bin/psxy "
              . "$flags -Sc$diameter -W1/0 -G255 -N\n";
    $d--;
  }

  # Now unclip for the rest of the map
  $command .= "$gmt_bin/psclip $flags -C\n";

  $self->run_ps($command, 'close');
}

sub get_mapscale_flag {
  my $self = shift;
  my $p = $self->params;

  my $width = $p->{'plot_width'};
  my $top = $p->{'plot_ymax'};

  my $ypos = 0.4;
  my $xpos = 5.5;
  my $length = $self->_mapscale_length or return;
  my $center_lon = $p->{'longitude'} + $p->{'lon_offset'}; 
  my $center_lat = $p->{'latitude'} + $p->{'lat_offset'}; 
  my $flags = sprintf "-Lx%s/%s/%s/%s:km:b",
    $xpos, $ypos, $center_lat, $length;
  return $flags;
}

sub _mapscale_length {
  my $self = shift;
  my $p = $self->params;
  my @lengths = qw( 0.1 1 5 10 20 30 40 50 100 200 300 400 500 1000 2500 );

  my $span = $p->{'lat_span'} / $p->{'plot_width'}; # Deg / inch
#  $span *= 69.172; # * Miles / degree => Miles / inch
  $span *= 111; # * Km / degree => km / inch

  while (@lengths) {
    my $try = shift @lengths;
    return $try if ($lengths[0] > $span);
  }
  carp "WARNING: _mapscale_length got bad span $span mi.\n";
  return;
}

#-----------------------------------------------------------------------

sub ps_to_products {
  my ($self,@products) = @_;

  $self->to_jpeg;
  $self->to_pdf;
}

push @PLOT_PARAMS,qw( jpeg_quality jpeg_xspan jpeg_yspan plot_dpi
  mmiscale_height );
sub to_jpeg {
  my $self = shift;
  my $p = $self->params;
  my ($ps,$jpg,$yspan,$ht,$ht_scalebar,$ycut,$flags);

  $ps = $self->{'output'}{'ps'};
  $jpg = $self->{'output'}{'jpg'};

  croak "ERROR: Plot::to_jpeg missing outputfile"
    unless ($jpg);

  unlink $jpg if (-e $jpg);

  $ycut = ($p->{ps_height} * $p->{plot_dpi}) - $p->{jpeg_yspan};

  $flags =  "-colorspace RGB -quality $p->{jpeg_quality} "
          . "-crop +0+$ycut  -antialias";

  ps_to_jpeg($ps,$jpg,$flags);
  croak "ERROR: Plot::ps_to_jpeg could not create file $jpg"
    unless (-e $jpg);
}

sub to_pdf {
  my ($self,$pdf) = @_;

  my $dir  = $self->{'params'}{'dir'};
  my $ps   = $self->{'output'}{'ps'};
  my $link = $self->{'output'}{'jpg'};

  $pdf = "$dir/" . File::product_link($link,'pdf');

  my $command = "$Base::pdf_program $ps $pdf";
  $run->($command);

  unless (-e $pdf) {
    carp "WARNING: Plot::ps_to_pdf could not create file $pdf";
    return;
  }
   
  $self->{'output'}{'pdf'} = $pdf;
}


#-----------------------------------------------------------------------

push @PLOT_PARAMS,qw( city_fontsize city_dotsize city_dotoffsetratio );
sub _plot_cities_block {
  my ($self,$citylist,$part) = @_;
  my $p = $self->params;
  my ($command,$flags,$dotsize,$n_cities,$n_plotted,$input_text,$input_dot);

  $dotsize = $p->{city_dotsize};
  $n_cities = scalar @$citylist;

  foreach my $city (@$citylist) { ### Checking cities for plotting--->
    my ($name,$lat,$lon) = @{%$city}{qw( city latitude longitude )};
    $name =~ s/\s\(.*$//;

    next if ($self->_block_text($name,$lat,$lon));
    $n_plotted++;

    my $text_lat = $self->_city_text_offset($lat);
    $input_dot  .= "$lon $lat\n";
    $input_text .= "$lon $text_lat $p->{city_fontsize} 0 0 CT $name\n";
  }   

#  print "Plot::_plot_cities_block: $n_plotted / $n_cities cities\n";

  $flags = $p->{plot_flags};
  $command = "$gmt_bin/pstext $flags -O -K <<END\n${input_text}END\n";
  $self->run_ps($command, $part || 'post');

  #Flags: -Sc circle -G fillcolor 
  $flags = "$p->{plot_flags} -Sc0.03 -G0"; 
  $command = "$gmt_bin/psxy $flags -O -K <<END\n${input_dot}END\n";
  $self->run_ps($command, $part || 'base');
 
 
}

sub _plot_cities_simple {
  my ($self,$file,$part) = @_;
  my $p = $self->params;
  my ($command,$flags,$dotsize,$n_cities,$n_plotted,$input_text,$input_dot);

  $dotsize = $p->{city_dotsize};
  my ($w,$e,$s,$n) = 
    @{$p}{ qw(plot_wbound plot_ebound plot_sbound plot_nbound) };

  my @slurp = File::slurp($file);
  foreach my $line (@slurp) { ### Checking cities for plotting-->
    next if ($line =~ /^#/);
    my ($lon,$lat,@name) = split /\s+/,$line;
   
    next if ($lon < $w or $lon > $e);
    next if ($lat < $s or $lat > $n);

    my $name = join ' ',@name;
    next if ($name =~ /#/);

    $name =~ s/,.*$//;
    $n_cities++;
    next if ($self->_block_text($name,$lat,$lon));

    $n_plotted++; 
    my $text_lat = $self->_city_text_offset($lat);
    $input_dot  .= "$lon $lat\n";
    $input_text .= "$lon $text_lat $p->{city_fontsize} 0 0 CT $name\n";
  }
  #print "Plot::_plot_cities_simple: $n_plotted / $n_cities cities\n";

  $flags = $p->{plot_flags};
  $command = "$gmt_bin/pstext $flags -O -K <<END\n${input_text}END\n";
  $self->run_ps($command, $part || 'post');

  #Flags: -Sc circle -G fillcolor
  $flags = "$p->{plot_flags} -Sc0.03 -G0";
  $command = "$gmt_bin/psxy $flags -O -K <<END\n${input_dot}END\n";
  $self->run_ps($command, $part || 'base');

}


#----------------------------------------------------------------------
# Convert a lat-lon pair or file into X-Y coordinates (in inches)

sub lonlat2xy {
  my $self = shift;
   
  my $p = $self->params;
  my ($command,$results);

  # -Fi output in plot inches 
  $command = "$gmt_bin/mapproject $p->{plot_flags}";
 
  if (scalar @_ == 2) {
    my ($lon,$lat) = @_;
    return split /\s/, $run->("echo $lon $lat | $command");
  }    
  if (scalar @_ == 1) {
    my $file = shift;
    my $tmp = "$file.tmp.lonlat2xy.$$";

    -s $file or croak "ERROR: Plot::lonlat2xy missing file $file";

    $run->("$command -M $file > $tmp");
    -s $tmp or croak "ERROR: Plot::lonlat2xy running command:\n$command\n";

    $run->("cp $tmp $file");    
    unlink $tmp;
  }
}

#----------------------------------------------------------------------
# Keeps track of used points in x-y hash %block. It calculates the x-y 
# rectangle taken by the text. Returns null if all points are clear.
# If that rectangle would overwrite points already used
# by a previous text string, it returns the earlier string.

sub _block_text {
  my ($self,$text,$lat,$lon) = @_;

  my @pts = $self->_add_pts($text,$lat,$lon);
  # @pts is now an array of refs to points in $self->{text_block}

  my $val;
  foreach my $point (@pts) {
    next unless (defined $$point);
    $val = $$point;
    return $val;
  }
  # All clear
  foreach my $point (@pts) { 
    $$point = $text;
  }
  return 0;
}

#----------------------------------------------------------------------
# Returns an array of refs to $self->{block} that are the set points
# 'taken up' by the text string.

sub _add_pts {
  my ($self,$text,$lat,$lon) = @_;
  my $p = $self->params;
  my @pts;

  my $block   = $self->{text_block};
  my $size    = $p->{city_fontsize};
  my $dpi = $p->{plot_dpi};

  my $text_lat = $self->_city_text_offset($lat);

  my ($x,$y) = $self->lonlat2xy($lon,$lat);
  $x = int ($x*$dpi/2 + 0.5);
  $y = int ($y*$dpi/2 + 0.5);

  # Add city dot to block list
  push @pts,\($block->{$x}{$y});

  # Compute center of text block
  ($x,$y) = $self->lonlat2xy($lon,$text_lat);
  $x = int ($x*$dpi/$size + 0.5);
  $y = int ($y*$dpi/$size + 0.5);

  # Note that we assume the text is offset down from $y.
  # It doesn't matter as long as all of the text is justified
  # the same way.
  my $x_offset = int (length($text)/2 + 0.5);
  my $y_extent = 1;

  for (my $y1 = 0; $y1 <= $y_extent; $y1++) { 
    for (my $x1 = -$x_offset; $x1 <= $x_offset; $x1++) { 
      push @pts,\$block->{$x+$x1}{$y+$y1};
    }
    
  }
  return wantarray ? @pts : \@pts;
}

sub _city_text_offset {
  my ($self,$lat) = @_;
  my $p = $self->params;

  my $offset = $p->{lat_span} * $p->{city_dotoffsetratio};
  return $lat + $offset; 
}

#-----------------------------------------------------------------------

sub ps_to_jpeg {
  my ($ps,$jpg,$flags) = @_;
  croak "ERROR: Plot::ps_to_jpeg cannot read input $ps"
    unless (defined $ps and -e $ps);

  $jpg = File::product_link($ps,'jpg') unless (defined $jpg);
    
  my $command = "$Base::convert_program $flags $ps $jpg";
  $run->($command);
  #unlink($ps);
}

sub get_basemap_ticks {
  my $self = shift;
  my $p = $self->params;

  my @ticks;
  foreach my $span ( $p->{'lon_span'},$p->{'lat_span'} ) {
    my $tick = ($span < 1  ) ? "a6m" 
             : ($span < 3  ) ? "a30mf15m"
             : ($span < 6  ) ? "a1f30m"
             : ($span < 10 ) ? "a2f1"
             : ($span < 30 ) ? "a5f1"
             : ($span < 90 ) ? "a10f5"
             : "a90f30";
    push @ticks,$tick;
  }
  my $tick = (join '/',@ticks);
  return $tick;
} 

1;

