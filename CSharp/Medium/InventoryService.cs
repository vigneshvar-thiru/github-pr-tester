using System;
using System.Collections.Generic;
using System.Linq;

namespace SampleApp.Services
{
    /// <summary>
    /// Service for handling inventory management
    /// Updated: Improved stock tracking
    /// </summary>
    public class InventoryService
    {
        private readonly Dictionary<int, InventoryItem> _inventory;
        private int _nextId;

        public InventoryService()
        {
            _inventory = new Dictionary<int, InventoryItem>();
            _nextId = 1;
        }

        /// <summary>
        /// Adds a new item to inventory
        /// </summary>
        public int AddItem(string name, int quantity, decimal cost)
        {
            var item = new InventoryItem
            {
                Id = _nextId++,
                Name = name,
                Quantity = quantity,
                UnitCost = cost,
                LastUpdated = DateTime.UtcNow
            };

            _inventory.Add(item.Id, item);
            return item.Id;
        }

        /// <summary>
        /// Updates the quantity of an item
        /// </summary>
        public bool UpdateQuantity(int itemId, int newQuantity)
        {
            if (!_inventory.ContainsKey(itemId))
                return false;

            _inventory[itemId].Quantity = newQuantity;
            _inventory[itemId].LastUpdated = DateTime.UtcNow;
            return true;
        }

        /// <summary>
        /// Gets items that are low in stock
        /// </summary>
        public IEnumerable<InventoryItem> GetLowStockItems(int threshold = 10)
        {
            return _inventory.Values.Where(item => item.Quantity < threshold);
        }

        /// <summary>
        /// Calculates total inventory value
        /// </summary>
        public decimal CalculateTotalValue()
        {
            return _inventory.Values.Sum(item => item.Quantity * item.UnitCost);
        }

        /// <summary>
        /// Removes an item from inventory
        /// </summary>
        public bool RemoveItem(int itemId)
        {
            return _inventory.Remove(itemId);
        }
    }

    public class InventoryItem
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public int Quantity { get; set; }
        public decimal UnitCost { get; set; }
        public DateTime LastUpdated { get; set; }
    }
}
