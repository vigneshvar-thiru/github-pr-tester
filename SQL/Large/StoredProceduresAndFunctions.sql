-- =============================================
-- Advanced Stored Procedures and Functions
-- E-Commerce Database - Business Logic Layer
-- Version: 1.0
-- =============================================

-- =============================================
-- CUSTOMER MANAGEMENT PROCEDURES
-- =============================================

-- Procedure to register a new customer
CREATE PROCEDURE sp_RegisterCustomer
    @Username NVARCHAR(50),
    @Email NVARCHAR(100),
    @PasswordHash NVARCHAR(255),
    @FirstName NVARCHAR(50),
    @LastName NVARCHAR(50),
    @PhoneNumber NVARCHAR(20) = NULL,
    @DateOfBirth DATE = NULL,
    @CustomerId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validate inputs
        IF @Username IS NULL OR LEN(@Username) < 3
            THROW 50001, 'Username must be at least 3 characters long', 1;

        IF @Email IS NULL OR @Email NOT LIKE '%@%.%'
            THROW 50002, 'Invalid email format', 1;

        -- Check if username or email already exists
        IF EXISTS (SELECT 1 FROM Customers WHERE Username = @Username)
            THROW 50003, 'Username already exists', 1;

        IF EXISTS (SELECT 1 FROM Customers WHERE Email = @Email)
            THROW 50004, 'Email already registered', 1;

        -- Insert new customer
        INSERT INTO Customers (Username, Email, PasswordHash, FirstName, LastName, PhoneNumber, DateOfBirth)
        VALUES (@Username, @Email, @PasswordHash, @FirstName, @LastName, @PhoneNumber, @DateOfBirth);

        SET @CustomerId = SCOPE_IDENTITY();

        -- Log the registration
        INSERT INTO AuditLog (TableName, RecordId, Action, NewValues, UserName)
        VALUES ('Customers', @CustomerId, 'INSERT', 
                CONCAT('Username: ', @Username, ', Email: ', @Email), @Username);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- Procedure to authenticate customer login
CREATE PROCEDURE sp_AuthenticateCustomer
    @Username NVARCHAR(50),
    @PasswordHash NVARCHAR(255),
    @SessionId UNIQUEIDENTIFIER OUTPUT,
    @CustomerId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @IsActive BIT;
        DECLARE @AccountLockedUntil DATETIME;
        DECLARE @FailedAttempts INT;

        -- Get customer details
        SELECT 
            @CustomerId = CustomerId,
            @IsActive = IsActive,
            @AccountLockedUntil = AccountLockedUntil,
            @FailedAttempts = FailedLoginAttempts
        FROM Customers
        WHERE Username = @Username AND PasswordHash = @PasswordHash;

        -- Check if customer exists
        IF @CustomerId IS NULL
        BEGIN
            -- Increment failed login attempts
            UPDATE Customers
            SET FailedLoginAttempts = FailedLoginAttempts + 1,
                AccountLockedUntil = CASE 
                    WHEN FailedLoginAttempts >= 4 THEN DATEADD(MINUTE, 30, GETDATE())
                    ELSE NULL
                END
            WHERE Username = @Username;
            
            THROW 50010, 'Invalid username or password', 1;
        END

        -- Check if account is locked
        IF @AccountLockedUntil IS NOT NULL AND @AccountLockedUntil > GETDATE()
            THROW 50011, 'Account is temporarily locked. Please try again later.', 1;

        -- Check if account is active
        IF @IsActive = 0
            THROW 50012, 'Account is disabled', 1;

        BEGIN TRANSACTION;

        -- Create new session
        SET @SessionId = NEWID();
        INSERT INTO CustomerSessions (SessionId, CustomerId, SessionToken, ExpiresDate)
        VALUES (@SessionId, @CustomerId, CONVERT(NVARCHAR(255), @SessionId), DATEADD(HOUR, 24, GETDATE()));

        -- Update customer login info
        UPDATE Customers
        SET LastLoginDate = GETDATE(),
            FailedLoginAttempts = 0,
            AccountLockedUntil = NULL
        WHERE CustomerId = @CustomerId;

        -- Log successful login
        INSERT INTO AuditLog (TableName, RecordId, Action, UserName)
        VALUES ('CustomerSessions', @CustomerId, 'INSERT', @Username);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- =============================================
