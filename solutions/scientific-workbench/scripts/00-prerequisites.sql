-- =============================================================================
-- 00-prerequisites.sql
-- Account-level objects: External Access Integration, Secrets, Network Rules
-- Run as ACCOUNTADMIN
--
-- This script is safe to run first — it creates the database and schema it
-- needs if they do not already exist. Script 01 will re-issue the same
-- CREATE IF NOT EXISTS statements, so ordering no longer matters.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Ensure the database and schema exist before referencing them for secrets
-- and network rules. These are idempotent — 01-databases-and-schemas.sql
-- creates the same objects (with additional schemas) when it runs later.
CREATE DATABASE IF NOT EXISTS SCIENTIFIC_WORKBENCH
  COMMENT = 'Scientific Workbench — core catalog, governance, and workflow objects';
CREATE SCHEMA IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG
  COMMENT = 'Tool registry, assets, search services, secrets, and network rules';

USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA CATALOG;

-- Network rule for NVIDIA BioNeMo API
CREATE NETWORK RULE IF NOT EXISTS NVIDIA_API_NETWORK_RULE
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = (
    'api.nvcf.nvidia.com:443',
    'integrate.api.nvidia.com:443',
    'health.api.nvidia.com:443',
    'files.rcsb.org:443'
  )
  COMMENT = 'Allow outbound access to NVIDIA BioNeMo hosted NIM endpoints + PDB structure download';

-- =============================================================================
-- NVIDIA API KEY SECRET
-- =============================================================================
-- IMPORTANT: Do NOT store the API key in plaintext in this file.
-- The SECRET object stores the key encrypted in Snowflake's secure store.
-- To create: run this statement with your actual key (one-time setup):
--
--   CREATE OR REPLACE SECRET SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET
--     TYPE = GENERIC_STRING
--     SECRET_STRING = '<paste-your-key-from-build.nvidia.com>'
--     COMMENT = 'NVIDIA BioNeMo API key — encrypted in Snowflake secure store';
--
-- After creation, the key is never visible in plaintext again.
-- Procedures access it via: _snowflake.get_generic_secret_string('nvidia_key')
-- The React app accesses it via: getSecret("NVIDIA_KEY", SecretType.GENERIC_STRING)
-- =============================================================================

-- Create the secret (user must replace the placeholder):
CREATE SECRET IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET
  TYPE = GENERIC_STRING
  SECRET_STRING = '{{NVIDIA_API_KEY}}'
  COMMENT = 'NVIDIA BioNeMo API key from build.nvidia.com — stored encrypted';

