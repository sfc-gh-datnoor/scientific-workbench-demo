# Snowflake HCLS Industry Solutions

Disclaimer: This application is not part of the Snowflake Service and is governed by the terms in LICENSE, unless expressly agreed to in writing. You use this application at your own risk, and Snowflake has no obligation to support your use of this application. [Learn more](./LEGAL.md)

**HCLS: Healthcare & Life Sciences**

End-to-end solution accelerators for the Healthcare & Life Sciences industry vertical, built on Snowflake and Cortex Code, showcasing Cortex AI, Snowflake ML, and the modern data platform.

This repository is part of the [Snowflake Industry Solutions](https://github.com/Snowflake-Labs/sf-solutions) catalogue — a central hub for discovering, installing, and managing all industry solution accelerators across verticals.

## Requirements

- Snowflake Trial account
- Enterprise edition+
- Python 3.12+
- [uv](https://docs.astral.sh/uv/) (Python package manager)

---

## Solution Catalog

| # | Solution | Industry | Directory | Key Snowflake Features | Status |
|---|----------|----------|-----------|----------------------|--------|
| 1 | **Clinical Quality and Patient Safety Agent** | Healthcare | `solutions/clinical-quality-agent/` | Snowflake Intelligence, Cortex Agent, Cortex Analyst, Cortex Search (PubMed), Semantic Model | ✅ Done |
| 2 | **Medical Device Streaming Platform** | Healthcare | `solutions/medical-device-streaming/` | Snowpipe Streaming (High-Performance), PIPE Objects, ASOF Joins, VARIANT Data, Flattened Views | ✅ Done |
| 3 | **Scientific Workbench for Life Sciences R&D** | Life Sciences | `solutions/scientific-workbench/` | Cortex Agents (Discovery Agent with Claude Sonnet 5.5), Multi-Agent Toolsets & Router, NVIDIA BioNeMo NIMs (10 GPU tools), Cortex Analyst Semantic Views (4), Snowflake App Runtime (Next.js), Notebooks | ✅ Done |

---

## Quick Install (via Cortex Code)

> **TBA** — Plugin install command will be available after public release.

```
$sf-solutions                              # List all available solutions
$sf-solutions hcls                         # Filter by HCLS industry
$sf-solutions:clinical-quality-agent       # Install a solution
$sf-solutions:clinical-quality-agent teardown  # Remove a solution
```

---

## Getting Started

Each solution is self-contained in its own directory. There are two types:

### Script Type

```
solutions/<solution-name>/
├── manifest.json      # Solution metadata (type: "script")
├── README.md          # Overview, architecture, prerequisites
├── NEXT_ACTIONS.md    # Post-install verification steps and example queries
├── scripts/           # SQL setup and teardown scripts
└── streamlit/         # Streamlit app (if applicable)
```

### Plugin Type

Solutions that install a Cortex Code plugin with skills, agents, and optionally Snowflake objects.

```
solutions/<solution-name>/
├── manifest.json          # Solution metadata (type: "plugin")
├── README.md              # Overview, usage
├── plugins/cortex-code/   # CoCo plugin directory
│   ├── .cortex-plugin/
│   │   └── plugin.json
│   └── skills/
│       └── ...
└── scripts/               # Optional SQL scripts
```

---

## Related Resources

### Web Pages

- [Snowflake ML](https://www.snowflake.com/en/data-cloud/snowflake-ml/) - Integrated set of capabilities for development, MLOps and inference leading with agentic ML
- [Snowflake Notebooks](https://www.snowflake.com/en/data-cloud/notebooks/) - Jupyter-based notebooks in Snowflake Workspaces
- [Cortex Code](https://www.snowflake.com/en/data-cloud/cortex/cortex-code/) - Snowflake's AI native coding agent that boosts ML productivity

### Technical Documentation

- [Cortex Code Documentation](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code) - Getting started with Cortex Code
- [Cortex Code in Snowsight](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-snowsight) - Browser-based experience
- [Cortex Code CLI](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli) - Command-line experience
- [Snowflake ML Documentation](https://docs.snowflake.com/en/developer-guide/snowflake-ml/overview) - Official Snowflake ML developer guide
- [Snowflake ML Quickstart](https://quickstarts.snowflake.com/guide/getting-started-with-snowflake-ml/) - Hands-on guides to get started with Snowflake ML
