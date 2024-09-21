module cmd_args
    implicit none
    type :: string
        character(len=:), pointer :: str
    end type string

    integer :: argc
    type(string), dimension(:), pointer :: argv

    contains

    subroutine get_args()
        implicit none
        integer :: argl, iarg

        argc = command_argument_count()
        allocate(argv(0:argc))
        do iarg = 0, argc
            call get_command_argument(iarg, length=argl)
            allocate(character(len=argl) :: argv(iarg)%str)
            call get_command_argument(iarg, value=argv(iarg)%str)
        end do

        return
    end subroutine get_args

    subroutine free_args()
        implicit none
        integer :: iarg

        do iarg = 0, argc
            deallocate(argv(iarg)%str)
            nullify(argv(iarg)%str)
        end do
        deallocate(argv)
        nullify(argv)

        return
    end subroutine free_args
end module cmd_args

program main
    use mpi
    use cmd_args
    implicit none

    external :: blacs_pinfo, blacs_setup
    external :: blacs_get, blacs_gridinit, blacs_gridinfo
    external :: pdlaset, pdelset, blacs_barrier
    external :: pdlaprnt
    external :: pdsyev
    external :: blacs_gridexit, blacs_exit
    integer, external :: numroc
    integer, external :: indxg2l, indxg2p

    logical :: n_read_from_cmd = .false.
    integer, parameter :: n_def = 2048
    integer :: m, n, i, j
    integer :: lda
    double precision, dimension(:), allocatable :: w
    double precision, dimension(:), allocatable :: work
    double precision, dimension(:, :), allocatable :: a, v
    integer :: lwork
    integer :: status

    ! for ScaLAPACK anc BLACS/PBLAS
    integer :: mypnum, nprocs
    integer :: context
    integer :: nprow, npcol ! cannot be constances
    integer, parameter :: mb = 64, nb = 64
    ! seems these mb and nb values are suitable for most HPCs for high performance
    ! 64 and 128 are commonly used
    integer, parameter :: dlen = 9
    integer :: myrow, mycol
    integer, dimension(dlen) :: desca, descv
    integer :: mpa, nqa
    integer :: val
    integer :: locali, localj

    ! for MPI
    logical :: initialized, finalized

    ! for time
    double precision :: t0, tt, dt

    ! see https://netlib.org/scalapack/slug/node33.html#basicsteps for details
    ! also please check the example https://netlib.org/scalapack/examples/sample_pdsyev_call.f

    ! initialize MPI
    call mpi_initialized(initialized, status)
    if (status /= 0) then
        write(0, '(a)') "MPI initialization failed."
        stop 1
    end if
    if (.not. initialized) then
        call mpi_init(status)
        if (status /= 0) then
            write(0, '(a)') "MPI initialization failed."
            stop 1
        end if
    end if

    ! get number of processors
    call blacs_pinfo(mypnum, nprocs)
    if (nprocs < 1) then
        write(0, '(a)') "This program has to be run with mpirun/mpiexec."
        stop 1
    end if
    ! you may use the comments below if you have default nprow and npcol values
    ! if (nprocs < 1) then
    !     call blacs_setup(mypnum, nprow * npcol)
    ! end if

    ! get command arguments
    call get_args()
    
    ! pharse command arguments and set matrix size
    n_read_from_cmd = .false.
    if (argc > 0) then
        read(argv(1)%str, *, iostat=status) n
        if (status == 0) then
            if (n > 0) then
                n_read_from_cmd = .true.
            end if
        end if
    end if
    if (.not. n_read_from_cmd) then
        n = n_def
    end if
    m = n
    if (mypnum == 0) then
        write(*, '(a, i0, a, i0)') "matrix size is ", m, " by ", n
    end if

    ! release command arguments
    call free_args()

    ! get a proper nprow and npcol
    ! the current strategy is to let nprow >= npcol, nprow * npcol = nprocs, minimize(nprow - npcol)
    npcol = int(floor(sqrt(dble(nprocs))))
    if ((npcol + 1) ** 2 <= nprocs) then
        npcol = npcol + 1
    end if
    do while (npcol > 1)
        if (mod(nprocs, npcol) == 0) then
            exit
        end if
        npcol = npcol - 1
    end do
    nprow = nprocs / npcol

    ! Initialize the Process Grid
    call blacs_get(-1, 0, context)
    ! BLACS_GET(ICONTXT, WHAT, VAL); WHAT == 0: Handle indicating default system context
    ! ICONTXT: On WHATs that are tied to a particular context, this is the integer handle indicating the context.
    call blacs_gridinit(context, 'C', nprow, npcol) ! R: row major; C: column major
    call blacs_gridinfo(context, nprow, npcol, myrow, mycol)
    if (myrow == -1) then
        write(0, '(a)') "BLACS initialization error"
        stop 1
    end if
    call blacs_barrier(context, 'A')

    ! get distributed matrix block size and leading dimension
    mpa = numroc(m, mb, myrow, 0, nprow)
    nqa = numroc(n, nb, mycol, 0, npcol)
    lda = max(mpa, 1)

    ! Distribute the Matrix on the Process Grid
    ! check https://netlib.org/scalapack/explore-html/dd/d22/descinit_8f_source.html for comments
    ! and see https://netlib.org/scalapack/slug/node77.html#secdesc1 also
    call descinit(desca, m, n, mb, nb, 0, 0, context, lda, status)
    if (status /= 0) then
        write(0, '(a, i0, a)') "Error: descinit returned ", status, " instead of 0."
        stop 1
    end if
    call descinit(descv, m, n, mb, nb, 0, 0, context, lda, status)
    if (status /= 0) then
        write(0, '(a, i0, a)') "Error: descinit returned ", status, " instead of 0."
        stop 1
    end if

    ! allocate memory for matrices and vectors
    allocate(w(min(m, n)))
    allocate(a(mpa, nqa), v(mpa, nqa))

    ! get lwork
    lwork = -1
    allocate(work(- lwork))
    call pdsyev('V', 'L', n, a, 1, 1, desca, w, v, 1, 1, descv, work, lwork, status)
    if (status /= 0) then
        write(0, '(a, i0, a)') "Error: pdsyev returned ", status, " instead of 0."
        stop 1
    end if
    lwork = int(work(1))
    deallocate(work)
    lwork = max(lwork, mb)
    lwork = max(lwork, nb)
    allocate(work(lwork))

    ! initialize the matrix
    ! set a to all 0
    call pdlaset('A', m, n, 0.d0, 0.d0, a, 1, 1, desca)
    do i = 1, n
        j = mod(i, n) + 1
        ! set a(i, j) and a(j, i) to 1
        call pdelset(a, i, j, desca, 1.d0)
        call pdelset(a, j, i, desca, 1.d0)
    end do

    ! if you want to check the matrix a
    ! call pdlaprnt(m, n, a, 1, 1, desca, 0, 0, 'a', 6, work) ! 6 = stdout
    ! work needed for pdlaprnt is at least mb, which is much smaller than that of pdsyev

    ! get begin time
    t0 = mpi_wtime()

    ! Call the ScaLAPACK Routine
    ! real call of pdsyev
    call blacs_barrier(context, 'A')
    call pdsyev('V', 'L', n, a, 1, 1, desca, w, v, 1, 1, descv, work, lwork, status)
    if (status /= 0) then
        write(0, '(a, i0, a)') "Error: pdsyev returned ", status, " instead of 0."
        stop 1
    end if

    ! get end time
    tt = mpi_wtime()
    dt = tt - t0

    ! output results
    call blacs_barrier(context, 'A')
    i = 1
    j = n
    if (myrow == indxg2p(i, mb, myrow, 0, nprow) .and. &
        mycol == indxg2p(j, nb, mycol, 0, npcol)) then
        locali = indxg2l(i, mb, myrow, 0, nprow)
        localj = indxg2l(j, nb, mycol, 0, npcol)
        write(*, '(a, f9.6)') "largest eigenvalue: (should be 2) ", w(n)
        write(*, '(a, f9.6)') &
            "correspond eigenvalue's first component squared times n: (should be 1) ", v(locali, localj) ** 2 * n
        write(*, '(a, f0.1, a)') "Time elapsed for the calculation: ", dt, " s"
    endif

    ! release memory
    deallocate(work)
    deallocate(a, v)
    deallocate(w)

    ! Release the Process Grid
    call blacs_gridexit(context)
    call blacs_exit(0)

    ! finalize MPI
    call mpi_finalized(finalized, status)
    if (status /= 0) then
        write(0, '(a)') "MPI finalization failed."
        stop 1
    end if
    if (.not. finalized) then
        call mpi_finalize(status)
        if (status /= 0) then
            write(0, '(a)') "MPI finalization failed."
            stop 1
        end if
    end if

    stop
end program main
