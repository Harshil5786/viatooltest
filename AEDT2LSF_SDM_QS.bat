::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::Mike Brickey
::Submits ANSYS AEDT (HFSS) sweep jobs to the LSF cluster.
::Initial version ~2008
::
::9/18/2017 v1.1 -  Added auto grab adaptive jobid and use as dependency for sweep job.
::                  Added Allowoffcore=0 for HFSS designs
::                  Added -waitforlicense
::11/30/2017 1.2 -  Added .lock file check
::12/15/2017 1.3 -  Added Allowoffcore=0 for HFSS 3D Layout Design
::01/03/2018 1.4 -  Added check for submit from local disk.
::04/03/2018 1.5 -  Ported to LSF 10.1.
::				    Added support for HFSS_EXEC env to use spaces in the path.
::				    Will not work on LSF 8 cluster due to new features not available on LSF 8.
::08/08/2018 1.6 -  Added MPI_USELSF=0 to resolve errant default setting in v19.x causing tasks not to distribute.
::10/18/2018 1.7 -  Added block scheduling for distributed jobs enabling better slot distribution.
::				    Removed SWAP reservation as it's no longer needed.
::02/19/2019 1.8 -  Added AEDT 19R1/19.3 support.
::                  Removed all versions prior to 19.x due to hfsshpc license feature removal.
::03/15/2019 1.81 - Added support for anshpc license feature. Removed hfsshpc license dependency. 
::05/07/2019 1.81 - Removed version 19.0 because Ansys did not include the 19.0 version in the last set of HPC MPI patches.
::06/12/2019 1.83 - Enabled LSF MPI Tight Integration
::                  Removed LSF 10.1 path check to facilitate submitting from SLAC clients.
::07/15/2019 1.84 - Added support for 2019 R2\19.4
::05/04/2020 1.85 - Added support for 2020 R1\20.1
::                  Removed tmp disk reservation setting due to misuse.
::                  Added check for submitting from local d:\ drive
::04/05/2021 1.88 - Added support for 2020 R2\20.2
::                  Added support for 2021 R1\21.1
::					Added support for Intel MPI for 2020 R2 and later
::                  Added new -batchoptions
::                  Added new EM Suite MPI timeout.
::                  Increased default sweep cores to 4 and memory reservation to 40G.
::					Added resource reservation estimates based on model memory requirements.			
::09/10/2021 1.89 -	Added support for 2021 R2.
::					Added automatic orphaned sweep job termination.
::					Added if defined project doesn't exist, print error and exit job submit.
::					Added ANSYSEM_ROOT212 env needed for v21.2 and up to define version path on exec host.
::04/04/2022 1.89.1 - Removed EOL'd AEDT versions
::
::05/10/2022 1.89.2 - Added support for version 2022 R1\221
::					  Added disk free check before job submit. Will warn is <15GB available
::					  Removed AEDT version check as no longer needed since older versions were removed.
::
::09/30/2022 1.89.3 - Added support for version 2022 R2\222
::					  Added 15% over memory limit for adaptive jobs. Jobs will be killed if use 115% of requested memory.
::
::11/06/2023 1.89.4 - Added support for version 2023 R1\231
::					  Added support for version 2023 R2\232
::					  Added support for Intel MPI v2021
::					  Added check for submitting from a UNC path. Bail out if UNC path detected
::					  Validated 180 task limit bug resolved on v23.1 and Intel MPI v2021
::
::01/16/2024 1.89.5 - Added support for new "HFSS 3D Layout Design/MPIVersion=2021" and "HFSS 3D Layout Design/MPIVendor=intel" required for v2023.x
::
::04/16/2024 1.89.6 - Added support for 2024 R1\241
::					  Removed support for 2021 R2\212
::
::08/20/2024 1.89.7 - Added support for 2024 R2\242
::					  Removed support for 2022 R1\221
::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

@ECHO OFF
SET VER=1.89.7 08/20/2024

:: Enter the AEDT file name without the .aedt extension below.
:: DO NOT OPEN THE PROJECT WHILE THE JOB IS RUNNING. The AEDT project file will corrupt and the job will hang. 
SET PROJECT=Project53

