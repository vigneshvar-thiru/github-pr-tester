"""
Product model for e-commerce application
Updated: Initial version with basic product class
"""

from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from typing import Optional


@dataclass
class Product:
    """Product entity representing an item in the catalog"""
    
    product_id: int
    name: str
    sku: str
    price: Decimal
    stock_quantity: int
    category: str
    description: Optional[str] = None
    created_at: datetime = None
    updated_at: datetime = None
    is_active: bool = True
    
    def __post_init__(self):
        """Initialize timestamps if not provided"""
        if self.created_at is None:
            self.created_at = datetime.now()
        if self.updated_at is None:
            self.updated_at = datetime.now()
    
    def is_in_stock(self) -> bool:
        """Check if product is currently in stock"""
        return self.stock_quantity > 0
    
    def update_stock(self, quantity: int) -> None:
        """Update stock quantity and timestamp"""
        self.stock_quantity = quantity
        self.updated_at = datetime.now()
    
    def apply_discount(self, discount_percent: float) -> Decimal:
        """Calculate discounted price"""
        discount = self.price * Decimal(str(discount_percent / 100))
        return self.price - discount
