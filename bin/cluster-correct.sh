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

echo "ROI size: ${ROIsize_voxel}"

# Get the degrees of freedom
contrasts=($(basename ${label} | sed -e 's/_Zscr//' -e 's/-/ /'))
if [ ${#contrasts[@]} -eq 1 ] ; then
	dof=$(wc -l < group-${contrasts[0]}.txt)
else
	dof=$(( $(wc -l < group-${contrasts[0]}.txt) + \
			$(wc -l < group-${contrasts[0]}.txt) - 2 ))
fi

Z=$(R --no-save --slave <<-EOF
	cat(qt(.05, ${dof}, lower.tail = FALSE))
EOF
)

echo "Z threshold is ${Z} (dof: ${dof})"

# Auto extact parameters
3dclust \
	-NN1 ${ROIsize_voxel} \
	-1thresh ${Z} \
	-prefix ${outdir}/${newname}vals \
	${orig}[${brik}]

# If there was an output from 3dclust (i.e. if the new BRIK/HEAD files exist)
# then convert it to nifti and overlay it on the Zscr
if [ -e ${outdir}/${newname}vals+orig.BRIK ] ; then

	# Convert to NIFTI
	3dAFNItoNIFTI \
		-prefix ${outdir}/${newname}_sigvals.nii.gz \
		${outdir}/${newname}vals+orig.BRIK

	# Binarize (3dAFNItoNIFTI gives each continguous ROI a different number)
	fslmaths ${outdir}/${newname}_sigvals.nii.gz -bin \
		${outdir}/${newname}_sig.nii.gz

	# Add clusters to Zscr
	fslmaths ${newfile} -abs \
		-div ${newfile} \
		-add ${outdir}/${newname}_sig.nii.gz \
		${outdir}/${newname}.nii.gz

	# Clean up
	rm ${outdir}/${newname}vals+orig.{BRIK,HEAD}

else
	echo "No clusters found"

	# Binarize
	fslmaths \
		${newfile} -bin \
		${outdir}/${newname}.nii.gz

	# rm ${newfile}
fi