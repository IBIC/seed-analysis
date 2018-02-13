# seed-analysis

Abstracted system for doing seed-based correlation analysis with any given set of groups and covariates. Uses AFNI `3dttest++`.

## How to setup this pipeline for any project.

Below is a general guide to setting up this pipeline for any project.

### 1. Create list of seeds

The makefile requires that the list of seeds and their locations be read in from a file. That file must be named `allseeds.txt` and have all the seeds used in the project listed in a single column like so:

	DANRaIPS
	DANLpIPS
	DANRFEF
	DANLFEF
	DANLaIPS
	...

This, like all other settings, can be modified on a per-project basis.

**Important**: All seeds must be generated for all subjects (see next section). If they aren't, the t-test for any seed where one or more subjects is missing the file will fail. 


### 2. Create `group-*.txt` group files

The makefile identifies groups by looking for files that match the regex `group-[[:alpha:]]*.txt`. For example, these files would create the groups "control" and "patient."

	group-control.txt
	patient-control.txt
	Makefile
	
Please ensure that there are no other files matching this pattern in the working directory. Do not use "`-`" in group names, as that is used to indicate contrasts. 

Group files must be of the following format:

	140593 /mnt/praxic/pdnetworksr01/subjects/140593/session1/mcvsa/SVC_MEICA/
	140605 /mnt/praxic/pdnetworksr01/subjects/140605/session1/mcvsa/SVC_MEICA/

That is, a subject identifier, followed by a space, then followed by the absolute path to the seed-based connectivity maps for that subject. It is important to label each subject because `3dttest++`'s syntax requires each map to be labeled with a subject identifier. 

**Important**: All of these directories must contain all of the required files. `3dttest++` will choke if it is given a non-existent file, and will not continue without it. I suggest you create a script to manage the creation of these files based on the existence of the map directories. 

### 3. Set variables

The first fifty or so lines of the makefile ask the user to fill in six variables (two more are automatically generated). Set these for your project (see details below)

1. `PROJECT_DIR`: The top-level directory for your project (contains `bin/`, `subjects/`, etc.)
2. `allseeds`: By default, all the seeds are read in from the file `allseeds` (see section 1). This can be overriden here if you have another method to identify seeds.
3. `groups`: This pulls the group names out of the `group-*.txt` files (see section 2). Don't override this setting, as later recipes assume the existence of the same `group-*.txt` files.
4. *`contrasts`: This variable automatically creates all the contrasts based on the given group, and filters out any 0 contrats (A - A). Don't change this declaration! There should be N(N-1) total contrasts* 
4. `STANDARD_MASK`: The MNI-space mask used in `3dttest++`. Using a mask reduces the number of comparisons and speeds up processing. Make sure the resolution (`Xmm`) matches the space your files are registered to. **Default:** 2mm
5. `SVCSUFFIX`: Depending on how `meica` was set up, the maps aren't necessarily given consistent names. Set this to whatever your project chose as the output. We're looking for the Z-transformed correlation map.
6. `COVFILE`: The covariates file (see section `XXX`) to read from. Leave blank if there are no covariates.
7. *`COVARIATE`: This variable is set automatically based on whether there is a `COVFILE`. It is later read by `3dttest++`, and adds the option `-covariates` for the proper syntax. Don't change this logic statement.*

### 4. Test your setup

Check to make sure your setup is done correctly. You can run `make test-<variable>` to get the contents of a variable and how many "words" it has; useful in checking that you have exported the correct number of contrasts, etc.


### 5. Set up covariates

*(This section in progress).*

### 6. Run analyses

There are two primary ways of running this makefile: single-group and between-group analyses. 

 + Run `SINGLEGROUP_<g>`, where `g` is one of the groups set in step 2 to run for a single group. Note that this requires a minimum of 14 subjects.
 + Run `GROUPDIFF_<g1>-<g2>`, where `g1` and `g2` are two *different* groups from step 2. This also requires 14 subjects, but between the two groups.
