# dbt Production Tools & Resources (2025)

Curated reference for tools, packages, and community resources mentioned in the production playbook.

---

## Official dbt Labs Tools

### audit_helper
- **Purpose**: Audit data before/after refactoring to verify outputs match
- **Use case**: Migrating stored procedures to dbt, renaming models, changing logic
- **Syntax**: `{{ audit_helper.compare_relations(...) }}`
- **Link**: https://github.com/dbt-labs/dbt-audit-helper
- **Cost**: Free

### dbt Project Evaluator
- **Purpose**: Automated best-practice audit; finds orphaned models, missing tests, documentation gaps
- **Output**: Fact tables with violations (undocumented models, unused models, schema drift)
- **How**: Install as package; runs in `dbt build` producing test results
- **Link**: https://github.com/dbt-labs/dbt-project-evaluator
- **Cost**: Free

### dbt-autofix
- **Purpose**: Auto-migrate deprecated configs when upgrading dbt versions
- **Use case**: dbt 1.10+ introduced YAML deprecation warnings; dbt-autofix fixes them automatically
- **Commands**: `dbt-autofix scan`, `dbt-autofix apply --behavior-change`
- **Link**: https://github.com/dbt-labs/dbt-autofix
- **Cost**: Free, available in dbt Studio and CLI

### dbt-meshify
- **Purpose**: Automate splitting a monolithic dbt project into domain-specific projects (Mesh)
- **Workflow**: Identifies domain boundaries, creates new project folders, configures cross-project refs
- **Link**: https://github.com/dbt-labs/dbt-meshify
- **Cost**: Free

### dbt-loom (Open-Source Mesh)
- **Purpose**: Enable cross-project refs in dbt Core (without dbt Cloud Enterprise)
- **Note**: Alternative to dbt Cloud Mesh for teams self-hosting dbt
- **Link**: https://github.com/garyblake/dbt-loom
- **Cost**: Free

---

## Community Tools & Packages

### Recce (Code Review for dbt)
- **Purpose**: Zero-config PR impact analysis; shows changed models + downstream affected models
- **Output**: Data diffs, row count changes, lineage visualization
- **Integration**: GitHub Actions, dbt Cloud UI
- **Link**: https://www.getrecce.io/ (open-source)
- **Cost**: Free OSS, paid cloud version available

### Datafold
- **Purpose**: Enterprise code review for data; includes data diffs, lineage, test insights
- **Features**: PR impact assessment, query diff, data profiling
- **Link**: https://www.datafold.com/
- **Cost**: Paid (mid-market: ~$5-10K/year)

### PipeRider
- **Purpose**: Open-source data profiling + code review for dbt PRs
- **Features**: Profile data before/after, lineage impact, zero config
- **Link**: https://github.com/inquirelabs/piperider
- **Cost**: Free (open-source)

### dbt Project Evaluator (Community Extensions)
- **phData evaluator**: Extended checks beyond dbt Labs default
- **Link**: https://github.com/phdata/dbt-project-evaluator
- **Cost**: Free

### dbt-utils (Foundational Macros)
- **Includes**: `surrogate_key`, `get_column_values`, `not_null_proportion`, `star` expansion
- **Use case**: Standard utilities for every dbt project
- **Link**: https://github.com/dbt-labs/dbt-utils
- **Cost**: Free

### dbt-expectations
- **Purpose**: 60+ data quality tests (ranges, patterns, distributions, anomaly detection)
- **Examples**: `expect_column_values_to_be_in_set`, `expect_row_values_to_have_data_for_every_n_timespan`
- **Link**: https://github.com/calogica/dbt-expectations
- **Cost**: Free

### Elementary
- **Purpose**: dbt observability platform; anomaly detection, schema drift, test insights
- **Features**: Statistical anomaly detection, Slack alerts, lineage tracking
- **Link**: https://www.elementary-data.com/ (open-source + cloud)
- **Cost**: Free OSS, paid cloud (~$1-2K/month for mid-market)

---

## External Tools (Not dbt-specific, but essential)

### SQLFluff (SQL Linting)
- **Purpose**: Lint + format SQL; catches style violations before they ship
- **Integration**: Pre-commit hooks, CI/CD
- **Link**: https://www.sqlfluff.com/
- **Cost**: Free

