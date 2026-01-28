using System;
using System.Collections.Generic;
using System.Linq;

namespace SampleApp.Services
{
    /// <summary>
    /// Service for managing customer operations
    /// Updated: Enhanced with validation
    /// </summary>
    public class CustomerService
    {
        private readonly List<Customer> _customers;

        public CustomerService()
        {
            _customers = new List<Customer>();
        }

        /// <summary>
        /// Adds a new customer to the system
        /// </summary>
        public void AddCustomer(Customer customer)
        {
            if (customer == null)
                throw new ArgumentNullException(nameof(customer));

            if (string.IsNullOrWhiteSpace(customer.Email))
                throw new ArgumentException("Email is required");

            _customers.Add(customer);
        }

        /// <summary>
        /// Retrieves a customer by ID
        /// </summary>
        public Customer GetCustomerById(int id)
        {
            return _customers.FirstOrDefault(c => c.Id == id);
        }

        /// <summary>
        /// Gets all active customers
        /// </summary>
        public IEnumerable<Customer> GetActiveCustomers()
        {
            return _customers.Where(c => c.IsActive);
        }

        /// <summary>
        /// Updates customer information
        /// </summary>
        public bool UpdateCustomer(int id, Customer updatedCustomer)
        {
            var customer = GetCustomerById(id);
            if (customer == null)
                return false;

            customer.Name = updatedCustomer.Name;
            customer.Email = updatedCustomer.Email;
            customer.IsActive = updatedCustomer.IsActive;
            return true;
        }

        /// <summary>
        /// Deletes a customer from the system
        /// </summary>
        public bool DeleteCustomer(int id)
        {
            var customer = GetCustomerById(id);
            if (customer == null)
                return false;

            return _customers.Remove(customer);
        }
    }

    public class Customer
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Email { get; set; }
        public bool IsActive { get; set; }
    }
}
