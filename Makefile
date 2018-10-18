#* This file works by loading in all the groups matching the regex group-*.txt
#* and then generating single group and group difference recipes for each
#* individual group and group difference recipes for each pair of groups.
#* This means it does generate recipes in the form of GROUPDIFF_A-A, which is
#* an unavoidable side-effect.

# Has all the user-set variables like PROJECT_DIR
include analysis/settings.conf

#! Seed directory is where all the seeds are kept for this project. This
#! directory is the first entry in allseeds.txt
seedsdir=$(shell head -n1 analysis/allseeds.txt)

#! Seeds is the list of seeds (w/o extensions, etc). They are the n>1 lines in
#! allseeds.txt
allseeds=$(shell tail -n+2 analysis/allseeds.txt)

# Check to make sure there are no hyphens in seed names, they'll muck things up
ifneq ($(findstring -,$(allseeds)),)
$(error Hyphen in one or more seed name(s))
endif

#! What are the groups in this analysis?
groups=$(patsubst group-%.txt, %, $(wildcard group-[[:alpha:]]*.txt))

# Check to make sure there are no hyphens in group names, they'll muck things up
ifneq ($(findstring -,$(groups)),)
$(error Hyphen in one or more group name(s))
endif

#! Generate the list of contrasts based on the given groups. Filters out any
#! matching contrats (like A-A).
contrasts=$(foreach g1,$(groups), \
			$(foreach g2,$(groups), \
				$(filter-out $(g1)-$(g1),$(g1)-$(g2)) ))

# If a covariate file is given, add the flag to the covariate variable and
# store the number of covariates for later. Otherwise, store the number of
# covariates as 0.
ifeq ($(COVFILE),)
covariate=
n_covariates=0
else
covariate=-covariates $(COVFILE)
covariatenames=$(filter-out idnum,$(shell head -n1 $(COVFILE)))
n_covariates=$(words $(covariatenames))
endif

# Check to make sure there's no hyphens in covariate names, they'll muck things
# up
ifneq ($(findstring -,$(covariatenames)),)
$(error Hyphen in one or more covariate name(s))
endif

#! Check whether to do a paired t-test (group diff only); defaults to "no"
ifdef PAIRED
pairflag=-paired
else
pairflag=
endif

################################################################################
# Single-group analysis

define singlegroup =

#? Create the NIFTI format mean and Tstat images
SINGLEGROUP_$(1): $(foreach seed,$(allseeds),\
						$(1)/nifti/$(seed)_$(1)_mean.nii.gz)

SINGLEGROUP_$(1)_clustcorr: \
						$(foreach seed,$(allseeds), \
							$(1)/clustcorr/$(seed)_$(1)_posclusters.nii.gz) \
						$(foreach seed,$(allseeds), \
							$(1)/clustcorr/$(seed)_$(1)_negclusters.nii.gz) \
						$(foreach seed,$(allseeds), \
							$(1)/clustcorr/$(seed)_$(1)_posclusters.png) \
						$(foreach seed,$(allseeds), \
							$(1)/clustcorr/$(seed)_$(1)_negclusters.png)

#> Convert the mean images from the first subbrick (#0)
#> If covariates or Zscr are misisng, delete _mean to regenerate all.
$(1)/nifti/$(2)_$(1)_mean.nii.gz: $(1)/headbrik/$(2)+????.BRIK
	mkdir -p $(1)/nifti ;\
	bin/extract-all-bricks.sh 			\
		$$(dir $$@) 					\
		$(1)/headbrik/$(2)+????.BRIK

#> Run the ttest on the available MEFC images; no cluster correction (not
#> enough people)
$(1)/headbrik/$(2)+????.BRIK: group-$(1).txt
	mkdir -p $(1)/headbrik 				;\
	export OMP_NUM_THREADS=1 ;			 \
	3dttest++ \
		-prefix $(1)/headbrik/$(2) 		 \
		-setA $(1) $$(shell sed 's|$$$$|/$(2)$(SVCSUFFIX).nii.gz|' \
						group-$(1).txt)  \
		-overwrite 						 \
		-mask $(STANDARD_MASK)			 \
		$(covariate)					 \
		$(ANALYSIS) 					 \
		-prefix_clustsim $(1)/headbrik/cc.$(2)

#> Create the NIFTI files with the clusters that survive correction
# (cluster-correct.sh creates both.)
$(1)/clustcorr/$(2)_$(1)_posclusters.nii.gz \
$(1)/clustcorr/$(2)_$(1)_negclusters.nii.gz: \
		$(1)/headbrik/$(2)+????.BRIK \
		$(1)/nifti/$(2)_$(1)_mean.nii.gz
	mkdir -p $(1)/clustcorr   ;\
	n_subjects=$$$$(grep -c "[^\s]" group-$(1).txt) ;\
	dof=$$$$(echo $$$${n_subjects} - $(n_covariates) - 1 | bc -l) ;\
	echo "$$$${dof}" ;\
	bin/cluster-correct.sh     \
		-i $(1)/headbrik/$(2)  \
		-o $(1)/clustcorr      \
		-d $$$${dof}

