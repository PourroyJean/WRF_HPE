#!/bin/bash -l
#SBATCH --account v10000
#SBATCH --partition workq
#SBATCH --nodes=1             
#SBATCH --ntasks=1            
#SBATCH --cpus-per-task=64
#SBATCH --time=24:00:00
#SBATCH --output=%x_%j.out    # Standard + Error output file
#SBATCH --hint=nomultithread
#SBATCH --exclusive

############# MODULES  ######################
# Load appropriate modules based on the selected environment : 
# TODO : module purge and load the correct modules manually
if [ "$ENV" == "GNU" ]; then
    module swap PrgEnv-cray PrgEnv-gnu/8.5.0
elif [ "$ENV" == "INTEL" ]; then
    module swap PrgEnv-cray PrgEnv-intel/8.5.0
elif [ "$ENV" == "AOCC" ]; then
    module swap PrgEnv-cray PrgEnv-aocc/8.5.0
    module swap cray-mpich/8.1.27 cray-mpich/8.1.28     # TODO : after upgrade this should not be needed  
elif [ "$ENV" == "CRAY" ]; then
    # Cray environment is already loaded by default
    :
fi

# Common modules
module load cray-hdf5
module load cray-netcdf
module load cray-parallel-netcdf
module load craype-x86-genoa
module load flex/2.6.4


########### CPE compilers ####################
export CC=cc
export CXX=CC
export FC=ftn
export F77=ftn
############# IO #########################
export HDF5=$HDF5_DIR
export PHDF5=$HDF5_DIR
export NETCDF=$NETCDF_DIR
export PNETCDF=$PNETCDF_DIR
export PNETCDF_QUILT=1
export WRFIO_NCD_LARGE_FILE_SUPPORT=1
export NETCDF_classic=1
############ WRF #########################
export FLEX_LIB_DIR=/usr/lib64
export FLEX=/usr/bin/flex 
export JASPERLIB=/usr/lib64
export JASPERINC=/usr/include/jasper
export YACC="/usr/bin/yacc -d"
########### CHEM #########################
export WRF_CHEM=1
export WRF_KPP=1
export WRF_EM_CORE=1
##########################################



# Construct the directory name based on ENV + COMPILER
[ "$ENV" == "GNU"   ] && COMPILER_VERSION=$(cc --version | grep -m 1 'gcc'    | grep -oP '\d+\.\d+\.\d+')
[ "$ENV" == "CRAY"  ] && COMPILER_VERSION=$(cc --version | grep -m 1 'clang'  | grep -oP '\d+\.\d+\.\d+')
[ "$ENV" == "INTEL" ] && COMPILER_VERSION=$(cc --version | grep -m 1 'oneAPI' | grep -oP '\d+\.\d+\.\d+' | head -n 1)
[ "$ENV" == "AOCC"  ] && COMPILER_VERSION=$(cc --version | grep -m 1 'clang'  | grep -oP '\d+\.\d+\.\d+' | head -n 1)
DIR=WRF_${WRF_VERSION}_CHEM_${ENV}_${COMPILER_VERSION}_${WRF_LABEL}
LOG_FILE="compile_${DIR}.log"

#         MPI     MPI+OMP
#         dmpar   dmsm
# GNU     34      35
# INTEL   50      51        
# CRAY    46      47
# AOCC    34      35  # Using the same as GNU for now
if [ "$ENV" == "GNU" ]; then
    code=34
elif [ "$ENV" == "AOCC" ]; then
    code=34
elif [ "$ENV" == "CRAY" ]; then
    code=46
elif [ "$ENV" == "INTEL" ]; then
    code=50
fi


echo "====================="
echo " - Preparing to copy and compile WRF :"
echo " - Source      = $SRC_DIR"
echo " - Compilation = $DIR"
echo " - Log file    = $LOG_FILE"
echo " - WRF_VERSION = $WRF_VERSION"
echo " - Env $ENV    = $COMPILER_VERSION (code = $code)"
echo " - WRF_CHEM    = $WRF_CHEM"
echo " - WRF_KPP     = $WRF_KPP"
echo "====================="

echo " -- MODULE LIST --"
module list
if ! module list 2>&1 | grep -iq "PrgEnv-${ENV}"; then
    echo "Error: The loaded PrgEnv does not match the ENV variable ($ENV)"
    exit 1
fi

# Copy sources + configure only if we start a new compilation
if [ "$CONTINUE" == "false" ]; then
    rm -rf $DIR
    cp -r $SRC_DIR $DIR
    cd $DIR
    ./configure <<EOF
$code
1
EOF
else
    cd $DIR
fi


## CPE WRAPPERS 
CONFIGURE_FILE=./configure.wrf
sed -i 's/gcc/cc/' $CONFIGURE_FILE 
sed -i 's/mpicc/cc/' $CONFIGURE_FILE
sed -i 's/gfortran/ftn/' $CONFIGURE_FILE
sed -i 's/mpif90/ftn/' $CONFIGURE_FILE
 
## MANUAL MODIFICATIONS : 
sed -i 's/# -DRSL0_ONLY/-DRSL0_ONLY/g' ./configure.wrf  # Only use one ouput RSL file during the execution

