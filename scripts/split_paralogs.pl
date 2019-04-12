#!/usr/perl

use strict;
use warnings;

# input/output
my $low_split_cutoff = 0.75;
my $paralog_cat = $ARGV[0];
my $loci_list = $ARGV[1];
my $output_file = $ARGV[2];
my $threads = $ARGV[3];
if ( scalar(@ARGV)>4 ){
	$low_split_cutoff = $ARGV[4];
}

my $print_loci = 0;
my $file_loci = 0;

# sub functions
sub process_family { # Process hashes of alleles in decending order of threshold.
	
	# sub-function parameters
	my %genomes = %{(shift)};
	my %alleles = %{(shift)};
	my %loci_info = %{(shift)};

	# find number of unique genomes in family.
	my @genomes = keys(%genomes);
	my $n_genomes  = scalar(@genomes);
	
	# target for splitting 
	my $org_genomes = $n_genomes; # initial count
		
	# sort alleles by thresholds
	my %loci = ();
	my $group_number = 0;
	my %allele_assignment = ();
	my %group_info = ();
	
	# find lowest threshold
	my $low_t = (sort {$a<=>$b} keys %alleles)[0];
	
	# loop variable = n genomes and also threshold for splitting - i.e. as variable decreases be more relaxed about splitting
	my $cont = 1;
	my $split_prev = 0;
	
	# check #loci and #truncation groups per genome at lowest threshold
	my $n_tgs = 0;
	my %tg_clusters = (); # variable to check number of clusters
	my %nov_count = (); # variable that stores number of novel (non-truncation) groups per genome	
	my $a_test = (keys %{$alleles{$low_t}})[0];
	for my $l ( keys %{$alleles{$low_t}{$a_test}} ) {

		# count of all loci for sanity check at end of sub function
		$loci{$l} = 1;
				
		# genome
		my $gn = "";
		if (!$loci_info{$l}{"ge"}){
			$gn = $loci_info{$l}{"ge"};
		}else{
			die " - problem with loci $l";
		}
		# store loci into truncation groups per genome		
		if( $loci_info{$l}{"tg"} ){
			if ( !$tg_clusters { $gn }{ $loci_info{$l}{"tg"} } ){
				$tg_clusters { $gn }{ $loci_info{$l}{"tg"} } = 1;
				++$n_tgs;
			}
		}else{
			$nov_count{$gn}++;
			$tg_clusters { $gn }{ "N$nov_count{$gn}" } = 1 ;
			++$n_tgs;
		}			

	}
	
	# clear variables
	%tg_clusters = ();
	%nov_count = ();
	
	# NOTE: only process if > 1 genome - the logic used for splitting i.e at a dosage of one in a set of genomes does not make sense for sequences at multiple copies in a single genome.
	$cont = 0 if $n_genomes == 1; 
	print "single genome\n" if $n_genomes == 1; 
	
	# dont process if number of truncation groups is equal to number of genomes
	$cont = 0 if $n_tgs == $n_genomes;
	print "equal tgs\n" if $n_tgs == $n_genomes; 
	
	# Otherwise split based upon frequency of loci (per genome) at each allele
	# Logic: 
	# A) A cluster of loci that represent an allele at a frequency of >=1 per genome for all constituent genomes most likely represents a novel gene.
	# B) Alleles are scored on the number of genomes in which they are present and how many truncation groups they contain (i.e. dosage)
	# C) The most optimally scored alleles are removed (lowest threshold) and the samples iterated upon after lowering the scoring threshold.
	
	# initial cutoffs
	my $n_cutoff = $n_genomes;
	my $tg_cutoff = $n_genomes;
	
	# keep processing until iterative limit is reached or no alleles remain to be split
	my @loop_thresholds = sort {$b<=>$a} keys %alleles;
	pop(@loop_thresholds);

	my %scores = ();
	my @scores = (); 
	
	while( $cont == 1 ){
	
		# reset values 
		%scores = ();
		@scores = (); 
			
		# exclude lowest threshold
		for my $t ( @loop_thresholds ) {
	
			# process all alleles for threshold - exclude those already assigned.
			for my $a ( keys %{$alleles{$t}} ) {
			
				# Find number of genomes in allele
				my %a_genomes = (); # allele genomes
				my %tg_clusters = (); # truncation clusters per genome
				my %nov_count = (); # novel genes 
				my $n_tgs = 0; # number of truncation groups
				my %c_loci = ();
				
				# store loci and number of trunaction in allele
				for my $l ( keys %{$alleles{$t}{$a}} ) { 
					
					# store current loci after removing those already assigned 
					unless ( $allele_assignment{$l} ){
					
						$c_loci{$l} = 1; 
							
						my $gn = $loci_info{$l}{"ge"};
						
						# allele_genomes
						$a_genomes{$gn}++;
												
						if( $loci_info{$l}{"tg"} ){
							$tg_clusters { $gn }{ $loci_info{$l}{"tg"} }++;
						}else{
							$nov_count{$gn}++;
							$tg_clusters { $gn }{ "N$nov_count{$gn}" } = 1 ;
						}
					}
					
				}
				
				# genomes/# in allele
				my @a_genomes = keys(%a_genomes);
				my $n_a_genomes  = scalar(@a_genomes);
	
				# summarise count of truncation groups per genome
				$n_tgs = 0;
				for ( @a_genomes ){
					for ( keys %{$tg_clusters{$_}} ){
						++$n_tgs;
					} 
				}
				
				# sanity check
				die " - number of truncation groups cannot be > number of loci\n" if ($n_tgs > scalar(keys(%c_loci)));
				
				# store score for allele if it is within current cutoffs - score = (1 - (n_a_genomes/n_genomes)) + (($n_tgs - $n_a_genomes)/n_genomes)
				# do not score individual loci
				if ( ($n_a_genomes >= $n_cutoff) && ( $n_tgs <= $tg_cutoff ) && ($n_a_genomes != 1)  ){
					
					# calculate scores
					my $score_n = 1 - ($n_a_genomes/$n_genomes);
					my $score_t = ($n_tgs-$n_a_genomes)/$n_genomes;
					my $score = 1 + $score_n + $score_t; # add 1 to allow storing as integer
					
					# feedback
					print "$n_a_genomes/$n_genomes/$n_tgs --- $score_n - $score_t - $score\n";
					
					# store scores
					$scores{$t}{$a}{"s"} = $score;
					$scores{$t}{$a}{"n"} = $n_a_genomes;
					$scores{$t}{$a}{"t"} = $n_tgs;
					
					# Add list of scores to array
					push(@scores, $score); 
					
					# feedback
					print "CANDIDATE: ($n_a_genomes == $n_cutoff) && ($n_tgs <= $tg_cutoff)\n";
					
				}
				
				# feedback
				print "($n_a_genomes == $n_cutoff) && ($n_tgs <= $tg_cutoff)\n";
			}
			
		}
		
		# find lowest score 
		my $n_genomes_new = 0;
		if ( scalar(@scores) > 0 ){
			
			my $best_score = (sort {$a<=>$b} @scores)[0];
			
			# remove all alleles that match lowest score
			for my $t ( sort {$a<=>$b} @loop_thresholds ) {
			
				# process all alleles for threshold - exclude those already assigned.
				for my $a ( keys %{$alleles{$t}} ) {
				
					# store if they match best 
					if ( ($scores{$t}{$a}{"s"}) && ($scores{$t}{$a}{"s"} == $best_score) ){
					
						# store loci in allele
						my %c_loci = (); # allele loci
						my %c_genomes = (); # genome for allele
						for my $l ( keys %{$alleles{$t}{$a}} ) { 
						
							unless ( $allele_assignment{$l} ){
							
								my $gn = $loci_info{$l}{"ge"};
						
								# current loci hash
								$c_loci {$l} = 1;
								$c_genomes {$gn} = 1;
							}
							
						}
						
						# check loci have not already been removed/stored
						if ( scalar(keys(%c_loci)) > 0 ){
						
							# increment group number
							++$group_number;
							
							# store group designation for all loci.
							for my $l ( keys %c_loci ) { 
								$allele_assignment{$l} = $group_number;
							}
			
							# store threshold, loci count, truncation group count and allele for group.
							$group_info {$group_number} {"T"} = $t;
							$group_info {$group_number} {"G"} = scalar(keys(%c_genomes));
							$group_info {$group_number} {"A"} = $a;
							$group_info {$group_number} {"C"} = scalar(keys(%c_loci));
							$group_info {$group_number} {"TC"} = $scores{$t}{$a}{"t"};	
							$group_info {$group_number} {"S"} = $scores{$t}{$a}{"s"};
							
							# feedback
							###print "Split - $t -$a - $group_info{$group_number}{C}/$n_cutoff - $group_info{$group_number}{TC} - $group_info{$group_number}{S}\n";
						
						} 
					}
				}
			}
		
			# if loci have been removed recalculate number of genomes using lowest threshold for assignment - count paralogous clusters per genome to check that family still contains paralogs.
			$n_tgs = 0;
			my %temp_genomes = ();
			for my $l ( keys %{$alleles{$low_t}{$a_test}} ) {
			
				# only check loci not assigned
				unless ( $allele_assignment{$l} ){
		
					# genome
					my $gn = $loci_info{$l}{"ge"};
				
					# store genome 
					$temp_genomes{$loci_info{$l}{"ge"}} = 1;
			
					# store loci into trunaction groups per genome		
					if( $loci_info{$l}{"tg"} ){
						if ( !$tg_clusters { $gn }{ $loci_info{$l}{"tg"} } ){
							$tg_clusters { $gn }{ $loci_info{$l}{"tg"} } = 1;
							++$n_tgs;
						}
					}else{
						$nov_count{$gn}++;
						$tg_clusters { $gn }{ "N$nov_count{$gn}" } = 1 ;
						++$n_tgs;
					}			
			
				}
		
			}
		
			# recalculate number of genomes
			my @n_genomes = keys(%temp_genomes);
			$n_genomes_new  = scalar(@n_genomes);
		
			# clear variables
			%tg_clusters = (); 
			%temp_genomes = ();

			# check there are genomes to process 
			last if $n_genomes_new <= 1; 
		
			# check that group still contains paralogs (excluding truncated loci). If none then stop.
			last if $n_tgs == $n_genomes_new;
			
		}else{
			$n_genomes_new = $n_genomes;
			###print "no alleles meet criteria\n";
		}
		
		# if number of genomes has changed and paralogs remain then reset loop and repeat 
		if ( $n_genomes_new ne $n_genomes ){
		
			# reset variables to new # genomes
			$n_genomes = $n_genomes_new;
			$split_prev = $group_number;	
			$org_genomes =  $n_genomes_new;
			
			# reset cutoffs to new # genomes 
			$n_cutoff = $n_genomes_new;
			$tg_cutoff = $n_genomes_new;
			
			###print "reset no. genomes\n";
			
		}else{
	
			# if group has been split then repeat using the same cutoffs to check for additional groups meeting criteria
			# otherwise, reduce threshold for splitting by set value.
			
			# check samples have been split 
			if ( $split_prev != $group_number){
		
				###print "samples split - repeat\n";
			
			}else{
			
				# reduce target cutoff values by x where x is a percentage of original group count; 
				my $new_gn = $n_cutoff;
				my $new_tg = $tg_cutoff;
				for ( my $i = 0.05; $i <= 0.25; $i=$i+0.0125 ) {
							
					$new_gn = int($n_cutoff - ($org_genomes * $i) );
					$new_tg = int($n_cutoff + ($org_genomes * $i) );
					
					last if $new_gn < $n_cutoff;					
				}
				#$t_genomes = $new_gn;
				$n_cutoff = $new_gn;
				$tg_cutoff = $new_tg unless $tg_cutoff == 10000000;
			
				# stop loop if threshold is <= cutoff value
				if( ($n_cutoff <= int($org_genomes * $low_split_cutoff )) && ($tg_cutoff == 10000000) ) {
					$cont = 0;
				}elsif ( ($n_cutoff <= int($org_genomes * $low_split_cutoff ) ) || ($n_cutoff == 1) ){
					$n_cutoff = $n_genomes_new;
					$tg_cutoff = 10000000;
				}
		
				###print "no-samples split - reduced target = $n_cutoff + $tg_cutoff \n";
		
			} 
			# store number of split groups
			$split_prev = $group_number;
		}
			
	}
	
	# check number of groups
	my $no_loci = keys %loci;
	my $no_assigned = keys %allele_assignment;
	###print "loci - $no_loci\t no assigned $no_assigned\n";
	
	# count split groups	
	my $split_groups = $group_number + 1;
	$split_groups = $group_number if $no_loci == $no_assigned;
	$split_groups = 1 if $split_groups == 0;
	
	# add any remaining isolates as an additional group
	++$group_number; 
	my %rem_loci = ();
	my %rem_genomes = ();
	%tg_clusters = ();
	%nov_count = ();
	$n_tgs = 0;
	for my $l (keys %loci){
	
		if (!$allele_assignment{$l}){
		
			# store loci 
			$rem_loci {$l} = 1;
			
			# get genome
			my $gn = $loci_info{$l}{"ge"};
			
			# store genome
			$rem_genomes{$gn} = 1;
			
			# store truncation group
			if( $loci_info{$l}{"tg"} ){
				if ( !$tg_clusters { $gn }{ $loci_info{$l}{"tg"} } ){
					$tg_clusters { $gn }{ $loci_info{$l}{"tg"} } = 1;
					++$n_tgs;
				}
			}else{
				$nov_count{$gn}++;
				$tg_clusters { $gn }{ "N$nov_count{$gn}" } = 1 ;
				++$n_tgs;
			}			
			
			# assign to allele
			$allele_assignment{$l} = $group_number;
		}
	}
	
	# store group info if any loci remain
	if ( (scalar(keys(%rem_loci))) > 0 ){
	
		$group_info {$group_number} {"G"} = scalar(keys(%rem_genomes));
		$group_info {$group_number} {"T"} = $low_t;
		$group_info {$group_number} {"A"} = $a_test;
		$group_info {$group_number} {"C"} = scalar(keys(%rem_loci));
		$group_info {$group_number} {"TC"} = $n_tgs;
		$group_info {$group_number} {"S"} = "0";
	
	}
		
	# Return group info
	return (\%allele_assignment, \%group_info, $split_groups);
	
}

