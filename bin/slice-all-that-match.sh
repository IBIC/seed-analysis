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
		${i} 0.0001 ${max} \
		${output}-overlay.nii.gz

	# If the overlay image fails for whatever reason, give a nice error.
	if ! [[ -e ${output}-overlay.nii.gz ]] ; then
		echo "${bn}: Overlay image not created, input must be empty"
		exit
	else

		# Get the mean of the image, removing whitespace
		clustersmean=$(fslstats ${i} -m | tr -d '[:space:]')

		# If there are clusters (i.e. the image mean is not 0), then take a
		# picture of the overlay
		if [[ ${clustersmean} != "0.000000" ]] ; then

			slicer \
				${output}-overlay.nii.gz \
				-a ${output}.png

		else

			temp=$(mktemp XXXX.png)

			# Otherwise, take a picture of the MNI template for placeholding
			# purposes
			slicer \
				${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz \
				-a ${temp}

			convert \
				${temp} \
				-gravity   center \
				-pointsize 30     \
				-fill      red    \
				-annotate  +0+0 "EMPTY" \
				${output}.png

			# Clean up
			rm ${temp}

		fi

	fi

	# Clean up
	rm -f $(dirname ${i})/${bn}-overlay.nii.gz

done