;========================================================
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/contributed.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/shea_util.ncl"
load "../functions/mask_tc.ncl"
load "../functions/bearing.ncl"
load "../functions/et_track_plot.ncl"
load "../functions/et_track_checks.ncl"
load "../functions/et_phase_plot.ncl"
load "../functions/cps_calcs.ncl"

;========================================================
; reads in TC trajectories and data
; follow storm through ET
; compute B, Vlt, and Vut
; plot track and plot phase space diagram
; write new ET trajectory file
; D. Thatcher 2014/07/23
;========================================================
begin
print("et_cyclone_phase.ncl")
print(" ")

; type of data
type="era"
; trajectory directory
tdir = "./tc-tracking/"
tfile = "new.txt"
; data directory
dir = "/global/homes/c/czarzyck/scratch/et-hyperion/"
fname1 = "CORI.VR28.NATL.EXT.CAM5.4CLM5.0.dtime900.003.cam.h7."

print(" ")

; select year(s) of traj files to look at.
; if not defined on the command line, you can specify by hardcoding here, useful for debugging
; else, will read in command line vars year_min_str, year_max_str and convert to ints
if (.not. isdefined("year_min_str") .or. .not. isdefined("year_max_str"))
  print("You did not feed in year_min_str or year_max_str, so using debug/default")
  year_min = 2009
  year_max = 2014
else
  year_min=toint(year_min_str)
  year_max=toint(year_max_str)
end if

do_debug=True

; recommended month_min = 1 and month_max = 12 for
; analyzing an entire year of data in final analysis.
; Other months are useful for testing over shorter
; interval or a particular storm
month_min = 1
month_max = 12

; Final year of data, only used if a storm starts
; in Dec. and continues into the next year 
data_year_max = 2014

; Here you can specify the basin that needs to be loaded. negative means all basins, 
; 1 = NATL, 2 = EPAC, 3 = CPAC, 4 = WPAC...
; NOTE, if you change basin from NATL, you will need to change that latmin/latmax
basin = 1
; set lat/lon boundaries to avoid loading unnecessary data
;latmin=0.0
;latmax=85.0  
;lonmin=-120.0
;lonmax=30.0
latmin=0.0
latmax=85.0  
lonmin=-180.0
lonmax=180.0
  
; resolution
resol = 0.25                 ; approximate resolution (deg) of the data (does not need to be exact).
hrintvl=6.0             ; hour interval of data (usually 6 hours if matching ibtracs/WMO)
del_t = hrintvl*60*60   ; time interval in seconds )

; crit radius for calculating B VTL VLU
critRad = 500.0
  
; define small number to use with coordinate indexes (fixes annoying bug)
eps = 0.0001

; info for degree/radian conversions
pi = 4.*atan(1.)
d2r = pi/180.
r2d = (1./d2r)

plot_test = False

;========================================================
; Read in storm trajectories from Colins file
;========================================================

print("Loading storm trajectories...")

; read in trajectory data from ascii file
; get number of storms by counting number of lines with 'start'
nstorms_tot = stringtoint(systemfunc("grep 'start' "+tdir+tfile+" | wc -l"))
print("   Total number of storms = "+nstorms_tot)

tdata_tmp = asciiread(tdir+tfile,-1,"string")  ; read in trajectory data as strings
dims = dimsizes(tdata_tmp)    ; get dimensions
nrows = dims(0)               ; get number of rows
ncol = 8                      ; assign number of columns
delete([/tdir,tfile,dims/])

; create new array that will hold all data except rows containing start information
; add column to contain storm number
tdata = new((/nrows-nstorms_tot,ncol+1/),float)

; create new array to hold all header information for each storm
dur     = new(nstorms_tot,integer)
s_year  = new(nstorms_tot,integer)
s_month = new(nstorms_tot,integer)
s_day   = new(nstorms_tot,integer)
s_hour  = new(nstorms_tot,integer)
e_year  = new(nstorms_tot,integer)
e_month = new(nstorms_tot,integer)

