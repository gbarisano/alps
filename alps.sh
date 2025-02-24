#! /bin/bash

#############################################################
# Giuseppe Barisano - barisano@stanford.edu
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
template=1 #use the FSL's JHU-ICBM-FA-1mm.nii.gz as FA template or FSL's MNI template if the structural MRI data is provided. 
skip=0 #perform all the steps of the pipeline. 
eddy=1 #try to use eddy_cpu
warp=0 #perform linear registration of the FA map to the template.
freg=1 #if the analysis is done on template space, by default it will use FSL's flirt or applywarp to transform the TENSOR file to the template.
struct='' #structural MRI data (can be either a T1-weighted or a T2-weighted image, no FLAIR, no PD)
weight=1 #if a structural MRI data is provided, by default it will be considered a T1-weighted image.

print_usage() {
  printf "\nUsage: alps.sh \n\
-a DWI \n\
-b BVAL \n\
-c BVEC \n\
-m METADATA (.json file) \n\
-i DWI (second input with opposite phase encoding) \n\
-j BVAL of second input (MUST BE DEFINED if second dwi input -i is defined) \n\
-k BVEC of second input (MUST BE DEFINED if second dwi input -i is defined) \n\
-n METADATA (.json file) of second input (MUST BE DEFINED if second dwi input -i is defined) \n\
-d DENOISING \n\
-e EDDY (specify which eddy program to use)
-r ROIS \n\
-t TEMPLATE \n\
-v VOLUMETRIC structural MRI data \n\
-h WeigHt of the volumetric structural MRI data \n\
-w WARP the reconstructed FA map to the template \n\
-f Use flirt or applywarp or vecreg to transform the TENSOR file to the template \n\
-s SKIP preprocessing and DTI fitting, i.e. perform ONLY ROI analysis \n\
-o OUTPUT_DIR_NAME \n"
  printf "\nDefault values: \n\
	-d DENOISING [default = 1];  0=skip; 1=both denoise and unringing; 2=only denoise; 3=only unringing. \n\
	-e EDDY [default = 1]; 0=skip eddy (not recommended); 1=use ${FSLDIR}/bin/eddy_cpu; 2=use ${FSLDIR}/bin/eddy; 3=use ${FSLDIR}/bin/eddy_correct; 
				alternatively, the user can specify which eddy program to use (e.g., eddy_cuda). The binary file specified by the user must be located in ${FSLDIR}/bin/ (do not include \"${FSLDIR}/bin/\" in the command, just the name of the binary file)\n\
	-r ROIS [default = 1]; 0=skip ROI analysis; 1=ROI analysis with provided ROIs drawn on JHU-ICBM-FA-1mm; 
		alternatively, a comma-separated list of 4 custom ROI nifti files can be specified.
		ROIs need to be in the following order: 1) LEFT and 2) RIGHT PROJECTION FIBERS (superior corona radiata), 3) LEFT and 4) RIGHT ASSOCIATION FIBERS (superior longitudinal fasciculus)\n\
	-t TEMPLATE [default = 1]; 0=ROI analysis in NATIVE space; 1=ROI analysis with FSL's JHU-ICBM-FA-1mm (if no structural MRI data input), MNI_T1_1mm (if structural data input is a T1) or JHU-ICBM-T2-1mm (if structural data input is a T2); \n\
		alternatively, the user can specify a template to use. \n\
	-v VOLUMETRIC structural MRI data: specify a structural MRI data (a T1w or T2w NIFTI file) to be used for registration of the FA map to the template;
	-h weight of the structural MRI data [default = 1]; 1=T1-weighted image; 2=T2-weighted image (no PD, no FLAIR).
	-w WARP [default = 0]; 0=perform linear registration of the reconstructed FA map to the template; 1=perform ONLY non-linear registration (warping) of the reconstructed FA map to the template using FSL's suggested default parameters (not recommended). \n\
		2=perform linear (flirt) + non-linear registration (fnirt); option -w is ignored when a structural MRI is used (-v is not empty).
  	-f method to transform the TENSOR to the template [default = 1]; 1=use flirt (or applywarp if WARP is 1 or 2 or -V is not empty) to transform the TENSOR to the template; \n\
   		2=use FSL's vecreg to transform the TENSOR to the template.
	-s Option to skip preprocessing and DTI fitting, i.e. performs ONLY ROI analysis [default = 0]; 0 = all the steps are performed; 1= ONLY ROI analysis is performed;
		If -s 1, then -o MUST BE DEFINED and MUST CORRESPOND TO THE FOLDER WHERE dxx.nii.gz, dyy.nii.gz and dzz.nii.gz ARE LOCATED.   \n\
	-o OUTPUT_DIR_NAME [default = 1]; default option will create a folder called \"alps\" located in the directory of the (first) input. \n\
	\nExample with 1 input: sh alps.sh -a dwi.nii.gz -b id.bval -c id.bvec -m id.json -d 1 -o alps\n\
	\nExample with 2 inputs with opposite phase encoding direction: sh alps.sh -a dwi_PA.nii.gz -b id_PA.bval -c id_PA.bvec -m id_PA.json -i dwi_AP.nii.gz -j id_AP.bval -k id_AP.bvec -n id_AP.json -d 1 -o alps\n"
}

while getopts 'a:b:c:m:i:j:k:n:d:e:r:t:v:h:w:f:s:o:' flag; do
  case "${flag}" in
    a) dwi1="$(echo "$(cd "$(dirname "${OPTARG}")" && pwd)/$(basename "${OPTARG}")")" ;;
    b) bval1="$(echo "$(cd "$(dirname "${OPTARG}")" && pwd)/$(basename "${OPTARG}")")" ;;
    c) bvec1="$(echo "$(cd "$(dirname "${OPTARG}")" && pwd)/$(basename "${OPTARG}")")" ;;
    m) json1="$(echo "$(cd "$(dirname "${OPTARG}")" && pwd)/$(basename "${OPTARG}")")" ;;
    i) dwi2="$(echo "$(cd "$(dirname "${OPTARG}")" && pwd)/$(basename "${OPTARG}")")" ;;
    j) bval2="$(echo "$(cd "$(dirname "${OPTARG}")" && pwd)/$(basename "${OPTARG}")")" ;;
    k) bvec2="$(echo "$(cd "$(dirname "${OPTARG}")" && pwd)/$(basename "${OPTARG}")")" ;;
    n) json2="$(echo "$(cd "$(dirname "${OPTARG}")" && pwd)/$(basename "${OPTARG}")")" ;;
    d) denoise="${OPTARG}" ;;
    e) eddy="${OPTARG}" ;;
    r) rois="${OPTARG}" ;;
    t) template="${OPTARG}" ;;
    v) struct="$(echo "$(cd "$(dirname "${OPTARG}")" && pwd)/$(basename "${OPTARG}")")" ;;
    h) weight="${OPTARG}" ;;
    w) warp="${OPTARG}" ;;
    f) freg="${OPTARG}" ;;
    s) skip="${OPTARG}" ;;
    o) output_dir_name="${OPTARG}" ;;
    *) print_usage
       exit 1 ;;
  esac
done
#INITIAL CHECKS
	#INPUTS
