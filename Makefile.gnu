# module load openblas/0.3.23 openmpi/4.1.6 scalapack/2.2.0-openblas
SHELL = bash
FC := mpifort
FCLINKER := $(FC)
# VERSION := Debug
VERSION := Release
ifeq ("$(shell echo $(VERSION) | tr a-z A-Z)", "DEBUG")
	OPTS := -g
	OPTLV := -O0
else
	OPTS := -s
	OPTLV := -O2
endif
SCALAPACK_LIB := -l scalapack
OPENMP_LIB := -fopenmp
MACROS := -cpp

.PHONY: all
all: test.gnu.x

test.gnu.x: test.o 
	@echo Linking $@ against $^ ...
	$(FCLINKER) -o $@ $^ $(SCALAPACK_LIB) $(OPTS) $(MACROS) $(OPENMP_LIB)

%.o: %.f90
	@echo Compiling $@ ...
	$(FC) -o $@ -c $< -fPIC $(OPTLV) $(OPTS) -ffpe-summary=none $(MACROS) $(OPENMP_LIB)

.PHONY: clean
clean:
	-rm -f test.o cmd_args.mod

.PHONY: veryclean
veryclean: clean
	-rm -f test.gnu.x

