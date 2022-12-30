#! /bin/bash

#############################################################
# Giuseppe Barisano - barisano@stanford.edu
# Xiaodan Liu - xiaodan.liu@ucsf.edu
#############################################################

##### Computing diffusion along perivascular spaces (ALPS) from diffusion-weighted images #####

# REQUIRES: - FSL v. 6.0.3 or newer (https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/FslInstallation)
#						- MRtrix3 (https://www.mrtrix.org/download/)
# This script assumes that FSL and MRtrix3 are in your $PATH.


# initial directories and parameters
#script_folder="${ALPSDIR}"
script_folder="$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}"; )" &> /dev/null && pwd 2> /dev/null; )";

# inputs # 1 or 2 dwi files (if 2, they should be of opposite phase encoding direction, e.g., PA and AP)
# REQUIRED INPUTS
dwi1='' 
bval1=''
bvec1=''

# Optional input for eddy current correction
json1='' # .json files with details about the diffusion sequence. Tested with .json files generated from dcm2niix https://github.com/rordenlab/dcm2niix)

# Optional second dwi inputs (needs to have opposite phase encoding direction and the first volume of both dwi1 and dwi2 must be a B0 image)
dwi2=''
bval2=''
bvec2=''
json2=''

# optional inputs with default options
denoise=1 # perform the denoise and unringing
rois=1 # perform the ROI analysis using the provided ROIs drawn on JHU-ICBM-FA-1mm.nii.gz
template=1 #use the FSL's JHU-ICBM-FA-1mm.nii.gz as template
output_dir_name='alps' # output folder, located in the same folder of the first input


print_usage() {
  printf "Usage: alps.sh \n\
-a DWI \n\
-b BVAL \n\
-c BVEC \n\
-m METADATA (.json file) \n\
-i DWI (second input with opposite phase encoding) \n\
-j BVAL of second input \n\
-k BVEC of second input \n\
-n METADATA (.json file) of second input \n\
-d DENOISING \n\
-r ROIS \n\
-t TEMPLATE \n\
-o OUTPUT_DIR_NAME \n"
  printf "Default values: \n\
	-d DENOISING [default = 1];  0=skip; 1=both denoise and unringing; 2=only denoise; 3=only unringing. \n\
	-r ROIS [default = 1]; 0=skip ROI analysis; 1=ROI analysis with provided ROIs drawn on JHU-ICBM-FA-1mm; 
					alternatively, a list of 4 custom ROI nifti files can be specified.
			ROIs need to be in the following order: 1) LEFT and 2) RIGHT PROJECTION FIBERS (superior corona radiata), 3) LEFT and 4) RIGHT ASSOCIATION FIBERS (superior longitudinal fasciculus)\n\
	-t TEMPLATE [default = 1]; 0=ROI analysis in NATIVE space; 1=ROI analysis with FSL's JHU-ICBM-FA-1mm; alternatively, the user can specify a template to use.
	-o OUTPUT_DIR_NAME [e.g. alps, located in the folder of the (first) input] \n
	\nExample with 1 input: sh alps.sh -a dwi.nii.gz -b id.bval -c id.bvec -m id.json -d 1 -o alps\n\
	\nExample with 2 inputs with opposite phase encoding direction: sh alps.sh -a dwi_PA.nii.gz -b id_PA.bval -c id_PA.bvec -m id_PA.json -i dwi_AP.nii.gz -j id_AP.bval -k id_AP.bvec -n id_AP.json -d 1 -o alps\n"
}

while getopts 'a:b:c:m:i:j:k:n:d:r:o:' flag; do
  case "${flag}" in
    a) dwi1="${OPTARG}" ;;
    b) bval1="${OPTARG}" ;;
    c) bvec1="${OPTARG}" ;;
    m) json1="${OPTARG}" ;;
		i) dwi2="${OPTARG}" ;;
		j) bval2="${OPTARG}" ;;
		k) bvec2="${OPTARG}" ;;
		n) json2="${OPTARG}" ;;
		d) denoise="${OPTARG}" ;;
		r) rois="${OPTARG}" ;;
		t) template="${OPTARG}" ;;
		o) output_dir_name="${OPTARG}" ;;
    *) print_usage
       exit 1 ;;
  esac
