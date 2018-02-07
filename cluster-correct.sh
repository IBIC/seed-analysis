#!/bin/bash

function usage {
	echo "./${0} <.*+orig.BRIK> <label to extract> <Zscr.nii.gz> <outdir>"
	echo
	echo -e ".*+orig.BRIK:\tBRIK file with output from 3dttest++"
	echo -e "label:\t\tLabel to extract from .*+orig.BRIK"
	echo -e "Zscr.nii.gz:\tUncorrected Z-score nifti"
	echo -e "outdir:\t\tWhere to save cluster-corrected niftis"
}

# Input files
orig=${1}
label=${2}
Zscr=${3}
outdir=${4}

if [[ ${#} -ne 4 ]]; then
	usage
	exit 1
fi

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