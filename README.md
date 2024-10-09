# WRF_HPE

This repository contains scripts to compile the Weather Research and Forecasting (WRF) model on HPE/CRAY systems.
It has been tested on the HPE/CRAY supercomputer "Shaheen 3" at King Abdullah University of Science and Technology (KAUST).


## Compilation Process

To compile WRF, follow these steps:

1. Clone the repository:

   ```
   git clone https://github.com/PourroyJean/WRF_HPE.git
   ```

2. Edit the `compile_wrf.sh` script to set the following variables:

   - `ENV`: Choose the compiler environment (CRAY, GNU, or INTEL)
   - `WRF_VERSION`: Specify the WRF version to compile (e.g., "release-v4.6.0")
   - `WRF_LABEL`: Add an optional label to the compilation directory
   - `CONTINUE`: Set to 'true' to continue an existing compilation, or 'false' to start fresh
   
3. Edit the `compile.sbatch` script to set the slurm parameters (partition, account)
    

3. Run the compilation script:

   ```
   ./compile_wrf.sh
   ```

   This script will:
   - Clone the appropriate WRF repository based on the selected environment
   - Initialize and update git submodules
   - Submit a Slurm job to compile WRF using the `compile.sbatch` script

4. The compilation process will run as a Slurm job. You can monitor the progress by  uncommenting the end of the compile_wrf.sh script.


## Compilation Details

The `compile.sbatch` script handles the following tasks:

- Loads the appropriate modules based on the selected environment
- Sets up necessary environment variables for WRF compilation
- Configures WRF for the selected compiler environment
- Applies any required patches or modifications to the WRF source code
- Compiles WRF with the specified options (including WRF-Chem if enabled)

## Important Notes

- Make sure you have the required permissions and access to the necessary modules and compilers on your HPE system.
- The compilation process may take a significant amount of time, depending on your system's resources and the WRF configuration (Cray compiler can last more than 4 hours)
- If you encounter any issues during compilation, check the Slurm job output file for error messages and consult the WRF documentation or your system administrator for assistance.

## Customization

You can modify the `compile.sbatch` script to adjust compilation options, such as enabling or disabling certain WRF features or changing optimization flags. Make sure to understand the implications of any changes you make to the compilation process.


