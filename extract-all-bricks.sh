#!/bin/bash

function usage {
	echo "./extract-all-bricks.sh <output directory> BRIK1[, BRIK2[, ...]]"
	echo "All BRIK files must have corresponding HEAD files."
}


# Check that there are input files
if [ ${#} -lt 2 ] ; then
	echo "Must input at least one BRIK file!"
	usage
	exit 1
fi

# Get files
outputdir=${1} ; shift
inputfiles=${@}

mkdir -p ${outputdir}

# Loop over each of the input files
for ifile in ${inputfiles}
do
	# Skip this file if it isn't a brik file
	if [[ ! ${ifile} =~ .*BRIK ]]; then
		>&2 echo "${ifile} isn't a BRIK file!"
		continue
	fi

	# Make sure that the appropriate HEAD file exists, and skip that BRIK file
	# if it doesn't.
	if [[ ! -e ${ifile%.BRIK}.HEAD ]]; then
		>&2 echo "There is no ${ifile%.BRIK}.HEAD file, exiting."
		continue
	fi

	# Get the max brick index (N - 1)
	maxbrikindex=$(3dinfo -nvi ${ifile})

	# Get label array
	labels=($(echo $(3dinfo -label ${ifile} | sed 's/|/ /g')))

	# ROI
	roi=$(basename ${ifile} | sed 's/\+.*.BRIK//')

	# Extract the brick with the label for that brik
	# Is there a better way to do this?
	for i in $(seq 0 ${maxbrikindex})
	do
	 	3dAFNItoNIFTI \
			-prefix ${outputdir}/${roi}_${labels[$i]}.nii.gz \
			${ifile}[${i}]
	done
done