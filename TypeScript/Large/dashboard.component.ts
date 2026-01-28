import { Component, OnInit, OnDestroy, ViewChild, AfterViewInit } from '@angular/core';
import { Subject, interval, forkJoin, Observable } from 'rxjs';
import { takeUntil, switchMap, map, catchError } from 'rxjs/operators';
import { Chart, ChartConfiguration, ChartType, registerables } from 'chart.js';
import { BaseChartDirective } from 'ng2-charts';
import { ProductService } from '../Medium/product.service';
import { UserService } from '../Medium/user.service';
import { Product, ProductCategory } from '../Small/product.model';
import { User, UserRole } from '../Small/user.model';

Chart.register(...registerables);

interface DashboardMetrics {
  totalRevenue: number;
  totalOrders: number;
  totalCustomers: number;
  totalProducts: number;
  averageOrderValue: number;
  conversionRate: number;
  revenueGrowth: number;
  customerGrowth: number;
}

interface SalesData {
  date: string;
  revenue: number;
  orders: number;
  customers: number;
}

interface TopProduct {
  id: string;
  name: string;
  category: ProductCategory;
  totalSales: number;
  unitsSold: number;
  revenue: number;
}

interface CategoryPerformance {
  category: ProductCategory;
  totalRevenue: number;
  totalOrders: number;
  averageOrderValue: number;
  growthRate: number;
}

interface CustomerSegment {
  segment: string;
  count: number;
  percentage: number;
  revenue: number;
  averageOrderValue: number;
}

interface RevenueBreakdown {
  product: number;
  shipping: number;
  tax: number;
  discount: number;
}

@Component({
  selector: 'app-dashboard',
  templateUrl: './dashboard.component.html',
  styleUrls: ['./dashboard.component.scss']
})
export class DashboardComponent implements OnInit, OnDestroy, AfterViewInit {
  @ViewChild('revenueChart') revenueChartRef?: BaseChartDirective;
  @ViewChild('categoryChart') categoryChartRef?: BaseChartDirective;
  @ViewChild('customerChart') customerChartRef?: BaseChartDirective;

  private destroy$ = new Subject<void>();
  private refreshInterval$ = interval(300000);

  isLoading = true;
  selectedTimeRange: 'day' | 'week' | 'month' | 'year' = 'month';
  selectedMetric: 'revenue' | 'orders' | 'customers' = 'revenue';

  metrics: DashboardMetrics = {
    totalRevenue: 0,
    totalOrders: 0,
    totalCustomers: 0,
    totalProducts: 0,
    averageOrderValue: 0,
    conversionRate: 0,
    revenueGrowth: 0,
    customerGrowth: 0
  };

  salesData: SalesData[] = [];
  topProducts: TopProduct[] = [];
  categoryPerformance: CategoryPerformance[] = [];
  customerSegments: CustomerSegment[] = [];
  revenueBreakdown: RevenueBreakdown = {
    product: 0,
    shipping: 0,
    tax: 0,
    discount: 0
  };

  recentOrders: any[] = [];
  recentCustomers: User[] = [];
  lowStockProducts: Product[] = [];

  revenueChartConfig: ChartConfiguration<'line'> = {
    type: 'line',
    data: {
      labels: [],
      datasets: [
        {
          label: 'Revenue',
          data: [],
          borderColor: 'rgb(75, 192, 192)',
          backgroundColor: 'rgba(75, 192, 192, 0.2)',
          tension: 0.4,
          fill: true
        },
        {
          label: 'Orders',
          data: [],
          borderColor: 'rgb(255, 99, 132)',
          backgroundColor: 'rgba(255, 99, 132, 0.2)',
          tension: 0.4,
          fill: true,
          yAxisID: 'y1'
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: {
        mode: 'index',
        intersect: false,
      },
      scales: {
        y: {
          type: 'linear',
          display: true,
          position: 'left',
          title: {
            display: true,
            text: 'Revenue ($)'
          }
        },
        y1: {
          type: 'linear',
          display: true,
          position: 'right',
          title: {
            display: true,
            text: 'Orders'
          },
          grid: {
            drawOnChartArea: false,
          }
        }
      },
      plugins: {
        legend: {
          display: true,
          position: 'top'
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              let label = context.dataset.label || '';
              if (label) {
                label += ': ';
              }
              if (context.parsed.y !== null) {
                label += new Intl.NumberFormat('en-US', {
                  style: 'currency',
                  currency: 'USD'
                }).format(context.parsed.y);
              }
              return label;
            }
          }
        }
      }
    }
  };