-- ORDER MANAGEMENT PROCEDURES
-- =============================================

-- Procedure to create a new order
CREATE PROCEDURE sp_CreateOrder
    @CustomerId INT,
    @ShippingAddressId INT,
    @BillingAddressId INT,
    @OrderItems NVARCHAR(MAX), -- JSON array of order items
    @DiscountCode NVARCHAR(50) = NULL,
    @OrderId INT OUTPUT,
    @OrderNumber NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @SubtotalAmount DECIMAL(18, 2) = 0;
        DECLARE @TaxAmount DECIMAL(18, 2) = 0;
        DECLARE @DiscountAmount DECIMAL(18, 2) = 0;
        DECLARE @ShippingAmount DECIMAL(18, 2) = 10.00; -- Default shipping
        DECLARE @TotalAmount DECIMAL(18, 2) = 0;
        DECLARE @TaxRate DECIMAL(5, 4) = 0.08; -- 8% tax rate

        -- Generate unique order number
        SET @OrderNumber = 'ORD-' + FORMAT(GETDATE(), 'yyyyMMdd') + '-' + 
                          RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS NVARCHAR(5)), 5);

        -- Parse order items JSON and calculate subtotal
        DECLARE @ItemsTable TABLE (
            ProductId INT,
            VariantId INT,
            Quantity INT,
            UnitPrice DECIMAL(18, 2)
        );

        -- Insert into temp table from JSON
        INSERT INTO @ItemsTable (ProductId, VariantId, Quantity, UnitPrice)
        SELECT 
            JSON_VALUE(value, '$.ProductId'),
            JSON_VALUE(value, '$.VariantId'),
            JSON_VALUE(value, '$.Quantity'),
            JSON_VALUE(value, '$.UnitPrice')
        FROM OPENJSON(@OrderItems);

        -- Validate inventory availability
        IF EXISTS (
            SELECT 1
            FROM @ItemsTable it
            INNER JOIN Inventory i ON it.ProductId = i.ProductId
            WHERE i.QuantityInStock < it.Quantity
        )
            THROW 50020, 'Insufficient inventory for one or more items', 1;

        -- Calculate subtotal
        SELECT @SubtotalAmount = SUM(Quantity * UnitPrice)
        FROM @ItemsTable;

        -- Apply discount if code provided
        IF @DiscountCode IS NOT NULL
        BEGIN
            DECLARE @DiscountType NVARCHAR(20);
            DECLARE @DiscountValue DECIMAL(18, 2);
            DECLARE @MinOrderAmount DECIMAL(18, 2);
            DECLARE @MaxDiscountAmount DECIMAL(18, 2);

            SELECT 
                @DiscountType = DiscountType,
                @DiscountValue = DiscountValue,
                @MinOrderAmount = MinimumOrderAmount,
                @MaxDiscountAmount = MaximumDiscountAmount
            FROM DiscountCodes
            WHERE Code = @DiscountCode
                AND IsActive = 1
                AND StartDate <= GETDATE()
                AND (EndDate IS NULL OR EndDate >= GETDATE())
                AND (UsageLimit IS NULL OR UsageCount < UsageLimit);

            IF @DiscountType IS NOT NULL
            BEGIN
                IF @MinOrderAmount IS NULL OR @SubtotalAmount >= @MinOrderAmount
                BEGIN
                    IF @DiscountType = 'Percentage'
                        SET @DiscountAmount = @SubtotalAmount * (@DiscountValue / 100.0);
                    ELSE
                        SET @DiscountAmount = @DiscountValue;

                    -- Apply maximum discount cap if specified
                    IF @MaxDiscountAmount IS NOT NULL AND @DiscountAmount > @MaxDiscountAmount
                        SET @DiscountAmount = @MaxDiscountAmount;

                    -- Update discount code usage
                    UPDATE DiscountCodes
                    SET UsageCount = UsageCount + 1
                    WHERE Code = @DiscountCode;
                END
            END
        END

        -- Calculate tax and total
        SET @TaxAmount = (@SubtotalAmount - @DiscountAmount) * @TaxRate;
        SET @TotalAmount = @SubtotalAmount - @DiscountAmount + @TaxAmount + @ShippingAmount;

        -- Create order
        INSERT INTO Orders (
            OrderNumber, CustomerId, ShippingAddressId, BillingAddressId,
            SubtotalAmount, TaxAmount, ShippingAmount, DiscountAmount, TotalAmount,
            OrderStatus, PaymentStatus
        )
        VALUES (
            @OrderNumber, @CustomerId, @ShippingAddressId, @BillingAddressId,
            @SubtotalAmount, @TaxAmount, @ShippingAmount, @DiscountAmount, @TotalAmount,
            'Pending', 'Pending'
        );

        SET @OrderId = SCOPE_IDENTITY();

        -- Insert order items
        INSERT INTO OrderItems (OrderId, ProductId, VariantId, ProductName, SKU, Quantity, UnitPrice, TaxAmount, TotalAmount)
        SELECT 
            @OrderId,
            it.ProductId,
            it.VariantId,
            p.ProductName,
            COALESCE(pv.SKU, p.SKU),
            it.Quantity,
            it.UnitPrice,
            it.Quantity * it.UnitPrice * @TaxRate,
            it.Quantity * it.UnitPrice * (1 + @TaxRate)
        FROM @ItemsTable it
        INNER JOIN Products p ON it.ProductId = p.ProductId
        LEFT JOIN ProductVariants pv ON it.VariantId = pv.VariantId;

        -- Reserve inventory
        UPDATE i
        SET i.QuantityInStock = i.QuantityInStock - it.Quantity
        FROM Inventory i
        INNER JOIN @ItemsTable it ON i.ProductId = it.ProductId;

        -- Log order creation
        INSERT INTO AuditLog (TableName, RecordId, Action, NewValues)
        VALUES ('Orders', @OrderId, 'INSERT', 
                CONCAT('OrderNumber: ', @OrderNumber, ', Total: ', @TotalAmount));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- Procedure to process payment
