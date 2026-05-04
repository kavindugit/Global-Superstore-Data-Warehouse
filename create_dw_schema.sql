USE GlobalSuperstore_DW;
GO

-- ============================================================
-- DROP tables if they exist (safe re-run)
-- Must drop FactSales first because it references dimensions
-- ============================================================
IF OBJECT_ID('dbo.FactSales',    'U') IS NOT NULL DROP TABLE dbo.FactSales;
IF OBJECT_ID('dbo.DimCustomer',  'U') IS NOT NULL DROP TABLE dbo.DimCustomer;
IF OBJECT_ID('dbo.DimProduct',   'U') IS NOT NULL DROP TABLE dbo.DimProduct;
IF OBJECT_ID('dbo.DimLocation',  'U') IS NOT NULL DROP TABLE dbo.DimLocation;
IF OBJECT_ID('dbo.DimShipMode',  'U') IS NOT NULL DROP TABLE dbo.DimShipMode;
IF OBJECT_ID('dbo.DimDate',      'U') IS NOT NULL DROP TABLE dbo.DimDate;
GO

-- ============================================================
-- TABLE 1: DimDate
-- Special case surrogate key — uses YYYYMMDD integer format
-- e.g. 31 July 2012 = DateKey 20120731
-- Pre-populated for years 2010 to 2016
-- ============================================================
CREATE TABLE dbo.DimDate (
    DateKey         INT             NOT NULL,   -- surrogate key e.g. 20120731
    FullDate        DATE            NOT NULL,   -- actual date value
    DayOfMonth      INT             NOT NULL,   -- 1 to 31
    DayName         VARCHAR(10)     NOT NULL,   -- Monday, Tuesday etc
    DayOfWeek       INT             NOT NULL,   -- 1=Sunday to 7=Saturday
    WeekOfYear      INT             NOT NULL,   -- 1 to 52
    MonthNumber     INT             NOT NULL,   -- 1 to 12
    MonthName       VARCHAR(10)     NOT NULL,   -- January, February etc
    Quarter         INT             NOT NULL,   -- 1 to 4
    QuarterName     VARCHAR(6)      NOT NULL,   -- Q1, Q2, Q3, Q4
    Year            INT             NOT NULL,   -- e.g. 2012
    IsWeekend       BIT             NOT NULL,   -- 1=weekend, 0=weekday

    CONSTRAINT PK_DimDate PRIMARY KEY (DateKey)
);
GO

-- Populate DimDate for years 2010 to 2016
DECLARE @StartDate DATE = '2010-01-01';
DECLARE @EndDate   DATE = '2016-12-31';
DECLARE @Date      DATE = @StartDate;

WHILE @Date <= @EndDate
BEGIN
    INSERT INTO dbo.DimDate (
        DateKey, FullDate, DayOfMonth, DayName, DayOfWeek,
        WeekOfYear, MonthNumber, MonthName, Quarter, QuarterName,
        Year, IsWeekend
    )
    VALUES (
        CAST(CONVERT(VARCHAR(8), @Date, 112) AS INT),
        @Date,
        DAY(@Date),
        DATENAME(WEEKDAY, @Date),
        DATEPART(WEEKDAY, @Date),
        DATEPART(WEEK, @Date),
        MONTH(@Date),
        DATENAME(MONTH, @Date),
        DATEPART(QUARTER, @Date),
        'Q' + CAST(DATEPART(QUARTER, @Date) AS VARCHAR(1)),
        YEAR(@Date),
        CASE WHEN DATEPART(WEEKDAY, @Date) IN (1,7) THEN 1 ELSE 0 END
    );
    SET @Date = DATEADD(DAY, 1, @Date);
END
GO

-- ============================================================
-- TABLE 2: DimShipMode
-- Small dimension — shipping method and order priority
-- ============================================================
CREATE TABLE dbo.DimShipMode (
    ShipModeKey     INT             NOT NULL IDENTITY(1,1),
    ShipMode        VARCHAR(20)     NOT NULL,   -- Same Day, First Class etc
    OrderPriority   VARCHAR(15)     NOT NULL,   -- Critical, High, Medium, Low

    CONSTRAINT PK_DimShipMode PRIMARY KEY (ShipModeKey)
);
GO