::SWEEP_CORES = The # of CPU cores\threads EACH solver will use during the sweep.
::Optimal is 4 if the memory requirement is <57GB memory.
::Optimal is 8 if the the memory requirement is 58GB-120GB memory.
::Optimal is 14 if the the memory requirement is >120GB memory.
SET SWEEP_CORES=4

::SOLVERS = Total number of concurrent solvers ran across all hosts.
::Do not specify more solvers than you have frequency points.
::***Do not specify more than 180 total cores, (solvers * sweep_cores) when using v2022 r2 and lower***
::Models needing <57GB memory, recommend up to 28 SOLVERS and 4 SWEEP_CORES.
::Models needing 58GB-500GB memory, recommend 18-22 SOLVERS and 6 or 8 SWEEP_CORES.
::Models needing 501GB-1TB memory, recommend 10-12 SOLVERS and 14 SWEEP_CORES.
::Note, the more cores you request the longer job dispatch can take.
SET SOLVERS=15

::ADAPTIVE_CORES = # of CPU cores to use during the adaptive solve performed on 1 machine. Testing shows solvers scaling to ~24 cores in latest EM Suite versions. 24 is the maximum.
::Note, the more cores you request the longer dispatch can take. There are many more 6-8 core <120GB mem servers than 24 core.
::Optimal is 4 if the memory requirement is <58GB memory.
::Optimal is 8 if the the memory requirement is <120GB memory.
::Optimal is 16-24 if the the memory requirement is >120GB memory.
SET ADAPTIVE_CORES=8

::Below values are in GIGABYTES
::Memory is reserved on a per solver basis. The higher you set the reservation the less solvers you may be able to run concurrently due to competition for resources.
::If you don't know how much memory your simulation will need, open the project in HFSS\AEDT, unselect the sweep and solve the adaptive interactively. Observe how much memory the adaptive solve
::uses either by looking at the "profile" after the simulation completes or observe memory usage in task manager. Use this max memory used amount when specifying your memory reservation below.
::Below values are in GIGABYTES
SET MEMORY=40

:: Version root path. Needed starting with v2021 r2
:: DO NOT MODIFY
SET ANSYSEM_ROOT242=C:\Program Files\AnsysEM\v242\Win64
SET ANSYSEM_ROOT241=C:\Program Files\AnsysEM\v241\Win64
SET ANSYSEM_ROOT232=C:\Program Files\AnsysEM\v232\Win64
SET ANSYSEM_ROOT231=C:\Program Files\AnsysEM\v231\Win64
SET ANSYSEM_ROOT222=C:\Program Files\AnsysEM\v222\Win64
:: DO NOT MODIFY


::
:: Select your desired version by uncommenting (::) the SET HFSS_EXEC= line. Make sure you comment (::) the versions you don't want to use.
::EM Suite 2024 R2/242
SET HFSS_EXEC="%ANSYSEM_ROOT242%\ansysedt.exe"

::EM Suite 2024 R1/241
::SET HFSS_EXEC="%ANSYSEM_ROOT241%\ansysedt.exe"

::EM Suite 2023 R2/232
::SET HFSS_EXEC="%ANSYSEM_ROOT232%\ansysedt.exe"

::EM Suite 2023 R1/231
::SET HFSS_EXEC="%ANSYSEM_ROOT231%\ansysedt.exe"

::EM Suite 2022 R2/222
::SET HFSS_EXEC="%ANSYSEM_ROOT222%\ansysedt.exe"







::##################################
::###                            ###
::## DO NOT EDIT BELOW THIS LINE  ##
::###                            ###
::##################################

SET /A MEMORY_ADAPTIVE=%MEMORY% * 1024 / %ADAPTIVE_CORES%
SET /A MEMORY_SWEEP=%MEMORY% * 1024 / %SWEEP_CORES%
SET /A TOTAL_CORES=%SWEEP_CORES% * %SOLVERS%
SET /A ALL_MEMORY=%SOLVERS% * %MEMORY%
SET /A MEMORY_LIMIT=%MEMORY% * 1024
for /f "delims=" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -Command [math]::Round^(%MEMORY_LIMIT%*1.15^)') do set MEMORY_LIMIT=%%a
SET /A MEMORY_LIMITGB=%MEMORY_LIMIT% / 1024


