-- =============================================================================
-- 14-custom-tool-onboarding.sql
-- BYOT (Bring Your Own Tool) — schema extensions, approval flow, shared EAI,
-- wrapper generator, and onboarding orchestrator.
-- Run as ACCOUNTADMIN (for EAI/network rules), then SYSADMIN (for procedures).
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA CATALOG;

-- =============================================================================
-- 1. SCHEMA EXTENSIONS — new columns on CATALOG.TOOLS
-- =============================================================================

-- Add BYOT columns (idempotent — uses EXECUTE IMMEDIATE to avoid ambiguous column errors)
EXECUTE IMMEDIATE $$
DECLARE
  col_count INT;
BEGIN
  SELECT COUNT(*) INTO col_count FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'CATALOG' AND TABLE_NAME = 'TOOLS' AND COLUMN_NAME = 'SOURCE_TYPE';
  IF (col_count = 0) THEN
    EXECUTE IMMEDIATE 'ALTER TABLE CATALOG.TOOLS ADD COLUMN source_type VARCHAR DEFAULT ''built-in''';
  END IF;
  SELECT COUNT(*) INTO col_count FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'CATALOG' AND TABLE_NAME = 'TOOLS' AND COLUMN_NAME = 'SOURCE_CONFIG';
  IF (col_count = 0) THEN
    EXECUTE IMMEDIATE 'ALTER TABLE CATALOG.TOOLS ADD COLUMN source_config VARIANT';
  END IF;
  SELECT COUNT(*) INTO col_count FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'CATALOG' AND TABLE_NAME = 'TOOLS' AND COLUMN_NAME = 'COMPUTE_ENV';
  IF (col_count = 0) THEN
    EXECUTE IMMEDIATE 'ALTER TABLE CATALOG.TOOLS ADD COLUMN compute_env VARCHAR DEFAULT ''warehouse''';
  END IF;
  SELECT COUNT(*) INTO col_count FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'CATALOG' AND TABLE_NAME = 'TOOLS' AND COLUMN_NAME = 'VISIBILITY';
  IF (col_count = 0) THEN
    EXECUTE IMMEDIATE 'ALTER TABLE CATALOG.TOOLS ADD COLUMN visibility VARCHAR DEFAULT ''org''';
  END IF;
  SELECT COUNT(*) INTO col_count FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'CATALOG' AND TABLE_NAME = 'TOOLS' AND COLUMN_NAME = 'SUBMITTED_BY';
  IF (col_count = 0) THEN
    EXECUTE IMMEDIATE 'ALTER TABLE CATALOG.TOOLS ADD COLUMN submitted_by VARCHAR';
  END IF;
  SELECT COUNT(*) INTO col_count FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'CATALOG' AND TABLE_NAME = 'TOOLS' AND COLUMN_NAME = 'APPROVED_BY';
  IF (col_count = 0) THEN
    EXECUTE IMMEDIATE 'ALTER TABLE CATALOG.TOOLS ADD COLUMN approved_by VARCHAR';
  END IF;
  SELECT COUNT(*) INTO col_count FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'CATALOG' AND TABLE_NAME = 'TOOLS' AND COLUMN_NAME = 'APPROVED_AT';
  IF (col_count = 0) THEN
    EXECUTE IMMEDIATE 'ALTER TABLE CATALOG.TOOLS ADD COLUMN approved_at TIMESTAMP_NTZ';
  END IF;
END
$$;

-- =============================================================================
-- 2. CUSTOM TOOL SUBMISSIONS TABLE — approval queue
-- =============================================================================

CREATE TABLE IF NOT EXISTS CATALOG.CUSTOM_TOOL_SUBMISSIONS (
    submission_id    VARCHAR NOT NULL PRIMARY KEY,
    tool_spec        VARIANT NOT NULL,
    submitted_by     VARCHAR DEFAULT CURRENT_USER(),
    submitted_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    status           VARCHAR DEFAULT 'pending',   -- 'pending' | 'approved' | 'rejected'
    reviewer         VARCHAR,
    reviewed_at      TIMESTAMP_NTZ,
    review_notes     VARCHAR,
    tool_id          VARCHAR                       -- set after approval + registration
)
COMMENT = 'Approval queue for user-submitted custom tools';

-- =============================================================================
-- 3. SHARED EAI POOL FOR CUSTOM REST TOOLS
-- =============================================================================
-- Run as ACCOUNTADMIN (deploy.sh runs this file as SYSADMIN, which cannot
-- create integrations); switch back to SYSADMIN after the grants below.
USE ROLE ACCOUNTADMIN;

CREATE NETWORK RULE IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_API_NETWORK_RULE
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('0.0.0.0:443')
  COMMENT = 'Egress for user-added REST API tools. Admin adds allowed domains via ADD_CUSTOM_API_DOMAIN.';

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION CUSTOM_API_EAI
  ALLOWED_NETWORK_RULES = (SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_API_NETWORK_RULE)
  ENABLED = TRUE
  COMMENT = 'Shared EAI for custom REST API tools in the Scientific Workbench';

GRANT USAGE ON INTEGRATION CUSTOM_API_EAI TO ROLE SYSADMIN;
GRANT USAGE ON INTEGRATION CUSTOM_API_EAI TO ROLE WORKBENCH_ADMIN;

USE ROLE SYSADMIN;

-- =============================================================================
-- 3a. ADD_CUSTOM_API_DOMAIN — admin procedure to add allowed domains
-- =============================================================================
-- NOTE: ALTER NETWORK RULE requires ACCOUNTADMIN. This procedure must be
-- created by and execute as ACCOUNTADMIN, or be granted via EXECUTE AS OWNER
-- by a role with the ALTER privilege on the network rule.
-- For the MVP we document this as an admin-run SQL step.

