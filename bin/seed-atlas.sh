#!/bin/bash

# The function of this script is to take clusters and identify what regions of
# the brain they overlap with.

# This requires you get a "--oindex" file from cluster
files=${*}

for the_file in ${files} ; do

	bn=$(echo ${the_file} | sed -e 's/.nii.gz$//')

	# Check to make sure it's the right file
	if [[ ! ${the_file} =~ .*.nii.gz ]] ; then
		echo "The file must be an nifti"
		exit 1
	fi

	# If the max value is > 0, find out what clusters exist
	tmpfile=$(mktemp /tmp/cluster_XXXX)
	>&2 echo "Index file is ${tmpfile}"

	# Must supply a threshold, 1e-6 is the smallest nifti value
	cluster \
		--in=${the_file} 				\
		--thresh=0.000001				\
		--oindex=${tmpfile}-oi.nii.gz 	\
		--othresh=${tmpfile}-ot.nii.gz	> /dev/null

	# Get number of clusters in file
	range=$(fslstats ${tmpfile}-oi -R)
	max=$(echo ${range} | awk '{print $2}')

	# echo ${range}

	# If the max value is 0, there are no clusters, so skip
	if (( $(echo "${max} == 0" | bc -l) )) ; then

		>&2 echo "Max for ${the_file} is 0, no clusters to check out"
		echo -e "${bn}\tNA\tNA\tNA\tNA\tNA\tNA"

	else

		# Print out the cortical and subcortical matches for every cluster
		# echo ${bn} ${clusters}
		for i in $(seq ${max}) ; do

			clustermask=${tmpfile}_${i}.nii.gz
			>&2 echo "Cluster file is ${clustermask}"

			# Extract the i'th cluster from o index file
			fslmaths \
				${tmpfile}-oi			\
				-thr ${i} -uthr ${i} 	\
				-bin					\
				${clustermask}

			# Get the values and mask them
			clustervalues=${tmpfile}-cv
			fslmaths \
				${tmpfile}-ot 		\
				-mul ${clustermask}	\
				${clustervalues}

			# Get the size in voxels
			size_vx=$(fslstats ${clustermask} -V | awk '{print $1}')

			# Get the coordinates of the max voxel, replaces spaces with tabs
			# for output file (includes trailing space)
			coords=$(fslstats ${clustervalues} -x | \
						img2stdcoord \
							-img ${FSLDIR}/data/standard/MNI152_T1_2mm \
							-std ${FSLDIR}/data/standard/MNI152_T1_2mm \
							-vox - |
						sed -e 's/ \+/\t/g')

			cort=$(atlasquery \
					-a "Harvard-Oxford Cortical Structural Atlas" \
					-m ${clustermask} | tr '\n' ' ')

			scort=$(atlasquery \
					-a "Harvard-Oxford Subcortical Structural Atlas" \
					-m ${clustermask} | tr '\n' ' ')

			echo -e "${bn}\t${i}\t${size_vx}\t${coords}\t${cort} ${scort}"

		done

	fi

done