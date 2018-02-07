#* This file works by loading in all the groups matching the regex group-*.txt
#* and then generating single group and group difference recipes for each
#* individual group and group difference recipes for each pair of groups.
#* This means it does generate recipes in the form of GROUPDIFF_A-A, which is
#* an unavoidable side-effect.

#! Project root directory
PROJECT_DIR=/mnt/praxic/pdnetworksr01/

#! Seeds is the list of seeds in $(PROJECT_DIR)/lib/SVC_seeds/
allseeds=$(shell cat allseeds.txt)

#! What are the groups in this analysis?
groups=$(patsubst group-%.txt, %, $(wildcard group-[[:alpha:]]*.txt))

#! Generate the list of contrasts based on the given groups. Filters out any
#! matching contrats (like A-A).
contrasts=$(foreach g1,$(groups), \
			$(foreach g2,$(groups), \
				$(filter-out $(g1)-$(g1),$(g1)-$(g2)) ))

#! Which standard brain to register to
STANDARD_MASK=/usr/share/fsl/5.0/data/standard/MNI152_T1_2mm_brain_mask.nii.gz

#! what is the name of the SVC output file?
SVCSUFFIX=_corrmap_z_mefc

#! Get the covariates file. None by default
COVFILE=

#! Which type of analysis to use. Use -Clustsim 1 to do cluster correction on a
#! single core.
ANALYSIS=-Clustsim 1
# ANALYSIS=-ETAC

# If a covariate file is given, add the flag to the COVARIATE variable
ifeq ($(COVFILE),)
COVARIATE=
else
COVARIATE=-covariates $(COVFILE)
endif

################################################################################
# Single-group analysis

define singlegroup =

#? Create the NIFTI format mean and Tstat images
SINGLEGROUP_$(1): $(foreach seed,$(allseeds),\
						$(1)/nifti/$(seed)_$(1)_mean.nii.gz)

SINGLEGROUP_$(1)_clustcorr: $(foreach seed,$(allseeds), \
								$(1)/clustcorr/$(seed)_$(1)_clusters.nii.gz)

#> Convert the mean images from the first subbrick (#0)
#> If covariates or Zscr are misisng, delete _mean to regenerate all.
$(1)/nifti/$(2)_$(1)_mean.nii.gz: $(1)/headbrik/$(2)+orig.BRIK
	mkdir -p $(1)/nifti ;\
	$(PROJECT_DIR)/bin/extract-all-bricks.sh \
		$$(dir $$@) \
		$(1)/headbrik/$(2)+orig.BRIK

#> Run the ttest on the available MEFC images; no cluster correction (not
#> enough people)
$(1)/headbrik/$(2)+orig.BRIK: \
		$(PROJECT_DIR)/lib/SVC_seeds/$(2)_sphereroi.nii.gz \
		group-$(1).txt
	mkdir -p $(1)/headbrik ;\
	3dttest++ \
		-prefix $(1)/headbrik/$(2) \
		-setA $(1) $$(shell sed 's|$$$$|/$(2)$(SVCSUFFIX).nii.gz|' \
						group-$(1).txt) \
		-overwrite \
		-mask $(STANDARD_MASK) \
		$(COVARIATE) \
		$(ANALYSIS)

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
									$(1)/clustcorr/$(seed)_$(1)_clusters.nii.gz)


#> Extract all the sub-bricks (automatically does all mean/Tstat for all
#> covariates and the basic state). Removes all of the single-group analyses
#> (those are extracted in the single group analysis.
$(1)/nifti/$(2)_$(1)_mean.nii.gz: $(1)/headbrik/$(2)+orig.BRIK
	mkdir -p $(1)/nifti ;\
	$(PROJECT_DIR)/bin/extract-all-bricks.sh \
		$$(dir $$@) \
		$(1)/headbrik/$(2)+orig.BRIK ;\
	find $(1)/nifti/ \
		-mindepth 1 \
		! -name "$(2)_*-*_*.nii.gz" \
		-delete

#> Run the ttest on the available MEFC images; no cluster correction (not
#> enough people)
$(1)/headbrik/$(2)+orig.BRIK: \
		$(PROJECT_DIR)/lib/SVC_seeds/$(2)_sphereroi.nii.gz \
		group-$(1).txt group-$(2).txt
	mkdir -p $(1)/headbrik ;\
	3dttest++ \
		-prefix $(1)/headbrik/$(2) \
		-setA $(1) $$(shell sed 's|$$$$|/$(2)$(SVCSUFFIX).nii.gz|' \
						group-$(1).txt) \
		-setB $(2) $$(shell sed 's|$$$$|/$(2)$(SVCSUFFIX).nii.gz|' \
						group-$(2).txt) \
		-overwrite \
		-mask $(STANDARD_MASK) \
		$(COVARIATE) \
		$(ANALYSIS)

$(1)/clustcorr/$(2)_$(1)_clusters.nii.gz: \
		$(1)/headbrik/$(2)+orig.BRIK \
		$(1)/nifti/$(2)_$(1)_mean.nii.gz
	mkdir -p $(1)/clustcorr ;\
	./cluster-correct.sh \
		$(1)/headbrik/$(2)+orig.BRIK \
		$(1)_Zscr \
		$(1)/nifti/$(2)_$(1)_Zscr.nii.gz \
		$(1)/clustcorr


endef

# Expand over the group list twice to create the recipes for every combination
# of groups. This makes things like A-A, which would be 0, of course.
$(foreach contrast,$(contrasts), \
	$(foreach seed,$(allseeds), \
		$(eval $(call twogroup,$(contrast),$(seed)))))

.PHONY: $(foreach group1,$(groups), \
			$(foreach group2,$(groups), \
				GROUPDIFF_${group1}-${group2})) \
		$(foreach group1,$(groups), \
			SINGLEGROUP_${group1})

.SECONDARY:


################################################################################

#? Echo the value of a variable
test-%:
	@echo $($*) ;\
	 echo "Count $*: $(words $($*))"
