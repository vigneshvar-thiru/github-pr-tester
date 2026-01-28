-- =============================================
-- Comprehensive E-Commerce Database Schema
-- Version: 1.0
-- Date: 2024-01-01
-- Updated: Added audit trail tables
-- Description: Complete database schema for e-commerce application
-- =============================================

-- =============================================
-- CUSTOMERS AND AUTHENTICATION
-- =============================================

-- Main customers table
CREATE TABLE Customers (
    CustomerId INT PRIMARY KEY IDENTITY(1,1),
    Username NVARCHAR(50) NOT NULL UNIQUE,
    Email NVARCHAR(100) NOT NULL UNIQUE,
    PasswordHash NVARCHAR(255) NOT NULL,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    PhoneNumber NVARCHAR(20),
    DateOfBirth DATE,
    IsActive BIT NOT NULL DEFAULT 1,
    EmailVerified BIT NOT NULL DEFAULT 0,
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    LastModifiedDate DATETIME NOT NULL DEFAULT GETDATE(),
    LastLoginDate DATETIME,
    FailedLoginAttempts INT NOT NULL DEFAULT 0,
    AccountLockedUntil DATETIME,
    CONSTRAINT CK_Customers_Email CHECK (Email LIKE '%@%.%')
);

-- Customer addresses
CREATE TABLE CustomerAddresses (
    AddressId INT PRIMARY KEY IDENTITY(1,1),
    CustomerId INT NOT NULL,
    AddressType NVARCHAR(20) NOT NULL, -- Billing, Shipping, Both
    AddressLine1 NVARCHAR(100) NOT NULL,
    AddressLine2 NVARCHAR(100),
    City NVARCHAR(50) NOT NULL,
    StateProvince NVARCHAR(50) NOT NULL,
    PostalCode NVARCHAR(20) NOT NULL,
    Country NVARCHAR(50) NOT NULL,
    IsDefault BIT NOT NULL DEFAULT 0,
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_CustomerAddresses_Customers FOREIGN KEY (CustomerId) 
        REFERENCES Customers(CustomerId) ON DELETE CASCADE
);

-- Customer sessions for authentication
CREATE TABLE CustomerSessions (
    SessionId UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    CustomerId INT NOT NULL,
    SessionToken NVARCHAR(255) NOT NULL UNIQUE,
    IpAddress NVARCHAR(50),
    UserAgent NVARCHAR(255),
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    ExpiresDate DATETIME NOT NULL,
    IsActive BIT NOT NULL DEFAULT 1,
    CONSTRAINT FK_CustomerSessions_Customers FOREIGN KEY (CustomerId) 
        REFERENCES Customers(CustomerId) ON DELETE CASCADE
);

-- =============================================
-- PRODUCTS AND CATALOG
-- =============================================

-- Product categories
CREATE TABLE Categories (
    CategoryId INT PRIMARY KEY IDENTITY(1,1),
    CategoryName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(500),
    ParentCategoryId INT,
    DisplayOrder INT NOT NULL DEFAULT 0,
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_Categories_ParentCategory FOREIGN KEY (ParentCategoryId) 
        REFERENCES Categories(CategoryId)
);

-- Products
CREATE TABLE Products (
    ProductId INT PRIMARY KEY IDENTITY(1,1),
    ProductName NVARCHAR(200) NOT NULL,
    SKU NVARCHAR(50) NOT NULL UNIQUE,
    CategoryId INT NOT NULL,
    Description NVARCHAR(MAX),
    ShortDescription NVARCHAR(500),
    UnitPrice DECIMAL(18, 2) NOT NULL,
    CompareAtPrice DECIMAL(18, 2),
    CostPrice DECIMAL(18, 2),
    Weight DECIMAL(10, 2),
    WeightUnit NVARCHAR(10), -- kg, lb, oz
    IsActive BIT NOT NULL DEFAULT 1,
    IsFeatured BIT NOT NULL DEFAULT 0,
    AllowBackorder BIT NOT NULL DEFAULT 0,
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    LastModifiedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_Products_Categories FOREIGN KEY (CategoryId) 
        REFERENCES Categories(CategoryId),
    CONSTRAINT CK_Products_UnitPrice CHECK (UnitPrice >= 0),
    CONSTRAINT CK_Products_CompareAtPrice CHECK (CompareAtPrice IS NULL OR CompareAtPrice >= UnitPrice)
);

-- Product images
CREATE TABLE ProductImages (
    ImageId INT PRIMARY KEY IDENTITY(1,1),
    ProductId INT NOT NULL,
    ImageUrl NVARCHAR(500) NOT NULL,
    AltText NVARCHAR(200),
    DisplayOrder INT NOT NULL DEFAULT 0,
    IsPrimary BIT NOT NULL DEFAULT 0,
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_ProductImages_Products FOREIGN KEY (ProductId) 
        REFERENCES Products(ProductId) ON DELETE CASCADE
);