if [ $skip -eq 0 ]; then #check the inputs only if are needed
	if [ $OPTIND -eq 1 ]; then echo "ERROR! No options were passed"; print_usage; exit 1; fi
	if [ ! $dwi1 ]; then echo "ERROR! input dwi (-a) is not defined."; print_usage; exit 1; fi
	if [ ! $bval1 ]; then echo "ERROR! bval (-b) is not defined."; print_usage; exit 1; fi
	if [ ! $bvec1 ]; then echo "ERROR! bvec (-c) is not defined."; print_usage; exit 1; fi
	if [ ! -f "${dwi1}" ]; then echo "ERROR! input $dwi1 does not exist."; exit 1; fi
	if [ ! -f "${bval1}" ]; then echo "ERROR! bval file $bval1 does not exist."; exit 1; fi
	if [ ! -f "${bvec1}" ]; then echo "ERROR! bvec file $bvec1 does not exist."; exit 1; fi
	#if [ ! $json1 ]; then echo "ERROR! metadata .json file (-m) is not defined."; print_usage; exit 1; fi
 	#CHECK FOR DWI2. Hashtagged, because: 
  		#bvec2 is not used, 
    		#bval2 might be skipped if the user verified that the first volume is a B0 volume
      		#json2 might be skipped if the user verified that the PE direction is opposite to that of dwi1.
	#if [ $dwi2 ]; then if [ ! $bval2 ] || [ ! $bvec2 ] || [ ! $json2 ]; then echo "ERROR! dwi2 (-i) is defined, but bval (-j), bvec (-k), and/or metadata .json file (-n) of the second input is/are not defined."; print_usage; exit 1; fi; fi;
	#if [ $bval2 ]; then if [ ! $dwi2 ] || [ ! $bvec2 ] || [ ! $json2 ]; then echo "ERROR! bval (-j) of the second input is defined, but dwi2 (-i), bvec (-k), and/or metadata .json file (-n) of the second input is/are not defined."; print_usage; exit 1; fi; fi;
	#if [ $bvec2 ]; then if [ ! $dwi2 ] || [ ! $bval2 ] || [ ! $json2 ]; then echo "ERROR! bvec (-k) of the second input is defined, but dwi2 (-i), bval (-j), and/or metadata .json file (-n) of the second input is/are not defined."; print_usage; exit 1; fi; fi;
	#if [ $json2 ]; then if [ ! $dwi2 ] || [ ! $bval2 ] || [ ! $bvec2 ]; then echo "ERROR! metadata .json file (-n) of the second input is defined, but dwi2 (-i), bval (-j), and/or bvec (-k) of the second input is/are not defined."; print_usage; exit 1; fi; fi;
	if [ $dwi2 ]; then 
		if [ ! -f "${dwi2}" ]; then echo "ERROR! second input $dwi2 does not exist."; exit 1; fi;
		if [ $bval2 ]; then if [ ! -f "${bval2}" ]; then echo "ERROR! bval file $bval2 of second input does not exist."; exit 1; fi; fi;
		#if [ ! -f "${bvec2}" ]; then echo "ERROR! bvec file $bvec2 of second input does not exist."; exit 1; fi;
		if [ $json2 ]; then if [ ! -f "${json2}" ]; then echo "ERROR! metadata .json file $json2 of second input does not exist."; exit 1; fi; fi;
	fi
fi
	#ROIS & TEMPLATE
if [ "$rois" != "0" ]; then
	if [ "$rois" == "1" ]; then
		echo "ROI analysis with default ROIs"
		rois="${script_folder}/ROIs_JHU_ALPS/L_SCR.nii.gz,${script_folder}/ROIs_JHU_ALPS/R_SCR.nii.gz,${script_folder}/ROIs_JHU_ALPS/L_SLF.nii.gz,${script_folder}/ROIs_JHU_ALPS/R_SLF.nii.gz"
	else
		echo "ROI analysis with user-defined ROIs: $rois"
	fi
	n_rois=`echo $rois | awk -F '[,]' '{print NF}'`
	if [ $n_rois -ne 4 ]; then echo "ERROR! The number of ROIs is not equal to 4. The string of ROIs must include only 4 elements separated by 3 commas. Please double check that exactly 4 elements and no more than 3 commas are present in your string of ROIs (e.g., no commas is present in file/directory names."; exit 1; fi;
	proj_L=`echo "$rois" | cut -d "," -f1`
	proj_R=`echo "$rois" | cut -d "," -f2`
	assoc_L=`echo "$rois" | cut -d "," -f3`
	assoc_R=`echo "$rois" | cut -d "," -f4`
	if [ ! -f "${proj_L}" ]; then echo "ERROR! Cannot find the following ROI file: ${proj_L}"; exit 1; fi;
	if [ ! -f "${proj_R}" ]; then echo "ERROR! Cannot find the following ROI file: ${proj_R}"; exit 1; fi;
	if [ ! -f "${assoc_L}" ]; then echo "ERROR! Cannot find the following ROI file: ${assoc_L}"; exit 1; fi;
	if [ ! -f "${assoc_R}" ]; then echo "ERROR! Cannot find the following ROI file: ${assoc_R}"; exit 1; fi;
	if [ "$template" != "0" ]; then #analysis in template space. Double check that the template exists.
		#conditional for existence of structural MRI data.
		if [ ! -z $struct ]; then
			if [ ! -f "$struct" ]; then echo "ERROR! User specified to use $struct as structural MRI data, but I could not find it. Please double-check that the file exists."; exit 1; fi;
		fi
		#conditional for template selection
		if [ "$template" == "1" ]; then
			if [ -f ${FSLDIR}/data/standard/MNI152_T1_1mm_brain_mask_dil.nii.gz ]; then
			template_mask="--refmask=${FSLDIR}/data/standard/MNI152_T1_1mm_brain_mask_dil.nii.gz "
			#used only for fnirt (warp > 0 or !-z struct)
			fi
			if [ -z $struct ]; then
				echo "Default FA template will be used: JHU-ICBM-FA-1mm.nii.gz"
				template=${FSLDIR}/data/atlases/JHU/JHU-ICBM-FA-1mm.nii.gz
				template_abbreviation=JHU-FA
			elif [ ! -z $struct ]; then
				if [ $weight == "1" ]; then
					echo "The structural MRI $struct is a T1-weighted image, therefore the default template that will be used is: MNI152_T1_1mm"
					template=${FSLDIR}/data/standard/MNI152_T1_1mm_brain.nii.gz
					template_abbreviation=MNI152_T1_1mm
					smri="t1w"
				elif [ $weight == "2" ]; then 
					echo "The structural MRI $struct is a T2-weighted image, therefore the default template that will be used is: JHU-ICBM-T2-1mm"
					template=${FSLDIR}/data/atlases/JHU/JHU-ICBM-T2-1mm.nii.gz
					template_abbreviation=JHU-ICBM-T2-1mm
					smri="t2w"
				elif [ $weight -ne 1 ] && [ $weight -ne 2 ] && [ "$template" != "0" ] && [ "$template" != "1" ] ; then
					echo "ERROR! A structural MRI data has been specified, but the user needs to specify with the option -h whether this is T1-weighted (-h 1) or T2-weighted (-h 2) in order to select a default template. \n\
					The only allowed option for -h are 1 or 2. Alternatively, the user can specify the file template to use, and the option -h will be ignored."; exit 1; 
				fi
			fi
		else
  			template="$(echo "$(cd "$(dirname "${template}")" && pwd)/$(basename "${template}")")"
			echo "User specified template: $template"
			template_abbreviation=template
		fi
		if [ ! -f "${template}" ]; then echo "ERROR! Cannot find the template "$template". The template file must exist if -t option is not 0."; exit 1; fi;
		if [ $warp -ne 0 ] && [ $warp -ne 1 ] && [ $warp -ne 2 ]; then echo "ERROR! The option specified with -w is $warp, which is not an allowed option. -w must be equal to 0 (for linear registration) or 1 (for non-linear registration)."; exit 1; fi;
  		if [ $freg -ne 1 ] && [ $freg -ne 2 ]; then echo "ERROR! The option specified with -f is $freg, which is not an allowed option. -f must be equal to 1 (for using FSL's flirt and/or applywarp depending on -w) or 2 (for using FSL's vecreg)."; exit 1; fi;
	fi
fi
	#OPTIONS
