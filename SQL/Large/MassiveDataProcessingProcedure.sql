-- =============================================
-- Enterprise Data Processing and ETL System
-- Version: 3.0
-- Date: 2024-01-20
-- Updated: Optimized batch processing
-- Description: Comprehensive data processing, ETL, and reporting system
-- This massive stored procedure handles complex data transformations and analytics
-- =============================================

CREATE PROCEDURE sp_EnterpriseDataProcessingSystem
    @ProcessingDate DATE = NULL,
    @BatchSize INT = 1000,
    @EnableLogging BIT = 1,
    @EnableValidation BIT = 1,
    @EnableArchiving BIT = 1,
    @ParallelProcessing BIT = 0,
    @DataSource NVARCHAR(100) = 'Production',
    @TargetEnvironment NVARCHAR(100) = 'DataWarehouse',
    @ProcessingMode NVARCHAR(50) = 'Incremental',
    @ErrorThreshold INT = 100,
    @RetryAttempts INT = 3
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    -- =============================================
    -- VARIABLE DECLARATIONS - SECTION 1
    -- =============================================
    
    DECLARE @StartTime DATETIME = GETDATE();
    DECLARE @EndTime DATETIME;
    DECLARE @ProcessingId UNIQUEIDENTIFIER = NEWID();
    DECLARE @TotalRecordsProcessed BIGINT = 0;
    DECLARE @TotalRecordsFailed BIGINT = 0;
    DECLARE @CurrentBatch INT = 0;
    DECLARE @ErrorCount INT = 0;
    DECLARE @WarningCount INT = 0;
    DECLARE @InfoCount INT = 0;
    DECLARE @ErrorMessage NVARCHAR(MAX);
    DECLARE @ErrorSeverity INT;
    DECLARE @ErrorState INT;
    DECLARE @RetryCount INT = 0;
    DECLARE @Success BIT = 0;
    
    -- Data quality metrics
    DECLARE @DuplicateRecords INT = 0;
    DECLARE @InvalidRecords INT = 0;
    DECLARE @OrphanedRecords INT = 0;
    DECLARE @DataQualityScore DECIMAL(5, 2);
    
    -- Performance metrics
    DECLARE @RecordsPerSecond DECIMAL(18, 2);
    DECLARE @AverageProcessingTime DECIMAL(18, 2);
    DECLARE @PeakMemoryUsage BIGINT;
    DECLARE @CpuTime BIGINT;
    
    -- Business metrics
    DECLARE @TotalRevenue DECIMAL(18, 2) = 0;
    DECLARE @TotalProfit DECIMAL(18, 2) = 0;
    DECLARE @TotalTransactions BIGINT = 0;
    DECLARE @ActiveCustomers INT = 0;
    DECLARE @NewCustomers INT = 0;
    
    -- =============================================
    -- INITIALIZATION AND VALIDATION
    -- =============================================
    
    BEGIN TRY
        -- Set processing date to today if not specified
        IF @ProcessingDate IS NULL
            SET @ProcessingDate = CAST(GETDATE() AS DATE);
        
        -- Validate parameters
        IF @BatchSize <= 0 OR @BatchSize > 10000
        BEGIN
            RAISERROR('Batch size must be between 1 and 10000', 16, 1);
            RETURN;
        END
        
        IF @ErrorThreshold < 0
        BEGIN
            RAISERROR('Error threshold cannot be negative', 16, 1);
            RETURN;
        END
        
        -- Log process start
        IF @EnableLogging = 1
        BEGIN
            INSERT INTO ProcessingLog (ProcessingId, ProcessType, StartTime, Status, Parameters)
            VALUES (
                @ProcessingId,
                'EnterpriseDataProcessing',
                @StartTime,
                'Started',
                CONCAT('Date: ', @ProcessingDate, ', BatchSize: ', @BatchSize, ', Mode: ', @ProcessingMode)
            );
        END
        
        -- =============================================
        -- CREATE TEMPORARY STAGING TABLES
        -- =============================================
        
        CREATE TABLE #StagingCustomers (
            RowId INT IDENTITY(1,1),
            CustomerId INT,
            CustomerName NVARCHAR(200),
            Email NVARCHAR(100),
            Phone NVARCHAR(20),
            RegistrationDate DATETIME,
            CustomerType NVARCHAR(50),
            CreditLimit DECIMAL(18, 2),
            CurrentBalance DECIMAL(18, 2),
            IsActive BIT,
            ValidationStatus NVARCHAR(50),
            ErrorMessage NVARCHAR(MAX)
        );
        
        CREATE TABLE #StagingOrders (
            RowId INT IDENTITY(1,1),
            OrderId INT,
            CustomerId INT,
            OrderDate DATETIME,
            TotalAmount DECIMAL(18, 2),
            OrderStatus NVARCHAR(50),
            PaymentMethod NVARCHAR(50),
            ShippingAddress NVARCHAR(MAX),
            ValidationStatus NVARCHAR(50),
            ErrorMessage NVARCHAR(MAX)
        );
        
        CREATE TABLE #StagingProducts (
            RowId INT IDENTITY(1,1),
            ProductId INT,
            ProductName NVARCHAR(200),
            SKU NVARCHAR(50),
            CategoryId INT,
            UnitPrice DECIMAL(18, 2),
            CostPrice DECIMAL(18, 2),
            QuantityInStock INT,
            ReorderLevel INT,
            ValidationStatus NVARCHAR(50),
            ErrorMessage NVARCHAR(MAX)
        );
        
        CREATE TABLE #ProcessingErrors (
            ErrorId INT IDENTITY(1,1),
            ErrorTime DATETIME DEFAULT GETDATE(),
            ErrorType NVARCHAR(50),
            ErrorMessage NVARCHAR(MAX),
            AffectedTable NVARCHAR(100),
            AffectedRowId INT,
            Severity NVARCHAR(20)
        );
        
        CREATE TABLE #DataQualityMetrics (
            MetricId INT IDENTITY(1,1),
            MetricName NVARCHAR(100),
            MetricValue DECIMAL(18, 2),
            ThresholdValue DECIMAL(18, 2),
            Status NVARCHAR(20),
            Description NVARCHAR(MAX)
        );
        
        -- =============================================
        -- SECTION 1: CUSTOMER DATA PROCESSING
        -- =============================================
        
        -- Load customer data into staging
        INSERT INTO #StagingCustomers (
            CustomerId, CustomerName, Email, Phone, RegistrationDate,
            CustomerType, CreditLimit, CurrentBalance, IsActive, ValidationStatus
        )
        SELECT 
            c.CustomerId,
            c.FirstName + ' ' + c.LastName,
            c.Email,
            c.PhoneNumber,
            c.CreatedDate,
            CASE 
                WHEN (SELECT SUM(TotalAmount) FROM Orders WHERE CustomerId = c.CustomerId) >= 10000 THEN 'Premium'
                WHEN (SELECT COUNT(*) FROM Orders WHERE CustomerId = c.CustomerId) >= 10 THEN 'Gold'
                WHEN (SELECT COUNT(*) FROM Orders WHERE CustomerId = c.CustomerId) >= 5 THEN 'Silver'
                ELSE 'Bronze'
            END,
            CASE 
                WHEN (SELECT SUM(TotalAmount) FROM Orders WHERE CustomerId = c.CustomerId) >= 10000 THEN 50000.00
                WHEN (SELECT COUNT(*) FROM Orders WHERE CustomerId = c.CustomerId) >= 10 THEN 25000.00
                WHEN (SELECT COUNT(*) FROM Orders WHERE CustomerId = c.CustomerId) >= 5 THEN 10000.00
                ELSE 5000.00
            END,
            COALESCE((SELECT SUM(TotalAmount) FROM Orders WHERE CustomerId = c.CustomerId AND OrderStatus = 'Pending'), 0),
            c.IsActive,
            'Pending'
        FROM Customers c
        WHERE c.CreatedDate <= @ProcessingDate;
        
        -- Validate customer data
        UPDATE #StagingCustomers
        SET ValidationStatus = 'Invalid',
            ErrorMessage = 'Invalid email format'
        WHERE Email IS NULL OR Email NOT LIKE '%@%.%';
        
        UPDATE #StagingCustomers
        SET ValidationStatus = 'Invalid',
            ErrorMessage = 'Customer name is required'
        WHERE CustomerName IS NULL OR LEN(TRIM(CustomerName)) = 0;
        
        UPDATE #StagingCustomers
        SET ValidationStatus = 'Warning',
            ErrorMessage = 'Current balance exceeds credit limit'
        WHERE CurrentBalance > CreditLimit
            AND ValidationStatus = 'Pending';
        
        UPDATE #StagingCustomers
        SET ValidationStatus = 'Valid'
        WHERE ValidationStatus = 'Pending';
        
        -- Log validation results
        SET @InvalidRecords = (SELECT COUNT(*) FROM #StagingCustomers WHERE ValidationStatus = 'Invalid');
        SET @WarningCount = @WarningCount + (SELECT COUNT(*) FROM #StagingCustomers WHERE ValidationStatus = 'Warning');
        
        -- =============================================
        -- SECTION 2: ORDER DATA PROCESSING
        -- =============================================
        
        -- Load order data into staging
        INSERT INTO #StagingOrders (
            OrderId, CustomerId, OrderDate, TotalAmount,
            OrderStatus, PaymentMethod, ShippingAddress, ValidationStatus
        )
        SELECT 
            o.OrderId,
            o.CustomerId,
            o.OrderDate,
            o.TotalAmount,
            o.OrderStatus,
            COALESCE(
                (SELECT TOP 1 PaymentMethod FROM PaymentTransactions 
                 WHERE OrderId = o.OrderId ORDER BY ProcessedDate DESC),
                'Unknown'
            ),
            COALESCE(
                (SELECT AddressLine1 + ', ' + City + ', ' + StateProvince 
                 FROM CustomerAddresses WHERE AddressId = o.ShippingAddressId),
                'No Address'
            ),
            'Pending'
        FROM Orders o
        WHERE o.OrderDate <= @ProcessingDate;
        
        -- Validate order data
        UPDATE #StagingOrders
        SET ValidationStatus = 'Invalid',
            ErrorMessage = 'Customer does not exist'
        WHERE CustomerId NOT IN (SELECT CustomerId FROM #StagingCustomers WHERE ValidationStatus = 'Valid');
        
        UPDATE #StagingOrders
        SET ValidationStatus = 'Invalid',
            ErrorMessage = 'Invalid total amount'
        WHERE TotalAmount <= 0
            AND ValidationStatus = 'Pending';
        
        UPDATE #StagingOrders
        SET ValidationStatus = 'Warning',
            ErrorMessage = 'Order date is in the future'
        WHERE OrderDate > GETDATE()
            AND ValidationStatus = 'Pending';
        
        UPDATE #StagingOrders
        SET ValidationStatus = 'Valid'
        WHERE ValidationStatus = 'Pending';
        
        -- =============================================
        -- SECTION 3: PRODUCT DATA PROCESSING
        -- =============================================
        
        -- Load product data into staging
        INSERT INTO #StagingProducts (
            ProductId, ProductName, SKU, CategoryId,
            UnitPrice, CostPrice, QuantityInStock, ReorderLevel, ValidationStatus
        )
        SELECT 
            p.ProductId,
            p.ProductName,
            p.SKU,
            p.CategoryId,
            p.UnitPrice,
            COALESCE(p.CostPrice, 0),
            COALESCE(i.QuantityInStock, 0),
            COALESCE(i.ReorderLevel, 10),
            'Pending'
        FROM Products p
        LEFT JOIN Inventory i ON p.ProductId = i.ProductId
        WHERE p.IsActive = 1;
        
        -- Validate product data
        UPDATE #StagingProducts
        SET ValidationStatus = 'Invalid',
            ErrorMessage = 'Product name is required'
        WHERE ProductName IS NULL OR LEN(TRIM(ProductName)) = 0;
        
        UPDATE #StagingProducts
        SET ValidationStatus = 'Invalid',
            ErrorMessage = 'SKU is required'
        WHERE SKU IS NULL OR LEN(TRIM(SKU)) = 0
            AND ValidationStatus = 'Pending';
        
        UPDATE #StagingProducts
        SET ValidationStatus = 'Warning',
            ErrorMessage = 'Unit price is less than cost price'
        WHERE UnitPrice < CostPrice
            AND ValidationStatus = 'Pending';
        
        UPDATE #StagingProducts
        SET ValidationStatus = 'Warning',
            ErrorMessage = 'Stock level below reorder level'
        WHERE QuantityInStock < ReorderLevel
            AND ValidationStatus = 'Pending';
        
        UPDATE #StagingProducts
        SET ValidationStatus = 'Valid'
        WHERE ValidationStatus = 'Pending';
        
        -- =============================================
        -- SECTION 4: DATA TRANSFORMATION
        -- =============================================
        
        -- Create fact tables for data warehouse
        CREATE TABLE #FactSales (
            SalesKey BIGINT IDENTITY(1,1),
            OrderId INT,
            CustomerId INT,
            ProductId INT,
            OrderDate DATE,
            SalesAmount DECIMAL(18, 2),
            CostAmount DECIMAL(18, 2),
            ProfitAmount DECIMAL(18, 2),
            Quantity INT,
            DiscountAmount DECIMAL(18, 2),
            TaxAmount DECIMAL(18, 2)
        );
        
        -- Populate fact sales table
        INSERT INTO #FactSales (
            OrderId, CustomerId, ProductId, OrderDate,
            SalesAmount, CostAmount, ProfitAmount, Quantity,
            DiscountAmount, TaxAmount
        )
        SELECT 
            o.OrderId,
            o.CustomerId,
            oi.ProductId,
            CAST(o.OrderDate AS DATE),
            oi.TotalAmount,
            oi.Quantity * p.CostPrice,
            oi.TotalAmount - (oi.Quantity * p.CostPrice),
            oi.Quantity,
            oi.DiscountAmount,
            oi.TaxAmount
        FROM #StagingOrders o
        INNER JOIN OrderItems oi ON o.OrderId = oi.OrderId
        INNER JOIN #StagingProducts p ON oi.ProductId = p.ProductId
        WHERE o.ValidationStatus = 'Valid'
            AND p.ValidationStatus IN ('Valid', 'Warning');
        
        -- =============================================
        -- SECTION 5: AGGREGATIONS AND CALCULATIONS
        -- =============================================
        
        -- Calculate daily aggregates
        CREATE TABLE #DailyAggregates (
            AggregateDate DATE,
            TotalOrders INT,
            TotalRevenue DECIMAL(18, 2),
            TotalProfit DECIMAL(18, 2),
            TotalCost DECIMAL(18, 2),
            AverageOrderValue DECIMAL(18, 2),
            UniqueCustomers INT,
            NewCustomers INT,
            TotalQuantitySold INT
        );
        
        INSERT INTO #DailyAggregates
        SELECT 
            OrderDate,
            COUNT(DISTINCT OrderId) AS TotalOrders,
            SUM(SalesAmount) AS TotalRevenue,
            SUM(ProfitAmount) AS TotalProfit,
            SUM(CostAmount) AS TotalCost,
            AVG(SalesAmount) AS AverageOrderValue,
            COUNT(DISTINCT CustomerId) AS UniqueCustomers,
            COUNT(DISTINCT CASE 
                WHEN NOT EXISTS (
                    SELECT 1 FROM #FactSales fs2 
                    WHERE fs2.CustomerId = fs.CustomerId 
                    AND fs2.OrderDate < fs.OrderDate
                ) 
                THEN CustomerId 
            END) AS NewCustomers,
            SUM(Quantity) AS TotalQuantitySold
        FROM #FactSales fs
        GROUP BY OrderDate;
        
        -- Calculate customer metrics
        CREATE TABLE #CustomerMetrics (
            CustomerId INT,
            TotalOrders INT,
            TotalSpent DECIMAL(18, 2),
            TotalProfit DECIMAL(18, 2),
            AverageOrderValue DECIMAL(18, 2),
            FirstOrderDate DATE,
            LastOrderDate DATE,
            DaysBetweenOrders INT,
            CustomerLifetimeDays INT,
            PredictedChurnProbability DECIMAL(5, 2)
        );
        
        INSERT INTO #CustomerMetrics
        SELECT 
            CustomerId,
            COUNT(DISTINCT OrderId) AS TotalOrders,
            SUM(SalesAmount) AS TotalSpent,
            SUM(ProfitAmount) AS TotalProfit,
            AVG(SalesAmount) AS AverageOrderValue,
            MIN(OrderDate) AS FirstOrderDate,
            MAX(OrderDate) AS LastOrderDate,
            CASE 
                WHEN COUNT(DISTINCT OrderDate) > 1 
                THEN DATEDIFF(DAY, MIN(OrderDate), MAX(OrderDate)) / (COUNT(DISTINCT OrderDate) - 1)
                ELSE 0 
            END AS DaysBetweenOrders,
            DATEDIFF(DAY, MIN(OrderDate), @ProcessingDate) AS CustomerLifetimeDays,
            CASE 
                WHEN DATEDIFF(DAY, MAX(OrderDate), @ProcessingDate) > 180 THEN 0.9
                WHEN DATEDIFF(DAY, MAX(OrderDate), @ProcessingDate) > 120 THEN 0.7
                WHEN DATEDIFF(DAY, MAX(OrderDate), @ProcessingDate) > 90 THEN 0.5
                WHEN DATEDIFF(DAY, MAX(OrderDate), @ProcessingDate) > 60 THEN 0.3
                ELSE 0.1
            END AS PredictedChurnProbability
        FROM #FactSales
        GROUP BY CustomerId;
        
        -- Calculate product metrics
        CREATE TABLE #ProductMetrics (
            ProductId INT,
            TotalQuantitySold INT,
            TotalRevenue DECIMAL(18, 2),
            TotalProfit DECIMAL(18, 2),
            ProfitMargin DECIMAL(5, 2),
            AveragePrice DECIMAL(18, 2),
            TotalOrders INT,
            UniqueCustomers INT,
            FirstSaleDate DATE,
            LastSaleDate DATE,
            DaysSinceLastSale INT
        );
        
        INSERT INTO #ProductMetrics
        SELECT 
            ProductId,
            SUM(Quantity) AS TotalQuantitySold,
            SUM(SalesAmount) AS TotalRevenue,
            SUM(ProfitAmount) AS TotalProfit,
            CASE 
                WHEN SUM(SalesAmount) > 0 
                THEN (SUM(ProfitAmount) / SUM(SalesAmount)) * 100 
                ELSE 0 
            END AS ProfitMargin,
            AVG(SalesAmount / NULLIF(Quantity, 0)) AS AveragePrice,
            COUNT(DISTINCT OrderId) AS TotalOrders,
            COUNT(DISTINCT CustomerId) AS UniqueCustomers,
            MIN(OrderDate) AS FirstSaleDate,
            MAX(OrderDate) AS LastSaleDate,
            DATEDIFF(DAY, MAX(OrderDate), @ProcessingDate) AS DaysSinceLastSale
        FROM #FactSales
        GROUP BY ProductId;
        
        -- =============================================
        -- SECTION 6: ADVANCED ANALYTICS
        -- =============================================
        
        -- RFM Analysis (Recency, Frequency, Monetary)
        CREATE TABLE #RFMAnalysis (
            CustomerId INT,
            Recency INT,
            Frequency INT,
            Monetary DECIMAL(18, 2),
            RecencyScore INT,
            FrequencyScore INT,
            MonetaryScore INT,
            RFMScore NVARCHAR(3),
            CustomerSegment NVARCHAR(50)
        );
        
        INSERT INTO #RFMAnalysis
        SELECT 
            CustomerId,
            DATEDIFF(DAY, LastOrderDate, @ProcessingDate) AS Recency,
            TotalOrders AS Frequency,
            TotalSpent AS Monetary,
            CASE 
                WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 30 THEN 5
                WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 60 THEN 4
                WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 90 THEN 3
                WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 180 THEN 2
                ELSE 1
            END AS RecencyScore,
            CASE 
                WHEN TotalOrders >= 20 THEN 5
                WHEN TotalOrders >= 10 THEN 4
                WHEN TotalOrders >= 5 THEN 3
                WHEN TotalOrders >= 2 THEN 2
                ELSE 1
            END AS FrequencyScore,
            CASE 
                WHEN TotalSpent >= 5000 THEN 5
                WHEN TotalSpent >= 2000 THEN 4
                WHEN TotalSpent >= 1000 THEN 3
                WHEN TotalSpent >= 500 THEN 2
                ELSE 1
            END AS MonetaryScore,
            CAST(
                CASE 
                    WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 30 THEN 5
                    WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 60 THEN 4
                    WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 90 THEN 3
                    WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 180 THEN 2
                    ELSE 1
                END AS NVARCHAR(1)) +
            CAST(
                CASE 
                    WHEN TotalOrders >= 20 THEN 5
                    WHEN TotalOrders >= 10 THEN 4
                    WHEN TotalOrders >= 5 THEN 3
                    WHEN TotalOrders >= 2 THEN 2
                    ELSE 1
                END AS NVARCHAR(1)) +
            CAST(
                CASE 
                    WHEN TotalSpent >= 5000 THEN 5
                    WHEN TotalSpent >= 2000 THEN 4
                    WHEN TotalSpent >= 1000 THEN 3
                    WHEN TotalSpent >= 500 THEN 2
                    ELSE 1
                END AS NVARCHAR(1)) AS RFMScore,
            CASE 
                WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 30 
                    AND TotalOrders >= 10 
                    AND TotalSpent >= 2000 THEN 'Champions'
                WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 60 
                    AND TotalOrders >= 5 
                    AND TotalSpent >= 1000 THEN 'Loyal Customers'
                WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 90 
                    AND TotalOrders >= 3 THEN 'Potential Loyalists'
                WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 30 
                    AND TotalOrders = 1 THEN 'New Customers'
                WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) <= 90 
                    AND TotalSpent >= 2000 THEN 'Big Spenders'
                WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) > 180 
                    AND TotalOrders >= 5 THEN 'At Risk'
                WHEN DATEDIFF(DAY, LastOrderDate, @ProcessingDate) > 270 THEN 'Lost Customers'
                WHEN TotalOrders = 1 AND DATEDIFF(DAY, LastOrderDate, @ProcessingDate) > 90 THEN 'Lost New Customers'
                ELSE 'Regular Customers'
            END AS CustomerSegment
        FROM #CustomerMetrics;
        
        -- Product affinity analysis (products bought together)
        CREATE TABLE #ProductAffinity (
            ProductId1 INT,
            ProductId2 INT,
            CoOccurrenceCount INT,
            AffinityScore DECIMAL(5, 2)
        );
        
        INSERT INTO #ProductAffinity
        SELECT 
            fs1.ProductId AS ProductId1,
            fs2.ProductId AS ProductId2,
            COUNT(DISTINCT fs1.OrderId) AS CoOccurrenceCount,
            CAST(COUNT(DISTINCT fs1.OrderId) AS DECIMAL(10, 2)) / 
                NULLIF((SELECT COUNT(DISTINCT OrderId) FROM #FactSales WHERE ProductId = fs1.ProductId), 0) * 100 
                AS AffinityScore
        FROM #FactSales fs1
        INNER JOIN #FactSales fs2 ON fs1.OrderId = fs2.OrderId AND fs1.ProductId < fs2.ProductId
        GROUP BY fs1.ProductId, fs2.ProductId
        HAVING COUNT(DISTINCT fs1.OrderId) >= 3;
        
        -- Time series analysis for forecasting
        CREATE TABLE #TimeSeriesAnalysis (
            AnalysisDate DATE,
            ActualRevenue DECIMAL(18, 2),
            MovingAverage7Day DECIMAL(18, 2),
            MovingAverage30Day DECIMAL(18, 2),
            TrendIndicator NVARCHAR(20),
            SeasonalityFactor DECIMAL(5, 2),
            ForecastedRevenue DECIMAL(18, 2)
        );
        
        INSERT INTO #TimeSeriesAnalysis
        SELECT 
            da.AggregateDate,
            da.TotalRevenue,
            (
                SELECT AVG(TotalRevenue)
                FROM #DailyAggregates da2
                WHERE da2.AggregateDate BETWEEN DATEADD(DAY, -7, da.AggregateDate) AND da.AggregateDate
            ) AS MovingAverage7Day,
            (
                SELECT AVG(TotalRevenue)
                FROM #DailyAggregates da3
                WHERE da3.AggregateDate BETWEEN DATEADD(DAY, -30, da.AggregateDate) AND da.AggregateDate
            ) AS MovingAverage30Day,
            CASE 
                WHEN da.TotalRevenue > (
                    SELECT AVG(TotalRevenue) * 1.1
                    FROM #DailyAggregates da2
                    WHERE da2.AggregateDate BETWEEN DATEADD(DAY, -7, da.AggregateDate) AND da.AggregateDate
                ) THEN 'Growing'
                WHEN da.TotalRevenue < (
                    SELECT AVG(TotalRevenue) * 0.9
                    FROM #DailyAggregates da3
                    WHERE da3.AggregateDate BETWEEN DATEADD(DAY, -7, da.AggregateDate) AND da.AggregateDate
                ) THEN 'Declining'
                ELSE 'Stable'
            END AS TrendIndicator,
            1.0 + (
                (DATEPART(WEEKDAY, da.AggregateDate) - 3) * 0.05
            ) AS SeasonalityFactor,
            (
                SELECT AVG(TotalRevenue)
                FROM #DailyAggregates da4
                WHERE da4.AggregateDate BETWEEN DATEADD(DAY, -30, da.AggregateDate) AND da.AggregateDate
            ) * (1.0 + ((DATEPART(WEEKDAY, da.AggregateDate) - 3) * 0.05)) AS ForecastedRevenue
        FROM #DailyAggregates da;
        
        -- =============================================
        -- SECTION 7: DATA QUALITY CHECKS
        -- =============================================
        
        -- Check for duplicate customers
        INSERT INTO #DataQualityMetrics (MetricName, MetricValue, ThresholdValue, Status, Description)
        SELECT 
            'Duplicate Customer Emails',
            COUNT(*),
            0,
            CASE WHEN COUNT(*) > 0 THEN 'Warning' ELSE 'Pass' END,
            'Number of duplicate email addresses found'
        FROM (
            SELECT Email, COUNT(*) AS DuplicateCount
            FROM #StagingCustomers
            WHERE ValidationStatus = 'Valid'
            GROUP BY Email
            HAVING COUNT(*) > 1
        ) dup;
        
        -- Check data completeness
        INSERT INTO #DataQualityMetrics (MetricName, MetricValue, ThresholdValue, Status, Description)
        SELECT 
            'Customer Data Completeness',
            (CAST(COUNT(CASE WHEN Email IS NOT NULL AND Phone IS NOT NULL THEN 1 END) AS DECIMAL(10,2)) / 
             NULLIF(COUNT(*), 0)) * 100,
            95.0,
            CASE 
                WHEN (CAST(COUNT(CASE WHEN Email IS NOT NULL AND Phone IS NOT NULL THEN 1 END) AS DECIMAL(10,2)) / 
                      NULLIF(COUNT(*), 0)) * 100 >= 95.0 THEN 'Pass'
                ELSE 'Warning'
            END,
            'Percentage of customers with complete contact information'
        FROM #StagingCustomers;
        
        -- Check for orphaned orders
        INSERT INTO #DataQualityMetrics (MetricName, MetricValue, ThresholdValue, Status, Description)
        SELECT 
            'Orphaned Orders',
            COUNT(*),
            0,
            CASE WHEN COUNT(*) > 0 THEN 'Error' ELSE 'Pass' END,
            'Number of orders without valid customer references'
        FROM #StagingOrders
        WHERE ValidationStatus = 'Invalid'
            AND ErrorMessage LIKE '%Customer does not exist%';
        
        -- Check for negative inventory
        INSERT INTO #DataQualityMetrics (MetricName, MetricValue, ThresholdValue, Status, Description)
        SELECT 
            'Negative Inventory Items',
            COUNT(*),
            0,
            CASE WHEN COUNT(*) > 0 THEN 'Warning' ELSE 'Pass' END,
            'Number of products with negative stock levels'
        FROM #StagingProducts
        WHERE QuantityInStock < 0;
        
        -- Calculate overall data quality score
        SELECT @DataQualityScore = 
            CASE 
                WHEN COUNT(CASE WHEN Status = 'Error' THEN 1 END) > 0 THEN 60.0
                WHEN COUNT(CASE WHEN Status = 'Warning' THEN 1 END) > 3 THEN 75.0
                WHEN COUNT(CASE WHEN Status = 'Warning' THEN 1 END) > 0 THEN 85.0
                ELSE 100.0
            END
        FROM #DataQualityMetrics;
        
        -- =============================================
        -- SECTION 8: BUSINESS RULES VALIDATION
        -- =============================================
        
        -- Check for suspicious high-value transactions
        CREATE TABLE #SuspiciousTransactions (
            OrderId INT,
            CustomerId INT,
            OrderDate DATE,
            TotalAmount DECIMAL(18, 2),
            SuspicionReason NVARCHAR(MAX),
            RiskScore DECIMAL(3, 2)
        );
        
        INSERT INTO #SuspiciousTransactions
        SELECT 
            o.OrderId,
            o.CustomerId,
            CAST(o.OrderDate AS DATE),
            o.TotalAmount,
            'Order value exceeds typical customer spending by 300%',
            0.8
        FROM #StagingOrders o
        INNER JOIN #CustomerMetrics cm ON o.CustomerId = cm.CustomerId
        WHERE o.TotalAmount > (cm.AverageOrderValue * 3)
            AND o.ValidationStatus = 'Valid';
        
        -- Check for rapid repeated purchases
        INSERT INTO #SuspiciousTransactions
        SELECT 
            o1.OrderId,
            o1.CustomerId,
            CAST(o1.OrderDate AS DATE),
            o1.TotalAmount,
            'Multiple orders within short timeframe',
            0.6
        FROM #StagingOrders o1
        INNER JOIN #StagingOrders o2 ON o1.CustomerId = o2.CustomerId 
            AND o1.OrderId <> o2.OrderId
            AND ABS(DATEDIFF(MINUTE, o1.OrderDate, o2.OrderDate)) < 60
        WHERE o1.ValidationStatus = 'Valid';
        
        -- =============================================
        -- SECTION 9: REPORTING AND ANALYTICS OUTPUT
        -- =============================================
        
        -- Executive summary report
        SELECT 
            'Executive Summary' AS ReportSection,
            @ProcessingDate AS ProcessingDate,
            (SELECT COUNT(*) FROM #StagingCustomers WHERE ValidationStatus = 'Valid') AS ValidCustomers,
            (SELECT COUNT(*) FROM #StagingOrders WHERE ValidationStatus = 'Valid') AS ValidOrders,
            (SELECT COUNT(*) FROM #StagingProducts WHERE ValidationStatus = 'Valid') AS ValidProducts,
            (SELECT SUM(TotalRevenue) FROM #DailyAggregates) AS TotalRevenue,
            (SELECT SUM(TotalProfit) FROM #DailyAggregates) AS TotalProfit,
            (SELECT AVG(AverageOrderValue) FROM #DailyAggregates) AS AverageOrderValue,
            @DataQualityScore AS DataQualityScore;
        
        -- Customer segment distribution
        SELECT 
            'Customer Segments' AS ReportSection,
            CustomerSegment,
            COUNT(*) AS CustomerCount,
            AVG(Monetary) AS AverageLifetimeValue,
            AVG(Frequency) AS AverageOrderCount,
            AVG(Recency) AS AverageRecency
        FROM #RFMAnalysis
        GROUP BY CustomerSegment
        ORDER BY AVG(Monetary) DESC;
        
        -- Top performing products
        SELECT 
            'Top Products' AS ReportSection,
            p.ProductName,
            pm.TotalQuantitySold,
            pm.TotalRevenue,
            pm.TotalProfit,
            pm.ProfitMargin,
            pm.UniqueCustomers
        FROM #ProductMetrics pm
        INNER JOIN #StagingProducts p ON pm.ProductId = p.ProductId
        ORDER BY pm.TotalRevenue DESC;
        
        -- Daily sales trends
        SELECT 
            'Daily Trends' AS ReportSection,
            AggregateDate,
            TotalOrders,
            TotalRevenue,
            TotalProfit,
            AverageOrderValue,
            NewCustomers
        FROM #DailyAggregates
        ORDER BY AggregateDate;
        
        -- Time series forecast
        SELECT 
            'Revenue Forecast' AS ReportSection,
            AnalysisDate,
            ActualRevenue,
            MovingAverage7Day,
            MovingAverage30Day,
            TrendIndicator,
            ForecastedRevenue
        FROM #TimeSeriesAnalysis
        ORDER BY AnalysisDate;
        
        -- Data quality report
        SELECT 
            'Data Quality Metrics' AS ReportSection,
            MetricName,
            MetricValue,
            ThresholdValue,
            Status,
            Description
        FROM #DataQualityMetrics
        ORDER BY 
            CASE Status 
                WHEN 'Error' THEN 1 
                WHEN 'Warning' THEN 2 
                ELSE 3 
            END;
        
        -- Suspicious transactions report
        IF EXISTS (SELECT 1 FROM #SuspiciousTransactions)
        BEGIN
            SELECT 
                'Suspicious Transactions' AS ReportSection,
                st.OrderId,
                c.CustomerName,
                st.OrderDate,
                st.TotalAmount,
                st.SuspicionReason,
                st.RiskScore
            FROM #SuspiciousTransactions st
            INNER JOIN #StagingCustomers c ON st.CustomerId = c.CustomerId
            ORDER BY st.RiskScore DESC, st.TotalAmount DESC;
        END
        
        -- Product affinity insights
        SELECT TOP 100
            'Product Affinity' AS ReportSection,
            p1.ProductName AS Product1,
            p2.ProductName AS Product2,
            pa.CoOccurrenceCount,
            pa.AffinityScore
        FROM #ProductAffinity pa
        INNER JOIN #StagingProducts p1 ON pa.ProductId1 = p1.ProductId
        INNER JOIN #StagingProducts p2 ON pa.ProductId2 = p2.ProductId
        ORDER BY pa.AffinityScore DESC;
        
        -- Customer churn prediction
        SELECT 
            'Churn Prediction' AS ReportSection,
            c.CustomerName,
            c.Email,
            cm.LastOrderDate,
            cm.DaysBetweenOrders,
            cm.TotalSpent,
            cm.PredictedChurnProbability,
            CASE 
                WHEN cm.PredictedChurnProbability >= 0.7 THEN 'High Risk'
                WHEN cm.PredictedChurnProbability >= 0.4 THEN 'Medium Risk'
                ELSE 'Low Risk'
            END AS ChurnRiskLevel
        FROM #CustomerMetrics cm
        INNER JOIN #StagingCustomers c ON cm.CustomerId = c.CustomerId
        WHERE cm.PredictedChurnProbability >= 0.4
        ORDER BY cm.PredictedChurnProbability DESC;
        
        -- =============================================
        -- SECTION 10: DATA ARCHIVING
        -- =============================================
        
        IF @EnableArchiving = 1
        BEGIN
            -- Archive processed data to historical tables
            INSERT INTO ArchiveCustomerMetrics (
                ProcessingDate, CustomerId, TotalOrders, TotalSpent,
                AverageOrderValue, ChurnProbability, CustomerSegment
            )
            SELECT 
                @ProcessingDate,
                cm.CustomerId,
                cm.TotalOrders,
                cm.TotalSpent,
                cm.AverageOrderValue,
                cm.PredictedChurnProbability,
                rfm.CustomerSegment
            FROM #CustomerMetrics cm
            LEFT JOIN #RFMAnalysis rfm ON cm.CustomerId = rfm.CustomerId;
            
            -- Archive daily aggregates
            INSERT INTO ArchiveDailyAggregates (
                ProcessingDate, AggregateDate, TotalOrders, TotalRevenue,
                TotalProfit, AverageOrderValue, NewCustomers
            )
            SELECT 
                @ProcessingDate,
                AggregateDate,
                TotalOrders,
                TotalRevenue,
                TotalProfit,
                AverageOrderValue,
                NewCustomers
            FROM #DailyAggregates;
            
            -- Archive product performance
            INSERT INTO ArchiveProductMetrics (
                ProcessingDate, ProductId, TotalQuantitySold, TotalRevenue,
                TotalProfit, ProfitMargin
            )
            SELECT 
                @ProcessingDate,
                ProductId,
                TotalQuantitySold,
                TotalRevenue,
                TotalProfit,
                ProfitMargin
            FROM #ProductMetrics;
        END
        
        -- =============================================
        -- SECTION 11: PERFORMANCE METRICS
        -- =============================================
        
        SET @EndTime = GETDATE();
        SET @TotalRecordsProcessed = 
            (SELECT COUNT(*) FROM #StagingCustomers) +
            (SELECT COUNT(*) FROM #StagingOrders) +
            (SELECT COUNT(*) FROM #StagingProducts);
        
        SET @RecordsPerSecond = 
            @TotalRecordsProcessed / 
            NULLIF(DATEDIFF(SECOND, @StartTime, @EndTime), 0);
        
        -- Performance summary
        SELECT 
            'Performance Metrics' AS ReportSection,
            @ProcessingId AS ProcessingId,
            @StartTime AS StartTime,
            @EndTime AS EndTime,
            DATEDIFF(SECOND, @StartTime, @EndTime) AS DurationSeconds,
            @TotalRecordsProcessed AS TotalRecordsProcessed,
            @TotalRecordsFailed AS TotalRecordsFailed,
            @RecordsPerSecond AS RecordsPerSecond,
            @ErrorCount AS ErrorCount,
            @WarningCount AS WarningCount,
            @DataQualityScore AS DataQualityScore;
        
        -- =============================================
        -- SECTION 12: CLEANUP AND FINALIZATION
        -- =============================================
        
        -- Update processing log with success
        IF @EnableLogging = 1
        BEGIN
            UPDATE ProcessingLog
            SET EndTime = @EndTime,
                Status = 'Completed',
                RecordsProcessed = @TotalRecordsProcessed,
                RecordsFailed = @TotalRecordsFailed,
                DataQualityScore = @DataQualityScore
            WHERE ProcessingId = @ProcessingId;
        END
        
        -- Drop temporary tables
        DROP TABLE #StagingCustomers;
        DROP TABLE #StagingOrders;
        DROP TABLE #StagingProducts;
        DROP TABLE #ProcessingErrors;
        DROP TABLE #DataQualityMetrics;
        DROP TABLE #FactSales;
        DROP TABLE #DailyAggregates;
        DROP TABLE #CustomerMetrics;
        DROP TABLE #ProductMetrics;
        DROP TABLE #RFMAnalysis;
        DROP TABLE #ProductAffinity;
        DROP TABLE #TimeSeriesAnalysis;
        DROP TABLE #SuspiciousTransactions;
        
        SET @Success = 1;
        
    END TRY
    BEGIN CATCH
        -- Error handling
        SELECT 
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorSeverity = ERROR_SEVERITY(),
            @ErrorState = ERROR_STATE();
        
        SET @EndTime = GETDATE();
        
        -- Log error
        IF @EnableLogging = 1
        BEGIN
            UPDATE ProcessingLog
            SET EndTime = @EndTime,
                Status = 'Failed',
                ErrorMessage = @ErrorMessage
            WHERE ProcessingId = @ProcessingId;
            
            INSERT INTO ErrorLog (ProcessingId, ErrorMessage, ErrorSeverity, ErrorTime)
            VALUES (@ProcessingId, @ErrorMessage, @ErrorSeverity, GETDATE());
        END
        
        -- Cleanup temp tables if they exist
        IF OBJECT_ID('tempdb..#StagingCustomers') IS NOT NULL DROP TABLE #StagingCustomers;
        IF OBJECT_ID('tempdb..#StagingOrders') IS NOT NULL DROP TABLE #StagingOrders;
        IF OBJECT_ID('tempdb..#StagingProducts') IS NOT NULL DROP TABLE #StagingProducts;
        IF OBJECT_ID('tempdb..#ProcessingErrors') IS NOT NULL DROP TABLE #ProcessingErrors;
        IF OBJECT_ID('tempdb..#DataQualityMetrics') IS NOT NULL DROP TABLE #DataQualityMetrics;
        IF OBJECT_ID('tempdb..#FactSales') IS NOT NULL DROP TABLE #FactSales;
        IF OBJECT_ID('tempdb..#DailyAggregates') IS NOT NULL DROP TABLE #DailyAggregates;
        IF OBJECT_ID('tempdb..#CustomerMetrics') IS NOT NULL DROP TABLE #CustomerMetrics;
        IF OBJECT_ID('tempdb..#ProductMetrics') IS NOT NULL DROP TABLE #ProductMetrics;
        IF OBJECT_ID('tempdb..#RFMAnalysis') IS NOT NULL DROP TABLE #RFMAnalysis;
        IF OBJECT_ID('tempdb..#ProductAffinity') IS NOT NULL DROP TABLE #ProductAffinity;
        IF OBJECT_ID('tempdb..#TimeSeriesAnalysis') IS NOT NULL DROP TABLE #TimeSeriesAnalysis;
        IF OBJECT_ID('tempdb..#SuspiciousTransactions') IS NOT NULL DROP TABLE #SuspiciousTransactions;
        
        -- Re-raise error
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
    
    RETURN @Success;
END;
GO

-- =============================================
-- SUPPORTING TABLES (should exist in database)
-- =============================================

/*
CREATE TABLE ProcessingLog (
    LogId BIGINT PRIMARY KEY IDENTITY(1,1),
    ProcessingId UNIQUEIDENTIFIER NOT NULL,
    ProcessType NVARCHAR(100),
    StartTime DATETIME,
    EndTime DATETIME,
    Status NVARCHAR(50),
    RecordsProcessed BIGINT,
    RecordsFailed BIGINT,
    DataQualityScore DECIMAL(5, 2),
    Parameters NVARCHAR(MAX),
    ErrorMessage NVARCHAR(MAX)
);

CREATE TABLE ErrorLog (
    ErrorId BIGINT PRIMARY KEY IDENTITY(1,1),
    ProcessingId UNIQUEIDENTIFIER,
    ErrorMessage NVARCHAR(MAX),
    ErrorSeverity INT,
    ErrorTime DATETIME DEFAULT GETDATE()
);

CREATE TABLE ArchiveCustomerMetrics (
    ArchiveId BIGINT PRIMARY KEY IDENTITY(1,1),
    ProcessingDate DATE,
    CustomerId INT,
    TotalOrders INT,
    TotalSpent DECIMAL(18, 2),
    AverageOrderValue DECIMAL(18, 2),
    ChurnProbability DECIMAL(5, 2),
    CustomerSegment NVARCHAR(50),
    ArchivedDate DATETIME DEFAULT GETDATE()
);

CREATE TABLE ArchiveDailyAggregates (
    ArchiveId BIGINT PRIMARY KEY IDENTITY(1,1),
    ProcessingDate DATE,
    AggregateDate DATE,
    TotalOrders INT,
    TotalRevenue DECIMAL(18, 2),
    TotalProfit DECIMAL(18, 2),
    AverageOrderValue DECIMAL(18, 2),
    NewCustomers INT,
    ArchivedDate DATETIME DEFAULT GETDATE()
);

CREATE TABLE ArchiveProductMetrics (
    ArchiveId BIGINT PRIMARY KEY IDENTITY(1,1),
    ProcessingDate DATE,
    ProductId INT,
    TotalQuantitySold INT,
    TotalRevenue DECIMAL(18, 2),
    TotalProfit DECIMAL(18, 2),
    ProfitMargin DECIMAL(5, 2),
    ArchivedDate DATETIME DEFAULT GETDATE()
);
*/

-- =============================================
-- SAMPLE USAGE
-- =============================================

/*
-- Run full processing with all features
EXEC sp_EnterpriseDataProcessingSystem
    @ProcessingDate = '2024-01-15',
    @BatchSize = 1000,
    @EnableLogging = 1,
    @EnableValidation = 1,
    @EnableArchiving = 1,
    @ProcessingMode = 'Incremental';

-- Run with custom parameters
EXEC sp_EnterpriseDataProcessingSystem
    @ProcessingDate = '2024-01-15',
    @BatchSize = 500,
    @EnableLogging = 1,
    @EnableValidation = 1,
    @EnableArchiving = 0,
    @ErrorThreshold = 50,
    @RetryAttempts = 5;
*/
