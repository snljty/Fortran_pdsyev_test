#! /bin/bash -e

# for mymodule in openblas/0.3.27 openmpi/4.1.6 scalapack/2.2.0-openblas
# do
#     if ! module is-loaded $mymodule
#     then
#         module load $mymodule
#     fi
# done
make -f Makefile.gnu clean
make -f Makefile.gnu
nprocs=$(($(cat /proc/cpuinfo | grep 'physical id' | sort | uniq | wc -l | awk '{print int($0)}')*$(cat /proc/cpuinfo | grep 'core id' | sort | uniq | wc -l | awk '{print int($0)}')))
nthreads_per_proc=2
# we assume that $nprocs is divisible by 2, this is correct for most modern CPUs.
echo "Running with $((nprocs/nthreads_per_proc)) processes, and each contains $nthreads_per_proc threads"
echo "command argument passed to the program: $*"
OMP_NUM_THREADS=$nthreads_per_proc mpirun -np $((nprocs/nthreads_per_proc)) ./test.gnu.x $*


