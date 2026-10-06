-- =============================================================================
-- 09-spcs-app-service.sql
-- Create the SPCS container service for the React Scientific Workbench app
-- Run as SYSADMIN
-- =============================================================================
-- Prerequisites:
--   - Compute pool WORKBENCH_APP_POOL exists (02-warehouses.sql)
--   - Image repository SCIENTIFIC_WORKBENCH.CATALOG.IMAGES exists (02-warehouses.sql)
--   - Docker image pushed: <repo_url>/scientific-workbench-app:latest
--   - Secret NVIDIA_API_SECRET exists (00-prerequisites.sql)
--   - EAI NVIDIA_API_EAI exists (00-prerequisites.sql)
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA CATALOG;

-- Stage for any supplementary app config (optional, service-spec lives in-line)
CREATE STAGE IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.APP_STAGE
  COMMENT = 'Stage for app artifacts and service specs';

-- Drop existing service if re-deploying
DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.WORKBENCH_APP_SERVICE;

-- Create the SPCS container service
CREATE SERVICE SCIENTIFIC_WORKBENCH.CATALOG.WORKBENCH_APP_SERVICE
  IN COMPUTE POOL WORKBENCH_APP_POOL
  MIN_INSTANCES = 1
  MAX_INSTANCES = 2
  EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
  QUERY_WAREHOUSE = WORKBENCH_XS
  COMMENT = 'Scientific Workbench React app — Docker container on SPCS'
  FROM SPECIFICATION $$
spec:
  containers:
    - name: workbench-app
      image: /SCIENTIFIC_WORKBENCH/CATALOG/IMAGES/scientific-workbench-app:latest
      env:
        PORT: "8000"
        HOSTNAME: "0.0.0.0"
        WORKBENCH_DB: "SCIENTIFIC_WORKBENCH"
        REFERENCE_DB: "WORKBENCH_REFERENCE"
        PROJECTS_DB: "WORKBENCH_PROJECTS"
      resources:
        requests:
          cpu: "0.5"
          memory: "1Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
      secrets:
        - snowflakeSecret: SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET
          secretKeyRef: secret_string
          envVarName: NVIDIA_API_KEY
  endpoints:
    - name: app
      port: 8000
      public: true
$$;

-- Grant access to workbench roles
GRANT USAGE ON SERVICE SCIENTIFIC_WORKBENCH.CATALOG.WORKBENCH_APP_SERVICE TO ROLE WORKBENCH_ADMIN;
GRANT USAGE ON SERVICE SCIENTIFIC_WORKBENCH.CATALOG.WORKBENCH_APP_SERVICE TO ROLE WORKBENCH_SCIENTIST;

-- Show service status (for verification)
DESCRIBE SERVICE SCIENTIFIC_WORKBENCH.CATALOG.WORKBENCH_APP_SERVICE;