# OMP Version
# TODO : Set OMPCC to –fopenmp (clang) instead of –homp (CCE now uses clang for C compiler)
if [ "$ENV" == "GNU" ]; then
    sed -i 's/^DM_CC.*/DM_CC           =       cc/' $CONFIGURE_FILE                                         # Update DM_CC to use "cc" compiler and remove "-cc=$(SCC)" from the configuration
    sed -i '/^FCOPTIM/s/=\( *\)/=\1-fallow-argument-mismatch /' $CONFIGURE_FILE                             # Add "-fallow-argument-mismatch" to FCOPTIM to allow argument mismatches
    sed -i '/^FCNOOPT/s/=\( *\)/=\1-fallow-argument-mismatch -fallow-invalid-boz  /' $CONFIGURE_FILE        # Add flags to FCNOOPT to allow argument mismatches and invalid boz constants
    sed -i '/^FCBASEOPTS_NO_G/s/=\( *\)/=\1-fallow-argument-mismatch -fallow-invalid-boz /' $CONFIGURE_FILE # Add flags to FCBASEOPTS_NO_G to allow argument mismatches and invalid boz constants
    # KPP
    sed -i 's/-ll //' chem/KPP/kpp/kpp-2.1/src/Makefile                                                     # Remove the linking to the libl library (-ll) from the Makefile
    sed -i 's|^YACC=.*|YACC="/usr/bin/yacc -d"|' chem/KPP/configure_kpp                                     # Replace the YACC definition with /usr/bin/yacc -d in the configure_kpp file
elif [ "$ENV" == "AOCC" ]; then
    echo "AMD compilation..."
    # AMD-specific modifications
    sed -i 's/^DM_CC.*/DM_CC           =       cc/' $CONFIGURE_FILE                                         # Update DM_CC to use "cc" compiler and remove "-cc=$(SCC)" from the configuration
    #Errors:
    sed -i '/^BYTESWAPIO/s/-fconvert=big-endian//' $CONFIGURE_FILE
    sed -i '/^CFLAGS_LOCAL/s/-w//' $CONFIGURE_FILE
    sed -i '/^FCBASEOPTS_NO_G/s/-w//' $CONFIGURE_FILE
    #Warnings:
    sed -i '/^FORMAT_FREE/s/-ffree-line-length-none//' $CONFIGURE_FILE
    sed -i '/^BYTESWAPIO/s/-frecord-marker=4//' $CONFIGURE_FILE
elif [ "$ENV" == "INTEL" ]; then
    sed -i 's/^DM_CC.*/DM_CC = cc/' $CONFIGURE_FILE
    sed -i '/FCOPTIM/s/-O3/-O3 -fp-model precise/' $CONFIGURE_FILE
    sed -i '/^FCOPTIM/s/=\( *\)/=\1-fallow-argument-mismatch /' $CONFIGURE_FILE
    sed -i '/^FCNOOPT/s/=\( *\)/=\1-fallow-argument-mismatch -fallow-invalid-boz /' $CONFIGURE_FILE
    sed -i '/^FCBASEOPTS_NO_G/s/=\( *\)/=\1-fallow-argument-mismatch -fallow-invalid-boz /' $CONFIGURE_FILE
elif [ "$ENV" == "CRAY" ]; then
    # For now : modifications are done in our own git https://github.com/mirekand/WRF_cce18/commit/8927d999a22f9f40636e0ea3be2f1ef474d2228f
    #  arch/configure.defaults line 1303 : 
        # ARCH Cray XE and XC CLE/Linux x86_64, Cray CCE compiler
        # -NOOMP           =       -hnoomp
        # +NOOMP           =       -fnoopenmp
        # -OMP             =       # -homp
        # +OMP             =       -fopenmp # -homp
        # -SFC             =       ftn $(NOOMP)
        # +SFC             =       ftn
        # -DM_FC           =       ftn $(NOOMP)
        # +DM_FC           =       ftn
        # -FCOPTIM         =       # -Ofp3 
        # +FCOPTIM         =       -O2 # -Ofp3 
        # -FCBASEOPTS_NO_G =       -N1023 $(FORMAT_FREE) $(BYTESWAPIO) #-ra             
        # +FCBASEOPTS_NO_G =       -N1023 $(FORMAT_FREE) $(BYTESWAPIO) -dC -M 878 #-ra      # -dC    : mismatch (-fallow-argument-mismatch) # -M 878 : disable diagnostic information warning 
        # -CC_TOOLS        =      gcc
        # +CC_TOOLS        =      cc

        ####### chem/KPP/configure_kpp
        # -##PSCC="SCC = cc"
        # +PSCC="SCC = gcc"

        ####### /chem/module_mosaic_addemiss.F
        # INTERFACE
        # +   subroutine mosaic_dust_gocartemis (dt,start_month,num_soil_layers,alt,  &
        # ..........

        ####### chem/module_optical_averaging.F
        # Remove ',' like we did in the past with  sed -i '4701 s/),/)/' chem/module_optical_averaging.F

        echo "Cray compilation..."
fi


## Compilation
time ./compile -j 16 em_real 2>&1 | tee -a $LOG_FILE

[ -f "main/wrf.exe" ] || { echo "Compilation failed"; exit 1; }

echo 
echo "/!\ WARNING /!\ "
echo " + if using NetCDF you may have to modify the io_form_history value to 11 in the namelist.input file"
echo " + To remove warnings at execution time, try to comment the following line in namelist.input : !iofields_filename                   = "my_file_d01.txt"
