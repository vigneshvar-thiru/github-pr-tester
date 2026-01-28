-- =============================================
-- Comprehensive Analytics and Reporting System
-- Version: 2.0
-- Date: 2024-01-15
-- Description: Complete analytics stored procedure for comprehensive business intelligence
-- This procedure generates detailed reports, analytics, and insights for the e-commerce platform
-- =============================================

CREATE PROCEDURE sp_GenerateComprehensiveAnalytics
    @StartDate DATETIME,
    @EndDate DATETIME,
    @IncludeCustomerAnalysis BIT = 1,
    @IncludeProductAnalysis BIT = 1,
    @IncludeSalesAnalysis BIT = 1,
    @IncludeInventoryAnalysis BIT = 1,
    @IncludeFinancialAnalysis BIT = 1,
    @IncludeMarketingAnalysis BIT = 1,
    @IncludeForecastAnalysis BIT = 1,
    @MinimumOrderValue DECIMAL(18, 2) = 0,
    @CategoryFilter NVARCHAR(MAX) = NULL,
    @RegionFilter NVARCHAR(MAX) = NULL,
    @CustomerSegment NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- =============================================
    -- VARIABLE DECLARATIONS
    -- =============================================
    
    DECLARE @TotalOrders INT;
    DECLARE @TotalRevenue DECIMAL(18, 2);
    DECLARE @TotalProfit DECIMAL(18, 2);
    DECLARE @AverageOrderValue DECIMAL(18, 2);
    DECLARE @TotalCustomers INT;
    DECLARE @NewCustomers INT;
    DECLARE @ReturningCustomers INT;
    DECLARE @CustomerRetentionRate DECIMAL(5, 2);
    DECLARE @ChurnRate DECIMAL(5, 2);
    DECLARE @ConversionRate DECIMAL(5, 2);
    DECLARE @RevenueGrowthRate DECIMAL(5, 2);
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @ErrorSeverity INT;
    DECLARE @ErrorState INT;
    
    -- =============================================
    -- ERROR HANDLING AND VALIDATION
    -- =============================================
    
    BEGIN TRY
        -- Validate date range
        IF @StartDate IS NULL OR @EndDate IS NULL
            THROW 50100, 'Start date and end date are required', 1;
            
        IF @StartDate > @EndDate
            THROW 50101, 'Start date cannot be greater than end date', 1;
            
        IF DATEDIFF(DAY, @StartDate, @EndDate) > 365
            THROW 50102, 'Date range cannot exceed 365 days', 1;
        
        -- =============================================
        -- TEMPORARY TABLES FOR ANALYTICS
        -- =============================================
        
        -- Create temp table for filtered orders
        CREATE TABLE #FilteredOrders (
            OrderId INT,
            CustomerId INT,
            OrderDate DATETIME,
            TotalAmount DECIMAL(18, 2),
            SubtotalAmount DECIMAL(18, 2),
            TaxAmount DECIMAL(18, 2),
            ShippingAmount DECIMAL(18, 2),
            DiscountAmount DECIMAL(18, 2),
            OrderStatus NVARCHAR(20),
            PaymentStatus NVARCHAR(20),
            IsNewCustomer BIT,
            CustomerSegment NVARCHAR(50),
            Region NVARCHAR(50)
        );
        
        -- Create temp table for product performance
        CREATE TABLE #ProductPerformance (
            ProductId INT,
            ProductName NVARCHAR(200),
            CategoryId INT,
            CategoryName NVARCHAR(100),
            QuantitySold INT,
            Revenue DECIMAL(18, 2),
            Cost DECIMAL(18, 2),
            Profit DECIMAL(18, 2),
            ProfitMargin DECIMAL(5, 2),
            ReorderCount INT,
            ReturnCount INT,
            ReturnRate DECIMAL(5, 2),
            AverageRating DECIMAL(3, 2),
            ReviewCount INT
        );
        
        -- Create temp table for customer segments
        CREATE TABLE #CustomerSegments (
            CustomerId INT,
            CustomerName NVARCHAR(100),
            Email NVARCHAR(100),
            Segment NVARCHAR(50),
            TotalOrders INT,
            TotalSpent DECIMAL(18, 2),
            AverageOrderValue DECIMAL(18, 2),
            LastOrderDate DATETIME,
            DaysSinceLastOrder INT,
            LifetimeValue DECIMAL(18, 2),
            ChurnRisk DECIMAL(3, 2)
        );
        
        -- Create temp table for time series data
        CREATE TABLE #TimeSeriesData (
            DateKey DATE,
            OrderCount INT,
            Revenue DECIMAL(18, 2),
            NewCustomers INT,
            ReturningCustomers INT,
            AverageOrderValue DECIMAL(18, 2),
            ConversionRate DECIMAL(5, 2)
        );
        
        -- =============================================
        -- POPULATE FILTERED ORDERS
        -- =============================================
        
        INSERT INTO #FilteredOrders
        SELECT 
            o.OrderId,
            o.CustomerId,
            o.OrderDate,
            o.TotalAmount,
            o.SubtotalAmount,
            o.TaxAmount,
            o.ShippingAmount,
            o.DiscountAmount,
            o.OrderStatus,
            o.PaymentStatus,
            CASE 
                WHEN (SELECT COUNT(*) FROM Orders o2 
                      WHERE o2.CustomerId = o.CustomerId 
                      AND o2.OrderDate < o.OrderDate) = 0 
                THEN 1 
                ELSE 0 
            END AS IsNewCustomer,
            CASE 
                WHEN (SELECT SUM(TotalAmount) FROM Orders o3 
                      WHERE o3.CustomerId = o.CustomerId 
                      AND o3.OrderStatus = 'Delivered') >= 1000 
                THEN 'VIP'
                WHEN (SELECT COUNT(*) FROM Orders o4 
                      WHERE o4.CustomerId = o.CustomerId) >= 5 
                THEN 'Loyal'
                WHEN (SELECT COUNT(*) FROM Orders o5 
                      WHERE o5.CustomerId = o.CustomerId) = 1 
                THEN 'New'
                ELSE 'Regular'
            END AS CustomerSegment,
            COALESCE(ca.StateProvince, 'Unknown') AS Region
        FROM Orders o
        LEFT JOIN CustomerAddresses ca ON o.ShippingAddressId = ca.AddressId
        WHERE o.OrderDate BETWEEN @StartDate AND @EndDate
            AND o.TotalAmount >= @MinimumOrderValue
            AND (@CustomerSegment IS NULL OR 
                 CASE 
                    WHEN (SELECT SUM(TotalAmount) FROM Orders o3 
                          WHERE o3.CustomerId = o.CustomerId 
                          AND o3.OrderStatus = 'Delivered') >= 1000 
                    THEN 'VIP'
                    WHEN (SELECT COUNT(*) FROM Orders o4 
                          WHERE o4.CustomerId = o.CustomerId) >= 5 
                    THEN 'Loyal'
                    WHEN (SELECT COUNT(*) FROM Orders o5 
                          WHERE o5.CustomerId = o.CustomerId) = 1 
                    THEN 'New'
                    ELSE 'Regular'
                 END = @CustomerSegment);
        
        -- =============================================
        -- CUSTOMER ANALYSIS
        -- =============================================
        
        IF @IncludeCustomerAnalysis = 1
        BEGIN
            -- Populate customer segments
            INSERT INTO #CustomerSegments
            SELECT 
                c.CustomerId,
                c.FirstName + ' ' + c.LastName AS CustomerName,
                c.Email,
                CASE 
                    WHEN SUM(CASE WHEN o.OrderStatus = 'Delivered' THEN o.TotalAmount ELSE 0 END) >= 1000 THEN 'VIP'
                    WHEN COUNT(o.OrderId) >= 5 THEN 'Loyal'
                    WHEN COUNT(o.OrderId) = 1 THEN 'New'
                    ELSE 'Regular'
                END AS Segment,
                COUNT(o.OrderId) AS TotalOrders,
                SUM(CASE WHEN o.OrderStatus = 'Delivered' THEN o.TotalAmount ELSE 0 END) AS TotalSpent,
                AVG(CASE WHEN o.OrderStatus = 'Delivered' THEN o.TotalAmount ELSE NULL END) AS AverageOrderValue,
                MAX(o.OrderDate) AS LastOrderDate,
                DATEDIFF(DAY, MAX(o.OrderDate), GETDATE()) AS DaysSinceLastOrder,
                SUM(CASE WHEN o.OrderStatus = 'Delivered' THEN o.TotalAmount ELSE 0 END) AS LifetimeValue,
                CASE 
                    WHEN DATEDIFF(DAY, MAX(o.OrderDate), GETDATE()) > 90 THEN 0.8
                    WHEN DATEDIFF(DAY, MAX(o.OrderDate), GETDATE()) > 60 THEN 0.6
                    WHEN DATEDIFF(DAY, MAX(o.OrderDate), GETDATE()) > 30 THEN 0.4
                    ELSE 0.2
                END AS ChurnRisk
            FROM Customers c
            LEFT JOIN Orders o ON c.CustomerId = o.CustomerId
            WHERE o.OrderDate BETWEEN @StartDate AND @EndDate
            GROUP BY c.CustomerId, c.FirstName, c.LastName, c.Email;
            
            -- Customer analysis summary
            SELECT 'Customer Analysis Summary' AS ReportSection;
            
            SELECT 
                COUNT(DISTINCT CustomerId) AS TotalCustomers,
                COUNT(DISTINCT CASE WHEN Segment = 'New' THEN CustomerId END) AS NewCustomers,
                COUNT(DISTINCT CASE WHEN Segment = 'Loyal' THEN CustomerId END) AS LoyalCustomers,
                COUNT(DISTINCT CASE WHEN Segment = 'VIP' THEN CustomerId END) AS VIPCustomers,
                AVG(TotalSpent) AS AverageLifetimeValue,
                AVG(TotalOrders) AS AverageOrdersPerCustomer,
                AVG(DaysSinceLastOrder) AS AverageDaysSinceLastOrder,
                AVG(ChurnRisk) AS AverageChurnRisk
            FROM #CustomerSegments;
            
            -- Top customers by revenue
            SELECT TOP 20
                CustomerName,
                Email,
                Segment,
                TotalOrders,
                TotalSpent,
                AverageOrderValue,
                LastOrderDate,
                DaysSinceLastOrder,
                ChurnRisk
            FROM #CustomerSegments
            ORDER BY TotalSpent DESC;
            
            -- Customer distribution by segment
            SELECT 
                Segment,
                COUNT(*) AS CustomerCount,
                SUM(TotalSpent) AS TotalRevenue,
                AVG(TotalSpent) AS AverageSpent,
                AVG(TotalOrders) AS AverageOrders,
                AVG(ChurnRisk) AS AverageChurnRisk
            FROM #CustomerSegments
            GROUP BY Segment
            ORDER BY TotalRevenue DESC;
            
            -- At-risk customers (high churn risk)
            SELECT 
                CustomerName,
                Email,
                Segment,
                TotalOrders,
                TotalSpent,
                LastOrderDate,
                DaysSinceLastOrder,
                ChurnRisk
            FROM #CustomerSegments
            WHERE ChurnRisk >= 0.6
            ORDER BY ChurnRisk DESC, TotalSpent DESC;
        END;
        
        -- =============================================
        -- PRODUCT ANALYSIS
        -- =============================================
        
        IF @IncludeProductAnalysis = 1
        BEGIN
            -- Populate product performance
            INSERT INTO #ProductPerformance
            SELECT 
                p.ProductId,
                p.ProductName,
                p.CategoryId,
                c.CategoryName,
                SUM(oi.Quantity) AS QuantitySold,
                SUM(oi.TotalAmount) AS Revenue,
                SUM(oi.Quantity * COALESCE(p.CostPrice, 0)) AS Cost,
                SUM(oi.TotalAmount) - SUM(oi.Quantity * COALESCE(p.CostPrice, 0)) AS Profit,
                CASE 
                    WHEN SUM(oi.TotalAmount) > 0 
                    THEN ((SUM(oi.TotalAmount) - SUM(oi.Quantity * COALESCE(p.CostPrice, 0))) / SUM(oi.TotalAmount)) * 100
                    ELSE 0 
                END AS ProfitMargin,
                COUNT(DISTINCT oi.OrderId) AS ReorderCount,
                0 AS ReturnCount, -- Placeholder
                0.00 AS ReturnRate, -- Placeholder
                COALESCE((SELECT AVG(CAST(Rating AS DECIMAL(3,2))) 
                         FROM ProductReviews pr 
                         WHERE pr.ProductId = p.ProductId 
                         AND pr.IsApproved = 1), 0) AS AverageRating,
                COALESCE((SELECT COUNT(*) 
                         FROM ProductReviews pr 
                         WHERE pr.ProductId = p.ProductId 
                         AND pr.IsApproved = 1), 0) AS ReviewCount
            FROM Products p
            INNER JOIN Categories c ON p.CategoryId = c.CategoryId
            LEFT JOIN OrderItems oi ON p.ProductId = oi.ProductId
            LEFT JOIN #FilteredOrders fo ON oi.OrderId = fo.OrderId
            WHERE fo.OrderId IS NOT NULL
            GROUP BY p.ProductId, p.ProductName, p.CategoryId, c.CategoryName;
            
            -- Product analysis summary
            SELECT 'Product Analysis Summary' AS ReportSection;
            
            SELECT 
                COUNT(DISTINCT ProductId) AS TotalProducts,
                SUM(QuantitySold) AS TotalQuantitySold,
                SUM(Revenue) AS TotalRevenue,
                SUM(Profit) AS TotalProfit,
                AVG(ProfitMargin) AS AverageProfitMargin,
                AVG(AverageRating) AS OverallAverageRating,
                SUM(ReviewCount) AS TotalReviews
            FROM #ProductPerformance;
            
            -- Top products by revenue
            SELECT TOP 30
                ProductName,
                CategoryName,
                QuantitySold,
                Revenue,
                Profit,
                ProfitMargin,
                AverageRating,
                ReviewCount
            FROM #ProductPerformance
            ORDER BY Revenue DESC;
            
            -- Top products by quantity sold
            SELECT TOP 30
                ProductName,
                CategoryName,
                QuantitySold,
                Revenue,
                AverageRating,
                ReviewCount
            FROM #ProductPerformance
            ORDER BY QuantitySold DESC;
            
            -- Top products by profit margin
            SELECT TOP 20
                ProductName,
                CategoryName,
                Revenue,
                Profit,
                ProfitMargin,
                QuantitySold
            FROM #ProductPerformance
            WHERE Revenue > 100
            ORDER BY ProfitMargin DESC;
            
            -- Category performance
            SELECT 
                CategoryName,
                COUNT(DISTINCT ProductId) AS ProductCount,
                SUM(QuantitySold) AS TotalQuantitySold,
                SUM(Revenue) AS TotalRevenue,
                SUM(Profit) AS TotalProfit,
                AVG(ProfitMargin) AS AverageProfitMargin,
                AVG(AverageRating) AS AverageRating
            FROM #ProductPerformance
            GROUP BY CategoryName
            ORDER BY TotalRevenue DESC;
            
            -- Low performing products
            SELECT 
                ProductName,
                CategoryName,
                QuantitySold,
                Revenue,
                Profit,
                ProfitMargin
            FROM #ProductPerformance
            WHERE Revenue < (SELECT AVG(Revenue) * 0.5 FROM #ProductPerformance)
            ORDER BY Revenue ASC;
        END;
        
        -- =============================================
        -- SALES ANALYSIS
        -- =============================================
        
        IF @IncludeSalesAnalysis = 1
        BEGIN
            -- Overall sales metrics
            SELECT 'Sales Analysis Summary' AS ReportSection;
            
            SELECT 
                COUNT(*) AS TotalOrders,
                COUNT(CASE WHEN OrderStatus = 'Delivered' THEN 1 END) AS DeliveredOrders,
                COUNT(CASE WHEN OrderStatus = 'Cancelled' THEN 1 END) AS CancelledOrders,
                COUNT(CASE WHEN OrderStatus = 'Pending' THEN 1 END) AS PendingOrders,
                SUM(TotalAmount) AS TotalRevenue,
                SUM(CASE WHEN OrderStatus = 'Delivered' THEN TotalAmount ELSE 0 END) AS DeliveredRevenue,
                AVG(TotalAmount) AS AverageOrderValue,
                SUM(DiscountAmount) AS TotalDiscounts,
                SUM(TaxAmount) AS TotalTax,
                SUM(ShippingAmount) AS TotalShipping,
                AVG(DiscountAmount) AS AverageDiscount,
                COUNT(DISTINCT CustomerId) AS UniqueCustomers,
                SUM(CASE WHEN IsNewCustomer = 1 THEN 1 ELSE 0 END) AS OrdersFromNewCustomers,
                SUM(CASE WHEN IsNewCustomer = 0 THEN 1 ELSE 0 END) AS OrdersFromReturningCustomers
            FROM #FilteredOrders;
            
            -- Populate time series data
            INSERT INTO #TimeSeriesData
            SELECT 
                CAST(OrderDate AS DATE) AS DateKey,
                COUNT(*) AS OrderCount,
                SUM(TotalAmount) AS Revenue,
                SUM(CASE WHEN IsNewCustomer = 1 THEN 1 ELSE 0 END) AS NewCustomers,
                SUM(CASE WHEN IsNewCustomer = 0 THEN 1 ELSE 0 END) AS ReturningCustomers,
                AVG(TotalAmount) AS AverageOrderValue,
                0.00 AS ConversionRate -- Placeholder
            FROM #FilteredOrders
            GROUP BY CAST(OrderDate AS DATE);
            
            -- Daily sales trend
            SELECT 
                DateKey,
                OrderCount,
                Revenue,
                NewCustomers,
                ReturningCustomers,
                AverageOrderValue
            FROM #TimeSeriesData
            ORDER BY DateKey;
            
            -- Weekly sales aggregation
            SELECT 
                DATEPART(YEAR, DateKey) AS Year,
                DATEPART(WEEK, DateKey) AS Week,
                MIN(DateKey) AS WeekStartDate,
                SUM(OrderCount) AS TotalOrders,
                SUM(Revenue) AS TotalRevenue,
                AVG(AverageOrderValue) AS AverageOrderValue,
                SUM(NewCustomers) AS NewCustomers,
                SUM(ReturningCustomers) AS ReturningCustomers
            FROM #TimeSeriesData
            GROUP BY DATEPART(YEAR, DateKey), DATEPART(WEEK, DateKey)
            ORDER BY Year, Week;
            
            -- Monthly sales aggregation
            SELECT 
                DATEPART(YEAR, DateKey) AS Year,
                DATEPART(MONTH, DateKey) AS Month,
                DATENAME(MONTH, DateKey) AS MonthName,
                SUM(OrderCount) AS TotalOrders,
                SUM(Revenue) AS TotalRevenue,
                AVG(AverageOrderValue) AS AverageOrderValue,
                SUM(NewCustomers) AS NewCustomers,
                SUM(ReturningCustomers) AS ReturningCustomers
            FROM #TimeSeriesData
            GROUP BY DATEPART(YEAR, DateKey), DATEPART(MONTH, DateKey), DATENAME(MONTH, DateKey)
            ORDER BY Year, Month;
            
            -- Day of week analysis
            SELECT 
                DATENAME(WEEKDAY, DateKey) AS DayOfWeek,
                DATEPART(WEEKDAY, DateKey) AS DayNumber,
                AVG(OrderCount) AS AverageOrders,
                AVG(Revenue) AS AverageRevenue,
                SUM(OrderCount) AS TotalOrders,
                SUM(Revenue) AS TotalRevenue
            FROM #TimeSeriesData
            GROUP BY DATENAME(WEEKDAY, DateKey), DATEPART(WEEKDAY, DateKey)
            ORDER BY DayNumber;
            
            -- Hour of day analysis (if time data available)
            SELECT 
                DATEPART(HOUR, OrderDate) AS HourOfDay,
                COUNT(*) AS OrderCount,
                SUM(TotalAmount) AS Revenue,
                AVG(TotalAmount) AS AverageOrderValue
            FROM #FilteredOrders
            GROUP BY DATEPART(HOUR, OrderDate)
            ORDER BY HourOfDay;
            
            -- Sales by region
            SELECT 
                Region,
                COUNT(*) AS OrderCount,
                SUM(TotalAmount) AS Revenue,
                AVG(TotalAmount) AS AverageOrderValue,
                COUNT(DISTINCT CustomerId) AS UniqueCustomers
            FROM #FilteredOrders
            GROUP BY Region
            ORDER BY Revenue DESC;
            
            -- Sales by customer segment
            SELECT 
                CustomerSegment,
                COUNT(*) AS OrderCount,
                SUM(TotalAmount) AS Revenue,
                AVG(TotalAmount) AS AverageOrderValue,
                COUNT(DISTINCT CustomerId) AS UniqueCustomers
            FROM #FilteredOrders
            GROUP BY CustomerSegment
            ORDER BY Revenue DESC;
            
            -- Payment status analysis
            SELECT 
                PaymentStatus,
                COUNT(*) AS OrderCount,
                SUM(TotalAmount) AS TotalAmount,
                AVG(TotalAmount) AS AverageAmount
            FROM #FilteredOrders
            GROUP BY PaymentStatus
            ORDER BY OrderCount DESC;
        END;
        
        -- =============================================
        -- INVENTORY ANALYSIS
        -- =============================================
        
        IF @IncludeInventoryAnalysis = 1
        BEGIN
            SELECT 'Inventory Analysis Summary' AS ReportSection;
            
            -- Current inventory status
            SELECT 
                COUNT(*) AS TotalProducts,
                SUM(i.QuantityInStock) AS TotalUnitsInStock,
                SUM(i.QuantityInStock * p.UnitPrice) AS TotalInventoryValue,
                SUM(i.QuantityInStock * COALESCE(p.CostPrice, 0)) AS TotalInventoryCost,
                COUNT(CASE WHEN i.QuantityInStock = 0 THEN 1 END) AS OutOfStockProducts,
                COUNT(CASE WHEN i.QuantityInStock <= i.ReorderLevel THEN 1 END) AS LowStockProducts,
                AVG(i.QuantityInStock) AS AverageStockLevel
            FROM Inventory i
            INNER JOIN Products p ON i.ProductId = p.ProductId
            WHERE p.IsActive = 1;
            
            -- Products requiring reorder
            SELECT 
                p.ProductName,
                c.CategoryName,
                i.QuantityInStock,
                i.ReorderLevel,
                i.ReorderQuantity,
                p.UnitPrice,
                i.QuantityInStock * p.UnitPrice AS CurrentValue,
                CASE 
                    WHEN i.QuantityInStock = 0 THEN 'OUT_OF_STOCK'
                    WHEN i.QuantityInStock <= i.ReorderLevel THEN 'LOW_STOCK'
                    ELSE 'ADEQUATE'
                END AS StockStatus,
                DATEDIFF(DAY, i.LastRestockDate, GETDATE()) AS DaysSinceRestock
            FROM Inventory i
            INNER JOIN Products p ON i.ProductId = p.ProductId
            INNER JOIN Categories c ON p.CategoryId = c.CategoryId
            WHERE i.QuantityInStock <= i.ReorderLevel
                AND p.IsActive = 1
            ORDER BY i.QuantityInStock ASC;
            
            -- Inventory turnover analysis
            SELECT 
                p.ProductId,
                p.ProductName,
                c.CategoryName,
                i.QuantityInStock,
                COALESCE(pp.QuantitySold, 0) AS QuantitySold,
                CASE 
                    WHEN i.QuantityInStock > 0 
                    THEN COALESCE(pp.QuantitySold, 0) / CAST(i.QuantityInStock AS DECIMAL(10,2))
                    ELSE 0 
                END AS TurnoverRatio,
                CASE 
                    WHEN COALESCE(pp.QuantitySold, 0) > 0 
                    THEN DATEDIFF(DAY, @StartDate, @EndDate) / (COALESCE(pp.QuantitySold, 0) / CAST(NULLIF(i.QuantityInStock, 0) AS DECIMAL(10,2)))
                    ELSE NULL 
                END AS DaysOfInventory
            FROM Inventory i
            INNER JOIN Products p ON i.ProductId = p.ProductId
            INNER JOIN Categories c ON p.CategoryId = c.CategoryId
            LEFT JOIN #ProductPerformance pp ON p.ProductId = pp.ProductId
            WHERE p.IsActive = 1
            ORDER BY TurnoverRatio DESC;
            
            -- Slow-moving inventory
            SELECT 
                p.ProductName,
                c.CategoryName,
                i.QuantityInStock,
                i.QuantityInStock * p.UnitPrice AS InventoryValue,
                COALESCE(pp.QuantitySold, 0) AS QuantitySold,
                DATEDIFF(DAY, i.LastRestockDate, GETDATE()) AS DaysSinceRestock
            FROM Inventory i
            INNER JOIN Products p ON i.ProductId = p.ProductId
            INNER JOIN Categories c ON p.CategoryId = c.CategoryId
            LEFT JOIN #ProductPerformance pp ON p.ProductId = pp.ProductId
            WHERE p.IsActive = 1
                AND i.QuantityInStock > 0
                AND (COALESCE(pp.QuantitySold, 0) = 0 OR 
                     COALESCE(pp.QuantitySold, 0) < i.QuantityInStock * 0.1)
            ORDER BY InventoryValue DESC;
        END;
        
        -- =============================================
        -- FINANCIAL ANALYSIS
        -- =============================================
        
        IF @IncludeFinancialAnalysis = 1
        BEGIN
            SELECT 'Financial Analysis Summary' AS ReportSection;
            
            -- Revenue and profit summary
            SELECT 
                SUM(fo.TotalAmount) AS TotalRevenue,
                SUM(fo.SubtotalAmount) AS TotalSubtotal,
                SUM(fo.TaxAmount) AS TotalTax,
                SUM(fo.ShippingAmount) AS TotalShipping,
                SUM(fo.DiscountAmount) AS TotalDiscounts,
                SUM(CASE WHEN pp.Profit IS NOT NULL THEN pp.Profit ELSE 0 END) AS TotalProfit,
                CASE 
                    WHEN SUM(fo.TotalAmount) > 0 
                    THEN (SUM(CASE WHEN pp.Profit IS NOT NULL THEN pp.Profit ELSE 0 END) / SUM(fo.TotalAmount)) * 100
                    ELSE 0 
                END AS OverallProfitMargin,
                AVG(fo.TotalAmount) AS AverageTransactionValue,
                COUNT(DISTINCT fo.CustomerId) AS ActiveCustomers,
                SUM(fo.TotalAmount) / NULLIF(COUNT(DISTINCT fo.CustomerId), 0) AS RevenuePerCustomer
            FROM #FilteredOrders fo
            LEFT JOIN OrderItems oi ON fo.OrderId = oi.OrderId
            LEFT JOIN #ProductPerformance pp ON oi.ProductId = pp.ProductId;
            
            -- Revenue breakdown by component
            SELECT 
                SUM(SubtotalAmount) AS SubtotalRevenue,
                SUM(SubtotalAmount) / NULLIF(SUM(TotalAmount), 0) * 100 AS SubtotalPercentage,
                SUM(TaxAmount) AS TaxRevenue,
                SUM(TaxAmount) / NULLIF(SUM(TotalAmount), 0) * 100 AS TaxPercentage,
                SUM(ShippingAmount) AS ShippingRevenue,
                SUM(ShippingAmount) / NULLIF(SUM(TotalAmount), 0) * 100 AS ShippingPercentage,
                SUM(DiscountAmount) AS DiscountAmount,
                SUM(DiscountAmount) / NULLIF(SUM(SubtotalAmount), 0) * 100 AS DiscountPercentage
            FROM #FilteredOrders;
            
            -- Monthly financial trend
            SELECT 
                DATEPART(YEAR, OrderDate) AS Year,
                DATEPART(MONTH, OrderDate) AS Month,
                DATENAME(MONTH, OrderDate) AS MonthName,
                COUNT(*) AS OrderCount,
                SUM(TotalAmount) AS Revenue,
                SUM(SubtotalAmount) AS Subtotal,
                SUM(TaxAmount) AS Tax,
                SUM(ShippingAmount) AS Shipping,
                SUM(DiscountAmount) AS Discounts,
                AVG(TotalAmount) AS AverageOrderValue
            FROM #FilteredOrders
            GROUP BY DATEPART(YEAR, OrderDate), DATEPART(MONTH, OrderDate), DATENAME(MONTH, OrderDate)
            ORDER BY Year, Month;
            
            -- Discount effectiveness analysis
            SELECT 
                CASE 
                    WHEN DiscountAmount = 0 THEN 'No Discount'
                    WHEN DiscountAmount <= 10 THEN '$1-$10'
                    WHEN DiscountAmount <= 25 THEN '$11-$25'
                    WHEN DiscountAmount <= 50 THEN '$26-$50'
                    ELSE 'Over $50'
                END AS DiscountRange,
                COUNT(*) AS OrderCount,
                SUM(TotalAmount) AS Revenue,
                AVG(TotalAmount) AS AverageOrderValue,
                SUM(DiscountAmount) AS TotalDiscount,
                AVG(DiscountAmount) AS AverageDiscount
            FROM #FilteredOrders
            GROUP BY 
                CASE 
                    WHEN DiscountAmount = 0 THEN 'No Discount'
                    WHEN DiscountAmount <= 10 THEN '$1-$10'
                    WHEN DiscountAmount <= 25 THEN '$11-$25'
                    WHEN DiscountAmount <= 50 THEN '$26-$50'
                    ELSE 'Over $50'
                END
            ORDER BY AverageOrderValue DESC;
            
            -- Revenue by order value ranges
            SELECT 
                CASE 
                    WHEN TotalAmount < 50 THEN 'Under $50'
                    WHEN TotalAmount < 100 THEN '$50-$100'
                    WHEN TotalAmount < 200 THEN '$100-$200'
                    WHEN TotalAmount < 500 THEN '$200-$500'
                    ELSE 'Over $500'
                END AS OrderValueRange,
                COUNT(*) AS OrderCount,
                SUM(TotalAmount) AS TotalRevenue,
                AVG(TotalAmount) AS AverageOrderValue,
                COUNT(*) * 100.0 / (SELECT COUNT(*) FROM #FilteredOrders) AS PercentageOfOrders,
                SUM(TotalAmount) * 100.0 / (SELECT SUM(TotalAmount) FROM #FilteredOrders) AS PercentageOfRevenue
            FROM #FilteredOrders
            GROUP BY 
                CASE 
                    WHEN TotalAmount < 50 THEN 'Under $50'
                    WHEN TotalAmount < 100 THEN '$50-$100'
                    WHEN TotalAmount < 200 THEN '$100-$200'
                    WHEN TotalAmount < 500 THEN '$200-$500'
                    ELSE 'Over $500'
                END
            ORDER BY AverageOrderValue;
        END;
        
        -- =============================================
        -- MARKETING ANALYSIS
        -- =============================================
        
        IF @IncludeMarketingAnalysis = 1
        BEGIN
            SELECT 'Marketing Analysis Summary' AS ReportSection;
            
            -- Customer acquisition analysis
            SELECT 
                DATEPART(YEAR, OrderDate) AS Year,
                DATEPART(MONTH, OrderDate) AS Month,
                COUNT(DISTINCT CASE WHEN IsNewCustomer = 1 THEN CustomerId END) AS NewCustomers,
                COUNT(DISTINCT CASE WHEN IsNewCustomer = 0 THEN CustomerId END) AS ReturningCustomers,
                COUNT(DISTINCT CustomerId) AS TotalCustomers,
                SUM(CASE WHEN IsNewCustomer = 1 THEN TotalAmount ELSE 0 END) AS NewCustomerRevenue,
                SUM(CASE WHEN IsNewCustomer = 0 THEN TotalAmount ELSE 0 END) AS ReturningCustomerRevenue,
                AVG(CASE WHEN IsNewCustomer = 1 THEN TotalAmount END) AS NewCustomerAOV,
                AVG(CASE WHEN IsNewCustomer = 0 THEN TotalAmount END) AS ReturningCustomerAOV
            FROM #FilteredOrders
            GROUP BY DATEPART(YEAR, OrderDate), DATEPART(MONTH, OrderDate)
            ORDER BY Year, Month;
            
            -- Discount code usage analysis
            SELECT 
                dc.Code,
                dc.Description,
                dc.DiscountType,
                dc.DiscountValue,
                dc.UsageCount,
                COUNT(DISTINCT fo.OrderId) AS OrdersWithDiscount,
                SUM(fo.DiscountAmount) AS TotalDiscountGiven,
                SUM(fo.TotalAmount) AS RevenueGenerated,
                AVG(fo.TotalAmount) AS AverageOrderValue
            FROM DiscountCodes dc
            LEFT JOIN #FilteredOrders fo ON fo.DiscountAmount > 0
            WHERE dc.IsActive = 1
                AND dc.StartDate <= @EndDate
                AND (dc.EndDate IS NULL OR dc.EndDate >= @StartDate)
            GROUP BY dc.Code, dc.Description, dc.DiscountType, dc.DiscountValue, dc.UsageCount
            ORDER BY RevenueGenerated DESC;
            
            -- Product review analysis
            SELECT 
                COUNT(*) AS TotalReviews,
                AVG(CAST(Rating AS DECIMAL(3,2))) AS AverageRating,
                COUNT(CASE WHEN Rating = 5 THEN 1 END) AS FiveStarReviews,
                COUNT(CASE WHEN Rating = 4 THEN 1 END) AS FourStarReviews,
                COUNT(CASE WHEN Rating = 3 THEN 1 END) AS ThreeStarReviews,
                COUNT(CASE WHEN Rating = 2 THEN 1 END) AS TwoStarReviews,
                COUNT(CASE WHEN Rating = 1 THEN 1 END) AS OneStarReviews,
                COUNT(CASE WHEN IsVerifiedPurchase = 1 THEN 1 END) AS VerifiedPurchaseReviews,
                AVG(HelpfulCount) AS AverageHelpfulCount
            FROM ProductReviews
            WHERE CreatedDate BETWEEN @StartDate AND @EndDate;
            
            -- Top reviewed products
            SELECT TOP 20
                p.ProductName,
                c.CategoryName,
                COUNT(pr.ReviewId) AS ReviewCount,
                AVG(CAST(pr.Rating AS DECIMAL(3,2))) AS AverageRating,
                SUM(pr.HelpfulCount) AS TotalHelpfulVotes,
                COUNT(CASE WHEN pr.IsVerifiedPurchase = 1 THEN 1 END) AS VerifiedReviews
            FROM Products p
            INNER JOIN Categories c ON p.CategoryId = c.CategoryId
            INNER JOIN ProductReviews pr ON p.ProductId = pr.ProductId
            WHERE pr.CreatedDate BETWEEN @StartDate AND @EndDate
                AND pr.IsApproved = 1
            GROUP BY p.ProductName, c.CategoryName
            ORDER BY ReviewCount DESC;
        END;
        
        -- =============================================
        -- FORECAST ANALYSIS
        -- =============================================
        
        IF @IncludeForecastAnalysis = 1
        BEGIN
            SELECT 'Forecast Analysis' AS ReportSection;
            
            DECLARE @DaysInPeriod INT = DATEDIFF(DAY, @StartDate, @EndDate);
            DECLARE @AverageDailyRevenue DECIMAL(18, 2);
            DECLARE @AverageDailyOrders INT;
            DECLARE @GrowthRate DECIMAL(5, 2);
            
            -- Calculate averages
            SELECT 
                @AverageDailyRevenue = AVG(Revenue),
                @AverageDailyOrders = AVG(OrderCount)
            FROM #TimeSeriesData;
            
            -- Calculate growth rate (comparing first and last week)
            WITH FirstWeekData AS (
                SELECT AVG(Revenue) AS AvgRevenue
                FROM #TimeSeriesData
                WHERE DateKey BETWEEN @StartDate AND DATEADD(DAY, 7, @StartDate)
            ),
            LastWeekData AS (
                SELECT AVG(Revenue) AS AvgRevenue
                FROM #TimeSeriesData
                WHERE DateKey BETWEEN DATEADD(DAY, -7, @EndDate) AND @EndDate
            )
            SELECT @GrowthRate = 
                CASE 
                    WHEN f.AvgRevenue > 0 
                    THEN ((l.AvgRevenue - f.AvgRevenue) / f.AvgRevenue) * 100
                    ELSE 0 
                END
            FROM FirstWeekData f, LastWeekData l;
            
            -- Forecast summary
            SELECT 
                @AverageDailyRevenue AS AverageDailyRevenue,
                @AverageDailyOrders AS AverageDailyOrders,
                @GrowthRate AS WeeklyGrowthRate,
                @AverageDailyRevenue * 30 AS ProjectedMonthlyRevenue,
                @AverageDailyRevenue * 365 AS ProjectedAnnualRevenue,
                @AverageDailyOrders * 30 AS ProjectedMonthlyOrders,
                @AverageDailyOrders * 365 AS ProjectedAnnualOrders;
            
            -- Seasonal patterns
            SELECT 
                DATENAME(MONTH, DateKey) AS Month,
                DATEPART(MONTH, DateKey) AS MonthNumber,
                AVG(Revenue) AS AverageRevenue,
                AVG(OrderCount) AS AverageOrders,
                MAX(Revenue) AS PeakRevenue,
                MIN(Revenue) AS LowestRevenue
            FROM #TimeSeriesData
            GROUP BY DATENAME(MONTH, DateKey), DATEPART(MONTH, DateKey)
            ORDER BY MonthNumber;
            
            -- Day of week patterns for forecasting
            SELECT 
                DATENAME(WEEKDAY, DateKey) AS DayOfWeek,
                DATEPART(WEEKDAY, DateKey) AS DayNumber,
                AVG(Revenue) AS AverageRevenue,
                AVG(OrderCount) AS AverageOrders,
                STDEV(Revenue) AS RevenueStdDev,
                STDEV(OrderCount) AS OrdersStdDev
            FROM #TimeSeriesData
            GROUP BY DATENAME(WEEKDAY, DateKey), DATEPART(WEEKDAY, DateKey)
            ORDER BY DayNumber;
        END;
        
        -- =============================================
        -- COHORT ANALYSIS
        -- =============================================
        
        SELECT 'Cohort Analysis' AS ReportSection;
        
        -- Customer cohort by first purchase month
        WITH CustomerCohorts AS (
            SELECT 
                c.CustomerId,
                DATEADD(MONTH, DATEDIFF(MONTH, 0, MIN(o.OrderDate)), 0) AS CohortMonth,
                COUNT(o.OrderId) AS TotalOrders,
                SUM(o.TotalAmount) AS TotalSpent
            FROM Customers c
            INNER JOIN Orders o ON c.CustomerId = o.CustomerId
            WHERE o.OrderDate BETWEEN @StartDate AND @EndDate
            GROUP BY c.CustomerId
        )
        SELECT 
            FORMAT(CohortMonth, 'yyyy-MM') AS Cohort,
            COUNT(DISTINCT CustomerId) AS CustomersInCohort,
            AVG(TotalOrders) AS AverageOrdersPerCustomer,
            AVG(TotalSpent) AS AverageSpendPerCustomer,
            SUM(TotalSpent) AS TotalCohortRevenue
        FROM CustomerCohorts
        GROUP BY CohortMonth
        ORDER BY CohortMonth;
        
        -- =============================================
        -- EXECUTIVE SUMMARY
        -- =============================================
        
        SELECT 'Executive Summary' AS ReportSection;
        
        SELECT 
            COUNT(DISTINCT fo.OrderId) AS TotalOrders,
            COUNT(DISTINCT fo.CustomerId) AS TotalCustomers,
            SUM(fo.TotalAmount) AS TotalRevenue,
            AVG(fo.TotalAmount) AS AverageOrderValue,
            SUM(fo.DiscountAmount) AS TotalDiscounts,
            COUNT(DISTINCT CASE WHEN fo.IsNewCustomer = 1 THEN fo.CustomerId END) AS NewCustomers,
            COUNT(DISTINCT CASE WHEN fo.IsNewCustomer = 0 THEN fo.CustomerId END) AS ReturningCustomers,
            CASE 
                WHEN COUNT(DISTINCT fo.CustomerId) > 0 
                THEN (COUNT(DISTINCT CASE WHEN fo.IsNewCustomer = 0 THEN fo.CustomerId END) * 100.0 / COUNT(DISTINCT fo.CustomerId))
                ELSE 0 
            END AS RetentionRate,
            (SELECT COUNT(DISTINCT ProductId) FROM #ProductPerformance) AS ProductsSold,
            (SELECT SUM(QuantitySold) FROM #ProductPerformance) AS TotalUnitsSold,
            DATEDIFF(DAY, @StartDate, @EndDate) AS DaysInPeriod,
            SUM(fo.TotalAmount) / NULLIF(DATEDIFF(DAY, @StartDate, @EndDate), 0) AS AverageDailyRevenue
        FROM #FilteredOrders fo;
        
        -- =============================================
        -- CLEANUP
        -- =============================================
        
        DROP TABLE #FilteredOrders;
        DROP TABLE #ProductPerformance;
        DROP TABLE #CustomerSegments;
        DROP TABLE #TimeSeriesData;
        
    END TRY
    BEGIN CATCH
        SELECT @ErrorMessage = ERROR_MESSAGE(),
               @ErrorSeverity = ERROR_SEVERITY(),
               @ErrorState = ERROR_STATE();
        
        -- Clean up temp tables if they exist
        IF OBJECT_ID('tempdb..#FilteredOrders') IS NOT NULL
            DROP TABLE #FilteredOrders;
        IF OBJECT_ID('tempdb..#ProductPerformance') IS NOT NULL
            DROP TABLE #ProductPerformance;
        IF OBJECT_ID('tempdb..#CustomerSegments') IS NOT NULL
            DROP TABLE #CustomerSegments;
        IF OBJECT_ID('tempdb..#TimeSeriesData') IS NOT NULL
            DROP TABLE #TimeSeriesData;
        
        -- Re-throw the error
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH;
END;
GO

-- =============================================
-- SAMPLE USAGE
-- =============================================

/*
-- Run comprehensive analytics for the last 30 days
EXEC sp_GenerateComprehensiveAnalytics 
    @StartDate = '2024-01-01',
    @EndDate = '2024-01-31',
    @IncludeCustomerAnalysis = 1,
    @IncludeProductAnalysis = 1,
    @IncludeSalesAnalysis = 1,
    @IncludeInventoryAnalysis = 1,
    @IncludeFinancialAnalysis = 1,
    @IncludeMarketingAnalysis = 1,
    @IncludeForecastAnalysis = 1;

-- Run sales analysis only for high-value orders
EXEC sp_GenerateComprehensiveAnalytics 
    @StartDate = '2024-01-01',
    @EndDate = '2024-01-31',
    @IncludeCustomerAnalysis = 0,
    @IncludeProductAnalysis = 0,
    @IncludeSalesAnalysis = 1,
    @IncludeInventoryAnalysis = 0,
    @IncludeFinancialAnalysis = 1,
    @IncludeMarketingAnalysis = 0,
    @IncludeForecastAnalysis = 0,
    @MinimumOrderValue = 100;

-- Run analysis for VIP customers only
EXEC sp_GenerateComprehensiveAnalytics 
    @StartDate = '2024-01-01',
    @EndDate = '2024-01-31',
    @CustomerSegment = 'VIP';
*/