if [ "$denoise" != "0" ] && [ "$denoise" != "1" ] && [ "$denoise" != "2" ] && [ "$denoise" != "3" ]; then echo "-d option is equal to $denoise, which is not an allowed option. -d must be equal to 0, 1, 2, or 3, or skipped (which corresponds to -d 1)."; print_usage; exit 1; fi;
if [ "$eddy" == "1" ] && [ ! -f "${FSLDIR}/bin/eddy_cpu" ]; then echo "-e option (eddy) is equal to $eddy (default), which means using ${FSLDIR}/bin/eddy_cpu, but ${FSLDIR}/bin/eddy_cpu cannot be found. -e must be equal to 0 (skip eddy correction, not recommended) 1 (use ${FSLDIR}/bin/eddy_cpu), 2 (use ${FSLDIR}/bin/eddy), 3 (use ${FSLDIR}/bin/eddy_correct), or skipped (default value = 1). If the user wants to use a specific eddy program, this must be located in ${FSLDIR}/bin/"; print_usage; exit 1; fi;
if [ "$eddy" == "2" ] && [ ! -f "${FSLDIR}/bin/eddy" ]; then echo "-e option (eddy) is equal to $eddy (default), which means using ${FSLDIR}/bin/eddy, but ${FSLDIR}/bin/eddy cannot be found. -e must be equal to 0 (skip eddy correction, not recommended) 1 (use ${FSLDIR}/bin/eddy_cpu), 2 (use ${FSLDIR}/bin/eddy), 3 (use ${FSLDIR}/bin/eddy_correct), or skipped (default value = 1). If the user wants to use a specific eddy program, this must be located in ${FSLDIR}/bin/"; print_usage; exit 1; fi;
if [ "$eddy" == "3" ] && [ ! -f "${FSLDIR}/bin/eddy_correct" ]; then echo "-e option (eddy) is equal to $eddy (default), which means using ${FSLDIR}/bin/eddy_correct, but ${FSLDIR}/bin/eddy_correct cannot be found. -e must be equal to 0 (skip eddy correction, not recommended) 1 (use ${FSLDIR}/bin/eddy_cpu), 2 (use ${FSLDIR}/bin/eddy), 3 (use ${FSLDIR}/bin/eddy_correct), or skipped (default value = 1). If the user wants to use a specific eddy program, this must be located in ${FSLDIR}/bin/"; print_usage; exit 1; fi;
if [ "$eddy" != "0" ] && [ "$eddy" != "1" ] && [ "$eddy" != "2" ] && [ "$eddy" != "3" ] && [ ! -f "${FSLDIR}/bin/$eddy" ]; then echo "-e option (eddy) is equal to $eddy, but ${FSLDIR}/bin/$eddy cannot be found. -e must be equal to 0 (skip eddy correction, not recommended) or 1 (use eddy_cpu if available, or eddy if not), or skipped (default value = 1). If the user wants to use a specific eddy program, this must be located in ${FSLDIR}/bin/"; print_usage; exit 1; fi;
if [ "$skip" != "0" ] && [ "$skip" != "1" ]; then echo "-s option is equal to $skip, which is not an allowed option. -s must be equal to 0 or 1, or skipped (default value = 0)."; print_usage; exit 1; fi;


#running check
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
-e $eddy \n
-r $rois \n
-t $template \n
-v $struct \n
-h $weight \n
-w $warp \n
-f $freg \n
-s $skip \n
-o $output_dir_name"