  categoryChartConfig: ChartConfiguration<'doughnut'> = {
    type: 'doughnut',
    data: {
      labels: [],
      datasets: [{
        data: [],
        backgroundColor: [
          'rgba(255, 99, 132, 0.8)',
          'rgba(54, 162, 235, 0.8)',
          'rgba(255, 206, 86, 0.8)',
          'rgba(75, 192, 192, 0.8)',
          'rgba(153, 102, 255, 0.8)',
          'rgba(255, 159, 64, 0.8)',
          'rgba(199, 199, 199, 0.8)'
        ],
        borderWidth: 2
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          display: true,
          position: 'right'
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              const label = context.label || '';
              const value = context.parsed || 0;
              const total = context.dataset.data.reduce((a: number, b: number) => a + b, 0);
              const percentage = ((value / total) * 100).toFixed(1);
              return `${label}: $${value.toLocaleString()} (${percentage}%)`;
            }
          }
        }
      }
    }
  };

  customerChartConfig: ChartConfiguration<'bar'> = {
    type: 'bar',
    data: {
      labels: [],
      datasets: [{
        label: 'Customers',
        data: [],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Number of Customers'
          }
        }
      },
      plugins: {
        legend: {
          display: false
        }
      }
    }
  };

  constructor(
    private productService: ProductService,
    private userService: UserService
  ) {}

  ngOnInit(): void {
    this.loadDashboardData();
    this.setupAutoRefresh();
  }

  ngAfterViewInit(): void {
    setTimeout(() => {
      this.initializeCharts();
    }, 100);
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }

  private setupAutoRefresh(): void {
    this.refreshInterval$
      .pipe(takeUntil(this.destroy$))
      .subscribe(() => {
        this.refreshDashboard();
      });
  }

  loadDashboardData(): void {
    this.isLoading = true;

    forkJoin({
      products: this.productService.getAllProducts(0, 100),
      customers: this.userService.getAllUsers(0, 100, UserRole.CUSTOMER)
    })
      .pipe(
        takeUntil(this.destroy$),
        map(data => {
          this.processMetrics(data);
          this.processSalesData();
          this.processTopProducts(data.products.products);
          this.processCategoryPerformance(data.products.products);
          this.processCustomerSegments(data.customers.users);
          this.processRevenueBreakdown();
          this.loadRecentActivity(data);
          return data;
        }),
        catchError(error => {
          console.error('Error loading dashboard data:', error);
          this.isLoading = false;
          throw error;
        })
      )
      .subscribe({
        next: () => {
          this.isLoading = false;
          this.updateCharts();
        },
        error: (error) => {
          console.error('Dashboard loading failed:', error);
          this.isLoading = false;
        }
      });
  }

  private processMetrics(data: any): void {
    this.metrics.totalProducts = data.products.total;
    this.metrics.totalCustomers = data.customers.total;
    this.metrics.totalRevenue = this.generateRandomMetric(50000, 500000);
    this.metrics.totalOrders = this.generateRandomMetric(500, 5000);
    this.metrics.averageOrderValue = this.metrics.totalRevenue / this.metrics.totalOrders;
    this.metrics.conversionRate = Math.random() * 5 + 2;
    this.metrics.revenueGrowth = Math.random() * 30 - 10;
    this.metrics.customerGrowth = Math.random() * 25 - 5;
  }

  private processSalesData(): void {
    const days = this.getTimeRangeDays();
    this.salesData = Array.from({ length: days }, (_, i) => {
      const date = new Date();
      date.setDate(date.getDate() - (days - i - 1));
      
      return {
        date: date.toISOString().split('T')[0],
        revenue: Math.random() * 10000 + 5000,
        orders: Math.floor(Math.random() * 100 + 50),
        customers: Math.floor(Math.random() * 50 + 20)
      };
    });
  }

  private processTopProducts(products: Product[]): void {
    this.topProducts = products
      .slice(0, 10)
      .map(product => ({
        id: product.id,
        name: product.name,
        category: product.category,
        totalSales: Math.floor(Math.random() * 500 + 100),
        unitsSold: Math.floor(Math.random() * 1000 + 200),
        revenue: Math.random() * 50000 + 10000
      }))
      .sort((a, b) => b.revenue - a.revenue);
  }

  private processCategoryPerformance(products: Product[]): void {
    const categories = Object.values(ProductCategory);
    
    this.categoryPerformance = categories.map(category => ({
      category,
      totalRevenue: Math.random() * 100000 + 20000,
      totalOrders: Math.floor(Math.random() * 1000 + 200),
      averageOrderValue: 0,
      growthRate: Math.random() * 40 - 10
    }));

    this.categoryPerformance.forEach(perf => {
      perf.averageOrderValue = perf.totalRevenue / perf.totalOrders;
    });

    this.categoryPerformance.sort((a, b) => b.totalRevenue - a.totalRevenue);
  }

  private processCustomerSegments(customers: User[]): void {
    const segments = [
      { segment: 'VIP', basePercentage: 5 },
      { segment: 'Loyal', basePercentage: 15 },
      { segment: 'Regular', basePercentage: 40 },
      { segment: 'New', basePercentage: 30 },
      { segment: 'Inactive', basePercentage: 10 }
    ];

    let totalCustomers = customers.length || 1000;
    
    this.customerSegments = segments.map(seg => {
      const count = Math.floor(totalCustomers * (seg.basePercentage / 100));
      const revenue = count * (Math.random() * 500 + 100);
      
      return {
        segment: seg.segment,
        count: count,
        percentage: seg.basePercentage,
        revenue: revenue,
        averageOrderValue: revenue / count
      };
    });
  }

  private processRevenueBreakdown(): void {
    const total = this.metrics.totalRevenue;
    this.revenueBreakdown = {
      product: total * 0.82,
      shipping: total * 0.08,
      tax: total * 0.07,
      discount: total * 0.03
    };
  }

  private loadRecentActivity(data: any): void {
    this.recentOrders = Array.from({ length: 5 }, (_, i) => ({
      id: `ORD-${1000 + i}`,
      customerName: `Customer ${i + 1}`,
      amount: Math.random() * 500 + 50,
      status: ['PENDING', 'CONFIRMED', 'SHIPPED'][Math.floor(Math.random() * 3)],
      date: new Date(Date.now() - Math.random() * 24 * 60 * 60 * 1000)
    }));

    this.recentCustomers = data.customers.users.slice(0, 5);
    
    this.lowStockProducts = data.products.products
      .filter((p: Product) => p.stock < 20)
      .slice(0, 5);
  }

  private initializeCharts(): void {
    this.updateCharts();
  }

  private updateCharts(): void {
    this.updateRevenueChart();
    this.updateCategoryChart();
    this.updateCustomerChart();
  }

  private updateRevenueChart(): void {
    if (this.revenueChartConfig.data) {
      this.revenueChartConfig.data.labels = this.salesData.map(d => d.date);
      this.revenueChartConfig.data.datasets[0].data = this.salesData.map(d => d.revenue);
      this.revenueChartConfig.data.datasets[1].data = this.salesData.map(d => d.orders);
      
      this.revenueChartRef?.update();
    }
  }

  private updateCategoryChart(): void {
    if (this.categoryChartConfig.data) {
      this.categoryChartConfig.data.labels = this.categoryPerformance.map(c => c.category);
      this.categoryChartConfig.data.datasets[0].data = this.categoryPerformance.map(c => c.totalRevenue);
      
      this.categoryChartRef?.update();
    }
  }

  private updateCustomerChart(): void {
    if (this.customerChartConfig.data) {
      this.customerChartConfig.data.labels = this.customerSegments.map(s => s.segment);
      this.customerChartConfig.data.datasets[0].data = this.customerSegments.map(s => s.count);
      
      this.customerChartRef?.update();
    }
  }

  changeTimeRange(range: 'day' | 'week' | 'month' | 'year'): void {
    this.selectedTimeRange = range;
    this.processSalesData();
    this.updateRevenueChart();
  }

  changeMetric(metric: 'revenue' | 'orders' | 'customers'): void {
    this.selectedMetric = metric;
    this.updateRevenueChart();
  }

  refreshDashboard(): void {
    this.loadDashboardData();
  }

  exportData(format: 'csv' | 'pdf' | 'excel'): void {
    console.log(`Exporting dashboard data as ${format}`);
  }

  private getTimeRangeDays(): number {
    switch (this.selectedTimeRange) {
      case 'day': return 1;
      case 'week': return 7;
      case 'month': return 30;
      case 'year': return 365;
      default: return 30;
    }
  }

  private generateRandomMetric(min: number, max: number): number {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  getMetricIcon(metric: string): string {
    const icons: { [key: string]: string } = {
      totalRevenue: 'attach_money',
      totalOrders: 'shopping_cart',
      totalCustomers: 'people',
      totalProducts: 'inventory',
      averageOrderValue: 'trending_up',
      conversionRate: 'analytics',
      revenueGrowth: 'show_chart',
      customerGrowth: 'person_add'
    };
    return icons[metric] || 'info';
  }

  getMetricTrend(value: number): 'up' | 'down' | 'neutral' {
    if (value > 0) return 'up';
    if (value < 0) return 'down';
    return 'neutral';
  }

  formatCurrency(value: number): string {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 2
    }).format(value);
  }

  formatNumber(value: number): string {
    return new Intl.NumberFormat('en-US').format(value);
  }

  formatPercentage(value: number): string {
    return `${value.toFixed(1)}%`;
  }
}
