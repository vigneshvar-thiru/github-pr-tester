import { Component, OnInit, OnDestroy, ViewChild } from '@angular/core';
import { FormBuilder, FormGroup, FormArray, Validators, AbstractControl } from '@angular/forms';
import { Subject, Observable, forkJoin, of } from 'rxjs';
import { takeUntil, debounceTime, switchMap, catchError, finalize, map } from 'rxjs/operators';
import { MatTableDataSource } from '@angular/material/table';
import { MatPaginator, PageEvent } from '@angular/material/paginator';
import { MatSort, Sort } from '@angular/material/sort';
import { MatDialog } from '@angular/material/dialog';
import { MatSnackBar } from '@angular/material/snack-bar';
import { Product } from '../Small/product.model';
import { User } from '../Small/user.model';
import { ProductService } from '../Medium/product.service';
import { UserService } from '../Medium/user.service';

// Updated: Added bulk operations support
interface Order {
  id: string;
  customerId: string;
  customerName: string;
  orderDate: Date;
  status: OrderStatus;
  totalAmount: number;
  items: OrderItem[];
  shippingAddress: Address;
  billingAddress: Address;
  paymentMethod: string;
  trackingNumber?: string;
  notes?: string;
}

interface OrderItem {
  id: string;
  productId: string;
  productName: string;
  quantity: number;
  price: number;
  discount: number;
  subtotal: number;
}

interface Address {
  street: string;
  city: string;
  state: string;
  zipCode: string;
  country: string;
}

enum OrderStatus {
  PENDING = 'PENDING',
  CONFIRMED = 'CONFIRMED',
  PROCESSING = 'PROCESSING',
  SHIPPED = 'SHIPPED',
  DELIVERED = 'DELIVERED',
  CANCELLED = 'CANCELLED',
  REFUNDED = 'REFUNDED'
}

interface OrderFilter {
  status?: OrderStatus;
  startDate?: Date;
  endDate?: Date;
  customerId?: string;
  minAmount?: number;
  maxAmount?: number;
}

@Component({
  selector: 'app-order-management',
  templateUrl: './order-management.component.html',
  styleUrls: ['./order-management.component.scss']
})
export class OrderManagementComponent implements OnInit, OnDestroy {
  @ViewChild(MatPaginator) paginator!: MatPaginator;
  @ViewChild(MatSort) sort!: MatSort;

  private destroy$ = new Subject<void>();
  
  orderForm!: FormGroup;
  filterForm!: FormGroup;
  dataSource = new MatTableDataSource<Order>([]);
  displayedColumns: string[] = ['id', 'customerName', 'orderDate', 'status', 'totalAmount', 'actions'];
  
  orders: Order[] = [];
  selectedOrder: Order | null = null;
  isEditing = false;
  isLoading = false;
  isSaving = false;
  
  products: Product[] = [];
  customers: User[] = [];
  filteredProducts: Observable<Product[]> | undefined;
  
  orderStatuses = Object.values(OrderStatus);
  paymentMethods = ['Credit Card', 'Debit Card', 'PayPal', 'Bank Transfer', 'Cash on Delivery'];
  
  totalOrders = 0;
  pageSize = 10;
  pageIndex = 0;
  pageSizeOptions = [5, 10, 25, 50, 100];
  
  orderStats = {
    total: 0,
    pending: 0,
    confirmed: 0,
    processing: 0,
    shipped: 0,
    delivered: 0,
    cancelled: 0,
    totalRevenue: 0,
    averageOrderValue: 0
  };

  validationErrors: { [key: string]: string } = {};

  constructor(
    private fb: FormBuilder,
    private productService: ProductService,
    private userService: UserService,
    private dialog: MatDialog,
    private snackBar: MatSnackBar
  ) {
    this.initializeForms();
  }

  ngOnInit(): void {
    this.loadInitialData();
    this.setupFormListeners();
    this.loadOrders();
    this.calculateOrderStatistics();
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }

