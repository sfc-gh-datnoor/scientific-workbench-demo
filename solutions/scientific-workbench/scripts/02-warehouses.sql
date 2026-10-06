-- =============================================================================
-- 02-warehouses.sql
-- Compute resources: Warehouses + SPCS Compute Pools (CPU + GPU)
-- Run as SYSADMIN
-- =============================================================================

-- =============================================================================
-- SQL WAREHOUSES
-- =============================================================================

-- Catalog operations, metadata, agent queries (lightweight)
CREATE WAREHOUSE IF NOT EXISTS WORKBENCH_XS
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Catalog operations, metadata queries, agent orchestration';

-- Interactive analysis (DE, pathway, survival — Snowpark Python)
CREATE WAREHOUSE IF NOT EXISTS WORKBENCH_S
  WAREHOUSE_SIZE = 'SMALL'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Interactive analysis, DE computation, tool execution';

-- ML and batch workloads (model training, batch scoring)
CREATE WAREHOUSE IF NOT EXISTS WORKBENCH_ML
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 300
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'ML model training, batch scoring, heavy transforms';

-- =============================================================================
-- SPCS COMPUTE POOLS
-- =============================================================================
-- IMPORTANT: GPU capacity is per-instance-type, not per-GPU-family.
-- If one instance type returns CAPACITY_ERROR, try the next size up in the same
-- GPU family before concluding that GPU class is unavailable.
-- Use DESCRIBE COMPUTE POOL (not SHOW) to read error_code — SHOW does not
-- expose it and will sit on STARTING forever.
-- CAPACITY_ERROR can take 12–19 minutes to surface.
-- =============================================================================

-- CPU pool: React app hosting, RDKit containers, Nextflow, general apps
CREATE COMPUTE POOL IF NOT EXISTS WORKBENCH_CPU_POOL
  MIN_NODES = 1
  MAX_NODES = 3
  INSTANCE_FAMILY = CPU_X64_S
  AUTO_SUSPEND_SECS = 600
  AUTO_RESUME = TRUE
  COMMENT = 'SPCS CPU pool: React app hosting, RDKit, general containers';

-- App compute pool: for the React SAR app deployment
CREATE COMPUTE POOL IF NOT EXISTS WORKBENCH_APP_POOL
  MIN_NODES = 1
  MAX_NODES = 2
  INSTANCE_FAMILY = CPU_X64_S
  AUTO_SUSPEND_SECS = 900
  AUTO_RESUME = TRUE
  COMMENT = 'SPCS pool for React Scientific Workbench app hosting';

