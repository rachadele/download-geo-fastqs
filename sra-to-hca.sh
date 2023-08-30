#!/bin/bash

# Include your utility functions here
source ~/bin/sra-to-hca/utils/utils.sh

function process_fastqs() {
	GSE=$1
	if ! download_miniml_file "$GSE"; then
		echo "Failed to download MINiML file for GSE accession: $GSE"
		exit 1
	fi
	acc=$(get_srr_accessions $GSE | grep SRR[0-9])
	echo $acc
	export -f download_fastqs
	parallel -j4 download_fastqs $GSE ::: ${acc}
	check_fastq_downloads $GSE
	#rename fastqs
}

#function process_bams() {
#}



function main() {
    local skip_fastq=0  # Default is to not skip fastq download
	local process_bam=0
	
	while getopts ":s" opt; do
		case "$opt" in
			s)
				skip_fastq=1
				;;
			b)
				process_bam=1
				;;
			\?)
				echo "Invalid option: -$OPTARG" >&2
				exit 1
				;;
		esac
	done

	shift $((OPTIND-1))
	
	local GSEs=("$@")
	
	if [ $# -eq 0 ]; then
	    echo "Usage: $0 --skip-fastq GSE1 GSE2 ..."
	    exit 1
	fi
	for GSE in "${GSEs[@]}"; do
		if [ "$skip_fastq" -eq 0 ]; then
			process_fastqs "$GSE"
		fi
#	wait
	#if [ "$download_bam" -eq 1 ]; then
	#	for GSE in "${GSEs[@]}"; do
	#		process_bams "$GSE"
	#	done
	
		download_supp_files $GSE
	done
}

main "$@"

