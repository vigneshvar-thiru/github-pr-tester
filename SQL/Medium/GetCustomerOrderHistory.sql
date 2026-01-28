-- Stored procedure to get customer order history
CREATE PROCEDURE GetCustomerOrderHistory
    @CustomerId INT,
    @StartDate DATETIME = NULL,
    @EndDate DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Set default dates if not provided
    IF @StartDate IS NULL
        SET @StartDate = DATEADD(YEAR, -1, GETDATE());
    
    IF @EndDate IS NULL
        SET @EndDate = GETDATE();

    -- Get customer orders with details
    SELECT 
        o.OrderId,
        o.OrderDate,
        o.Status,
        o.TotalAmount,
        c.CustomerName,
        c.Email,
        COUNT(oi.OrderItemId) AS ItemCount
    FROM Orders o
    INNER JOIN Customers c ON o.CustomerId = c.CustomerId
    LEFT JOIN OrderItems oi ON o.OrderId = oi.OrderId
    WHERE 
        o.CustomerId = @CustomerId
        AND o.OrderDate BETWEEN @StartDate AND @EndDate
    GROUP BY 
        o.OrderId,
        o.OrderDate,
        o.Status,
        o.TotalAmount,
        c.CustomerName,
        c.Email
    ORDER BY o.OrderDate DESC;

    -- Return summary statistics
    SELECT 
        COUNT(*) AS TotalOrders,
        SUM(TotalAmount) AS TotalSpent,
        AVG(TotalAmount) AS AverageOrderValue,
        MAX(OrderDate) AS LastOrderDate
    FROM Orders
    WHERE 
        CustomerId = @CustomerId
        AND OrderDate BETWEEN @StartDate AND @EndDate;
END;
