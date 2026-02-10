# Data Quality Insights (DQI) – Oracle APEX Region Plugin

**Data Quality Insights (DQI)** is a professional **Oracle APEX Region Plug-in** that provides real-time, visual data quality profiling for any SQL query.

It helps APEX developers, analysts, and architects quickly identify **nulls, duplicates, and invalid values** directly inside their applications — without exporting data or building custom reports.

---

## ✨ Features

- 🔍 **Query-based profiling** (works with any SQL query)
- 📊 **Column-level quality metrics**
  - Null %
  - Duplicate rows %
  - Invalid values % (rule-based)
- 🧮 **Accurate duplicate detection**
  - Counts rows involved in duplication (not just extra rows)
- 🧾 **Rule-based validation**
  - Regex-driven invalid detection per column
- 🚦 **Clear quality status**
  - Good / Warning / Issue
- ⚡ **Performance-safe**
  - Row sampling support
  - Single SQL execution per run
- 🎨 **Modern, clean UI**
  - Card-based dashboard
  - Lightweight CSS (no frameworks)

---

## 📦 Plugin Type

- **Oracle APEX Region Plug-in**
- Compatible with **Oracle APEX**
- Designed for **Oracle Database 19c+** (26ai-ready)

---

## 🏗 Architecture Overview

### Backend
- PL/SQL Region Render Procedure
- PL/SQL AJAX Procedure
- Dynamic SQL with bind variables
- JSON response using `APEX_JSON`

### Frontend
- JavaScript via `apex.server.plugin`
- Responsive HTML rendering
- Minimal, enterprise-grade CSS

### Configuration
- Uses **Custom Attributes (Static IDs)** in Oracle APEX
- No dependency on `attribute_01` ordering
- Fully declarative setup

---

## 🚀 Installation

### 1. Import the Plug-in
1. Go to **Shared Components → Plug-ins**
2. Click **Import**
3. Upload the plug-in SQL file
4. Install the plug-in

### 2. Upload Plugin Files
Ensure the following files are attached to the plug-in:
- `dqi.js`
- `dqi.css`
---

### 3. Create Package in Database
Ensure the following files are attached to the plug-in:
- `dqi_apex_plugin.spc`
- `dqi_apex_plugin.bdy`
---

## ⚙️ Configuration (Custom Attributes)

| Label | Static ID | Type | Description |
|-----|---------|------|------------|
| SQL Query | `sql_query` | Textarea | SQL query to profile |
| Columns (CSV) | `columns_csv` | Text | Comma-separated column aliases |
| Sample Rows | `sample_rows` | Number | Max rows to sample |
| Warn Null % | `warn_null` | Number | Warning threshold |
| Error Null % | `error_null` | Number | Error threshold |
| Warn Duplicate % | `warn_duplicate` | Number | Warning threshold |
| Error Duplicate % | `error_duplicate` | Number | Error threshold |
| Warn Invalid % | `warn_invalid` | Number | Warning threshold |
| Error Invalid % | `error_invalid` | Number | Error threshold |
| Regex Rules JSON | `regex_rules_json` | Textarea | Validation rules |

---

## 🧪 Example Usage

### Example SQL Query

```sql
select
  'user'||level||'@mail.com' as email,
  '0300-123456'||level as phone,
  level as order_id,
  case when level in (4,6) then null else 'A-'||level end as test_column
from dual
connect by level <= 10