# 1. PREPROCESSING (Denoising, unringing, Topup for Opposite EPI acquisitions, Eddy)
if [ $skip -eq 0 ]; then
	# create output directory and copy bval and bvec files
	if [ ! $output_dir_name ]; then 
		#study_folder="$(dirname "${dwi1}")"
		study_folder=`echo "$(cd "$(dirname -- "${dwi1}")" >/dev/null; pwd -P)"`
		outdir="${study_folder}/alps"
	else
		outdir="${output_dir_name}"
	fi
	#OUTPUT ALPS CHECK
	if [ -f "${outdir}/alps.stat/alps.csv" ] && [ ! -z "`tail -n 1 "${outdir}/alps.stat/alps.csv" | tr -d ,`" ]; then echo "ERROR! Final output alps.csv already exists and is not empty! Remove/rename the output folder in order to re-run the pipeline with input $dwi1"; exit 1; fi;
	
	echo "create output directory: ${outdir}"
	mkdir -p "${outdir}"
	cp "$bvec1" "${outdir}/bvec1"
	cp "$bval1" "${outdir}/bval1"
	cd "${outdir}"

	## Denoising and/or unringing
	if [ $denoise -ne 0 ]; then
		if [ $denoise -eq 1 ]; then
			echo "Denoising and unringing $dwi1"
			dwidenoise "$dwi1" "${outdir}/dwi1.denoised.nii.gz"
			mrdegibbs "${outdir}/dwi1.denoised.nii.gz" "${outdir}/dwi1.denoised.unring.nii.gz"
			dwi1_processed="${outdir}/dwi1.denoised.unring.nii.gz"
		fi
		if [ $denoise -eq 2 ]; then
			echo "Denoising $dwi1"
			dwidenoise "$dwi1" "${outdir}/dwi1.denoised.nii.gz"
			dwi1_processed="${outdir}/dwi1.denoised.nii.gz"
		fi
		if [ $denoise -eq 3 ]; then
			echo "Unringing $dwi1"
			mrdegibbs "$dwi1" "${outdir}/dwi1.unring.nii.gz"
			dwi1_processed="${outdir}/dwi1.unring.nii.gz"
		fi
	else
		echo "Denoising and unringing skipped by the user (-d 0 option)"
		dwi1_processed="${dwi1}"
	fi

	# IF YOU HAVE A METADATA (JSON) FILE, THEN YOU CAN RUN EDDY with eddy_cpu
	if [ -f "${json1}" ]; then
		# ACQUISITION PARAMETERS OF FIRST INPUT (REQUIRED FOR EDDY)
		#scanner1=$(jq -r '.Manufacturer' "$json1") # -r gives you the raw output
		#scanner1=$(cat "${json1}" | grep -w Manufacturer | cut -d ' ' -f2 | tr -d ',')
  		scanner1=$(cat "${json1}" | awk -F'"' '/"Manufacturer"/ {print $4}')
		if [[ "$scanner1" == *"Philips"* ]]
		then
			#PEdir1=$(jq -r '.PhaseEncodingAxis' "$json1")
			#PEdir1=$(cat "${json1}" | grep -w PhaseEncodingAxis | cut -d ' ' -f2 | tr -d ',' | tr -d '"')
   			PEdir1=$(cat "${json1}" | awk -F'"' '/"PhaseEncodingAxis"/ {print $4}')
			TotalReadoutTime1=0.1 #this assumes that the readout time is identical for all acquisitions on the Philips scanner. A "realistic" read-out time is ~50-100ms (and eddy accepts 10-200ms). So use 0.1 (i.e., 100 ms), not 1.
		else
			#PEdir1=$(jq -r '.PhaseEncodingDirection' "$json1")
			#TotalReadoutTime1=$(jq -r '.TotalReadoutTime' "$json1")
			#PEdir1=$(cat "${json1}" | grep -w PhaseEncodingDirection | cut -d ' ' -f2 | tr -d ',' | tr -d '"')
   			#TotalReadoutTime1=$(cat "${json1}" | grep -w TotalReadoutTime | cut -d ' ' -f2 | tr -d ',' | tr -d '"')
   			PEdir1=$(cat "${json1}" | awk -F'"' '/"PhaseEncodingDirection"/ {print $4}')
      			TotalReadoutTime1=$(cat "${json1}" | grep -w TotalReadoutTime | cut -d ':' -f2 | cut -d ',' -f1 | xargs)
			
		fi
		if [ "$PEdir1" = i ]; then printf "1 0 0 $TotalReadoutTime1" > "${outdir}/acqparams.txt";
		elif [ "$PEdir1" = i- ]; then printf "-1 0 0 $TotalReadoutTime1" > "${outdir}/acqparams.txt";
		elif [ "$PEdir1" = j ]; then printf "0 1 0 $TotalReadoutTime1" > "${outdir}/acqparams.txt";
		elif [ "$PEdir1" = j- ]; then printf "0 -1 0 $TotalReadoutTime1" > "${outdir}/acqparams.txt";
		elif [ "$PEdir1" = k ]; then printf "0 0 1 $TotalReadoutTime1" > "${outdir}/acqparams.txt";
		elif [ "$PEdir1" = k- ]; then printf "0 0 -1 $TotalReadoutTime1" > "${outdir}/acqparams.txt"; 
		fi

		#IF YOU HAVE A SECOND DWI
		if [ "$dwi2" ]; then
			echo "2nd DWI is available"
			#if [[ "$dwi2" == *".nii" ]]; then gzip "$dwi2"; fi
			if [ $denoise -eq 1 ]; then
				echo "Denoising and unringing $dwi2"
				dwidenoise "$dwi2" "${outdir}/dwi2.denoised.nii.gz"
				mrdegibbs "${outdir}/dwi2.denoised.nii.gz" "${outdir}/dwi2.denoised.unring.nii.gz"
				dwi2_processed="${outdir}/dwi2.denoised.unring.nii.gz"
			elif [ $denoise -eq 2 ]; then
				echo "Denoising $dwi2"
				dwidenoise "$dwi2" "${outdir}/dwi2.denoised.nii.gz"
				dwi2_processed="${outdir}/dwi2.denoised.nii.gz"
			elif [ $denoise -eq 3 ]; then
				echo "Unringing $dwi2"
				mrdegibbs "$dwi2" "${outdir}/dwi2.unring.nii.gz"
				dwi2_processed="${outdir}/dwi2.unring.nii.gz"
			elif [ $denoise -eq 0 ]; then
				dwi2_processed="${dwi2}"
			fi
			
			##
   			if [ "$json2" ]; then
				#scanner2=$(jq -r '.Manufacturer' "$json2")
				#scanner2=$(cat "${json2}" | grep -w Manufacturer | cut -d ' ' -f2 | tr -d ',')
    				scanner2=$(cat "${json2}" | awk -F'"' '/"Manufacturer"/ {print $4}')
				if [[ "$scanner2" == *"Philips"* ]]
				then
					#PEdir2=$(jq -r '.PhaseEncodingAxis' "$json2")- #added "-" to make it opposite to the PEdir1. #Philips scans json files generated with dcm2niix have a problem where the PEdirection is the same (j) even though it is not.
					#PEdir2=$(cat "${json2}" | grep -w PhaseEncodingAxis | cut -d ' ' -f2 | tr -d ',' | tr -d '"')
     					PEdir2=$(cat "${json2}" | awk -F'"' '/"PhaseEncodingAxis"/ {print $4}')
					TotalReadoutTime2=0.1 #this assumes that the readout time is identical for all acquisitions on the Philips scanner. A "realistic" read-out time is ~50-100ms (and eddy accepts 10-200ms). So use 0.1 (i.e., 100 ms), not 1.
				else
					#PEdir2=$(jq -r '.PhaseEncodingDirection' "$json2")
					#TotalReadoutTime2=$(jq -r '.TotalReadoutTime' "$json2")
					#PEdir2=$(cat "${json2}" | grep -w PhaseEncodingDirection | cut -d ' ' -f2 | tr -d ',' | tr -d '"')
					#TotalReadoutTime2=$(cat "${json2}" | grep -w TotalReadoutTime | cut -d ' ' -f2 | tr -d ',' | tr -d '"')
     					PEdir2=$(cat "${json2}" | awk -F'"' '/"PhaseEncodingDirection"/ {print $4}')
      					TotalReadoutTime2=$(cat "${json2}" | grep -w TotalReadoutTime | cut -d ':' -f2 | cut -d ',' -f1 | xargs)
				fi
    			else #if you don't have a json2 file, then assume that the PEdir2 is opposite to PEdir1 and that the TotalReadoutTime2 is equal to TotalReadoutTime1 
       				if [[ "${PEdir1}" == *"-"* ]]; then PEdir2=$(echo ${PEdir1} | tr -d '-')
	   			else PEdir2="${PEdir1}-"
       				fi
	   			TotalReadoutTime2=$TotalReadoutTime1
       			fi
	
			# ACQUISITION PARAMETERS (ADDED TO THE PREVIOUS FILE)
			if [ "$PEdir2" = i ]; then printf "\n1 0 0 $TotalReadoutTime2" >> "${outdir}/acqparams.txt";
			elif [ "$PEdir2" = i- ]; then printf "\n-1 0 0 $TotalReadoutTime2" >> "${outdir}/acqparams.txt";
			elif [ "$PEdir2" = j ]; then printf "\n0 1 0 $TotalReadoutTime2" >> "${outdir}/acqparams.txt";
			elif [ "$PEdir2" = j- ]; then printf "\n0 -1 0 $TotalReadoutTime2" >> "${outdir}/acqparams.txt";
			elif [ "$PEdir2" = k ]; then printf "\n0 0 1 $TotalReadoutTime2" >> "${outdir}/acqparams.txt";
			elif [ "$PEdir2" = k- ]; then printf "\n0 0 -1 $TotalReadoutTime2" >> "${outdir}/acqparams.txt"; 
			fi


			#TOPUP (only if PEdir1 = PEdir2- and both DWI datasets have B0 images as first volume)
			b0_dwi1=`head -c 1 "$bval1"`
			if [ "$bval2" ]; then #if you don't have a bval2 file, then assume it equal to b0_dwi1, that should be 0.
   				b0_dwi2=`head -c 1 "$bval2"`
       			else
	  			b0_dwi2=$b0_dwi1
      			fi
			if [ "${PEdir1}" == "${PEdir2}-" ] || [ "${PEdir2}" == "${PEdir1}-" ] && ([ "${b0_dwi1}" == "${b0_dwi2}" ] && [ "${b0_dwi1}" == "0" ]);
			then
				b0_1="${outdir}/b0_first_direction.nii.gz"
				b0_2="${outdir}/b0_second_direction.nii.gz"
				fslroi "$dwi1_processed" "$b0_1" 0 1
				fslroi "$dwi2_processed" "$b0_2" 0 1
				
				#check dimensions of b0_1 and b0_2 because sometimes they are different and needs to be coregistered for fslmerge to work
				dim1_1=`fslhd "$b0_1" | grep dim1 | tr -s ' ' | cut -d " " -f2 | head -n 1` #tr with the squeeze option makes all consecutive whitespaces equal to 1 whitespace
				dim2_1=`fslhd "$b0_1" | grep dim2 | tr -s ' ' | cut -d " " -f2 | head -n 1` #tr with the squeeze option makes all consecutive whitespaces equal to 1 whitespace
				dim3_1=`fslhd "$b0_1" | grep dim3 | tr -s ' ' | cut -d " " -f2 | head -n 1` #tr with the squeeze option makes all consecutive whitespaces equal to 1 whitespace
				dim1_2=`fslhd "$b0_2" | grep dim1 | tr -s ' ' | cut -d " " -f2 | head -n 1` #tr with the squeeze option makes all consecutive whitespaces equal to 1 whitespace
				dim2_2=`fslhd "$b0_2" | grep dim2 | tr -s ' ' | cut -d " " -f2 | head -n 1` #tr with the squeeze option makes all consecutive whitespaces equal to 1 whitespace
				dim3_2=`fslhd "$b0_2" | grep dim3 | tr -s ' ' | cut -d " " -f2 | head -n 1` #tr with the squeeze option makes all consecutive whitespaces equal to 1 whitespace
				if [ "${dim1_1}" != "${dim1_2}" ] || [ "${dim2_1}" != "${dim2_2}" ] || [ "${dim3_1}" != "${dim3_2}" ]; 
				then
					flirt -in "${b0_2}" -ref "${b0_1}" -out "${outdir}/b0_second_direction_reg" -omat "${outdir}/b0_2.in.b0_1.mat" -bins 256 -cost corratio -searchrx -90 90 -searchry -90 90 -searchrz -90 90 -dof 6
					b0_2="${outdir}/b0_second_direction_reg.nii.gz"
					echo "b0_2 registered to b0_1"
				fi

				fslmerge -t "${outdir}/both_b0" "$b0_1" "$b0_2"
				temp=`fslhd "${dwi1}" | grep dim3`
				dimtmp=( $temp )
				n_slices=${dimtmp[1]}
				echo "Running FSL TOPUP"
				if [ $((n_slices%2)) -eq 0 ] #even number of slices
				then
					topup --imain=both_b0 --datain=acqparams.txt --config=b02b0.cnf --out=my_topup_results --iout=my_hifi_b0 #which will upon completion create the two files my_topup_results_fieldcoef.nii.gz (an estimate of the susceptibility induced off-resonance field), my_topup_results_movpar.txt and the non-distorted space my_hifi_b0.nii.gz
				else #odd number of slices, use a different configuration file (https://www.jiscmail.ac.uk/cgi-bin/webadmin?A2=FSL;6c4c9591.2002)
					b02b0_1=`find /${FSLDIR} -name "b02b0_1.cnf" | head -n 1` #the location is usually ${FSLDIR}/src/topup/flirtsch/b02b0_1.cnf
					if [ -z $b02b0_1 ]; then echo "ERROR! Could not find the configuration file required for running TOPUP on data with odd number of slices (your input has $n_slices slices). Should be in $FSLDIR."; exit 1; 
					else
						topup --imain=both_b0 --datain=acqparams.txt --config=${b02b0_1} --out=my_topup_results --iout=my_hifi_b0 #which will upon completion create the two files my_topup_results_fieldcoef.nii.gz (an estimate of the susceptibility induced off-resonance field), my_topup_results_movpar.txt and the non-distorted space my_hifi_b0.nii.gz
					fi
				fi
				# Processing of topup output
				fslmaths my_hifi_b0 -Tmean my_hifi_b0
				bet2 my_hifi_b0 b0_brain -m

				#EDDY
    				if [ $eddy == "0" ]; then echo "EDDY skipped by the user (-e option is equal to $eddy)"; 
				else
					echo "Running EDDY with TOPUP RESULTS"
					temp=`fslhd "${dwi1}" | grep dim4`
					dimtmp=( $temp )
					n_vol=${dimtmp[1]}
					indx=""
					for ((i=1; i<=$n_vol; i+=1)); do indx="$indx 1"; done
					echo $indx > index.txt
					if [ $eddy == "1" ] && [ -f ${FSLDIR}/bin/eddy_cpu ]; then 
						echo "Found eddy_cpu! Running ${FSLDIR}/bin/eddy_cpu with default options"
						eddy_cpu --imain="$dwi1_processed" --mask=b0_brain_mask --acqp=acqparams.txt --index=index.txt --bvecs=bvec1 --bvals=bval1 --topup=my_topup_results --out=eddy_corrected_data
					elif [ $eddy == "2" ] && [ -f ${FSLDIR}/bin/eddy ]; then 
						echo "Running ${FSLDIR}/bin/eddy with default options";
						eddy --imain="$dwi1_processed" --mask=b0_brain_mask --acqp=acqparams.txt --index=index.txt --bvecs=bvec1 --bvals=bval1 --topup=my_topup_results --out=eddy_corrected_data
					elif [ $eddy == "3" ] && [ -f ${FSLDIR}/bin/eddy_correct ]; then 
						echo "Running ${FSLDIR}/bin/eddy_correct with default options";
						eddy_correct "$dwi1_processed" eddy_corrected_data 0 trilinear
					else echo "Eddy with user-specified eddy program ${FSLDIR}/bin/$eddy"
						"${FSLDIR}/bin/$eddy" --imain="$dwi1_processed" --mask=b0_brain_mask --acqp=acqparams.txt --index=index.txt --bvecs=bvec1 --bvals=bval1 --topup=my_topup_results --out=eddy_corrected_data
					fi
    				fi
			elif [ "${PEdir1}" != "${PEdir2}-" ] || [ "${PEdir2}" != "${PEdir1}-" ] || [ "${b0_dwi1}" != "${b0_dwi2}" ]; then
				fslroi "$dwi1_processed" "${outdir}/b0" 0 1
				bet2 "${outdir}/b0" "${outdir}/b0_brain" -m
				#EDDY
    				if [ $eddy == "0" ]; then echo "EDDY skipped by the user (-e option is equal to $eddy)"; 
				else
					echo "Running EDDY (NO TOPUP) because PE directions are not opposite or b0 images are different"
					temp=`fslhd "${dwi1}" | grep dim4`
					dimtmp=( $temp )
					n_vol=${dimtmp[1]}
					indx=""
					for ((i=1; i<=$n_vol; i+=1)); do indx="$indx 1"; done
					echo $indx > index.txt
					if [ $eddy == "1" ] && [ -f ${FSLDIR}/bin/eddy_cpu ]; then 
							echo "Found eddy_cpu! Running ${FSLDIR}/bin/eddy_cpu with default options"
							eddy_cpu --imain="$dwi1_processed" --mask=b0_brain_mask --acqp=acqparams.txt --index=index.txt --bvecs=bvec1 --bvals=bval1 --out=eddy_corrected_data
					elif [ $eddy == "2" ] && [ -f ${FSLDIR}/bin/eddy ]; then 
							echo "Running ${FSLDIR}/bin/eddy with default options";
							eddy --imain="$dwi1_processed" --mask=b0_brain_mask --acqp=acqparams.txt --index=index.txt --bvecs=bvec1 --bvals=bval1 --out=eddy_corrected_data
					elif [ $eddy == "3" ] && [ -f ${FSLDIR}/bin/eddy_correct ]; then 
							echo "Running ${FSLDIR}/bin/eddy_correct with default options";
							eddy_correct "$dwi1_processed" eddy_corrected_data 0 trilinear
					else echo "Eddy with user-specified eddy program ${FSLDIR}/bin/$eddy"
						"${FSLDIR}/bin/$eddy" --imain="$dwi1_processed" --mask=b0_brain_mask --acqp=acqparams.txt --index=index.txt --bvecs=bvec1 --bvals=bval1 --out=eddy_corrected_data
					fi
     				fi
			fi
		elif [ ! "$dwi2" ]; then
			fslroi "$dwi1_processed" "${outdir}/b0" 0 1
			bet2 "${outdir}/b0" "${outdir}/b0_brain" -m
			#EDDY
   			if [ $eddy == "0" ]; then echo "EDDY skipped by the user (-e option is equal to $eddy)"; 
			else
				echo "Running EDDY only (NO TOPUP) because there is no dwi2"
				temp=`fslhd "${dwi1}" | grep dim4`
				dimtmp=( $temp )
				n_vol=${dimtmp[1]}
				indx=""
				for ((i=1; i<=$n_vol; i+=1)); do indx="$indx 1"; done
				echo $indx > index.txt
				if [ $eddy == "1" ] && [ -f ${FSLDIR}/bin/eddy_cpu ]; then 
						echo "Found eddy_cpu! Running ${FSLDIR}/bin/eddy_cpu with default options"
						eddy_cpu --imain="$dwi1_processed" --mask=b0_brain_mask --acqp=acqparams.txt --index=index.txt --bvecs=bvec1 --bvals=bval1 --out=eddy_corrected_data
				elif [ $eddy == "2" ] && [ -f ${FSLDIR}/bin/eddy ]; then 
						echo "Running ${FSLDIR}/bin/eddy with default options";
						eddy --imain="$dwi1_processed" --mask=b0_brain_mask --acqp=acqparams.txt --index=index.txt --bvecs=bvec1 --bvals=bval1 --out=eddy_corrected_data
				elif [ $eddy == "3" ] && [ -f ${FSLDIR}/bin/eddy_correct ]; then 
						echo "Running ${FSLDIR}/bin/eddy_correct with default options";
						eddy_correct "$dwi1_processed" eddy_corrected_data 0 trilinear
				else echo "Eddy with user-specified eddy program ${FSLDIR}/bin/$eddy"
					"${FSLDIR}/bin/$eddy" --imain="$dwi1_processed" --mask=b0_brain_mask --acqp=acqparams.txt --index=index.txt --bvecs=bvec1 --bvals=bval1 --out=eddy_corrected_data
				fi
    			fi
		fi
	elif [ ! -f "${json1}" ] && [ $eddy == "3" ]; then
		echo "Running ${FSLDIR}/bin/eddy_correct with default options";
		eddy_correct "$dwi1_processed" eddy_corrected_data 0 trilinear
	fi


	# 2. FIT TENSOR
	if [ -f "${outdir}/eddy_corrected_data.nii.gz" ]; then
		echo "starting DTI FITTING on eddy corrected data"
		dtifit --data=eddy_corrected_data.nii.gz --out=dti --mask=b0_brain_mask.nii.gz --bvecs=bvec1 --bvals=bval1 --save_tensor
	else
		if [ -f "${dwi1_processed}" ]; then
			fslroi "$dwi1_processed" "${outdir}/b0" 0 1
			bet2 "${outdir}/b0" "${outdir}/b0_brain" -m
			echo "starting DTI FITTING on preprocessed diffusion data (denoised and/or unringed, NO TOPUP, NO eddy correction)"
			dtifit --data="${dwi1_processed}" --out=dti --mask=b0_brain_mask.nii.gz --bvecs=bvec1 --bvals=bval1 --save_tensor
		else
			fslroi "$dwi1" "${outdir}/b0" 0 1
			bet2 "${outdir}/b0" "${outdir}/b0_brain" -m
			echo "starting DTI FITTING on input diffusion data (NO preprocessing (denoising/unringing), NO TOPUP, NO eddy correction)"
			dtifit --data="${dwi1}" --out=dti --mask=b0_brain_mask.nii.gz --bvecs=bvec1 --bvals=bval1 --save_tensor
		fi
	fi

	echo "DTI FITTING completed!"
	#fslsplit "${outdir}/dti_tensor.nii.gz" 
	#cp "${outdir}/vol0000.nii.gz" "${outdir}/dxx.nii.gz" 
	#cp "${outdir}/vol0003.nii.gz" "${outdir}/dyy.nii.gz" 
	#cp "${outdir}/vol0005.nii.gz" "${outdir}/dzz.nii.gz"
