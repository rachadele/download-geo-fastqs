#!/bin/bash

#exit when any command fails
#set -e
#keep track of last executed command
#trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
#trap 'echo "\"${last_command}\" command failed with exit code $?."' EXIT


read -erp "Enter GEO accession: " GSE
read -erp "Enter the path to your hca-util virtual environment: " path

source $path/bin/activate
hca-util create $GSE
echo "enter upload area uuid"
read uuid
hca-util select $uuid
aws s3 cp ./ s3://hca-util-upload-area/$uuid --recursive --exclude "*" --include "*"
echo "upload complete"

read -erp "Enter submission uuid: " submission
hca-util sync $submission
