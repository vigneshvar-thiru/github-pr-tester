package com.ecommerce.service;

import com.ecommerce.model.Product;
import com.ecommerce.repository.ProductRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

/**
 * Service class for managing product operations
 */
@Service
@Transactional
public class ProductService {
    
    private final ProductRepository productRepository;
    
    @Autowired
    public ProductService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }
    
    /**
     * Creates a new product
     * @param product the product to create
     * @return the created product
     */
    public Product createProduct(Product product) {
        validateProduct(product);
        return productRepository.save(product);
    }
    
    /**
     * Updates an existing product
     * @param id the product ID
     * @param product the updated product data
     * @return the updated product
     */
    public Product updateProduct(Long id, Product product) {
        Optional<Product> existing = productRepository.findById(id);
        if (!existing.isPresent()) {
            throw new RuntimeException("Product not found with id: " + id);
        }
        
        product.setProductId(id);
        validateProduct(product);
        return productRepository.save(product);
    }
    
    /**
     * Finds a product by ID
     * @param id the product ID
     * @return the product if found
     */
    public Optional<Product> findById(Long id) {
        return productRepository.findById(id);
    }
    
    /**
     * Finds all products
     * @return list of all products
     */
    public List<Product> findAll() {
        return productRepository.findAll();
    }
    
    /**
     * Finds products by name containing the search term
     * @param name the search term
     * @return list of matching products
     */
    public List<Product> findByName(String name) {
        return productRepository.findByProductNameContaining(name);
    }
    
    /**
     * Deletes a product by ID
     * @param id the product ID
     */
    public void deleteProduct(Long id) {
        if (!productRepository.existsById(id)) {
            throw new RuntimeException("Product not found with id: " + id);
        }
        productRepository.deleteById(id);
    }
    
    /**
     * Updates product stock quantity
     * @param id the product ID
     * @param quantity the quantity to add (can be negative)
     * @return the updated product
     */
    public Product updateStock(Long id, Integer quantity) {
        Product product = productRepository.findById(id)
            .orElseThrow(() -> new RuntimeException("Product not found with id: " + id));
        
        Integer newQuantity = product.getStockQuantity() + quantity;
        if (newQuantity < 0) {
            throw new RuntimeException("Insufficient stock");
        }
        
        product.setStockQuantity(newQuantity);
        return productRepository.save(product);
    }
    
    /**
     * Validates product data
     * @param product the product to validate
     */
    private void validateProduct(Product product) {
        if (product.getProductName() == null || product.getProductName().trim().isEmpty()) {
            throw new IllegalArgumentException("Product name is required");
        }
        
        if (product.getSku() == null || product.getSku().trim().isEmpty()) {
            throw new IllegalArgumentException("SKU is required");
        }
        
        if (product.getPrice() == null || product.getPrice().compareTo(BigDecimal.ZERO) < 0) {
            throw new IllegalArgumentException("Price must be non-negative");
        }
    }
}