done
if [ $OPTIND -eq 1 ]; then echo "ERROR! No options were passed"; print_usage; exit 1; fi
if [ ! $dwi1 ]; then echo "ERROR! input dwi (-a) is not defined."; print_usage; exit 1; fi
if [ ! $bval1 ]; then echo "ERROR! bval (-b) is not defined."; print_usage; exit 1; fi
if [ ! $bvec1 ]; then echo "ERROR! bvec (-c) is not defined."; print_usage; exit 1; fi
#if [ ! $json1 ]; then echo "ERROR! metadata .json file (-m) is not defined."; print_usage; exit 1; fi
if [ $dwi2 ]; then if [ ! $bval2 ] || [ ! $bvec2 ] || [ ! $json2 ]; then echo "ERROR! bval (-j), bvec (-k), and/or metadata .json file (-n) of the second input is/are not defined."; print_usage; exit 1; fi; fi;

study_folder=$(dirname ${dwi1})
if [ -f "${study_folder}/${output_dir_name}/alps.stat/alps.csv" ]; then echo "Final output alps.csv already exists! Remove/rename the output folder in order to re-run the pipeline with input $dwi1"; exit 1; fi;

#running
echo -e "Running ALPS with the following parameters: \n
-a $dwi1 \n
-b $bval1 \n
-c $bvec1 \n
-m $json1 \n
-i $dwi2 \n
-j $bval2 \n
-k $bvec2 \n
-n $json2 \n
-d $denoise \n
-r $rois \n
-t $template \n
-o $output_dir_name"


# create output directory and copy bval and bvec files
echo "create output directory: ${study_folder}/${output_dir_name}"
outdir="${study_folder}/${output_dir_name}"
mkdir -p ${outdir}/alps.stat
cp $bvec1 ${outdir}/bvec1
cp $bval1 ${outdir}/bval1


# 1. PREPROCESSING (Denoising, unringing, Topup for Opposite EPI acquisitions, Eddy)

## Denoising and/or unringing
if [ $denoise -eq 1 ]; then
	echo "Denoising and unringing $dwi1"
	dwidenoise $dwi1 ${outdir}/dwi1.denoised.nii.gz
	mrdegibbs ${outdir}/dwi1.denoised.nii.gz ${outdir}/dwi1.denoised.unring.nii.gz
	dwi1_processed=${outdir}/dwi1.denoised.unring.nii.gz
fi
if [ $denoise -eq 2 ]; then
	echo "Denoising $dwi1"
	dwidenoise $dwi1 ${outdir}/dwi1.denoised.nii.gz
	dwi1_processed=${outdir}/dwi1.denoised.nii.gz
fi
if [ $denoise -eq 3 ]; then
	echo "Unringing $dwi1"
	mrdegibbs $dwi1 ${outdir}/dwi1.unring.nii.gz
	dwi1_processed=${outdir}/dwi1.unring.nii.gz
	rm ${outdir}/dwi1.nii
fi

