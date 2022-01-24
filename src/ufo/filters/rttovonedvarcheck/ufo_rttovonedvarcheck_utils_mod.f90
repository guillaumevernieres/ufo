! (C) Copyright 2021 Met Office
!
! This software is licensed under the terms of the Apache Licence Version 2.0
! which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

!> Fortran module containing subroutines used by both minimizers.

module ufo_rttovonedvarcheck_utils_mod

use kinds
use ufo_constants_mod, only: min_q
use fckit_log_module, only : fckit_log
use ufo_geovals_mod
use ufo_rttovonedvarcheck_constants_mod
use ufo_rttovonedvarcheck_obs_mod
use ufo_rttovonedvarcheck_profindex_mod
use ufo_rttovonedvarcheck_setup_mod, only: ufo_rttovonedvarcheck
use ufo_vars_mod
use ufo_utils_mod, only: Ops_SatRad_Qsplit, Ops_QSat, Ops_QSatWat, cmp_strings

implicit none
private

! subroutines - public
public ufo_rttovonedvarcheck_check_geovals
public ufo_rttovonedvarcheck_adjust_bmatrix

character(len=max_string) :: message

contains

!-------------------------------------------------------------------------------
!> Check the geovals are ready for the first iteration
!!
!! \details Heritage: Ops_SatRad_SetUpRTprofBg_RTTOV12.f90
!!
!! Check the geovals profile is ready for the first iteration.  The
!! only check included at the moment if the first calculation for 
!! q total.
!!
!! \author Met Office
!!
!! \date 09/06/2020: Created
!!
subroutine ufo_rttovonedvarcheck_check_geovals(self, geovals, profindex, surface_type)

implicit none

! subroutine arguments:
type(ufo_rttovonedvarcheck), intent(in) :: self
type(ufo_geovals), intent(inout) :: geovals   !< model data at obs location
type(ufo_rttovonedvarcheck_profindex), intent(in) :: profindex !< index array for x vector
integer, intent(in) :: surface_type  !< surface type for cold surface check

character(len=*), parameter  :: routinename = "ufo_rttovonedvarcheck_check_geovals"
character(len=max_string)    :: varname
type(ufo_geoval), pointer    :: geoval
integer                      :: gv_index, i     ! counters
integer                      :: nlevels
real(kind_real), allocatable :: temperature(:)  ! temperature (K)
real(kind_real), allocatable :: pressure(:)     ! pressure (Pa)
real(kind_real), allocatable :: qsaturated(:)
real(kind_real), allocatable :: humidity_total(:)
real(kind_real), allocatable :: q(:)            ! specific humidity (kg/kg)
real(kind_real), allocatable :: ql(:)
real(kind_real), allocatable :: qi(:)
real(kind_real)              :: skin_t, pressure_2m, temperature_2m, NewT
integer                      :: level_1000hpa, level_950hpa

write(message, *) routinename, " : started"
call fckit_log % debug(message)

! -------------------------------------------
! Load variables needed by multiple routines
! -------------------------------------------

nlevels = profindex % nlevels
allocate(temperature(nlevels))
allocate(pressure(nlevels))
call ufo_geovals_get_var(geovals, trim(var_ts), geoval)
temperature(:) = geoval%vals(:, 1) ! K
call ufo_geovals_get_var(geovals, trim(var_prs), geoval)
pressure(:) = geoval%vals(:, 1)    ! Pa