::Check if defined PROJECT file exists
IF NOT EXIST "%PROJECT%.aedt" (
	ECHO *************  E R R O R  *************
    ECHO ***************************************
	ECHO The project file name ^"%PROJECT%^" specfied in %0 does not exist.
	ECHO Update %0 with the correct project file name and run again.
	TIMEOUT /t -1
    EXIT /b 
)

::Check if submitting from a local disk
IF /i "%~d0" == "c:" (
    ECHO *************  E R R O R  *************
    ECHO ***************************************
    ECHO Job submission from local C:\ drive detected!
    ECHO You must submit LSF jobs from a mapped
    ECHO network drive and not c:\.
    ECHO Move %PROJECT%.aedt to a mapped network drive
    ECHO and submit the job from there.
    ECHO ***************************************
    TIMEOUT /t -1
    EXIT /b 
)

IF /i "%~d0" == "d:" (
    ECHO *************  E R R O R  *************
    ECHO ***************************************
    ECHO Job submission from local D:\ drive detected!
    ECHO You must submit LSF jobs from a mapped
    ECHO network drive and not D:\.
    ECHO Move %PROJECT%.aedt to a mapped network drive
    ECHO and submit the job from there.
    ECHO ***************************************
    TIMEOUT /t -1
    EXIT /b 
)

:: Check if submitting from a UNC path
IF /i "%~d0" == "\\" (
    ECHO *************  E R R O R  *************
    ECHO ***************************************
    ECHO Job submission from UNC path detected!
    ECHO You must submit LSF jobs from a mapped
    ECHO network drive and not a UNC path, \\.
    ECHO Map a drive to your project file share
	ECHO and submit the job from there.
	ECHO UNC path: %~dp0
    ECHO ***************************************
    TIMEOUT /t -1
    EXIT /b 
)

::Check for lock file, exit out if found.
IF EXIST %PROJECT%.aedt.lock (
    ECHO *************  E R R O R  *************
    ECHO %PROJECT%.AEDT.LOCK FILE DETECTED
	ECHO ***************************************
	ECHO.
    ECHO The presence of the lock file indicates the project is open for editing.
    ECHO Close the open %PROJECT% project to release the project lock.
    ECHO If the simulation crashed earlier, manually delete the %PROJECT%.aedt.lock file.
    ECHO If you delete the file but the project is still open the job will hang and the project may be corrupted.
	ECHO Resubmit the job after closing the project or manually deleting the .lock file.
    ECHO *************  E R R O R  *************
    TIMEOUT /t -1
    EXIT /b
)

IF NOT EXIST .\lsflogs MD lsflogs
DEL %PROJECT%_Adaptive_batchlog.log 2> NUL
DEL %PROJECT%_Sweep_batchlog.log 2> NUL
DEL %PROJECT%_Adaptive_batchlog.solinfo 2> NUL
DEL %PROJECT%_Sweep_batchlog.solinfo 2> NUL
DEL %PROJECT%.aedt.q.completed 2> NUL
TYPE \\amr.corp.intel.com\ec\proj\pst\jf\software\utilities\scripts\lsf\aedtlogo.txt

::Get free disk space, throw warning if low space
dir /-c . |findstr /c:"bytes free" >freespace.txt
FOR /f "tokens=3 delims= " %%a IN (freespace.txt) DO SET FREESPACE=%%a
del freespace.txt
SET /A FREESPACE=%FREESPACE:~0,-6% / (1074)
IF %FREESPACE% LEQ 15 (
	ECHO.
	ECHO *************  W A R N I N G  *************
	ECHO  LOW DISK SPACE DETECTED - %FREESPACE%GB AVAILABLE
	ECHO *******************************************
	timeout /t 5
)

::Enable Tight Integration
SET MPI_USELSF=Y

::EM Suite MPI communication timeout, in seconds
SET MPI_TIME_OUT_SECONDS=180

