# seed-analysis

Abstracted system for doing seed-based correlation analysis with any given set of groups and covariates. Uses AFNI `3dttest++`.

## How to setup this pipeline for any project.

Below is a general guide to setting up this pipeline for any project. We assume that you will clone this repository and, in that directory, follow these instructions.

### 1. Create list of seeds

The makefile requires that the list of seeds and their locations be read in from a file. That file must be named `allseeds.txt` and have the project seed directory, and all the seeds used in the project listed in a single column like so:

    
    /mnt/praxic/pdnetworksr01/lib/SVC_seeds/
    DANRaIPS
    DANLpIPS
    DANRFEF
    DANLFEF
	...

The makefile reads from the directory listed in the first line and looks for the seeds on the `n>1` lines. These seeds can have any notes following the seed name in the file name, but must have an `.nii.gz` extension. For example, `DANRaIPS_sphereroi.nii.gz` is acceptable, but `ROI_DANRaIPS.nii` wouldn't be. 

**Important**: All seeds must be generated for all subjects (see next section). If they aren't, the t-test for any seed where one or more subjects is missing the file will fail. 


### 2. Create `group-*.txt` group files

The makefile identifies groups by looking for files that match the regex `group-[[:alpha:]]*.txt`. For example, these files would create the groups "control" and "patient."

	group-control.txt
	group-patient.txt
	Makefile
	
