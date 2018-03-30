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

#! What are the groups in this analysis?
groups=$(patsubst group-%.txt, %, $(wildcard group-[[:alpha:]]*.txt))

#! Generate the list of contrasts based on the given groups. Filters out any
#! matching contrats (like A-A).
contrasts=$(foreach g1,$(groups), \
			$(foreach g2,$(groups), \
				$(filter-out $(g1)-$(g1),$(g1)-$(g2)) ))

# If a covariate file is given, add the flag to the covariate variable
ifeq ($(COVFILE),)
covariate=
else
covariate=-covariates $(COVFILE)
endif

#! Check whether to do a paired t-test (group diff only); defaults to "no"
Paired=
ifeq ($(Paired),)
pairflag=
else
pairflag=-paired
endif

################################################################################
# Single-group analysis

define singlegroup =

#? Create the NIFTI format mean and Tstat images
SINGLEGROUP_$(1): $(foreach seed,$(allseeds),\
						$(1)/nifti/$(seed)_$(1)_mean.nii.gz)

SINGLEGROUP_$(1)_clustcorr: $(foreach seed,$(allseeds), \
								$(1)/clustcorr/$(seed)_$(1)_clusters.nii.gz) \
							$(foreach seed,$(allseeds), \
								$(1)/clustcorr/$(seed)_$(1)_clusters.gif)

#> Convert the mean images from the first subbrick (#0)
#> If covariates or Zscr are misisng, delete _mean to regenerate all.
$(1)/nifti/$(2)_$(1)_mean.nii.gz: $(1)/headbrik/$(2)+????.BRIK
	mkdir -p $(1)/nifti ;\
	bin/extract-all-bricks.sh \
		$$(dir $$@) \
		$(1)/headbrik/$(2)+????.BRIK

#> Run the ttest on the available MEFC images; no cluster correction (not
#> enough people)
$(1)/headbrik/$(2)+????.BRIK: group-$(1).txt
	mkdir -p $(1)/headbrik ;\
	export OMP_NUM_THREADS=1 ;\
	3dttest++ \
		-prefix $(1)/headbrik/$(2) \
		-setA $(1) $$(shell sed 's|$$$$|/$(2)$(SVCSUFFIX).nii.gz|' \
						group-$(1).txt) \
		-overwrite \
		-mask $(STANDARD_MASK) \
		$(covariate) \
		$(Analysis) \
		-prefix_clustsim $(1)/headbrik/cc.$(2)

$(1)/clustcorr/$(2)_$(1)_clusters.nii.gz: \
		$(1)/headbrik/$(2)+????.BRIK \
		$(1)/nifti/$(2)_$(1)_mean.nii.gz
	mkdir -p $(1)/clustcorr ;\
	bin/cluster-correct.sh \
		-i $(1)/headbrik/$(2) \
		-o $(1)/clustcorr

$(1)/clustcorr/$(2)_$(1)_clusters.gif: \
		$(1)/clustcorr/$(2)_$(1)_clusters.nii.gz
	bin/slice-all-that-match.sh \
		$(1)/clustcorr/$(2)_$(1)_*clusters.nii.gz

endef

# Loop over groups and seeds to create targets/recipes for the single-group
# analysis.
$(foreach group,$(groups), \
	$(foreach seed,$(allseeds), \
		$(eval $(call singlegroup,$(group),$(seed)))))

################################################################################

################################################################################
# Group difference

define twogroup =

#? Create the NIFTI format mean and Tstat images for both the group difference
#? (A-B) as well as automatically creating the A and B groups
GROUPDIFF_$(1): $(foreach seed,$(allseeds),\
						$(1)/nifti/$(seed)_$(1)_mean.nii.gz)

GROUPDIFF_$(1)_clustcorr: $(foreach seed,$(allseeds), \
									$(1)/clustcorr/$(seed)_$(1)_clusters.nii.gz) \
						$(foreach seed,$(allseeds), \
									$(1)/clustcorr/$(seed)_$(1)_clusters.gif)

#> Extract all the sub-bricks (automatically does all mean/Tstat for all
#> covariates and the basic state). Removes all of the single-group analyses
#> (those are extracted in the single group analysis.
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
		$(Analysis) \
		$(pairflag)

$(1)/clustcorr/$(2)_$(1)_clusters.nii.gz: \
		$(1)/headbrik/$(2)+????.BRIK \
		$(1)/nifti/$(2)_$(1)_mean.nii.gz \
		$(1)/headbrik/cc.$(2).CSimA.NN1_1sided.1D
	mkdir -p $(1)/clustcorr ;\
	export OMP_NUM_THREADS=1 ;\
	bin/cluster-correct.sh -D \
		-i $(1)/headbrik/$(2) \
		-o $(1)/clustcorr

$(1)/clustcorr/$(2)_$(1)_clusters.gif: \
		$(1)/clustcorr/$(2)_$(1)_clusters.nii.gz
	bin/slice-all-that-match.sh \
		$(1)/clustcorr/$(2)_$(1)_*clusters.nii.gz


endef

# Expand over the group list twice to create the recipes for every combination
# of groups.
$(foreach contrast,$(contrasts), \
	$(foreach seed,$(allseeds), \
		$(eval $(call twogroup,$(contrast),$(seed)))))

.PHONY: EVERYTHING \
		$(foreach contrast,$(contrasts), \
				GROUPDIFF_${contrast})) \
		$(foreach group,$(groups), \
			SINGLEGROUP_${group})

.SECONDARY:

EVERYTHING: $(foreach contrast,$(contrasts), \
				GROUPDIFF_${contrast})) \
		$(foreach group,$(groups), \
			SINGLEGROUP_${group})

################################################################################

#? Echo the value of a variable
test-%:
	@echo $($*) ;\
	 echo "Count $*: $(words $($*))"
