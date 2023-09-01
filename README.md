# Download GEO FASTQs for HCA Submission
This repository contains a Bash script (download-geo-fastqs.sh) designed to simplify the process of downloading data from Gene Expression Omnibus (GEO) submissions and preparing them for submission to the Human Cell Atlas (HCA) data repository. The script supports various options for downloading and processing data, making it a versatile tool for researchers working with single-cell RNA sequencing (scRNA-seq) data generated using 10x or Smart-Seq2 (SS2) library strategies. Additionally, it will download all supplemental files associated with the given GEO series and subseries.

## Prerequisites
Before using this script, ensure you have the following prerequisites installed on your system:

GNU Parallel: Required for parallel processing of SRA data downloads.
Bash: The script is written in Bash and requires it to run.
Git: Optional but recommended for version control.
HCA-utils: Optional, required for certain data processing steps.

## Getting Started
Clone this repository to your local machine:

```
git clone https://github.com/your-username/your-repository.git
```
Navigate to the repository directory:
```
cd your-repository
```

Make the script executable:
```
chmod +x download-geo-fastqs.sh
```

## Usage
The download-geo-fastqs.sh script can be used with various options to control its behavior. Below are some common use cases:

Downloading FASTQ files for a specific GEO accession (e.g., GSE12345):
```
./download-geo-fastqs.sh GSE12345
```

Downloading FASTQ files and renaming them based on library preparation strategy (e.g., "10x" or "ss2"):
```
./download-geo-fastqs.sh -r 10x GSE12345
```

Processing BAM files and renaming them based on library preparation strategy:
```
./download-geo-fastqs.sh -b -r ss2 GSE12345
```

Skipping FASTQ file download and downloading only GEO supplemental files (e.g. Cellranger output or .rds files):
```
./download-geo-fastqs.sh -s GSE12345
```

For a full list of options and additional details, consult the script's built-in help message:
```
./download-geo-fastqs.sh -h
```

Contributing
Contributions to this project are welcome! If you encounter issues or have ideas for improvements, please open an issue or submit a pull request.






