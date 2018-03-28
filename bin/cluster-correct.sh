#!/bin/bash

function usage {
	echo "./${0} [-a A] -i <input prefix> -o <output dir>"
	echo
	echo -e "\t-i\tInput prefix. Path to HEAD/BRIK w/o +{orig,tlrc}.{HEAD,BRIK}"
	echo -e "\t-o\tOutput directory"
	echo -e "\t-a\tOPTIONAL, set custom alpha value (default .5)"
}

# Default alpha value
ALPHA=.05

while getopts ":a:i:o:" opt ; do
	case ${opt} in
		a)
			ALPHA=${OPTARG} ;;
		i)
			# Check that input file exists
			if find . -wholename "${INPUT}+????.BRIK" ; then
				INPUT=${OPTARG}
				echo "Input prefix is ${INPUT}"
			else
				echo "Input file ${OPTARG}+????.BRIK is missing."
			fi
			;;
		o)
			OUTPUTDIR=${OPTARG}
			echo "Output dir is ${OUTPUTDIR}"
	esac
done

# Check that the two req. args (and their flags) are on the CLI
if [[ ${#} -lt 4 ]]; then
	usage
	exit 1
fi

echo "Alpha level is ${ALPHA}"
mkdir -p ${OUTPUTDIR}
prefix=$(basename ${INPUT})

# Find the input file. The suffix (????) could be either tlrc or orig, so check
inputfile=$(find $(dirname ${INPUT}) -name "${prefix}+????.BRIK")

# Get the maximum brik index (0-indexed)
maxbrikindex=$(3dinfo -nvi ${inputfile})
echo "Max brik index: ${maxbrikindex}"

# Get the minimum cluster size
# The t-test info is in this 1D file
ttest=$(dirname ${INPUT})/*.${prefix}.CSimA.NN1_1sided.1D
p05=$(grep "^ 0.050000" ${ttest})

# Convert from alpha value to column (columns go NA, 0.1 ... 0.01)
column=$(echo "${ALPHA} * -100 + 12" | bc | sed 's/.00//')

# Get the ROI size in voxels
ROIsize_voxel=$(echo ${p05} | awk "{print \$${column}}")
echo "ROI size: ${ROIsize_voxel}"

# Loop over each sub-brik and extract it and do cluster correction on it if it's
# a contrast brik.
label=($(3dinfo -label ${INPUT} | sed 's/|/ /g'))
for brik in $(seq 0 ${maxbrikindex}) ; do

	# If it's not a diff brik, skip it.
	if [[ ! ${label[${brik}]} =~ ^.*-.*_Zscr$ ]]; then
		continue
	fi

	thislabel=$(echo ${label[${brik}]} | sed 's/_Zscr//')

	# Get the DoF by counting the number of subjects in each group and
	# subtracting two (for each group)
	contrasts=($(echo ${thislabel} | sed -e 's/_Zscr//' -e 's/-/ /'))
	dof=$(( $(wc -l < group-${contrasts[0]}.txt) + \
			$(wc -l < group-${contrasts[0]}.txt) - 2 ))

	# Convert from DoF to a Z score using a p-val of <.05 using a 1-sided t-test
	Z=$(R --no-save --slave <<-EOF
		cat(qt(.05, ${dof}, lower.tail = FALSE))
	EOF
	)

	# If the output file exists, remove it (3dclust doesn't have an -overwrite
	# option)
	rm -f ${OUTPUTDIR}/${prefix}_${thislabel}_vals+*.{BRIK,HEAD}

	# Do the cluster correction and save the values to _vals
	# 3dclust \
	# 	-NN1 ${ROIsize_voxel} \
	# 	-1thresh ${Z} \
	# 	-prefix ${OUTPUTDIR}/${prefix}_${thislabel}_vals \
	# 	${inputfile}[${brik}]

	3dAFNItoNIFTI \
		-prefix ${inputfile}.nii.gz \
		${inputfile}[${brik}]

	cluster \
		-z        ${inputfile}.nii.gz  \
		--zthresh=${Z} \
		--no_table \
		--othresh=${OUTPUTDIR}/${prefix}_${thislabel}_vals

	# Extract the Z scr block (we need it either as a "correction failed"
	# image  or to overlay corrected images on.
	3dAFNItoNIFTI \
		-prefix ${OUTPUTDIR}/${prefix}_${thislabel}-temp1.nii.gz \
		${inputfile}[${brik}]

	# Binarize Zscr vals
	fslmaths ${OUTPUTDIR}/${prefix}_${thislabel}-temp1.nii.gz \
		-thr 0 -bin \
		${OUTPUTDIR}/${prefix}_${thislabel}-temp2.nii.gz


	# If the output file was created (i.e. there ARE sig. clusters)
	nfound=$(find ${OUTPUTDIR} \
				-name "${prefix}_${thislabel}_vals+????.BRIK" | wc -l)
	if [[ ${nfound} > 0 ]] ; then

		echo "Converting to NIFTI"

		# Convert to NIFTI
		3dAFNItoNIFTI \
			-prefix ${OUTPUTDIR}/${prefix}_${thislabel}_sigvals.nii.gz \
			${OUTPUTDIR}/${prefix}_${thislabel}_vals+*

		rm ${OUTPUTDIR}/${prefix}_${thislabel}_vals+????.{BRIK,HEAD}

		# Binarize values to get binary mask
		fslmaths ${OUTPUTDIR}/${prefix}_${thislabel}_sigvals.nii.gz \
			-bin \
			${OUTPUTDIR}/${prefix}_${thislabel}_sigmask.nii.gz

		# Add binarized sig values to binarized Zmap to get 1=n.s, 2=s.
		fslmaths ${OUTPUTDIR}/${prefix}_${thislabel}-temp2.nii.gz \
			-add ${OUTPUTDIR}/${prefix}_${thislabel}_sigmask.nii.gz \
			${OUTPUTDIR}/${prefix}_${thislabel}.nii.gz

	else

		mv ${OUTPUTDIR}/${prefix}_${thislabel}{-temp1,_clusters}.nii.gz

	fi

done

# Clean up
rm -f ${OUTPUTDIR}/${prefix}{*temp*,*_sigmask}.nii.gz
