#!/bin/bash

# The function of this script is to take clusters and identify what regions of
# the brain they overlap with.

# This requires you get a "--oindex" file from cluster
files=${*}

for the_file in ${files} ; do

	bn=$(echo ${the_file} | sed -e 's/oindex.nii.gz//')

	# Check to make sure it's the right file
	if [[ ! ${the_file} =~ .*oindex.nii.gz ]] ; then
		echo "The file must be an oindex nifti created with cluster"
		exit 1
	fi

	# Get number of clusters in file
	range=$(fslstats ${the_file} -R)
	max=$(echo ${range} | awk '{print $2}')

	# If the max value is 0, there are no clusters, so skip
	if (( $(echo "${max} == 0" | bc -l) )) ; then
		>&2 echo "Max for ${the_file} is 0, no clusters to check out"
		echo -e "${bn}\tNA\tNA"
		continue
	fi

	# If the max value is > 0, find out what clusters exist
	tmpdir=$(mktemp -d /tmp/cluster-XXXX)
	# echo "Temp directory is ${tmpdir}"

	n_bins=$(echo "${max} + 1" | bc -l)

	# Get the clusters that have voxels by generating a histogram with fslstats,
	# numbering them from 0 (because there will be lots of values with no
	# voxels), then remove lines with 0 voxels, and finally skip the first line
	# (that's 0) and then get just the indices
	clusters=$(fslstats ${the_file} -H ${n_bins} 0 ${max} | \
				paste <(seq 0 ${max}) - | \
				grep -Pv "\t0.000000 $" | \
				tail -n +2 | \
				awk '{print $1}' )

	# Print out the cortical and subcortical matches for every cluster
	# echo ${bn} ${clusters}
	for i in ${clusters} ; do

		# echo "${the_file} cluster ${i}"

		fslmaths \
			${the_file} \
			-thr ${i} -uthr ${i} \
			${tmpdir}/clusters-${i}

		cort=$(atlasquery \
				-a "Harvard-Oxford Cortical Structural Atlas" \
				-m ${tmpdir}/clusters-${i} | tr '\n' ' ')

		scort=$(atlasquery \
				-a "Harvard-Oxford Subcortical Structural Atlas" \
				-m ${tmpdir}/clusters-${i} | tr '\n' ' ')

		echo -e "${bn}\t${i}\t${cort} ${scort}"

	done

done