#> Make a slice of the clusters images - pattern matching works here
$(1)/clustcorr/$(2)_$(1)_%clusters.png: \
		$(1)/clustcorr/$(2)_$(1)_%clusters.nii.gz
	bin/slice-all-that-match.sh \
		$(1)/clustcorr/$(2)_$(1)*_$$*clusters.nii.gz

endef

#@ Create a separate recipe for calculating the DoF for each group because if
#@ we put it in the other recipe, it will be overridden because it also loops
#@ over seeds
define singlegroup_dof =

SINGLEGROUP_$(1)_DoF:
	n_subjects=$$$$(grep -c "[^\s]" group-$(1).txt) ;\
	dof=$$$$(echo $$$${n_subjects} - $(n_covariates) - 1 | bc) ;\
	echo "$(1) DoF: $$$${dof}"

endef

# Loop over groups and seeds to create targets/recipes for the single-group
# analysis.
$(foreach group,$(groups), \
	$(foreach seed,$(allseeds), \
		$(eval $(call singlegroup,$(group),$(seed)))))

# Calculate DoF for each group, but only once!
$(foreach group,$(groups), \
	$(eval $(call singlegroup_dof,$(group))))

################################################################################

################################################################################
# Group difference

define twogroup =

#? Create the NIFTI format mean and Tstat images for both the group difference
#? (A-B) as well as automatically creating the A and B groups
GROUPDIFF_$(1): $(foreach seed,$(allseeds),\
						$(1)/nifti/$(seed)_$(1)_mean.nii.gz)

GROUPDIFF_$(1)_clustcorr: \
					$(foreach seed,$(allseeds), \
							$(1)/clustcorr/$(seed)_$(1)_posclusters.nii.gz) \
					$(foreach seed,$(allseeds), \
							$(1)/clustcorr/$(seed)_$(1)_negclusters.nii.gz) \
					$(foreach seed,$(allseeds), \
							$(1)/clustcorr/$(seed)_$(1)_posclusters.png) \
					$(foreach seed,$(allseeds), \
							$(1)/clustcorr/$(seed)_$(1)_negclusters.png)

#> Extract all the sub-bricks (automatically does all mean/Tstat for all
#> covariates and the basic state). Removes all of the single-group analyses
#> (those are extracted in the single group analysis).
$(1)/nifti/$(2)_$(1)_mean.nii.gz: $(1)/headbrik/$(2)+????.BRIK
	mkdir -p $(1)/nifti ;\
	bin/extract-all-bricks.sh \
		$$(dir $$@) \
		$(1)/headbrik/$(2)+????.BRIK ;\
	find $(1)/nifti/ \
		-mindepth 1 \
		! -name "*_*-*_*.nii.gz" \
		-delete

#> Run the ttest on the available MEFC images; no cluster correction (not
#> enough people)
$(1)/headbrik/$(2)+????.BRIK:
	mkdir -p $(1)/headbrik ;\
	export OMP_NUM_THREADS=1 ;\
	group1=$$$$(echo $(1) | sed 's/-.*//') ;\
	group2=$$$$(echo $(1) | sed 's/.*-//') ;\
	3dttest++ \
		-prefix $(1)/headbrik/$(2) \
		-prefix_clustsim $(1)/headbrik/cc.$(2) \
		-setA $$$${group1} \
				$$$$(sed 's|$$$$|/$(2)$(SVCSUFFIX).nii.gz|' \
					group-$$$${group1}.txt) \
		-setB $$$${group2} \
				$$$$(sed 's|$$$$|/$(2)$(SVCSUFFIX).nii.gz|' \
					group-$$$${group2}.txt) \
		-overwrite \
		-mask $(STANDARD_MASK) \
		$(covariate) \
		$(ANALYSIS) \
		$(pairflag)

# Generate different rules depending on whether the analysis was done on paired
# or unpaired groups
ifndef PAIRED

## UNPAIRED

#> Create the NIFTI files with the clusters that survive correction: paired
# (cluster-correct.sh creates both.)
$(1)/clustcorr/$(2)_$(1)_posclusters.nii.gz \
$(1)/clustcorr/$(2)_$(1)_negclusters.nii.gz: \
		$(1)/headbrik/$(2)+????.BRIK \
		$(1)/nifti/$(2)_$(1)_mean.nii.gz \
		$(1)/headbrik/cc.$(2).CSimA.NN1_1sided.1D
	mkdir -p $(1)/clustcorr ;\
	export OMP_NUM_THREADS=1 ;\
	group1=$$$$(echo $(1) | sed 's/-.*//') ;\
	group2=$$$$(echo $(1) | sed 's/.*-//') ;\
	n_subjects1=$$$$(grep -c "[^\s]" group-$$$${group1}.txt) ;\
	n_subjects2=$$$$(grep -c "[^\s]" group-$$$${group2}.txt) ;\
	n_subjects=$$$$(echo $$$${n_subjects1} + $$$${n_subjects2} | bc) ;\
	dof=$$$$(echo $$$${n_subjects} - $(n_covariates) - 2 | bc) ;\
	echo "$$$${dof}" ;\
	bin/cluster-correct.sh \
		-D \
		-i $(1)/headbrik/$(2) \
		-o $(1)/clustcorr \
		-d $$$${dof}

