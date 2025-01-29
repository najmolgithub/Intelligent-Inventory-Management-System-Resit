CREATE DATABASE TestingDB;

USE TestingDB;
GO
-- Drop all tables if they exist
IF OBJECT_ID('dbo.SALES', 'U') IS NOT NULL
    DROP TABLE dbo.SALES;

IF OBJECT_ID('dbo.DW_ITEM', 'U') IS NOT NULL
    DROP TABLE dbo.DW_ITEM;

IF OBJECT_ID('dbo.DW_SUPPLIER', 'U') IS NOT NULL
    DROP TABLE dbo.DW_SUPPLIER;

IF OBJECT_ID('dbo.TIME', 'U') IS NOT NULL
    DROP TABLE dbo.TIME;
GO

-- Create Dimension Tables
-- Create DW_ITEM dimension table
CREATE TABLE DW_ITEM (
    Item_Key INT IDENTITY(1,1) PRIMARY KEY,
    Item_Code VARCHAR(50) UNIQUE,
    Item_Description VARCHAR(255),
    Item_Type VARCHAR(50)
);
GO

-- Create DW_SUPPLIER dimension table
CREATE TABLE DW_SUPPLIER (
    Supplier_Key INT IDENTITY(1,1) PRIMARY KEY,
    Supplier_Name VARCHAR(255) UNIQUE
);
GO

-- Create TIME dimension table
CREATE TABLE TIME (
    Date_Key INT PRIMARY KEY,
    Year INT,
    Month INT,
    Day INT,
    Quarter INT
);
GO

-- Create Fact Table
-- Create SALES fact table
CREATE TABLE SALES (
    Sales_Key INT IDENTITY(1,1) PRIMARY KEY,
    Date_Key INT,
    Item_Key INT,
    Supplier_Key INT,
    Retail_Sales INT,
    Retail_Transfers INT,
    Warehouse_Sales INT,
    FOREIGN KEY (Date_Key) REFERENCES TIME(Date_Key),
    FOREIGN KEY (Item_Key) REFERENCES DW_ITEM(Item_Key),
    FOREIGN KEY (Supplier_Key) REFERENCES DW_SUPPLIER(Supplier_Key)
);
GO





-- Populate DW_ITEM dimension table
WITH CTE_Item AS (
    SELECT 
        [ITEM CODE] AS Item_Code, 
        [ITEM DESCRIPTION] AS Item_Description, 
        [ITEM TYPE] AS Item_Type,
        ROW_NUMBER() OVER (PARTITION BY [ITEM CODE] ORDER BY [ITEM CODE]) AS RowNum
    FROM [dbo].[Warehouse_and_Retail_Sales CSV]
    WHERE ISNUMERIC([RETAIL SALES]) = 1 -- Ensure numeric values
      AND ISNUMERIC([RETAIL TRANSFERS]) = 1
      AND ISNUMERIC([WAREHOUSE SALES]) = 1
)
INSERT INTO DW_ITEM (Item_Code, Item_Description, Item_Type)
SELECT 
    Item_Code, 
    Item_Description, 
    Item_Type
FROM CTE_Item
WHERE RowNum = 1;
GO

-- Populate DW_SUPPLIER dimension table
WITH CTE_Supplier AS (
    SELECT 
        [SUPPLIER] AS Supplier_Name,
        ROW_NUMBER() OVER (PARTITION BY [SUPPLIER] ORDER BY [SUPPLIER]) AS RowNum
    FROM [dbo].[Warehouse_and_Retail_Sales CSV]
)
INSERT INTO DW_SUPPLIER (Supplier_Name)
SELECT DISTINCT 
    Supplier_Name
FROM CTE_Supplier
WHERE RowNum = 1;
GO

-- Populate TIME dimension table
WITH CTE_Time AS (
    SELECT 
        YEAR * 100 + MONTH AS Date_Key,
        YEAR,
        MONTH,
        1 AS Day, -- Default to 1 as day information is not available
        CASE 
            WHEN MONTH IN (1, 2, 3) THEN 1
            WHEN MONTH IN (4, 5, 6) THEN 2
            WHEN MONTH IN (7, 8, 9) THEN 3
            ELSE 4
        END AS Quarter,
        ROW_NUMBER() OVER (PARTITION BY YEAR, MONTH ORDER BY YEAR, MONTH) AS RowNum
    FROM [dbo].[Warehouse_and_Retail_Sales CSV]
    WHERE ISNUMERIC(YEAR) = 1 -- Ensure numeric values
      AND ISNUMERIC(MONTH) = 1
)
INSERT INTO TIME (Date_Key, Year, Month, Day, Quarter)
SELECT 
    Date_Key,
    Year,
    Month,
    Day,
    Quarter
FROM CTE_Time
WHERE RowNum = 1;
GO

-- Populate SALES fact table
INSERT INTO SALES (Date_Key, Item_Key, Supplier_Key, Retail_Sales, Retail_Transfers, Warehouse_Sales)
SELECT 
    T.Date_Key,
    DI.Item_Key,
    DS.Supplier_Key,
    TRY_CAST(W.[RETAIL SALES] AS INT), -- Safely convert to INT
    TRY_CAST(W.[RETAIL TRANSFERS] AS INT),
    TRY_CAST(W.[WAREHOUSE SALES] AS INT)
FROM [dbo].[Warehouse_and_Retail_Sales CSV] W
JOIN TIME T ON W.YEAR * 100 + W.MONTH = T.Date_Key
JOIN DW_ITEM DI ON W.[ITEM CODE] = DI.Item_Code
JOIN DW_SUPPLIER DS ON W.[SUPPLIER] = DS.Supplier_Name
WHERE TRY_CAST(W.[RETAIL SALES] AS INT) IS NOT NULL -- Filter out non-integer values
  AND TRY_CAST(W.[RETAIL TRANSFERS] AS INT) IS NOT NULL
  AND TRY_CAST(W.[WAREHOUSE SALES] AS INT) IS NOT NULL;
GO

