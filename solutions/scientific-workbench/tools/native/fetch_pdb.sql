-- =============================================================================
-- tools/native/fetch_pdb.sql
-- Fetch protein structure and metadata from RCSB PDB
-- Requires: PDB_API_EAI external access integration, created by
--           setup/00-prerequisites.sql as ACCOUNTADMIN. It cannot be created
--           here: this file is deployed as SYSADMIN, which cannot hold
--           CREATE EXTERNAL ACCESS INTEGRATION on the account.
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA CATALOG;

-- PDB Fetch procedure
CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.FETCH_PDB(
  P_PDB_ID VARCHAR,
  P_OUTPUT_TABLE VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (PDB_API_EAI)
COMMENT = 'Fetch protein structure and metadata from RCSB PDB by PDB ID'
EXECUTE AS OWNER
AS
$$
import json, requests

PDB_API = "https://data.rcsb.org/rest/v1/core/entry"
PDB_FILES = "https://files.rcsb.org/download"

def run(session, p_pdb_id, p_output_table):
    pdb_id = p_pdb_id.strip().upper()
    if len(pdb_id) != 4:
        return {"error": "Invalid PDB ID. Must be 4 characters.", "success": False}
    
    result = {"pdb_id": pdb_id, "success": False}
    
    # Fetch entry metadata
    try:
        resp = requests.get(PDB_API + "/" + pdb_id, timeout=30)
        resp.raise_for_status()
        entry = resp.json()
        
        struct = entry.get("struct", {})
        exptl_list = entry.get("exptl", [{}])
        exptl = exptl_list[0] if exptl_list else {}
        refine_list = entry.get("refine", [{}])
        refine = refine_list[0] if refine_list else {}
        
        result["title"] = struct.get("title", "")
        result["method"] = exptl.get("method", "")
        result["resolution"] = refine.get("ls_d_res_high")
        result["deposition_date"] = entry.get("rcsb_accession_info", {}).get("deposit_date")
        result["release_date"] = entry.get("rcsb_accession_info", {}).get("initial_release_date")
        result["success"] = True
    except Exception as e:
        result["error"] = "Failed to fetch PDB entry: " + str(e)
        return result
    
    # Fetch polymer entity (sequence + organism)
    try:
        poly_resp = requests.get("https://data.rcsb.org/rest/v1/core/polymer_entity/" + pdb_id + "/1", timeout=15)
        if poly_resp.ok:
            poly = poly_resp.json()
            seq = poly.get("entity_poly", {}).get("pdbx_seq_one_letter_code_can", "")
            result["sequence"] = seq
            result["sequence_length"] = len(seq)
            src = poly.get("rcsb_entity_source_organism", [])
            if src:
                result["organism"] = src[0].get("ncbi_scientific_name", "")
    except:
        pass
    
    # Fetch PDB coordinates
    try:
        pdb_resp = requests.get(PDB_FILES + "/" + pdb_id + ".pdb", timeout=30)
        if pdb_resp.ok:
            pdb_text = pdb_resp.text
            atom_lines = [l for l in pdb_text.split("\n") if l.startswith("ATOM")]
            chains = set()
            for l in atom_lines:
                if len(l) > 21:
                    chains.add(l[21])
            result["atom_count"] = len(atom_lines)
            result["chain_count"] = len(chains)
            result["chains"] = sorted(list(chains))
            result["pdb_coordinates"] = "fetched (" + str(len(atom_lines)) + " atoms)"
    except Exception as e:
        result["pdb_fetch_note"] = str(e)
    
    return result
$$;

-- Grant to workbench roles
GRANT USAGE ON PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.FETCH_PDB(VARCHAR, VARCHAR)
  TO ROLE WORKBENCH_ADMIN;
GRANT USAGE ON PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.FETCH_PDB(VARCHAR, VARCHAR)
  TO ROLE WORKBENCH_SCIENTIST;

-- Register in tool catalog.
-- Uses CATALOG.REGISTER_TOOL, the same idempotent entry point every other tool
-- uses. The previous raw INSERT here targeted columns that do not exist on
-- CATALOG.TOOLS (TYPE, COMPUTE_TYPE, ESTIMATED_RUNTIME, INPUT_SCHEMA,
-- OUTPUT_SCHEMA, PROCEDURE_NAME, _LOADED_TIMESTAMP) and failed with
-- "invalid identifier 'TYPE'", so the PDB tool was never registered and the
-- agent could neither discover nor dispatch to it.
CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'fetch_pdb',
    'PDB Fetch',
    'Fetch protein structure and metadata from RCSB Protein Data Bank by PDB ID. '
    || 'Returns title, method, resolution, organism, sequence, chain info, and atom count.',
    'structural,protein',
    'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.FETCH_PDB',
    '{"p_pdb_id":"STRING","p_output_table":"STRING"}',
    'VARIANT',
    'CALL CATALOG.FETCH_PDB(6OIM, output_table)'
);