; loop over lines of trajectory data, convert string to float
nstorm = 0   ; assign storm number
n2 = 0       ; counter data without header lines
do n1 = 0,nrows-1  ; loop over all data with header lines
  first = str_get_cols(tdata_tmp(n1),0,0)   ; obtain first character of row
  if (first .ne. "s") then              ; if not 's', this is not a header
    tdata_tmp(n1) = str_sub_str(tdata_tmp(n1),"    "," ")   ; remove extra white space
    tdata_tmp(n1) = str_sub_str(tdata_tmp(n1),"   "," ")    ; remove extra white space
    tdata_tmp(n1) = str_sub_str(tdata_tmp(n1),"  "," ")     ; remove extra white space
    tdata_tmp(n1) = str_strip(tdata_tmp(n1))                ; remove extra white space
    tdata(n2,1::) = tofloat(str_split_csv(tdata_tmp(n1)," ",0))  ; convert to float
    tdata(n2,0) = nstorm - 1   ; assign first dimension as storm number
    n2 = n2 + 1
  else  ; if 's' in the header
    dur(nstorm)     = stringtoint(str_get_field(tdata_tmp(n1),2," "))
    s_year(nstorm)  = stringtoint(str_get_field(tdata_tmp(n1),3," "))
    s_month(nstorm) = stringtoint(str_get_field(tdata_tmp(n1),4," "))
    s_day(nstorm)   = stringtoint(str_get_field(tdata_tmp(n1),5," "))
    s_hour(nstorm)  = stringtoint(str_get_field(tdata_tmp(n1),6," "))
    if (n1 .ne. 0) then
      e_year(nstorm-1)  = floattoint(tdata(n2-1,5))
      e_month(nstorm-1) = floattoint(tdata(n2-1,6))
    end if
    nstorm = nstorm + 1
    continue
  end if
end do
e_year(nstorm-1)  = floattoint(tdata(n2-1,5))
e_month(nstorm-1) = floattoint(tdata(n2-1,6))

delete([/tdata_tmp,n1,n2,nstorms_tot,nstorm,first,nrows,ncol/])

; data now contains all trajectory information with the following columns
; 0 = storm number
; 1 = longitude
; 2 = latitude
; 3 = wind speed
; 4 = sea level pressure
; 5 = year
; 6 = month
; 7 = day
; 8 = hour

;========================================================
; Select storms within desired time period
;========================================================
  
; find indices where data is between given year/month min and max
if (year_max .eq. data_year_max) then
  ind_storm = ind(((s_year .eq. year_min .and. s_month .ge. month_min) .or.  \
                 (s_year .gt. year_min .and. s_year .le. year_max)) .and. \
                ((s_year .eq. year_max .and. e_month .le. month_max) .or.  \
                 (s_year .ge. year_min .and. s_year .lt. year_max)))
else
  ind_storm = ind(((s_year .eq. year_min .and. s_month .ge. month_min) .or.  \
                 (s_year .gt. year_min .and. s_year .le. year_max)) .and. \
                ((s_year .eq. year_max .and. s_month .le. month_max) .or.  \
                 (s_year .ge. year_min .and. s_year .lt. year_max)))
end if

delete([/year_min,year_max,month_min,month_max,e_year,e_month/])

ntc = dimsizes(ind_storm)
print("   Number of storms to be evaluated = "+ntc)
print("Storm trajectories loaded.")
print(" ")

;========================================================
; Assign maximum storm radius based on latitude
;========================================================
  
; preallocate arrays for distance from storm center and radius allowed
nlat = floattoint(1+(latmax-latmin)/resol)
lat = fspan(latmin,latmax,nlat)
rad = new(nlat,float)

do jlat = 0,nlat-1     ; loop over all lats
if (lat(jlat) .lt. 20) then       ; 300 km storm diameter near equator
  rad(jlat) = 300.
else if (lat(jlat) .ge. 45) then  ; 700 km storm diameter in midlatitudes
  rad(jlat) = 700.
else                              ; 500 km storm diameter in between
  rad(jlat) = 500.
end if
end if
end do

delete([/lat,nlat,jlat/])

;========================================================
; Read in data
;========================================================