CREATE PROCEDURE sp_ProcessPayment
    @OrderId INT,
    @PaymentMethod NVARCHAR(50),
    @GatewayTransactionId NVARCHAR(100),
    @TransactionId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @TotalAmount DECIMAL(18, 2);
        DECLARE @OrderStatus NVARCHAR(20);

        -- Get order details
        SELECT @TotalAmount = TotalAmount, @OrderStatus = OrderStatus
        FROM Orders
        WHERE OrderId = @OrderId;

        IF @OrderStatus != 'Pending'
            THROW 50030, 'Order is not in pending status', 1;

        -- Record payment transaction
        INSERT INTO PaymentTransactions (OrderId, TransactionType, PaymentMethod, Amount, TransactionStatus, GatewayTransactionId)
        VALUES (@OrderId, 'Payment', @PaymentMethod, @TotalAmount, 'Success', @GatewayTransactionId);

        SET @TransactionId = SCOPE_IDENTITY();

        -- Update order status
        UPDATE Orders
        SET PaymentStatus = 'Paid',
            PaymentDate = GETDATE(),
            OrderStatus = 'Paid',
            LastModifiedDate = GETDATE()
        WHERE OrderId = @OrderId;

        -- Log payment
        INSERT INTO AuditLog (TableName, RecordId, Action, NewValues)
        VALUES ('PaymentTransactions', @TransactionId, 'INSERT', 
                CONCAT('OrderId: ', @OrderId, ', Amount: ', @TotalAmount));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        -- Record failed payment
        INSERT INTO PaymentTransactions (OrderId, TransactionType, PaymentMethod, Amount, TransactionStatus, GatewayTransactionId, GatewayResponse)
        VALUES (@OrderId, 'Payment', @PaymentMethod, @TotalAmount, 'Failed', @GatewayTransactionId, ERROR_MESSAGE());

        THROW;
    END CATCH
END;
GO

-- =============================================
-- REPORTING FUNCTIONS
-- =============================================

-- Function to calculate customer lifetime value
CREATE FUNCTION fn_GetCustomerLifetimeValue(@CustomerId INT)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    DECLARE @TotalValue DECIMAL(18, 2);

    SELECT @TotalValue = ISNULL(SUM(TotalAmount), 0)
    FROM Orders
    WHERE CustomerId = @CustomerId
        AND OrderStatus = 'Delivered';

    RETURN @TotalValue;
END;
GO

