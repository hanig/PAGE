#!/usr/bin/perl

my $pagedir ;
BEGIN{
    if ((!$ENV{PAGEDIR}) || ($ENV{PAGEDIR} eq '')) {
	$pagedir="./" ;
	print "The PAGEDIR environment variable is not set. It is set to default.\n";
    }
    else{
	$pagedir = $ENV{PAGEDIR};
    }
}

my $programdir = $pagedir."/PROGRAMS" ;
my $scriptdir  = $pagedir."/SCRIPTS" ;

use lib "$pagedir/SCRIPTS";

use strict;
use Sets;
use PBS;
use Table;
use Getopt::Long;
use Data::Dumper;

if (@ARGV == 0) {
  die "Usage: perl page.pl --expfile=FILE --datafile=FILE --goindexfile=FILE --gonamesfile=FILE --exptype=TXT --cattypes=F,C,P --catmaxcount=INT\n";
}

my $expfile          = undef ;
my $goindexfile      = undef ;
my $gonamesfile      = undef ;
my $species          = undef ;
my $exptype          = "discrete" ;
my $datafile         = undef ;
my $catmaxcount      = 200 ;
my $catmincount      = 0;
my $independence     = 1 ;
my $shuffle          = undef;
my $max_p            = 0.005 ;
my $randomize        = undef;
my $dopage           = 1;
my $minmax_lp        = undef;
my $minr             = undef;
my $nbclusters       = 5;
my $cattypes         = "F,P,C";  # undef means all (F,P,C)
my $verbose          = 0;
my $submit           = 0;
my $draw_sample_heatmap = "false" ;
my $draw_min         = -3;
my $draw_max         = 3;
my $ebins            = undef ; 
my $from_gui         = 0 ;
my $onecatfile       = undef;
my $suffix           = undef;
my $order            = 1 ;
my $dodraw           = 1 ;

my $annochoice = 0;
my $protein = 0;
my $homologiesfile=undef;
my $genelist=undef;
my $nodups = 0;

GetOptions ('expfile=s'              => \$expfile,
	    'exptype=s'              => \$exptype,
	    'species=s'              => \$species,
	    'goindexfile=s'          => \$goindexfile,
	    'onecatfile=s'           => \$onecatfile,
	    'gonamesfile=s'          => \$gonamesfile,
	    'catmaxcount=s'          => \$catmaxcount,
	    'catmincount=s'          => \$catmincount,
	    'cattypes=s'             => \$cattypes,
	    'shuffle=s'              => \$shuffle,
	    'datafile=s'             => \$datafile,
	    'max_p=s'                => \$max_p,
	    'minmax_lp=s'            => \$minmax_lp,
	    'minr=s'                 => \$minr,
	    'nbclusters=s'           => \$nbclusters,
	    'dopage=s'               => \$dopage,
	    'verbose=s'              => \$verbose,
	    'independence=s'         => \$independence,
	    'submit=s'               => \$submit,
	    'draw_sample_heatmap'    => \$draw_sample_heatmap,
	    'randomize=s'            => \$randomize,
	    'draw_min=s'             => \$draw_min,
	    'draw_max=s'             => \$draw_max,
	    'ebins=s'                => \$ebins,
	    'suffix=s'               => \$suffix,
	    'from_gui=i'             => \$from_gui,
	    'order=i'                => \$order,
	    'annochoice=i' => \$annochoice,
	    'protein=i' => \$protein,
	    'homologiesfile=s' => \$homologiesfile,
	    'genelist=s' => \$genelist,
	    'nodups=i' => \$nodups,
	    'dodraw=i' => \$dodraw,
) ;

# protein add
if (defined $species && $protein == 2 && ($species eq 'human' || $species eq 'mouse' || $species eq 'ecoli')) {
	$species .= 'p';
}
# protein end

if (defined($suffix)) {
  
  if (($expfile =~ /\*/) or ($submit == 1)) {
    die "--suffix option not supported with multiple expfile, or grid submission (for now).\n";
  } else {

    my $newexpfile = "$expfile.$suffix";
    system("cp $expfile $newexpfile");
    $expfile = $newexpfile;
    
  }

}  