; loop over each storm
do jtc = 0,ntc-1
  itc = jtc + ind_storm(0)
  print("Storm Number: "+itc)
  print("  "+s_year(itc)+" "+s_month(itc)+" "+s_day(itc))

  ; select trajectory information for individual storm
  tsub_ind = ind(tdata(:,0) .eq. itc)
  tsub = tdata(tsub_ind,:)
  
  dims = dimsizes(tsub)
  nrows = dims(0)

  delete([/tsub_ind,dims/])

  ;========================================================
  ; Test for correct basin
  ;========================================================

  ; select appropriate basin based on trajectory lat/lon
  ; analyze only north atlantic basin storms, skip all others

  if (basin .gt. 0) then
    print("  Checking storm basin...")

    maskspacing=1.0
    tcMask = mask_tc(0,-999,-999,maskspacing,360)

    orilat=tsub(0,2)
    orilon=tsub(0,1)
    if (orilon .gt. 360.0-maskspacing) then
      orilon=360.0-maskspacing
      print("    original lon: "+tsub(0,1)+"   modified lon: "+orilon)
    end if

    if (tcMask({orilat},{orilon}) .ne. basin) then
      print("     "+tcMask({orilat},{orilon})+" != "+basin+"... Not relevant basin... skipping storm")
      print(" ")
      delete([/tsub,nrows,maskspacing,tcMask,orilat,orilon/])
      continue
    else if (tsub(nrows-1,2) .lt. 20.0) then
      print("      Storm dissipates... skipping storm")
      print(" ")
      delete([/tsub,nrows,maskspacing,tcMask/])
      continue
    end if
    end if

    print("     "+tcMask({orilat},{orilon})+" = "+basin+"... matching basin, tracking storm")
    print(" ")

    delete([/maskspacing,tcMask/])

  end if

  STARTTIME=stringtointeger(systemfunc("date -u +%s"))

  ;========================================================
  ; Find start time
  ;========================================================

if (do_debug) then
  PRINTSTRING="finding start time"
  print("Starting "+PRINTSTRING)
  wcStrtSub = systemfunc("date")
end if
  

  ; convert longitude (0 to 360) to (-180 to 180)
  tsub(:,1) = where(tsub(:,1) .gt. 180, tsub(:,1) - 360, tsub(:,1))
  
  ; convert start time to match data calendar format

  OPT=0
  OPT@calendar="gregorian"
  s_time = cd_inv_calendar(s_year(itc),s_month(itc),s_day(itc),s_hour(itc),0,0, \
                           "days since 1984-01-01 00:00:00",OPT)
  s_date = sprinti("%0.4i",s_year)+sprinti("%0.2i",s_month)+sprinti("%0.2i",s_day)



  ; allow 21 days past the end of TC phase
  e_time = s_time + (dur(itc)/4.) + 21
  e_time@units = s_time@units
  e_time@calendar = s_time@calendar

  ; convert time to date format for selecting files  
  end_date = cd_calendar(e_time,0)
  e_mon_str = sprinti("%0.2i",floattoint(end_date(0,1)))
  e_year = end_date(0,0)
  
  print("TC start time: "+cd_calendar(s_time,-3))
  ;print("TC end time: "+cd_calendar(,-3))
  print("Extended end time: "+cd_calendar(e_time,-3))
  
  delete(end_date)

if (do_debug) then
  print("...ending "+PRINTSTRING)
  wallClockElapseTime(wcStrtSub, PRINTSTRING, 0)
end if


  ;========================================================
  ; Load input files
  ;========================================================

if (do_debug) then
  PRINTSTRING="loading files into memory"
  print("Starting "+PRINTSTRING)
  wcStrtSub = systemfunc("date")
end if

  ; find previous month for selecting h2 files and convert to strings
  s_mon_prev = sprinti("%0.2i",s_month(itc)-1)
  s_mon_str = sprinti("%0.2i",s_month(itc))
  s_year_prev = s_year(itc)-1

  ; read in data, selecting only necessary months
  if (s_year(itc) .ne. e_year) then
    files1 = systemfunc("ls "+dir+"/"+ \
              fname1+s_year(itc)+"-{"+s_mon_str+"..12}*.nc "+ \
              dir+"/"+ \
              fname1+e_year+"-{01.."+e_mon_str+"}*.nc")
  else
    files1 = systemfunc("ls "+dir+"/"+ \
              fname1+s_year(itc)+"-"+"{"+s_mon_str+".."+e_mon_str+"}*.nc")
  end if
  
  delete([/e_year,e_mon_str,s_mon_prev,s_mon_str/])

if (do_debug) then
  print("...ending "+PRINTSTRING)
  wallClockElapseTime(wcStrtSub, PRINTSTRING, 0)
end if

  ;========================================================
  ; Load Z and interpolate to pressure levels
  ;========================================================

if (do_debug) then
  PRINTSTRING="load Z and interpolate to pressure levels"
  print("Starting "+PRINTSTRING)
  wcStrtSub = systemfunc("date")