else

## PAIRED

#> Create the NIFTI files with the clusters that survive correction: unpaired
# (cluster-correct.sh creates both.)
$(1)/clustcorr/$(2)_$(1)_posclusters.nii.gz \
$(1)/clustcorr/$(2)_$(1)_negclusters.nii.gz: \
		$(1)/headbrik/$(2)+????.BRIK \
		$(1)/nifti/$(2)_$(1)_mean.nii.gz \
		$(1)/headbrik/cc.$(2).CSimA.NN1_1sided.1D
	mkdir -p $(1)/clustcorr ;\
	export OMP_NUM_THREADS=1 ;\
	group1=$$$$(echo $(1) | sed 's/-.*//') ;\
	n_pairs=$$$$(grep -c "[^\s]" group-$$$${group1}.txt) ;\
	dof=$$$$(echo $$$${n_pairs} - $(n_covariates) - 1 | bc) ;\
	echo "$$$${dof}" ;\
	bin/cluster-correct.sh \
		-D \
		-i $(1)/headbrik/$(2) \
		-o $(1)/clustcorr \
		-d $$$${dof}

endif

#> Make a slice of the clusters images - pattern matching works here
$(1)/clustcorr/$(2)_$(1)_%clusters.png: \
		$(1)/clustcorr/$(2)_$(1)_%clusters.nii.gz
	bin/slice-all-that-match.sh \
		$(1)/clustcorr/$(2)_$(1)*_$$*clusters.nii.gz

endef

# There are two calculations to perform, one if paired, and one if unpaired.
ifndef PAIRED

## UNPAIRED

#@ If the calculation is UNPAIRED, then the DoF is the total number of subjects
#@ minus 2 (two groups) and then minus the number of covariates. IMPORTANT: The
#@ makefile does not check that the two groups are actually unpaired.
define twogroup_dof =

#? Calculate the DoF for an unpaired group difference
GROUPDIFF_$(1)_DoF:
	group1=$$$$(echo $(1) | sed 's/-.*//') ;\
	group2=$$$$(echo $(1) | sed 's/.*-//') ;\
	n_subjects1=$$$$(grep -c "[^\s]" group-$$$${group1}.txt) ;\
	n_subjects2=$$$$(grep -c "[^\s]" group-$$$${group2}.txt) ;\
	n_subjects=$$$$(echo $$$${n_subjects1} + $$$${n_subjects2} | bc) ;\
	dof=$$$$(echo $$$${n_subjects} - $(n_covariates) - 2 | bc) ;\
	echo "Unpaired DoF: $$$${dof}" ;\

endef

else

## PAIRED

#@ If the calculation is PAIRED, then the DoF is the number of pairs minus 1,
#@ then minus the number of covariates. Just use the number of subjects in
#@ group 1 as the number of pairs. IMPORTANT: The makefile does not check that
#@ the groups are actually paired.
define twogroup_dof =

#? Calculate the DoF for a paired group difference
GROUPDIFF_$(1)_DoF:
	group1=$$$$(echo $(1) | sed 's/-.*//') ;\
	n_pairs=$$$$(grep -c "[^\s]" group-$$$${group1}.txt) ;\
	dof=$$$$(echo $$$${n_pairs} - $(n_covariates) - 1 | bc) ;\
	echo "Paired DoF: $$$${dof}" ;\

endef

endif

# Expand over the group list twice to create the recipes for every combination
# of groups.
$(foreach contrast,$(contrasts), \
	$(foreach seed,$(allseeds), \
		$(eval $(call twogroup,$(contrast),$(seed)))))

$(foreach contrast,$(contrasts), \
	$(eval $(call twogroup_dof,$(contrast))))

.PHONY: EVERYTHING \
		$(foreach contrast,$(contrasts), GROUPDIFF_${contrast})) \
		$(foreach group,$(groups), SINGLEGROUP_${group})

.SECONDARY:

#? This will run everything the makefile can do.
EVERYTHING: $(foreach contrast,$(contrasts), \
				GROUPDIFF_${contrast})) \
		$(foreach group,$(groups), \
			SINGLEGROUP_${group})

################################################################################

#? Echo the value of a variable
test-%:
	@echo \'$($*)\' ;\
	 echo "Count $*: $(words $($*))"
