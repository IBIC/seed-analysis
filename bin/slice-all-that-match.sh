#!/bin/bash

# Loop over all files given (e.g. a glob) and convert them to a slice with the
# same name but .nii.gz replaced w/ gif extension

input=${@}

echo "Slicing: ${input}"

for i in ${input} ; do

	bn=$(basename ${i} .nii.gz)
	output=$(dirname ${i})/${bn}

	max=$(fslstats ${i} -R | sed 's/^[0-9.-]* //')

	overlay \
		0 1 \
		${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz -a \
		${i} 0.000001 ${max} \
		${output}-overlay.nii.gz

	# If the overlay image fails for whatever reason, give a nice error.
	if ! [[ -e ${output}-overlay.nii.gz ]] ; then
		echo "${bn}: Overlay image not created, input must be empty"
		exit
	else
		# slices \
		# 	${output}-overlay.nii.gz \
		# 	-o ${output}.gif

		# Slicer outputs png, not gif
		slicer \
			${output}-overlay.nii.gz \
			-a ${output}.png
	fi

	rm -f $(dirname ${i})/${bn}-overlay.nii.gz

done