end if

  ; new pressure levels  
	pnew = (/300.,350.,400.,450.,500.,550.,600., \
			 650.,700.,750.,800.,850.,900./)  
	logp = log(pnew*100.)   ; convert p from hPa to Pa and take log
	  
  ; assign indices to be used later
	indtop = 0      ; top index for VTU
	indmid = 6      ; bottom index for VTU, top index for B, VTL
	indbot = 12     ; bottom index for B, VTL

	; read in data for Z levels
	input1 = addfiles(files1,"r")
	ListSetType(input1,"cat")
	delete(files1)
   
	; read in data    
	Z3 = input1[:]->Z({s_time:e_time},:,{latmin:latmax},:)
	nlev = dimsizes(Z3&lev)
	Znew = Z3(:,0:nlev-2,:,:)
	
	; compute weights from latitudes  
	deg2rad = 4.0*atan(1.0)/180.0
	wgt = cos((Z3&lat)*deg2rad)
  delete([/Z3/])

  ; flip longitude for geopotential height 
	;Znew = lonFlip(Znew)
	Z = Znew(:,:,:,{lonmin-eps:lonmax}) 
	delete([/Znew/])

if (do_debug) then
  print("...ending "+PRINTSTRING)
  wallClockElapseTime(wcStrtSub, PRINTSTRING, 0)
end if


  ;========================================================
  ; Load data and calculate UMAG
  ;========================================================

if (do_debug) then
  PRINTSTRING="Load data and calculate UMAG"
  print("Starting "+PRINTSTRING)
  wcStrtSub = systemfunc("date")
end if

	; load wind speeds at lowermost model level
	UBOT_in = input1[:]->UBOT({s_time:e_time},{latmin:latmax},:)
	VBOT_in = input1[:]->UBOT({s_time:e_time},{latmin:latmax},:)

  ; flip longitude
	;UBOT_in = lonFlip(UBOT_in)
	;VBOT_in = lonFlip(VBOT_in)
	UBOT = UBOT_in(:,:,{lonmin-eps:lonmax})
	VBOT = VBOT_in(:,:,{lonmin-eps:lonmax})
	delete([/UBOT_in,VBOT_in/])  

  UBOTMAG = ((VBOT^2 + UBOT^2)^(0.5))

  copy_VarMeta(UBOT,UBOTMAG)

	delete([/UBOT,VBOT/])

if (do_debug) then
  print("...ending "+PRINTSTRING)
  wallClockElapseTime(wcStrtSub, PRINTSTRING, 0)
end if
  

          
  ;========================================================
  ; Load data and preallocate some arrays
  ;========================================================

if (do_debug) then
  PRINTSTRING="Load data and preallocate some arrays"
  print("Starting "+PRINTSTRING)
  wcStrtSub = systemfunc("date")
end if

  ; time and lat/lon arrays
  time = input1[:]->time({s_time:e_time})
  ; because lat/lon may be double and we want float, but NCL doesn't persist meta when
  ; type converting, we load temp arrays, convert to float, and copy meta, release tmp arrays
  lat_in = input1[0]->lat({latmin:latmax})
  lon_in = input1[0]->lon({lonmin-eps:lonmax})
  lat = tofloat(lat_in)
  lon = tofloat(lon_in)
  copy_VarMeta(lat_in,lat)
  copy_VarMeta(lon_in,lon)
	delete([/lat_in,lon_in/])


	; flip longitude for sea level pressure  
	PSL_all = input1[:]->PSL({s_time:e_time},{latmin:latmax},:)
	;PSL_all = lonFlip(PSL_all)
	PSL_in = PSL_all(:,:,{lonmin-eps:lonmax})
    
  date = cd_calendar(input1[:]->time({s_time:e_time}),-2)
	delete([/PSL_all,input1,s_time,e_time/])

  ; convert Pa to hPa
  PSL = PSL_in/100.0
  copy_VarMeta(PSL_in,PSL)
  PSL@units = "hPa"
  delete(PSL_in)
    
  ; assign fill value for missing 
  PSL@_FillValue = 9.969209968386869e+36
  
  ; get Z thickness between 600 and 900 for B calculation
  Z_thick = Z(:,indmid,:,:) - Z(:,indbot,:,:)
  Z_thick!0 = "time"
  Z_thick!1 = "lat"
  Z_thick!2 = "lon"
  Z_thick&time = time
  Z_thick&lat = lat
  Z_thick&lon = lon

if (do_debug) then
  print("...ending "+PRINTSTRING)
  wallClockElapseTime(wcStrtSub, PRINTSTRING, 0)
end if



  ;========================================================
  ; Preallocate arrays
  ;======================================================== 

if (do_debug) then
  PRINTSTRING="Preallocate arrays"
  print("Starting "+PRINTSTRING)
  wcStrtSub = systemfunc("date")