-- External Access Integration for NVIDIA API
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION NVIDIA_API_EAI
  ALLOWED_NETWORK_RULES = (NVIDIA_API_NETWORK_RULE)
  ALLOWED_AUTHENTICATION_SECRETS = (SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
  ENABLED = TRUE
  COMMENT = 'External access to NVIDIA BioNeMo NIM hosted endpoints';

-- Grant usage to SYSADMIN (role already exists)
GRANT USAGE ON INTEGRATION NVIDIA_API_EAI TO ROLE SYSADMIN;

-- =============================================================================
-- SPCS NIM DEPLOYMENT: NGC Registry + Runtime Weight Download
-- =============================================================================
-- These are SEPARATE from the hosted API above. They allow:
-- 1. Pulling NIM container images from nvcr.io into Snowflake image repository
-- 2. NIM containers to download model weights at runtime from NGC/HuggingFace
--
-- The NGC_API_KEY is different from NVIDIA_API_SECRET:
-- - NVIDIA_API_SECRET: key from build.nvidia.com for hosted API calls
-- - NGC_API_KEY: key from ngc.nvidia.com for container registry + weight download
-- =============================================================================

-- NGC API Key for container registry auth and NIM runtime weight download
-- Get from: https://org.ngc.nvidia.com/setup/personal-keys
-- Generate a Personal Key with "NGC Catalog" selected under "Services Included".
-- Without that scope the key authenticates but nvcr.io refuses the image pull.
-- IMPORTANT: SECRET_STRING cannot be read back via SQL after creation.
CREATE SECRET IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY
  TYPE = GENERIC_STRING
  SECRET_STRING = '{{NGC_API_KEY}}'
  COMMENT = 'NGC API key for NIM container pull and runtime weight download — from ngc.nvidia.com';

-- =============================================================================
-- Network Rule: NGC Registry Pull (image mirroring)
-- =============================================================================
-- Used by the build pool job to pull images from nvcr.io into Snowflake registry.
-- Also used by the NIM_IMAGE_SIZE UDF to probe OCI manifests.

CREATE NETWORK RULE IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NGC_REGISTRY_PULL
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = (
    'nvcr.io:443',
    -- Wildcard rather than the specific host: 'cdn.nvcf.nvidia.com' does not
    -- resolve in public DNS, and Snowflake rejects unresolvable hosts with
    -- "invalid value for property 'VALUE_LIST' ... might be an unresolvable
    -- host name. Verify all hosts are resolvable, or use a wildcard pattern."
    -- The wildcard covers the CDN host and matches the pattern already used
    -- by the NIM_SPCS_EGRESS rule below.
    '*.nvcf.nvidia.com:443',
    'auth.docker.io:443',
    'production.cloudflare.docker.com:443'
  )
  COMMENT = 'Egress for pulling NIM images from NGC container registry';

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION NGC_REGISTRY_PULL_EAI
  ALLOWED_NETWORK_RULES = (SCIENTIFIC_WORKBENCH.CATALOG.NGC_REGISTRY_PULL)
  ALLOWED_AUTHENTICATION_SECRETS = (SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY)
  ENABLED = TRUE
  COMMENT = 'EAI for NIM image mirroring and OCI manifest probes';

GRANT USAGE ON INTEGRATION NGC_REGISTRY_PULL_EAI TO ROLE SYSADMIN;

-- =============================================================================
-- Network Rule: NIM Runtime Egress (weight download at container startup)
-- =============================================================================
-- NIM containers download model weights on every cold start from NGC and
-- related CDNs. This is faster than reading from a block volume (~400 MB/s
-- download vs 125 MiB/s volume read). No block volume needed for weights.
--
-- GenMol additionally requires huggingface.co for its tokenizer at model-init.
-- This is GenMol-specific and not covered by a weight cache.

CREATE NETWORK RULE IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_RUNTIME_EGRESS
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = (
    'nvcr.io:443',
    '*.nvcf.nvidia.com:443',
    '*.ngc.nvidia.com:443',
    '*.download.nvidia.com:443',
    'huggingface.co:443',
    '*.huggingface.co:443'
  )
  COMMENT = 'Egress for NIM runtime weight download from NGC + HuggingFace (GenMol tokenizer)';

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION NIM_RUNTIME_EAI
  ALLOWED_NETWORK_RULES = (SCIENTIFIC_WORKBENCH.CATALOG.NIM_RUNTIME_EGRESS)
  ALLOWED_AUTHENTICATION_SECRETS = (SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY)
  ENABLED = TRUE
  COMMENT = 'EAI for NIM containers to download weights at runtime';

GRANT USAGE ON INTEGRATION NIM_RUNTIME_EAI TO ROLE SYSADMIN;

-- =============================================================================
-- Network Rule + EAI: RCSB Protein Data Bank
-- Consumed by CATALOG.FETCH_PDB (tools/native/fetch_pdb.sql).
-- Defined here, not in the tool file: the tool files are deployed as SYSADMIN,
-- which cannot hold CREATE EXTERNAL ACCESS INTEGRATION on the account.
-- =============================================================================
CREATE NETWORK RULE IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.PDB_API_RULE
  TYPE = HOST_PORT
  MODE = EGRESS
  VALUE_LIST = ('data.rcsb.org:443', 'files.rcsb.org:443')
  COMMENT = 'Access to RCSB PDB REST API and structure file downloads';

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION PDB_API_EAI
  ALLOWED_NETWORK_RULES = (SCIENTIFIC_WORKBENCH.CATALOG.PDB_API_RULE)
  ENABLED = TRUE
  COMMENT = 'External access to RCSB Protein Data Bank REST API';

GRANT USAGE ON INTEGRATION PDB_API_EAI TO ROLE SYSADMIN;
