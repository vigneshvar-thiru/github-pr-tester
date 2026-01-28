-- Simple SELECT query
-- Updated: Added StockQuantity column
SELECT 
    ProductId,
    ProductName,
    Price,
    StockQuantity
FROM Products
WHERE Price > 100
ORDER BY Price DESC;