end if

  ; record dimension sizes
  ntime = dimsizes(time)  ; time
  nlat = dimsizes(lat)    ; latitude
  nlon = dimsizes(lon)    ; longitude

  ; preallocate arrays for minimum pressure value and locations  
  minP    = new(ntime,float)   ; minimum pressure value (Pa)
  minPlat = new(ntime,float)   ; minimum pressure latitude
  minPlon = new(ntime,float)   ; minimum pressure longitude
  V       = new(ntime,float)   ; maximum wind speed at 10 m
  dist    = new(ntime,float)   ; distance traveled between each time step (m)
  ang     = new(ntime,float)   ; angle of storm travel
  d_ang   = new(ntime,float)   ; change in angle of storm travel
  B       = new(ntime,float)   ; B parameter (Hart 2003)
  Vlt     = new(ntime,float)   ; lower troposphere thermal wind (Hart 2003)
  Vut     = new(ntime,float)   ; upper troposphere thermal wind (Hart 2003)
  ang_all = new((/nlat,nlon/),float) ; angle of all values from storm center
 
if (do_debug) then
  print("...ending "+PRINTSTRING)
  wallClockElapseTime(wcStrtSub, PRINTSTRING, 0)
end if

  ;========================================================
  ; Compute values during TC tracker
  ;======================================================== 

  print("Tracking storm...")

  ; set values to trajectory
  minP(0:nrows-1) = tsub(:,4)      ; minimum pressure values
  minPlat(0:nrows-1) = tsub(:,2)   ; latitude of minimum pressure
  minPlon(0:nrows-1) = tsub(:,1)   ; longitude of minimum pressure
  V(0:nrows-1) = tsub(:,3)         ; max wind speed

  delete(tsub)

  ; compute distance traveled, speed of storm, and change in direction of motion
  ; for times already in TC trajectory
  do i = 1,nrows-1

if (do_debug) then
  print("doing row "+i)
  PRINTSTRING="early calcs"
  print("Starting "+PRINTSTRING)
  wcStrtSub = systemfunc("date")
end if

    dist(i) = gc_latlon(minPlat(i),minPlon(i),minPlat(i-1),minPlon(i-1),2,4)  ; km
    ang(i) = bearing(minPlat(i-1),minPlon(i-1),minPlat(i),minPlon(i))
    d_ang(i) = r2d*atan2(sin((ang(i-1)-ang(i))*d2r),cos((ang(i-1)-ang(i))*d2r))

if (do_debug) then
  print("...ending "+PRINTSTRING)
  wallClockElapseTime(wcStrtSub, PRINTSTRING, 0)
end if

;========================================================
; Find thickness of the right and left hand sides of storm
;========================================================

B(i) = calc_B(Z_thick(i,:,:),lat,lon,10.,critRad,dist(i),ang(i),minPlat(i),minPlon(i))

;========================================================
; Compute thermal wind values (Vlt and Vut)
;========================================================

rtn_tmp = calc_VltVut(Z(i,:,:,:),lat,lon,10.,critRad,dist(i),ang(i),minPlat(i),minPlon(i),logp)
Vlt(i) = rtn_tmp(0)
Vut(i) = rtn_tmp(1)

    ;========================================================
    ; Print various fields to screen
    ;========================================================
  
    if (i .eq. 1) then
      print("    Press.   Lat      Lon     dist    V      ang" + \
            "     d_ang      B     Vlt     Vut     TYPE")
    else
      print_ET_toScreen(minP(i),minPlat(i),minPlon(i),dist(i),V(i),ang(i),d_ang(i), \
        B(i),Vlt(i),Vut(i),"TC")

    end if


  ;delete([/qq_Z,qq_lat,qq_lon,qq_nlat,qq_nlon,qq_ang_all,qq_wgt,qq_ddeg/])

  end do   ; end loop of already TC tracked stuff

  delete(i)

  ;========================================================
  ; call function to create et plot
  ;========================================================

  plot_track = False
  if (plot_track) then  
    do i = 0, nrows-1
      et_track_plot(type,itc,i,lat,lon,date(i),minP(i),minPlat(i),minPlon(i), \
                    PSL(i,:,:),PSL(i,:,:))
    end do
    delete(i)
  end if

  ;========================================================
  ; Find great circle distances and pressure values within radius
  ;========================================================

  ; loop over all times after TC tracker ends
  do i = nrows,ntime-1

if (do_debug) then
  print("Starting time: "+i)
  wcStrt = systemfunc("date")