sub print_groups { # print alleles per split group.
	
	# sub-function parameters
	my $group = shift;
	my %alleles = %{(shift)};
	my %loci_info = %{(shift)};
	my %allele_assignment = %{(shift)};
	my %group_info = %{(shift)};
	my $oloci = shift;
	my $olog = shift;

	# get thresholds 
	my @thresholds = sort {$a<=>$b} keys %alleles;

	# Check for how many sig figs to use for allele numbering - process all thresholds
	my $max = 0;
	for my $t (sort {$b<=>$a} keys %alleles) { 	
		for my $a ( keys %{$alleles{$t}} ) {
			if ( $a =~ /\_(\d+)$/ ){
				$max = $1 if $1 > $max;
			}
		}
	}
	my $no_sigfigs = length($max);

	# Check if all loci are in one truncation group - maybe unnecessary
	my $n_loci_t = scalar(keys(%allele_assignment));
	my $l_count = 0;
	my $min_thresh = $thresholds[0];
	for my $a ( keys %{$alleles{$min_thresh}} ){
		for my $l ( keys %{$alleles{$min_thresh}{$a}} ) { 
			++$l_count;
		}
	}

	# identify group numbering 
	#my $no_core = scalar(keys(%allele_assignment));

	# no_core == 0 then print without amendment
	my %modified_name = ();

	# store modified names - do not do so if there is only one group - this can come about by the paralogous cluster being detected due to fission/fusions with no duplications.
	my $no_groups = keys(%group_info);
	unless ( scalar(keys(%group_info)) == 1 ){
		for my $a ( keys %{$alleles{$min_thresh}} ){
			for my $l ( keys %{$alleles{$min_thresh}{$a}} ) { 
				$modified_name{$l} = $allele_assignment{$l};		
			}
		}
	}		
	
	# print summary to output file 
	my @log_line = ($group);
	# summary line - original group name 	new group name(threshold/#loci/#genomes/#truncation groups/allele name) ...
	
	# store single group (unmodified name)
	if ( scalar(keys(%group_info)) == 1 ){
	
		my $group_number = (keys(%group_info))[0];
		my $sum_line = sprintf( "%s(%s/%s/%s/%s/%.3f/%s)", $group, $group_info {$group_number} {"T"}, $group_info {$group_number} {"C"}, $group_info {$group_number} {"G"}, $group_info {$group_number} {"TC"}, $group_info {$group_number} {"S"}, $group_info {$group_number} {"A"}  );
		push(@log_line, $sum_line);
		
		# clear renaming variable
		%modified_name = (); 
		
	}
	# store multiple groups with modified names
	else{
		for my $group_number (sort keys %group_info){
			my $sum_line = sprintf( "%s\_%s(%s/%s/%s/%s/%.3f/%s)", $group, $group_number, $group_info {$group_number} {"T"}, $group_info {$group_number} {"C"}, $group_info {$group_number} {"G"}, $group_info {$group_number} {"TC"}, $group_info {$group_number} {"S"},  $group_info {$group_number} {"A"}  );
			push(@log_line, $sum_line);

		}
		
	}
	
	# print log line
	print $olog join("\t", @log_line). "\n";

	# process all loci for threshold and print with amended group/allele names where appropriate
	for my $t (sort {$a<=>$b} keys %alleles) { 	# process all thresholds

		# process all alleles for threshold 
		for my $a ( keys %{$alleles{$t}} ) {
	
			# process all loci in allele
			for my $l ( keys %{$alleles{$t}{$a}} ) { 				
		
				my $group_out = $group;
				my $allele_out = $a;
			
				# only rename clusters that have been split
				if ( $modified_name{$l} ) {					
					$group_out = sprintf( "%s\_%i", $group_out, $modified_name{$l} );
				
					# modify allele name (except lowest threshold, initial allele)
					if ( $a =~ /\_(\d+)$/ ){
						$allele_out = sprintf( "%s\_%*d", $group_out, $no_sigfigs, $1 );
						$allele_out =~ tr/ /0/;
					}else{
						$allele_out = $group_out;
					}
				}
			
				# identify genome
				my $genome = $loci_info{$l}{"ge"};
			
				# print locus info
				print $oloci "$l\t$group_out\t$t\t$allele_out\t$genome\n";
				++$print_loci;

			}		
		}
	}
}


