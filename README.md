# 🏪 GlobalSuperstore Data Warehouse & Business Intelligence System

A full-stack **Data Engineering & BI project** — from raw OLTP data through a production-grade ETL pipeline, star schema data warehouse, SSAS OLAP cube, and multi-report Power BI dashboards.

The solution processes **51,290 sales transaction records** across **147 countries**, **1,590 unique customers**, **10,292 unique products**, and **7 global markets** spanning a four-year period (2011–2014).

---

## 🏗️ Architecture

The solution follows a five-layer DW/BI architecture where data flows from heterogeneous source systems through a staging buffer, gets transformed by an SSIS ETL engine, lands in a star schema data warehouse, and is finally consumed by OLAP and BI reporting tools.

```
┌──────────────┐    ┌─────────────┐    ┌─────────────┐    ┌──────────────┐    ┌────────────┐
│  Layer 1     │    │  Layer 2    │    │  Layer 3    │    │  Layer 4     │    │  Layer 5   │
│  Data Sources│───▶│  Staging    │───▶│  ETL (SSIS) │───▶│  Data        │───▶│  BI Layer  │
│  (OLTP)      │    │  (Buffer)   │    │  Pipeline   │    │  Warehouse   │    │  Reporting │
└──────────────┘    └─────────────┘    └─────────────┘    └──────────────┘    └────────────┘
```

| Layer | Component | Details |
|-------|-----------|---------|
| **Sources** | SQL Server DB, CSV Flat File, Excel | 3 heterogeneous source types |
| **Staging** | `GlobalSuperstore_Staging` | Raw landing zone — no transformations applied |
| **ETL** | 3 SSIS packages | Extract, transform, load pipeline |
| **Warehouse** | `GlobalSuperstore_DW` — Star Schema | FactSales + 5 dimension tables |
| **Reporting** | SSAS Cube, Power BI, Excel PivotTables | OLAP analysis & dashboards |

---

## 🗄️ Data Modelling — Star Schema

The warehouse uses a **Star Schema** — chosen for query performance, simplicity, and multi-dimensional analytical suitability. The grain is defined as **one product line item within a customer order**.

```
                         ┌────────────┐
                         │  DimDate   │
                         │ 2,557 rows │
                         └─────┬──────┘
                               │
┌──────────────────┐    ┌──────┴───────┐    ┌─────────────────┐
│   DimCustomer    │    │  FactSales   │    │   DimProduct    │
│   SCD Type 2     │────│ 51,290 rows  │────│  10,292 rows    │
└──────────────────┘    └──────┬───────┘    └─────────────────┘
                               │
                  ┌────────────┴────────────┐
                  │                         │
           ┌──────┴──────┐         ┌────────┴───────┐
           │ DimLocation │         │  DimShipMode   │
           │  5-level    │         │  16 combos     │
           │  hierarchy  │         └────────────────┘
           └─────────────┘
```

### Fact Table — FactSales

| Column | Type | Description |
|--------|------|-------------|
| `Sales` | DECIMAL | Revenue generated from the sale |
| `Quantity` | INT | Number of units sold |
| `Discount` | DECIMAL | Discount rate applied |
| `Profit` | DECIMAL | Profit or loss from the transaction |
| `ShippingCost` | DECIMAL | Cost of delivery |
| `accm_txn_create_time` | DATETIME | Accumulating fact — warehouse load timestamp |
| `accm_txn_complete_time` | DATETIME | Accumulating fact — completion timestamp (updated later) |
| `txn_process_time_hours` | FLOAT | Derived — DATEDIFF between creation and completion |

The last three columns implement the **Accumulating Snapshot Fact Table** pattern — unlike a standard transactional fact table where rows are only ever inserted, these columns allow existing rows to be updated as a business process moves through stages.

### Dimension Tables

| Table | Rows | Key Design Decision |
|-------|------|---------------------|
| `DimDate` | 2,557 | YYYYMMDD integer surrogate key; pre-populated 2010–2016 to accommodate ship dates and future loads |
| `DimCustomer` | 1,590 | **SCD Type 2** on CustomerName (full history preserved); SCD Type 1 on Segment (overwrite) |
| `DimProduct` | 10,292 | 3-level hierarchy: Category → SubCategory → ProductName |
| `DimLocation` | Unique combos | 5-level hierarchy: Market → Region → Country → State → City |
| `DimShipMode` | 16 | 4 shipping modes × 4 order priorities |

