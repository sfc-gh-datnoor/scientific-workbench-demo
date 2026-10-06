-- =============================================================================
-- !! READ BEFORE DEPLOYING ANY SERVICE IN THIS FILE !!
-- =============================================================================
-- STATUS 2026-09-01: these specs DEPLOY correctly but the tools CANNOT CALL them.
-- Boltz-2 was mirrored (amd64) and NIM_BOLTZ2_SVC reached READY on an L40S with
-- restartCount 0, serving its own /v1/health/ready probes. The container, GPU,
-- pool, spec and mirroring pipeline are all proven working.
--
-- What does NOT work is the integration. Pointing RUN_BOLTZ2 at the service
-- fails with:
--     Failed to connect to host='sfc-endpoint-login.snowflakecomputing.app'
--
-- CAUSE: Snowflake permits only two callers to reach a service endpoint,
-- service FUNCTIONS and other SERVICES. The NIM HTTP call in tools/nvidia/*.sql
-- lives in a STORED PROCEDURE, which is neither, so its only route is the public
-- ingress, and that requires Snowflake OAuth which the procedure cannot present.
-- An NVIDIA bearer token is not accepted.
--
-- CONSEQUENCE: deploying these services costs GPU credits and yields nothing
-- callable until the integration is changed. Do not schedule SPCS mirroring work
-- expecting tools to start using it.
--
-- TWO WAYS FORWARD:
--   1. Move the HTTP call into the React app, which IS a service and can reach
--      NIMs at their internal DNS (e.g. nim-boltz2-svc.<hash>.svc.spcs.internal).
--      Downside: Cortex Agents invoke tools via SQL, so they lose SPCS access.
--   2. RECOMMENDED. Add ONE gateway service fronted by a service function that
--      forwards to whichever NIM over internal DNS. Keeps the existing CALL
--      interface working for BOTH the app and the agents, and is one adapter
--      rather than ten. Note a service function sends Snowflake batch JSON
--      ({"data":[[0,...]]}), which a NIM cannot parse, so the gateway must
--      translate.
--
-- ALSO NOTE:
--   - 'public: true' below is unnecessary for every service here. Private
--     endpoints are already reachable by service functions and other services.
--     Making them public is what produced the misleading login redirect above
--     instead of a clean refusal.
--   - Mirror images by amd64 DIGEST. Docker on Apple Silicon pulls arm64 and the
--     container then dies with "exec /bin/bash: exec format error". Beware that
--     'docker pull --platform linux/amd64' silently reuses a cached index and
--     reports "Image is up to date" while leaving the wrong arch in place, and
--     that on Docker 29 'docker image inspect' reports empty Os/Architecture for
--     a multi-platform tag. Use 'docker buildx imagetools inspect --raw'.
--   - msa_search cannot run here as specified: its reference databases are
--     ~1.2 TB against a 93 GiB node cap, so it needs a block volume.
--   - evo2 has no spec in this file because its ~89 GiB runtime against the
--     93 GiB cap was never measured.
-- =============================================================================

-- =============================================================================
-- 10-nim-spcs-services.sql
-- SPCS Service Definitions for NVIDIA BioNeMo NIM Containers
-- Run as SYSADMIN
-- =============================================================================
-- Prerequisites:
--   - Compute pools exist (02-warehouses.sql): NIM_GPU_A10G_POOL, NIM_GPU_L40S_POOL
--   - Image repository exists (02-warehouses.sql): SCIENTIFIC_WORKBENCH.CATALOG.NIM_GPU_IMAGES
--   - NGC_API_KEY secret exists (00-prerequisites.sql)
--   - NIM_RUNTIME_EAI exists (00-prerequisites.sql)
--   - Images mirrored from nvcr.io (use NIM_BUILD_POOL + mirroring job)
--
-- DEPLOYMENT NOTES:
--   Startup timing (pool already IDLE):
--     - CREATE SERVICE to container start: ~3.5 min (image pull)
--     - Container start to READY: ~4 min (weight download + engine init)
--     - Total: ~7.5 min
--   Add 11–15 min if pool must provision a node first.
--
--   /dev/shm REQUIREMENT:
--   All PyTorch-based NIM containers require a shared memory volume at /dev/shm.
--   SPCS has no --shm-size flag; the equivalent is a source:memory volume.
--   Without it, the container will not start.
--
--   ENDPOINT DISCOVERY:
--   Container inference paths DIFFER from hosted API paths. The only reliable
--   source is the running container's /openapi.json. Do not hardcode from docs.
--   Example: Boltz-2 hosted = /v1/biology/nvidia/boltz-1
--            Boltz-2 SPCS   = /biology/mit/boltz2/predict
--
--   NODE STORAGE CAP:
--   All instance families cap at 93.13 GiB (including H100/H200).
--   Runtime budget = unpacked_image + weights + working_space < 93.13 GiB.
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA CATALOG;

-- =============================================================================
-- BOLTZ-2 (VERIFIED — 2026-08-26)
-- =============================================================================
-- Image: nvcr.io/nim/mit/boltz2:1.8.0 (9.93 GiB compressed, 109 layers)
-- GPU: L40S 48 GiB VRAM (GPU_L40S_G1_16)
-- Inference: 2.3 s warm. No TensorRT compilation on first request.
-- Endpoint: POST /biology/mit/boltz2/predict
-- Request: {polymers: [{id, molecule_type, sequence}], ligands: [{id, smiles, predict_affinity}]}
-- Response: mmCIF structure + confidence_scores + affinity_pic50
-- NOTE: predict_affinity is a LIGAND property. Put it at request root = silent failure.
-- NOTE: /openapi.json reports info.version 1.7.0 for image tag 1.8.0. Ignore it.
-- Max: 12 polymers, 20 ligands. molecule_type enum: dna | rna | protein

DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_BOLTZ2_SVC;

CREATE SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_BOLTZ2_SVC
  IN COMPUTE POOL NIM_GPU_L40S_POOL
  FROM SPECIFICATION $$
spec:
  containers:
    - name: boltz2
      image: /SCIENTIFIC_WORKBENCH/CATALOG/NIM_GPU_IMAGES/boltz2:1.8.0
      env:
        NIM_HTTP_API_PORT: "8000"
        NIM_LOG_LEVEL: "INFO"
      secrets:
        - snowflakeSecret: SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY
          secretKeyRef: SECRET_STRING
          envVarName: NGC_API_KEY
      volumeMounts:
        - name: dshm
          mountPath: /dev/shm
      resources:
        requests:
          nvidia.com/gpu: 1
          memory: 32Gi
        limits:
          nvidia.com/gpu: 1
          memory: 90Gi
      readinessProbe:
        port: 8000
        path: /v1/health/ready
  endpoints:
    - name: boltz2
      port: 8000
      public: true
  volumes:
    - name: dshm
      source: memory
      size: 16Gi
  $$
  EXTERNAL_ACCESS_INTEGRATIONS = (NIM_RUNTIME_EAI)
  MIN_INSTANCES = 1
  MAX_INSTANCES = 1
  COMMENT = 'Boltz-2 NIM: co-folding + binding affinity. VERIFIED on L40S 2026-08-26.';

-- =============================================================================
-- GENMOL (template — endpoint path UNVERIFIED on SPCS)
-- =============================================================================
-- Image: nvcr.io/nim/nvidia/genmol:latest (9.44 GiB compressed)
-- GPU: A10G 24 GiB (GPU_NV_S) — lightweight model
-- SPECIAL: Requires huggingface.co egress for tokenizer download at model-init.
--          This is GenMol-specific and not covered by a weight cache.
-- Runtime footprint: ~30 GiB — well within 93.13 GiB cap
-- Endpoint: UNKNOWN — read from container /openapi.json after deployment
-- Previously ran on GPU_NV_M (4x A10G) — overkill, single A10G likely sufficient

-- DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_GENMOL_SVC;
--
-- CREATE SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_GENMOL_SVC
--   IN COMPUTE POOL NIM_GPU_A10G_POOL
--   FROM SPECIFICATION $$
-- spec:
--   containers:
--     - name: genmol
--       image: /SCIENTIFIC_WORKBENCH/CATALOG/NIM_GPU_IMAGES/genmol:latest
--       env:
--         NIM_HTTP_API_PORT: "8000"
--         NIM_LOG_LEVEL: "INFO"
--       secrets:
--         - snowflakeSecret: SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY
--           secretKeyRef: SECRET_STRING
--           envVarName: NGC_API_KEY
--       volumeMounts:
--         - name: dshm
--           mountPath: /dev/shm
--       resources:
--         requests:
--           nvidia.com/gpu: 1
--           memory: 8Gi
--         limits:
--           nvidia.com/gpu: 1
--           memory: 24Gi
--       readinessProbe:
--         port: 8000
--         path: /v1/health/ready
--   endpoints:
--     - name: genmol
--       port: 8000
--       public: true
--   volumes:
--     - name: dshm
--       source: memory
--       size: 16Gi
--   $$
--   EXTERNAL_ACCESS_INTEGRATIONS = (NIM_RUNTIME_EAI)
--   MIN_INSTANCES = 1
--   MAX_INSTANCES = 1
--   COMMENT = 'GenMol NIM: de novo molecule generation. UNVERIFIED on SPCS.';

-- =============================================================================
-- DIFFDOCK (template — endpoint path UNVERIFIED on SPCS)
-- =============================================================================
-- Image: nvcr.io/nim/mit/diffdock:latest (15.33 GiB compressed)
-- GPU: L40S 48 GiB (conservative — may work on A100 40 GiB, UNTESTED)
-- Runtime footprint: ~46 GiB unpack + weights — probably fits 93.13 GiB
-- Endpoint: UNKNOWN — read from container /openapi.json after deployment

-- DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_DIFFDOCK_SVC;
--
-- CREATE SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_DIFFDOCK_SVC
--   IN COMPUTE POOL NIM_GPU_L40S_POOL
--   FROM SPECIFICATION $$
-- spec:
--   containers:
--     - name: diffdock
--       image: /SCIENTIFIC_WORKBENCH/CATALOG/NIM_GPU_IMAGES/diffdock:latest
--       env:
--         NIM_HTTP_API_PORT: "8000"
--         NIM_LOG_LEVEL: "INFO"
--       secrets:
--         - snowflakeSecret: SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY
--           secretKeyRef: SECRET_STRING
--           envVarName: NGC_API_KEY
--       volumeMounts:
--         - name: dshm
--           mountPath: /dev/shm
--       resources:
--         requests:
--           nvidia.com/gpu: 1
--           memory: 32Gi
--         limits:
--           nvidia.com/gpu: 1
--           memory: 64Gi
--       readinessProbe:
--         port: 8000
--         path: /v1/health/ready
--   endpoints:
--     - name: diffdock
--       port: 8000
--       public: true
--   volumes:
--     - name: dshm
--       source: memory
--       size: 16Gi
--   $$
--   EXTERNAL_ACCESS_INTEGRATIONS = (NIM_RUNTIME_EAI)
--   MIN_INSTANCES = 1
--   MAX_INSTANCES = 1
--   COMMENT = 'DiffDock NIM: molecular docking. UNVERIFIED on SPCS.';

-- =============================================================================
-- RFDIFFUSION (template — image mirrored, NOT served)
-- =============================================================================
-- Image: nvcr.io/nim/nvidia/rfdiffusion:2.3.0 (16.37 GiB compressed — largest NIM)
-- GPU: L40S 48 GiB (likely requirement, UNTESTED)
-- Runtime footprint: ~49 GiB unpack + weights — probably fits 93.13 GiB
-- Endpoint: UNKNOWN — image mirrored and digest verified but never started
-- Digest: verified post-mirror, not served

-- DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_RFDIFFUSION_SVC;
--
-- CREATE SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_RFDIFFUSION_SVC
--   IN COMPUTE POOL NIM_GPU_L40S_POOL
--   FROM SPECIFICATION $$
-- spec:
--   containers:
--     - name: rfdiffusion
--       image: /SCIENTIFIC_WORKBENCH/CATALOG/NIM_GPU_IMAGES/rfdiffusion:2.3.0
--       env:
--         NIM_HTTP_API_PORT: "8000"
--         NIM_LOG_LEVEL: "INFO"
--       secrets:
--         - snowflakeSecret: SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY
--           secretKeyRef: SECRET_STRING
--           envVarName: NGC_API_KEY
--       volumeMounts:
--         - name: dshm
--           mountPath: /dev/shm
--       resources:
--         requests:
--           nvidia.com/gpu: 1
--           memory: 32Gi
--         limits:
--           nvidia.com/gpu: 1
--           memory: 90Gi
--       readinessProbe:
--         port: 8000
--         path: /v1/health/ready
--   endpoints:
--     - name: rfdiffusion
--       port: 8000
--       public: true
--   volumes:
--     - name: dshm
--       source: memory
--       size: 16Gi
--   $$
--   EXTERNAL_ACCESS_INTEGRATIONS = (NIM_RUNTIME_EAI)
--   MIN_INSTANCES = 1
--   MAX_INSTANCES = 1
--   COMMENT = 'RFdiffusion NIM: backbone design. UNVERIFIED — image mirrored, not served.';

-- =============================================================================
-- PROTEINMPNN (template — endpoint path UNVERIFIED on SPCS)
-- =============================================================================
-- Image: nvcr.io/nim/nvidia/proteinmpnn:latest (8.60 GiB compressed — smallest NIM)
-- GPU: A10G 24 GiB (lightweight model)
-- Runtime footprint: ~26 GiB unpack + small weights — well within cap
-- Endpoint: UNKNOWN — read from container /openapi.json after deployment
-- License: NGC click-through returned HTTP 200 on this org (already accepted)

-- DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_PROTEINMPNN_SVC;
--
-- CREATE SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_PROTEINMPNN_SVC
--   IN COMPUTE POOL NIM_GPU_A10G_POOL
--   FROM SPECIFICATION $$
-- spec:
--   containers:
--     - name: proteinmpnn
--       image: /SCIENTIFIC_WORKBENCH/CATALOG/NIM_GPU_IMAGES/proteinmpnn:latest
--       env:
--         NIM_HTTP_API_PORT: "8000"
--         NIM_LOG_LEVEL: "INFO"
--       secrets:
--         - snowflakeSecret: SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY
--           secretKeyRef: SECRET_STRING
--           envVarName: NGC_API_KEY
--       volumeMounts:
--         - name: dshm
--           mountPath: /dev/shm
--       resources:
--         requests:
--           nvidia.com/gpu: 1
--           memory: 8Gi
--         limits:
--           nvidia.com/gpu: 1
--           memory: 24Gi
--       readinessProbe:
--         port: 8000
--         path: /v1/health/ready
--   endpoints:
--     - name: proteinmpnn
--       port: 8000
--       public: true
--   volumes:
--     - name: dshm
--       source: memory
--       size: 8Gi
--   $$
--   EXTERNAL_ACCESS_INTEGRATIONS = (NIM_RUNTIME_EAI)
--   MIN_INSTANCES = 1
--   MAX_INSTANCES = 1
--   COMMENT = 'ProteinMPNN NIM: inverse folding. UNVERIFIED on SPCS.';

-- =============================================================================
-- MOLMIM (template — endpoint path UNVERIFIED on SPCS)
-- =============================================================================
-- Image: nvcr.io/nim/nvidia/molmim:latest (13.04 GiB compressed)
-- GPU: A10G 24 GiB (may fit) or L40S (conservative)
-- Runtime footprint: ~39 GiB unpack + weights — probably fits on A10G

-- DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_MOLMIM_SVC;
--
-- CREATE SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_MOLMIM_SVC
--   IN COMPUTE POOL NIM_GPU_A10G_POOL
--   FROM SPECIFICATION $$
-- spec:
--   containers:
--     - name: molmim
--       image: /SCIENTIFIC_WORKBENCH/CATALOG/NIM_GPU_IMAGES/molmim:latest
--       env:
--         NIM_HTTP_API_PORT: "8000"
--         NIM_LOG_LEVEL: "INFO"
--       secrets:
--         - snowflakeSecret: SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY
--           secretKeyRef: SECRET_STRING
--           envVarName: NGC_API_KEY
--       volumeMounts:
--         - name: dshm
--           mountPath: /dev/shm
--       resources:
--         requests:
--           nvidia.com/gpu: 1
--           memory: 16Gi
--         limits:
--           nvidia.com/gpu: 1
--           memory: 48Gi
--       readinessProbe:
--         port: 8000
--         path: /v1/health/ready
--   endpoints:
--     - name: molmim
--       port: 8000
--       public: true
--   volumes:
--     - name: dshm
--       source: memory
--       size: 16Gi
--   $$
--   EXTERNAL_ACCESS_INTEGRATIONS = (NIM_RUNTIME_EAI)
--   MIN_INSTANCES = 1
--   MAX_INSTANCES = 1
--   COMMENT = 'MolMIM NIM: latent-space molecule optimization. UNVERIFIED on SPCS.';

-- =============================================================================
-- OPENFOLD2 (template — endpoint path UNVERIFIED on SPCS)
-- =============================================================================
-- Image: nvcr.io/nim/nvidia/openfold2:latest (size between 8–10 GiB compressed)
-- GPU: A10G 24 GiB (monomer only, lighter than OpenFold3)

-- DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_OPENFOLD2_SVC;
--
-- CREATE SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_OPENFOLD2_SVC
--   IN COMPUTE POOL NIM_GPU_A10G_POOL
--   FROM SPECIFICATION $$
-- spec:
--   containers:
--     - name: openfold2
--       image: /SCIENTIFIC_WORKBENCH/CATALOG/NIM_GPU_IMAGES/openfold2:latest
--       env:
--         NIM_HTTP_API_PORT: "8000"
--         NIM_LOG_LEVEL: "INFO"
--       secrets:
--         - snowflakeSecret: SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY
--           secretKeyRef: SECRET_STRING
--           envVarName: NGC_API_KEY
--       volumeMounts:
--         - name: dshm
--           mountPath: /dev/shm
--       resources:
--         requests:
--           nvidia.com/gpu: 1
--           memory: 16Gi
--         limits:
--           nvidia.com/gpu: 1
--           memory: 48Gi
--       readinessProbe:
--         port: 8000
--         path: /v1/health/ready
--   endpoints:
--     - name: openfold2
--       port: 8000
--       public: true
--   volumes:
--     - name: dshm
--       source: memory
--       size: 16Gi
--   $$
--   EXTERNAL_ACCESS_INTEGRATIONS = (NIM_RUNTIME_EAI)
--   MIN_INSTANCES = 1
--   MAX_INSTANCES = 1
--   COMMENT = 'OpenFold2 NIM: monomer structure prediction. UNVERIFIED on SPCS.';

-- =============================================================================
-- OPENFOLD3 (template — endpoint path UNVERIFIED on SPCS)
-- =============================================================================
-- Image: nvcr.io/nim/nvidia/openfold3:latest (10.19 GiB compressed)
-- GPU: L40S 48 GiB (complex prediction likely needs >24 GiB VRAM)
-- Runtime footprint: ~31 GiB unpack + ~40 GiB weights — probably fits
-- Endpoint: UNKNOWN — documented as open item. Read from /openapi.json.
-- NOTE: RTX PRO 6000 (96 GiB) compatibility UNKNOWN per NVIDIA support matrices.

-- DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_OPENFOLD3_SVC;
--
-- CREATE SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_OPENFOLD3_SVC
--   IN COMPUTE POOL NIM_GPU_L40S_POOL
--   FROM SPECIFICATION $$
-- spec:
--   containers:
--     - name: openfold3
--       image: /SCIENTIFIC_WORKBENCH/CATALOG/NIM_GPU_IMAGES/openfold3:latest
--       env:
--         NIM_HTTP_API_PORT: "8000"
--         NIM_LOG_LEVEL: "INFO"
--       secrets:
--         - snowflakeSecret: SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY
--           secretKeyRef: SECRET_STRING
--           envVarName: NGC_API_KEY
--       volumeMounts:
--         - name: dshm
--           mountPath: /dev/shm
--       resources:
--         requests:
--           nvidia.com/gpu: 1
--           memory: 32Gi
--         limits:
--           nvidia.com/gpu: 1
--           memory: 90Gi
--       readinessProbe:
--         port: 8000
--         path: /v1/health/ready
--   endpoints:
--     - name: openfold3
--       port: 8000
--       public: true
--   volumes:
--     - name: dshm
--       source: memory
--       size: 16Gi
--   $$
--   EXTERNAL_ACCESS_INTEGRATIONS = (NIM_RUNTIME_EAI)
--   MIN_INSTANCES = 1
--   MAX_INSTANCES = 1
--   COMMENT = 'OpenFold3 NIM: complex structure prediction. UNVERIFIED on SPCS.';

-- =============================================================================
-- MSA-SEARCH (template — SPECIAL: requires block volume for reference databases)
-- =============================================================================
-- Image: nvcr.io/nim/nvidia/msa-search:latest (8.64 GiB compressed)
-- GPU: A10G (computation is CPU/IO heavy, GPU for acceleration)
-- CRITICAL: Reference databases are 100 MB (pdb70 test) to 1.2 TB (full).
--           These are NOT model weights — they are sequence databases.
--           They REQUIRE a block volume. Standard weight download does not cover them.
-- Endpoint: UNKNOWN — read from container /openapi.json after deployment

-- DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_MSA_SEARCH_SVC;
--
-- CREATE SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_MSA_SEARCH_SVC
--   IN COMPUTE POOL NIM_GPU_A10G_POOL
--   FROM SPECIFICATION $$
-- spec:
--   containers:
--     - name: msa-search
--       image: /SCIENTIFIC_WORKBENCH/CATALOG/NIM_GPU_IMAGES/msa-search:latest
--       env:
--         NIM_HTTP_API_PORT: "8000"
--         NIM_LOG_LEVEL: "INFO"
--       secrets:
--         - snowflakeSecret: SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY
--           secretKeyRef: SECRET_STRING
--           envVarName: NGC_API_KEY
--       volumeMounts:
--         - name: dshm
--           mountPath: /dev/shm
--         - name: refdb
--           mountPath: /databases
--       resources:
--         requests:
--           nvidia.com/gpu: 1
--           memory: 16Gi
--         limits:
--           nvidia.com/gpu: 1
--           memory: 48Gi
--       readinessProbe:
--         port: 8000
--         path: /v1/health/ready
--   endpoints:
--     - name: msa-search
--       port: 8000
--       public: true
--   volumes:
--     - name: dshm
--       source: memory
--       size: 8Gi
--     - name: refdb
--       source: block
--       size: 500Gi
--       blockConfig:
--         initialContents:
--           fromStage: "@SCIENTIFIC_WORKBENCH.CATALOG.MSA_REF_DATABASES"
--   $$
--   EXTERNAL_ACCESS_INTEGRATIONS = (NIM_RUNTIME_EAI)
--   MIN_INSTANCES = 1
--   MAX_INSTANCES = 1
--   COMMENT = 'MSA-Search NIM: sequence alignment. REQUIRES block volume for ref DBs. UNVERIFIED.';

-- =============================================================================
-- EVO2 (BLOCKED — runtime footprint vs node storage cap is unmeasured)
-- =============================================================================
-- Image: nvcr.io/nim/nvidia/evo2:latest (15.25 GiB compressed)
-- GPU: UNKNOWN — 40B parameter model likely needs H100 80 GiB or H200 141 GiB
--      (reservation-only in current account)
-- STORAGE RISK: 15.25 GiB × 3 ≈ 49 GiB unpack + ~40 GB FP8 weights = ~89 GiB
--               Against 93.13 GiB node cap — too close to call from arithmetic.
--               DO NOT deploy until measured.
-- Endpoint: UNKNOWN — read from container /openapi.json after deployment

-- SERVICE SPEC INTENTIONALLY OMITTED — needs measurement before deployment.
-- When ready, use NIM_GPU_L40S_POOL at minimum (48 GiB VRAM likely insufficient
-- for 40B model — may need reservation-only H100/H200).

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- After creating a service, verify with:
--   DESCRIBE SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_BOLTZ2_SVC;
--   SELECT SYSTEM$GET_SERVICE_STATUS('SCIENTIFIC_WORKBENCH.CATALOG.NIM_BOLTZ2_SVC');
--   SELECT SYSTEM$GET_SERVICE_LOGS('SCIENTIFIC_WORKBENCH.CATALOG.NIM_BOLTZ2_SVC', 0, 'boltz2', 50);
--
-- To check endpoint URL (for use in tool procedures):
--   SHOW ENDPOINTS IN SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_BOLTZ2_SVC;
--
-- To suspend/resume (CRITICAL: suspend service BEFORE expecting pool auto-suspend):
--   ALTER SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_BOLTZ2_SVC SUSPEND;
--   ALTER SERVICE SCIENTIFIC_WORKBENCH.CATALOG.NIM_BOLTZ2_SVC RESUME;
