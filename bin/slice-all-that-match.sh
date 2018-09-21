#!/bin/bash

# Loop over all files given (e.g. a glob) and convert them to a slice with the
# same name but .nii.gz replaced w/ gif extension

input=${@}

echo "Slicing: ${input}"

for i in ${input} ; do

	bn=$(basename ${i} .nii.gz)
	output=$(dirname ${i})/${bn}

	max=$(fslstats ${i} -r | sed -e 's/^[0-9.-]* //' -e 's/\s//')

	# If the image isn't all 0s
	if [[ ${max} != "0.000000" ]] ; then

		overlay \
			0 1 \
			${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz -a \
			${i} 0.1 ${max} \
			${output}-overlay.nii.gz

		# If the overlay image fails for whatever reason, give a nice error.
		if ! [[ -e ${output}-overlay.nii.gz ]] ; then
			echo "${bn}: Overlay image not created"
			exit 1
		else
			# Slicer outputs png, not gif
			slicer \
				${output}-overlay.nii.gz \
				-a ${output}.png
		fi

	else
		# If it is all 0s, take pictures of the template for illustrative
		# reasons
		slicer \
			${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz  \
			-a ${output}.png

	fi

	rm -f $(dirname ${i})/${bn}-overlay.nii.gz

done