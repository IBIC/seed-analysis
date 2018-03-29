#!/bin/bash

# Loop over all files given (e.g. a glob) and convert them to a slice with the
# same name but .nii.gz replaced w/ gif extension

input=${@}

echo "Slicing: ${input}"

for i in ${input} ; do
	bn=$(basename ${i} .nii.gz)
	output=$(dirname ${i})/${bn}

	max=$(fslstats ${i} -R | sed 's/^[0-9.]* //')

	overlay \
		0 1 \
		${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz -a \
		${i} 0.1 ${max} \
		${output}-overlay.nii.gz

	slices \
		${output}-overlay.nii.gz \
		-o ${output}.gif

	rm -f $(dirname ${i})/${bn}-overlay.nii.gz
done