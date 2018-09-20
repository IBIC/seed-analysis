#!/bin/bash

# Define the help function for easy calling later
function usage {
    echo "./${0} [-a A] [-Dh] [-n N] [-1/2] -i <prefix> -d n -o <dir>"
    echo
    echo -e "\t-i\tInput prefix. Path to HEAD/BRIK w/o +{orig,tlrc}.{HEAD,BRIK}"
    echo -e "\t-d\tSet the degrees of freedom (NOW mandatory)"
    echo -e "\t-o\tOutput directory"
    echo -e "->\t-D\tGROUP MODE toggle"
    echo
    echo    "OPTIONAL:"
    echo -e "\t-1\tUse a 1-sided t-test"
    echo -e "\t-2\tUse a 2-sided t-test (default)"
    echo -e "\t-a\tSet custom alpha value (default .5)"
    echo -e "\t-h\tDisplay this help menu"
    echo -e "\t-k\tKeep intermediate files"
    echo -e "\t-n\tWhich neighbor method (1-3, default 3)"

    exit ${1}
}

# Define a function ro report values as we loop over
function report_value {
    echo -e "%--- ${1}: ${2}"
}

# Default alpha value
ALPHA=.05

# Default clustering method (1-3)
NMODE=3

# Default t-test sidedness; 1 is more conservative than 2
SIDED=2

while getopts ":12a:Dd:hi:kn:o:" opt ; do
    case ${opt} in
        1)
            SIDED=1 ;;
        2)
            SIDED=2 ;;
        a)
            ALPHA=${OPTARG} ;;
        D)
            DIFFMODE="yes" ;;
        d)
            if [[ ${OPTARG} =~ ^[0-9]+ ]] ; then
                DOF=${OPTARG}
                report_value "dof" ${DOF}
            else
                echo "Illegal degrees of freedom: Must be positive integer."
                echo
                usage 1
            fi ;;
        h)
            # Print usage, quit cleanly (help is expected behavior)
            usage 0 ;;
        i)
            # Check that input file exists
            if find . -wholename "${INPUT}+????.BRIK" ; then
                INPUT=${OPTARG}
                report_value "input prefix" ${INPUT}
            else
                echo "Input file ${OPTARG}+????.BRIK is missing."
            fi
            ;;
        k)
            KEEP="yes" ;;
        o)
            OUTPUTDIR=${OPTARG}
            mkdir -p ${OUTPUTDIR}
            report_value "output directory" ${OUTPUTDIR} ;;
        n)
            if ! [[ ${OPTARG} =~ [1-3] ]]; then
                NMODE=${OPTARG}
            else
                echo "Illegal N mode: 1-3 only"
                usage 1
            fi ;;
    esac
done

report_value "neighbor" ${NMODE}
report_value "alpha"    ${ALPHA}
report_value "t-test"   ${SIDED}"-sided"

# Check that both input and output were given
if [[ ${INPUT} == "" ]] || [[ ${OUTPUTDIR} == "" ]] ; then
    echo "Both input and output dir must be minimally supplied."
    echo
    usage 1
fi

# Check that degrees of freedom was given
if [[ ${DOF} == "" ]] ; then
    echo "Degrees of freedom must be supplied."
    echo
    usage 1
fi

# Clear +tlrc/orig from input, just as a helper function, in case they forget
# to take it out
INPUT=$(echo ${INPUT} | sed -e 's/+tlrc//' -e 's/+orig//')
prefix=$(basename ${INPUT})

# Find the input file. The suffix (????) could be either tlrc or orig, so check
# for both
inputfile=$(find $(dirname ${INPUT}) -name "${prefix}+????.BRIK")

# Get the maximum brik index (0-indexed)
maxbrikindex=$(3dinfo -nvi ${inputfile})
report_value "Max brik index" ${maxbrikindex}