# variables
my %loci_info = ();
my %family_info = ();

# parse loci list for paralog cluster loci 
print " - parsing paralog category file\n";
open PARA, $paralog_cat or die "$paralog_cat would not open.\n";
while (<PARA>){
	
	my $line = $_;
	chomp $line;
	
	my @split =  split(/\t/, $line, -1);
	
	my $cloci = $split[0];
	my $mc = $split[3];
	my $trunc_group = $split[5];
	my $length_group = $split[6];
	
	# Store data
	$loci_info{$cloci}{"fa"} = $split[1];
	$loci_info{$cloci}{"ge"} = $split[2];
	$loci_info{$cloci}{"tg"} = $split[5] if ( $split[5] > 0);
	#$loci_info{$cloci}{"lg"} = $split[6];
	
	# Family info
	$family_info{ $split[1] }{ $cloci } = 1;
	
}close PARA;


# feedback
my $no_paralog_families = scalar(keys(%family_info));
print " - $no_paralog_families families to split.\n";

# parse loci list - split families when all loci have been identified for a paralog.
my $curr_group = "";
my $paralog = 0;
my $paralog_check = 0;
my %genomes = ();
my %alleles = ();
my $split_no = 0;
my $split_total = 0;

# open output file.
open my $oloci, ">$output_file" or die " - ERROR: could not open output file ($output_file)";
open my $olog, ">$output_file.log" or die " - ERROR: could not open output file ($output_file.log)";

