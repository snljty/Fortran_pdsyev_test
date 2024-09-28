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
nthreads_per_proc=2
# we assume that $nprocs is divisible by 2, this is correct for most modern CPUs.
echo "Running with $((nprocs/nthreads_per_proc)) processes, and each contains $nthreads_per_proc threads"
echo "command argument passed to the program: $*"
MKL_NUM_THREADS=$nthreads_per_proc mpirun -np $((nprocs/nthreads_per_proc)) ./test.intel.x $*