!---------------------------------------------------
! 1. Make sure q and q2m does not exceed saturation
!---------------------------------------------------
if (profindex % q(1) > 0 .or. profindex % qt(1) > 0) then
  allocate(q(nlevels))
  allocate(qsaturated(nlevels))

  ! Get humidity - kg/kg
  varname = trim(var_q)
  call ufo_geovals_get_var(geovals, varname, geoval)
  q(:) = geoval%vals(:, 1)

  ! Calculated saturation humidity
  if (self % UseRHwaterForQC) then
    call Ops_QsatWat (qsaturated(:),   & ! out
                      temperature(:),  & ! in
                      pressure(:),     & ! in
                      nlevels)           ! in
  else
    call Ops_Qsat (qsaturated(:),   & ! out
                   temperature(:),  & ! in
                   pressure(:),     & ! in
                   nlevels)           ! in  
  end if

  ! Limit q
  where (q > qsaturated)
    q = qsaturated
  end where
  where (q < min_q)
    q = min_q
  end where

  ! Assign values to geovals q
  gv_index = 0
  do i=1,geovals%nvar
    if (cmp_strings(varname, geovals%variables(i))) gv_index = i
  end do
  geovals%geovals(gv_index) % vals(:,1) = q(:)

  deallocate(q)
  deallocate(qsaturated)
end if

if (profindex % q2 > 0) then
  allocate(q(1))
  allocate(qsaturated(1))

  ! Get humidity - kg/kg
  varname = trim(var_sfc_q2m)
  call ufo_geovals_get_var(geovals, varname, geoval)
  q(1) = geoval%vals(1, 1)

  ! Calculated saturation humidity
  if (self % UseRHwaterForQC) then
    call Ops_QsatWat (qsaturated(1:1),   & ! out
                      temperature(1:1),  & ! in
                      pressure(1:1),     & ! in
                      1)                   ! in
  else
    call Ops_Qsat (qsaturated(1:1),   & ! out
                   temperature(1:1),  & ! in
                   pressure(1:1),     & ! in
                   1)                   ! in
  end if

  ! Limit q
  if (q(1) > qsaturated(1)) q(1) = qsaturated(1)
  if (q(1) < min_q) q(1) = min_q

  ! Assign values to geovals q
  gv_index = 0
  do i=1,geovals%nvar
    if (cmp_strings(varname, geovals%variables(i))) gv_index = i
  end do
  geovals%geovals(gv_index) % vals(1,1) = q(1)

  deallocate(q)
  deallocate(qsaturated)
end if

!-------------------------
! 2. Specific humidity total
!-------------------------

if (profindex % qt(1) > 0) then

  allocate(humidity_total(nlevels))
  allocate(q(nlevels))
  allocate(ql(nlevels))
  allocate(qi(nlevels))

  humidity_total(:) = 0.0
  ! Water vapour
  call ufo_geovals_get_var(geovals, trim(var_q), geoval)
  humidity_total(:) = humidity_total(:) + geoval%vals(:, 1)

  ! Cloud liquid water
  call ufo_geovals_get_var(geovals, trim(var_clw), geoval)
  where (geoval%vals(:, 1) < 0.0) geoval%vals(:, 1) = 0.0
  humidity_total(:) = humidity_total(:) + geoval%vals(:, 1)

  ! Add ciw if rttov scatt is being used
  if (self % RTTOV_mwscattSwitch) then
    call ufo_geovals_get_var(geovals, trim(var_cli), geoval)
    where (geoval%vals(:, 1) < 0.0) geoval%vals(:, 1) = 0.0
    humidity_total(:) = humidity_total(:) + geoval%vals(:, 1)
  end if

  ! Split qtotal to q(water_vapour), q(liquid), q(ice)
  call Ops_SatRad_Qsplit ( 1,       &
                    pressure(:),    &
                    temperature(:), &
                    humidity_total, &
                    q(:),           &
                    ql(:),          &
                    qi(:),          &
                    self % UseQtsplitRain)

  ! Assign values to geovals q
  varname = trim(var_q)  ! kg/kg
  gv_index = 0
  do i=1,geovals%nvar
    if (cmp_strings(varname, geovals%variables(i))) gv_index = i
  end do
  geovals%geovals(gv_index) % vals(:,1) = q(:)

  ! Assign values to geovals q clw
  varname = trim(var_clw)  ! kg/kg
  gv_index = 0
  do i=1,geovals%nvar
    if (cmp_strings(varname, geovals%variables(i))) gv_index = i
  end do
  geovals%geovals(gv_index) % vals(:,1) = ql(:)

  ! Assign values to geovals ciw
  varname = trim(var_cli)  ! kg/kg
  gv_index = 0
  do i=1,geovals%nvar
    if (cmp_strings(varname, geovals%variables(i))) gv_index = i
  end do
  geovals%geovals(gv_index)%vals(:,1) = qi(:)

  deallocate(humidity_total)
  deallocate(q)
  deallocate(ql)
  deallocate(qi)