-- ============================================================
-- TABLE 3: DimLocation
-- Geographic dimension with 5-level hierarchy:
-- Market → Region → Country → State → City
-- ============================================================
CREATE TABLE dbo.DimLocation (
    LocationKey     INT             NOT NULL IDENTITY(1,1),
    City            NVARCHAR(100)   NOT NULL,
    State           NVARCHAR(100)   NOT NULL,
    Country         NVARCHAR(100)   NOT NULL,
    PostalCode      VARCHAR(20)     NULL,       -- nullable, many rows have none
    Market          VARCHAR(10)     NOT NULL,   -- US, EU, APAC, LATAM etc
    Region          VARCHAR(30)     NOT NULL,   -- East, West, Central etc

    CONSTRAINT PK_DimLocation PRIMARY KEY (LocationKey)
);
GO

-- ============================================================
-- TABLE 4: DimProduct
-- Product dimension with 3-level hierarchy:
-- Category → SubCategory → ProductName
-- ============================================================
CREATE TABLE dbo.DimProduct (
    ProductKey          INT             NOT NULL IDENTITY(1,1),
    AlternateProductID  NVARCHAR(20)     NOT NULL,   -- natural key from source
    ProductName         NVARCHAR(200)   NOT NULL,
    Category            NVARCHAR(20)     NOT NULL,   -- Furniture, Technology, Office Supplies
    SubCategory         NVARCHAR(20)     NOT NULL,   -- Chairs, Phones, Paper etc

    CONSTRAINT PK_DimProduct PRIMARY KEY (ProductKey)
);
GO

-- ============================================================
-- TABLE 5: DimCustomer
-- SCD Type 2 dimension — tracks history of segment changes
-- StartDate and EndDate identify which version is current
-- IsCurrent = 1 means this is the latest record
-- ============================================================
CREATE TABLE dbo.DimCustomer (
    CustomerKey         INT             NOT NULL IDENTITY(1,1),
    AlternateCustomerID NVARCHAR(10)     NOT NULL,   -- natural key 
    CustomerName        NVARCHAR(100)   NOT NULL,   -- Type 2: new row if changes
    Segment             NVARCHAR(15)     NOT NULL,   -- Type 1: overwrite if changes
    StartDate           DATETIME        NULL,       -- when this version became active
    EndDate             DATETIME        NULL,       -- when this version expired (NULL = current)
    IsCurrent           BIT             NOT NULL DEFAULT 1, -- 1=current, 0=expired

    CONSTRAINT PK_DimCustomer PRIMARY KEY (CustomerKey)
);
GO

-- ============================================================
-- TABLE 6: FactSales
-- Central fact table — one row per order line (51,290 rows)
-- Grain: one product line within one order
-- Natural key: RowID
-- Measures: Sales, Quantity, Discount, Profit, ShippingCost
-- Accumulating fact columns added for Task 6
-- ============================================================





CREATE TABLE dbo.FactSales (
    SalesKey                INT             NOT NULL IDENTITY(1,1),
    RowID                   INT             NOT NULL,
    -- Foreign keys to dimension tables (surrogate keys)
    DateKey                 INT             NOT NULL,   -- FK to DimDate (OrderDate)
    ShipDateKey             INT             NOT NULL,   -- FK to DimDate (ShipDate)
    CustomerKey             INT             NOT NULL,   -- FK to DimCustomer
    ProductKey              INT             NOT NULL,   -- FK to DimProduct
    LocationKey             INT             NOT NULL,   -- FK to DimLocation
    ShipModeKey             INT             NOT NULL,   -- FK to DimShipMode

    OrderID                 VARCHAR(20)     NOT NULL,
    Sales                   DECIMAL(12,4)   NOT NULL,
    Quantity                INT             NOT NULL,
    Discount                DECIMAL(5,4)    NOT NULL,
    Profit                  DECIMAL(12,4)   NOT NULL,
    ShippingCost            DECIMAL(12,4)   NOT NULL,


    CONSTRAINT PK_FactSales PRIMARY KEY (SalesKey),
    -- Foreign key constraints
    CONSTRAINT FK_Fact_Date     FOREIGN KEY (DateKey)     REFERENCES dbo.DimDate(DateKey),
    CONSTRAINT FK_Fact_ShipDate FOREIGN KEY (ShipDateKey) REFERENCES dbo.DimDate(DateKey),
    CONSTRAINT FK_Fact_Customer FOREIGN KEY (CustomerKey) REFERENCES dbo.DimCustomer(CustomerKey),
    CONSTRAINT FK_Fact_Product  FOREIGN KEY (ProductKey)  REFERENCES dbo.DimProduct(ProductKey),
    CONSTRAINT FK_Fact_Location FOREIGN KEY (LocationKey) REFERENCES dbo.DimLocation(LocationKey),
    CONSTRAINT FK_Fact_ShipMode FOREIGN KEY (ShipModeKey) REFERENCES dbo.DimShipMode(ShipModeKey)
);
GO