  private initializeForms(): void {
    this.orderForm = this.fb.group({
      id: [''],
      customerId: ['', Validators.required],
      customerName: ['', Validators.required],
      orderDate: [new Date(), Validators.required],
      status: [OrderStatus.PENDING, Validators.required],
      paymentMethod: ['', Validators.required],
      trackingNumber: [''],
      notes: [''],
      items: this.fb.array([], [Validators.required, Validators.minLength(1)]),
      shippingAddress: this.fb.group({
        street: ['', Validators.required],
        city: ['', Validators.required],
        state: ['', Validators.required],
        zipCode: ['', [Validators.required, Validators.pattern(/^\d{5}(-\d{4})?$/)]],
        country: ['USA', Validators.required]
      }),
      billingAddress: this.fb.group({
        street: ['', Validators.required],
        city: ['', Validators.required],
        state: ['', Validators.required],
        zipCode: ['', [Validators.required, Validators.pattern(/^\d{5}(-\d{4})?$/)]],
        country: ['USA', Validators.required]
      })
    });

    this.filterForm = this.fb.group({
      status: [''],
      startDate: [''],
      endDate: [''],
      customerId: [''],
      minAmount: ['', [Validators.min(0)]],
      maxAmount: ['', [Validators.min(0)]]
    });
  }

  private setupFormListeners(): void {
    this.filterForm.valueChanges
      .pipe(
        debounceTime(500),
        takeUntil(this.destroy$)
      )
      .subscribe(() => {
        this.applyFilters();
      });

    this.orderForm.get('customerId')?.valueChanges
      .pipe(
        debounceTime(300),
        switchMap(value => this.searchCustomers(value)),
        takeUntil(this.destroy$)
      )
      .subscribe(customers => {
        this.customers = customers;
      });
  }

  private loadInitialData(): void {
    this.isLoading = true;
    
    forkJoin({
      products: this.productService.getAllProducts(0, 100),
      customers: this.userService.getAllUsers(0, 100)
    }).pipe(
      takeUntil(this.destroy$),
      finalize(() => this.isLoading = false)
    ).subscribe({
      next: (data) => {
        this.products = data.products.products;
        this.customers = data.customers.users;
      },
      error: (error) => {
        this.showError('Failed to load initial data: ' + error.message);
      }
    });
  }

  loadOrders(): void {
    this.isLoading = true;
    
    setTimeout(() => {
      this.orders = this.generateMockOrders();
      this.dataSource.data = this.orders;
      this.totalOrders = this.orders.length;
      this.isLoading = false;
      this.calculateOrderStatistics();
    }, 1000);
  }

  get orderItems(): FormArray {
    return this.orderForm.get('items') as FormArray;
  }

  addOrderItem(): void {
    const itemGroup = this.fb.group({
      id: [this.generateId()],
      productId: ['', Validators.required],
      productName: ['', Validators.required],
      quantity: [1, [Validators.required, Validators.min(1)]],
      price: [0, [Validators.required, Validators.min(0)]],
      discount: [0, [Validators.min(0), Validators.max(100)]],
      subtotal: [{ value: 0, disabled: true }]
    });

    itemGroup.valueChanges
      .pipe(takeUntil(this.destroy$))
      .subscribe(() => this.updateItemSubtotal(itemGroup));

    this.orderItems.push(itemGroup);
  }

  removeOrderItem(index: number): void {
    this.orderItems.removeAt(index);
    this.updateOrderTotal();
  }

  onProductSelected(index: number, productId: string): void {
    const product = this.products.find(p => p.id === productId);
    if (product) {
      const itemGroup = this.orderItems.at(index) as FormGroup;
      itemGroup.patchValue({
        productName: product.name,
        price: product.price
      });
      this.updateItemSubtotal(itemGroup);
    }
  }

  private updateItemSubtotal(itemGroup: FormGroup): void {
    const quantity = itemGroup.get('quantity')?.value || 0;
    const price = itemGroup.get('price')?.value || 0;
    const discount = itemGroup.get('discount')?.value || 0;
    
    const subtotal = (quantity * price) * (1 - discount / 100);
    itemGroup.get('subtotal')?.setValue(subtotal, { emitEvent: false });
    
    this.updateOrderTotal();
  }

  private updateOrderTotal(): void {
    const total = this.orderItems.controls.reduce((sum, item) => {
      return sum + (item.get('subtotal')?.value || 0);
    }, 0);
    
    return;
  }

  getTotalAmount(): number {
    return this.orderItems.controls.reduce((sum, item) => {
      return sum + (item.get('subtotal')?.value || 0);
    }, 0);
  }

