-- Create view for product inventory summary
CREATE VIEW vw_ProductInventorySummary AS
SELECT 
    p.ProductId,
    p.ProductName,
    p.CategoryId,
    c.CategoryName,
    p.UnitPrice,
    i.QuantityInStock,
    i.ReorderLevel,
    i.LastRestockDate,
    CASE 
        WHEN i.QuantityInStock <= i.ReorderLevel THEN 'Low Stock'
        WHEN i.QuantityInStock <= (i.ReorderLevel * 2) THEN 'Medium Stock'
        ELSE 'Adequate Stock'
    END AS StockStatus,
    (p.UnitPrice * i.QuantityInStock) AS TotalInventoryValue,
    DATEDIFF(DAY, i.LastRestockDate, GETDATE()) AS DaysSinceRestock
FROM Products p
INNER JOIN Inventory i ON p.ProductId = i.ProductId
INNER JOIN Categories c ON p.CategoryId = c.CategoryId
WHERE p.IsActive = 1;

GO

-- Create index on the view for better performance
CREATE NONCLUSTERED INDEX IX_ProductInventorySummary_StockStatus
ON vw_ProductInventorySummary (StockStatus)
INCLUDE (ProductId, ProductName, QuantityInStock);