#
# Make a batch in case there are multiple input files
#
if (($expfile =~ /\*/) or ($submit == 1))
{
    my $files = Sets::getFiles($expfile) ;

    my $walltime = "20:00:00";
    my $platform = undef;
    
    foreach my $file(@$files)
    {
    
	my $f = substr($file, rindex($file, "/"), length($file)-rindex($file, "/")) ;
	mkdir "$file\_PAGE/" if ! (-d "$file\_PAGE/");
	my $expfile_nodups_page = "$file\_PAGE/$f";
	print $f,"\n";
	
	my $pwd  = `pwd`; $pwd =~ s/\n//;
	my $time = Sets::getNiceDateTime(1);
	
	my $pbs = PBS->new;
	$pbs->setPlatform($platform) if (defined($platform));
	$pbs->setWallTime($walltime);
	$pbs->addCmd("cd $pwd");
	
	$pbs->setScriptName("$expfile_nodups_page.scriptPAGE");
	
	$pbs->addCmd("date") ;
	$pbs->addCmd("export PAGEDIR=$pagedir") ;
	
	$pbs->addCmd("echo \"Running PAGE\"") ;
	
	my $cmd = "perl $pagedir/page.pl --expfile=$file --species=$species --goindexfile=$goindexfile --gonamesfile=$gonamesfile --exptype=$exptype --catmaxcount=$catmaxcount --cattypes=$cattypes --independence=$independence --datafile=$datafile --shuffle=$shuffle --max_p=$max_p --ebins=$ebins --draw_min=$draw_min --draw_max=$draw_max --annochoice=$annochoice --homologiesfile=$homologiesfile --genelist=$genelist --nodups=$nodups" ;
	
	$pbs->addCmd($cmd) ;
	
	my $page_jobid ;
	if ($submit==0)
	{
	    $pbs->execute ;
	}
	elsif ($submit==1)
	{
	    $page_jobid = $pbs->submit ;
	    print "Submitted job $page_jobid.\n";
	}
    }
    exit (1) ;
}


# add remove duplicates
## can only happen if species is known or if a homologies, gene list files are supplied ($homologiesfile, $genelist)
my $removedups = 0;
if ($nodups == 0) {
	print "homologiesfile: $homologiesfile\n";
	print "genelist: $genelist\n";
	
	if (defined $species || (defined $homologiesfile && defined $genelist)) {
		print "REMOVING DUPLICATES\n";
		if (defined $species && !defined $homologiesfile && !defined $genelist) {
			$homologiesfile = "$pagedir/PAGE_DATA/ANNOTATIONS/$species/$species\.homologies";
			$genelist = "$pagedir/PAGE_DATA/ANNOTATIONS/seqnames/$species\.txt";
		}
		
		my $nodupsexptype;
		if ($exptype eq "discrete") {
			$nodupsexptype = 1 ;
		} elsif ($exptype eq "continuous"){
			$nodupsexptype = 0 ;
		}
		my $fileout = "$expfile\.nodups";
		my $removedupcmd = "perl $scriptdir/remove_homologous_sequences_withseed.pl -expfile $expfile -quantized $nodupsexptype -genelist $genelist -dupfile $homologiesfile -outfile $fileout";
		
		if (defined($ebins)) {
			$removedupcmd .= " -ebins $ebins ";
		}

		print $removedupcmd,"\n\n";
		if (-e $homologiesfile && -e $genelist) {
			system($removedupcmd);
			$removedups = 1;
			system("mv $expfile $expfile\.original");
			system("cp $expfile\.nodups $expfile");
		} else {
			print "DUPLICATION REMOVAL CANCELLED -- homologiesfile does not exist\n\n";
		}
	}
}
# end add remove duplicates


#
# Making workspace directory
#
if (! -d "$expfile\_PAGE") 
{
    mkdir("$expfile\_PAGE") or die "couldn't make the directory: $?";
}

#
# Changing unconventional inputs
#

