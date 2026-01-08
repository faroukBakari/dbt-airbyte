# Plan: Comprehensive README

## Progress Checklist

- [x] Step 1: Restructure README with Clear Sections
- [x] Step 2: Add ELT Pipeline Explanation Section
- [x] Step 3: Add Gold Layer Query Examples Section
- [x] Step 4: Add Pipeline Execution Section
- [x] Step 5: Add Visual Data Showcase Section
- [x] Step 6: Fix Airbyte Host Documentation
- [x] Step 7: Add Troubleshooting Section
- [x] Step 8: Add Table of Contents with Anchors

---

## Plan Details

**1- Restructure README with Clear Sections:** `[Risk: Low]`
- Replace existing README.md with a comprehensive, well-organized structure
- Sections: Overview, Prerequisites, Quick Start, Architecture, ELT Pipeline, Setup Guide, Running Pipeline, Visualizing Results, Troubleshooting

**2- Add ELT Pipeline Explanation Section:** `[Risk: Low]`
- Document transformation flow with data lineage
- Explain each layer: Raw → Staging → Marts → Gold

**3- Add Gold Layer Query Examples Section:** `[Risk: Low]`
- Provide copy-paste ready SQL queries for gold layer
- Include connection command

**4- Add Pipeline Execution Section:** `[Risk: Low]`
- Document `./scripts/run_pipeline.sh` usage
- Add Airflow DAG task descriptions table

**5- Add Visual Data Showcase Section:** `[Risk: Low]`
- Include shell commands to query each layer

**6- Fix Airbyte Host Documentation:** `[Risk: Low]`
- Update destination host from `n8n-postgres` to `localhost`
- Add warning callout explaining `--network host` behavior

**7- Add Troubleshooting Section:** `[Risk: Low]`
- Common issues and fixes

**8- Add Table of Contents with Anchors:** `[Risk: Low]`
- GitHub-compatible TOC at top