All dimension tables use **surrogate keys** as primary keys with original source IDs stored as alternate keys for traceability.

### Hierarchies

```
Product:     Category → SubCategory → ProductName
Geographic:  Market → Region → Country → State → City
Date:        Year → Quarter → MonthNumber → MonthName
```

---

## ⚙️ ETL Pipeline — SSIS

Three SSIS packages handle the complete pipeline, designed for **idempotent, automated execution** — running `GS_Load_Staging.dtsx` triggers the entire pipeline end-to-end via an Execute Package Task chain.

### `GS_Load_Staging.dtsx`

Extracts raw data from three different source types and lands it into the staging database with zero transformations. **OnPreExecute Event Handlers** TRUNCATE each staging table before every load, preventing duplicate accumulation across runs.

| Task | Source Type | Staging Target |
|------|-------------|----------------|
| Extract Orders | OLE DB Source (SQL Server) | `StgOrders` |
| Extract OrderLines | OLE DB Source (SQL Server) | `StgOrderLines` |
| Extract Customers | Flat File Source (CSV) | `StgCustomers` |
| Extract Products | Excel Source + Data Conversion | `StgProducts` |

The staging layer **decouples extraction from transformation** — protecting source systems and providing a single unified SQL Server buffer before any DW loading begins.

### `GS_Load_DW.dtsx`

Reads from staging and applies all transformations before loading the data warehouse. Dimensions are loaded sequentially before the fact table to guarantee all surrogate keys exist at lookup time.

| Transformation | SSIS Component | Purpose |
|----------------|----------------|---------|
| Combine Orders + OrderLines | Sort → **Merge Join** (on OrderID) | Reconstruct full transaction record |
| Resolve date surrogate keys | **Lookup** → DimDate | Map OrderDate and ShipDate to DateKey |
| Resolve customer surrogate keys | **Lookup** → DimCustomer | Map CustomerID to CustomerKey |
| Resolve product surrogate keys | Data Conversion → **Lookup** → DimProduct | Map ProductID to ProductKey |
| Resolve location surrogate keys | SELECT DISTINCT → **Lookup** → DimLocation | Map City-Country to LocationKey |
| Resolve ship mode keys | **Lookup** → DimShipMode | Map ShipMode + OrderPriority to ShipModeKey |
| Customer history tracking | **SCD Wizard** — Type 2 + Type 1 | Insert new row on name change; overwrite segment |
| Dimension upserts | **OLE DB Command** + stored procedures | Idempotent inserts — check before inserting |
| Data quality routing | **Conditional Split** | Route invalid records to quarantine table |
| Timestamp stamping | **Derived Column** → `GETDATE()` | Populate `accm_txn_create_time` on insert |

### `Update_Fact_Completions.dtsx`

A dedicated, independently schedulable package that implements the accumulating snapshot update pattern. Reads `transaction_completions.csv` (an external system feed) and updates FactSales rows in place.

```sql
UPDATE FactSales
SET accm_txn_complete_time = ?,
    txn_process_time_hours = DATEDIFF(HOUR, accm_txn_create_time, ?)
WHERE RowID = ?
```

A **Lookup transformation** validates each incoming `txn_id` against `RowID` in FactSales before attempting any update — preventing silent failures for unmatched records. Processing hours are calculated inline in SQL rather than in SSIS, keeping transformation logic inside the database where it is easier to audit and verify.

---

## 🧊 OLAP Cube — SSAS

An **Analysis Services Multidimensional** project (`GlobalSuperstore_Cube`) was built and deployed on top of the data warehouse:

- **Measure group:** FactSales — Sales, Quantity, Discount, Profit, ShippingCost
- **Dimensions:** Dim Customer, Dim Date, Dim Location, Dim Product, Dim Ship Mode — all with Regular relationships to the measure group
- **Hierarchies defined:** Product Category (3 levels), Geography (5 levels), Date (4 levels)
- **Connected to:** Excel PivotTables and Power BI for live multi-dimensional analysis

