#!/bin/bash

# Check to make sure the project configuration files are in the proper location.

errecho () { echo -e "ERROR:\t${1}" ; }

# Check that the config directory exists.
if ! [[ -d analysis ]] ; then
	errecho "analysis/ dir missing, creating for you."
fi

# If the all seeds list exists, check the format, or error if it doesn't exist
if [[ -e analysis/allseeds.txt ]] ; then

	seedsdir=$(head -n1 analysis/allseeds.txt)
	if ! [[ -d ${seedsdir} ]] ; then
		errecho "The seeds directory ${seedsdir} provided by analysis/allseeds.txt does not exist."
	fi

	length=$(cat analysis/allseeds.txt | wc -l)

	if [[ ${length} -lt 2 ]] ; then
		errecho "Too few lines in analysis/allseeds.txt"
	fi

else
	errecho "No allseeds list - can't continue"
fi