end if

    if (minPlat(i-1) .ge. (latmax-10.) .or. minPlon(i-1) .ge. (lonmax-10.) .or. \
           minPlat(i-1) .le. (latmin+10.) .or. minPlon(i-1) .le. (lonmin+10.)) then
      print("Done tracking storm since it exited our available domain...")
      break
    else  ; still tracking storm
      ; find distance from storm center to each grid point using great circle length
      PSL_tmp = PSL(i,:,:)
      UBOTMAG_tmp = UBOTMAG(i,:,:)

      ; ++CMZ
      ; rad_tmp = rad(ind(lat .eq. minPlat(i-1)))
      if ( minPlat(i-1) .lt. 20.0 ) then
        rad_tmp=300.
      else if ( minPlat(i-1) .ge. 45.0) then
        rad_tmp=700.
      else
        rad_tmp=500.
      end if
      end if
      ; --CMZ

if (do_debug) then
  print("Starting masking operation")
  wcStrtSub = systemfunc("date")
end if

      ;do jlat = 0,nlat-1
      ;do jlon = 0,nlon-1
      ;  d = gc_latlon(minPlat(i-1),minPlon(i-1),lat(jlat),lon(jlon),2,4)  ; km
      ;  if (d .gt. rad_tmp) then
      ;    PSL_tmp(jlat,jlon) = PSL_tmp@_FillValue  ; set points outside radius to missing
      ;    UBOTMAG_tmp(jlat,jlon) = UBOTMAG_tmp@_FillValue
      ;  end if
      ;end do
      ;end do
lat2d=conform_dims((/nlat,nlon/),lat,0)
lon2d=conform_dims((/nlat,nlon/),lon,1)
d = gc_latlon(minPlat(i-1),minPlon(i-1),lat2d,lon2d,2,4)  ; km
PSL_tmp=where(d.gt.rad_tmp,PSL_tmp@_FillValue,PSL_tmp)
UBOTMAG_tmp=where(d.gt.rad_tmp,UBOTMAG_tmp@_FillValue,UBOTMAG_tmp)
delete(d)
delete(lat2d)
delete(lon2d)

if (do_debug) then
  print("...ending masking operation")
  wallClockElapseTime(wcStrtSub, "masking", 0)
end if

      ; find max wind speed
      V_tmp = max(UBOTMAG_tmp)

      ;delete([/d,rad_tmp,jlat,jlon,UBOTMAG_tmp/])
      delete([/rad_tmp,UBOTMAG_tmp/])

      ;========================================================
      ; Find all local pressure minimums
      ;========================================================

      ; find location of pressure minimums
if (do_debug) then
  PRINTSTRING="pmin search"
  print("Starting "+PRINTSTRING)
  wcStrtSub = systemfunc("date")
end if

      locmin = local_min(PSL_tmp,False,0.0)
  
if (do_debug) then
  print("...ending "+PRINTSTRING)
  wallClockElapseTime(wcStrtSub, PRINTSTRING, 0)
end if

      ; if pressure minimums exist, choose the best one
      if (locmin(0) .gt. 0) then
        locmin_lat = lat(locmin@yi)    ; latitudes of local mins
        locmin_lon = lon(locmin@xi)    ; longitudes of local mins
        nmins = dimsizes(locmin_lat)   ; number of local mins

if (do_debug) then
  PRINTSTRING="plot local mins"
  print("Starting "+PRINTSTRING)
  wcStrtSub = systemfunc("date")
end if

        ; plot all local mins for debugging
        plot_test = False
        if (plot_test) then
          plot_track = False   ; don't overwrite with later plot of single point
          et_track_plot(type,itc,i,lat,lon,date(i),minP(i-1),locmin_lat,locmin_lon, \
                PSL_tmp,PSL(i,:,:))
        end if

if (do_debug) then
  print("...ending "+PRINTSTRING)
  wallClockElapseTime(wcStrtSub, PRINTSTRING, 0)
end if

        ;========================================================
        ; Test if each local min is a valid storm
        ;========================================================

        ; preallocate arrays	
        locmin_test = new(nmins,logical)  ; test if local min is valid
        minP_tmp = new(nmins,float)       ; minimum pressure value
        dist_tmp = new(nmins,float)       ; distance traveled (km)
        ang_tmp = new(nmins,float)        ; storm bearing (degrees)
        d_ang_tmp = new(nmins,float)      ; change in bearing (degrees)
  
if (do_debug) then
  PRINTSTRING="pmin testing"
  print("Starting "+PRINTSTRING)
  wcStrtSub = systemfunc("date")
