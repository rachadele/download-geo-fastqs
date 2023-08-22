#!/bin/bash


function download_miniml_file() {
    local GSE=$1
    local stub="${GSE%???}nnn" # Replace the last three characters of the accession with "nnn"
    local url="https://ftp.ncbi.nlm.nih.gov/geo/series/$stub/$accession/miniml/$accession""_family.xml.tgz"
    output_file="${GSE}_family.xml.tgz"
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
    local output_dir="/hive/data/outside/geo/$GSE"
    mkdir -p "$output_dir"
    local srp_accessions=$(pysradb gse-to-srp "$GSE" | tail -n +2 | awk '{print $2}')

    if [ -z "$srp_accessions" ]; then
       # echo "No SRP accessions found for the provided GSE accession: $GSE"
        download_miniml_file "$GSE"
        #check for subseries in the MINiML file for the given accession
        subseries=$(grep "SuperSeries of" ${GSE}_family.xml | grep -oP '(?<=target=")GSE[0-9]+')
        #if the subseries object is empty
        if [[ -z $subseries ]]; then 
	        echo "No SubSeries found" 
            local srx_accessions=$(grep -oP '(?<=term=)[A-Za-z0-9]+' "${GSE}_family.xml")
            local srr_accessions=$(echo "$srx_accessions" | xargs -n 1 pysradb srx-to-srr | tail -n +2 | grep -v "run_accession" | awk '{print $2}')
            echo "$srr_accessions" >> "{$output_dir}_Acc_list.txt"
        else #subseries found in MINiML file
	        echo "the SuperSeries $GSE contains SubSeries $(echo -n $subseries)"; 
	        for accession in $subseries; do
                subdir="/hive/data/outside/geo/$GSE/$subseries"
                mkdir -p $subdir
                cd $subdir
	            download_miniml_file "$accession"
                local srx_accessions=$(grep -oP '(?<=term=)[A-Za-z0-9]+' "${GSE}_family.xml")
                local srr_accessions=$(echo "$srx_accessions" | xargs -n 1 pysradb srx-to-srr | tail -n +2 | grep -v "run_accession" | awk '{print $2}')
                echo "$srr_accessions" >> "{$subdir}_Acc_list.txt"
                cd ..
                done #download MINiML file for each subseries
            fi
        #rm *gz #remove gzipped MINiML files
        #extract supplementary links from each MINiML file and download using wget
        #for miniml_file in *.xml; do
        #    local srx_accessions=$(grep -oP '(?<=term=)[A-Za-z0-9]+' "${GSE}_family.xml")
        #    local srr_accessions=$(echo "$srx_accessions" | xargs -n 1 pysradb srx-to-srr | tail -n +2 | grep -v "run_accession" | awk '{print $2}')
        else
           local srr_accessions=$(echo "$srp_accessions" | xargs -n 1 pysradb srp-to-srr | awk '{print $2}' | grep -v "run*")
    
    #return srr accessions
            echo "$srr_accessions"
            echo "$srr_accessions" >> "{$output_dir}_Acc_list.txt"
            fi
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

    rm -r "$output_dir/"*.sra
    echo "removing SRA files for $SRR"
}

function check_fastq_downloads() {
    local GSE=$1
    local expected_srrs=$(get_srr_accessions "$GSE")
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
    local file_path="$1"
    local read_length=$(zcat "$file_path" | head -n 2 | tail -n 1 | awk '{print length($0)}')
    local base_name=$(basename "$file_path" .fastq.gz)
    
    if [[ $read_length -eq 8 ]]; then
        new_name="${base_name}_I1.fastq.gz"
    elif [[ $read_length -eq 26 || $read_length -eq 28 ]]; then
        new_name="${base_name}_R1.fastq.gz"
    elif [[ $read_length -eq 98 ]]; then
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

function donwload_supp_files() {
    GSE=$1
    #pass the GEO accession to the download function to download MINiML file
    download_miniml_file $GSE
    #check for subseries in the MINiML file for the given accession
    subseries=$(grep "SuperSeries of" ${GSE}_family.xml | grep -oP '(?<=target=")GSE[0-9]+')
    #if the subseries object is empty
    if [[ -z $subseries ]]; then 
	    echo "No SubSeries found" 
    else #subseries found in MINiML file
	    echo "the SuperSeries $GSE contains SubSeries $(echo -n $subseries)"; 
	for accession in $subseries; do
	    download_miniml_file "$accession"; done #download MINiML file for each subseries
    fi
    rm *gz #remove gzipped MINiML files
    #extract supplementary links from each MINiML file and download using wget
    for miniml_file in *.xml; do
	    urls=($(awk -F'[<>]' '/<Supplementary-Data type=".*">/ {getline; if ($0 ~ /series/) print}' $miniml_file))
	    for url in "${urls[@]}"; do
	    	wget "$url"
	    done
    done
    rm *xml #remove MINiML files

#export -f *
