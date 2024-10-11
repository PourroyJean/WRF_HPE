#!/bin/bash

# MODIFY THE FOLLOWING:
export ENV=AOCC                          # Options: CRAY, GNU, INTEL, AOCC
export WRF_VERSION="release-v4.6.0"     # Available releases at https://github.com/wrf-model/WRF/branches/all?query=release
export WRF_LABEL="genoa"                # Add a label to the compilation directory created
export CONTINUE=false                   # Set to 'true' to continue an existing compilation, or 'false' to start fresh
export SRC_DIR="WRF_SRC_${WRF_VERSION}" # Directory according to the environment. This directory is not modified; the code will be copied before being compiled.


# Only if we start a new compilation : download the sources corresponding to the PrgEnv selected
if [ "$CONTINUE" == "false" ]; then
  rm -rf $SRC_DIR
  echo "Fetching WRF $WRF_VERSION sources for $ENV in $SRC_DIR..."
  if [ "$ENV" == "GNU" ] || [ "$ENV" == "INTEL" ] || [ "$ENV" == "AOCC" ]; then
      git clone --branch $WRF_VERSION --single-branch --depth 1  https://github.com/wrf-model/WRF.git $SRC_DIR
  elif [ "$ENV" == "CRAY" ]; then
      # HPE modification of WRF source code for PrgEnv-Cray
      git clone --branch $WRF_VERSION-cray --single-branch --depth 1 https://github.com/mirekand/WRF_cce18.git $SRC_DIR
      cd $SRC_DIR
      git checkout 8927d999a22f9f40636e0ea3be2f1ef474d2228f
      cd ..
  else
      echo "Error: Unknown environment '$ENV'. Please set ENV to 'CRAY', 'GNU', 'INTEL', or 'AOCC'"
      exit 1
  fi
  # Download submodules in advance since compute nodes lack Internet access: the '/phys/noahmp' submodule must be downloaded in advance
  git -C $SRC_DIR submodule update --init --recursive
  # Check if git clone was successful
  if [ $? -ne 0 ]; then
      echo "Error: Failed to clone the repository."
      exit 1
  fi 
fi

# Launch the compilation with slurm
job_output=$(sbatch --job-name="wrf_${ENV}" compile.sbatch 2>&1) ; sbatch_exit_status=$?
echo "$job_output"


# OPTIONAL
# Submit the job and capture the output and error messages
# Wait until the output file is created
# Read the output file based on the job id
# job_id=$(echo "$job_output" | awk '{print $4}')  # Extract the job ID from the sbatch output
# if [ $sbatch_exit_status -ne 0 ] || [ -z "$job_id" ]; then
#     echo "Error: sbatch command failed or job ID could not be retrieved. Details:"
#     echo "$job_output"
#     exit 1
# fi
# echo "Job submitted with ID: $job_id"
# output_pattern="*${job_id}*.out"
# while [ -z "$(ls $output_pattern 2>/dev/null)" ]; do
#   sleep 1  # Wait 1 second before checking again
# done
# output_file=$(ls $output_pattern)
# tail -f "$output_file"







