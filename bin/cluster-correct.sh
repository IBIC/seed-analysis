#!/bin/bash

function usage {
	echo "./${0} <.*+orig.BRIK> <label to extract> <Zscr.nii.gz> <outdir>"
	echo
	echo -e ".*+orig.BRIK:\tBRIK file with output from 3dttest++"
	echo -e "label:\t\tLabel to extract from .*+orig.BRIK"
	echo -e "Zscr.nii.gz:\tUncorrected Z-score nifti"
	echo -e "outdir:\t\tWhere to save cluster-corrected niftis"
}

# What alpha value to use for determining ROI size
ALPHA=.05

# Input files
orig=${1}
label=${2}
Zscr=${3}
ttest=${4}
outdir=${5}

if [[ ${#} -ne 5 ]]; then
	usage
	exit 1
fi

newfile=${outdir}/$(basename ${Zscr})

# Get the label name for extraction
brik=$(3dinfo -label2index ${label} ${orig})
echo "Brik ID is ${brik}"

fslmaths ${Zscr} -thr 0 ${newfile}

newname=$(basename ${Zscr} .nii.gz | sed 's/_Zscr/_clusters/')

# Get the minimum cluster size
p05=$(grep "^ 0.050000" ${ttest})
# Convert from alpha value to column (columns go NA, 0.1 ... 0.01)
column=$(echo "${ALPHA} * -100 + 12" | bc | sed 's/.00//')

# Get the ROI size in voxels
ROIsize_voxel=$(echo ${p05} | awk "{print \$${column}}")

# Get the voxel size in mm for voxel -> uL conversion
voxelsize=$(fslinfo ${Zscr} | head -n9 | tail -n3 | awk '{print $2}')
voxelvol=$(echo ${voxelsize} | sed 's/ /\*/g' | bc)

ROIsize_uL=$(echo "${ROIsize_voxel} * ${voxelvol}" | bc | sed 's/.0\+$//')

# Auto extact parameters
3dclust \
	-1tindex -1dindex \
	-savemask ${outdir}/${newname} \
	-1clip 0.3 5 ${ROIsize_uL} \
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