-- Product variants (for products with options like size, color)
CREATE TABLE ProductVariants (
    VariantId INT PRIMARY KEY IDENTITY(1,1),
    ProductId INT NOT NULL,
    SKU NVARCHAR(50) NOT NULL UNIQUE,
    VariantName NVARCHAR(100) NOT NULL,
    UnitPrice DECIMAL(18, 2),
    QuantityInStock INT NOT NULL DEFAULT 0,
    IsActive BIT NOT NULL DEFAULT 1,
    CONSTRAINT FK_ProductVariants_Products FOREIGN KEY (ProductId) 
        REFERENCES Products(ProductId) ON DELETE CASCADE
);

-- Inventory management
CREATE TABLE Inventory (
    InventoryId INT PRIMARY KEY IDENTITY(1,1),
    ProductId INT NOT NULL,
    VariantId INT,
    QuantityInStock INT NOT NULL DEFAULT 0,
    ReorderLevel INT NOT NULL DEFAULT 10,
    ReorderQuantity INT NOT NULL DEFAULT 50,
    LastRestockDate DATETIME,
    LastStockCheckDate DATETIME,
    WarehouseLocation NVARCHAR(50),
    CONSTRAINT FK_Inventory_Products FOREIGN KEY (ProductId) 
        REFERENCES Products(ProductId),
    CONSTRAINT FK_Inventory_ProductVariants FOREIGN KEY (VariantId) 
        REFERENCES ProductVariants(VariantId),
    CONSTRAINT CK_Inventory_QuantityInStock CHECK (QuantityInStock >= 0)
);

-- =============================================
-- ORDERS AND TRANSACTIONS
-- =============================================

-- Orders
CREATE TABLE Orders (
    OrderId INT PRIMARY KEY IDENTITY(1,1),
    OrderNumber NVARCHAR(50) NOT NULL UNIQUE,
    CustomerId INT NOT NULL,
    OrderDate DATETIME NOT NULL DEFAULT GETDATE(),
    OrderStatus NVARCHAR(20) NOT NULL DEFAULT 'Pending', -- Pending, Paid, Shipped, Delivered, Cancelled
    PaymentStatus NVARCHAR(20) NOT NULL DEFAULT 'Pending', -- Pending, Paid, Failed, Refunded
    ShippingAddressId INT,
    BillingAddressId INT,
    SubtotalAmount DECIMAL(18, 2) NOT NULL,
    TaxAmount DECIMAL(18, 2) NOT NULL DEFAULT 0,
    ShippingAmount DECIMAL(18, 2) NOT NULL DEFAULT 0,
    DiscountAmount DECIMAL(18, 2) NOT NULL DEFAULT 0,
    TotalAmount DECIMAL(18, 2) NOT NULL,
    PaymentDate DATETIME,
    ShipDate DATETIME,
    DeliveryDate DATETIME,
    CancellationDate DATETIME,
    CancellationReason NVARCHAR(500),
    TrackingNumber NVARCHAR(100),
    Notes NVARCHAR(MAX),
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    LastModifiedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerId) 
        REFERENCES Customers(CustomerId),
    CONSTRAINT FK_Orders_ShippingAddress FOREIGN KEY (ShippingAddressId) 
        REFERENCES CustomerAddresses(AddressId),
    CONSTRAINT FK_Orders_BillingAddress FOREIGN KEY (BillingAddressId) 
        REFERENCES CustomerAddresses(AddressId),
    CONSTRAINT CK_Orders_TotalAmount CHECK (TotalAmount >= 0)
);

-- Order items
CREATE TABLE OrderItems (
    OrderItemId INT PRIMARY KEY IDENTITY(1,1),
    OrderId INT NOT NULL,
    ProductId INT NOT NULL,
    VariantId INT,
    ProductName NVARCHAR(200) NOT NULL,
    SKU NVARCHAR(50) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18, 2) NOT NULL,
    DiscountAmount DECIMAL(18, 2) NOT NULL DEFAULT 0,
    TaxAmount DECIMAL(18, 2) NOT NULL DEFAULT 0,
    TotalAmount DECIMAL(18, 2) NOT NULL,
    CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderId) 
        REFERENCES Orders(OrderId) ON DELETE CASCADE,
    CONSTRAINT FK_OrderItems_Products FOREIGN KEY (ProductId) 
        REFERENCES Products(ProductId),
    CONSTRAINT FK_OrderItems_ProductVariants FOREIGN KEY (VariantId) 
        REFERENCES ProductVariants(VariantId),
    CONSTRAINT CK_OrderItems_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_OrderItems_UnitPrice CHECK (UnitPrice >= 0)
);

-- Payment transactions
CREATE TABLE PaymentTransactions (
    TransactionId INT PRIMARY KEY IDENTITY(1,1),
    OrderId INT NOT NULL,
    TransactionType NVARCHAR(20) NOT NULL, -- Payment, Refund, Void
    PaymentMethod NVARCHAR(50) NOT NULL, -- CreditCard, DebitCard, PayPal, etc.
    Amount DECIMAL(18, 2) NOT NULL,
    Currency NVARCHAR(3) NOT NULL DEFAULT 'USD',
    TransactionStatus NVARCHAR(20) NOT NULL, -- Pending, Success, Failed
    GatewayTransactionId NVARCHAR(100),
    GatewayResponse NVARCHAR(MAX),
    ProcessedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_PaymentTransactions_Orders FOREIGN KEY (OrderId) 
        REFERENCES Orders(OrderId)
);

