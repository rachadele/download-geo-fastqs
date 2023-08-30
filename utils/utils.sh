#!/bin/bash

function download_miniml_file() {
    local GSE=$1
    local stub="${GSE%???}nnn" # Replace the last three characters of the accession with "nnn"
    local url="https://ftp.ncbi.nlm.nih.gov/geo/series/$stub/$GSE/miniml/$GSE""_family.xml.tgz"
    local output_file="${GSE}_family.xml.tgz"
    echo "Downloading MINiML file for accession $GSE..."
    curl -OJL "$url"

    if [ $? -eq 0 ]; then
        echo "Downloaded MINiML file successfully."
        tar -xvzf "$output_file"
        echo "Extracted MINiML file: ${GSE}_family.xml"
    else
        echo "Failed to download MINiML file for accession $GSE."
    fi

}

function get_srr_accessions() {
    local GSE=$1
    #mkdir -p $output_dir
    local srp_accessions=$(pysradb gse-to-srp "$GSE" | tail -n +2 | awk '{print $2}')
	local srr_accessions
    if [ -z "$srp_accessions" ]; then
        echo "No SRP accessions found for the provided GSE accession: $GSE"
        srx_accessions=$(grep -oP '(?<=term=)[A-Za-z0-9]+' "${GSE}_family.xml")
        srr_accessions=$(echo "$srx_accessions" | xargs -n 1 pysradb srx-to-srr | tail -n +2 | grep -v "run_accession" | awk '{print $2}')
    	echo $srr_accessions
    else
        srr_accessions=$(echo "$srp_accessions" | xargs -n 1 pysradb srp-to-srr | awk '{print $2}' | grep -v "run*")
	echo $srr_accessions
    fi 
    #return srr accessions
    
}

function download_fastqs() {
    #can't be run in directory where files are being downloaded becuase prefetch will have a seizure
    local GSE=$1
    local SRR=$2
    local output_dir="/hive/data/outside/geo/$GSE/$SRR"
    local log="${output_dir}/log"
    #make directory if it doesn't exist yet
    mkdir -p "$output_dir"
    ~/sratoolkit.2.11.0-ubuntu64/bin/prefetch $SRR --max-size 900GB --output-directory $output_dir &> $log 
    #potentially change log name to /hive/data/outside/geo/$GSE/SRR.log to help with missing SRR download?
    echo "prefetched SRA file for $SRR"

    ~/sratoolkit.2.11.0-ubuntu64/bin/fasterq-dump $SRR --include-technical -S -t $output_dir -O $output_dir &>> $log
    gzip "$output_dir/"*fastq* &>> $log
    echo "FASTqs downloaded and gzipped for $SRR"

    rm -r "$output_dir/$SRR/$SRR/"*.sra
    echo "removing SRA files for $SRR"
}

function check_fastq_downloads() {
    local GSE=$1
    local result=$(get_srr_accessions "$GSE")
    local expected_srrs=$(echo $result | grep -o 'SRR[0-9]\+')
    local output_dir="/hive/data/outside/geo/$GSE" 
    local missing_srrs=""
    for srr in $expected_srrs; do
        if [[ ! -d "$output_dir/$srr" ]]; then
            missing_srrs="$missing_srrs $srr"
        fi
    done

    if [[ -z "$missing_srrs" ]]; then
        echo "All fastqs for GSE $GSE have been downloaded."
    else
        echo "Missing fastqs for GSE $GSE: $missing_srrs"
    fi
}

function rename_10x() {
    #doesn't work if r1 and r2 are same length (both 150)
    #insert check for poly a tail
    local file_path="$1"
    local read_length=$(zcat "$file_path" | head -n 2 | tail -n 1 | awk '{print length($0)}')
    local base_name=$(basename "$file_path" .fastq.gz)
		base_name="${base_name%%_[0-9]*}"
    if [[ $read_length -eq 8 ]]; then
        new_name="${base_name}_I1.fastq.gz"
    elif [[ $read_length -eq 26 || $read_length -eq 28 ]]; then
        new_name="${base_name}_R1.fastq.gz"
    elif [[ $read_length -ge 90 ]]; then
	new_name="${base_name}_R2.fastq.gz"
    else
        echo "Unknown read length for file: $file_path"
        return
    fi
		mv "$file_path" "$(dirname "$file_path")/$new_name"    
}

