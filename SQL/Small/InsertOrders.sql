-- Insert sample data into Orders table
INSERT INTO Orders (CustomerId, OrderDate, TotalAmount)
VALUES 
    (1, GETDATE(), 150.00),
    (2, GETDATE(), 250.50),
    (3, GETDATE(), 99.99);
