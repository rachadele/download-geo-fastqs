#!/bin/bash

#download-geo-fastqs.sh
#This script takes GSE accessions as command line arguments and processes them accordingly for submission to the hca-util bucket
#the file rename options for this script work for single-cell data generated using either 10x or SS2 library strategies. 
#The script can download fastqs for both bulk-and single-cell data without the rename flag
#Options for processing include skipping FASTQ files and only donwloading supplemental files, converting FASTQs from bam, and renaming files based on library preparation strategy

#Source utility functions
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export USER_UTILS_PATH="$script_dir"

source "$script_dir/utils/utils.sh"

#Functions to execute utities given command line args

function process_fastqs() {
	GSE=$1
	if ! download_miniml_file "$GSE"; then
		echo "Failed to download MINiML file for GSE accession: $GSE"
		exit 1
	fi
	acc=$(get_srr_accessions $GSE)
	export -f download_fastqs
 	echo "downloading FASTQs for $GSE"
	parallel -j4 download_fastqs $GSE ::: ${acc[@]}
 
 	while true; do
		local missing_srrs=$(check_fastq_downloads $GSE)
 		if [[ -z "$missing_srrs" ]]; then
  			echo "All fastqs for GSE $GSE have been downloaded."
    			break
		else
       		#srrs=$(echo "$output" | grep -o 'SRR[0-9]\+')
			parallel -j4 download_fastqs $GSE ::: "${missing_srrs[@]}"
   		fi
    done
}

function process_bams() {
	GSE=$1
	acc=$(get_srr_accessions $GSE)
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
	    echo "Usage: $0 -s -b -r 10x GSE1 GSE2 ..."
	    exit 1
	fi
	if [ "$process_bam" -eq 1 ]; then skip_fastq=1; rename_mode=""; fi #if bam argument passed, process_bams will convert bam files to fastq, so no need to run process_fastqs
	if [ "$skip_fastq" -eq 1 ]; then rename_mode=""; fi
	for GSE in "${GSEs[@]}"; do
		if [ "$skip_fastq" -eq 0 ]; then
			process_fastqs "$GSE"
		fi
  		#rename fastqs according to library method if applicable
  		if [ "$rename_mode" = "10x" ]; then
     			rename_10x $GSE
		fi
		if [ "$rename_mode" = "ss2" ]; then
     			rename_SS2 $GSE
		fi
  		#process bams instead of FASTQs
    		#potentially write a function to detect if original format is bam
		if [ "$process_bam" -eq 1 ]; then
			echo "Processing BAMs for $GSE"	
			process_bams "$GSE"
		fi
		download_supp_files $GSE
	done
}

main "$@"