-- Function to get average order value
CREATE FUNCTION fn_GetAverageOrderValue(@StartDate DATETIME, @EndDate DATETIME)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    DECLARE @AvgValue DECIMAL(18, 2);

    SELECT @AvgValue = AVG(TotalAmount)
    FROM Orders
    WHERE OrderDate BETWEEN @StartDate AND @EndDate
        AND OrderStatus != 'Cancelled';

    RETURN ISNULL(@AvgValue, 0);
END;
GO

-- Procedure to get sales report
CREATE PROCEDURE sp_GetSalesReport
    @StartDate DATETIME,
    @EndDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    -- Overall statistics
    SELECT 
        COUNT(*) AS TotalOrders,
        COUNT(CASE WHEN OrderStatus = 'Delivered' THEN 1 END) AS CompletedOrders,
        COUNT(CASE WHEN OrderStatus = 'Cancelled' THEN 1 END) AS CancelledOrders,
        SUM(TotalAmount) AS TotalRevenue,
        AVG(TotalAmount) AS AverageOrderValue,
        SUM(DiscountAmount) AS TotalDiscounts,
        COUNT(DISTINCT CustomerId) AS UniqueCustomers
    FROM Orders
    WHERE OrderDate BETWEEN @StartDate AND @EndDate;

    -- Daily sales breakdown
    SELECT 
        CAST(OrderDate AS DATE) AS SaleDate,
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS DailyRevenue,
        AVG(TotalAmount) AS AvgOrderValue
    FROM Orders
    WHERE OrderDate BETWEEN @StartDate AND @EndDate
        AND OrderStatus != 'Cancelled'
    GROUP BY CAST(OrderDate AS DATE)
    ORDER BY SaleDate;

    -- Top selling products
    SELECT TOP 10
        p.ProductId,
        p.ProductName,
        SUM(oi.Quantity) AS TotalQuantitySold,
        SUM(oi.TotalAmount) AS TotalRevenue
    FROM OrderItems oi
    INNER JOIN Orders o ON oi.OrderId = o.OrderId
    INNER JOIN Products p ON oi.ProductId = p.ProductId
    WHERE o.OrderDate BETWEEN @StartDate AND @EndDate
        AND o.OrderStatus != 'Cancelled'
    GROUP BY p.ProductId, p.ProductName
    ORDER BY TotalRevenue DESC;

    -- Category performance
    SELECT 
        c.CategoryName,
        COUNT(DISTINCT oi.OrderId) AS OrderCount,
        SUM(oi.Quantity) AS TotalQuantitySold,
        SUM(oi.TotalAmount) AS TotalRevenue
    FROM OrderItems oi
    INNER JOIN Orders o ON oi.OrderId = o.OrderId
    INNER JOIN Products p ON oi.ProductId = p.ProductId
    INNER JOIN Categories c ON p.CategoryId = c.CategoryId
    WHERE o.OrderDate BETWEEN @StartDate AND @EndDate
        AND o.OrderStatus != 'Cancelled'
    GROUP BY c.CategoryName
    ORDER BY TotalRevenue DESC;
END;
GO

-- =============================================
-- MAINTENANCE PROCEDURES
-- =============================================

-- Procedure to clean up expired sessions
CREATE PROCEDURE sp_CleanupExpiredSessions
AS
BEGIN
    SET NOCOUNT ON;
    
    DELETE FROM CustomerSessions
    WHERE ExpiresDate < GETDATE() OR IsActive = 0;

    SELECT @@ROWCOUNT AS DeletedSessions;
END;
GO

-- Procedure to update product inventory alerts
CREATE PROCEDURE sp_UpdateInventoryAlerts
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        p.ProductId,
        p.ProductName,
        i.QuantityInStock,
        i.ReorderLevel,
        i.ReorderQuantity,
        CASE 
            WHEN i.QuantityInStock = 0 THEN 'OUT_OF_STOCK'
            WHEN i.QuantityInStock <= i.ReorderLevel THEN 'LOW_STOCK'
            ELSE 'ADEQUATE'
        END AS StockStatus
    FROM Inventory i
    INNER JOIN Products p ON i.ProductId = p.ProductId
    WHERE i.QuantityInStock <= i.ReorderLevel
        AND p.IsActive = 1
    ORDER BY i.QuantityInStock;
END;
GO
