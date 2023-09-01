# Download GEO FASTQs for HCA Submission
This repository contains a Bash script (download-geo-fastqs.sh) designed to simplify the process of downloading data from Gene Expression Omnibus (GEO) submissions and preparing them for submission to the Human Cell Atlas (HCA) data repository. The script supports various options for downloading and processing data, making it a versatile tool for researchers working with single-cell RNA sequencing (scRNA-seq) data generated using 10x or Smart-Seq2 (SS2) library strategies. Additionally, it will automatically download all supplemental files associated with the given GEO series and subseries.

## Prerequisites
Before using this script, ensure you have the following prerequisites installed on your system:

- **GNU Parallel**: Required for parallel processing of SRA data downloads.
- **Bash**: The script is written in Bash and requires it to run.
- **Git**: Optional but recommended for version control.
- **HCA-utils**: Optional, required for certain data processing steps.

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

## Downloading data
The download-geo-fastqs.sh script can be used with various options to control its behavior. Below are some common use cases:

Downloading FASTQ files for a list of GSE accessions (e.g., GSE1, GSE2, GSE3, etc):
```
./download-geo-fastqs.sh GSE1 GSE2 GSE3
```

Downloading FASTQ files and renaming them based on library preparation strategy (e.g., "10x" or "ss2"):
```
./download-geo-fastqs.sh -r 10x GSE12345
```

Downloading BAM files and converting them to FASTQ format:
```
./download-geo-fastqs.sh -b GSE12345
```

Skipping FASTQ file download and downloading only GEO supplemental files (e.g. Cellranger output or .rds files):
```
./download-geo-fastqs.sh -s GSE12345
```

For a full list of options and additional details, consult the script's built-in help message:
```
./download-geo-fastqs.sh -h
```

It is important to understand that only one rename option can be passed per list of GEO accessions. If file renaming is desired, all GEO accessions must have been prepared using the same library strategy (either 10x or SS2). Alternatively, for lists of GSEs with differing library strategies, please rename the files using the rename functions directly:

```
source download-geo-fastq/utils/utils.sh
rename_10x GSE1
rename_SS2 GSE2
```

## Uploading Data (upload-geo-fastqs.sh)

The upload-geo-fastqs.sh script is used to upload data to the HCA data repository. It prompts you to enter necessary information. Here's how to use it:

Create a virtual environment to access the `hca-util` bucket. You will need appropriate credentials for this. Before running the upload script, you must create a virtual `hca-util` environment using virutalenv (this script does not accept conda environments). If you would like to use a conda environment or not use an environment at all, the commands within the upload.sh script can be run on the command line manually. 

Run the script:

```
./upload-geo-fastqs.sh
```
Enter the requested information, such as GEO accession, the path to your virtualenv, upload area UUID, and submission UUID.

The script will activate the HCA utilities environment, create an HCA submission, upload the data to the specified upload area, and then sync the files from the upload area to the submission.

Contributing
Contributions to this project are welcome! If you encounter issues or have ideas for improvements, please open an issue or submit a pull request.






