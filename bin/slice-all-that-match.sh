#!/bin/bash

# Loop over all files given (e.g. a glob) and convert them to a slice with the
# same name but .nii.gz replaced w/ png extension

input=${@}

for i in ${input} ; do
	bn=$(basename ${i} .nii.gz)

	slices ${i} \
		-o $(dirname ${i})/${bn}.png
done