Please ensure that there are no other files matching this pattern in the working directory. Do not use "`-`" within group names (i.e., within "control" or "patient", because a hyphen is used by the macros to indicate contrasts. 

Group files must contain lines the following format:

	140593 /mnt/praxic/pdnetworksr01/subjects/140593/session1/mcvsa/SVC_MEICA/
	140605 /mnt/praxic/pdnetworksr01/subjects/140605/session1/mcvsa/SVC_MEICA/

Each line consists of a subject identifier, followed by a space, then followed by the absolute path to the seed-based connectivity maps for that subject. It is important to label each subject because the syntax of `3dttest++` requires each map to be labeled with a subject identifier. 

For info on the `[[:alpha:]]` syntax, see [this page](https://www.regular-expressions.info/posixbrackets.html). It is equivalent to `[a-zA-Z]`.

**Important**: All of these directories must contain all of the required files. `3dttest++` will choke if it is given a non-existent file, and will not continue without it. I suggest you create a script to manage the creation of these files based on the existence of the map directories. 

### 3. Set variables

The first fifty or so lines of the makefileset a number of variables for `make` execution. There are three kinds of variables in the makefile:

---

**`ALL_CAPS`: These variables need to be set on a per-projecct basis**

1. `PROJECT_DIR`: The top-level directory for your project (in IBIC standard convention, this contains `bin/`, `subjects/`, etc.)
4. `STANDARD_MASK`: The MNI-space mask used in `3dttest++`. Using a mask reduces the number of comparisons and speeds up processing. Make sure the resolution (`Xmm`) matches the space your files are registered to. **Default:** 2mm
5. `SVCSUFFIX`: Depending on how `meica` was set up, the maps aren't necessarily given consistent names. Set this to whatever your project chose as the output. We're looking for the Z-transformed correlation map.
6. `COVFILE`: The covariates file (see section `XXX`) to read from. Leave blank if there are no covariates.

---

**`PascalCase`: These variables have set defaults but can be overriden on the command line.**

To override the default value of these variables, simply set a new value for them on the command line, like so:

    make SINGLEGROUP_PD ANALYSIS=-ETAC`
    
1. `Analysis`: Which type of `3dttest++` test to use. Available options are `ETAC` or `Clustsim`. Note that the number of cores can be specified as an argument to these flags, or left off to use all available cores. **Important:** The leading dash must be included. 
2. `Paired`: By default, an unpaired t-test is executed. To do a paired t-test, changed the value of `Paired` to anything other than the empty string. `3dttest++` will fail if your subject lists aren't properly paired.

`COVFILE`, like any other variable, can also be modified from the command line, but I'm leaving it in as a permanent variable because all covariates must be in that one file (see section 5).

---

**`lowercase`: These variables are automatically created variables.** 

In general, they shouldn't be overwritten, especially the variables in *italics*.

1. `seedsdir`: This variable is read in from the first lne of `allseeds.txt` and contains all the ROIs used in later analyses.
2. `allseeds`: By default, all the seeds are read in from the file `allseeds` (see section 1). This can be overriden here if you have another method to identify the names of the seeds.
3. `groups`: This pulls the group names out of the `group-*.txt` files (see section 2). Don't override this setting, as later recipes assume the existence of the same `group-*.txt` files.
4. *`contrasts`: This variable automatically creates all the contrasts based on the given group, and filters out any 0 contrasts (A - A). Don't change this declaration! There should be N(N-1) total contrasts* 
7. *`covariate`: This variable is set automatically based on whether there is a `COVFILE`. It is later read by `3dttest++`, and adds the option `-covariates` for the proper syntax. Don't change this logic statement.*
8. *`pairflag`: Adds the `-paired` flag to the `GROUPDIFF` t-test if the `Paired` variable is set to true.*

### 4. Test your setup

Check to make sure your setup is done correctly. You can run `make test-<variable>` to get the contents of a variable and how many "words" it has; useful in checking that you have exported the correct number of contrasts, etc.


### 5. Set up covariates


A covariate file takes the following format, including up to 32 whitespace-separated columns (including the subject identifier column). 

    idnum   age gender  ...
    RRF01   18  0       ...
    RRF02   20  1       ...
    RRF04   21  1       ...
    RRF05   22  0       ...
    ...     ... ...
    
From the [`3dttest++` manual](https://afni.nimh.nih.gov/pub/dist/doc/program_help/3dttest++.html):

> \* A maximum of 31 covariates are allowed.  If you have more, then
   seriously consider the likelihood that you are completely deranged.
   
    
The column headers will be part of the output filenames, so ensure that they are descriptive, but not too cumbersome. For example, you might end up with files named `DMNLPCC_PDa-PDr_mean_age.nii.gz`.

You can only add one covariate file, so the covariates for all subjects in all groups must be present in this one file. 

There is no required name for the covariate file (`COVFILE` is empty by default), but `covariates.txt` works just fine.

Additionally from the `3dttest++` manual:

> \* There is no provision for missing values -- the entire table must be filled!

### 6. Run analyses

There are two primary ways of running this makefile: single-group and between-group analyses. 

 + Run `SINGLEGROUP_<g>`, where `g` is one of the groups set in step 2 to run for a single group. Note that this requires a minimum of 14 subjects.
 For example, you could type:
 
```
make SINGLEGROUP_patient
```
 
 to create a directory called `patient` with the single group analyses results for the subjects in the file `group_patient.txt`.

 + Run `GROUPDIFF_<g1>-<g2>`, where `g1` and `g2` are two *different* groups from step 2. This also requires 14 subjects, but between the two groups.
 
 Analogously, this would be called using

```
make GROUPDIFF_control-patient
```

to create the contrast between patients and controls.

### 7. Notes on parallelizing

You might want to (a) parallelize processing of a single ROI to speed it up (see 7.1); or (b) parallelize processing of multiple ROIs to decrease total competion time (see 7.2). 

#### 7.1 Parallelizing locally

The easiest way to parallelize locally is to override `Analysis` to be `-Clustsim`, without an integer argument. Then, `3dttest++` will use all available cores.

Use this to test one ROI, as testing multiple will rapidly overwhelm your machine, but this is useful for rapid testing over waiting an hour+ for one-core execution to complete.

#### 7.2 Parellelizing on the grid engine

Check that the grid engine is set up properly for your user/machine. See [here](http://faculty.washington.edu/madhyt/using-the-gridengine-to-process-data-quickly/) for instructions.

You can submit the jobs on the queue with `qmake`:

    qmake -cwd -V -- -j <n> -k <TARGET>
    
Where "`n`" is the number of jobs (which you can get with `make test-allseeds` to see how many you can parallelize), and `TARGET` is the `make` target you want to build (like `SINGLEGROUP_PD`). The `-cwd` flag to qmake tells it to work in the current directory, and `-V` passes along all environment variables.

Or, you can submit the jobs using [`rmake`](https://github.com/IBIC/rmake):

    rmake -T <TARGET> 