CREATE OR REPLACE PROCEDURE CATALOG.ADD_CUSTOM_API_DOMAIN(P_DOMAIN VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Add a domain to the CUSTOM_API_NETWORK_RULE allowed list. Run as ACCOUNTADMIN.'
EXECUTE AS CALLER
AS
$$
BEGIN
    -- Validate domain format: must be host:port or host (default 443)
    IF (:P_DOMAIN IS NULL OR TRIM(:P_DOMAIN) = '') THEN
        RETURN 'ERROR: Domain cannot be empty';
    END IF;

    LET v_domain VARCHAR := TRIM(:P_DOMAIN);
    IF (NOT CONTAINS(:v_domain, ':')) THEN
        v_domain := :v_domain || ':443';
    END IF;

    -- ALTER NETWORK RULE to add the domain
    -- Note: Snowflake does not support ADD to VALUE_LIST, so we must read + rebuild.
    -- For the MVP, we document manual ALTER. This procedure serves as the interface.
    EXECUTE IMMEDIATE
        'ALTER NETWORK RULE SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_API_NETWORK_RULE '
        || 'SET VALUE_LIST = (''' || :v_domain || ''')';

    RETURN 'Added domain: ' || :v_domain || '. NOTE: This replaces the VALUE_LIST. Use ALTER NETWORK RULE directly to set multiple domains.';
END;
$$;

-- =============================================================================
-- 4. PYTHON CODE GUARDRAILS — allowlisted packages and banned patterns
-- =============================================================================

CREATE TABLE IF NOT EXISTS CATALOG.BYOT_PYTHON_ALLOWLIST (
    package_name     VARCHAR NOT NULL PRIMARY KEY,
    max_version      VARCHAR,
    description      VARCHAR,
    added_at         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Allowlisted Python packages for custom tool code uploads';

-- Seed with safe packages available in Snowpark Python 3.10
MERGE INTO CATALOG.BYOT_PYTHON_ALLOWLIST tgt
USING (
    SELECT column1 AS package_name, column2 AS description FROM VALUES
        ('snowflake-snowpark-python', 'Snowpark session and DataFrame API'),
        ('pandas', 'Data manipulation and analysis'),
        ('numpy', 'Numerical computing'),
        ('scipy', 'Scientific computing'),
        ('scikit-learn', 'Machine learning algorithms'),
        ('requests', 'HTTP client (requires EAI)'),
        ('rdkit', 'Cheminformatics toolkit'),
        ('biopython', 'Bioinformatics utilities')
) src ON tgt.package_name = src.package_name
WHEN NOT MATCHED THEN INSERT (package_name, description) VALUES (src.package_name, src.description);

-- Banned code patterns stored as a table for easy admin extension
CREATE TABLE IF NOT EXISTS CATALOG.BYOT_BANNED_PATTERNS (
    pattern          VARCHAR NOT NULL PRIMARY KEY,
    reason           VARCHAR NOT NULL,
    added_at         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Banned code patterns for Python tool uploads — regex patterns';

MERGE INTO CATALOG.BYOT_BANNED_PATTERNS tgt
USING (
    SELECT column1 AS pattern, column2 AS reason FROM VALUES
        ('import\s+os\b', 'os module access not allowed'),
        ('from\s+os\b', 'os module access not allowed'),
        ('import\s+subprocess\b', 'subprocess execution not allowed'),
        ('from\s+subprocess\b', 'subprocess execution not allowed'),
        ('import\s+socket\b', 'Raw socket access not allowed'),
        ('from\s+socket\b', 'Raw socket access not allowed'),
        ('import\s+ctypes\b', 'ctypes access not allowed'),
        ('from\s+ctypes\b', 'ctypes access not allowed'),
        ('import\s+_snowflake\b', 'Direct secret access not allowed from user code'),
        ('from\s+_snowflake\b', 'Direct secret access not allowed from user code'),
        ('\bexec\s*\(', 'Dynamic code execution not allowed'),
        ('\beval\s*\(', 'Dynamic code evaluation not allowed'),
        ('__import__\s*\(', 'Dynamic imports not allowed'),
        ('\bcompile\s*\(', 'Code compilation not allowed'),
        ('\bglobals\s*\(', 'globals() access not allowed'),
        ('\blocals\s*\(', 'locals() access not allowed')
) src ON tgt.pattern = src.pattern
WHEN NOT MATCHED THEN INSERT (pattern, reason) VALUES (src.pattern, src.reason);

-- =============================================================================
-- 4b. PYTHON PACKAGE CAPABILITY CATALOG
-- =============================================================================
-- Pre-built tool templates for known scientific Python packages. When a user
-- says "add RDKit", the system looks up this catalog to find ready-made
-- capabilities rather than asking the user to write code from scratch.

CREATE TABLE IF NOT EXISTS CATALOG.BYOT_PACKAGE_CATALOG (
    package_name     VARCHAR NOT NULL,
    capability_name  VARCHAR NOT NULL,
    display_name     VARCHAR NOT NULL,
    description      VARCHAR NOT NULL,
    domains          VARCHAR NOT NULL,           -- comma-separated
    code_template    VARCHAR NOT NULL,           -- Python function body template
    parameters       VARIANT NOT NULL,           -- JSON parameter schema
    return_type      VARCHAR DEFAULT 'VARCHAR',
    packages         ARRAY,                      -- additional packages needed
    added_at         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (package_name, capability_name)
)
COMMENT = 'Pre-built tool templates for known Python packages — capabilities users can install in one click';

-- Seed RDKit capabilities
MERGE INTO CATALOG.BYOT_PACKAGE_CATALOG tgt
USING (
    SELECT column1 AS package_name, column2 AS capability_name, column3 AS display_name,
           column4 AS description, column5 AS domains, column6 AS code_template,
           PARSE_JSON(column7) AS parameters, column8 AS return_type,
           ARRAY_CONSTRUCT('rdkit') AS packages
    FROM VALUES
    -- 1. Molecular Descriptors
    ('rdkit', 'molecular_descriptors',
     'RDKit Molecular Descriptors',
     'Calculate molecular descriptors (MW, LogP, HBD, HBA, TPSA, rotatable bonds, ring count, Lipinski violations) for a SMILES string.',
     'chemistry,drug-discovery,descriptors',
     'from rdkit import Chem
from rdkit.Chem import Descriptors, Lipinski
import pandas as pd

mol = Chem.MolFromSmiles(smiles)
if mol is None:
    return pd.DataFrame([{"smiles": smiles, "error": "Invalid SMILES"}])

mw = Descriptors.MolWt(mol)
logp = Descriptors.MolLogP(mol)
hbd = Descriptors.NumHDonors(mol)
hba = Descriptors.NumHAcceptors(mol)
tpsa = Descriptors.TPSA(mol)
rotatable = Descriptors.NumRotatableBonds(mol)
rings = Descriptors.RingCount(mol)
lipinski_violations = sum([mw > 500, logp > 5, hbd > 5, hba > 10])

return pd.DataFrame([{
    "smiles": smiles, "molecular_weight": round(mw, 2),
    "logp": round(logp, 2), "hbd": hbd, "hba": hba,
    "tpsa": round(tpsa, 2), "rotatable_bonds": rotatable,
    "ring_count": rings, "lipinski_violations": lipinski_violations
}])',
     '{"smiles": {"type": "STRING", "description": "Input SMILES string", "required": true}}',
     'VARCHAR'),

    -- 2. SMILES Validation
    ('rdkit', 'validate_smiles',
     'RDKit SMILES Validator',
     'Validate SMILES strings and return canonical form, molecular formula, and atom count.',
     'chemistry,validation',
     'from rdkit import Chem
from rdkit.Chem import Descriptors
import pandas as pd

mol = Chem.MolFromSmiles(smiles)
if mol is None:
    return pd.DataFrame([{"input_smiles": smiles, "valid": False, "error": "Cannot parse SMILES"}])

canonical = Chem.MolToSmiles(mol)
formula = Descriptors.MolecularFormula(mol)
atom_count = mol.GetNumAtoms()

return pd.DataFrame([{
    "input_smiles": smiles, "valid": True, "canonical_smiles": canonical,
    "molecular_formula": formula, "heavy_atom_count": atom_count
}])',
     '{"smiles": {"type": "STRING", "description": "SMILES string to validate", "required": true}}',
     'VARCHAR'),

    -- 3. Molecular Fingerprints & Similarity
    ('rdkit', 'molecular_similarity',
     'RDKit Molecular Similarity',
     'Calculate Tanimoto similarity between two molecules using Morgan fingerprints (ECFP4).',
     'chemistry,drug-discovery,similarity',
     'from rdkit import Chem
from rdkit.Chem import AllChem
from rdkit import DataStructs
import pandas as pd

mol1 = Chem.MolFromSmiles(smiles_1)
mol2 = Chem.MolFromSmiles(smiles_2)
if mol1 is None or mol2 is None:
    return pd.DataFrame([{"error": "Invalid SMILES", "smiles_1": smiles_1, "smiles_2": smiles_2}])

fp1 = AllChem.GetMorganFingerprintAsBitVect(mol1, 2, nBits=2048)
fp2 = AllChem.GetMorganFingerprintAsBitVect(mol2, 2, nBits=2048)
tanimoto = DataStructs.TanimotoSimilarity(fp1, fp2)

return pd.DataFrame([{
    "smiles_1": smiles_1, "smiles_2": smiles_2,
    "tanimoto_similarity": round(tanimoto, 4),
    "fingerprint_type": "Morgan_r2_2048bits"
}])',
     '{"smiles_1": {"type": "STRING", "description": "First molecule SMILES", "required": true}, "smiles_2": {"type": "STRING", "description": "Second molecule SMILES", "required": true}}',
     'VARCHAR'),

    -- 4. Substructure Search
    ('rdkit', 'substructure_search',
     'RDKit Substructure Search',
     'Check if a molecule contains a given substructure pattern (SMARTS or SMILES).',
     'chemistry,search',
     'from rdkit import Chem
import pandas as pd

mol = Chem.MolFromSmiles(molecule_smiles)
pattern = Chem.MolFromSmarts(substructure_pattern)
if pattern is None:
    pattern = Chem.MolFromSmiles(substructure_pattern)
if mol is None or pattern is None:
    return pd.DataFrame([{"error": "Invalid SMILES/SMARTS input"}])

has_match = mol.HasSubstructMatch(pattern)
matches = mol.GetSubstructMatches(pattern)

return pd.DataFrame([{
    "molecule": molecule_smiles, "pattern": substructure_pattern,
    "has_match": has_match, "match_count": len(matches),
    "matched_atoms": str(matches) if matches else "none"
}])',
     '{"molecule_smiles": {"type": "STRING", "description": "Target molecule SMILES", "required": true}, "substructure_pattern": {"type": "STRING", "description": "Substructure SMARTS or SMILES pattern", "required": true}}',
     'VARCHAR')
) src ON tgt.package_name = src.package_name AND tgt.capability_name = src.capability_name
WHEN NOT MATCHED THEN INSERT (package_name, capability_name, display_name, description, domains, code_template, parameters, return_type, packages)
VALUES (src.package_name, src.capability_name, src.display_name, src.description, src.domains, src.code_template, src.parameters, src.return_type, src.packages);

-- Seed BioPython capabilities
MERGE INTO CATALOG.BYOT_PACKAGE_CATALOG tgt
USING (
    SELECT column1 AS package_name, column2 AS capability_name, column3 AS display_name,
           column4 AS description, column5 AS domains, column6 AS code_template,
           PARSE_JSON(column7) AS parameters, column8 AS return_type,
           ARRAY_CONSTRUCT('biopython') AS packages
    FROM VALUES
    ('biopython', 'sequence_stats',
     'BioPython Sequence Statistics',
     'Calculate GC content, length, molecular weight, and base composition for a DNA/RNA sequence.',
     'genomics,bioinformatics,sequence-analysis',
     'from Bio.Seq import Seq
from Bio.SeqUtils import gc_fraction, molecular_weight
import pandas as pd

seq = Seq(sequence.upper())
gc = gc_fraction(seq)
mw = molecular_weight(seq, seq_type="DNA" if set(str(seq)).issubset({"A","T","G","C","N"}) else "RNA")
composition = {base: str(seq).count(base) for base in "ATGCUN"}

return pd.DataFrame([{
    "sequence_length": len(seq), "gc_content": round(gc, 4),
    "molecular_weight": round(mw, 2), **composition
}])',
     '{"sequence": {"type": "STRING", "description": "DNA or RNA sequence", "required": true}}',
     'VARCHAR'),

    ('biopython', 'translate_sequence',
     'BioPython Sequence Translation',
     'Translate a DNA coding sequence to protein. Reports the protein sequence and any stop codons.',
     'genomics,bioinformatics,translation',
     'from Bio.Seq import Seq
import pandas as pd

seq = Seq(sequence.upper())
protein = str(seq.translate())
stop_count = protein.count("*")

return pd.DataFrame([{
    "dna_sequence": str(seq)[:100] + ("..." if len(seq) > 100 else ""),
    "protein_sequence": protein,
    "protein_length": len(protein.rstrip("*")),
    "stop_codons": stop_count,
    "is_complete_cds": protein.endswith("*") and stop_count == 1
}])',
     '{"sequence": {"type": "STRING", "description": "DNA coding sequence (multiple of 3)", "required": true}}',
     'VARCHAR')
) src ON tgt.package_name = src.package_name AND tgt.capability_name = src.capability_name
WHEN NOT MATCHED THEN INSERT (package_name, capability_name, display_name, description, domains, code_template, parameters, return_type, packages)
VALUES (src.package_name, src.capability_name, src.display_name, src.description, src.domains, src.code_template, src.parameters, src.return_type, src.packages);

-- Seed scikit-learn capabilities
MERGE INTO CATALOG.BYOT_PACKAGE_CATALOG tgt
USING (
    SELECT column1 AS package_name, column2 AS capability_name, column3 AS display_name,
           column4 AS description, column5 AS domains, column6 AS code_template,
           PARSE_JSON(column7) AS parameters, column8 AS return_type,
           ARRAY_CONSTRUCT('scikit-learn', 'pandas') AS packages
    FROM VALUES
    ('scikit-learn', 'pca_analysis',
     'PCA Dimensionality Reduction',
     'Run PCA on a result table. Returns principal components, explained variance, and transformed data.',
     'machine-learning,analysis,dimensionality-reduction',
     'from sklearn.decomposition import PCA
import pandas as pd
from snowflake.snowpark.context import get_active_session

session = get_active_session()
df = session.table(input_table).to_pandas()
numeric_cols = df.select_dtypes(include=["number"]).columns.tolist()
if not numeric_cols:
    return pd.DataFrame([{"error": "No numeric columns found in " + input_table}])

X = df[numeric_cols].fillna(0)
n = min(int(n_components), len(numeric_cols), len(X))
pca = PCA(n_components=n)
transformed = pca.fit_transform(X)

result = pd.DataFrame(transformed, columns=[f"PC{i+1}" for i in range(n)])
result["explained_variance_ratio"] = [round(v, 4) for v in pca.explained_variance_ratio_] + [None] * (len(result) - n)
return result',
     '{"input_table": {"type": "STRING", "description": "Source table with numeric columns", "required": true}, "n_components": {"type": "INT", "description": "Number of principal components", "required": true}}',
     'VARCHAR')
) src ON tgt.package_name = src.package_name AND tgt.capability_name = src.capability_name
WHEN NOT MATCHED THEN INSERT (package_name, capability_name, display_name, description, domains, code_template, parameters, return_type, packages)
VALUES (src.package_name, src.capability_name, src.display_name, src.description, src.domains, src.code_template, src.parameters, src.return_type, src.packages);

GRANT SELECT ON TABLE CATALOG.BYOT_PACKAGE_CATALOG TO ROLE WORKBENCH_SCIENTIST;
GRANT SELECT, INSERT, UPDATE ON TABLE CATALOG.BYOT_PACKAGE_CATALOG TO ROLE WORKBENCH_ADMIN;

-- =============================================================================
-- 4c. AI-ASSISTED TOOL GENERATION via CORTEX.COMPLETE
-- =============================================================================
-- For packages or capabilities NOT in the curated catalog, use an LLM to
-- generate the wrapper code. The generated code is still validated against
-- banned patterns and goes through admin approval.

CREATE OR REPLACE PROCEDURE CATALOG.GENERATE_TOOL_CODE_AI(
    P_PACKAGE_NAME VARCHAR,
    P_CAPABILITY    VARCHAR,
    P_DESCRIPTION   VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'Use Cortex LLM to generate Python tool code for a package capability'
EXECUTE AS CALLER
AS
$$
DECLARE
    v_prompt VARCHAR;
    v_result VARCHAR;
BEGIN
    v_prompt := 'You are a scientific software engineer. Generate a Python function body that implements this tool capability.

PACKAGE: ' || :P_PACKAGE_NAME || '
CAPABILITY: ' || :P_CAPABILITY || '
DESCRIPTION: ' || :P_DESCRIPTION || '

REQUIREMENTS:
- The function receives named parameters and returns a pandas DataFrame
- Import only from: ' || :P_PACKAGE_NAME || ', pandas, numpy (if needed)
- Do NOT import os, subprocess, socket, ctypes, _snowflake
- Do NOT use exec(), eval(), __import__(), compile()
- Keep the code under 100 lines
- Include basic input validation
- Return a DataFrame with clear column names

Return ONLY the Python function body (no def line, no docstring wrapper). The function parameters will be injected by the system.
Also return a JSON object with:
- "parameters": parameter schema as {"param_name": {"type": "STRING|INT|FLOAT", "description": "...", "required": true/false}}
- "display_name": a short human-readable name
- "domains": comma-separated domain tags

Format your response as JSON:
{"code": "...", "parameters": {...}, "display_name": "...", "domains": "..."}';

    SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', :v_prompt) INTO :v_result;

    -- Try to extract JSON from the response
    RETURN PARSE_JSON(:v_result);
END;
$$;

GRANT USAGE ON PROCEDURE CATALOG.GENERATE_TOOL_CODE_AI(VARCHAR, VARCHAR, VARCHAR) TO ROLE WORKBENCH_ADMIN;
GRANT USAGE ON PROCEDURE CATALOG.GENERATE_TOOL_CODE_AI(VARCHAR, VARCHAR, VARCHAR) TO ROLE WORKBENCH_SCIENTIST;

-- =============================================================================
-- 5. APPROVE / REJECT CUSTOM TOOL — admin-only procedures
-- =============================================================================

CREATE OR REPLACE PROCEDURE CATALOG.APPROVE_CUSTOM_TOOL(
    P_SUBMISSION_ID VARCHAR,
    P_NOTES VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
COMMENT = 'Approve a pending custom tool submission. Generates wrapper, validates at runtime, registers with rich knowledge.'
EXECUTE AS CALLER
AS
$$
import json
import re
import time


def _build_test_input(spec):
    """Build a minimal test input from the tool spec for runtime validation."""
    # Check for explicit known_answer_test in the spec
    kat = spec.get("known_answer_test")
    if kat and isinstance(kat, dict) and kat.get("input"):
        return kat["input"], kat.get("expected_output_contains")

    # Auto-generate minimal test inputs from parameter schema
    params = spec.get("parameters", {})
    test_input = {}
    for pname, pspec in params.items():
        if pname.lower() == "output_table":
            continue
        ptype = pspec.get("type", "STRING").upper() if isinstance(pspec, dict) else str(pspec).upper()
        if ptype in ("INT", "INTEGER", "NUMBER"):
            test_input[pname] = 1
        elif ptype in ("FLOAT", "DOUBLE"):
            test_input[pname] = 1.0
        elif ptype == "BOOLEAN":
            test_input[pname] = True
        else:
            # For string params, try to infer a safe test value from semantic type
            sem = pspec.get("semantic_type", "") if isinstance(pspec, dict) else ""
            if "SMILES" in sem.upper() or "smiles" in pname.lower():
                test_input[pname] = "C"  # methane — simplest valid SMILES
            elif "FASTA" in sem.upper() or "sequence" in pname.lower():
                test_input[pname] = "ATGCATGC"
            elif "PDB" in sem.upper() or "pdb" in pname.lower():
                test_input[pname] = "1CRN"  # crambin — tiny, always available
            else:
                test_input[pname] = "test"
    return test_input, None


def _build_rich_knowledge(spec, source_type):
    """Generate rich TOOL_KNOWLEDGE content from the tool spec."""
    params = spec.get("parameters", {})
    domains = spec.get("domains", ["custom"])
    description = spec.get("description", "")
    display_name = spec.get("display_name", spec.get("name", ""))

    # Scientific context
    domain_str = ", ".join(domains) if isinstance(domains, list) else str(domains)
    sci_context = f"{description}\n\nDomains: {domain_str}."
    if source_type == "python_package":
        pkg = spec.get("source_config", {}).get("package_name", "")
        cap = spec.get("source_config", {}).get("capability_name", "")
        sci_context += f"\nBacked by {pkg}" + (f" ({cap} capability)." if cap else ".")
    elif source_type == "rest_api":
        url = spec.get("source_config", {}).get("url", "")
        sci_context += f"\nWraps external API: {url}"

    # Parameter guide
    param_lines = []
    for pname, pspec in params.items():
        if isinstance(pspec, dict):
            ptype = pspec.get("type", "STRING")
            pdesc = pspec.get("description", "")
            sem = pspec.get("semantic_type", "")
            req = " (required)" if pspec.get("required") else " (optional)"
            line = f"- {pname} ({ptype}{req}): {pdesc}"
            if sem:
                line += f" [semantic: {sem}]"
            param_lines.append(line)
        else:
            param_lines.append(f"- {pname} ({pspec})")
    param_guide = "\n".join(param_lines) if param_lines else "No parameters documented."

    # Common pitfalls
    pitfalls = ["This is a custom tool — verify outputs against known references before using in production workflows."]
    if source_type in ("python_package", "python_code"):
        pitfalls.append("Runs in Snowpark Python 3.10 sandbox. Package versions are fixed by the Snowflake runtime.")
    if source_type == "rest_api":
        pitfalls.append("Depends on external API availability. Timeout is 120 seconds. API rate limits may apply.")
    if any("smiles" in p.lower() for p in params):
        pitfalls.append("SMILES inputs must be valid. Invalid SMILES may produce errors or empty results.")

    # Output guide
    output_guide = "Results are written to the specified output_table in SCIENTIFIC_WORKBENCH.RESULTS. Check the table for columns and data types."

    # Example SQL
    param_placeholders = ", ".join(f"'<{p}>'" for p in params)
    func_ref = spec.get("source_config", {}).get("function_reference",
                f"SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_{spec.get('name', 'TOOL').upper()}")
    example_sql = f"CALL {func_ref}({param_placeholders})"

    return {
        "scientific_context": sci_context,
        "parameter_guide": param_guide,
        "output_guide": output_guide,
        "common_pitfalls": "\n".join(pitfalls),
        "example_sql": example_sql,
    }


def run(session, p_submission_id, p_notes):
    if not p_submission_id:
        return {"status": "ERROR", "error": "submission_id is required"}

    # Fetch the submission
    rows = session.sql(
        "SELECT tool_spec, status, submitted_by "
        "FROM SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_TOOL_SUBMISSIONS "
        "WHERE submission_id = ?", params=[p_submission_id]
    ).collect()

    if not rows:
        return {"status": "ERROR", "error": f"Submission {p_submission_id} not found"}

    if rows[0]["STATUS"] != "pending":
        return {"status": "ERROR", "error": f"Submission is already {rows[0]['STATUS']}"}

    spec = rows[0]["TOOL_SPEC"]
    if isinstance(spec, str):
        spec = json.loads(spec)

    submitted_by = rows[0]["SUBMITTED_BY"]
    source_type = spec.get("source_type", "")
    name = spec.get("name", "")

    # ---------------------------------------------------------------
    # STEP 1: Generate the tool wrapper DDL
    # ---------------------------------------------------------------
    try:
        gen_rows = session.sql(
            "CALL SCIENTIFIC_WORKBENCH.CATALOG.GENERATE_TOOL_WRAPPER(?, ?, PARSE_JSON(?), PARSE_JSON(?), ?)",
            params=[
                name, source_type,
                json.dumps(spec.get("source_config", {})),
                json.dumps(spec.get("parameters", {})),
                spec.get("return_type", "VARCHAR")
            ]
        ).collect()
        ddl = gen_rows[0][0] if gen_rows else None
    except Exception as exc:
        return {"status": "ERROR", "error": f"Wrapper generation failed: {str(exc)[:500]}"}

    if not ddl or str(ddl).startswith("ERROR"):
        return {"status": "ERROR", "error": f"Wrapper generation returned: {ddl}"}

    # ---------------------------------------------------------------
    # STEP 2: Execute the generated DDL (CREATE PROCEDURE)
    # ---------------------------------------------------------------
    func_ref = spec.get("source_config", {}).get("function_reference",
                f"SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_{re.sub(r'[^A-Za-z0-9_]', '', name).upper()}")

    if ddl != "NO_DDL_NEEDED":
        try:
            session.sql(ddl).collect()
        except Exception as exc:
            return {"status": "ERROR", "error": f"DDL execution failed: {str(exc)[:500]}",
                    "ddl": ddl[:2000]}

    # ---------------------------------------------------------------
    # STEP 3: RUNTIME VALIDATION — test-execute the procedure
    # ---------------------------------------------------------------
    validation_result = None
    test_input, expected_contains = _build_test_input(spec)

    if test_input:
        test_table = f"SCIENTIFIC_WORKBENCH.RESULTS._BYOT_VALIDATION_{re.sub(r'[^A-Za-z0-9_]', '', name).upper()}"
        test_input["output_table"] = test_table
        try:
            test_rows = session.sql(
                "CALL SCIENTIFIC_WORKBENCH.CATALOG.EXECUTE_TOOL_BY_NAME(?, PARSE_JSON(?))",
                params=[name if ddl == "NO_DDL_NEEDED" else f"custom_{name}",
                        json.dumps(test_input)]
            ).collect()
            test_result = test_rows[0][0] if test_rows else None
            if isinstance(test_result, str):
                try:
                    test_result = json.loads(test_result)
                except Exception:
                    pass

            if isinstance(test_result, dict) and test_result.get("status") == "ERROR":
                # Runtime validation FAILED — roll back by dropping the procedure
                if ddl != "NO_DDL_NEEDED":
                    try:
                        session.sql(f"DROP PROCEDURE IF EXISTS {func_ref}(VARCHAR, VARCHAR)").collect()
                    except Exception:
                        pass
                return {
                    "status": "ERROR",
                    "error": f"Runtime validation failed: {test_result.get('error', 'unknown error')[:500]}",
                    "test_input": test_input,
                    "phase": "runtime_validation"
                }

            # Check expected output if provided
            if expected_contains and isinstance(test_result, dict):
                result_str = json.dumps(test_result)
                if expected_contains not in result_str:
                    validation_result = f"WARNING: Expected output to contain '{expected_contains}' but it was not found. Tool registered but may need review."

            # Clean up validation table
            try:
                session.sql(f"DROP TABLE IF EXISTS {test_table}").collect()
            except Exception:
                pass

            validation_result = validation_result or "PASSED"

        except Exception as exc:
            # Runtime validation failed — procedure crashes
            if ddl != "NO_DDL_NEEDED":
                try:
                    session.sql(f"DROP PROCEDURE IF EXISTS {func_ref}(VARCHAR, VARCHAR)").collect()
                except Exception:
                    pass
            return {
                "status": "ERROR",
                "error": f"Runtime validation crashed: {str(exc)[:500]}",
                "test_input": test_input,
                "phase": "runtime_validation"
            }

    # ---------------------------------------------------------------
    # STEP 4: Register in CATALOG.TOOLS
    # ---------------------------------------------------------------
    domains = ",".join(spec.get("domains", ["custom"]))
    params_json = json.dumps(spec.get("parameters", {}))

    try:
        reg_rows = session.sql(
            "CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(?, ?, ?, ?, ?, ?, ?, ?, ?)",
            params=[
                name, spec.get("display_name", name), spec.get("description", ""),
                domains, "procedure", func_ref, params_json,
                spec.get("return_type", "VARCHAR"),
                spec.get("example_usage", f"CALL {func_ref}(...)")
            ]
        ).collect()
        reg_result = reg_rows[0][0] if reg_rows else "unknown"
    except Exception as exc:
        return {"status": "ERROR", "error": f"Registration failed: {str(exc)[:500]}"}

    tool_id = None
    match = re.search(r'ID:\s*(T\d+)', str(reg_result))
    if match:
        tool_id = match.group(1)

    # ---------------------------------------------------------------
    # STEP 5: Update CATALOG.TOOLS with BYOT metadata
    # ---------------------------------------------------------------
    if tool_id:
        try:
            session.sql(
                "UPDATE SCIENTIFIC_WORKBENCH.CATALOG.TOOLS "
                "SET source_type = ?, source_config = PARSE_JSON(?), "
                "    compute_env = ?, visibility = ?, "
                "    submitted_by = ?, approved_by = CURRENT_USER(), "
                "    approved_at = CURRENT_TIMESTAMP() "
                "WHERE tool_id = ?",
                params=[source_type, json.dumps(spec.get("source_config", {})),
                        spec.get("compute_env", "warehouse"),
                        spec.get("visibility", "shared"),
                        submitted_by, tool_id]
            ).collect()
        except Exception:
            pass

    # ---------------------------------------------------------------
    # STEP 6: Insert RICH TOOL_KNOWLEDGE (Gap 3 fix)
    # ---------------------------------------------------------------
    knowledge = _build_rich_knowledge(spec, source_type)
    try:
        # Delete any existing thin knowledge row
        session.sql("DELETE FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOL_KNOWLEDGE WHERE TOOL_NAME = ?",
                    params=[name]).collect()
        session.sql(
            "INSERT INTO SCIENTIFIC_WORKBENCH.CATALOG.TOOL_KNOWLEDGE "
            "(TOOL_NAME, SCIENTIFIC_CONTEXT, PARAMETER_GUIDE, EXAMPLE_INPUTS, "
            " OUTPUT_GUIDE, COMMON_PITFALLS, RELATED_TOOLS, EXAMPLE_SQL) "
            "SELECT ?, ?, ?, PARSE_JSON(?), ?, ?, ARRAY_CONSTRUCT(), ?",
            params=[
                name,
                knowledge["scientific_context"],
                knowledge["parameter_guide"],
                json.dumps([spec.get("example_usage", "")]),
                knowledge["output_guide"],
                knowledge["common_pitfalls"],
                knowledge["example_sql"]
            ]
        ).collect()
    except Exception:
        pass

    # ---------------------------------------------------------------
    # STEP 7: Update submission status
    # ---------------------------------------------------------------
    session.sql(
        "UPDATE SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_TOOL_SUBMISSIONS "
        "SET status = 'approved', reviewer = CURRENT_USER(), "
        "    reviewed_at = CURRENT_TIMESTAMP(), review_notes = ?, tool_id = ? "
        "WHERE submission_id = ?",
        params=[p_notes or "", tool_id or "", p_submission_id]
    ).collect()

    return {
        "status": "OK",
        "action": "approved",
        "submission_id": p_submission_id,
        "tool_id": tool_id,
        "registration": reg_result,
        "function_reference": func_ref,
        "runtime_validation": validation_result or "SKIPPED (no test input available)"
    }
$$;


CREATE OR REPLACE PROCEDURE CATALOG.REJECT_CUSTOM_TOOL(
    P_SUBMISSION_ID VARCHAR,
    P_NOTES VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'Reject a pending custom tool submission with a reason.'
EXECUTE AS CALLER
AS
$$
BEGIN
    UPDATE SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_TOOL_SUBMISSIONS
    SET status = 'rejected',
        reviewer = CURRENT_USER(),
        reviewed_at = CURRENT_TIMESTAMP(),
        review_notes = :P_NOTES
    WHERE submission_id = :P_SUBMISSION_ID
      AND status = 'pending';

    IF (SQLROWCOUNT = 0) THEN
        RETURN PARSE_JSON('{"status":"ERROR","error":"Submission not found or not pending"}');
    END IF;

    RETURN PARSE_JSON('{"status":"OK","action":"rejected","submission_id":"' || :P_SUBMISSION_ID || '"}');
END;
$$;

-- Grant approval procedures to admin only
GRANT USAGE ON PROCEDURE CATALOG.APPROVE_CUSTOM_TOOL(VARCHAR, VARCHAR) TO ROLE WORKBENCH_ADMIN;
GRANT USAGE ON PROCEDURE CATALOG.REJECT_CUSTOM_TOOL(VARCHAR, VARCHAR) TO ROLE WORKBENCH_ADMIN;

-- =============================================================================
-- 6. TOOL WRAPPER GENERATOR
-- =============================================================================

CREATE OR REPLACE PROCEDURE CATALOG.GENERATE_TOOL_WRAPPER(
    P_NAME         VARCHAR,
    P_SOURCE_TYPE  VARCHAR,
    P_SOURCE_CONFIG VARIANT,
    P_PARAMETERS   VARIANT,
    P_RETURN_TYPE  VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
COMMENT = 'Generate CREATE PROCEDURE DDL for a custom tool wrapper'
EXECUTE AS CALLER
AS
$$
import json
import re
# Built at runtime: a literal dollar-quote here would end this procedure body.
DQ = "$" * 2


def _safe_identifier(name):
    """Ensure a name is a safe SQL identifier."""
    cleaned = re.sub(r'[^A-Za-z0-9_]', '', name)
    if not cleaned or not cleaned[0].isalpha():
        cleaned = 'T_' + cleaned
    return cleaned.upper()


def _build_param_list(parameters):
    """Build SQL parameter declarations from the parameters spec."""
    if not parameters:
        return "output_table VARCHAR", ["output_table"]

    parts = []
    names = []
    for pname, pspec in parameters.items():
        if pname.lower() == 'output_table':
            continue
        sql_type = "VARCHAR"
        if isinstance(pspec, dict):
            t = pspec.get("type", "STRING").upper()
            if t in ("INT", "INTEGER", "NUMBER"):
                sql_type = "INT"
            elif t in ("FLOAT", "DOUBLE", "NUMBER"):
                sql_type = "FLOAT"
            elif t == "BOOLEAN":
                sql_type = "BOOLEAN"
            elif t in ("VARIANT", "OBJECT", "ARRAY"):
                sql_type = "VARIANT"
            else:
                sql_type = "VARCHAR"
        elif isinstance(pspec, str):
            sql_type = pspec if pspec.upper() in ("VARCHAR","INT","FLOAT","BOOLEAN","VARIANT") else "VARCHAR"
        parts.append(f"    {_safe_identifier(pname)} {sql_type}")
        names.append(pname)

    parts.append("    OUTPUT_TABLE VARCHAR")
    names.append("output_table")
    return ",\n".join(parts), names


def _validate_python_code(code, session):
    """Check Python code against banned patterns. Returns list of violations."""
    violations = []
    try:
        rows = session.sql(
            "SELECT pattern, reason FROM SCIENTIFIC_WORKBENCH.CATALOG.BYOT_BANNED_PATTERNS"
        ).collect()
        for row in rows:
            if re.search(row["PATTERN"], code):
                violations.append(row["REASON"])
    except Exception:
        violations.append("Could not validate code against banned patterns")
    return violations


def _validate_packages(packages, session):
    """Check that all requested packages are in the allowlist."""
    if not packages:
        return []
    violations = []
    try:
        rows = session.sql(
            "SELECT package_name FROM SCIENTIFIC_WORKBENCH.CATALOG.BYOT_PYTHON_ALLOWLIST"
        ).collect()
        allowed = {r["PACKAGE_NAME"].lower() for r in rows}
        for pkg in packages:
            if pkg.lower().strip() not in allowed:
                violations.append(f"Package '{pkg}' is not in the allowlist")
    except Exception:
        violations.append("Could not validate packages against allowlist")
    return violations


def _generate_rest_api(name, config, parameters):
    """Generate a REST API wrapper procedure."""
    safe_name = _safe_identifier(name)
    proc_name = f"CUSTOM_{safe_name}"
    url = config.get("url", "")
    method = config.get("method", "POST").upper()
    auth_type = config.get("auth_type", "none")
    response_path = config.get("response_path", "")
    headers = config.get("headers", {})

    if not url or not url.startswith("https://"):
        return "ERROR: URL must be HTTPS"

    param_decl, param_names = _build_param_list(parameters)

    # Build secrets clause
    secrets_clause = ""
    secret_code = ""
    if auth_type in ("api_key", "bearer"):
        secret_name = f"SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_TOOL_{safe_name}_KEY"
        secrets_clause = f"\nSECRETS = ('api_key' = {secret_name})"
        secret_code = "    api_key = _snowflake.get_generic_secret_string('api_key')"

    # Build header code
    header_lines = ["    headers = {'Content-Type': 'application/json'}"]
    if auth_type == "bearer":
        header_lines.append("    headers['Authorization'] = f'Bearer {api_key}'")
    elif auth_type == "api_key":
        header_key = config.get("auth_header", "X-API-Key")
        header_lines.append(f"    headers['{header_key}'] = api_key")
    for k, v in headers.items():
        header_lines.append(f"    headers['{k}'] = '{v}'")
    headers_code = "\n".join(header_lines)

    # Build request body mapping
    body_parts = []
    for pname in param_names:
        if pname.lower() != "output_table":
            body_parts.append(f"        '{pname}': {pname}")
    body_code = "    payload = {\n" + ",\n".join(body_parts) + "\n    }"

    # Build response parsing
    if response_path:
        parts = response_path.split(".")
        access = "data"
        for p in parts:
            access += f".get('{p}', {{}})"
        response_code = f"    result_data = {access}"
    else:
        response_code = "    result_data = data"

    ddl = f"""CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.{proc_name}(
{param_decl}
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (CUSTOM_API_EAI){secrets_clause}
COMMENT = 'TOOL:{{"display_name":"{config.get("display_name", name)}","description":"Custom REST API tool","domains":"custom","params":{{}},"return_type":"VARCHAR"}}'
AS
{DQ}
import json, requests, pandas as pd
{"import _snowflake" if auth_type != "none" else ""}
from snowflake.snowpark.context import get_active_session

def run(session, {", ".join(f"{_safe_identifier(p).lower()}" for p in param_names)}):
{secret_code}
{headers_code}
{body_code}

    response = requests.{method.lower()}(
        '{url}',
        headers=headers,
        {"json=payload" if method == "POST" else "params=payload"},
        timeout=120
    )
    response.raise_for_status()
    data = response.json()

{response_code}

    if isinstance(result_data, list) and result_data:
        result_df = pd.DataFrame(result_data)
        sp_df = session.create_dataframe(result_df)
        sp_df.write.mode('overwrite').save_as_table(output_table)
        return json.dumps({{"status": "SUCCESS", "rows": len(result_data), "output_table": output_table}})
    else:
        return json.dumps({{"status": "SUCCESS", "result": str(result_data)[:4000]}})
{DQ};"""

    return ddl


def _generate_python_code(name, config, parameters, session):
    """Generate a Python code wrapper procedure."""
    safe_name = _safe_identifier(name)
    proc_name = f"CUSTOM_{safe_name}"
    code = config.get("code", "")
    packages = config.get("packages", [])

    if not code:
        return "ERROR: No code provided"

    # Validate code against banned patterns
    violations = _validate_python_code(code, session)
    if violations:
        return "ERROR: Code violates security policy: " + "; ".join(violations)

    # Validate packages
    pkg_violations = _validate_packages(packages, session)
    if pkg_violations:
        return "ERROR: " + "; ".join(pkg_violations)

    param_decl, param_names = _build_param_list(parameters)

    # Build package list
    pkg_list = ["'snowflake-snowpark-python'", "'pandas'"]
    for pkg in packages:
        quoted = f"'{pkg.strip()}'"
        if quoted not in pkg_list:
            pkg_list.append(quoted)

    # Escape user code for embedding in dollar-quoted string
    escaped_code = code.replace(DQ, "\\$\\$")

    ddl = f"""CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.{proc_name}(
{param_decl}
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ({", ".join(pkg_list)})
HANDLER = 'run'
COMMENT = 'TOOL:{{"display_name":"{config.get("display_name", name)}","description":"Custom Python tool","domains":"custom","params":{{}},"return_type":"VARCHAR"}}'
AS
{DQ}
import json, pandas as pd
from snowflake.snowpark.context import get_active_session

# --- User-provided code (sandboxed) ---
def _user_function({", ".join(p for p in param_names if p != "output_table")}):
{chr(10).join("    " + line for line in escaped_code.split(chr(10)))}

def run(session, {", ".join(f"{_safe_identifier(p).lower()}" for p in param_names)}):
    try:
        result = _user_function({", ".join(p for p in param_names if p != "output_table")})

        if isinstance(result, pd.DataFrame):
            sp_df = session.create_dataframe(result)
            sp_df.write.mode('overwrite').save_as_table(output_table)
            return json.dumps({{"status": "SUCCESS", "rows": len(result), "output_table": output_table}})
        else:
            return json.dumps({{"status": "SUCCESS", "result": str(result)[:4000]}})
    except Exception as exc:
        return json.dumps({{"status": "ERROR", "error": str(exc)[:2000]}})
{DQ};"""

    return ddl


def _generate_spcs_container(name, config, parameters):
    """Generate SPCS service spec + service function. Returns DDL for both."""
    safe_name = _safe_identifier(name)
    image_uri = config.get("image_uri", "")
    endpoint_path = config.get("endpoint_path", "/predict")
    port = config.get("port", 8080)
    compute_pool = config.get("compute_pool", "WORKBENCH_CPU_POOL")
    env_vars = config.get("env_vars", {})

    if not image_uri:
        return "ERROR: image_uri is required for SPCS containers"

    param_decl, param_names = _build_param_list(parameters)

    # Build env block
    env_block = ""
    if env_vars:
        env_lines = [f'          {k}: "{v}"' for k, v in env_vars.items()]
        env_block = "\n        env:\n" + "\n".join(env_lines)

    service_name = f"CUSTOM_{safe_name}_SVC"
    func_name = f"CUSTOM_{safe_name}_SVCFN"
    proc_name = f"CUSTOM_{safe_name}"

    # 1. CREATE SERVICE
    svc_ddl = f"""CREATE SERVICE IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.{service_name}
  IN COMPUTE POOL {compute_pool}
  MIN_INSTANCES = 0
  MAX_INSTANCES = 1
  AUTO_SUSPEND_SECS = 300
  COMMENT = 'SPCS service for custom tool {name}'
  FROM SPECIFICATION {DQ}
  spec:
    containers:
      - name: tool
        image: {image_uri}
        resources:
          requests:
            memory: 4Gi
            cpu: "2"
          limits:
            memory: 8Gi
            cpu: "4"
        readinessProbe:
          port: {port}
          path: /health{env_block}
    endpoints:
      - name: api
        port: {port}
  {DQ};"""

    # 2. CREATE SERVICE FUNCTION (bridges proc→service gap)
    svcfn_ddl = f"""CREATE OR REPLACE FUNCTION SCIENTIFIC_WORKBENCH.CATALOG.{func_name}(input VARIANT)
RETURNS VARIANT
SERVICE = SCIENTIFIC_WORKBENCH.CATALOG.{service_name}
ENDPOINT = api
AS '{endpoint_path}';"""

    # 3. CREATE PROCEDURE that calls the service function
    body_parts = []
    for pname in param_names:
        if pname.lower() != "output_table":
            body_parts.append(f"        '{pname}': {_safe_identifier(pname).lower()}")
    payload_code = "    payload = {\n" + ",\n".join(body_parts) + "\n    }"

    proc_ddl = f"""CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.{proc_name}(
{param_decl}
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
COMMENT = 'TOOL:{{"display_name":"{name}","description":"Custom SPCS container tool","domains":"custom","params":{{}},"return_type":"VARCHAR"}}'
AS
{DQ}
import json, pandas as pd
from snowflake.snowpark.context import get_active_session

def run(session, {", ".join(f"{_safe_identifier(p).lower()}" for p in param_names)}):
{payload_code}

    rows = session.sql(
        "SELECT SCIENTIFIC_WORKBENCH.CATALOG.{func_name}(PARSE_JSON(?)) AS result",
        params=[json.dumps(payload)]
    ).collect()

    result = rows[0]["RESULT"] if rows else None
    if isinstance(result, str):
        try:
            result = json.loads(result)
        except Exception:
            pass

    if isinstance(result, (list, dict)):
        if isinstance(result, list) and result:
            result_df = pd.DataFrame(result)
            sp_df = session.create_dataframe(result_df)
            sp_df.write.mode('overwrite').save_as_table(output_table)
            return json.dumps({{"status": "SUCCESS", "rows": len(result), "output_table": output_table}})
        return json.dumps({{"status": "SUCCESS", "result": str(result)[:4000]}})
    return json.dumps({{"status": "SUCCESS", "result": str(result)[:4000]}})
{DQ};"""

    return svc_ddl + "\n\n" + svcfn_ddl + "\n\n" + proc_ddl


def _handle_existing_procedure(name, config, session):
    """Validate an existing procedure and return NO_DDL_NEEDED."""
    func_ref = config.get("function_reference", "")
    if not func_ref:
        return "ERROR: function_reference is required for existing_procedure source type"

    parts = func_ref.split(".")
    if len(parts) != 3:
        return "ERROR: function_reference must be fully qualified (DB.SCHEMA.NAME)"

    db, schema, proc_name = [p.strip('"') for p in parts]
    rows = session.sql(
        f"SELECT ARGUMENT_SIGNATURE FROM {db}.INFORMATION_SCHEMA.PROCEDURES "
        f"WHERE PROCEDURE_SCHEMA = '{schema.upper()}' AND PROCEDURE_NAME = '{proc_name.upper()}' "
        f"LIMIT 1"
    ).collect()

    if not rows:
        return f"ERROR: Procedure {func_ref} not found"

    return "NO_DDL_NEEDED"


def _generate_python_package(name, config, parameters, session):
    """Generate a tool from the package catalog or via AI-assisted code generation."""
    safe_name = _safe_identifier(name)
    proc_name = f"CUSTOM_{safe_name}"
    package_name = config.get("package_name", "")
    capability_name = config.get("capability_name", "")
    capability_description = config.get("capability_description", "")

    if not package_name:
        return "ERROR: package_name is required for python_package source type"

    code = None
    resolved_params = parameters
    resolved_packages = [package_name]
    display = config.get("display_name", name)

    # Path 1: Check curated catalog
    if capability_name:
        rows = session.sql(
            "SELECT code_template, parameters, packages, display_name, domains "
            "FROM SCIENTIFIC_WORKBENCH.CATALOG.BYOT_PACKAGE_CATALOG "
            "WHERE package_name = ? AND capability_name = ?",
            params=[package_name.lower(), capability_name.lower()]
        ).collect()
        if rows:
            code = rows[0]["CODE_TEMPLATE"]
            if not resolved_params:
                cat_params = rows[0]["PARAMETERS"]
                if isinstance(cat_params, str):
                    import json as _json
                    resolved_params = _json.loads(cat_params)
                elif isinstance(cat_params, dict):
                    resolved_params = cat_params
            pkg_arr = rows[0]["PACKAGES"]
            if pkg_arr:
                resolved_packages = list(pkg_arr) if isinstance(pkg_arr, (list, tuple)) else [package_name]
            display = rows[0]["DISPLAY_NAME"] or display

    # Path 2: AI-assisted generation if not in catalog
    if not code and capability_description:
        try:
            ai_rows = session.sql(
                "CALL SCIENTIFIC_WORKBENCH.CATALOG.GENERATE_TOOL_CODE_AI(?, ?, ?)",
                params=[package_name, capability_name or "custom", capability_description]
            ).collect()
            ai_result = ai_rows[0][0] if ai_rows else None
            if isinstance(ai_result, str):
                import json as _json
                ai_result = _json.loads(ai_result)
            if isinstance(ai_result, dict):
                code = ai_result.get("code", "")
                if not resolved_params and ai_result.get("parameters"):
                    resolved_params = ai_result["parameters"]
                if ai_result.get("display_name"):
                    display = ai_result["display_name"]
        except Exception as exc:
            return f"ERROR: AI code generation failed: {str(exc)[:500]}"

    if not code:
        return f"ERROR: No capability template found for {package_name}/{capability_name} and no description provided for AI generation"

    # Validate generated code against banned patterns
    violations = _validate_python_code(code, session)
    if violations:
        return "ERROR: Generated code violates security policy: " + "; ".join(violations)

    pkg_violations = _validate_packages(resolved_packages, session)
    if pkg_violations:
        return "ERROR: " + "; ".join(pkg_violations)

    # Use the python_code generator with the resolved code
    config["code"] = code
    config["packages"] = resolved_packages
    config["display_name"] = display
    return _generate_python_code(name, config, resolved_params, session)


def _generate_git_repo(name, config, parameters, session):
    """Generate a tool from a Git repository specification.

    The repo must contain a tool manifest (tool.json or tool.yaml) or a
    main Python file. For now, the user provides the code extracted from
    the repo — full git clone support requires SPCS or an EAI for git hosts.
    """
    safe_name = _safe_identifier(name)
    repo_url = config.get("repo_url", "")
    entry_point = config.get("entry_point", "")
    code = config.get("code", "")
    packages = config.get("packages", [])

    if not repo_url and not code:
        return "ERROR: Either repo_url or code must be provided for git_repo source type"

    if not code:
        # Without SPCS git clone capability, we cannot fetch the repo at SQL time.
        # The frontend/API layer should fetch the repo content and pass it in source_config.code.
        return ("ERROR: Direct git clone from SQL is not yet supported. "
                "The API layer should fetch repo content and pass it in source_config.code. "
                f"Repo: {repo_url}, Entry point: {entry_point}")

    # Validate and delegate to python_code generator
    violations = _validate_python_code(code, session)
    if violations:
        return "ERROR: Repo code violates security policy: " + "; ".join(violations)

    config["packages"] = packages
    return _generate_python_code(name, config, parameters, session)


def run(session, p_name, p_source_type, p_source_config, p_parameters, p_return_type):
    if not p_name or not p_source_type:
        return "ERROR: name and source_type are required"

    config = p_source_config if isinstance(p_source_config, dict) else {}
    parameters = p_parameters if isinstance(p_parameters, dict) else {}
    source_type = str(p_source_type).lower().strip()

    if source_type == "rest_api":
        return _generate_rest_api(p_name, config, parameters)
    elif source_type == "python_code":
        return _generate_python_code(p_name, config, parameters, session)
    elif source_type == "python_package":
        return _generate_python_package(p_name, config, parameters, session)
    elif source_type == "git_repo":
        return _generate_git_repo(p_name, config, parameters, session)
    elif source_type == "spcs_container":
        return _generate_spcs_container(p_name, config, parameters)
    elif source_type == "existing_procedure":
        return _handle_existing_procedure(p_name, config, session)
    else:
        return f"ERROR: Unknown source_type '{source_type}'. Expected: rest_api, python_code, python_package, git_repo, spcs_container, existing_procedure"
$$;

-- =============================================================================
-- 7. ONBOARD_CUSTOM_TOOL — main entry point
-- =============================================================================

CREATE OR REPLACE PROCEDURE CATALOG.ONBOARD_CUSTOM_TOOL(P_SPEC VARIANT)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
COMMENT = 'Main entry point for submitting a custom tool. Routes existing_procedure to immediate registration, others to approval queue.'
EXECUTE AS CALLER
AS
$$
import json
import re
import uuid


def _safe_id(name):
    return re.sub(r'[^A-Za-z0-9_]', '', name).upper()


def run(session, p_spec):
    spec = p_spec
    if isinstance(spec, str):
        try:
            spec = json.loads(spec)
        except Exception:
            return {"status": "ERROR", "error": "P_SPEC must be a valid JSON object"}
    if not isinstance(spec, dict):
        return {"status": "ERROR", "error": "P_SPEC must be a JSON object"}

    # Validate required fields
    required = ["name", "source_type"]
    missing = [f for f in required if not spec.get(f)]
    if missing:
        return {"status": "ERROR", "error": f"Missing required fields: {', '.join(missing)}"}

    name = str(spec["name"]).strip().lower()
    name = re.sub(r'[^a-z0-9_]', '_', name)

    source_type = str(spec["source_type"]).strip().lower()
    valid_types = ("rest_api", "python_code", "python_package", "git_repo", "existing_procedure", "spcs_container")
    if source_type not in valid_types:
        return {"status": "ERROR", "error": f"Invalid source_type. Must be one of: {', '.join(valid_types)}"}

    # Check name uniqueness
    existing = session.sql(
        "SELECT COUNT(*) AS cnt FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS WHERE name = ?",
        params=[name]
    ).collect()
    if existing and existing[0]["CNT"] > 0:
        return {"status": "ERROR", "error": f"Tool name '{name}' already exists"}

    # Check pending submissions
    pending = session.sql(
        "SELECT COUNT(*) AS cnt FROM SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_TOOL_SUBMISSIONS "
        "WHERE tool_spec:name::VARCHAR = ? AND status = 'pending'",
        params=[name]
    ).collect()
    if pending and pending[0]["CNT"] > 0:
        return {"status": "ERROR", "error": f"A submission for '{name}' is already pending approval"}

    # ---------------------------------------------------------------
    # EXISTING PROCEDURE — auto-approve, register immediately
    # ---------------------------------------------------------------
    if source_type == "existing_procedure":
        config = spec.get("source_config", {})
        func_ref = config.get("function_reference", "")
        if not func_ref:
            return {"status": "ERROR", "error": "source_config.function_reference is required"}

        # Validate it exists
        gen_rows = session.sql(
            "CALL SCIENTIFIC_WORKBENCH.CATALOG.GENERATE_TOOL_WRAPPER(?, ?, PARSE_JSON(?), PARSE_JSON(?), ?)",
            params=[name, source_type, json.dumps(config),
                    json.dumps(spec.get("parameters", {})),
                    spec.get("return_type", "VARCHAR")]
        ).collect()
        result = gen_rows[0][0] if gen_rows else ""
        if result.startswith("ERROR"):
            return {"status": "ERROR", "error": result}

        # Register directly
        domains = ",".join(spec.get("domains", ["custom"]))
        params_json = json.dumps(spec.get("parameters", {}))

        reg_rows = session.sql(
            "CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(?, ?, ?, ?, ?, ?, ?, ?, ?)",
            params=[
                name,
                spec.get("display_name", name),
                spec.get("description", ""),
                domains,
                "procedure",
                func_ref,
                params_json,
                spec.get("return_type", "VARCHAR"),
                spec.get("example_usage", f"CALL {func_ref}(...)")
            ]
        ).collect()
        reg_result = reg_rows[0][0] if reg_rows else "registered"

        tool_id = None
        match = re.search(r'ID:\s*(T\d+)', str(reg_result))
        if match:
            tool_id = match.group(1)

        # Set BYOT metadata
        if tool_id:
            try:
                session.sql(
                    "UPDATE SCIENTIFIC_WORKBENCH.CATALOG.TOOLS "
                    "SET source_type = 'existing_procedure', "
                    "    source_config = PARSE_JSON(?), "
                    "    visibility = ?, submitted_by = CURRENT_USER(), "
                    "    approved_by = CURRENT_USER(), approved_at = CURRENT_TIMESTAMP() "
                    "WHERE tool_id = ?",
                    params=[json.dumps(config), spec.get("visibility", "shared"), tool_id]
                ).collect()
            except Exception:
                pass

        return {
            "status": "active",
            "tool_id": tool_id,
            "name": name,
            "function_reference": func_ref,
            "message": "Existing procedure registered immediately — no approval needed."
        }

    # ---------------------------------------------------------------
    # ALL OTHER TYPES — queue for admin approval
    # ---------------------------------------------------------------
    submission_id = "SUB-" + str(uuid.uuid4())[:8].upper()

    # Pre-validate before queuing
    config = spec.get("source_config", {})

    if source_type == "rest_api":
        url = config.get("url", "")
        if not url.startswith("https://"):
            return {"status": "ERROR", "error": "REST API URL must use HTTPS"}

    if source_type == "python_code":
        code = config.get("code", "")
        if not code.strip():
            return {"status": "ERROR", "error": "Python code cannot be empty"}
        # Pre-validate code
        gen_rows = session.sql(
            "CALL SCIENTIFIC_WORKBENCH.CATALOG.GENERATE_TOOL_WRAPPER(?, ?, PARSE_JSON(?), PARSE_JSON(?), ?)",
            params=[name, source_type, json.dumps(config),
                    json.dumps(spec.get("parameters", {})),
                    spec.get("return_type", "VARCHAR")]
        ).collect()
        result = gen_rows[0][0] if gen_rows else ""
        if str(result).startswith("ERROR"):
            return {"status": "ERROR", "error": result}

    if source_type == "spcs_container":
        if not config.get("image_uri"):
            return {"status": "ERROR", "error": "source_config.image_uri is required for SPCS containers"}

    if source_type == "python_package":
        if not config.get("package_name"):
            return {"status": "ERROR", "error": "source_config.package_name is required for python_package"}
        # Must have either a known capability or a description for AI generation
        if not config.get("capability_name") and not config.get("capability_description"):
            return {"status": "ERROR", "error": "Either capability_name (from catalog) or capability_description (for AI generation) is required"}

    if source_type == "git_repo":
        if not config.get("repo_url") and not config.get("code"):
            return {"status": "ERROR", "error": "source_config.repo_url or source_config.code is required for git_repo"}

    # Insert into submissions queue
    spec["name"] = name  # normalized
    session.sql(
        "INSERT INTO SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_TOOL_SUBMISSIONS "
        "(submission_id, tool_spec) "
        "SELECT ?, PARSE_JSON(?)",
        params=[submission_id, json.dumps(spec)]
    ).collect()

    return {
        "status": "pending_approval",
        "submission_id": submission_id,
        "name": name,
        "source_type": source_type,
        "message": f"Submitted for admin review. Submission ID: {submission_id}"
    }
$$;

-- Grant to scientists (submit) and admins (submit + approve)
GRANT USAGE ON PROCEDURE CATALOG.ONBOARD_CUSTOM_TOOL(VARIANT) TO ROLE WORKBENCH_SCIENTIST;
GRANT USAGE ON PROCEDURE CATALOG.ONBOARD_CUSTOM_TOOL(VARIANT) TO ROLE WORKBENCH_ADMIN;
GRANT USAGE ON PROCEDURE CATALOG.GENERATE_TOOL_WRAPPER(VARCHAR, VARCHAR, VARIANT, VARIANT, VARCHAR) TO ROLE WORKBENCH_ADMIN;

-- Submissions table access
GRANT SELECT ON TABLE CATALOG.CUSTOM_TOOL_SUBMISSIONS TO ROLE WORKBENCH_SCIENTIST;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE CATALOG.CUSTOM_TOOL_SUBMISSIONS TO ROLE WORKBENCH_ADMIN;
-- Admins approve, reject and remove custom tools, which writes to the registry.
GRANT INSERT, UPDATE, DELETE ON TABLE CATALOG.TOOLS TO ROLE WORKBENCH_ADMIN;
GRANT SELECT ON TABLE CATALOG.BYOT_PYTHON_ALLOWLIST TO ROLE WORKBENCH_SCIENTIST;
GRANT SELECT ON TABLE CATALOG.BYOT_BANNED_PATTERNS TO ROLE WORKBENCH_ADMIN;