# IF YOU HAVE A METADATA (JSON) FILE, THEN YOU CAN RUN EDDY
if [ -f ${json1} ]; then
	# ACQUISITION PARAMETERS OF FIRST INPUT (REQUIRED FOR EDDY)
	scanner1=$(jq -r '.Manufacturer' $json1) # -r gives you the raw output
	if [[ "$scanner1" == *"Philips"* ]]
	then
		PEdir1=$(jq -r '.PhaseEncodingAxis' $json1)
		TotalReadoutTime1=0.1 #this assumes that the readout time is identical for all acquisitions on the Philips scanner. A "realistic" read-out time is ~50-100ms (and eddy accepts 10-200ms). So use 0.1 (i.e., 100 ms), not 1.
	else
		PEdir1=$(jq -r '.PhaseEncodingDirection' $json1)
		TotalReadoutTime1=$(jq -r '.TotalReadoutTime' $json1)
	fi
	if [ "$PEdir1" = i ]; then printf "1 0 0 $TotalReadoutTime1" > ${outdir}/acqparams.txt;
	elif [ "$PEdir1" = i- ]; then printf "-1 0 0 $TotalReadoutTime1" > ${outdir}/acqparams.txt;
	elif [ "$PEdir1" = j ]; then printf "0 1 0 $TotalReadoutTime1" > ${outdir}/acqparams.txt;
	elif [ "$PEdir1" = j- ]; then printf "0 -1 0 $TotalReadoutTime1" > ${outdir}/acqparams.txt;
	elif [ "$PEdir1" = k ]; then printf "0 0 1 $TotalReadoutTime1" > ${outdir}/acqparams.txt;
	elif [ "$PEdir1" = k- ]; then printf "0 0 -1 $TotalReadoutTime1" > ${outdir}/acqparams.txt; 
	fi

	#IF YOU HAVE A SECOND DWI
	if [ $dwi2 ]; then
		echo "2nd DWI is available"
		if [[ $dwi2 == *".nii" ]]; then gzip $dwi2; fi
		if [ $denoise -eq 1 ]; then
			echo "Denoising and unringing $dwi2"
			dwidenoise $dwi2 ${outdir}/dwi2.denoised.nii.gz
			mrdegibbs ${outdir}/dwi2.denoised.nii.gz ${outdir}/dwi2.denoised.unring.nii.gz
			dwi2_processed=${outdir}/dwi2.denoised.unring.nii.gz
		fi
		if [ $denoise -eq 2 ]; then
			echo "Denoising $dwi2"
			dwidenoise $dwi2 ${outdir}/dwi2.denoised.nii.gz
			dwi2_processed=${outdir}/dwi2.denoised.nii.gz
		fi
		if [ $denoise -eq 3 ]; then
			echo "Unringing $dwi2"
			mrdegibbs $dwi2 ${outdir}/dwi2.unring.nii.gz
			dwi2_processed=${outdir}/dwi2.unring.nii.gz
		fi
		
		##
		scanner2=$(jq -r '.Manufacturer' $json2)
		if [[ "$scanner2" == *"Philips"* ]]
		then
			PEdir2=$(jq -r '.PhaseEncodingAxis' $json2)- #added "-" to make it opposite to the PEdir1. #Philips scans json files generated with dcm2niix have a problem where the PEdirection is the same (j) even though it is not.
			TotalReadoutTime2=0.1 #this assumes that the readout time is identical for all acquisitions on the Philips scanner. A "realistic" read-out time is ~50-100ms (and eddy accepts 10-200ms). So use 0.1 (i.e., 100 ms), not 1.
		else
			PEdir2=$(jq -r '.PhaseEncodingDirection' $json2)
			TotalReadoutTime2=$(jq -r '.TotalReadoutTime' $json2)
		fi

		# ACQUISITION PARAMETERS (ADDED TO THE PREVIOUS FILE)
		if [ "$PEdir2" = i ]; then printf "\n1 0 0 $TotalReadoutTime2" >> ${outdir}/acqparams.txt;
		elif [ "$PEdir2" = i- ]; then printf "\n-1 0 0 $TotalReadoutTime2" >> ${outdir}/acqparams.txt;
		elif [ "$PEdir2" = j ]; then printf "\n0 1 0 $TotalReadoutTime2" >> ${outdir}/acqparams.txt;
		elif [ "$PEdir2" = j- ]; then printf "\n0 -1 0 $TotalReadoutTime2" >> ${outdir}/acqparams.txt;
		elif [ "$PEdir2" = k ]; then printf "\n0 0 1 $TotalReadoutTime2" >> ${outdir}/acqparams.txt;
		elif [ "$PEdir2" = k- ]; then printf "\n0 0 -1 $TotalReadoutTime2" >> ${outdir}/acqparams.txt; 
		fi


		#TOPUP (only if PEdir1 = PEdir2- and both DWI datasets have B0 images as first volume)
		b0_dwi1=`head -c 1 $bval1`
		b0_dwi2=`head -c 1 $bval2`
		if [ "${PEdir1}" == "${PEdir2}-" ] || [ "${PEdir2}" == "${PEdir1}-" ] && ([ "${b0_dwi1}" == "${b0_dwi2}" ] && [ "${b0_dwi1}" == "0" ]);
		then
			b0_1=${outdir}/b0_first_direction.nii.gz
			b0_2=${outdir}/b0_second_direction.nii.gz
			fslroi $dwi1_processed $b0_1 0 1
			fslroi $dwi2_processed $b0_2 0 1
			
			#check dimensions of b0_1 and b0_2 because sometimes they are different and needs to be coregistered for fslmerge to work
			dim1_1=`fslhd $b0_1 | grep dim1 | tr -s ' ' | cut -d " " -f2 | head -n 1` #tr with the squeeze option makes all consecutive whitespaces equal to 1 whitespace
			dim2_1=`fslhd $b0_1 | grep dim2 | tr -s ' ' | cut -d " " -f2 | head -n 1` #tr with the squeeze option makes all consecutive whitespaces equal to 1 whitespace
			dim3_1=`fslhd $b0_1 | grep dim3 | tr -s ' ' | cut -d " " -f2 | head -n 1` #tr with the squeeze option makes all consecutive whitespaces equal to 1 whitespace
			dim1_2=`fslhd $b0_2 | grep dim1 | tr -s ' ' | cut -d " " -f2 | head -n 1` #tr with the squeeze option makes all consecutive whitespaces equal to 1 whitespace
			dim2_2=`fslhd $b0_2 | grep dim2 | tr -s ' ' | cut -d " " -f2 | head -n 1` #tr with the squeeze option makes all consecutive whitespaces equal to 1 whitespace
			dim3_2=`fslhd $b0_2 | grep dim3 | tr -s ' ' | cut -d " " -f2 | head -n 1` #tr with the squeeze option makes all consecutive whitespaces equal to 1 whitespace
			if [ "${dim1_1}" != "${dim1_2}" ] || [ "${dim2_1}" != "${dim2_2}" ] || [ "${dim3_1}" != "${dim3_2}" ]; 
			then
				flirt -in ${b0_2} -ref ${b0_1} -out ${outdir}/b0_second_direction_reg -omat ${outdir}/b0_2.in.b0_1.mat -bins 256 -cost corratio -searchrx -90 90 -searchry -90 90 -searchrz -90 90 -dof 6
				b0_2=${outdir}/b0_second_direction_reg.nii.gz
				echo "b0_2 registered to b0_1"
			fi

			fslmerge -t ${outdir}/both_b0 $b0_1 $b0_2
			cd ${outdir}
			temp=`fslhd ${dwi1} | grep dim3`
			dimtmp=( $temp )
			n_slices=${dimtmp[1]}
			echo "Running FSL TOPUP"
			if [ $((n_slices%2)) -eq 0 ] #even number of slices
			then
				topup --imain=both_b0 --datain=acqparams.txt --config=b02b0.cnf --out=my_topup_results --iout=my_hifi_b0 #which will upon completion create the two files my_topup_results_fieldcoef.nii.gz (an estimate of the susceptibility induced off-resonance field), my_topup_results_movpar.txt and the non-distorted space my_hifi_b0.nii.gz
			else #odd number of slices, use a different configuration file (https://www.jiscmail.ac.uk/cgi-bin/webadmin?A2=FSL;6c4c9591.2002)
				topup --imain=both_b0 --datain=acqparams.txt --config=${FSLDIR}/src/topup/flirtsch/b02b0_1.cnf --out=my_topup_results --iout=my_hifi_b0 #which will upon completion create the two files my_topup_results_fieldcoef.nii.gz (an estimate of the susceptibility induced off-resonance field), my_topup_results_movpar.txt and the non-distorted space my_hifi_b0.nii.gz
			fi
			# Processing of topup output
			fslmaths my_hifi_b0 -Tmean my_hifi_b0
			bet2 my_hifi_b0 b0_brain -m

			#EDDY
			echo "Running EDDY with TOPUP RESULTS"
			temp=`fslhd ${dwi1} | grep dim4`
			dimtmp=( $temp )
			n_vol=${dimtmp[1]}
			indx=""
			for ((i=1; i<=$n_vol; i+=1)); do indx="$indx 1"; done
			echo $indx > index.txt
			eddy_openmp --imain=$dwi1_processed --mask=b0_brain_mask --acqp=acqparams.txt --index=index.txt --bvecs=bvec1 --bvals=bval1 --topup=my_topup_results --out=eddy_corrected_data
		elif [ "${PEdir1}" != "${PEdir2}-" ] || [ "${PEdir2}" != "${PEdir1}-" ] || [ "${b0_dwi1}" != "${b0_dwi2}" ]; then
			cd ${outdir}
			fslroi $dwi1_processed ${outdir}/b0 0 1
			bet2 ${outdir}/b0 ${outdir}/b0_brain -m
			#EDDY
			echo "Running EDDY (NO TOPUP) because PE directions are not opposite or b0 images are different"
			temp=`fslhd ${dwi1} | grep dim4`
			dimtmp=( $temp )
			n_vol=${dimtmp[1]}
			indx=""
			for ((i=1; i<=$n_vol; i+=1)); do indx="$indx 1"; done
			echo $indx > index.txt
			eddy_openmp --imain=$dwi1_processed --mask=b0_brain_mask --acqp=acqparams.txt --index=index.txt --bvecs=bvec1 --bvals=bval1 --out=eddy_corrected_data	
		fi
	elif [ ! $dwi2 ]; then
		cd ${outdir}
		fslroi $dwi1_processed ${outdir}/b0 0 1
		bet2 ${outdir}/b0 ${outdir}/b0_brain -m
		#EDDY
		echo "Running EDDY only (NO TOPUP) because there is no dwi2"
		temp=`fslhd ${dwi1} | grep dim4`
		dimtmp=( $temp )
		n_vol=${dimtmp[1]}
		indx=""
		for ((i=1; i<=$n_vol; i+=1)); do indx="$indx 1"; done
		echo $indx > index.txt
		eddy_openmp --imain=$dwi1_processed --mask=b0_brain_mask --acqp=acqparams.txt --index=index.txt --bvecs=bvec1 --bvals=bval1 --out=eddy_corrected_data
	fi
