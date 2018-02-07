#!/bin/bash

SUBJECTS_DIR=/mnt/praxic/pdnetworksr01/subjects

MEICA=mefc

SUFFIX=_reoriented

# Generate PD/Control lists for three scan types
SUBJECTS=${SUBJECTS_DIR}/1?????

echo "There are $(echo ${SUBJECTS} | wc -w) subjects"

# Make empty files
for i in group-{C,PD}{a,m,r}.txt
do
	> ${i}
done

# Loop over scan types
for s in a m r
do
	# Expand scan names
	if [[ ${s} == "a" ]]; then
		scan=mcvsa
	elif [[ ${s} == "m" ]]; then
		scan=mcvsm
	else
		scan=mrest
	fi

	# Loop over subjects
	for subj in ${SUBJECTS_DIR}/1?????
	do
		group=$(cat ${subj}/session1/0_group)
		svcdir=${subj}/session1/${scan}/SVC_MEICA

		if [[ ${group} == CONTROL ]]; then
			g=C
		else
			g=PD
		fi

		if [[ -d ${svcdir} ]]; then
			id=$(echo ${subj} | grep -o [0-9][0-9][0-9][0-9][0-9][0-9])
			echo "${id} ${svcdir}/" >> group-${g}${s}.txt
		fi
	done
done

wc -l group-*.txt