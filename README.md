# alps.sh

This is a ```bash``` script that automatically computes the diffusion along perivascular spaces (ALPS) metric from diffusion-weighted images (```dwi```). 
The ALPS index has been described by Taoka et al. (Japanese Journal of Radiology, 2017)

## Required libraries
- FSL v. 6.0.3 or newer (https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/FslInstallation)
- MRtrix3 (https://www.mrtrix.org/download) (only needed for preprocessing steps)

This script assumes that FSL and MRtrix3 are in your $PATH.

## Required inputs

You must define these elements:
- ```-a```: 4D ```NIfTI``` file of ```dwi``` (the first volume should be a B0 image)
- ```-b```: ```bval``` file
- ```-c```: ```bvec``` file

## Optional inputs
1. ```-m```: BIDS sidecar ```json``` file including the metadata of the input ```dwi``` (HIGHLY RECOMMENDED)

  If you provide this file, then the script will try to perform eddy correction based on the acquisition parameters reported in the ```json``` file. The DTI fitting will use the eddy corrected data as input.
  If you do not provide this file, then no eddy correction will be performed, and the DTI fitting will be performed on the raw ```dwi``` input or the preprocessed ```dwi``` input (if preprocessing is enabled).

  The script has been tested with ```json``` files generated from ```dcm2niix``` (https://github.com/rordenlab/dcm2niix)

2. A second ```dwi``` dataset with opposite phase encoding (PE) direction to correct for susceptibility-induced distortions. 

  To correct for susceptibility-induced distortions, the user must define the following 4 additional inputs:
  - ```-i```: 4D ```NIfTI``` file of the second ```dwi``` input (the first volume must be a B0 image and the PE direction must be opposite to the PE of the first ```dwi``` dataset in order to be used)
  - ```-j```: ```bval``` file of the second ```dwi``` input
  - ```-k```: ```bvec``` file of the second ```dwi``` input
  - ```-n```: BIDS sidecar ```json``` file of the second ```dwi``` input

3. Optional inputs

  If the user does not specify these inputs, the script will use the default option for each of them (see below)
  - ```-d```: determines which preprocessing steps need to be performed on the ```dwi``` input(s) [default = 1]
    - 0 = skip
    - 1 [default] = both denoising and unringing
    - 2 = only denoising
    - 3 = only unringing
  - ```-r```: Region of interest (ROI) analysis [default = 1]
    - 0 = skip ROI analysis (the output ```csv``` file with ALPS index will NOT be generated)
    - 1 [default] = ROI analysis done using the provided ROIs drawn on FSL's ```JHU-ICBM-FA-1mm.nii.gz```:
      - ```L_SCR.nii.gz``` LEFT PROJECTION FIBERS (superior corona radiata)
      - ```R_SCR.nii.gz``` RIGHT PROJECTION FIBERS (superior corona radiata)
      - ```L_SLF.nii.gz``` LEFT ASSOCIATION FIBERS (superior longitudinal fasciculus)
      - ```R_SLF.nii.gz``` RIGHT ASSOCIATION FIBERS (superior longitudinal fasciculus)
    - alternatively, the user can specify a list of 4 custom ROIs (```NIfTI``` binary masks), which MUST be in the following order: 
      1. ```LEFT``` PROJECTION FIBERS (superior corona radiata)
      2. ```RIGHT``` PROJECTION FIBERS (superior corona radiata)
      3. ```LEFT``` ASSOCIATION FIBERS (superior longitudinal fasciculus)
      4. ```RIGHT``` ASSOCIATION FIBERS (superior longitudinal fasciculus)
  - ```-t```: template to use for the ROI analysis [default = 1]. Only used if ```-r``` is not equal to 0. The DTI maps will be registered to the template specified by the user.
    - 0 = performs the analysis in NATIVE space. A list of 4 custom ROIs in NATIVE space must be specified with the ```-r``` option.
    - 1 [default] = ```JHU-ICBM-FA-1mm.nii.gz``` in FSLDIR will be used as template.
    - alternatively, the user can specify a ```NIfTI``` file to be used as a template. The ROIs must be in the same space of this template. The DTI maps will be registered to this template.
  - ```-o```: name of the output folder. If not specified, the default output folder will be called 'alps' and will be located in the same folder of the (first) input.

## Example usage

1. ALPS analysis with 1 ```dwi``` input.

```alps.sh -a my_4D_dwi.nii.gz -b my_bval_file -c my_bvec_file -m my_bids_file.json```

This command will preprocess ```my_4D_dwi.nii.gz``` (denoising and unringing, i.e. default option ```-d```), perform eddy current correction on the preprocessed data, and compute the ALPS index using the provided default ROIs on FSL template ```JHU-ICBM-FA-1mm.nii.gz```. The output folder will be called with the default name "alps" and will be located in the same folder as the input.

2. ALPS analysis with 2 ```dwi``` inputs with opposite PE direction and B0 image as first volume in both inputs.

```alps.sh -a dwi_PA.nii.gz -b id_PA.bval -c id_PA.bvec -m id_PA.json -i dwi_AP.nii.gz -j id_AP.bval -k id_AP.bvec -n id_AP.json```

This command will preprocess both ```dwi_PA.nii.gz``` and ```dwi_AP.nii.gz``` (denoising and unringing, i.e. default option ```-d```), perform TOPUP and eddy current correction on the preprocessed data, and compute the ALPS index using the provided default ROIs on FSL template ```JHU-ICBM-FA-1mm.nii.gz```. The output folder will be called with the default name "alps" and will be located in the same folder as the FIRST input.

3. ALPS analysis with 1 ```dwi``` input, in native space (```-t 0```), and customized output folder (```-o my_output_folder```).

```alps.sh my_4D_dwi.nii.gz -b my_bval_file -c my_bvec_file -m my_bids_file.json -t 0 -r proj_L.nii.gz proj_R.nii.gz assoc_L.nii.gz assoc_R.nii.gz -o my_output_folder```

This command will preprocess ```my_4D_dwi.nii.gz``` (denoising and unringing, i.e. default option ```-d```), perform eddy current correction on the preprocessed data, and compute the ALPS index in native space (```-t 0```) using the ROIs file defined by the user, which MUST be in native space. on FSL template ```JHU-ICBM-FA-1mm.nii.gz```. The output folder will be "my_output_folder".

4. ALPS analysis without denoising and unringing (e.g., in case MRtrix3 is not available).

```alps.sh my_4D_dwi.nii.gz -b my_bval_file -c my_bvec_file -m my_bids_file.json -d 0 -r 1 -t 1```

This command will perform eddy current correction on the raw ```dwi``` input data and compute the ALPS index using the provided default ROIs on FSL template ```JHU-ICBM-FA-1mm.nii.gz```. The output folder will be called with the default name "alps" and will be located in the same folder as the input.

5. Minimal number of inputs (not recommended, because no eddy current correction will be performed).

```alps.sh -a my_4D_dwi.nii.gz -b my_bval_file -c my_bvec_file```

This command will preprocess ```my_4D_dwi.nii.gz``` (denoising and unringing, i.e. default option ```-d```) and compute the ALPS index using the provided default ROIs on FSL template ```JHU-ICBM-FA-1mm.nii.gz```. No eddy current correction will be applied, which is not recommended.