end if
  
        ; loop over all local minimums
        do jmin = 0,nmins-1
           minP_tmp(jmin) = PSL(i,{locmin_lat(jmin)},{locmin_lon(jmin)})
           dist_tmp(jmin) = gc_latlon(minPlat(i-1),minPlon(i-1), \
                     locmin_lat(jmin),locmin_lon(jmin),2,4) ; km
           ang_tmp(jmin) = bearing(minPlat(i-1),minPlon(i-1), \
                       locmin_lat(jmin),locmin_lon(jmin))
           d_ang_tmp(jmin) = r2d*atan2(sin((ang(i-1)-ang_tmp(jmin))*d2r), \
                         cos((ang(i-1)-ang_tmp(jmin))*d2r))

           locmin_test(jmin) = et_track_checks(latmax,lonmax, \
                               minP_tmp(jmin),locmin_lat(jmin),locmin_lon(jmin), \
                     dist_tmp(jmin),d_ang_tmp(jmin))
        end do
  
if (do_debug) then
  print("...ending "+PRINTSTRING)
  wallClockElapseTime(wcStrtSub, PRINTSTRING, 0)
end if

        delete(jmin)
  
        locmin_true = ind(locmin_test)   ; gather indices where storm is valid


  


        ;========================================================
        ; Choose best storm (valid + lowest pressure)
        ;========================================================
if (do_debug) then
  PRINTSTRING="best storm choice"
  print("Starting "+PRINTSTRING)
  wcStrtSub = systemfunc("date")
end if

        if (.not. all(ismissing(locmin_true))) then
          minPind = ind(minP_tmp .eq. min(minP_tmp(locmin_true)))  ; choose lowest pressure

          ; loop to check if two valid points within the search area
          ; have the exact same minimum pressure (yes, this actually happens)
          ; choose minimum pressure with travel distance/speed most similar to previous time step
          if (dimsizes(minPind) .gt. 1) then
            dist_diff = abs(dist(i-1) - dist_tmp)
            minPindTmp=-1
            minDiffTmp=99999.9
            do ii = 0,dimsizes(minPind)-1
              print(dist_diff(minPind(ii))+" "+minDiffTmp)
              if (dist_diff(minPind(ii)) .lt. minDiffTmp) then
                minDiffTmp=dist_diff(minPind(ii))
                print("updating minPindTmp from "+minPindTmp+" "+minPind(ii))
                minPindTmp=minPind(ii)
              end if
            end do
            delete([/minDiffTmp,dist_diff,ii,minPind/])
            minPind=minPindTmp
            delete(minPindTmp)
          end if
  
          minPlat(i) = (/locmin_lat(minPind)/)   ; latitude of minimum pressure
          minPlon(i) = (/locmin_lon(minPind)/)   ; longitude of minimum pressure
          minP(i) = minP_tmp(minPind)            ; minimum pressure value
    
          dist(i) = dist_tmp(minPind)     ; distance traveled by storm (km)
          V(i) = V_tmp                    ; max wind speed
          ang(i) = ang_tmp(minPind)       ; storm bearing
          d_ang(i) = d_ang_tmp(minPind)   ; change in storm direction
    
          delete(minPind)
        else ; stop tracking if no local min satisfies all tests
          delete([/PSL_tmp,locmin,locmin_lat,locmin_lon,nmins/])
          delete([/locmin_test,minP_tmp,dist_tmp,V_tmp,ang_tmp,d_ang_tmp,locmin_true/])
          break
        end if
  
        delete([/locmin,locmin_lat,locmin_lon,nmins/])
        delete([/locmin_test,minP_tmp,dist_tmp,V_tmp,ang_tmp,d_ang_tmp,locmin_true/])
    
      else  ; stop tracking if no local min exists
        delete([/PSL_tmp,locmin/])
        break
      end if
if (do_debug) then
  print("...ending "+PRINTSTRING)
  wallClockElapseTime(wcStrtSub, PRINTSTRING, 0)
end if

;========================================================
; Find thickness of the right and left hand sides of storm
;========================================================

B(i) = calc_B(Z_thick(i,:,:),lat,lon,10.,critRad,dist(i),ang(i),minPlat(i),minPlon(i))

;========================================================
; Compute thermal wind values (Vlt and Vut)
;========================================================

rtn_tmp = calc_VltVut(Z(i,:,:,:),lat,lon,10.,critRad,dist(i),ang(i),minPlat(i),minPlon(i),logp)
Vlt(i) = rtn_tmp(0)
Vut(i) = rtn_tmp(1)

      ;========================================================
      ; Print various fields to screen
      ;========================================================
 
