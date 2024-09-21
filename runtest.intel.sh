#! /bin/bash -e

# for mymodule in intel/oneapi/compiler intel/oneapi/mkl intel/oneapi/mpi
# do
#     if ! module is-loaded $mymodule
#     then
#         module load $mymodule
#     fi
# done
make -f Makefile.intel clean
make -f Makefile.intel
nprocs=$(($(cat /proc/cpuinfo | grep 'physical id' | sort | uniq | wc -l | awk '{print int($0)}')*$(cat /proc/cpuinfo | grep 'core id' | sort | uniq | wc -l | awk '{print int($0)}')))
echo "Running with $nprocs processes"
echo "command argument passed to the program: $*"
mpirun -np $nprocs ./test.intel.x $*

