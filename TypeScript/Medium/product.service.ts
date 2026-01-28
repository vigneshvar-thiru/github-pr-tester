import { Injectable } from '@angular/core';
import { HttpClient, HttpHeaders, HttpParams, HttpErrorResponse } from '@angular/common/http';
import { Observable, throwError, BehaviorSubject } from 'rxjs';
import { catchError, map, tap, retry, debounceTime, distinctUntilChanged } from 'rxjs/operators';
import { Product, ProductCategory, ProductVariant, ProductReview } from '../Small/product.model';

@Injectable({
  providedIn: 'root'
})
export class ProductService {
  private apiUrl = '/api/products';
  private cartItemsSubject = new BehaviorSubject<number>(0);
  public cartItems$ = this.cartItemsSubject.asObservable();

  private httpOptions = {
    headers: new HttpHeaders({
      'Content-Type': 'application/json'
    })
  };

  constructor(private http: HttpClient) {
    this.loadCartCount();
  }

  private loadCartCount(): void {
    const count = localStorage.getItem('cartItemsCount');
    if (count) {
      this.cartItemsSubject.next(parseInt(count, 10));
    }
  }

  getAllProducts(page: number = 0, size: number = 20, category?: ProductCategory): Observable<{ products: Product[], total: number }> {
    let params = new HttpParams()
      .set('page', page.toString())
      .set('size', size.toString());

    if (category) {
      params = params.set('category', category);
    }

    return this.http.get<{ products: Product[], total: number }>(this.apiUrl, { params })
      .pipe(
        retry(2),
        catchError(this.handleError)
      );
  }

  getProductById(id: string): Observable<Product> {
    return this.http.get<Product>(`${this.apiUrl}/${id}`)
      .pipe(
        retry(2),
        catchError(this.handleError)
      );
  }

  createProduct(product: Partial<Product>): Observable<Product> {
    return this.http.post<Product>(this.apiUrl, product, this.httpOptions)
      .pipe(
        tap(newProduct => console.log(`Created product: ${newProduct.name}`)),
        catchError(this.handleError)
      );
  }

  updateProduct(id: string, product: Partial<Product>): Observable<Product> {
    return this.http.put<Product>(`${this.apiUrl}/${id}`, product, this.httpOptions)
      .pipe(
        tap(updatedProduct => console.log(`Updated product: ${updatedProduct.name}`)),
        catchError(this.handleError)
      );
  }

  deleteProduct(id: string): Observable<void> {
    return this.http.delete<void>(`${this.apiUrl}/${id}`)
      .pipe(
        tap(() => console.log(`Deleted product: ${id}`)),
        catchError(this.handleError)
      );
  }

  searchProducts(query: string, filters?: { minPrice?: number, maxPrice?: number, category?: ProductCategory }): Observable<Product[]> {
    let params = new HttpParams().set('q', query);

    if (filters) {
      if (filters.minPrice !== undefined) {
        params = params.set('minPrice', filters.minPrice.toString());
      }
      if (filters.maxPrice !== undefined) {
        params = params.set('maxPrice', filters.maxPrice.toString());
      }
      if (filters.category) {
        params = params.set('category', filters.category);
      }
    }

    return this.http.get<Product[]>(`${this.apiUrl}/search`, { params })
      .pipe(
        debounceTime(300),
        distinctUntilChanged(),
        catchError(this.handleError)
      );
  }

  getProductsByCategory(category: ProductCategory): Observable<Product[]> {
    return this.http.get<Product[]>(`${this.apiUrl}/category/${category}`)
      .pipe(
        retry(2),
        catchError(this.handleError)
      );
  }

  getFeaturedProducts(): Observable<Product[]> {
    return this.http.get<Product[]>(`${this.apiUrl}/featured`)
      .pipe(
        retry(2),
        catchError(this.handleError)
      );
  }

  updateStock(id: string, quantity: number): Observable<Product> {
    return this.http.patch<Product>(`${this.apiUrl}/${id}/stock`, { quantity }, this.httpOptions)
      .pipe(
        catchError(this.handleError)
      );
  }

  getProductVariants(productId: string): Observable<ProductVariant[]> {
    return this.http.get<ProductVariant[]>(`${this.apiUrl}/${productId}/variants`)
      .pipe(
        catchError(this.handleError)
      );
  }

  getProductReviews(productId: string): Observable<ProductReview[]> {
    return this.http.get<ProductReview[]>(`${this.apiUrl}/${productId}/reviews`)
      .pipe(
        catchError(this.handleError)
      );
  }

  addProductReview(productId: string, review: Partial<ProductReview>): Observable<ProductReview> {
    return this.http.post<ProductReview>(`${this.apiUrl}/${productId}/reviews`, review, this.httpOptions)
      .pipe(
        catchError(this.handleError)
      );
  }

  private handleError(error: HttpErrorResponse): Observable<never> {
    let errorMessage = 'An unknown error occurred';
    
    if (error.error instanceof ErrorEvent) {
      errorMessage = `Client Error: ${error.error.message}`;
    } else {
      errorMessage = `Server Error Code: ${error.status}\nMessage: ${error.message}`;
    }
    
    console.error(errorMessage);
    return throwError(() => new Error(errorMessage));
  }
}