ECHO.
ECHO **********************************
ECHO * Submitting %PROJECT% for HPC processing on LSF cluster
ECHO * Requesting %ADAPTIVE_CORES% processor cores for the Adaptive solve 
ECHO * Requesting %TOTAL_CORES% processor cores for the Sweep
ECHO * Requesting %SOLVERS% HPC solvers
ECHO * Each sweep solver will use %SWEEP_CORES% core(s)
ECHO * %TOTAL_CORES% HPC licenses will be used
ECHO * Reserving %MEMORY% GB of memory for each solver
ECHO * Memory usage limit is %MEMORY_LIMITGB% GB
ECHO * Reserving %ALL_MEMORY% GB of total memory
ECHO * Available network disk space %FREESPACE%GB
ECHO * Submit script version: %VER%
ECHO **********************************
ECHO.


::Create batch Options file
SET BATCH_OPTIONS_FILE_ADAPTIVE=%PROJECT%_batch_options_adaptive.txt
SET BATCH_OPTIONS_FILE_SWEEP=%PROJECT%_batch_options_sweep.txt
DEL %BATCH_OPTIONS_FILE_ADAPTIVE% 2> NUL
DEL %BATCH_OPTIONS_FILE_SWEEP% 2> NUL

::Adaptive
ECHO $begin 'Config' >%BATCH_OPTIONS_FILE_ADAPTIVE%
ECHO 'HFSS/NumCoresPerDistributedTask'=%ADAPTIVE_CORES% >>%BATCH_OPTIONS_FILE_ADAPTIVE%
ECHO 'HFSS/SolveAdaptiveOnly'=1 >>%BATCH_OPTIONS_FILE_ADAPTIVE%
ECHO 'HFSS 3D Layout Design/SolveAdaptiveOnly'=1 >>%BATCH_OPTIONS_FILE_ADAPTIVE%
ECHO 'HFSS-IE/NumCoresPerDistributedTask'=%ADAPTIVE_CORES% >>%BATCH_OPTIONS_FILE_ADAPTIVE%
ECHO 'HFSS-IE/HPCLicenseType'=pool >>%BATCH_OPTIONS_FILE_ADAPTIVE%
ECHO 'HPCLicenseType'=pool >>%BATCH_OPTIONS_FILE_ADAPTIVE%
ECHO 'HFSS/AllowOffCore'=0 >>%BATCH_OPTIONS_FILE_ADAPTIVE%
ECHO 'HFSS 3D Layout Design/AllowOffCore'=0 >>%BATCH_OPTIONS_FILE_ADAPTIVE%
ECHO $end 'Config' >>%BATCH_OPTIONS_FILE_ADAPTIVE%

::Sweep
ECHO $begin 'Config' >%BATCH_OPTIONS_FILE_SWEEP%
ECHO 'HFSS/NumCoresPerDistributedTask'=%SWEEP_CORES% >>%BATCH_OPTIONS_FILE_SWEEP%
ECHO 'HFSS/SolveAdaptiveOnly'=0 >>%BATCH_OPTIONS_FILE_SWEEP%
ECHO 'HFSS 3D Layout Design/SolveAdaptiveOnly'=0 >>%BATCH_OPTIONS_FILE_SWEEP%
ECHO 'HFSS/MPIVersion'='2021' >>%BATCH_OPTIONS_FILE_SWEEP%
ECHO 'HFSS/MPIVendor'=intel >>%BATCH_OPTIONS_FILE_SWEEP%
ECHO 'HFSS 3D Layout Design/MPIVersion'='2021' >>%BATCH_OPTIONS_FILE_SWEEP%
ECHO 'HFSS 3D Layout Design/MPIVendor'=intel >>%BATCH_OPTIONS_FILE_SWEEP%
ECHO 'HPCLicenseType'=pool >>%BATCH_OPTIONS_FILE_SWEEP%
ECHO 'HFSS/AllowOffCore'=0 >>%BATCH_OPTIONS_FILE_SWEEP%
ECHO 'HFSS 3D Layout Design/AllowOffCore'=0 >>%BATCH_OPTIONS_FILE_SWEEP%
ECHO $end 'Config' >>%BATCH_OPTIONS_FILE_SWEEP%