### Metricflow (dbt's Semantic Layer)
- **Purpose**: Define metrics once, query consistently across BI tools
- **Note**: dbt Labs' official semantic modeling layer
- **Link**: https://docs.getdbt.com/docs/use-dbt-semantic-layer
- **Cost**: Free (OSS), included in dbt Cloud (paid)

### dbt Cloud (Hosted dbt)
- **Features**: Slim CI, state-aware scheduling, dbt Mesh (Enterprise), IDE
- **Cost**: $300+/month (3 developers)
- **When to use**: Teams >5, complex orchestration, need Mesh

### Dagster + Dagster-dbt Integration
- **Purpose**: Orchestrate dbt as Directed Acyclic Graphs (DAGs) with assets
- **Advantage over Airflow**: Asset-centric (vs task-centric); better UX for data teams
- **Link**: https://docs.dagster.io/integrations/dbt
- **Cost**: Free (open-source) or paid cloud

### Snowflake / Databricks Query Profiler
- **Snowflake**: `select * from snowflake.account_usage.query_history` + query plan
- **Databricks**: Query History UI + SQL Editor
- **Purpose**: Diagnose slow queries, check execution time breakdown
- **Cost**: Included with warehouse subscription

---

## Observability & Monitoring

### Monte Carlo Data
- **Purpose**: Enterprise data observability; automated anomaly detection across entire warehouse
- **Features**: ML-driven anomaly detection, data lineage, incident response
- **Link**: https://www.montecarlodata.com/
- **Cost**: Paid (~$100K+/year for enterprise)

### Metaplane
- **Purpose**: Mid-market data observability; automated freshness + volume anomalies
- **Features**: Simple setup, Slack alerts, cost-efficient
- **Link**: https://www.metaplane.com/
- **Cost**: Paid (~$5-10K/month)

### dbt artifacts (manifest.json, run_results.json)
- **Purpose**: Local inspection of dbt metadata without external tools
- **Use case**: Script-based monitoring, in-house dashboards
- **Free**: Built into every dbt run

---

## Community Resources

### dbt Discourse
- **Purpose**: Q&A forum, best practices discussions
- **Link**: https://discourse.getdbt.com/
- **Activity**: ~500K posts, very active

### Reddit r/dataengineering
- **Purpose**: War stories, career advice, tool discussions
- **Sentiment**: Honest takes on dbt scaling, incident postmortems
- **Link**: https://www.reddit.com/r/dataengineering/

### Coalesce Conference
- **Purpose**: Annual dbt conference (Oct-Nov)
- **Content**: Talks on scaling, production patterns, new features
- **Link**: https://www.coalesce.getdbt.com/
- **Cost**: Paid (in-person) or free on-demand videos

### dbt Labs Blog
- **Purpose**: Announcements, best practices, case studies
- **Link**: https://www.getdbt.com/blog/
- **Frequency**: Weekly posts

### Analytics Engineering Slack Communities
- **dbt Community Slack**: https://www.getdbt.com/community
- **Analytics Engineering Insider**: Paid community (~$200/year)
- **Benefit**: Direct access to dbt Labs team, exclusive content

---

## Blogs & Individual Resources

### Blogs with Production Patterns

| Author/Org | Blog | Topic |
|-----------|------|-------|
| **phData** | https://www.phdata.io/blog/ | dbt best practices, scaling patterns |
| **Stellans** | https://stellans.io/ | dbt conventions, project structure |
| **Astrafy** | https://www.astrafy.io/blog | dbt in the wild, case studies |
| **Yuval Moskovitch** | https://www.linkedin.com/in/yuval-moskovitch/ | dbt optimization, performance |
| **Abhishek Kumar** | Medium: "Tech with Abhishek" | Performance, versioning, scaling |
| **Datafold Blog** | https://www.datafold.com/blog | Code review, testing, data quality |
| **Elementary Blog** | https://www.elementary-data.com/blog | Observability, incident response |

---

## Configuration Templates

### Pre-commit Hooks (SQLFluff + dbt)
```bash
# Install
pip install pre-commit sqlfluff dbt-checkpoint

# Create .pre-commit-config.yaml
repos:
  - repo: https://github.com/dbt-checkpoint/dbt-checkpoint
    rev: 0.8.0
    hooks:
      - id: dbt-parse
      - id: dbt-deps
      - id: dbt-docs-generate
      - id: dbt-yamllint

  - repo: https://github.com/sqlfluff/sqlfluff
    rev: 2.1.0
    hooks:
      - id: sqlfluff-lint
        args: [--dialect, snowflake]
      - id: sqlfluff-fix
        args: [--dialect, snowflake]
```

