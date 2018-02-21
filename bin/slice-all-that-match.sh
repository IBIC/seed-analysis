#!/bin/bash

input=${@}

for i in ${input} ; do
	bn=$(basename ${i} .nii.gz)

	slices ${i} -o $(dirname ${i})/${bn}.png
done