-- =============================================================================
-- NIM GPU COMPUTE POOLS
-- =============================================================================
-- CRITICAL: All GPU pools use INITIALLY_SUSPENDED = TRUE and MIN_NODES = 1.
-- MIN_NODES = 0 is rejected by Snowflake ("invalid value '0' for property
-- 'MIN_NODES'"); the minimum accepted value is 1. INITIALLY_SUSPENDED = TRUE
-- is what prevents billing on CREATE — a suspended pool runs no nodes
-- regardless of MIN_NODES, so the cost goal is unaffected.
-- Without INITIALLY_SUSPENDED, a pool provisions a node on CREATE and bills
-- immediately. A running service BLOCKS pool auto-suspend — always suspend
-- services before expecting the pool to auto-suspend.
-- =============================================================================

-- GPU pool (A10G, 24 GiB VRAM): GenMol, ProteinMPNN, MolMIM, OpenFold2
-- Instance: GPU_NV_S — 1x A10G, 4 vCPU, 16 GiB RAM
CREATE COMPUTE POOL IF NOT EXISTS NIM_GPU_A10G_POOL
  MIN_NODES = 1
  MAX_NODES = 2
  INSTANCE_FAMILY = GPU_NV_S
  AUTO_SUSPEND_SECS = 300
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'NIM GPU pool (A10G 24 GiB): GenMol, ProteinMPNN, MolMIM, OpenFold2';

-- GPU pool (L40S, 48 GiB VRAM): Boltz-2, DiffDock, RFdiffusion, OpenFold3
-- Instance: GPU_L40S_G1_16 — 1x L40S, 14 vCPU, 116 GiB RAM, 93.13 GiB storage
-- VERIFIED: Boltz-2 runs on this pool (2026-08-26).
-- NOTE: GPU_L40S_G1_8 (same GPU, 6 vCPU / 58 GiB) is a separate capacity pool
-- and may return CAPACITY_ERROR even when G1_16 has capacity.
CREATE COMPUTE POOL IF NOT EXISTS NIM_GPU_L40S_POOL
  MIN_NODES = 1
  MAX_NODES = 2
  INSTANCE_FAMILY = GPU_L40S_G1_16
  AUTO_SUSPEND_SECS = 300
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'NIM GPU pool (L40S 48 GiB): Boltz-2, DiffDock, RFdiffusion, OpenFold3 — verified 2026-08-26';

-- CPU build pool: image mirroring from nvcr.io (no GPU needed)
-- Instance: GEN_X64_G2_32 — 32 vCPU, 128 GiB RAM
-- Mirrors a 10 GiB image in ~6 min including pool resume from SUSPENDED.
CREATE COMPUTE POOL IF NOT EXISTS NIM_BUILD_POOL
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = GEN_X64_G2_32
  AUTO_SUSPEND_SECS = 120
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'CPU pool for NIM image mirroring (nvcr.io → Snowflake registry). No GPU needed.';

-- =============================================================================
-- IMAGE REPOSITORIES
-- =============================================================================

CREATE IMAGE REPOSITORY IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.IMAGES
  COMMENT = 'Container images for SPCS services (app, RDKit, custom tools)';

-- NIM-specific image repository (mirrors of nvcr.io/nim images)
-- NOTE: IMAGE_REGISTRY_URL uses registry-local host with UNDERSCORES in account name.
-- The external registry.snowflakecomputing.com host uses DASHES. Not interchangeable.
CREATE IMAGE REPOSITORY IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_GPU_IMAGES
  COMMENT = 'Mirrored NVIDIA NIM images from nvcr.io for SPCS GPU inference';

-- =============================================================================
-- NODE STORAGE NOTE
-- =============================================================================
-- All SPCS instance families cap node storage at 93.13 GiB — including H100/H200.
-- Sizing up GPUs does NOT buy more storage. This constrains runtime footprint:
--   compressed_image × ~3 (unpack) + weights + working_space < 93.13 GiB
-- Per-NIM storage budget (verified/estimated):
--   GenMol:      ~30 GiB unpack + small weights → safe
--   Boltz-2:     ~30 GiB unpack + ~40 GiB weights = ~73 GiB → VERIFIED fits
--   DiffDock:    ~46 GiB unpack + weights → probably fits
--   RFdiffusion: ~49 GiB unpack + weights → probably fits
--   OpenFold3:   ~31 GiB unpack + ~40 GiB weights → probably fits
--   MolMIM:      ~39 GiB unpack + weights → probably fits
--   Evo2:        ~49 GiB unpack + ~40 GiB FP8 weights = ~89 GiB → MARGINAL, unmeasured
--   MSA-Search:  ~26 GiB unpack + ref DBs up to 1.2 TB → NEEDS BLOCK VOLUME
-- =============================================================================

-- GRANTS moved to 03-rbac.sql (roles must exist before granting)

-- =============================================================================
-- Snowflake App Runtime (SAR) prerequisites
-- =============================================================================
-- app/snowflake.yml declares the app in database SNOWFLAKE_APPS, schema PUBLIC,
-- with code_workspace SNOWFLAKE_APPS.PUBLIC.SNOWFLAKE_APPS and
-- query_warehouse SNOWFLAKE_APPS_QUERY_WH. Nothing else in setup/ creates these,
-- so `snow app deploy` (Phase 6) failed with:
--   Could not use a workspace for code storage ... Database 'SNOWFLAKE_APPS'
--   does not exist or not authorized.. Falling back to a stage.
--   Failed to look up stage 'SNOWFLAKE_APPS.PUBLIC.SCIENTIFIC_WORKBENCH_APP_CODE'
-- Note setup/09-spcs-app-service.sql is the older raw-SPCS path (CREATE SERVICE)
-- and is deliberately not run by deploy.sh, which uses SAR instead.
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_APPS
  COMMENT = 'Code storage and workspace for Snowflake App Runtime (SAR) apps';

CREATE WAREHOUSE IF NOT EXISTS SNOWFLAKE_APPS_QUERY_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Query warehouse for the Scientific Workbench SAR app';

GRANT USAGE ON DATABASE SNOWFLAKE_APPS TO ROLE SYSADMIN;
GRANT USAGE ON WAREHOUSE SNOWFLAKE_APPS_QUERY_WH TO ROLE SYSADMIN;