if (defined $species && $species ne "" && !defined $goindexfile){
	if($annochoice == 2) {
		$goindexfile = "$pagedir/PAGE_DATA/ANNOTATIONS/$species/$species\_index_k.txt" ;
		$gonamesfile = "$pagedir/PAGE_DATA/ANNOTATIONS/$species/$species\_names_k.txt" ;
		if ((!-e $goindexfile) && (!-e $gonamesfile)) {
			die ("FAILURE: KEGG annotations not available.");
		}
	} elsif ($annochoice == 1) {
		$goindexfile = "$pagedir/PAGE_DATA/ANNOTATIONS/$species/$species\_index_gk.txt" ;
		$gonamesfile = "$pagedir/PAGE_DATA/ANNOTATIONS/$species/$species\_names_gk.txt" ;
		if ((!-e $goindexfile) && (!-e $gonamesfile)) {
			$goindexfile = "$pagedir/PAGE_DATA/ANNOTATIONS/$species/$species\_index.txt" ;
			$gonamesfile = "$pagedir/PAGE_DATA/ANNOTATIONS/$species/$species\_names.txt" if (!defined $gonamesfile);
		}
	} else {
		$goindexfile = "$pagedir/PAGE_DATA/ANNOTATIONS/$species/$species\_index.txt" ;
		$gonamesfile = "$pagedir/PAGE_DATA/ANNOTATIONS/$species/$species\_names.txt" if (!defined $gonamesfile);
	}
} elsif (defined($onecatfile)) {
  
  $goindexfile = $onecatfile;
  my $f = "$onecatfile.names";
  if (! -e $f) {
    
    # create a fake name file
    open OUT, ">$f" or die "Cannot open $f\n";
    print OUT "0\t0\tP\n";
    print OUT "1\t1\tP\n";
    close OUT;
  
  }

  
  $gonamesfile = $f;

  # remove limit for cat max count
  $catmaxcount = 10000000;
  
}

if ($exptype eq "discrete") {
  $exptype = 1 ;
} elsif ($exptype eq "continuous"){
  $exptype = 0 ;
}

if ($catmaxcount eq "all") {
  print INF "Retaining all categories.\n" ;
  $catmaxcount=-1 if ($catmaxcount eq "all") ;
}

my %PARAMS = (expfile          => $expfile,
	      goindexfile      => $goindexfile,
	      gonamesfile      => $gonamesfile,
	      catmaxcount      => $catmaxcount,
	      catmincount      => $catmincount,
	      exptype          => $exptype,
	      cattypes         => $cattypes,
	      max_p            => $max_p,
	      minr             => $minr,
	      independence     => $independence,
	      ebins            => $ebins);

#
# Write a log of the input data
#
open(INF, "> $expfile\_PAGE/info.txt") ;
foreach my $k (sort keys %PARAMS){
    print INF $k, "\t", $PARAMS{$k}, "\n" ;
}

my $todo = &getFaceCommand(\%PARAMS);

if (($dopage == 1) && (!defined($randomize))) {
  print "$todo\n" if ($verbose == 1);
  system("$todo") == 0 or die "command failed: $todo";
}
  
#
# Randomizing the data
#
if ($randomize > 0) {
  
  my $rand_dir = "$expfile\_RANDOM";
  if (! -e $rand_dir) {
    mkdir $rand_dir;
  }

  my @rands = ();
  for(my $i=0 ; $i<$randomize ; $i++) {
    
    my $rrun = $i+1;
    print "Randomize run $rrun.\n";

    # create name
    my $rand_expfile = "$expfile\_RANDOM/$i.txt";

    # PAGE dir
    my $rand_page_dir = "$rand_expfile\_PAGE";
    mkdir $rand_page_dir if (! -e $rand_page_dir);

    # create file
    #system("perl shuffle_column.pl $expfile > $rand_expfile") == 0 or die "system failed: $?";

    # update parameter
    $PARAMS{expfile}       = $rand_expfile;
    $PARAMS{stdoutlogfile} = "$rand_page_dir/log.txt";

    # get cmd 
    my $todo = &getFaceCommand(\%PARAMS);
    if ($verbose == 1) {
	print "$todo\n";
    }
    system($todo) == 0 or die "system failed: $?";

    # parse output
    open(IN, "< $rand_page_dir/log.txt") or die "couldn't open file: $?" ;
    my $fp = undef;
    while(<IN>) {
      chomp ;
      if (/Number of categories that passed the tests/) {
	my @A = split(/\s+/, $_) ;
	print("Number of false positives = ", $A[-1],"\n") ;
	$fp = $A[-1];
	push(@rands, $A[-1]) ;
      }
    }
    close(IN) ;

    print "FP = $fp\n";
    
  }
  
  my $average = Sets::average(\@rands);
  my $std     = Sets::stddev (\@rands);

  print ("Results from $randomize random shufflings indicate a mean of $average false positivies with standard deviation of $std\n") ;

  foreach(@rands) {
    print INF "Number of false positives = ".$_."\n" ;
  }
  
  print INF "Results from $shuffle random shufflings indicate a mean of $average false positivies with standard deviation of $std\n" ;
}