open LOCI, "$loci_list" or die " - ERROR: loci list ($loci_list) does not exist\n";
print " - identifying and separating core clusters\n";
while ( <LOCI> ){
	
	my $line = $_;
	chomp $line;
	
	++$file_loci;
	
	# Format: loci	family	threshold	allele_name	genome
	my ( $loci, $group, $threshold, $allele, $genome ) = split( /\t/ , $line, -1);
	
	# check for group change. 
	if( $curr_group ne $group ) {
	
		# process family if paralogous
		if ( $paralog == 1 ) {
		
			my ($r1, $r2, $r3) = process_family(\%genomes, \%alleles, \%loci_info);

			my %allele_assignment = %$r1;
			my %group_info = %$r2;
			my $core_alleles = $r3;
	
			# increment total splits
			$split_total += ($core_alleles-1) if $core_alleles > 1;
			$split_no++ if $core_alleles > 1; 
		
			# Print split alleles.
			print_groups($curr_group, \%alleles, \%loci_info, \%allele_assignment, \%group_info, $oloci, $olog);
					
		}
		
		# Check for paralog family.
		if ( $family_info{$group} ){
		
			++$paralog_check;
			$paralog = 1;
			
		}else{
			$paralog = 0;
		}
		
		# clear family info.
		%genomes = ();
		%alleles = ();
	}
	
	# store family info.
	$genomes {$genome}++;
	$alleles{$threshold}{$allele}{$loci} = 1;
	
	# store current group.
	$curr_group = $group;
	
}close LOCI;

# process final family if paralogous
if ( $paralog == 1 ) {

	my ($r1, $r2, $r3) = process_family(\%genomes, \%alleles, \%loci_info) if $paralog == 1;

	my %allele_assignment = %$r1;
	my %group_info = %$r2;
	my $core_alleles = $r3;

	# increment total splits
	$split_total += ($core_alleles-1) if $core_alleles > 1; 
	$split_no++ if $core_alleles > 1; 
	
	# Print split alleles.
	print_groups($curr_group, \%alleles, \%loci_info, \%allele_assignment, \%group_info, $oloci, $olog);
			
}

# feedback
my $total = $split_no+$paralog_check;
print " - $paralog_check of $no_paralog_families paralog families found in loci list.\n";
print " - $split_total families split into $split_no additional core/accessory alleles - $total total\n";
print " - $print_loci loci printed to file of $file_loci loci found in file\n";
exit;