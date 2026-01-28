package com.ecommerce.model;

import java.math.BigDecimal;

public class Product {
    private Long productId;
    private String productName;
    private String sku;
    private BigDecimal price;
    private Integer stockQuantity;
    
    public Product() {
    }
    
    public Product(Long productId, String productName, String sku, BigDecimal price) {
        this.productId = productId;
        this.productName = productName;
        this.sku = sku;
        this.price = price;
    }
    
    public Long getProductId() {
        return productId;
    }
    
    public void setProductId(Long productId) {
        this.productId = productId;
    }
    
    public String getProductName() {
        return productName;
    }
    
    public void setProductName(String productName) {
        this.productName = productName;
    }
    
    public String getSku() {
        return sku;
    }
    
    public void setSku(String sku) {
        this.sku = sku;
    }
    
    public BigDecimal getPrice() {
        return price;
    }
    
    public void setPrice(BigDecimal price) {
        this.price = price;
    }
    
    public Integer getStockQuantity() {
        return stockQuantity;
    }
    
    public void setStockQuantity(Integer stockQuantity) {
        this.stockQuantity = stockQuantity;
    }
}
