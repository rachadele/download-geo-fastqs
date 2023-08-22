#!/bin/bash
source utils/utils.sh

read -erp "Enter GEO accession to be processed: " GSE

check_for_subseries $GSE
