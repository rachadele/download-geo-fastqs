#!/bin/bash

#sra-to-hca.sh
#This script takes GSE accessions as command line arguments and processes them accordingly for submission to the hca-util bucket
#Options for processing include skipping FASTQ files and only donwloading supplemental files, converting FASTQs from bam, and renaming files based on library preparation strategy

#Source utility functions
source ~/bin/sra-to-hca/utils/utils.sh

#Functions to execute utities given command line args

function process_fastqs() {
	GSE=$1
	if ! download_miniml_file "$GSE"; then
		echo "Failed to download MINiML file for GSE accession: $GSE"
		exit 1
	fi
	acc=$(get_srr_accessions $GSE | grep SRR[0-9])
	export -f download_fastqs
	parallel -j4 download_fastqs $GSE ::: ${acc[@]}
 
 	while true; do
		local missing_srrs=$(check_fastq_downloads GSE165577)
 		if [[ -z "$missing_srrs" ]]; then
  			echo "All fastqs for GSE $GSE have been downloaded."
    			break
		else
       		#srrs=$(echo "$output" | grep -o 'SRR[0-9]\+')
			parallel -j4 download_fastqs {} ::: "${missing_srrs[@]}"
   		fi
    done
}

function process_bams() {
	GSE=$1
	acc=$(get_srr_accessions $GSE | grep SRR[0-9])
	export -f download_bams
	parallel -j4 download_bams $GSE ::: ${acc}
	rename_bams $GSE
}

function main() {
    local skip_fastq=0  # Default is to not skip fastq download
	local process_bam=0 # Default is not to process bam files
	local rename_mode=""  # Initialize rename_mode as an empty string

	#optargs argument parser
	while getopts ":sbr:" opt; do
		case "$opt" in
			s)
				skip_fastq=1
				;;
			b)
				process_bam=1
				;;
			
			r)
				rename_mode="$OPTARG"  # Set rename_mode to the provided argument
				if [[ "$rename_mode" != "10x" && "$rename_mode" != "ss2" ]]; then
					echo "Invalid argument for -r option: $rename_mode" >&2
					exit 1
				fi
				;;
			\?)
				echo "Invalid option: -$OPTARG" >&2
				exit 1
				;;
		esac
	done
	
	shift $((OPTIND-1)) # Remove the processed options and their arguments from the argument list
	# Now, $@ contains only the non-option arguments (GSE accession numbers)
	
	local GSEs=("$@")
	if [ $# -eq 0 ]; then
	    echo "Usage: $0 -s -b GSE1 GSE2 ..."
	    exit 1
	fi
	if [ "$process_bam" -eq 1 ]; then skip_fastq=1; fi #if bam argument passed, process_bams will convert bam files to fastq, so no need to run process_fastqs
	for GSE in "${GSEs[@]}"; do
		if [ "$skip_fastq" -eq 0 ]; then
			echo "Processing FASTQs for $GSE"
			process_fastqs "$GSE"
		fi
		if [ "$process_bam" -eq 1 ]; then
			echo "Processing BAMs for $GSE"	
			process_bams "$GSE"
		fi
		download_supp_files $GSE
	done
}

main "$@"

