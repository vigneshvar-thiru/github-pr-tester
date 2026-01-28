// Updated: Added discount field
export interface Product {
  id: string;
  name: string;
  description: string;
  price: number;
  category: ProductCategory;
  stock: number;
  imageUrl: string;
  sku: string;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
  discount?: number;
}

export enum ProductCategory {
  ELECTRONICS = 'ELECTRONICS',
  CLOTHING = 'CLOTHING',
  BOOKS = 'BOOKS',
  HOME = 'HOME',
  SPORTS = 'SPORTS',
  TOYS = 'TOYS',
  FOOD = 'FOOD'
}

export interface ProductVariant {
  id: string;
  productId: string;
  size?: string;
  color?: string;
  price: number;
  stock: number;
}

export interface ProductReview {
  id: string;
  productId: string;
  userId: string;
  rating: number;
  comment: string;
  createdAt: Date;
}
