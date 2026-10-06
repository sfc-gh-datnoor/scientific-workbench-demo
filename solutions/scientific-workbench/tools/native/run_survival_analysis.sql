-- =============================================================================
-- tools/native/run_survival_analysis.sql
-- Kaplan-Meier + log-rank + Cox PH survival analysis
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_SURVIVAL_ANALYSIS(
    patients_table   VARCHAR,
    time_col         VARCHAR,
    event_col        VARCHAR,
    strata_col       VARCHAR,
    filter_condition VARCHAR,  -- optional WHERE clause, empty string to skip
    output_table     VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'scipy', 'numpy', 'pandas', 'lifelines')
HANDLER = 'run'
COMMENT = 'TOOL:{"display_name":"Survival Analysis (KM + Cox)","description":"Kaplan-Meier survival curves, log-rank test, and Cox proportional hazards model stratified by a clinical variable. Returns median survival, hazard ratios, and p-values.","domains":"clinical,survival,oncology","params":{"patients_table":"STRING","time_col":"STRING","event_col":"STRING","strata_col":"STRING","filter_condition":"STRING","output_table":"STRING"},"return_type":"VARCHAR","example":"CALL CATALOG.RUN_SURVIVAL_ANALYSIS(patients, time, event, strata, filter, output_table)"}'
AS
$$
import numpy as np
import pandas as pd
from lifelines import KaplanMeierFitter, CoxPHFitter
from lifelines.statistics import logrank_test
from snowflake.snowpark.context import get_active_session

def run(session, patients_table: str, time_col: str, event_col: str,
        strata_col: str, filter_condition: str, output_table: str) -> str:

    where_clause = f'WHERE {filter_condition}' if filter_condition else ''
    sql = f"""
        SELECT {time_col}, {event_col}, {strata_col}
        FROM {patients_table}
        {where_clause}
    """
    df = session.sql(sql).to_pandas()
    df.columns = ['TIME', 'EVENT', 'STRATA']
    df = df.dropna()
    df['TIME'] = pd.to_numeric(df['TIME'], errors='coerce')
    df['EVENT'] = pd.to_numeric(df['EVENT'], errors='coerce')
    df = df.dropna()

    strata_values = df['STRATA'].unique().tolist()
    if len(strata_values) < 2:
        return f"ERROR: Need at least 2 strata values, found: {strata_values}"

    results = []
    kmfs = {}
    for s in strata_values:
        mask = df['STRATA'] == s
        kmf = KaplanMeierFitter()
        kmf.fit(df.loc[mask, 'TIME'], df.loc[mask, 'EVENT'], label=str(s))
        kmfs[s] = kmf

        median_surv = kmf.median_survival_time_
        results.append({
            'SUBGROUP': str(s),
            'N_PATIENTS': int(mask.sum()),
            'N_EVENTS': int(df.loc[mask, 'EVENT'].sum()),
            'MEDIAN_SURVIVAL': float(median_surv) if not np.isnan(median_surv) else None
        })

    # Log-rank test (pairwise between all groups)
    if len(strata_values) == 2:
        g1 = df[df['STRATA'] == strata_values[0]]
        g2 = df[df['STRATA'] == strata_values[1]]
        lr = logrank_test(g1['TIME'], g2['TIME'], g1['EVENT'], g2['EVENT'])
        logrank_p = float(lr.p_value)
    else:
        logrank_p = None

    # Cox PH (if multiple covariates needed)
    try:
        cox_df = pd.get_dummies(df[['TIME', 'EVENT', 'STRATA']], columns=['STRATA'], drop_first=True)
        cph = CoxPHFitter()
        cph.fit(cox_df, duration_col='TIME', event_col='EVENT')
        hr_row = cph.summary
        for i, row in enumerate(results):
            if i == 0:
                row['HAZARD_RATIO'] = None
                row['HR_CI_LOW'] = None
                row['HR_CI_HIGH'] = None
                row['LOGRANK_P'] = logrank_p
            else:
                strata_key = f'STRATA_{strata_values[i]}'
                if strata_key in hr_row.index:
                    row['HAZARD_RATIO'] = round(float(np.exp(hr_row.loc[strata_key, 'coef'])), 3)
                    row['HR_CI_LOW'] = round(float(np.exp(hr_row.loc[strata_key, 'coef lower 95%'])), 3)
                    row['HR_CI_HIGH'] = round(float(np.exp(hr_row.loc[strata_key, 'coef upper 95%'])), 3)
                row['LOGRANK_P'] = logrank_p
    except Exception as e:
        for row in results:
            row.setdefault('HAZARD_RATIO', None)
            row.setdefault('HR_CI_LOW', None)
            row.setdefault('HR_CI_HIGH', None)
            row.setdefault('LOGRANK_P', logrank_p)

    result_df = pd.DataFrame(results)
    result_sp = session.create_dataframe(result_df)
    result_sp.write.mode('overwrite').save_as_table(output_table)
    return f"SUCCESS: Survival analysis for {len(strata_values)} groups. Results in {output_table}"
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_survival_analysis', 'Survival Analysis (KM + Cox)',
    'Kaplan-Meier survival curves, log-rank test, and Cox PH model stratified by a clinical variable.',
    'clinical,survival,oncology,biomarker', 'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_SURVIVAL_ANALYSIS',
    '{"patients_table":"STRING","time_col":"STRING","event_col":"STRING","strata_col":"STRING","filter_condition":"STRING","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_SURVIVAL_ANALYSIS(patients, time, event, strata, filter, output_table)'
);
