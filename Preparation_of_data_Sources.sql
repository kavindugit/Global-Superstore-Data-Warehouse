

use GlobalSuperstore_Source;

CREATE TABLE dbo.RawImport (
    RowID           INT,
    OrderID         VARCHAR(20),
    OrderDate       VARCHAR(15),    
    ShipDate        VARCHAR(15),    
    ShipMode        VARCHAR(20),
    CustomerID      VARCHAR(10),
    CustomerName    NVARCHAR(50),
    Segment         VARCHAR(15),
    City            NVARCHAR(50),
    State           NVARCHAR(50),
    Country         NVARCHAR(50),
    PostalCode      VARCHAR(20),
    Market          VARCHAR(10),
    Region          VARCHAR(30),
    ProductID       VARCHAR(20),
    Category        VARCHAR(20),
    SubCategory     VARCHAR(20),
    ProductName     NVARCHAR(200),
    Sales           VARCHAR(20),
    Quantity        VARCHAR(5),
    Discount        VARCHAR(10),
    Profit          VARCHAR(20),
    ShippingCost    VARCHAR(20),
    OrderPriority   VARCHAR(15)
);
GO

SELECT COUNT(*) AS RawImportRows FROM dbo.RawImport;



GO

-- Drop and recreate tables
IF OBJECT_ID('dbo.OrderLines', 'U') IS NOT NULL DROP TABLE dbo.OrderLines;
IF OBJECT_ID('dbo.Orders',     'U') IS NOT NULL DROP TABLE dbo.Orders;
GO

CREATE TABLE dbo.Orders (
    OrderID       VARCHAR(20),
    OrderDate     DATE,
    ShipDate      DATE,
    ShipMode      VARCHAR(20),
    CustomerID    VARCHAR(10),
    CustomerName  NVARCHAR(100),
    Segment       VARCHAR(15),
    OrderPriority VARCHAR(15)
);
GO

CREATE TABLE dbo.OrderLines (
    RowID        INT,
    OrderID      VARCHAR(20),
    ProductID    VARCHAR(20),
    Category     VARCHAR(20),
    SubCategory  VARCHAR(20),
    ProductName  NVARCHAR(200),
    Sales        DECIMAL(12,4),
    Quantity     INT,
    Discount     DECIMAL(5,4),
    Profit       DECIMAL(12,4),
    ShippingCost DECIMAL(12,4),
    City         NVARCHAR(100),
    State        NVARCHAR(100),
    Country      NVARCHAR(100),
    PostalCode   VARCHAR(20),
    Market       VARCHAR(10),
    Region       VARCHAR(30)
);
GO

-- Load Orders
-- Group by OrderID and take MIN of other fields
-- This guarantees exactly one row per OrderID
INSERT INTO dbo.Orders (
    OrderID, OrderDate, ShipDate, ShipMode,
    CustomerID, CustomerName, Segment, OrderPriority
)
SELECT
    OrderID,
    TRY_CONVERT(DATE,
        SUBSTRING(MIN(OrderDate),7,4) + '-' +
        SUBSTRING(MIN(OrderDate),4,2) + '-' +
        SUBSTRING(MIN(OrderDate),1,2)
    ),
    TRY_CONVERT(DATE,
        SUBSTRING(MIN(ShipDate),7,4) + '-' +
        SUBSTRING(MIN(ShipDate),4,2) + '-' +
        SUBSTRING(MIN(ShipDate),1,2)
    ),
    MIN(ShipMode),
    MIN(CustomerID),
    MIN(CustomerName),
    MIN(Segment),
    MIN(OrderPriority)
FROM dbo.RawImport
WHERE OrderID IS NOT NULL
GROUP BY OrderID;
GO

-- Load OrderLines
INSERT INTO dbo.OrderLines (
    RowID, OrderID, ProductID,
    Category, SubCategory, ProductName,
    Sales, Quantity, Discount, Profit, ShippingCost,
    City, State, Country, PostalCode, Market, Region
)
SELECT
    CAST(RowID AS INT),
    OrderID,
    ProductID,
    Category,
    SubCategory,
    ProductName,
    CAST(Sales        AS DECIMAL(12,4)),
    CAST(Quantity     AS INT),
    CAST(Discount     AS DECIMAL(5,4)),
    CAST(Profit       AS DECIMAL(12,4)),
    CAST(ShippingCost AS DECIMAL(12,4)),
    City, State, Country,
    NULLIF(LTRIM(RTRIM(PostalCode)), ''),
    Market, Region
FROM dbo.RawImport
WHERE RowID IS NOT NULL;
GO

-- Verify row counts — expect Orders=25035, OrderLines=51290
SELECT 'Orders'     AS TableName, COUNT(*) AS RowCount_ FROM dbo.Orders
UNION ALL
SELECT 'OrderLines' AS TableName, COUNT(*) AS RowCount_ FROM dbo.OrderLines;

-- Verify date range — expect 2011-01-01 to 2014-12-31
SELECT MIN(OrderDate) AS Earliest, MAX(OrderDate) AS Latest
FROM dbo.Orders;

-- Spot check one order with multiple lines
SELECT o.OrderID, o.CustomerName, o.OrderDate,
       ol.ProductName, ol.Sales, ol.Profit
FROM dbo.Orders o
JOIN dbo.OrderLines ol ON o.OrderID = ol.OrderID
WHERE o.OrderID = 'IN-2013-77878';


SELECT 'Orders'     AS TableName, COUNT(*) AS RowCount_ FROM dbo.Orders
UNION ALL
SELECT 'OrderLines' AS TableName, COUNT(*) AS RowCount_ FROM dbo.OrderLines;

select * from dbo.OrderLines;