-- =============================================
-- PROMOTIONS AND DISCOUNTS
-- =============================================

-- Discount codes/coupons
CREATE TABLE DiscountCodes (
    DiscountCodeId INT PRIMARY KEY IDENTITY(1,1),
    Code NVARCHAR(50) NOT NULL UNIQUE,
    Description NVARCHAR(200),
    DiscountType NVARCHAR(20) NOT NULL, -- Percentage, FixedAmount
    DiscountValue DECIMAL(18, 2) NOT NULL,
    MinimumOrderAmount DECIMAL(18, 2),
    MaximumDiscountAmount DECIMAL(18, 2),
    UsageLimit INT,
    UsageCount INT NOT NULL DEFAULT 0,
    StartDate DATETIME NOT NULL,
    EndDate DATETIME,
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT CK_DiscountCodes_DiscountValue CHECK (DiscountValue > 0)
);

-- =============================================
-- REVIEWS AND RATINGS
-- =============================================

-- Product reviews
CREATE TABLE ProductReviews (
    ReviewId INT PRIMARY KEY IDENTITY(1,1),
    ProductId INT NOT NULL,
    CustomerId INT NOT NULL,
    OrderId INT,
    Rating INT NOT NULL,
    Title NVARCHAR(200),
    ReviewText NVARCHAR(MAX),
    IsVerifiedPurchase BIT NOT NULL DEFAULT 0,
    IsApproved BIT NOT NULL DEFAULT 0,
    HelpfulCount INT NOT NULL DEFAULT 0,
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_ProductReviews_Products FOREIGN KEY (ProductId) 
        REFERENCES Products(ProductId) ON DELETE CASCADE,
    CONSTRAINT FK_ProductReviews_Customers FOREIGN KEY (CustomerId) 
        REFERENCES Customers(CustomerId),
    CONSTRAINT FK_ProductReviews_Orders FOREIGN KEY (OrderId) 
        REFERENCES Orders(OrderId),
    CONSTRAINT CK_ProductReviews_Rating CHECK (Rating BETWEEN 1 AND 5)
);

-- =============================================
-- AUDIT AND LOGGING
-- =============================================

-- Audit log for tracking important events
CREATE TABLE AuditLog (
    AuditId BIGINT PRIMARY KEY IDENTITY(1,1),
    TableName NVARCHAR(100) NOT NULL,
    RecordId INT NOT NULL,
    Action NVARCHAR(20) NOT NULL, -- INSERT, UPDATE, DELETE
    OldValues NVARCHAR(MAX),
    NewValues NVARCHAR(MAX),
    UserId INT,
    UserName NVARCHAR(100),
    IpAddress NVARCHAR(50),
    Timestamp DATETIME NOT NULL DEFAULT GETDATE()
);

-- =============================================
-- INDEXES FOR PERFORMANCE
-- =============================================

-- Customer indexes
CREATE NONCLUSTERED INDEX IX_Customers_Email ON Customers(Email);
CREATE NONCLUSTERED INDEX IX_Customers_Username ON Customers(Username);
CREATE NONCLUSTERED INDEX IX_Customers_LastLoginDate ON Customers(LastLoginDate);

-- Product indexes
CREATE NONCLUSTERED INDEX IX_Products_CategoryId ON Products(CategoryId);
CREATE NONCLUSTERED INDEX IX_Products_SKU ON Products(SKU);
CREATE NONCLUSTERED INDEX IX_Products_IsActive ON Products(IsActive);
CREATE NONCLUSTERED INDEX IX_Products_IsFeatured ON Products(IsFeatured);

-- Order indexes
CREATE NONCLUSTERED INDEX IX_Orders_CustomerId ON Orders(CustomerId);
CREATE NONCLUSTERED INDEX IX_Orders_OrderNumber ON Orders(OrderNumber);
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate ON Orders(OrderDate);
CREATE NONCLUSTERED INDEX IX_Orders_OrderStatus ON Orders(OrderStatus);

-- Inventory indexes
CREATE NONCLUSTERED INDEX IX_Inventory_ProductId ON Inventory(ProductId);
CREATE NONCLUSTERED INDEX IX_Inventory_QuantityInStock ON Inventory(QuantityInStock);

-- =============================================
-- INITIAL DATA
-- =============================================

-- Insert default categories
INSERT INTO Categories (CategoryName, Description, DisplayOrder)
VALUES 
    ('Electronics', 'Electronic devices and accessories', 1),
    ('Clothing', 'Apparel and fashion items', 2),
    ('Books', 'Books and publications', 3),
    ('Home & Garden', 'Home improvement and garden supplies', 4),
    ('Sports & Outdoors', 'Sports equipment and outdoor gear', 5);

GO
