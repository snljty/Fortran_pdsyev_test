#! /bin/bash -e

# for mymodule in lapack/3.12.0 openmpi/4.1.1 scalapack/2.2.0 
# do
#     if ! module is-loaded $mymodule
#     then
#         module load $mymodule
#     fi
# done
make -f Makefile.gnu clean
make -f Makefile.gnu
nprocs=$(($(cat /proc/cpuinfo | grep 'physical id' | sort | uniq | wc -l | awk '{print int($0)}')*$(cat /proc/cpuinfo | grep 'core id' | sort | uniq | wc -l | awk '{print int($0)}')))
echo "Running with $nprocs processes"
echo "command argument passed to the program: $*"
mpirun -np $nprocs ./test.gnu.x $*

