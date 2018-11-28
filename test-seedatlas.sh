#!/bin/bash

# Tara wants the NBM, l/r PPN, l/r putamen, and r hippocampus

bin/seed-atlas.sh \
	pdOn-pdOff/clustcorr/*{NBMNBM4,PPN,putamen,RHC}*_sai_*clusters.nii.gz
