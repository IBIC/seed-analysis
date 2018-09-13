#!/bin/bash

function usage {
    echo "./${0} [-a A] [-Ddh] [-n N] [-1/2] -i <input prefix> -o <output dir>"
    echo
    echo -e "\t-i\tInput prefix. Path to HEAD/BRIK w/o +{orig,tlrc}.{HEAD,BRIK}"
    echo -e "\t-o\tOutput directory"
    echo -e "\t-h\tDisplay this help info."
    echo -e "->\t-D\tGROUP MODE toggle"
    echo
    echo    "OPTIONAL:"
    echo -e "\t-1\tUse a 1-sided t-test (default)"
    echo -e "\t-2\tUse a 2-sided t-test"
    echo -e "\t-a\tSet custom alpha value (default .5)"
    echo -e "\t-d\tOverride degrees of freedom (calculated by default)"
    echo -e "\t-h\tDisplay this help menu"
    echo -e "\t-k\tKeep intermediate files"
    echo -e "\t-n\tWhich neighbor method (1-3, default 1)"
}

# Default alpha value
ALPHA=.05

# Default clustering method (1-3)
NMODE=3

# Default t-test sidedness; 1 is more conservative than 2
SIDED=1

while getopts ":12a:Dd:hi:kn:o:" opt ; do
    case ${opt} in
        1)
            SIDED=1
            echo "Using 1-sided t-test (default)" ;;
        2)
            SIDED=2
            echo "Using 2-sided t-test" ;;
        a)
            ALPHA=${OPTARG} ;;
        D)
            DIFFMODE="yes" ;;
        d)
            if [[ ${OPTARG} =~ ^[0-9]+ ]] ; then
                echo "Override DoF: ${OPTARG}"
                DEGREESOFFREEDOM=${OPTARG}
            elif [[ ${OPTARG} = "-1" ]] ; then
                echo "** cluster-correct.sh is estimating degrees of freedom."
                DEGREESOFFREEDOM=""
            else
                echo -n "Illegal degrees of freedom: Must be positive integer"
                echo    " or pass -1 to calculate."
                usage
                exit 1
            fi ;;
        h)
            usage
            exit 1 ;;
        i)
            # Check that input file exists
            if find . -wholename "${INPUT}+????.BRIK" ; then
                INPUT=${OPTARG}
                echo "Input prefix is ${INPUT}"
            else
                echo "Input file ${OPTARG}+????.BRIK is missing."
            fi
            ;;
        k)
            KEEP="yes" ;;
        o)
            OUTPUTDIR=${OPTARG}
            echo "Output dir is ${OUTPUTDIR}" ;;
        n)
            if ! [[ ${OPTARG} =~ [1-3] ]]; then
                NMODE=${OPTARG}
            else
                echo "Illegal N mode: 1-3 only"
                usage
                exit 1
            fi ;;
    esac
done

if [[ ${INPUT} == "" ]] || [[ ${OUTPUTDIR} == "" ]] ; then
    echo "Both input and output dir must be minimally supplied"
    echo
    usage
    exit 1
fi

# Clear +tlrc/orig from input, just as a helper function
INPUT=$(echo ${INPUT} | sed -e 's/+tlrc//' -e 's/+orig//')

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
ttest=$(dirname ${INPUT})/*.${prefix}.CSimA.NN${NMODE}_${SIDED}sided.1D
p05=$(grep "^ 0.050000" ${ttest})

# echo ${ttest} ; exit

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

# Get the DoF differentially based on whether this is a group or single-group
# analysis
if [[ ${DEGREESOFFREEDOM} == "" ]]  ; then
    if [[ ${DIFFMODE} == "yes" ]] ; then
        # Get the DoF by counting the number of subjects in each group and
        # subtracting two (for each group)
        contrasts=($(echo ${labels[0]} | sed -e 's/_mean//' -e 's/-/ /'))
        dof=$(( $(wc -l < group-${contrasts[0]}.txt) + \
                $(wc -l < group-${contrasts[1]}.txt) - 2 ))
    else
        # Degrees of freedom for one group is n - 1
        group=$(echo ${labels[0]} | sed 's/_mean//')
        dof=$(( $(wc -l < group-${group}.txt) - 1 ))
    fi

    echo "** DoF calculated as: ${dof}"
else
    dof=${DEGREESOFFREEDOM}
    echo "** Using DoF: ${dof}"
fi

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

    # Convert from DoF to a Z score using a p-val of <.05 using a 1-sided
    # t-test
    # Unfortunately, EOF) has to be unindented awkwardly like this.
    Z=$(R --no-save --slave <<-EOF
        cat(qt(.05, ${dof}, lower.tail = FALSE))
EOF
)

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

    # Remove it here before we forget
    rm ${outputprefix}_Z-inv.nii.gz

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

    done

    if [[ $(fslstats ${outputprefix}_posclusters.nii.gz -M) == "0.000000 " ]]
    then
        echo -e "${prefix}_${label}" >> ${OUTPUTDIR}/pos-clusters-no.txt
    else
        echo -e "${prefix}_${label}" >> ${OUTPUTDIR}/pos-clusters-yes.txt
    fi

    if [[ $(fslstats ${outputprefix}_negclusters.nii.gz -M) == "0.000000 " ]]
    then
        echo -e "${prefix}_${label}" >> ${OUTPUTDIR}/neg-clusters-no.txt
    else
        echo -e "${prefix}_${label}" >> ${OUTPUTDIR}/neg-clusters-yes.txt
    fi

    # Clean up
    if [[ ${KEEP} != "yes" ]] ; then
        rm -f ${outputprefix}_*{keepmap,Z,osize}.nii.gz
    fi

done