elif [ $skip -eq 1 ]; then
	if [ ! $output_dir_name ]; then echo "ERROR! Option -s is set to 1, therefore option -o MUST BE DEFINED and MUST CORRESPOND TO THE FOLDER WHERE dxx.nii.gz, dyy.nii.gz and dzz.nii.gz ARE LOCATED."; exit 1; fi;
	echo "Preprocessing and DTI fitting skipped by the user (-s 1 option). ONLY ROI ANALYSIS IS PERFORMED. Checking all required inputs are available..."
	outdir="${output_dir_name}"
	if [ -f "${outdir}/alps.stat/alps.csv" ] && [ ! -z "`tail -n 1 "${outdir}/alps.stat/alps.csv" | tr -d ,`" ]; then echo "ERROR! Final output alps.csv already exists and is not empty! Remove/rename the "alps.stat" folder or the "alps.stat/alps.csv" file in order to run the ROI analysis only (-s 1) in ${outdir}"; exit 1; fi;
	if [ -f "${outdir}/dti_FA.nii.gz" ]; then echo "dti_FA.nii.gz is available for ROI analysis"; else echo "ERROR! Cannot find ${outdir}/dti_FA.nii.gz, needed for ROI analysis. Double check that ${outdir}/dti_FA.nii.gz exists; if it does not exist, consider running the whole alps script (-s 0, default option)"; exit 1; fi
 	if [ -f "${outdir}/dti_tensor.nii.gz" ]; then echo "dti_tensor.nii.gz is available for ROI analysis"; else echo "ERROR! Cannot find ${outdir}/dti_tensor.nii.gz, needed for ROI analysis. Double check that ${outdir}/dti_tensor.nii.gz exists; if it does not exist, consider running the whole alps script (-s 0, default option)"; exit 1; fi
	#if [ -f "${outdir}/dxx.nii.gz" ]; then echo "dxx.nii.gz is available for ROI analysis"; else echo "ERROR! Cannot find ${outdir}/dxx.nii.gz, needed for ROI analysis. Double check that ${outdir}/dxx.nii.gz exists; if it does not exist, consider running the whole alps script (-s 0, default option)"; exit 1; fi
	#if [ -f "${outdir}/dyy.nii.gz" ]; then echo "dyy.nii.gz is available for ROI analysis"; else echo "ERROR! Cannot find ${outdir}/dyy.nii.gz, needed for ROI analysis. Double check that ${outdir}/dyy.nii.gz exists; if it does not exist, consider running the whole alps script (-s 0, default option)"; exit 1; fi
	#if [ -f "${outdir}/dyy.nii.gz" ]; then echo "dzz.nii.gz is available for ROI analysis"; else echo "ERROR! Cannot find ${outdir}/dzz.nii.gz, needed for ROI analysis. Double check that ${outdir}/dzz.nii.gz exists; if it does not exist, consider running the whole alps script (-s 0, default option)"; exit 1; fi