USE GlobalSuperstore_DW;


ALTER TABLE dbo.FactSales
ADD
    accm_txn_create_time    DATETIME    NULL,
    accm_txn_complete_time  DATETIME    NULL,
    txn_process_time_hours  FLOAT       NULL;
GO


SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'FactSales'
AND COLUMN_NAME IN (
    'accm_txn_create_time',
    'accm_txn_complete_time',
    'txn_process_time_hours'
);








truncate table factsales;


ALTER TABLE dbo.FactSales 
ALTER COLUMN Profit DECIMAL(18,4) NOT NULL;

ALTER TABLE dbo.FactSales 
ALTER COLUMN Sales DECIMAL(18,4) NOT NULL;



-- ============================================================
-- VERIFY: Check all tables were created
-- ============================================================
SELECT
    t.TABLE_NAME,
    COUNT(c.COLUMN_NAME) AS ColumnCount
FROM INFORMATION_SCHEMA.TABLES t
JOIN INFORMATION_SCHEMA.COLUMNS c ON t.TABLE_NAME = c.TABLE_NAME
WHERE t.TABLE_SCHEMA = 'dbo'
AND t.TABLE_TYPE = 'BASE TABLE'
GROUP BY t.TABLE_NAME
ORDER BY t.TABLE_NAME;

-- Verify DimDate was populated
SELECT
    COUNT(*)        AS TotalDays,
    MIN(FullDate)   AS FirstDate,
    MAX(FullDate)   AS LastDate
FROM dbo.DimDate;
GO


select * from dbo.dimdate;



SELECT RowID, OrderID, Profit 
FROM dbo.StgOrderLines
WHERE ABS(Profit) >= 100000000 -- Values with 9 or more digits before the decimal
   OR Profit IS NULL;






   CREATE TABLE dbo.FactSales_Quarantine (
    RowID INT NULL,
    OrderID VARCHAR(20) NULL,
    ProductID VARCHAR(20) NULL,
    CustomerKey INT NULL,
    Sales NUMERIC(18,4) NULL,
    Profit NUMERIC(18,4) NULL, -- This allows the NULLs to land safely
    QuarantineDate DATETIME DEFAULT GETDATE(),
    RejectionReason NVARCHAR(100) DEFAULT 'Missing Profit Data'
);


select * from dbo.FactSales_Quarantine;
select * from dbo.FactSales;

*/




SELECT TOP 100 OrderID, Profit, accm_txn_create_time 
FROM dbo.FactSales;




use GlobalSuperstore_DW


SELECT 'DimCustomer' as Dim, COUNT(*) as Count FROM dbo.DimCustomer
UNION ALL
SELECT 'DimProduct', COUNT(*) FROM dbo.DimProduct
UNION ALL
SELECT 'DimLocation', COUNT(*) FROM dbo.DimLocation
UNION ALL
SELECT 'DimShipMode', COUNT(*) FROM dbo.DimShipMode
UNION ALL
SELECT 'DimDate', COUNT(*) FROM dbo.DimDate;



SELECT 'FactSales (Clean Data)' AS TableName, COUNT(*) AS TotalRows FROM dbo.FactSales
UNION ALL
SELECT 'FactSales_Quarantine (Broken Data)', COUNT(*) FROM dbo.FactSales_Quarantine;



SELECT RowID, OrderID, Productkey, COUNT(*) as DuplicateCount
FROM dbo.FactSales
GROUP BY RowID, OrderID, Productkey
HAVING COUNT(*) > 1;


TRUNCATE TABLE dbo.FactSales;
TRUNCATE TABLE dbo.FactSales_Quarantine;





SELECT 'StgCustomers' AS TableName, COUNT(*) AS RowCount_ FROM [GlobalSuperstore_Staging].dbo.StgCustomers
UNION ALL
SELECT 'StgOrderLines', COUNT(*) FROM [GlobalSuperstore_Staging].dbo.StgOrderLines
UNION ALL
SELECT 'StgOrders', COUNT(*) FROM [GlobalSuperstore_Staging].dbo.StgOrders
UNION ALL
SELECT 'StgProducts', COUNT(*) FROM [GlobalSuperstore_Staging].dbo.StgProducts;



SELECT TOP 10 OrderID, Profit, accm_txn_create_time 
FROM dbo.FactSales;