print_ET_toScreen(minP(i),minPlat(i),minPlon(i),dist(i),V(i),ang(i),d_ang(i),B(i),Vlt(i),Vut(i),"ETC")

      ;========================================================
      ; Plot storm
      ;========================================================

      ; call function to create et plot
      if (plot_track) then
        et_track_plot(type,itc,i,lat,lon,date(i), \
                      minP(i),minPlat(i),minPlon(i),PSL_tmp,PSL(i,:,:))
      end if
  
      delete(PSL_tmp)

    end if ; check to see if storm is still in domain
  end do   ;loop over all times after TC tracker ends

  delete([/PSL,ang_all,Z,Z_thick,UBOTMAG,wgt,lat,lon,nlat,nlon,ntime,nrows/])

  print("Finished tracking storm.")
  print(" ")

  ; if plotting track, combine pdfs into gif
  if (plot_track .or. plot_test) then
    system("mkdir gifs")
    system("rm -f ./gifs/track_plot_"+type+"_"+sprinti("%0.3i",itc)+".gif")
    system("convert -delay 50 -loop 0 -density 300 ./gifs/track_plot_"+type+"_"+ \
           sprinti("%0.3i",itc)+"_*.pdf ./gifs/track_plot_"+type+"_"+ \
           sprinti("%0.3i",itc)+".gif")
    system("rm -f ./gifs/track_plot_"+type+"_"+sprinti("%0.3i",itc)+"_*.pdf")
  end if

  ;========================================================
  ; Plot phase space diagram
  ;========================================================

if (do_debug) then
  PRINTSTRING="phase plotting"
  print("Starting "+PRINTSTRING)
  wcStrtSub = systemfunc("date")
end if

  plot_phase = True
  if (plot_phase) then
    system("mkdir phase_plots")
    system("rm -f ./phase_plots/phase_plot_"+type+"_"+itc+".pdf") ; remove existing pdf
    et_phase_plot(type,itc,date(0:i-1),B,Vlt,Vut)     ; plot phase space diagram
  end if

if (do_debug) then
  print("...ending "+PRINTSTRING)
  wallClockElapseTime(wcStrtSub, PRINTSTRING, 0)
end if

  delete([/date/])
  
  ;========================================================
  ; Write output to text file
  ;========================================================

  print("Writing to trajectory ascii file...")

  system("mkdir text_files")

  ; remove text file if it already exists
  system("rm -f ./text_files/tmp_"+type+"_"+sprinti("%0.3i",itc)+".txt")

  ; write header line for storm
  write_table("./text_files/tmp_"+type+"_"+sprinti("%0.3i",itc)+".txt","w", \
              [/"start",i,s_year(itc),s_month(itc),s_day(itc),s_hour(itc),itc/], \
              "%s   %03i  %04i      %02i    %02i    %02i    %03i")

  ; reformat missing values to avoid terrible formatting in ascii file
  dist(0) = -999
  ang(0)  = -999
  B(0)    = -999
  Vlt(0)  = -999
  Vut(0)  = -999

  st_date = cd_calendar(time(0:i-1),0)  ; get date at each time step

  ; write storm data to ascii file (append to header)   
  write_table("./text_files/tmp_"+type+"_"+sprinti("%0.3i",itc)+".txt","a", \
    [/minPlon(0:i-1),minPlat(0:i-1),minP(0:i-1), \
    V(0:i-1),dist(0:i-1),ang(0:i-1), \
    B(0:i-1),Vlt(0:i-1),Vut(0:i-1), \
    st_date(:,0),st_date(:,1),st_date(:,2),st_date(:,3)/], \
    "   %6.2f   %5.2f   %7.2f" + \
    "   %4.1f   %7.2f   %7.2f" + \
    "   %7.2f   %7.2f   %7.2f" + \
    "   %4.0f  %2.0f  %2.0f  %2.0f")

  ENDTIME=stringtointeger(systemfunc("date -u +%s"))
  TOTTIME=ENDTIME-STARTTIME
  asciiwrite ("./text_files/timing_"+type+"_"+sprinti("%0.3i",itc)+".TIME",TOTTIME)
  
  delete([/i,itc,time,st_date,minPlon,minPlat,minP,V,dist,ang,d_ang,B,Vlt,Vut/])

  print("Done with storm.")
  print(" ")

end do ; end storm loop
  
end