### OLAP Operations Demonstrated in Excel PivotTables

| Operation | What It Does | How It Was Applied |
|-----------|-------------|-------------------|
| **Roll-up** | Aggregate from detail to summary | Collapsed Geography: City → State → Country → Region → Market (5 steps) |
| **Drill-down** | Navigate from summary to detail | Expanded Market → Region → Country → State → City |
| **Slice** | Filter on a single dimension value | Isolated US market — Sales by Product Category |
| **Dice** | Filter on multiple dimensions simultaneously | US + Technology; then EU + Furniture |
| **Pivot** | Rotate axes | Swapped Category (rows) ↔ Year (columns) |

---

## 📈 Power BI Reports

Four reports built in `PowerBIReports.pbix` connected directly to the data warehouse:

| Report | Visuals & Features |
|--------|--------------------|
| **Sales Performance Matrix** | Matrix visual — Sales, Profit, Quantity by Category × Year (2011–2014) with grand totals |
| **Sales Insights Dashboard** | Cascading slicers (Country → Market → Category); Sales by Category bar chart; Profit by Customer Segment donut; Sales Trend by Year line chart; Shipping Cost by Ship Mode bar chart |
| **Hierarchical Sales Analysis** | Clickable drill-down bar chart (Profit by Geography); Sales by Time Period drill (Month → Quarter); Quantity by Sub Category; Year slicer |
| **Sales Summary + Order Details** | Right-click drill-through from category summary to full order-level detail table with all measures |

---

## 🛠️ Technology Stack

| Category | Tools |
|----------|-------|
| **Database** | SQL Server 2022 (T-SQL) |
| **ETL** | SQL Server Integration Services (SSIS) — Visual Studio Data Tools |
| **OLAP** | SQL Server Analysis Services (SSAS) — Multidimensional |
| **BI & Reporting** | Power BI, Microsoft Excel PivotTables |
| **Data Modelling** | Star Schema, SCD Type 2, Accumulating Snapshot Fact Table |
| **Source Formats** | SQL Server DB, CSV Flat File, Microsoft Excel (.xlsx) |

---

## 📁 Repository Structure

```
Global-Superstore-Data-Warehouse/
│
├── GlobalSuperstore_ETL/               ← SSIS ETL project
│   ├── GS_Load_Staging.dtsx            ← Package 1: Extract all sources → Staging DB
│   ├── GS_Load_DW.dtsx                 ← Package 2: Transform + Load dimensions + FactSales
│   ├── Update_Fact_Completions.dtsx    ← Package 3: Update accumulating fact timestamps
│   ├── Project.params                  ← Project-level parameters
│   └── GlobalSuperstore_ETL.dtproj     ← SSIS project file
│
├── GlobalSuperstore_Cube/              ← SSAS OLAP cube project
│   ├── Global Superstore DW.cube       ← Cube definition
│   ├── Global Superstore DW.ds         ← Data source
│   ├── Global Superstore DW.dsv        ← Data source view
│   ├── Dim Customer.dim                ← Customer dimension (SCD Type 2)
│   ├── Dim Date.dim                    ← Date dimension
│   ├── Dim Location.dim                ← Location dimension (5-level hierarchy)
│   ├── Dim Product.dim                 ← Product dimension (3-level hierarchy)
│   ├── Dim Ship Mode.dim               ← Ship mode dimension
│   └── GlobalSuperstore_Cube.dwproj    ← SSAS project file
│
├── DataWarehouse/                      ← Data warehouse project files
│
├── create_dw_schema.sql                ← DDL: Star schema table creation scripts
├── Preparation_of_data_Sources.sql     ← SQL: Source DB setup and data preparation
├── Global_Superstore.csv               ← Source data: raw transaction flat file
├── Product_Catalog.xlsx                ← Source data: product catalog (10,292 products)
├── transaction_completions.csv         ← Source data: accumulating fact completion feed
└── PowerBIReports.pbix                 ← Power BI report file (4 reports)
```