fi


# 2. FIT TENSOR
if [ -f "${outdir}/eddy_corrected_data.nii.gz" ]; then
	echo "starting DTI FITTING on eddy corrected data"
	dtifit --data=eddy_corrected_data.nii.gz --out=dti --mask=b0_brain_mask.nii.gz --bvecs=bvec1 --bvals=bval1 --save_tensor
else
	if [ -f "${dwi1_processed}" ]; then
		echo "starting DTI FITTING on preprocessed diffusion data (denoised and/or unringed, NO TOPUP, NO eddy correction)"
		dtifit --data=${dwi1_processed} --out=dti --mask=b0_brain_mask.nii.gz --bvecs=bvec1 --bvals=bval1 --save_tensor
	else
		echo "starting DTI FITTING on input diffusion data (NO preprocessing (denoising/unringing), NO TOPUP, NO eddy correction)"
		dtifit --data=${dwi1} --out=dti --mask=b0_brain_mask.nii.gz --bvecs=bvec1 --bvals=bval1 --save_tensor
	fi
fi

echo "DTI FITTING completed!"
fslsplit ${outdir}/dti_tensor.nii.gz 
cp ${outdir}/vol0000.nii.gz ${outdir}/dxx.nii.gz 
cp ${outdir}/vol0003.nii.gz ${outdir}/dyy.nii.gz 
cp ${outdir}/vol0005.nii.gz ${outdir}/dzz.nii.gz 