fi 

# 3. ROI ANALYSIS
if [ "$rois" != "0" ]
then
	#ROIs
	echo "starting ROI analysis with projection fibers "$(basename "$proj_L")" (LEFT) and "$(basename "$proj_R")" (RIGHT), and association fibers "$(basename "$assoc_L")" (LEFT) and "$(basename "$assoc_R")" (RIGHT)"
	#TEMPLATE
	if [ "$template" != "0" ]; then #analysis in template space
		if [ -f "$struct" ]; then #if you have structural MRI data
			echo "Linear (flirt) + Non-Linear (fnirt) registration to template via structural scan";
			cp "$struct" "${outdir}/${smri}.nii.gz"
   			#hashtagged the following 2 lines because bet2 does not work super well in all struct MRI scans.
			#bet2 "${outdir}/${smri}.nii.gz" "${outdir}/${smri}_brain" -m #this is used for flirt dti2struct and flirt struct2template
			#flirt -ref "${outdir}/${smri}_brain.nii.gz" -in "${outdir}/dti_FA.nii.gz" -dof 6 -omat "${outdir}/dti2struct.mat"
   			if [ $weight == "1" ]; then
				flirt -ref "${outdir}/${smri}.nii.gz" -in "${outdir}/dti_FA.nii.gz" -dof 6 -out "${outdir}/dti_FA_2_${smri}.nii.gz" -omat "${outdir}/dti2struct.mat"
   			elif [ $weight == "2" ]; then #if it's a T2, it's better to align the b0 volume rather than the FA, because the b0 contrast is more similar to T2.
	      			if [ -f "${outdir}/b0.nii.gz" ]; then
	      			flirt -ref "${outdir}/${smri}.nii.gz" -in "${outdir}/b0.nii.gz" -dof 6 -out "${outdir}/b0_2_${smri}.nii.gz" -omat "${outdir}/dti2struct.mat"
		 		else #in case you don't have b0 (i.e., you skipped the preprocessing, and are only doing ROI analysis with a dti_FA map ready)
     				flirt -ref "${outdir}/${smri}.nii.gz" -in "${outdir}/dti_FA.nii.gz" -dof 6 -out "${outdir}/dti_FA_2_${smri}.nii.gz" -omat "${outdir}/dti2struct.mat"
    				fi
	 		fi
			if [ -f "${outdir}/b0_brain_mask.nii.gz" ]; then
				flirt -in "${outdir}/b0_brain_mask.nii.gz" -ref "${outdir}/${smri}.nii.gz" -interp nearestneighbour -out "${outdir}/b0_brain_mask_2_struct.nii.gz" -init "${outdir}/dti2struct.mat" -applyxfm
				fslmaths "${outdir}/${smri}.nii.gz" -mul "${outdir}/b0_brain_mask_2_struct.nii.gz" "${outdir}/${smri}_brain.nii.gz"
			else #in case you don't have b0_brain_mask (i.e., you skipped the preprocessing, and are only doing ROI analysis)
				bet2 "${outdir}/dti_FA.nii.gz" "${outdir}/dti_FA_brain" -m
				flirt -in "${outdir}/dti_FA_brain_mask.nii.gz" -ref "${outdir}/${smri}.nii.gz" -interp nearestneighbour -out "${outdir}/dti_FA_brain_mask_2_struct.nii.gz" -init "${outdir}/dti2struct.mat" -applyxfm
				fslmaths "${outdir}/${smri}.nii.gz" -mul "${outdir}/dti_FA_brain_mask_2_struct.nii.gz" "${outdir}/${smri}_brain.nii.gz"
			fi

			flirt -ref "${template}" -in "${outdir}/${smri}_brain.nii.gz" -omat "${outdir}/struct2template_aff.mat"
			fnirt --in="${outdir}/${smri}.nii.gz" --aff="${outdir}/struct2template_aff.mat" --cout="${outdir}/struct2template_warps" \
			--ref="${template}" ${template_mask}--imprefm=1 \
			--impinm=1 --imprefval=0 --impinval=0 --subsamp=4,4,2,2,1,1 --miter=5,5,5,5,5,10 --infwhm=8,6,5,4.5,3,2 --reffwhm=8,6,5,4,2,0 \
			--lambda=300,150,100,50,40,30 --estint=1,1,1,1,1,0 --applyrefmask=1,1,1,1,1,1 --applyinmask=1 --warpres=10,10,10 --ssqlambda=1 \
			--regmod=bending_energy --intmod=global_non_linear_with_bias --intorder=5 --biasres=50,50,50 --biaslambda=10000 --refderiv=0
			applywarp --in="${outdir}/dti_FA.nii.gz" --ref="${template}" --warp="${outdir}/struct2template_warps" --premat="${outdir}/dti2struct.mat" --out="${outdir}/dti_FA_to_${template_abbreviation}.nii.gz"
   			applywarp --in="${outdir}/dti_MD.nii.gz" --ref="${template}" --warp="${outdir}/struct2template_warps" --premat="${outdir}/dti2struct.mat" --out="${outdir}/dti_MD_to_${template_abbreviation}.nii.gz"
	   			if [ "$freg" == "1" ]; then echo "Transformation of the tensor to the template with applywarp";
	      			applywarp --in="${outdir}/dti_tensor.nii.gz" --ref="${template}" --warp="${outdir}/struct2template_warps" --premat="${outdir}/dti2struct.mat" --out="${outdir}/dti_tensor_in_${template_abbreviation}.nii.gz"
	      			#applywarp --in="${outdir}/dxx.nii.gz" --ref="${template}" --warp="${outdir}/struct2template_warps" --premat="${outdir}/dti2struct.mat" --out="${outdir}/dxx_in_${template_abbreviation}.nii.gz"
				#applywarp --in="${outdir}/dyy.nii.gz" --ref="${template}" --warp="${outdir}/struct2template_warps" --premat="${outdir}/dti2struct.mat" --out="${outdir}/dyy_in_${template_abbreviation}.nii.gz"
				#applywarp --in="${outdir}/dzz.nii.gz" --ref="${template}" --warp="${outdir}/struct2template_warps" --premat="${outdir}/dti2struct.mat" --out="${outdir}/dzz_in_${template_abbreviation}.nii.gz"
	   			elif [ "$freg" == "2" ]; then echo "Transformation of the tensor to the template with vecreg";
	   			vecreg -i "${outdir}/dti_tensor.nii.gz" -r "${template}" -o "${outdir}/dti_tensor_in_struct.nii.gz" -t "${outdir}/dti2struct.mat"
	   			vecreg -i "${outdir}/dti_tensor_in_struct.nii.gz" -r "${template}" -o "${outdir}/dti_tensor_in_${template_abbreviation}.nii.gz" -w "${outdir}/struct2template_warps"
	      			fi
		else
			if [ "$warp" == "0" ]; then echo "Linear registration to template with flirt and default options";
			flirt -in "${outdir}/dti_FA.nii.gz" -ref "${template}" -out "${outdir}/dti_FA_to_${template_abbreviation}.nii.gz" -omat "${outdir}/FA_to_${template_abbreviation}.mat" -bins 256 -cost corratio -searchrx -90 90 -searchry -90 90 -searchrz -90 90 -dof 12
   			flirt -in "${outdir}/dti_MD.nii.gz" -ref "${template}" -out "${outdir}/dti_MD_to_${template_abbreviation}.nii.gz" -init "${outdir}/FA_to_${template_abbreviation}.mat" -applyxfm
				if [ "$freg" == "1" ]; then echo "Transformation of the tensor to the template with flirt";
	      			flirt -in "${outdir}/dti_tensor.nii.gz" -ref "${template}" -out "${outdir}/dti_tensor_in_${template_abbreviation}.nii.gz" -init "${outdir}/FA_to_${template_abbreviation}.mat" -applyxfm
		 		#flirt -in "${outdir}/dxx.nii.gz" -ref "${template}" -out "${outdir}/dxx_in_${template_abbreviation}.nii.gz" -init "${outdir}/FA_to_${template_abbreviation}.mat" -applyxfm
				#flirt -in "${outdir}/dyy.nii.gz" -ref "${template}" -out "${outdir}/dyy_in_${template_abbreviation}.nii.gz" -init "${outdir}/FA_to_${template_abbreviation}.mat" -applyxfm
				#flirt -in "${outdir}/dzz.nii.gz" -ref "${template}" -out "${outdir}/dzz_in_${template_abbreviation}.nii.gz" -init "${outdir}/FA_to_${template_abbreviation}.mat" -applyxfm
				elif [ "$freg" == "2" ]; then echo "Transformation of the tensor to the template with vecreg";
	   			vecreg -i "${outdir}/dti_tensor.nii.gz" -r "${template}" -o "${outdir}/dti_tensor_in_${template_abbreviation}.nii.gz" -t "${outdir}/FA_to_${template_abbreviation}.mat"
       				#vecreg -i "${outdir}/dxx.nii.gz" -r "${template}" -o "${outdir}/dxx_in_${template_abbreviation}.nii.gz" -t "${outdir}/FA_to_${template_abbreviation}.mat"
				#vecreg -i "${outdir}/dyy.nii.gz" -r "${template}" -o "${outdir}/dyy_in_${template_abbreviation}.nii.gz" -t "${outdir}/FA_to_${template_abbreviation}.mat"
				#vecreg -i "${outdir}/dzz.nii.gz" -r "${template}" -o "${outdir}/dzz_in_${template_abbreviation}.nii.gz" -t "${outdir}/FA_to_${template_abbreviation}.mat"
				fi
			elif [ "$warp" == "1" ]; then echo "Non-Linear registration to template with fnirt and default options (cf. fsl/etc/flirtsch/FA_2_FMRIB58_1mm.cnf)";
			fnirt --in="${outdir}/dti_FA.nii.gz" --ref="${template}" ${template_mask}--cout="${outdir}/FA_to_${template_abbreviation}_warps" --imprefm=1 --impinm=1 --imprefval=0 --impinval=0 --subsamp=8,4,2,2 \
			--miter=5,5,5,5 --infwhm=12,6,2,2 --reffwhm=12,6,2,2 --lambda=300,75,30,30 --estint=1,1,1,0 --warpres=10,10,10 --ssqlambda=1 \
			--regmod=bending_energy --intmod=global_linear --refderiv=0
			applywarp --in="${outdir}/dti_FA.nii.gz" --ref="${template}" --warp="${outdir}/FA_to_${template_abbreviation}_warps" --out="${outdir}/dti_FA_to_${template_abbreviation}.nii.gz"
   			applywarp --in="${outdir}/dti_MD.nii.gz" --ref="${template}" --warp="${outdir}/FA_to_${template_abbreviation}_warps" --out="${outdir}/dti_MD_to_${template_abbreviation}.nii.gz"
	   			if [ "$freg" == "1" ]; then echo "Transformation of the tensor to the template with applywarp";
	      			applywarp --in="${outdir}/dti_tensor.nii.gz" --ref="${template}" --warp="${outdir}/FA_to_${template_abbreviation}_warps" --out="${outdir}/dti_tensor_in_${template_abbreviation}.nii.gz"
				#applywarp --in="${outdir}/dxx.nii.gz" --ref="${template}" --warp="${outdir}/FA_to_${template_abbreviation}_warps" --out="${outdir}/dxx_in_${template_abbreviation}.nii.gz"
				#applywarp --in="${outdir}/dyy.nii.gz" --ref="${template}" --warp="${outdir}/FA_to_${template_abbreviation}_warps" --out="${outdir}/dyy_in_${template_abbreviation}.nii.gz"
				#applywarp --in="${outdir}/dzz.nii.gz" --ref="${template}" --warp="${outdir}/FA_to_${template_abbreviation}_warps" --out="${outdir}/dzz_in_${template_abbreviation}.nii.gz"
    				elif [ "$freg" == "2" ]; then echo "Transformation of the tensor to the template with vecreg";
	   			vecreg -i "${outdir}/dti_tensor.nii.gz" -r "${template}" -o "${outdir}/dti_tensor_in_${template_abbreviation}.nii.gz" -w "${outdir}/FA_to_${template_abbreviation}_warps"
       				fi
			elif [ "$warp" == "2" ]; then echo "Linear (flirt) + Non-Linear (fnirt) registration to template";
			flirt -in "${outdir}/dti_FA.nii.gz" -ref "${template}" -omat "${outdir}/FA_to_${template_abbreviation}_aff.mat" -bins 256 -cost corratio -searchrx -90 90 -searchry -90 90 -searchrz -90 90 -dof 12
			fnirt --in="${outdir}/dti_FA.nii.gz" --ref="${template}" ${template_mask}--aff="${outdir}/FA_to_${template_abbreviation}_aff.mat" \
			--cout="${outdir}/FA_to_${template_abbreviation}_warps" --imprefm=1 --impinm=1 --imprefval=0 --impinval=0 --subsamp=8,4,2,2 \
			--miter=5,5,5,5 --infwhm=12,6,2,2 --reffwhm=12,6,2,2 --lambda=300,75,30,30 --estint=1,1,1,0 --warpres=10,10,10 --ssqlambda=1 \
			--regmod=bending_energy --intmod=global_linear --refderiv=0
			applywarp --in="${outdir}/dti_FA.nii.gz" --ref="${template}" --warp="${outdir}/FA_to_${template_abbreviation}_warps" --out="${outdir}/dti_FA_to_${template_abbreviation}.nii.gz"
   			applywarp --in="${outdir}/dti_MD.nii.gz" --ref="${template}" --warp="${outdir}/FA_to_${template_abbreviation}_warps" --out="${outdir}/dti_MD_to_${template_abbreviation}.nii.gz"
   				if [ "$freg" == "1" ]; then echo "Transformation of the tensor to the template with applywarp";
       				applywarp --in="${outdir}/dti_tensor.nii.gz" --ref="${template}" --warp="${outdir}/FA_to_${template_abbreviation}_warps" --out="${outdir}/dti_tensor_in_${template_abbreviation}.nii.gz"
       				#applywarp --in="${outdir}/dxx.nii.gz" --ref="${template}" --warp="${outdir}/FA_to_${template_abbreviation}_warps" --out="${outdir}/dxx_in_${template_abbreviation}.nii.gz"
				#applywarp --in="${outdir}/dyy.nii.gz" --ref="${template}" --warp="${outdir}/FA_to_${template_abbreviation}_warps" --out="${outdir}/dyy_in_${template_abbreviation}.nii.gz"
				#applywarp --in="${outdir}/dzz.nii.gz" --ref="${template}" --warp="${outdir}/FA_to_${template_abbreviation}_warps" --out="${outdir}/dzz_in_${template_abbreviation}.nii.gz"
    				elif [ "$freg" == "2" ]; then echo "Transformation of the tensor to the template with vecreg";
   				vecreg -i "${outdir}/dti_tensor.nii.gz" -r "${template}" -o "${outdir}/dti_tensor_in_${template_abbreviation}.nii.gz" -w "${outdir}/FA_to_${template_abbreviation}_warps"
				fi
			fi
		fi
   		fslroi "${outdir}/dti_tensor_in_${template_abbreviation}.nii.gz" "${outdir}/dxx_in_${template_abbreviation}.nii.gz" 0 1
     		fslroi "${outdir}/dti_tensor_in_${template_abbreviation}.nii.gz" "${outdir}/dyy_in_${template_abbreviation}.nii.gz" 3 1
       		fslroi "${outdir}/dti_tensor_in_${template_abbreviation}.nii.gz" "${outdir}/dzz_in_${template_abbreviation}.nii.gz" 5 1
		dxx="${outdir}/dxx_in_${template_abbreviation}.nii.gz"
		dyy="${outdir}/dyy_in_${template_abbreviation}.nii.gz"
		dzz="${outdir}/dzz_in_${template_abbreviation}.nii.gz"
  		fa="${outdir}/dti_FA_to_${template_abbreviation}.nii.gz"
    		md="${outdir}/dti_MD_to_${template_abbreviation}.nii.gz"
	elif [ "$template" == "0" ]; then #analysis in native space
 		echo "ALPS analysis in native space"
   		fslroi "${outdir}/dti_tensor.nii.gz" "${outdir}/dxx.nii.gz" 0 1
     		fslroi "${outdir}/dti_tensor.nii.gz" "${outdir}/dyy.nii.gz" 3 1
       		fslroi "${outdir}/dti_tensor.nii.gz" "${outdir}/dzz.nii.gz" 5 1
		dxx="${outdir}/dxx.nii.gz"
		dyy="${outdir}/dyy.nii.gz"
		dzz="${outdir}/dzz.nii.gz"
  		fa="${outdir}/dti_FA.nii.gz"
	 	md="${outdir}/dti_MD.nii.gz"
  		if [ "$rois" == "${script_folder}/ROIs_JHU_ALPS/L_SCR.nii.gz,${script_folder}/ROIs_JHU_ALPS/R_SCR.nii.gz,${script_folder}/ROIs_JHU_ALPS/L_SLF.nii.gz,${script_folder}/ROIs_JHU_ALPS/R_SLF.nii.gz" ]; then
    			template=${FSLDIR}/data/atlases/JHU/JHU-ICBM-FA-1mm.nii.gz
			template_abbreviation=JHU-FA
    			flirt -ref "${outdir}/dti_FA.nii.gz" -in "${template}" -out "${outdir}/dti_FA_${template_abbreviation}_to_native.nii.gz" -omat "${outdir}/${template_abbreviation}_to_native.mat" -bins 256 -cost corratio -searchrx -90 90 -searchry -90 90 -searchrz -90 90 -dof 12
       			for r in $(echo $rois | tr -s ',' ' '); do
	  			flirt -in "${r}" -ref "${outdir}/dti_FA.nii.gz" -out "${outdir}/$(basename ${r} .nii.gz)_native.nii.gz" -init "${outdir}/${template_abbreviation}_to_native.mat" -applyxfm -interp nearestneighbour
      			done
	  		proj_L=${outdir}/"$(basename "$(echo "${rois}" | cut -d ',' -f1)" .nii.gz)"_native.nii.gz
     			proj_R=${outdir}/"$(basename "$(echo "${rois}" | cut -d ',' -f2)" .nii.gz)"_native.nii.gz
			assoc_L=${outdir}/"$(basename "$(echo "${rois}" | cut -d ',' -f3)" .nii.gz)"_native.nii.gz
   			assoc_R=${outdir}/"$(basename "$(echo "${rois}" | cut -d ',' -f4)" .nii.gz)"_native.nii.gz
	  	fi
	fi

	
	#GATHER STATS
	mkdir -p "${outdir}/alps.stat"
	echo "id,scanner,x_proj_L,x_assoc_L,y_proj_L,z_assoc_L,x_proj_R,x_assoc_R,y_proj_R,z_assoc_R,alps_L,alps_R,alps" > "${outdir}/alps.stat/alps.csv"
	echo "id,scanner,diffusion_metric,proj_L,assoc_L,proj_R,assoc_R,mean_proj,mean_assoc" > "${outdir}/alps.stat/fa+md_alps.csv"
 
	if [[ "$dwi1" == *".nii" ]]; then 
		id="$(basename "$dwi1" .nii)"
	elif [[ $dwi1 == *".nii.gz" ]]; then
		id="$(basename "$dwi1" .nii.gz)"
	else
		id="$(basename "$dwi1")"
	fi

	x_proj_L="$(fslstats "${dxx}" -k "${proj_L}" -m)"
	x_assoc_L="$(fslstats "${dxx}" -k "${assoc_L}" -m)"
	y_proj_L="$(fslstats "${dyy}" -k "${proj_L}" -m)"
	z_assoc_L="$(fslstats "${dzz}" -k "${assoc_L}" -m)"
	x_proj_R="$(fslstats "${dxx}" -k "${proj_R}" -m)"
	x_assoc_R="$(fslstats "${dxx}" -k "${assoc_R}" -m)"
	y_proj_R="$(fslstats "${dyy}" -k "${proj_R}" -m)"
	z_assoc_R="$(fslstats "${dzz}" -k "${assoc_R}" -m)"
	alps_L=`echo "(($x_proj_L+$x_assoc_L)/2)/(($y_proj_L+$z_assoc_L)/2)" | bc -l` #proj1 and assoc1 are left side, bc -l needed for decimal printing results
	alps_R=`echo "(($x_proj_R+$x_assoc_R)/2)/(($y_proj_R+$z_assoc_R)/2)" | bc -l` #proj2 and assoc2 are right side, bc -l needed for decimal printing results
	alps=`echo "($alps_R+$alps_L)/2" | bc -l`

	echo "${id},${scanner1},${x_proj_L},${x_assoc_L},${y_proj_L},${z_assoc_L},${x_proj_R},${x_assoc_R},${y_proj_R},${z_assoc_R},${alps_L},${alps_R},${alps}" >> "${outdir}/alps.stat/alps.csv"

 	#FA and MD values from projection and association areas
  	for diff in "${fa}" "${md}"; do
   		pl="$(fslstats "${diff}" -k "${proj_L}" -m)"
     		pr="$(fslstats "${diff}" -k "${proj_R}" -m)"
       		al="$(fslstats "${diff}" -k "${assoc_L}" -m)"
	 	ar="$(fslstats "${diff}" -k "${assoc_R}" -m)"
   		pmean=`echo "($pl+$pr)/2" | bc -l`
     		amean=`echo "($al+$ar)/2" | bc -l`
       		if [ "${diff}" == "${fa}" ]; then d="FA"; else d="MD"; fi
   		echo "${id},${scanner1},${d},${pl},${al},${pr},${ar},${pmean},${amean}" >> "${outdir}/alps.stat/fa+md_alps.csv"
    	done
elif [ "$rois" == "0" ]; then 
	echo "ROI analysis skipped by the user.";
fi

echo "Finito! Please cite this repository (https://github.com/gbarisano/alps/) and the paper:
Liu, X, Barisano, G, et al., Cross-Vendor Test-Retest Validation of Diffusion Tensor Image Analysis along the Perivascular Space (DTI-ALPS) for Evaluating Glymphatic System Function, Aging and Disease (2023)"



