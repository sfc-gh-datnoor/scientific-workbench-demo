-- =============================================================================
-- 15-monai-parabricks-tools.sql
-- Register NVIDIA MONAI and Parabricks tools in the workbench catalog.
-- Run as SYSADMIN after 14-tools.sql
-- =============================================================================
-- These tools expand the workbench into medical imaging (MONAI) and
-- GPU-accelerated genomics (Parabricks). They are registered in the
-- CATALOG.TOOLS table so the agent can describe them and scientists
-- can discover them in the Asset Catalog.
--
-- MONAI tools call the NVIDIA hosted API via NVIDIA_API_EAI (same as
-- the BioNeMo NIMs). Parabricks runs as a container CLI and requires
-- SPCS GPU compute; the procedures return instructions until SPCS
-- execution is configured.
-- =============================================================================

USE ROLE SYSADMIN;
USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA CATALOG;
USE WAREHOUSE WORKBENCH_S;

-- =============================================================================
-- 1. MONAI TOOLS — Medical Imaging AI
-- =============================================================================

-- MONAI VISTA-3D: Whole-body CT segmentation
CREATE OR REPLACE PROCEDURE CATALOG.RUN_MONAI_VISTA3D(
    "P_INPUT_STAGE_PATH" VARCHAR,
    "P_OUTPUT_TABLE" VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key' = SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT = 'TOOL:{"display_name":"MONAI VISTA-3D — Whole-body CT Segmentation","description":"Segment 127 anatomical structures in CT scans using NVIDIA MONAI VISTA-3D. Input: NIfTI file on a stage. Output: segmentation masks + organ labels.","domains":"imaging,radiology,clinical","params":{"input_stage_path":"STRING","output_table":"STRING"},"return_type":"VARCHAR","example":"CALL CATALOG.RUN_MONAI_VISTA3D(stage_path, output_table)"}'
AS
$$
import _snowflake
import requests
import json

def run(session, p_input_stage_path: str, p_output_table: str) -> str:
    api_key = _snowflake.get_generic_secret_string('nvidia_key')
    # MONAI VISTA-3D NIM endpoint
    url = "https://health.api.nvidia.com/v1/medicalimaging/nvidia/vista-3d"
    
    # Read the NIfTI file from stage
    try:
        stage_content = session.file.get(p_input_stage_path)
    except Exception as e:
        return json.dumps({"status": "error", "message": f"Cannot read from stage: {str(e)}. Ensure the NIfTI file is uploaded to a Snowflake stage."})
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/octet-stream",
        "Accept": "application/json"
    }
    
    try:
        resp = requests.post(url, headers=headers, data=stage_content, timeout=300)
        resp.raise_for_status()
        result = resp.json()
    except requests.exceptions.HTTPError as e:
        return json.dumps({"status": "error", "message": f"MONAI VISTA-3D API error: {str(e)}", "details": resp.text[:500] if resp else ""})
    except Exception as e:
        return json.dumps({"status": "error", "message": f"Request failed: {str(e)}"})
    
    # Write segmentation results to output table
    import snowflake.snowpark.functions as F
    df = session.create_dataframe([{
        "INPUT_PATH": p_input_stage_path,
        "MODEL": "VISTA-3D",
        "SEGMENTS_FOUND": len(result.get("segments", [])),
        "RESULT": json.dumps(result),
    }])
    df.write.mode("overwrite").save_as_table(p_output_table)
    
    n_segments = len(result.get("segments", []))
    return json.dumps({"status": "success", "segments_found": n_segments, "output_table": p_output_table})
$$;

