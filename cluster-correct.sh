#!/bin/bash

# Input files
orig=${1}
Zscr=${2}
label=${3}
outdir=${4}

newfile=${outdir}/$(basename ${Zscr})

# Get the label name for extraction
brik=$(3dinfo -label2index ${label} ${orig})
echo "Brik ID is ${brik}"

fslmaths ${Zscr} -thr 0 ${newfile}

newname=$(basename ${Zscr} .nii.gz | sed 's/_Zscr/_clusters/')

# Auto extact parameters

3dclust \
	-1tindex -1dindex \
	-savemask ${outdir}/${newname} \
	-1clip 2 5 3000 \
	${orig}[${brik}]

# If there was an output from 3dclust (i.e. if the new BRIK/HEAD files exist)
# then convert it to nifti and overlay it on the Zscr
if [ -e ${outdir}/${newname}+orig.BRIK ] ; then

	# Convert to NIFTI
	3dAFNItoNIFTI \
		-prefix ${outdir}/${newname}_sig.nii.gz \
		${outdir}/${newname}+orig.BRIK

	# Binarize (3dAFNItoNIFTI gives each continguous ROI a different number)
	fslmaths ${outdir}/${newname}_sig.nii.gz -bin \
		${outdir}/${newname}_sig.nii.gz

	# Add clusters to Zscr
	fslmaths ${newfile} -abs \
		-div ${newfile} \
		-add ${outdir}/${newname}_sig.nii.gz \
		${outdir}/${newname}.nii.gz

	# Clean up
	rm ${outdir}/${newname}+orig.{BRIK,HEAD} \
		${newfile}

else
	echo "No clusters found"

	fslmaths \
		${newfile} -abs \
		-div ${newfile} \
		${outdir}/${newname}.nii.gz

	rm ${newfile}
fi