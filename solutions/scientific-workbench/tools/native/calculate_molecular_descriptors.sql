-- =============================================================================
-- tools/native/calculate_molecular_descriptors.sql
-- RDKit-based molecular property calculation from SMILES
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.CALCULATE_MOLECULAR_DESCRIPTORS(
    input_smiles VARCHAR,    -- Single SMILES string OR fully-qualified table name
    input_mode   VARCHAR,    -- 'single' | 'table'  (table must have a SMILES column)
    output_table VARCHAR     -- Used only when input_mode = 'table'
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'rdkit')
HANDLER = 'run'
COMMENT = 'TOOL:{"display_name":"Molecular Descriptor Calculator","description":"Computes RDKit physicochemical properties from SMILES: molecular weight, LogP, H-bond donors/acceptors, TPSA, rotatable bonds, ring count, and Fsp3. Use for Lipinski Rule of Five filtering.","domains":"chemistry,cheminformatics,admet","params":{"input_smiles":"STRING","input_mode":"STRING","output_table":"STRING"},"return_type":"VARIANT","example":"CALL CATALOG.CALCULATE_MOLECULAR_DESCRIPTORS(smiles, single, output_table)"}'
AS
$$
import json
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.functions import udf, col
from snowflake.snowpark.types import StructType, StructField, StringType, FloatType, IntegerType, BooleanType

def run(session, input_smiles: str, input_mode: str, output_table: str):
    # RDKit is available via Snowflake Anaconda channel
    try:
        from rdkit import Chem
        from rdkit.Chem import Descriptors, rdMolDescriptors
        from rdkit.Chem.FilterCatalog import FilterCatalog, FilterCatalogParams
    except ImportError:
        return {"error": "rdkit not available — add 'rdkit' to PACKAGES"}

    def compute_descriptors(smiles: str) -> dict:
        """Compute properties for a single SMILES."""
        mol = Chem.MolFromSmiles(smiles, sanitize=True)
        if mol is None:
            return {
                "smiles": smiles, "valid": False,
                "mw": None, "logp": None, "hbd": None, "hba": None,
                "tpsa": None, "rotatable_bonds": None, "ring_count": None,
                "fsp3": None, "lipinski_violations": None
            }

        mw    = round(Descriptors.MolWt(mol), 2)
        logp  = round(Descriptors.MolLogP(mol), 3)
        hbd   = rdMolDescriptors.CalcNumHBD(mol)
        hba   = rdMolDescriptors.CalcNumHBA(mol)
        tpsa  = round(Descriptors.TPSA(mol), 2)
        rotb  = rdMolDescriptors.CalcNumRotatableBonds(mol)
        rings = rdMolDescriptors.CalcNumRings(mol)
        fsp3  = round(rdMolDescriptors.CalcFractionCSP3(mol), 3)

        violations = sum([
            mw > 500,
            logp > 5,
            hbd > 5,
            hba > 10
        ])

        return {
            "smiles": smiles, "valid": True,
            "mw": mw, "logp": logp, "hbd": hbd, "hba": hba,
            "tpsa": tpsa, "rotatable_bonds": rotb, "ring_count": rings,
            "fsp3": fsp3, "lipinski_violations": violations
        }

    if input_mode == 'single':
        result = compute_descriptors(input_smiles)
        return result

    # Table mode: read SMILES column from table
    df = session.sql(f"SELECT * FROM {input_smiles}").to_pandas()
    df.columns = [c.upper() for c in df.columns]

    # Find the SMILES column
    smiles_col = next((c for c in df.columns if 'SMILES' in c), None)
    if smiles_col is None:
        return {"error": f"No SMILES column found in {input_smiles}. Columns: {list(df.columns)}"}

    import pandas as pd
    results = [compute_descriptors(s) for s in df[smiles_col].tolist()]
    result_df = pd.DataFrame(results)
    result_sp = session.create_dataframe(result_df)
    result_sp.write.mode('overwrite').save_as_table(output_table)
    return {"status": "success", "rows": len(results), "output_table": output_table}
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'calculate_molecular_descriptors', 'Molecular Descriptor Calculator',
    'Computes physicochemical properties from SMILES: MW, LogP, HBD, HBA, TPSA, rotatable bonds, Fsp3, Lipinski violations.',
    'chemistry,cheminformatics,admet', 'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.CALCULATE_MOLECULAR_DESCRIPTORS',
    '{"input_smiles":"STRING","input_mode":"STRING","output_table":"STRING"}',
    'VARIANT',
    'CALL CATALOG.CALCULATE_MOLECULAR_DESCRIPTORS(smiles, single, output_table)'
);