### GitHub Actions: Slim CI
```yaml
name: dbt slim CI

on:
  pull_request:
    paths:
      - 'models/**'
      - 'dbt_project.yml'

jobs:
  dbt-slim:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0

      - name: Set up dbt
        run: pip install dbt-core dbt-snowflake

      - name: dbt parse
        run: dbt parse

      - name: dbt build (slim)
        run: dbt build --select state:modified+ --state ./manifest/ --defer
```

### dbt_project.yml: Defaults
```yaml
name: 'my_analytics'
version: '1.0.0'

profile: 'default'

model-paths: ["models"]
test-paths: ["tests"]
data-paths: ["data"]

target-path: "target"
clean-targets:
  - "target"
  - "dbt_packages"

models:
  my_analytics:
    staging:
      materialized: view
      schema: staging
    intermediate:
      materialized: ephemeral
      schema: staging
    marts:
      materialized: table
      schema: analytics
      +pre-hook: "{{ log('Building ' ~ this.name, info=true) }}"
      +test_selector: "selector.yml:critical"

tests:
  my_analytics:
    +store_failures: true
    +severity: warn  # Change to error for critical paths

vars:
  dbt_project_evaluator:
    table_rename_threshold: 5
    execute_project_evaluator: true
```

---

## Recommended Reading Order

1. **Start here**: `docs/dbt-state-of-the-art-2025.md` (foundation)
2. **Production patterns**: `docs/dbt-production-playbook-2025.md` (detailed)
3. **Quick lookup**: `docs/PRODUCTION-QUICK-REFERENCE.md` (checklists)
4. **Official dbt docs**: https://docs.getdbt.com (reference)
5. **Coalesce talks**: YouTube search "Coalesce 2024" for talks on your specific pain point

---

## Tools Selection Matrix

### By Organization Size

| Size | Observability | Code Review | Orchestration |
|------|---------------|-------------|---------------|
| **1-5 people** | Elementary OSS | None (manual review) | dbt Cloud free or Airflow |
| **5-15** | Elementary OSS + Slack | Recce (free) | Airflow + Cosmos or dbt Cloud |
| **15-50** | Metaplane | Datafold or Recce | Dagster or Airflow |
| **50+** | Monte Carlo | Datafold | Dagster + dbt Cloud Enterprise |

### By Pain Point

| Problem | Tool |
|---------|------|
| "I don't know if my data is fresh" | Elementary anomaly detection + source freshness |
| "PRs are slow to review, hard to assess impact" | Recce + SQLFluff |
| "Models are undocumented" | dbt Project Evaluator + dbt-osmosis |
| "We have 1000+ models, can't manage as monolith" | dbt Mesh + dbt Cloud Enterprise |
| "Queries are slow, warehouse bills are huge" | Snowflake query profiler + intermediate table strategy |
| "Tests keep breaking, alert fatigue" | dbt Project Evaluator to audit test coverage |

---

## Cost Estimates (2025)

### Free Stack
- dbt Core + Snowflake/Redshift/BigQuery
- SQLFluff + pre-commit
- dbt Project Evaluator
- Elementary OSS
- dbt-utils + dbt-expectations
- **Total**: $0 (except warehouse costs)

### Startup Stack ($10-20K/year)
- dbt Cloud (3 developers): $300/mo = $3.6K
- Metaplane: $5K/year
- Recce (free)
- **Total**: ~$8.6K

### Mid-Market Stack ($50K+/year)
- dbt Cloud (10+ developers): $3K+/mo = $36K+/year
- Datafold: $10K/year
- Metaplane: $5K/year
- **Total**: $50K+/year

### Enterprise Stack ($150K+/year)
- dbt Cloud Enterprise (includes Mesh): $10K+/mo
- Monte Carlo: $100K+/year
- Semantic Layer API: included in dbt Cloud Enterprise
- **Total**: $200K+/year

---

## Staying Current

- **Subscribe**: dbt Labs newsletter (weekly)
- **Follow**: @dbtlabs Twitter for announcements
- **Watch**: Coalesce talks (Oct-Nov) + on-demand videos
- **Join**: dbt Community Slack for peer learning
- **Read**: Discourse discussions for real-world scenarios