SET ANSYSEM_ENV_VARS_TO_PASS=MPIRUN_*;I_MPI_*;ANSOFT_*;ANS_*;ANSYSEM_*;FI_*
SET I_MPI_HYDRA_BRANCH_COUNT=0
SET FI_PROVIDER=tcp
SET ANSYS_HFSS_DISABLE_GPU=1

:: EM suite 19 includes 4 hfsshpc licenses.
::SET HFSS_SOLVE_LIC=%ADAPTIVE_CORES% - 4

SET SUBMIT_ADAPTIVE=bsub -n %ADAPTIVE_CORES% -J %PROJECT%_Adaptive -q hfss -app hfss -o "lsflogs\%PROJECT%_AEDT_Adaptive_stdout.%%J.log" -M %MEMORY_LIMIT% -R "span[hosts=1] select[defined(fastest)] rusage[mem=%MEMORY_ADAPTIVE%,anshpc=%ADAPTIVE_CORES%:duration=20s]" %HFSS_EXEC% -distributed includetypes"="default maxlevels"="1 -machinelist num"="1 -monitor -ng -waitforlicense -batchoptions "%BATCH_OPTIONS_FILE_ADAPTIVE%" -batchsolve -LogFile "%PROJECT%_Adaptive_batchlog.log" "%PROJECT%.aedt"
ECHO Submitting Adaptive job. . . 
FOR /f "tokens=2 delims=<>" %%a IN ('%SUBMIT_ADAPTIVE%') DO SET ADAPTIVE_JOBID=%%a
ECHO Job %ADAPTIVE_JOBID% is submitted to queue ^<hfss^>.

:: Debug log settings. 
:: Make sure you create the log dir path, AEDT won't auto create it.
::SET ANSOFT_DEBUG_LOG=\\amr.corp.intel.com\ec\proj\pst\jf\jf627\lsf_test\10.1\hfss\2021R1-testing\debug_logs\debug
::SET ANSOFT_DEBUG_LOG=c:\temp\debug_logs\debug
::SET ANSOFT_DEBUG_LOG_SEPARATE=1
::SET ANSOFT_DEBUG_LOG_THREAD_ID=1
::SET ANSOFT_DEBUG_LOG_TIMESTAMP=1
::SET ANSOFT_DEBUG_MODE=2
::SET ANSOFT_PASS_DEBUG_ENV_TO_REMOTE_ENGINES=1

::SET ANSYSEM_ENV_VARS_TO_PASS=MPIRUN_*;MPI_*;ANSOFT_*;ANS_*;ANSYSEM_*
::SET ANSYSEM_ENV_VARS_TO_PASS=MPIRUN_*;I_MPI_*;ANSOFT_*;ANS_*;ANSYSEM_*;FI_*

:: Intel MPI debug logging
::set I_MPI_DEBUG=10
::set I_MPI_HYDRA_DEBUG=1
::set FI_LOG_LEVEL=debug
::set I_MPI_DEBUG_OUTPUT=intel_mpi_debug.log

ECHO.
ECHO Submitting Sweep job. . .
bsub -n %TOTAL_CORES% -J %PROJECT%_Sweep -q hfss-hpc -app hfss-hpc -o "lsflogs\%PROJECT%_AEDT_Sweep_stdout.%%J.log" -w 'done(%ADAPTIVE_JOBID%)' -ti -R "select[defined(fastest)] span[block=%SWEEP_CORES%] rusage[mem=%MEMORY_SWEEP%,anshpc=1:duration=20s]" %HFSS_EXEC% -distributed includetypes=default maxlevels=1 -machinelist num=%SOLVERS% -monitor -ng -waitforlicense -batchoptions "%BATCH_OPTIONS_FILE_SWEEP%" -batchsolve -LogFile "%PROJECT%_Sweep_batchlog.log" "%PROJECT%.aedt"

ECHO.
ECHO You may use the 'bjobs -l jobid' and 'bpeek jobid' commands at the cmd prompt to view job status.
ECHO You may view job status from any system connected to Intel at http://goto.intel.com/slac
ECHO For more information on monitoring ANSYS EM jobs visit https://wiki.ith.intel.com/display/plattech/Monitoring+AEDT+jobs
ECHO Get the latest version of this script at https://wiki.ith.intel.com/display/plattech/LSF#LSF-AEDT
timeout /t 15