-- MONAI Lung Nodule Detection
CREATE OR REPLACE PROCEDURE CATALOG.RUN_MONAI_LUNG_NODULE(
    "P_INPUT_STAGE_PATH" VARCHAR,
    "P_OUTPUT_TABLE" VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key' = SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT = 'TOOL:{"display_name":"MONAI Lung Nodule Detection","description":"Detect and classify lung nodules in chest CT scans using NVIDIA MONAI. Returns nodule locations, sizes, and malignancy scores.","domains":"imaging,radiology,oncology","params":{"input_stage_path":"STRING","output_table":"STRING"},"return_type":"VARCHAR","example":"CALL CATALOG.RUN_MONAI_LUNG_NODULE(stage_path, output_table)"}'
AS
$$
import _snowflake
import requests
import json

def run(session, p_input_stage_path: str, p_output_table: str) -> str:
    api_key = _snowflake.get_generic_secret_string('nvidia_key')
    url = "https://health.api.nvidia.com/v1/medicalimaging/nvidia/lung-nodule-ct-detection"
    
    try:
        stage_content = session.file.get(p_input_stage_path)
    except Exception as e:
        return json.dumps({"status": "error", "message": f"Cannot read from stage: {str(e)}. Ensure the NIfTI/DICOM file is uploaded to a Snowflake stage."})
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/octet-stream",
        "Accept": "application/json"
    }
    
    try:
        resp = requests.post(url, headers=headers, data=stage_content, timeout=300)
        resp.raise_for_status()
        result = resp.json()
    except requests.exceptions.HTTPError as e:
        return json.dumps({"status": "error", "message": f"MONAI Lung Nodule API error: {str(e)}", "details": resp.text[:500] if resp else ""})
    except Exception as e:
        return json.dumps({"status": "error", "message": f"Request failed: {str(e)}"})
    
    nodules = result.get("nodules", result.get("detections", []))
    import snowflake.snowpark.functions as F
    rows = []
    for i, nodule in enumerate(nodules):
        rows.append({
            "INPUT_PATH": p_input_stage_path,
            "NODULE_ID": i + 1,
            "LOCATION_X": nodule.get("x", nodule.get("center", [0,0,0])[0]),
            "LOCATION_Y": nodule.get("y", nodule.get("center", [0,0,0])[1]),
            "LOCATION_Z": nodule.get("z", nodule.get("center", [0,0,0])[2]),
            "DIAMETER_MM": nodule.get("diameter_mm", nodule.get("size", 0)),
            "CONFIDENCE": nodule.get("confidence", nodule.get("score", 0)),
            "RESULT_JSON": json.dumps(nodule),
        })
    if not rows:
        rows = [{"INPUT_PATH": p_input_stage_path, "NODULE_ID": 0, "LOCATION_X": None, "LOCATION_Y": None, "LOCATION_Z": None, "DIAMETER_MM": None, "CONFIDENCE": None, "RESULT_JSON": json.dumps(result)}]
    
    df = session.create_dataframe(rows)
    df.write.mode("overwrite").save_as_table(p_output_table)
    
    return json.dumps({"status": "success", "nodules_detected": len(nodules), "output_table": p_output_table})
$$;

-- =============================================================================
-- 2. PARABRICKS TOOLS — GPU-accelerated Genomics
-- =============================================================================
-- Parabricks runs as a container CLI (pbrun), not an HTTP API.
-- These procedures are stubs that will execute via SPCS when the
-- gateway service is deployed. For now they document the interface.

