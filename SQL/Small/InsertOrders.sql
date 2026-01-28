-- Insert sample data into Orders table
-- Updated: Added Status column value
INSERT INTO Orders (CustomerId, OrderDate, TotalAmount, Status)
VALUES 
    (1, GETDATE(), 150.00, 'Pending'),
    (2, GETDATE(), 250.50, 'Shipped'),
    (3, GETDATE(), 99.99, 'Delivered');
