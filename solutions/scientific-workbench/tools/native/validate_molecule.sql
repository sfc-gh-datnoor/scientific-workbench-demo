-- =============================================================================
-- tools/native/validate_molecule.sql
-- NIM Plausibility Gate: RDKit + PAINS filter on generated molecules
-- =============================================================================

CREATE OR REPLACE FUNCTION SCIENTIFIC_WORKBENCH.CATALOG.VALIDATE_MOLECULE(smiles VARCHAR)
RETURNS TABLE (
    smiles              VARCHAR,
    valid               BOOLEAN,
    alerts              ARRAY,
    lipinski_violations INT,
    sanitization_error  VARCHAR,
    confidence_tier     VARCHAR   -- 'clean' | 'warn' | 'reject'
)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'rdkit')
HANDLER = 'MolValidator'
COMMENT = 'TOOL:{"display_name":"Molecule Plausibility Gate","description":"Validates generated molecules using RDKit sanitization and PAINS/BRENK structural alert filters. Every NIM-generated molecule must pass this gate before downstream use.","domains":"chemistry,cheminformatics,drug-discovery","params":{"smiles":"STRING"},"return_type":"TABLE","example":"SELECT * FROM TABLE(CATALOG.VALIDATE_MOLECULE(smiles))"}'
AS
$$
class MolValidator:
    def process(self, smiles: str):
        try:
            from rdkit import Chem
            from rdkit.Chem import Descriptors, rdMolDescriptors
            from rdkit.Chem.FilterCatalog import FilterCatalog, FilterCatalogParams
        except ImportError:
            yield (smiles, False, [], 0, 'rdkit not available', 'reject')
            return

        try:
            mol = Chem.MolFromSmiles(smiles, sanitize=True)
        except Exception as e:
            yield (smiles, False, [], 0, str(e), 'reject')
            return

        if mol is None:
            yield (smiles, False, [], 0, 'Could not parse SMILES', 'reject')
            return

        params = FilterCatalogParams()
        params.AddCatalog(FilterCatalogParams.FilterCatalogs.PAINS_A)
        params.AddCatalog(FilterCatalogParams.FilterCatalogs.PAINS_B)
        params.AddCatalog(FilterCatalogParams.FilterCatalogs.PAINS_C)
        params.AddCatalog(FilterCatalogParams.FilterCatalogs.BRENK)
        catalog = FilterCatalog(params)

        alerts = []
        matches = catalog.GetMatches(mol)
        for match in matches:
            alerts.append(match.GetDescription())

        mw   = Descriptors.MolWt(mol)
        logp = Descriptors.MolLogP(mol)
        hbd  = rdMolDescriptors.CalcNumHBD(mol)
        hba  = rdMolDescriptors.CalcNumHBA(mol)
        violations = sum([mw > 500, logp > 5, hbd > 5, hba > 10])

        valid = len(alerts) == 0
        tier = 'clean' if valid and violations == 0 else ('warn' if violations <= 1 else 'reject')

        yield (smiles, valid, alerts, violations, None, tier)
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'validate_molecule', 'Molecule Plausibility Gate',
    'Validates SMILES using RDKit sanitization + PAINS/BRENK structural alert filters. Returns validity, alerts, and confidence tier.',
    'chemistry,cheminformatics,drug-discovery', 'function',
    'SCIENTIFIC_WORKBENCH.CATALOG.VALIDATE_MOLECULE',
    '{"smiles":"STRING"}',
    'TABLE(smiles,valid,alerts,lipinski_violations,sanitization_error,confidence_tier)',
    'SELECT * FROM TABLE(CATALOG.VALIDATE_MOLECULE(''CCO''))'
);
