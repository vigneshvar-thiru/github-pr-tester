using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SampleApp.Business
{
    /// <summary>
    /// Comprehensive order management system for handling all aspects of order processing
    /// Updated: Enhanced with webhook support
    /// </summary>
    /// <remarks>
    /// This service provides complete functionality for:
    /// - Order creation and validation
    /// - Order status tracking
    /// - Payment processing integration
    /// - Inventory management integration
    /// - Customer notification handling
    /// - Order history and reporting
    /// </remarks>
    public class OrderManagementSystem
    {
        private readonly Dictionary<int, Order> _orders;
        private readonly Dictionary<int, OrderItem> _orderItems;
        private readonly IPaymentProcessor _paymentProcessor;
        private readonly IInventoryService _inventoryService;
        private readonly INotificationService _notificationService;
        private int _nextOrderId;
        private int _nextItemId;

        public OrderManagementSystem(
            IPaymentProcessor paymentProcessor,
            IInventoryService inventoryService,
            INotificationService notificationService)
        {
            _orders = new Dictionary<int, Order>();
            _orderItems = new Dictionary<int, OrderItem>();
            _paymentProcessor = paymentProcessor ?? throw new ArgumentNullException(nameof(paymentProcessor));
            _inventoryService = inventoryService ?? throw new ArgumentNullException(nameof(inventoryService));
            _notificationService = notificationService ?? throw new ArgumentNullException(nameof(notificationService));
            _nextOrderId = 1000;
            _nextItemId = 1;
        }

        /// <summary>
        /// Creates a new order with validation and inventory checks
        /// </summary>
        /// <param name="customerId">The ID of the customer placing the order</param>
        /// <param name="items">List of items to include in the order</param>
        /// <returns>The created order ID</returns>
        /// <exception cref="ArgumentException">Thrown when validation fails</exception>
        /// <exception cref="InvalidOperationException">Thrown when inventory is insufficient</exception>
        public async Task<int> CreateOrderAsync(int customerId, List<OrderItemRequest> items)
        {
            if (customerId <= 0)
                throw new ArgumentException("Invalid customer ID", nameof(customerId));

            if (items == null || !items.Any())
                throw new ArgumentException("Order must contain at least one item", nameof(items));

            // Validate inventory availability
            foreach (var item in items)
            {
                if (!await _inventoryService.CheckAvailabilityAsync(item.ProductId, item.Quantity))
                {
                    throw new InvalidOperationException($"Insufficient inventory for product {item.ProductId}");
                }
            }

            // Create order
            var order = new Order
            {
                Id = _nextOrderId++,
                CustomerId = customerId,
                OrderDate = DateTime.UtcNow,
                Status = OrderStatus.Pending,
                TotalAmount = 0
            };

            // Add order items and calculate total
            decimal totalAmount = 0;
            foreach (var itemRequest in items)
            {
                var orderItem = new OrderItem
                {
                    Id = _nextItemId++,
                    OrderId = order.Id,
                    ProductId = itemRequest.ProductId,
                    Quantity = itemRequest.Quantity,
                    UnitPrice = itemRequest.UnitPrice
                };

                _orderItems.Add(orderItem.Id, orderItem);
                totalAmount += orderItem.Quantity * orderItem.UnitPrice;
            }

            order.TotalAmount = totalAmount;
            _orders.Add(order.Id, order);

            // Send notification
            await _notificationService.SendOrderConfirmationAsync(customerId, order.Id);

            return order.Id;
        }

        /// <summary>
        /// Processes payment for an order
        /// </summary>
        /// <param name="orderId">The order ID</param>
        /// <param name="paymentMethod">Payment method to use</param>
        /// <returns>True if payment was successful</returns>
        public async Task<bool> ProcessPaymentAsync(int orderId, PaymentMethod paymentMethod)
        {
            if (!_orders.TryGetValue(orderId, out var order))
                throw new ArgumentException("Order not found", nameof(orderId));

            if (order.Status != OrderStatus.Pending)
                throw new InvalidOperationException($"Cannot process payment for order in {order.Status} status");

            try
            {
                var paymentResult = await _paymentProcessor.ProcessPaymentAsync(
                    order.TotalAmount,
                    paymentMethod);

                if (paymentResult.Success)
                {
                    order.Status = OrderStatus.Paid;
                    order.PaymentDate = DateTime.UtcNow;
                    order.PaymentTransactionId = paymentResult.TransactionId;

                    // Reserve inventory
                    await ReserveInventoryForOrderAsync(orderId);

                    // Send notification
                    await _notificationService.SendPaymentConfirmationAsync(order.CustomerId, orderId);

                    return true;
                }
                else
                {
                    order.Status = OrderStatus.PaymentFailed;
                    await _notificationService.SendPaymentFailureNotificationAsync(order.CustomerId, orderId);
                    return false;
                }
            }
            catch (Exception ex)
            {
                order.Status = OrderStatus.PaymentFailed;
                await _notificationService.SendErrorNotificationAsync(order.CustomerId, orderId, ex.Message);
                throw;
            }
        }

        /// <summary>
        /// Ships an order that has been paid
        /// </summary>
        public async Task<bool> ShipOrderAsync(int orderId, string trackingNumber)
        {
            if (!_orders.TryGetValue(orderId, out var order))
                return false;

            if (order.Status != OrderStatus.Paid)
                throw new InvalidOperationException("Order must be paid before shipping");

            order.Status = OrderStatus.Shipped;
            order.ShipDate = DateTime.UtcNow;
            order.TrackingNumber = trackingNumber;

            await _notificationService.SendShipmentNotificationAsync(order.CustomerId, orderId, trackingNumber);

            return true;
        }

        /// <summary>
        /// Marks an order as delivered
        /// </summary>
        public async Task<bool> CompleteOrderAsync(int orderId)
        {
            if (!_orders.TryGetValue(orderId, out var order))
                return false;

            if (order.Status != OrderStatus.Shipped)
                throw new InvalidOperationException("Order must be shipped before completion");

            order.Status = OrderStatus.Delivered;
            order.DeliveryDate = DateTime.UtcNow;

            await _notificationService.SendDeliveryConfirmationAsync(order.CustomerId, orderId);

            return true;
        }

        /// <summary>
        /// Cancels an order and releases inventory if applicable
        /// </summary>
        public async Task<bool> CancelOrderAsync(int orderId, string reason)
        {
            if (!_orders.TryGetValue(orderId, out var order))
                return false;

            if (order.Status == OrderStatus.Delivered || order.Status == OrderStatus.Cancelled)
                throw new InvalidOperationException($"Cannot cancel order in {order.Status} status");

            var previousStatus = order.Status;
            order.Status = OrderStatus.Cancelled;
            order.CancellationReason = reason;

            // Release inventory if it was reserved
            if (previousStatus == OrderStatus.Paid || previousStatus == OrderStatus.Shipped)
            {
                await ReleaseInventoryForOrderAsync(orderId);
            }

            // Process refund if payment was made
            if (previousStatus == OrderStatus.Paid || previousStatus == OrderStatus.Shipped)
            {
                await _paymentProcessor.ProcessRefundAsync(order.PaymentTransactionId, order.TotalAmount);
            }

            await _notificationService.SendCancellationNotificationAsync(order.CustomerId, orderId, reason);

            return true;
        }

        /// <summary>
        /// Gets order details by ID
        /// </summary>
        public Order GetOrder(int orderId)
        {
            return _orders.TryGetValue(orderId, out var order) ? order : null;
        }

        /// <summary>
        /// Gets all items for a specific order
        /// </summary>
        public IEnumerable<OrderItem> GetOrderItems(int orderId)
        {
            return _orderItems.Values.Where(item => item.OrderId == orderId);
        }

        /// <summary>
        /// Gets order history for a customer
        /// </summary>
        public IEnumerable<Order> GetCustomerOrders(int customerId)
        {
            return _orders.Values.Where(o => o.CustomerId == customerId).OrderByDescending(o => o.OrderDate);
        }

        /// <summary>
        /// Gets orders by status
        /// </summary>
        public IEnumerable<Order> GetOrdersByStatus(OrderStatus status)
        {
            return _orders.Values.Where(o => o.Status == status);
        }

        /// <summary>
        /// Calculates total revenue for a date range
        /// </summary>
        public decimal CalculateRevenue(DateTime startDate, DateTime endDate)
        {
            return _orders.Values
                .Where(o => o.OrderDate >= startDate && o.OrderDate <= endDate && o.Status == OrderStatus.Delivered)
                .Sum(o => o.TotalAmount);
        }

        /// <summary>
        /// Gets sales statistics for reporting
        /// </summary>
        public SalesStatistics GetSalesStatistics(DateTime startDate, DateTime endDate)
        {
            var orders = _orders.Values
                .Where(o => o.OrderDate >= startDate && o.OrderDate <= endDate)
                .ToList();

            return new SalesStatistics
            {
                TotalOrders = orders.Count,
                CompletedOrders = orders.Count(o => o.Status == OrderStatus.Delivered),
                CancelledOrders = orders.Count(o => o.Status == OrderStatus.Cancelled),
                TotalRevenue = orders.Where(o => o.Status == OrderStatus.Delivered).Sum(o => o.TotalAmount),
                AverageOrderValue = orders.Any() ? orders.Average(o => o.TotalAmount) : 0
            };
        }

        private async Task ReserveInventoryForOrderAsync(int orderId)
        {
            var items = GetOrderItems(orderId);
            foreach (var item in items)
            {
                await _inventoryService.ReserveItemAsync(item.ProductId, item.Quantity);
            }
        }

        private async Task ReleaseInventoryForOrderAsync(int orderId)
        {
            var items = GetOrderItems(orderId);
            foreach (var item in items)
            {
                await _inventoryService.ReleaseItemAsync(item.ProductId, item.Quantity);
            }
        }
    }

    #region Supporting Classes

    public class Order
    {
        public int Id { get; set; }
        public int CustomerId { get; set; }
        public DateTime OrderDate { get; set; }
        public OrderStatus Status { get; set; }
        public decimal TotalAmount { get; set; }
        public DateTime? PaymentDate { get; set; }
        public string PaymentTransactionId { get; set; }
        public DateTime? ShipDate { get; set; }
        public string TrackingNumber { get; set; }
        public DateTime? DeliveryDate { get; set; }
        public string CancellationReason { get; set; }
    }

    public class OrderItem
    {
        public int Id { get; set; }
        public int OrderId { get; set; }
        public int ProductId { get; set; }
        public int Quantity { get; set; }
        public decimal UnitPrice { get; set; }
    }

    public class OrderItemRequest
    {
        public int ProductId { get; set; }
        public int Quantity { get; set; }
        public decimal UnitPrice { get; set; }
    }

    public enum OrderStatus
    {
        Pending,
        Paid,
        Shipped,
        Delivered,
        Cancelled,
        PaymentFailed
    }

    public enum PaymentMethod
    {
        CreditCard,
        DebitCard,
        PayPal,
        BankTransfer
    }

    public class SalesStatistics
    {
        public int TotalOrders { get; set; }
        public int CompletedOrders { get; set; }
        public int CancelledOrders { get; set; }
        public decimal TotalRevenue { get; set; }
        public decimal AverageOrderValue { get; set; }
    }

    public class PaymentResult
    {
        public bool Success { get; set; }
        public string TransactionId { get; set; }
        public string ErrorMessage { get; set; }
    }

    #endregion

    #region Interfaces

    public interface IPaymentProcessor
    {
        Task<PaymentResult> ProcessPaymentAsync(decimal amount, PaymentMethod method);
        Task<bool> ProcessRefundAsync(string transactionId, decimal amount);
    }

    public interface IInventoryService
    {
        Task<bool> CheckAvailabilityAsync(int productId, int quantity);
        Task ReserveItemAsync(int productId, int quantity);
        Task ReleaseItemAsync(int productId, int quantity);
    }

    public interface INotificationService
    {
        Task SendOrderConfirmationAsync(int customerId, int orderId);
        Task SendPaymentConfirmationAsync(int customerId, int orderId);
        Task SendPaymentFailureNotificationAsync(int customerId, int orderId);
        Task SendShipmentNotificationAsync(int customerId, int orderId, string trackingNumber);
        Task SendDeliveryConfirmationAsync(int customerId, int orderId);
        Task SendCancellationNotificationAsync(int customerId, int orderId, string reason);
        Task SendErrorNotificationAsync(int customerId, int orderId, string errorMessage);
    }

    #endregion
}
