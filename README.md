# alps.sh

This is a ```bash``` script that automatically computes the diffusion along perivascular spaces (ALPS) metric from diffusion-weighted images (```dwi```).   
The ALPS index has been described by [Taoka et al. (Japanese Journal of Radiology, 2017)](https://link.springer.com/article/10.1007/s11604-017-0617-z)  
If you use this script, please cite our work: 

If you have any question, please contact me: barisano at stanford.edu.

## Table of contents
- [Required libraries](#required-libraries)
- [Required inputs](#required-inputs)
- [Optional inputs](#optional-inputs)
- [Optional arguments](#optional-arguments)
- [Outputs](#outputs)
- [Examples of usage](#examples-of-usage)

## Required libraries
- FSL v. 6.0.3 or newer (https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/FslInstallation) (it should work with older versions of FSL, but you might need to get the b02b0_1.cnf configuration file from newer FSL versions. This configuration file is needed in case your dwi input has odd number of slices)
- MRtrix3 (https://www.mrtrix.org/download) (only needed for preprocessing steps)

This script assumes that FSL and MRtrix3 are in your $PATH.

## Required inputs

You must define these elements (except when ```-s 1```, read [Optional arguments](#optional-arguments)):
- ```-a```: 4D ```NIfTI``` file of ```dwi``` (the first volume should be a B0 image)
- ```-b```: ```bval``` file
- ```-c```: ```bvec``` file
- ```-m```: BIDS sidecar ```json``` file including the metadata of the input ```dwi``` (not required, but HIGHLY RECOMMENDED)  
If you provide this file, then the script will try to perform eddy correction based on the acquisition parameters reported in the ```json``` file. The DTI fitting will use the eddy corrected data as input.
  If you do not provide this file, then NO eddy correction will be performed, and the DTI fitting will be performed on the raw ```dwi``` input or the preprocessed ```dwi``` input (if preprocessing is enabled).  
  The script has been tested with ```json``` files generated from ```dcm2niix``` (https://github.com/rordenlab/dcm2niix)

## Optional inputs
A second ```dwi``` dataset with opposite phase encoding (PE) direction to correct for susceptibility-induced distortions. 
To correct for susceptibility-induced distortions, the user must define the following 4 additional inputs:
  - ```-i```: 4D ```NIfTI``` file of the second ```dwi``` input (the first volume must be a B0 image and the PE direction must be opposite to the PE of the first ```dwi``` dataset in order to be used)
  - ```-j```: ```bval``` file of the second ```dwi``` input
  - ```-k```: ```bvec``` file of the second ```dwi``` input
  - ```-n```: BIDS sidecar ```json``` file of the second ```dwi``` input

## Optional arguments

  If the user does not specify these options, the script will use the default argument for each of them (see below)
  - ```-d```: determines which preprocessing steps need to be performed on the ```dwi``` input(s) [default = 1]
    - 0 = skip
    - 1 [default] = both denoising and unringing
    - 2 = only denoising
    - 3 = only unringing
  - ```-e```: determines which EDDY program to use [default = 1]
    - 0 = skip eddy correction (not recommended) (this is the same as running ```alps.sh``` without specifying the ```json``` file with the ```-m``` option, but using only the inputs ```-a```, ```-b```, and ```-c```); 
    - 1 [default] = try to use ```eddy_openmp```, and if not available will try to use ```eddy```; 
    - alternatively, the user can specify which eddy program to use (e.g., ```eddy_cuda```). The binary file specified by the user must be located in ```${FSLDIR}/bin/```
  - ```-r```: Region of interest (ROI) analysis [default = 1]
    - 0 = skip ROI analysis (the output ```csv``` file with ALPS index will NOT be generated)
    - 1 [default] = ROI analysis done using the provided ROIs drawn on FSL's ```JHU-ICBM-FA-1mm.nii.gz```:
      - ```L_SCR.nii.gz``` LEFT PROJECTION FIBERS (superior corona radiata)
      - ```R_SCR.nii.gz``` RIGHT PROJECTION FIBERS (superior corona radiata)
      - ```L_SLF.nii.gz``` LEFT ASSOCIATION FIBERS (superior longitudinal fasciculus)
      - ```R_SLF.nii.gz``` RIGHT ASSOCIATION FIBERS (superior longitudinal fasciculus)
    - alternatively, the user can specify a COMMA-SEPARATED list of 4 custom ROIs (```NIfTI``` binary masks), which MUST be in the following order: 
      1. ```LEFT``` PROJECTION FIBERS (superior corona radiata)
      2. ```RIGHT``` PROJECTION FIBERS (superior corona radiata)
      3. ```LEFT``` ASSOCIATION FIBERS (superior longitudinal fasciculus)
      4. ```RIGHT``` ASSOCIATION FIBERS (superior longitudinal fasciculus)
  - ```-t```: template to use for the ROI analysis [default = 1]. Only used if ```-r``` is not equal to 0. The DTI maps will be registered to the template specified by the user.
    - 0 = performs the analysis in NATIVE space. A list of 4 custom ROIs in NATIVE space must be specified with the ```-r``` option.
    - 1 [default] = ```JHU-ICBM-FA-1mm.nii.gz``` in FSLDIR will be used as template.
    - alternatively, the user can specify a ```NIfTI``` file to be used as a template. The ROIs must be in the same space of this template. The DTI maps will be registered to this template.
  - ```-o```: name of the output folder. If not specified, the default output folder will be called 'alps' and will be located in the same folder of the (first) input.
  - ```-s```: Option to skip preprocessing and DTI fitting, i.e. performs ONLY ROI analysis [default = 0]; 
    - 0 [default] = all the steps are performed; 
    - 1 = ONLY ROI analysis is performed;  
 If ```-s 1```, then ```-o``` MUST BE DEFINED and MUST CORRESPOND TO THE FOLDER WHERE dxx.nii.gz, dyy.nii.gz and dzz.nii.gz ARE LOCATED.  
 This option is useful for example when the user wants to perform the ROI analysis in NATIVE space with custom ROIs drawn on the output of the DTI processing steps (dti_FA.nii.gz) (see [Example 4](#4-alps-analysis-with-1-dwi-input-in-native-space--t-0-after-drawing-rois-on-the-output-dti_faniigz)). In this case, the user can run the ```alps``` script twice: the first time skipping the ROI analysis (```-r 0``` option), then draw the ROIs on the dti_FA.nii.gz output, and then re-run the ```alps``` script with the options ```-s 1```, ```-r myroi1.nii.gz,myroi2.nii.gz,myroi3.nii.gz,myroi4.nii.gz``` and ```-o outputdirectory``` (where "outputdirectory" is the directory where dti_FA.nii.gz and the other tensor files are located).  
 If you want to include the ```id``` name in the output csv file with the ALPS index, include the ```-a``` option with the ID you want to use (e.g., ```-a myID```; if ```-a``` is a ```.nii``` or ```.nii.gz``` file, then the file extension will be excluded from the ID name: ```-a mynifti.nii.gz``` will result in ID ```mynifti```).
  
## Outputs
- The main output is a ```csv``` file named ```alps.csv``` located in ```alps.stat``` folder in the output directory. This file includes the ```id``` (based on the ```-a``` input), the scanner manufacturer (based on the ```-m``` input), and the metrics required to compute the ALPS index, separately for the left and right side: 
 $$ALPS=mean(Dxproj,Dxassoc)/mean(Dyproj,Dzassoc)$$
The last column named ```alps``` is the average of the ALPS index on the left and right side.
- DTI FITTING outputs: these ```.nii.gz``` files are the outputs from the FSL command ```dtifit``` and their names start with ```dti_```
- TENSOR files: these ```vol000X.nii.gz``` files are the tensor files from ```dti_tensor.nii.gz``` separated in different volumes.
- ALPS tensor files: ```dxx.nii.gz```,```dyy.nii.gz```, and ```dzz.nii.gz``` are the tensor files used for the calculation of the ALPS index. If the analysis is done on a template space, the corresponding files transformed to the template space will be also output.
- Preprocessing outputs: for each input dwi, the following files will be possibly output (based on the user-defined ```-d``` option): ```dwi1.denoised.nii.gz```,```dwi1.unring.nii.gz```,```dwi1.denoised.unring.nii.gz```, which represents the denoised dwi image, the unringed dwi image, and the denoised+unringed dwi image, respectively. If 2 dwi inputs are provided, the output will be generated for each input.
- Eddy current correction outputs: these files' name starts with ```eddy_corrected_data.```
- TOPUP correction outputs: ```my_hifi_b0.nii.gz``` (the new B0 image corrected for susceptibility-induced distortions) and ```my_topup_results_fieldcoef.nii.gz``` (what topup thinks the off-resonance field looks like).

IMPORTANT: If Eddy current correction outputs are not present in the output folder, it means that the DTI fitting has been performed EITHER on preprocessed (denoised and/or unringed) input(s) OR on raw dwi input(s) if preprocessed data are not present in the output folder. If TOPUP correction outputs are not present in the output folder, it means that NO TOPUP correction has been applied (see the log for understanding the reason why).

## Examples of usage

### 1. ALPS analysis with 1 ```dwi``` input.

```alps.sh -a my_4D_dwi.nii.gz -b my_bval_file -c my_bvec_file -m my_bids_file.json```

This command will preprocess ```my_4D_dwi.nii.gz``` (denoising and unringing, i.e. default option ```-d```), perform eddy current correction on the preprocessed data, and compute the ALPS index using the provided default ROIs on FSL template ```JHU-ICBM-FA-1mm.nii.gz```. The output folder will be called with the default name "alps" and will be located in the same folder as the input.

### 2. ALPS analysis with 2 ```dwi``` inputs with opposite PE direction and B0 image as first volume in both inputs.

```alps.sh -a dwi_PA.nii.gz -b id_PA.bval -c id_PA.bvec -m id_PA.json -i dwi_AP.nii.gz -j id_AP.bval -k id_AP.bvec -n id_AP.json```

This command will preprocess both ```dwi_PA.nii.gz``` and ```dwi_AP.nii.gz``` (denoising and unringing, i.e. default option ```-d```), perform TOPUP and eddy current correction on the preprocessed data, and compute the ALPS index using the provided default ROIs on FSL template ```JHU-ICBM-FA-1mm.nii.gz```. The output folder will be called with the default name "alps" and will be located in the same folder as the FIRST input.

### 3. ALPS analysis with 1 ```dwi``` input, in native space (```-t 0```), and customized output folder (```-o my_output_folder```).

```alps.sh -a my_4D_dwi.nii.gz -b my_bval_file -c my_bvec_file -m my_bids_file.json -t 0 -r proj_L.nii.gz,proj_R.nii.gz,assoc_L.nii.gz,assoc_R.nii.gz -o my_output_folder```

This command will preprocess ```my_4D_dwi.nii.gz``` (denoising and unringing, i.e. default option ```-d```), perform eddy current correction on the preprocessed data, and compute the ALPS index in native space (```-t 0```) using the ROI files defined by the user, which MUST be in native space. The output folder will be "my_output_folder".

### 4. ALPS analysis with 1 ```dwi``` input in native space (```-t 0```) after drawing ROIs on the output dti_FA.nii.gz.
This is a 3-step process:
1. ```alps.sh -a my_4D_dwi.nii.gz -b my_bval_file -c my_bvec_file -m my_bids_file.json -r0 -o my_output_folder```  
This command will preprocess ```my_4D_dwi.nii.gz``` (denoising and unringing, i.e. default option ```-d```), perform eddy current correction on the preprocessed data, and output only the DTI fitting files in "my_output_folder".
2. Draw the ROIs in the generated FA map (native space): myroi1_native.nii.gz, myroi2_native.nii.gz, myroi3_native.nii.gz, myroi4_native.nii.gz
3. ```alps.sh -a my_4D_dwi.nii.gz -t 0 -s 1 -o my_output_folder -r myroi1_native.nii.gz,myroi2_native.nii.gz,myroi3_native.nii.gz,myroi4_native.nii.gz```
This command will skip all preprocessing steps and the DTI fitting step (```-s 1```) and will use the DTI fitting output files previously generated in "my_output_folder" to compute the ALPS index in native space (```-t 0```) using the user-defined ROIs (```-r myroi1_native.nii.gz,myroi2_native.nii.gz,myroi3_native.nii.gz,myroi4_native.nii.gz```).  
The option ```-a my_4D_dwi.nii.gz``` is not required in this latest command, but is only needed to add the ID in the final CSV output file with the ALPS index.


### 5. ALPS analysis without denoising and unringing (e.g., in case MRtrix3 is not available).

```alps.sh -a my_4D_dwi.nii.gz -b my_bval_file -c my_bvec_file -m my_bids_file.json -d 0 -r 1 -t 1```

This command will perform ONLY eddy current correction on the RAW ```dwi``` input data (not denoised nor unringed), and compute the ALPS index using the provided default ROIs on FSL template ```JHU-ICBM-FA-1mm.nii.gz```. The output folder will be called with the default name "alps" and will be located in the same folder as the input.

### 6. Minimal number of inputs (not recommended, because no eddy current correction will be performed).

```alps.sh -a my_4D_dwi.nii.gz -b my_bval_file -c my_bvec_file```

This command will preprocess ```my_4D_dwi.nii.gz``` (denoising and unringing, i.e. default option ```-d```) and compute the ALPS index using the provided default ROIs on FSL template ```JHU-ICBM-FA-1mm.nii.gz```. No eddy current correction will be applied, which is not recommended.