# Get the minimum cluster size
# The t-test info is in this 1D file
ttest=$(dirname ${INPUT})/*.${prefix}.CSimA.NN${NMODE}_${SIDED}sided.1D
p05=$(grep "^ 0.050000" ${ttest})

# echo ${ttest} ; exit

# Convert from alpha value to column (columns go NA, 0.1 ... 0.01)
column=$(echo "${ALPHA} * -100 + 12" | bc | sed 's/.00//')

# Get the ROI size in voxels
ROIsize_voxel=$(echo ${p05} | awk "{print \$${column}}")
report_value "ROI size (vx)" ${ROIsize_voxel}

# The second brik is always the one that we want - for a single group, it's the
# Z score, and for a groupdiff, it goes diff, diff z, group 1, group 1 Z ...
# BRIKs are 0-indexed, so the 2nd is 1
# brik=1

# Get the corresponding label (we need to know whether this is a diff or single
# group BRIK)
labels=($(3dinfo -label ${INPUT} | sed 's/|/ /g'))

# Convert from DoF to a Z score using a p-val of <.05 using a 1 or 2 sided
# t-test
# Unfortunately, EOF) has to be indented awkwardly like this.
if [ ${SIDED} -eq 2 ] ; then
Z=$(R --no-save --slave <<-EOF
    cat(qt(.05, ${DOF}, lower.tail = TRUE))
EOF
)
elif [ ${SIDED} -eq 1 ] ; then
Z=$(R --no-save --slave <<-EOF
    cat(qt(.05, ${DOF}, lower.tail = FALSE))
EOF
)
fi

report_value "Z" ${Z}

# Loop over every other brik, Zscr bricks are all the odd briks
# Clear the files that keep track of which clusters are good/nonexistent
> ${OUTPUTDIR}/pos-clusters-no.txt
> ${OUTPUTDIR}/pos-clusters-yes.txt
> ${OUTPUTDIR}/neg-clusters-no.txt
> ${OUTPUTDIR}/neg-clusters-yes.txt
for brik in $(seq 1 2 ${maxbrikindex}) ; do

    # Which label are we working on?
    label=$(echo ${labels[${brik}]} | sed 's/_Zscr//') ; echo -n "${label}"
    outputprefix=${OUTPUTDIR}/${prefix}_${label}

    # If we're in diff mode and the label doesn't have a - (i.e. it's one of
    # the single-groups, skip it)
    if ! [[ ${label} =~ .*-.* ]] && [[ ${DIFFMODE} == "yes" ]] ; then
        echo ": skipping"
        continue
    else
        # If we didn't echo ": skipping", add a newline for pretty output
        echo
    fi

    # Extract the Z scr block (we need it either as a "correction failed"
    # image  or to overlay corrected images on.
    3dAFNItoNIFTI \
        -prefix ${outputprefix}_Z.nii.gz \
        ${inputfile}[${brik}]

    # Run the cluster correction
    # Take the input (zstat) image, threshold it at zthresh, and save the
    # thresheld values to othresh, and save a mask with the voxel size to osize.
    cluster \
        --zstat=${outputprefix}_Z.nii.gz  \
        --zthresh=${Z} \
        --othresh=${outputprefix}_posclusters \
        --osize=${outputprefix}_pososize \
    > ${outputprefix}_posclusters.txt

    # Cluster doesn't seem to like clustering negative values, so invert the
    # Z map, then cluster

    # For some reason, when you multiply by -1, you get a minimum value of -0,
    # which screws up later processing. Here, we threshold at the lowest value
    # possible to get back to a minimum of regular 0.
    fslmaths \
        ${outputprefix}_Z.nii.gz \
        -mul -1 -thr 0.000001 \
        ${outputprefix}_Z-inv.nii.gz

    # Run cluster on the inverted, treshheld data.
    cluster \
        --zstat=${outputprefix}_Z-inv.nii.gz  \
        --zthresh=${Z} \
        --othresh=${outputprefix}_negclusters \
        --osize=${outputprefix}_negosize \
    > ${outputprefix}_negclusters.txt

    # The following steps are the same for both negative and positive, so wrap
    # in a for loop for conciseness
    for sign in neg pos ; do

        # We need to save only the clusters whose size > $ROIsize_voxel, so
        # create a binary mask with which clusters to save for both directions.
        fslmaths \
            ${outputprefix}_${sign}osize \
            -thr ${ROIsize_voxel} \
            -bin \
            ${outputprefix}_${sign}keepmap

        # Mask clusters image to only include large enough clusters and then
        # binarize them to create a nice mask
        fslmaths ${outputprefix}_${sign}clusters.nii.gz \
            -mas ${outputprefix}_${sign}keepmap \
            ${outputprefix}_${sign}clusters.nii.gz

        # Is the mean of the cluster image 0? If so, save it to no text file,
        # else, save it to the yes file
        mean=$(fslstats ${outputprefix}_${sign}clusters.nii.gz -M)
        if [[ ${mean} == "0.000000 " ]]
        then
            echo -e "${prefix}_${label}" >> ${OUTPUTDIR}/${sign}-clusters-no.txt
        else
            echo -e "${prefix}_${label}" >> \
                ${OUTPUTDIR}/${sign}-clusters-yes.txt
        fi

    done

    # Clean up
    if [[ ${KEEP} != "yes" ]] ; then
        rm -f ${outputprefix}_*{keepmap,Z,osize,Z-inv}.nii.gz
    fi

done