end if

!----
! Legacy Ops_SatRad_SetUpRTprofBg_RTTOV12.f90 - done here to make sure geovals are updated
! Reset low level temperatures over seaice and cold, low land as per Ops_SatRad_SetUpRTprofBg.F90
! N.B. I think this should be flagged so it's clear that the background has been modified
!----
if(surface_type /= RTsea .and. self % UseColdSurfaceCheck) then

  ! Get skin temperature
  call ufo_geovals_get_var(geovals, var_sfc_tskin, geoval)
  skin_t = geoval%vals(1, 1)

  ! Get 2m pressure
  call ufo_geovals_get_var(geovals, var_ps, geoval)
  pressure_2m = geoval%vals(1, 1)

  ! Get 2m temperature
  call ufo_geovals_get_var(geovals, var_sfc_t2m, geoval)
  temperature_2m = geoval%vals(1, 1)

  if(skin_t < 271.4_kind_real .and. &
     pressure_2m  > 95000.0_kind_real) then

     level_1000hpa = minloc(abs(pressure - 100000.0_kind_real),DIM=1)
     level_950hpa = minloc(abs(pressure - 95000.0_kind_real),DIM=1)

     NewT = temperature(level_950hpa)
     if(pressure_2m > 100000.0_kind_real) then
       NewT = max(NewT, temperature(level_1000hPa))
     end if
     NewT = min(NewT, 271.4_kind_real)

     temperature(level_1000hPa) = max(temperature(level_1000hPa), NewT)
     temperature_2m = max(temperature_2m, NewT)
     skin_t = max(skin_t, NewT)

     ! Put updated values back into geovals
     ! Temperature
     gv_index = 0
     varname = trim(var_ts)
     do i=1,geovals%nvar
       if (cmp_strings(varname, geovals%variables(i))) gv_index = i
     end do
     geovals%geovals(gv_index) % vals(level_1000hPa,1) = temperature(level_1000hPa)

     ! 2m Temperature
     gv_index = 0
     varname = trim(var_sfc_t2m)
     do i=1,geovals%nvar
       if (cmp_strings(varname, geovals%variables(i))) gv_index = i
     end do
     geovals%geovals(gv_index) % vals(1,1) = temperature_2m

     ! Skin Temperature
     gv_index = 0
     varname = trim(var_sfc_tskin)
     do i=1,geovals%nvar
       if (cmp_strings(varname, geovals%variables(i))) gv_index = i
     end do
     geovals%geovals(gv_index) % vals(1,1) = skin_t

   endif

endif

! Tidy up
if (allocated(temperature))    deallocate(temperature)
if (allocated(pressure))       deallocate(pressure)
if (allocated(qsaturated))     deallocate(qsaturated)
if (allocated(humidity_total)) deallocate(humidity_total)
if (allocated(q))              deallocate(q)
if (allocated(ql))             deallocate(ql)
if (allocated(qi))             deallocate(qi)

write(message, *) routinename, " : ended"
call fckit_log % debug(message)

end subroutine ufo_rttovonedvarcheck_check_geovals

!-----------------------------------------------------------
!> Adjust b matrix for 1D-Var setup.
!!
!! \author Met Office
!!
!! \date 19/05/2021: Created
!!
subroutine ufo_rttovonedvarcheck_adjust_bmatrix(profindex, &
            obs, obindex, config, &
            b_matrix, b_inverse, b_sigma)

implicit none