# 3. ROI ANALYSIS
if [ $rois -ne 0 ]
then
	#ROIs
	if [ $rois -eq 1 ]
	then
		echo "ROI analysis with default ROIs"
		rois="${script_folder}/ROIs_JHU_ALPS/L_SCR.nii.gz ${script_folder}/ROIs_JHU_ALPS/R_SCR.nii.gz ${script_folder}/ROIs_JHU_ALPS/L_SLF.nii.gz ${script_folder}/ROIs_JHU_ALPS/R_SLF.nii.gz"
	else
		echo "ROI analysis with user-defined ROIs: $rois"
	fi
	proj_L=`echo $rois | cut -d " " -f1`
	proj_R=`echo $rois | cut -d " " -f2`
	assoc_L=`echo $rois | cut -d " " -f3`
	assoc_R=`echo $rois | cut -d " " -f4`
	echo "starting ROI analysis with projection fibers $(basename $proj_L) (LEFT) and $(basename $proj_R) (RIGHT), and association fibers $(basename $assoc_L) (LEFT) and $(basename $assoc_R) (RIGHT)"
	#TEMPLATE
	if [ $template -ne 0 ]; then #analysis in template space
		if [ $template -eq 1 ]; then
			echo "Default template: JHU-ICBM-FA-1mm.nii.gz"
			template=${FSLDIR}/data/atlases/JHU/JHU-ICBM-FA-1mm.nii.gz
			template_abbreviation=JHU-FA
		else
			echo "User specified template: $template"
			template_abbreviation=template
		fi
		flirt -in ${outdir}/dti_FA.nii.gz -ref ${template} -out ${outdir}/dti_FA_to_${template_abbreviation}.nii.gz -omat ${outdir}/FA_to_${template_abbreviation}.mat -bins 256 -cost corratio -searchrx -90 90 -searchry -90 90 -searchrz -90 90 -dof 12
		flirt -in ${outdir}/dxx.nii.gz -ref ${template} -out ${outdir}/dxx_in_${template_abbreviation}.nii.gz -init ${outdir}/FA_to_${template_abbreviation}.mat -applyxfm
		flirt -in ${outdir}/dyy.nii.gz -ref ${template} -out ${outdir}/dyy_in_${template_abbreviation}.nii.gz -init ${outdir}/FA_to_${template_abbreviation}.mat -applyxfm
		flirt -in ${outdir}/dzz.nii.gz -ref ${template} -out ${outdir}/dzz_in_${template_abbreviation}.nii.gz -init ${outdir}/FA_to_${template_abbreviation}.mat -applyxfm
		dxx=${outdir}/dxx_in_${template_abbreviation}.nii.gz
		dyy=${outdir}/dyy_in_${template_abbreviation}.nii.gz
		dzz=${outdir}/dzz_in_${template_abbreviation}.nii.gz
	elif [ $template -eq 0 ]; then #analysis in native space
		dxx=${outdir}/dxx.nii.gz
		dyy=${outdir}/dyy.nii.gz
		dzz=${outdir}/dzz.nii.gz
	fi

	
	#GATHER STATS
	echo "id,scanner,x_proj_L,x_assoc_L,y_proj_L,z_assoc_L,x_proj_R,x_assoc_R,y_proj_R,z_assoc_R,alps_L,alps_R,alps" > ${outdir}/alps.stat/alps.csv
	
	if [[ $dwi1 == *".nii" ]]; then 
		id=$(basename $dwi1 .nii)
	elif [[ $dwi1 == *".nii.gz" ]]; then
		id=$(basename $dwi1 .nii.gz)
	fi

	x_proj_L="$(fslstats ${dxx} -k $proj_L -m)"
	x_assoc_L="$(fslstats ${dxx} -k $assoc_L -m)"
	y_proj_L="$(fslstats ${dyy} -k $proj_L -m)"
	z_assoc_L="$(fslstats ${dzz} -k $assoc_L -m)"
	x_proj_R="$(fslstats ${dxx} -k $proj_R -m)"
	x_assoc_R="$(fslstats ${dxx} -k $assoc_R -m)"
	y_proj_R="$(fslstats ${dyy} -k $proj_R -m)"
	z_assoc_R="$(fslstats ${dzz} -k $assoc_R -m)"
	alps_L=`echo "(($x_proj_L+$x_assoc_L)/2)/(($y_proj_L+$z_assoc_L)/2)" | bc -l` #proj1 and assoc1 are left side, bc -l needed for decimal printing results
	alps_R=`echo "(($x_proj_R+$x_assoc_R)/2)/(($y_proj_R+$z_assoc_R)/2)" | bc -l` #proj2 and assoc2 are right side, bc -l needed for decimal printing results
	alps=`echo "($alps_R+$alps_L)/2" | bc -l`

	echo "${id},${scanner1},${x_proj_L},${x_assoc_L},${y_proj_L},${z_assoc_L},${x_proj_R},${x_assoc_R},${y_proj_R},${z_assoc_R},${alps_L},${alps_R},${alps}" >> ${outdir}/alps.stat/alps.csv
elif [ $rois -eq 0 ]
	then echo "ROI analysis skipped by the user.";
fi

echo "Finito! Please cite ..."



