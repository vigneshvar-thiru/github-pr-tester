-- Simple table creation for Users
CREATE TABLE Users (
    UserId INT PRIMARY KEY IDENTITY(1,1),
    Username NVARCHAR(50) NOT NULL,
    Email NVARCHAR(100) NOT NULL,
    CreatedDate DATETIME DEFAULT GETDATE()
);