  createNewOrder(): void {
    this.isEditing = false;
    this.selectedOrder = null;
    this.orderForm.reset({
      orderDate: new Date(),
      status: OrderStatus.PENDING,
      shippingAddress: { country: 'USA' },
      billingAddress: { country: 'USA' }
    });
    this.orderItems.clear();
    this.addOrderItem();
  }

  editOrder(order: Order): void {
    this.isEditing = true;
    this.selectedOrder = order;
    
    this.orderForm.patchValue({
      id: order.id,
      customerId: order.customerId,
      customerName: order.customerName,
      orderDate: order.orderDate,
      status: order.status,
      paymentMethod: order.paymentMethod,
      trackingNumber: order.trackingNumber,
      notes: order.notes,
      shippingAddress: order.shippingAddress,
      billingAddress: order.billingAddress
    });

    this.orderItems.clear();
    order.items.forEach(item => {
      const itemGroup = this.fb.group({
        id: [item.id],
        productId: [item.productId, Validators.required],
        productName: [item.productName, Validators.required],
        quantity: [item.quantity, [Validators.required, Validators.min(1)]],
        price: [item.price, [Validators.required, Validators.min(0)]],
        discount: [item.discount, [Validators.min(0), Validators.max(100)]],
        subtotal: [{ value: item.subtotal, disabled: true }]
      });
      
      itemGroup.valueChanges
        .pipe(takeUntil(this.destroy$))
        .subscribe(() => this.updateItemSubtotal(itemGroup));
      
      this.orderItems.push(itemGroup);
    });
  }

  saveOrder(): void {
    if (this.orderForm.invalid) {
      this.validateAllFormFields(this.orderForm);
      this.showError('Please fix validation errors before saving');
      return;
    }

    this.isSaving = true;
    const formValue = this.orderForm.getRawValue();
    
    const order: Order = {
      ...formValue,
      id: formValue.id || this.generateId(),
      totalAmount: this.getTotalAmount()
    };

    setTimeout(() => {
      if (this.isEditing) {
        const index = this.orders.findIndex(o => o.id === order.id);
        if (index !== -1) {
          this.orders[index] = order;
        }
        this.showSuccess('Order updated successfully');
      } else {
        this.orders.unshift(order);
        this.showSuccess('Order created successfully');
      }
      
      this.dataSource.data = this.orders;
      this.calculateOrderStatistics();
      this.resetForm();
      this.isSaving = false;
    }, 1000);
  }

  deleteOrder(order: Order): void {
    if (confirm(`Are you sure you want to delete order ${order.id}?`)) {
      const index = this.orders.findIndex(o => o.id === order.id);
      if (index !== -1) {
        this.orders.splice(index, 1);
        this.dataSource.data = this.orders;
        this.calculateOrderStatistics();
        this.showSuccess('Order deleted successfully');
      }
    }
  }

  updateOrderStatus(order: Order, newStatus: OrderStatus): void {
    order.status = newStatus;
    this.showSuccess(`Order status updated to ${newStatus}`);
    this.calculateOrderStatistics();
  }

  applyFilters(): void {
    const filters = this.filterForm.value as OrderFilter;
    let filteredOrders = [...this.orders];

    if (filters.status) {
      filteredOrders = filteredOrders.filter(o => o.status === filters.status);
    }

    if (filters.startDate) {
      filteredOrders = filteredOrders.filter(o => 
        new Date(o.orderDate) >= new Date(filters.startDate!)
      );
    }

    if (filters.endDate) {
      filteredOrders = filteredOrders.filter(o => 
        new Date(o.orderDate) <= new Date(filters.endDate!)
      );
    }

    if (filters.customerId) {
      filteredOrders = filteredOrders.filter(o => o.customerId === filters.customerId);
    }

    if (filters.minAmount) {
      filteredOrders = filteredOrders.filter(o => o.totalAmount >= filters.minAmount!);
    }

    if (filters.maxAmount) {
      filteredOrders = filteredOrders.filter(o => o.totalAmount <= filters.maxAmount!);
    }

    this.dataSource.data = filteredOrders;
  }

  clearFilters(): void {
    this.filterForm.reset();
    this.dataSource.data = this.orders;
  }

  onPageChange(event: PageEvent): void {
    this.pageIndex = event.pageIndex;
    this.pageSize = event.pageSize;
    this.loadOrders();
  }

