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

# The second brik is always the one that we want - for a single group, it's the
# Z score, and for a groupdiff, it goes diff, diff z, group 1, group 1 Z ...
# BRIKs are 0-indexed, so the 2nd is 1
# brik=1

# Get the corresponding label (we need to know whether this is a diff or single
# group BRIK)
labels=($(3dinfo -label ${INPUT} | sed 's/|/ /g'))

# Loop over every other brik, Zscr bricks are all the odd briks
for brik in $(seq 1 2 ${maxbrikindex}) ; do

    label=$(echo ${labels[${brik}]} | sed 's/_Zscr//')
    echo ${label} ; continue
    # Degrees of freedom
    if [[ ${label} =~ .*-.* ]] ; then
        # Get the DoF by counting the number of subjects in each group and
        # subtracting two (for each group)
        contrasts=($(echo ${label} | sed 's/-/ /'))
        dof=$(( $(wc -l < group-${contrasts[0]}.txt) + \
                $(wc -l < group-${contrasts[1]}.txt) - 2 ))
    else
        # Degrees of freedom for one group is n - 1
        dof=$(( $(wc -l < group-${label}.txt) - 1 ))
    fi
    echo "DoF: ${dof}"

    # Convert from DoF to a Z score using a p-val of <.05 using a 1-sided t-test
Z=$(R --no-save --slave <<-EOF
    cat(qt(.05, ${dof}, lower.tail = FALSE))
EOF
)
    # No need to write out this three-variable prefix every ime
    outputprefix=${OUTPUTDIR}/${prefix}_${label}

    # Extract the Z scr block (we need it either as a "correction failed"
    # image  or to overlay corrected images on.
    3dAFNItoNIFTI \
        -prefix ${outputprefix}_Z.nii.gz \
        ${inputfile}[${brik}]

    # Run the cluster correction
    # Take the input (zstat) image, threshold it at zthresh, and save the thresheld
    # values to othresh, and save a mask with the voxel size to osize.
    cluster \
            --zstat=${outputprefix}_Z.nii.gz  \
            --zthresh=${Z} \
            --othresh=${outputprefix}_clusters \
            --osize=${outputprefix}_osize \
        > ${outputprefix}_clusters.txt

    # We need to save only the clusters whose size > $ROIsize_voxel, so create a
    # binary mask with which clusters to save.
    fslmaths \
        ${outputprefix}_osize \
        -thr ${ROIsize_voxel} \
        -bin \
        ${outputprefix}_keepmap

    # Mask vals image to only include large enough clusters and then binarize
    # them to create a nice mask
    fslmaths ${outputprefix}_clusters.nii.gz \
        -mas ${outputprefix}_keepmap \
        ${outputprefix}_clusters.nii.gz

    > ${OUTPUTDIR}/clusters-no.txt
    > ${OUTPUTDIR}/clusters-yes.txt
    if [[ $(fslstats ${outputprefix}_clusters.nii.gz -M) == "0.000000 " ]]; then
        echo -e "${prefix}_${label}" >> ${OUTPUTDIR}/clusters-no.txt
    else
        echo -e "${prefix}_${label}" >> ${OUTPUTDIR}/clusters-yes.txt
    fi

    # Clean up
    rm -f ${outputprefix}_{keepmap,Z}.nii.gz

<<<<<<< HEAD
done
=======
# No need to write out this three-variable prefix every ime
outputprefix=${OUTPUTDIR}/${prefix}_${label}

# Extract the Z scr block (we need it either as a "correction failed"
# image  or to overlay corrected images on.
3dAFNItoNIFTI \
    -prefix ${outputprefix}_Z.nii.gz \
    ${inputfile}[${brik}]

# Run the cluster correction
# Take the input (zstat) image, threshold it at zthresh, and save the thresheld
# values to othresh, and save a mask with the voxel size to osize.
cluster \
        --zstat=${outputprefix}_Z.nii.gz  \
        --zthresh=${Z} \
        --othresh=${outputprefix}_clusters \
        --osize=${outputprefix}_osize \
    > ${outputprefix}_clusters.txt

# We need to save only the clusters whose size > $ROIsize_voxel, so create a
# binary mask with which clusters to save.
fslmaths \
    ${outputprefix}_osize \
    -thr ${ROIsize_voxel} \
    -bin \
    ${outputprefix}_keepmap

# Mask vals image to only include large enough clusters and then binarize
# them to create a nice mask
fslmaths ${outputprefix}_clusters.nii.gz \
    -mas ${outputprefix}_keepmap \
    ${outputprefix}_clusters.nii.gz

> ${OUTPUTDIR}/clusters-no.txt
> ${OUTPUTDIR}/clusters-yes.txt
if [[ $(fslstats ${outputprefix}_clusters.nii.gz -M) == "0.000000 " ]]; then
    echo -e "${prefix}_${label}" >> ${OUTPUTDIR}/clusters-no.txt
else
    echo -e "${prefix}_${label}" >> ${OUTPUTDIR}/clusters-yes.txt
fi

# Clean up
rm -f ${outputprefix}_{keepmap,Z}.nii.gz
>>>>>>> master