exit if ($dodraw==0) ;
#
# drawing the result
#
my $pvaluematrixfile = "$expfile\_PAGE/pvmatrix.txt";

$todo = "perl $scriptdir/mi_go_draw_matrix.pl  --pvaluematrixfile=$pvaluematrixfile --expfile=$expfile --order=$order --draw_sample_heatmap=$draw_sample_heatmap --min=$draw_min --max=$draw_max --cluster=$nbclusters" ; 
if (defined($minmax_lp)) {
  $todo .= " --minmax_lp=$minmax_lp ";
}
if ($exptype == 0) {
  $todo .= " --quantized=0 ";
}

print "$todo\n";
system("$todo") if ($from_gui==0) ;

#
# html version of result
#
my $pvaluematrixfile = "$expfile\_PAGE/pvmatrix.txt";

$todo = "perl $scriptdir/mi_go_draw_matrix_html.pl  --pvaluematrixfile=$pvaluematrixfile --expfile=$expfile --order=$order --draw_sample_heatmap=$draw_sample_heatmap --min=$draw_min --max=$draw_max --cluster=$nbclusters" ; 
if (defined($minmax_lp)) {
  $todo .= " --minmax_lp=$minmax_lp ";
}
if ($exptype == 0) {
  $todo .= " --quantized=0 ";
}

#re enable when page generation works!
print "$todo\n";
system("$todo") if ($from_gui==0) ;

$todo = "perl $scriptdir/list_killed_cats.pl --pvmatrixfile=$pvaluematrixfile"; 
print "$todo\n";
system("$todo") if ($from_gui==0) ;

print "DONE\n" ;

sub getFaceCommand {
  my ($p) = @_;
  
  my $pvaluematrixfile = "$p->{expfile}\_PAGE/pvmatrix.txt";

  my $todo = "$programdir/page -expfile $p->{expfile} -goindexfile $p->{goindexfile} -gonamesfile $p->{gonamesfile} -catmaxcount $p->{catmaxcount} -catmincount $p->{catmincount} -logfile $pvaluematrixfile.log  -quantized $p->{exptype} -pvaluematrixfile $pvaluematrixfile -max_p $p->{max_p} " ;
  
  my @a_cats = split /\,/, $p->{cattypes};
  if (Sets::in_array('F', @a_cats)) {
    $todo .= " -F 1 ";
  } else {
    $todo .= " -F 0 ";
  }   
  if (Sets::in_array('P', @a_cats)) {
    $todo .= " -P 1 ";
  } else {
    $todo .= " -P 0 ";
  } 
  if (Sets::in_array('C', @a_cats)) {
    $todo .= " -C 1 ";
  } else {
    $todo .= " -C 0 ";
  } 

  if (defined($p->{minr})) {
    $todo .= " -minr $p->{minr} ";
  }

  if (defined($p->{stdoutlogfile})) {
    $todo .= " > $p->{stdoutlogfile} ";
  }

  if (defined($p->{independence})) {
    $todo .= " -independence $p->{independence} ";
  }

  if (defined($p->{ebins})) {
    $todo .= " -ebins $p->{ebins} "; 
  }
  
  return $todo;
}