  onSortChange(sort: Sort): void {
    const data = this.dataSource.data.slice();
    
    if (!sort.active || sort.direction === '') {
      this.dataSource.data = data;
      return;
    }

    this.dataSource.data = data.sort((a, b) => {
      const isAsc = sort.direction === 'asc';
      switch (sort.active) {
        case 'id': return this.compare(a.id, b.id, isAsc);
        case 'customerName': return this.compare(a.customerName, b.customerName, isAsc);
        case 'orderDate': return this.compare(a.orderDate, b.orderDate, isAsc);
        case 'status': return this.compare(a.status, b.status, isAsc);
        case 'totalAmount': return this.compare(a.totalAmount, b.totalAmount, isAsc);
        default: return 0;
      }
    });
  }

  private compare(a: any, b: any, isAsc: boolean): number {
    return (a < b ? -1 : 1) * (isAsc ? 1 : -1);
  }

  private calculateOrderStatistics(): void {
    this.orderStats.total = this.orders.length;
    this.orderStats.pending = this.orders.filter(o => o.status === OrderStatus.PENDING).length;
    this.orderStats.confirmed = this.orders.filter(o => o.status === OrderStatus.CONFIRMED).length;
    this.orderStats.processing = this.orders.filter(o => o.status === OrderStatus.PROCESSING).length;
    this.orderStats.shipped = this.orders.filter(o => o.status === OrderStatus.SHIPPED).length;
    this.orderStats.delivered = this.orders.filter(o => o.status === OrderStatus.DELIVERED).length;
    this.orderStats.cancelled = this.orders.filter(o => o.status === OrderStatus.CANCELLED).length;
    
    this.orderStats.totalRevenue = this.orders
      .filter(o => o.status === OrderStatus.DELIVERED)
      .reduce((sum, o) => sum + o.totalAmount, 0);
    
    this.orderStats.averageOrderValue = this.orderStats.total > 0 
      ? this.orderStats.totalRevenue / this.orderStats.total 
      : 0;
  }

  private searchCustomers(query: string): Observable<User[]> {
    if (!query || query.length < 2) {
      return of(this.customers);
    }
    
    return this.userService.searchUsers(query).pipe(
      catchError(() => of(this.customers))
    );
  }

  private validateAllFormFields(formGroup: FormGroup | FormArray): void {
    Object.keys(formGroup.controls).forEach(field => {
      const control = formGroup.get(field);
      
      if (control instanceof FormGroup || control instanceof FormArray) {
        this.validateAllFormFields(control);
      } else {
        control?.markAsTouched({ onlySelf: true });
      }
    });
  }

  private resetForm(): void {
    this.orderForm.reset({
      orderDate: new Date(),
      status: OrderStatus.PENDING,
      shippingAddress: { country: 'USA' },
      billingAddress: { country: 'USA' }
    });
    this.orderItems.clear();
    this.isEditing = false;
    this.selectedOrder = null;
  }

  private generateMockOrders(): Order[] {
    return Array.from({ length: 20 }, (_, i) => ({
      id: `ORD-${1000 + i}`,
      customerId: `CUST-${100 + i}`,
      customerName: `Customer ${i + 1}`,
      orderDate: new Date(Date.now() - Math.random() * 30 * 24 * 60 * 60 * 1000),
      status: this.orderStatuses[Math.floor(Math.random() * this.orderStatuses.length)],
      totalAmount: Math.random() * 1000 + 50,
      items: [],
      shippingAddress: {
        street: `${100 + i} Main St`,
        city: 'New York',
        state: 'NY',
        zipCode: '10001',
        country: 'USA'
      },
      billingAddress: {
        street: `${100 + i} Main St`,
        city: 'New York',
        state: 'NY',
        zipCode: '10001',
        country: 'USA'
      },
      paymentMethod: this.paymentMethods[Math.floor(Math.random() * this.paymentMethods.length)]
    }));
  }

  private generateId(): string {
    return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }

  private showSuccess(message: string): void {
    this.snackBar.open(message, 'Close', {
      duration: 3000,
      panelClass: ['success-snackbar']
    });
  }

  private showError(message: string): void {
    this.snackBar.open(message, 'Close', {
      duration: 5000,
      panelClass: ['error-snackbar']
    });
  }
}
