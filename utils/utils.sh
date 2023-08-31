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
 	local srx_accessions=$(grep -oP '(?<=term=)[A-Za-z0-9]+' "${GSE}_family.xml")
   	local srr_accessions=$(echo "$srx_accessions" | xargs -n 1 pysradb srx-to-srr | tail -n +2 | grep -v "run_accession" | awk '{print $2}')
    echo $srr_accessions
    #return srr accessions
}

function download_fastqs() {
    local GSE=$1
    shift
	local accessions=("$@")
 	local output_dir="/hive/data/outside/geo/$GSE"
    #make parent directory if it doesn't exist yet
	mkdir -p $output_dir
	for line in "${accessions[@]}"; do
 		#line represents SRR accession
    		local log="$output_dir/$line.log" #log can't be in subdirectory bc it gets written before /hive/data/outside/geo/$GSE/$line is created
		~/sratoolkit.2.11.0-ubuntu64/bin/prefetch "$line" --max-size 900GB -O $output_dir &> $log 
  		#prefetch will automatically create a subdirectory in $output_dir for given SRR
		#if this directory is manually created before prefetch is run it may error out
		echo "Prefetched SRA file for $line"
		# Download and gzip FASTQs
		~/sratoolkit.2.11.0-ubuntu64/bin/fasterq-dump "$line" --include-technical -S -t "$output_dir/$line" -O "$output_dir/$line" &>> $log
		gzip "$output_dir/$line"/*fastq* &>> $log
		echo "FASTQs downloaded and gzipped for $line"
  		#remove sra file
		find "$output_dir/$line" -type f -name "*.sra" -exec rm {} \;
		echo "Removed SRA files for $line"
	 done
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
	echo "$missing_srrs"
}

function download_missing_srrs() {
	#need this to be a separate function from initial download bc sra can't handle feeding srrs back into initial donwload loop
	#reasons not entirely clear not me
	local GSE="$1"
	shift
	local accessions=("$@")
	for line in "${accessions[@]}"; do
		~/sratoolkit.2.11.0-ubuntu64/bin/prefetch "$line" --max-size 900GB -O "/hive/data/outside/geo/$GSE" &> "/hive/data/outside/geo/$GSE/$line.log"
		echo "Prefetched SRA file for $line"

		# Download and gzip FASTQs
		~/sratoolkit.2.11.0-ubuntu64/bin/fasterq-dump "$line" --include-technical -S -t "/hive/data/outside/geo/$GSE/$line" -O "/hive/data/outside/geo/$GSE/$line" &>> "/hive/data/outside/geo/$GSE/$line.log"
		gzip "/hive/data/outside/geo/$GSE/$line"/*fastq* &>> "/hive/data/outside/geo/$GSE/$line/$line.log"
		echo "FASTQs downloaded and gzipped for $line"

		rm -r "/hive/data/outside/geo/$GSE"/*/*sra
		echo "Removed SRA files for $line"
	 done

}

function rename_10x() {
   echo "test"
   local GSE="$1"
	for file_path in "/hive/data/outside/geo/$GSE/"SRR[0-9]*/*.fastq.gz; do
		echo $file_path
		if [ -f "$file_path" ]; then
			local read_length=$(zcat "$file_path" | head -n 2 | tail -n 1 | awk '{print length($0)}')
			local base_name=$(basename "$file_path" .fastq.gz)
			base_name="${base_name%%_[0-9]*}"
			if [[ $(zcat "$file_path" | head -n 4 | sed -n '2p' | grep -o 'A\{100,\}') ]]; then	
				echo "found polyA tail, assuming technical barcode read 1"
				new_name="${base_name}_R1.fastq.gz"
			else
	   			if [[ $read_length -eq 8 ]]; then
        			new_name="${base_name}_I1.fastq.gz"
    			elif [[ $read_length -eq 26 || $read_length -eq 28 ]]; then
        			new_name="${base_name}_R1.fastq.gz"
    			elif [[ $read_length -ge 90 ]]; then
					new_name="${base_name}_R2.fastq.gz"
    			else
        			echo "Unknown read length for file: $file_path"
        			continue
    			fi
			fi
			mv "$file_path" "$(dirname "$file_path")/$new_name"
		else 
			echo "file path not found"
		fi
	done
}

function rename_SS2() {
   local GSE="$1"
   for file_path in "/hive/data/outside/geo/$GSE/"SRR[0-9]*/*.fastq.gz; do
        if [ -f "$file_path" ]; then
			local base=$(basename "$filename")
        	if [[ $base =~ _1\.fastq\.gz$ ]]; then
            	new_name="${base/_1.fastq.gz/_R1.fastq.gz}"
            	mv "$file_path" "$(dirname "$file_path")/$new_name"
        	
			elif [[ $base =~ _2\.fastq\.gz$ ]]; then
            	new_name="${base/_2.fastq.gz/_R2.fastq.gz}"
				mv "$file_path" "$(dirname "$file_path")/$new_name"
			fi
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