type(ufo_rttovonedvarcheck_profindex), intent(inout) :: profindex !< index array for x vector
type(ufo_rttovonedvarcheck_obs), intent(in) :: obs
integer, intent(in)                         :: obindex
type(ufo_rttovonedvarcheck), intent(in)     :: config
real(kind_real), intent(inout)              :: b_matrix(:,:)
real(kind_real), intent(inout)              :: b_inverse(:,:)
real(kind_real), intent(inout)              :: b_sigma(:)

integer :: i, j, chanindex
real(kind_real) :: MwEmissError
real(kind_real) :: bscale

!! Switch off emissivity retrieval if not needed or over sea
!! or if missing values exist in microwave emissivity error atlas
if (obs % surface_type(obindex) /= RTland .or. &
    .not. allocated(obs % mwemisserr) ) profindex % mwemiss(:) = 0

!IF (SatInfo % Systemtype /= Stype_ATOVS .OR. &
!   .NOT. UseEmissivityAtlas .OR. Ob % surface /= RTland) THEN
!  Profindex % mwemiss(:) = 0
!ELSE
!  IF (ASSOCIATED (Ob % MwEmErrAtlas)) THEN
!    IF (ABS (Ob % MwEmErrAtlas(1) - RMDI) < RMDItol) THEN
!      Profindex % mwemiss(:) = 0
!    END IF
!  END IF
!END IF

! This has been left in for future development
!! Use errors associated with microwave emissivity atlas
if (profindex % mwemiss(1) > 0) then

  ! Atlas uncertainty stored in Ob % MwEmErrAtlas, use this to scale each
  ! row/column of the B matrix block.
  ! The default B matrix, contains error
  ! covariances representing a global average. Here, those elements are scaled
  ! by a factor MwEmissError/SQRT(diag(B_matrix)) for each channel.
  do i = profindex % mwemiss(1), profindex % mwemiss(2)
    chanindex = 0
    do j = 1, size(obs % channels)
      if (obs % channels(j) == config % EmissToChannelMap(i - profindex % mwemiss(1) + 1)) then
        chanindex = j
        cycle
      end if
    end do
    if (chanindex == 0) then
      write(message,*) "MwEmissError for channel ",config % EmissToChannelMap(i - profindex % mwemiss(1) + 1), &
                       "is required. This channel should be included in the list of filter vars for the ", &
                       "RTTOVOneDVarCheck. The channel will not be used in the minimization if it was rejected ", &
                       "prior to the RTTOVOneDVarCheck."
      call abor1_ftn(message)
    end if
    MwEmissError = obs % mwemisserr(chanindex, obindex)
    if (MwEmissError > 1.0E-4 .and. MwEmissError < 1.0) then
      bscale = MwEmissError / sqrt (b_matrix(i,i))
      b_matrix(:,i) = b_matrix(:,i) * bscale
      b_matrix(i,:) = b_matrix(i,:) * bscale
      b_inverse(:,i) = b_inverse(:,i) / bscale
      b_inverse(i,:) = b_inverse(i,:) / bscale
      b_sigma(i) = b_sigma(i) * bscale
    end if
  end do

end if

!! Scale the background skin temperature error covariances over land
if (profindex % tstar > 0) then
  if (obs % surface_type(obindex) == RTland .and. config % SkinTempErrorLand >= 0.0) then
    write(*,*) "Adjusting b matrix t star = ", profindex % tstar
    bscale = config % SkinTempErrorLand / sqrt (b_matrix(profindex % tstar,profindex % tstar))
    b_matrix(:,profindex % tstar) = b_matrix(:,profindex % tstar) * bscale
    b_matrix(profindex % tstar,:) = b_matrix(profindex % tstar,:) * bscale
    b_inverse(:,profindex % tstar) = b_inverse(:,profindex % tstar) / bscale
    b_inverse(profindex % tstar,:) = b_inverse(profindex % tstar,:) / bscale
    b_sigma(profindex % tstar) = b_sigma(profindex % tstar) * bscale
  end if
end if

end subroutine ufo_rttovonedvarcheck_adjust_bmatrix

! ----------------------------------------------------------

end module ufo_rttovonedvarcheck_utils_mod