function rename_SS2() {
    local input_dir="$1"
    
    find "$input_dir" -type f -name "*.fastq.gz" | while read filename; do
        base=$(basename "$filename")
        if [[ $base =~ _1\.fastq\.gz$ ]]; then
            new_name="${base/_1.fastq.gz/_R1.fastq.gz}"
            mv "$filename" "$input_dir/$new_name"
        elif [[ $base =~ _2\.fastq\.gz$ ]]; then
            new_name="${base/_2.fastq.gz/_R2.fastq.gz}"
            mv "$filename" "$input_dir/$new_name"
        fi
    done
}

function download_bams() {
    local GSE=$1
    local SRR=$2
    local output_dir="/hive/data/outside/geo/$GSE/$SRR"
    local bam_dir="/hive/data/outside/geo/$GSE/$SRR/$SRR"
    aws s3 sync s3://sra-pub-src-2/$SRR/ $output_dir;
    aws s3 sync s3://sra-pub-src-1/$SRR/ $output_dir;
    ~rachelschwartz/bamtofastq_linux *bam* $bam_dir
}

function rename_bams() {
    local GSE=$1
    local output_dir="/hive/data/outside/geo/$GSE"
    echo "renaming files"
    for i in $(find $output_dir/SRR*/SRR*/* -type d); do
        cd $i; f=$(echo $i | sed -E s,SRR.{9},, | sed s,/,_,); ls | while read line; do mv $line $(echo $line | sed "s,bamtofastq,$f,"); done; cd ../../../; done
    echo "file rename complete"
}

function has_subseries() {
	local xml_file="$1"
	local subseries
	subseries=$(grep "SuperSeries of" "$xml_file" | grep -oP '(?<=target=")GSE[0-9]+')
	if [[ -z $subseries ]]; then
		return 1
	else
		return 0
	fi
}

function download_supp_files() {
    local GSE="$1"
	local subseries
	local output_dir="/hive/data/outside/geo/$GSE"
	mkdir -p $output_dir
	
	if [ ! -f "$output_dir/${GSE}_family.xml" ]; then cd $output_dir; download_miniml_file "$GSE"; cd ..; fi
	if has_subseries ${GSE}_family.xml; then
		subseries=$(grep "SuperSeries of" ${GSE}_family.xml | grep -oP '(?<=target=")GSE[0-9]+')
		echo "The SuperSeries $GSE contains SubSeries: $(echo -n $subseries)"
		for sub_accession in $subseries; do
			local sub_dir="$output_dir/$sub_accession"
			mkdir -p "$sub_dir"
			cd $sub_dir
			download_miniml_file "$sub_accession"
			echo $sub_accession $sub_dir
			for miniml_file in "$sub_dir"/*xml; do
				urls=($(awk -F'[<>]' '/<Supplementary-Data type=".*">/ {getline; if ($0 ~ /series/) print}' "$miniml_file"))
				for url in "${urls[@]}"; do
					wget -P "$sub_dir" "$url"
				done
			cd .. 
			done
		done
	fi
	for miniml_file in "$output_dir"/*.xml; do
		urls=($(awk -F'[<>]' '/<Supplementary-Data type=".*">/ {getline; if ($0 ~ /series/) print}' "$miniml_file"))
		for url in "${urls[@]}"; do
			wget -P "$output_dir" "$url"
		done			
	done
	find "$output_dir" -type f -name '*.xml.tgz' -exec rm {} \;
	echo "Removed gzipped XML files"
}