CREATE OR REPLACE PROCEDURE CATALOG.RUN_PARABRICKS_FQ2BAM(
    "P_FASTQ_R1" VARCHAR,
    "P_FASTQ_R2" VARCHAR,
    "P_REFERENCE_GENOME" VARCHAR,
    "P_OUTPUT_TABLE" VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
COMMENT = 'TOOL:{"display_name":"Parabricks FASTQ-to-BAM Alignment","description":"GPU-accelerated FASTQ to sorted BAM alignment using NVIDIA Parabricks (pbrun fq2bam). 30-50x faster than CPU BWA-MEM. Requires SPCS GPU compute pool with Parabricks container.","domains":"genomics,ngs,alignment","params":{"fastq_r1":"STRING","fastq_r2":"STRING","reference_genome":"STRING","output_table":"STRING"},"return_type":"VARCHAR","example":"CALL CATALOG.RUN_PARABRICKS_FQ2BAM(r1_path, r2_path, ref_genome, output_table)"}'
AS
$$
import json

def run(session, p_fastq_r1: str, p_fastq_r2: str, p_reference_genome: str, p_output_table: str) -> str:
    return json.dumps({
        "status": "pending_spcs",
        "message": "Parabricks fq2bam requires an SPCS GPU compute pool with the Parabricks container. This tool will be callable once the NIM gateway service is deployed. Input files should be staged at @SCIENTIFIC_WORKBENCH.CATALOG.GENOMICS_DATA.",
        "tool": "pbrun fq2bam",
        "inputs": {"fastq_r1": p_fastq_r1, "fastq_r2": p_fastq_r2, "reference": p_reference_genome},
        "gpu_requirement": "GPU_NV_S (A10G 24GB) minimum",
        "reference_genome_size": "~30 GB for GRCh38"
    })
$$;

CREATE OR REPLACE PROCEDURE CATALOG.RUN_PARABRICKS_HAPLOTYPECALLER(
    "P_INPUT_BAM" VARCHAR,
    "P_REFERENCE_GENOME" VARCHAR,
    "P_OUTPUT_TABLE" VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
COMMENT = 'TOOL:{"display_name":"Parabricks HaplotypeCaller","description":"GPU-accelerated germline variant calling using NVIDIA Parabricks (pbrun haplotypecaller). Produces GVCF/VCF output compatible with GATK. Requires SPCS GPU compute pool.","domains":"genomics,variant-calling,clinical","params":{"input_bam":"STRING","reference_genome":"STRING","output_table":"STRING"},"return_type":"VARCHAR","example":"CALL CATALOG.RUN_PARABRICKS_HAPLOTYPECALLER(bam_path, ref_genome, output_table)"}'
AS
$$
import json

def run(session, p_input_bam: str, p_reference_genome: str, p_output_table: str) -> str:
    return json.dumps({
        "status": "pending_spcs",
        "message": "Parabricks HaplotypeCaller requires an SPCS GPU compute pool. This tool will be callable once the NIM gateway service is deployed.",
        "tool": "pbrun haplotypecaller",
        "inputs": {"input_bam": p_input_bam, "reference": p_reference_genome},
        "gpu_requirement": "GPU_NV_S (A10G 24GB) minimum"
    })
$$;

CREATE OR REPLACE PROCEDURE CATALOG.RUN_PARABRICKS_DEEPVARIANT(
    "P_INPUT_BAM" VARCHAR,
    "P_REFERENCE_GENOME" VARCHAR,
    "P_OUTPUT_TABLE" VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
COMMENT = 'TOOL:{"display_name":"Parabricks DeepVariant","description":"GPU-accelerated deep learning variant calling using NVIDIA Parabricks (pbrun deepvariant). Higher accuracy than traditional methods for germline SNPs and indels. Requires SPCS GPU compute pool.","domains":"genomics,variant-calling,deep-learning","params":{"input_bam":"STRING","reference_genome":"STRING","output_table":"STRING"},"return_type":"VARCHAR","example":"CALL CATALOG.RUN_PARABRICKS_DEEPVARIANT(bam_path, ref_genome, output_table)"}'
AS
$$
import json

def run(session, p_input_bam: str, p_reference_genome: str, p_output_table: str) -> str:
    return json.dumps({
        "status": "pending_spcs",
        "message": "Parabricks DeepVariant requires an SPCS GPU compute pool. This tool will be callable once the NIM gateway service is deployed.",
        "tool": "pbrun deepvariant",
        "inputs": {"input_bam": p_input_bam, "reference": p_reference_genome},
        "gpu_requirement": "GPU_NV_S (A10G 24GB) minimum, GPU_NV_M recommended for WGS"
    })
$$;

-- =============================================================================
-- 3. REGISTER ALL NEW TOOLS
-- =============================================================================

-- MONAI Tools
CALL CATALOG.REGISTER_TOOL(
    'run_monai_vista3d',
    'MONAI VISTA-3D — Whole-body CT Segmentation',
    'Segment 127 anatomical structures in CT scans using NVIDIA MONAI VISTA-3D. Input: NIfTI file on a stage. Output: segmentation masks with organ labels.',
    'imaging,radiology,clinical',
    'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_MONAI_VISTA3D',
    '{"input_stage_path":"STRING","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_MONAI_VISTA3D(''@stage/scan.nii.gz'', ''RESULTS.VISTA3D_OUTPUT'')'
);

CALL CATALOG.REGISTER_TOOL(
    'run_monai_lung_nodule',
    'MONAI Lung Nodule Detection',
    'Detect and classify lung nodules in chest CT scans using NVIDIA MONAI. Returns nodule locations, sizes, and malignancy confidence scores.',
    'imaging,radiology,oncology',
    'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_MONAI_LUNG_NODULE',
    '{"input_stage_path":"STRING","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_MONAI_LUNG_NODULE(''@stage/chest_ct.nii.gz'', ''RESULTS.NODULE_OUTPUT'')'
);

-- Parabricks Tools
CALL CATALOG.REGISTER_TOOL(
    'run_parabricks_fq2bam',
    'Parabricks FASTQ-to-BAM Alignment',
    'GPU-accelerated FASTQ to sorted BAM alignment using NVIDIA Parabricks (pbrun fq2bam). 30-50x faster than CPU BWA-MEM + samtools. Requires SPCS GPU compute.',
    'genomics,ngs,alignment',
    'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_PARABRICKS_FQ2BAM',
    '{"fastq_r1":"STRING","fastq_r2":"STRING","reference_genome":"STRING","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_PARABRICKS_FQ2BAM(''@stage/sample_R1.fq.gz'', ''@stage/sample_R2.fq.gz'', ''GRCh38'', ''RESULTS.ALIGNMENT_OUTPUT'')'
);

CALL CATALOG.REGISTER_TOOL(
    'run_parabricks_haplotypecaller',
    'Parabricks HaplotypeCaller',
    'GPU-accelerated germline variant calling using NVIDIA Parabricks. GATK-compatible GVCF/VCF output. 20-30x faster than CPU GATK HaplotypeCaller. Requires SPCS GPU compute.',
    'genomics,variant-calling,clinical',
    'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_PARABRICKS_HAPLOTYPECALLER',
    '{"input_bam":"STRING","reference_genome":"STRING","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_PARABRICKS_HAPLOTYPECALLER(''@stage/sample.bam'', ''GRCh38'', ''RESULTS.VARIANT_OUTPUT'')'
);

CALL CATALOG.REGISTER_TOOL(
    'run_parabricks_deepvariant',
    'Parabricks DeepVariant',
    'GPU-accelerated deep learning variant calling using NVIDIA Parabricks. Higher accuracy than traditional methods for germline SNPs and indels. Requires SPCS GPU compute.',
    'genomics,variant-calling,deep-learning',
    'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_PARABRICKS_DEEPVARIANT',
    '{"input_bam":"STRING","reference_genome":"STRING","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_PARABRICKS_DEEPVARIANT(''@stage/sample.bam'', ''GRCh38'', ''RESULTS.DEEPVARIANT_OUTPUT'')'
);

-- =============================================================================
-- 4. RESEED ASSET CATALOG
-- =============================================================================
CALL CATALOG.SEED_ASSETS();

-- =============================================================================
-- 5. VERIFICATION
-- =============================================================================
SELECT 'New Tools' AS check_name,
       COUNT(*) AS count,
       LISTAGG(display_name, ', ') WITHIN GROUP (ORDER BY name) AS tools
FROM CATALOG.TOOLS
WHERE name LIKE 'run_monai%' OR name LIKE 'run_parabricks%';
