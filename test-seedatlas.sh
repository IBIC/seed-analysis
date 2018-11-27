#!/bin/bash

# Tara wants the NBM, l/r PPN, l/r putamen, and r hippocampus

bin/seed-atlas.sh \
	hcOn-pdOff/clustcorr/*NBMNBM4*_sai_*oindex.nii.gz \
	hcOn-pdOff/clustcorr/*PPN*_sai_*oindex.nii.gz \
	hcOn-pdOff/clustcorr/*putamen*_sai_*oindex.nii.gz \
	hcOn-pdOff/clustcorr/*RHC*_sai_*oindex.nii.gz \
