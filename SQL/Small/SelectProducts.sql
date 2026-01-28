-- Simple SELECT query
SELECT 
    ProductId,
    ProductName,
    Price
FROM Products
WHERE Price > 100
ORDER BY Price DESC;
