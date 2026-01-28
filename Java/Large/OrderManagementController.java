package com.ecommerce.controller;

import com.ecommerce.dto.*;
import com.ecommerce.exception.*;
import com.ecommerce.model.*;
import com.ecommerce.service.OrderService;
import com.ecommerce.validator.OrderValidator;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * REST Controller for Order Management Operations
 * Handles CRUD operations, order processing, and business logic for e-commerce orders
 */
@RestController
@RequestMapping("/api/v1/orders")
@Tag(name = "Order Management", description = "Endpoints for managing e-commerce orders")
@CrossOrigin(origins = "*", maxAge = 3600)
public class OrderManagementController {

    private static final Logger logger = LoggerFactory.getLogger(OrderManagementController.class);
    private static final int DEFAULT_PAGE_SIZE = 20;
    private static final int MAX_PAGE_SIZE = 100;

    @Autowired
    private OrderService orderService;

    @Autowired
    private OrderValidator orderValidator;

    /**
     * Get all orders with pagination and filtering
     */
    @GetMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'MANAGER')")
    @Operation(summary = "Get all orders", description = "Retrieve paginated list of orders with optional filtering")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Successfully retrieved orders"),
        @ApiResponse(responseCode = "403", description = "Access denied"),
        @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    public ResponseEntity<Map<String, Object>> getAllOrders(
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) int size,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String customerId,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime startDate,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime endDate,
            @RequestParam(defaultValue = "createdAt") String sortBy,
            @RequestParam(defaultValue = "DESC") String sortDirection) {

        logger.info("Fetching orders - Page: {}, Size: {}, Status: {}, CustomerId: {}", 
                    page, size, status, customerId);

        try {
            int validatedSize = Math.min(size, MAX_PAGE_SIZE);
            Sort sort = Sort.by(Sort.Direction.fromString(sortDirection), sortBy);
            Pageable pageable = PageRequest.of(page, validatedSize, sort);

            OrderFilterDTO filterDTO = OrderFilterDTO.builder()
                .status(status)
                .customerId(customerId)
                .startDate(startDate)
                .endDate(endDate)
                .build();

            Page<Order> orderPage = orderService.findAllOrders(filterDTO, pageable);

            Map<String, Object> response = new HashMap<>();
            response.put("orders", orderPage.getContent());
            response.put("currentPage", orderPage.getNumber());
            response.put("totalItems", orderPage.getTotalElements());
            response.put("totalPages", orderPage.getTotalPages());
            response.put("hasNext", orderPage.hasNext());
            response.put("hasPrevious", orderPage.hasPrevious());

            logger.info("Successfully retrieved {} orders", orderPage.getContent().size());
            return ResponseEntity.ok(response);

        } catch (Exception e) {
            logger.error("Error fetching orders: {}", e.getMessage(), e);
            throw new OrderProcessingException("Failed to retrieve orders", e);
        }
    }

    /**
     * Get order by ID
     */
    @GetMapping("/{orderId}")
    @PreAuthorize("hasAnyRole('ADMIN', 'MANAGER', 'CUSTOMER')")
    @Operation(summary = "Get order by ID", description = "Retrieve a specific order by its ID")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Order found"),
        @ApiResponse(responseCode = "404", description = "Order not found"),
        @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<OrderResponseDTO> getOrderById(
            @PathVariable @NotNull String orderId,
            @RequestHeader("X-User-Id") String userId) {

        logger.info("Fetching order with ID: {} for user: {}", orderId, userId);

        try {
            Order order = orderService.findOrderById(orderId)
                .orElseThrow(() -> new OrderNotFoundException("Order not found with ID: " + orderId));

            if (!orderService.hasAccessToOrder(userId, order)) {
                logger.warn("User {} attempted to access unauthorized order {}", userId, orderId);
                throw new UnauthorizedAccessException("You do not have permission to view this order");
            }

            OrderResponseDTO response = convertToResponseDTO(order);
            logger.info("Successfully retrieved order: {}", orderId);
            return ResponseEntity.ok(response);

        } catch (OrderNotFoundException e) {
            logger.error("Order not found: {}", orderId);
            throw e;
        } catch (Exception e) {
            logger.error("Error retrieving order {}: {}", orderId, e.getMessage(), e);
            throw new OrderProcessingException("Failed to retrieve order", e);
        }
    }

    /**
     * Create a new order
     */
    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'MANAGER', 'CUSTOMER')")
    @Operation(summary = "Create new order", description = "Create a new order with order items")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Order created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid order data"),
        @ApiResponse(responseCode = "422", description = "Validation error")
    })
    public ResponseEntity<OrderResponseDTO> createOrder(
            @Valid @RequestBody OrderCreateDTO orderCreateDTO,
            BindingResult bindingResult,
            @RequestHeader("X-User-Id") String userId) {

        logger.info("Creating new order for user: {}", userId);

        if (bindingResult.hasErrors()) {
            logger.error("Validation errors in order creation: {}", bindingResult.getAllErrors());
            throw new ValidationException("Invalid order data", bindingResult.getAllErrors());
        }

        try {
            orderValidator.validateOrderCreate(orderCreateDTO);

            Order order = new Order();
            order.setOrderId(UUID.randomUUID().toString());
            order.setCustomerId(orderCreateDTO.getCustomerId());
            order.setStatus(OrderStatus.PENDING);
            order.setCreatedAt(LocalDateTime.now());
            order.setUpdatedAt(LocalDateTime.now());

            List<OrderItem> orderItems = orderCreateDTO.getItems().stream()
                .map(this::convertToOrderItem)
                .collect(Collectors.toList());
            order.setItems(orderItems);

            BigDecimal totalAmount = calculateTotalAmount(orderItems);
            order.setTotalAmount(totalAmount);
            order.setSubtotal(totalAmount);
            order.setTax(calculateTax(totalAmount));
            order.setShippingCost(calculateShipping(orderCreateDTO));

            order.setShippingAddress(orderCreateDTO.getShippingAddress());
            order.setBillingAddress(orderCreateDTO.getBillingAddress());
            order.setPaymentMethod(orderCreateDTO.getPaymentMethod());

            Order savedOrder = orderService.createOrder(order);
            
            orderService.sendOrderConfirmationEmail(savedOrder);
            orderService.updateInventory(savedOrder);

            logger.info("Successfully created order: {}", savedOrder.getOrderId());
            
            OrderResponseDTO response = convertToResponseDTO(savedOrder);
            return ResponseEntity.status(HttpStatus.CREATED).body(response);

        } catch (ValidationException e) {
            logger.error("Validation failed for order creation: {}", e.getMessage());
            throw e;
        } catch (InsufficientStockException e) {
            logger.error("Insufficient stock for order: {}", e.getMessage());
            throw e;
        } catch (Exception e) {
            logger.error("Error creating order: {}", e.getMessage(), e);
            throw new OrderProcessingException("Failed to create order", e);
        }
    }

    /**
     * Update an existing order
     */
    @PutMapping("/{orderId}")
    @PreAuthorize("hasAnyRole('ADMIN', 'MANAGER')")
    @Operation(summary = "Update order", description = "Update an existing order")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Order updated successfully"),
        @ApiResponse(responseCode = "404", description = "Order not found"),
        @ApiResponse(responseCode = "400", description = "Invalid update data")
    })
    public ResponseEntity<OrderResponseDTO> updateOrder(
            @PathVariable @NotNull String orderId,
            @Valid @RequestBody OrderUpdateDTO orderUpdateDTO,
            BindingResult bindingResult) {

        logger.info("Updating order: {}", orderId);

        if (bindingResult.hasErrors()) {
            logger.error("Validation errors in order update: {}", bindingResult.getAllErrors());
            throw new ValidationException("Invalid update data", bindingResult.getAllErrors());
        }

        try {
            Order existingOrder = orderService.findOrderById(orderId)
                .orElseThrow(() -> new OrderNotFoundException("Order not found with ID: " + orderId));

            orderValidator.validateOrderUpdate(existingOrder, orderUpdateDTO);

            if (orderUpdateDTO.getStatus() != null) {
                validateStatusTransition(existingOrder.getStatus(), orderUpdateDTO.getStatus());
                existingOrder.setStatus(orderUpdateDTO.getStatus());
            }

            if (orderUpdateDTO.getShippingAddress() != null) {
                existingOrder.setShippingAddress(orderUpdateDTO.getShippingAddress());
            }

            if (orderUpdateDTO.getTrackingNumber() != null) {
                existingOrder.setTrackingNumber(orderUpdateDTO.getTrackingNumber());
            }

            existingOrder.setUpdatedAt(LocalDateTime.now());

            Order updatedOrder = orderService.updateOrder(existingOrder);
            
            orderService.sendOrderUpdateNotification(updatedOrder);

            logger.info("Successfully updated order: {}", orderId);
            
            OrderResponseDTO response = convertToResponseDTO(updatedOrder);
            return ResponseEntity.ok(response);

        } catch (OrderNotFoundException e) {
            logger.error("Order not found for update: {}", orderId);
            throw e;
        } catch (InvalidStatusTransitionException e) {
            logger.error("Invalid status transition: {}", e.getMessage());
            throw e;
        } catch (Exception e) {
            logger.error("Error updating order {}: {}", orderId, e.getMessage(), e);
            throw new OrderProcessingException("Failed to update order", e);
        }
    }

    /**
     * Delete/Cancel an order
     */
    @DeleteMapping("/{orderId}")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Delete order", description = "Delete or cancel an order")
    @ApiResponse(responseCode = "204", description = "Order deleted successfully")
    public ResponseEntity<Void> deleteOrder(@PathVariable @NotNull String orderId) {
        logger.info("Deleting order: {}", orderId);

        try {
            Order order = orderService.findOrderById(orderId)
                .orElseThrow(() -> new OrderNotFoundException("Order not found with ID: " + orderId));

            if (!orderService.canCancelOrder(order)) {
                throw new OrderCancellationException("Order cannot be cancelled in current status: " + order.getStatus());
            }

            orderService.deleteOrder(orderId);
            orderService.restoreInventory(order);
            orderService.processRefund(order);

            logger.info("Successfully deleted order: {}", orderId);
            return ResponseEntity.noContent().build();

        } catch (OrderNotFoundException e) {
            logger.error("Order not found for deletion: {}", orderId);
            throw e;
        } catch (Exception e) {
            logger.error("Error deleting order {}: {}", orderId, e.getMessage(), e);
            throw new OrderProcessingException("Failed to delete order", e);
        }
    }

    /**
     * Get orders by customer ID
     */
    @GetMapping("/customer/{customerId}")
    @PreAuthorize("hasAnyRole('ADMIN', 'MANAGER', 'CUSTOMER')")
    @Operation(summary = "Get customer orders", description = "Retrieve all orders for a specific customer")
    public ResponseEntity<List<OrderResponseDTO>> getOrdersByCustomerId(
            @PathVariable @NotNull String customerId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size) {

        logger.info("Fetching orders for customer: {}", customerId);

        try {
            Pageable pageable = PageRequest.of(page, size, Sort.by("createdAt").descending());
            List<Order> orders = orderService.findOrdersByCustomerId(customerId, pageable);

            List<OrderResponseDTO> response = orders.stream()
                .map(this::convertToResponseDTO)
                .collect(Collectors.toList());

            logger.info("Retrieved {} orders for customer {}", orders.size(), customerId);
            return ResponseEntity.ok(response);

        } catch (Exception e) {
            logger.error("Error fetching orders for customer {}: {}", customerId, e.getMessage(), e);
            throw new OrderProcessingException("Failed to retrieve customer orders", e);
        }
    }

    /**
     * Process payment for an order
     */
    @PostMapping("/{orderId}/payment")
    @PreAuthorize("hasAnyRole('ADMIN', 'MANAGER', 'CUSTOMER')")
    @Operation(summary = "Process payment", description = "Process payment for an order")
    public ResponseEntity<PaymentResponseDTO> processPayment(
            @PathVariable @NotNull String orderId,
            @Valid @RequestBody PaymentRequestDTO paymentRequest) {

        logger.info("Processing payment for order: {}", orderId);

        try {
            Order order = orderService.findOrderById(orderId)
                .orElseThrow(() -> new OrderNotFoundException("Order not found with ID: " + orderId));

            PaymentResponseDTO paymentResponse = orderService.processPayment(order, paymentRequest);
            
            if (paymentResponse.isSuccess()) {
                order.setStatus(OrderStatus.CONFIRMED);
                order.setPaymentStatus(PaymentStatus.COMPLETED);
                orderService.updateOrder(order);
                logger.info("Payment successful for order: {}", orderId);
            } else {
                order.setPaymentStatus(PaymentStatus.FAILED);
                orderService.updateOrder(order);
                logger.warn("Payment failed for order: {}", orderId);
            }

            return ResponseEntity.ok(paymentResponse);

        } catch (Exception e) {
            logger.error("Error processing payment for order {}: {}", orderId, e.getMessage(), e);
            throw new PaymentProcessingException("Failed to process payment", e);
        }
    }

    private OrderItem convertToOrderItem(OrderItemDTO dto) {
        OrderItem item = new OrderItem();
        item.setProductId(dto.getProductId());
        item.setProductName(dto.getProductName());
        item.setQuantity(dto.getQuantity());
        item.setPrice(dto.getPrice());
        item.setSubtotal(dto.getPrice().multiply(BigDecimal.valueOf(dto.getQuantity())));
        return item;
    }

    private BigDecimal calculateTotalAmount(List<OrderItem> items) {
        return items.stream()
            .map(OrderItem::getSubtotal)
            .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    private BigDecimal calculateTax(BigDecimal subtotal) {
        BigDecimal taxRate = new BigDecimal("0.08");
        return subtotal.multiply(taxRate).setScale(2, BigDecimal.ROUND_HALF_UP);
    }

    private BigDecimal calculateShipping(OrderCreateDTO orderDTO) {
        return new BigDecimal("9.99");
    }

    private void validateStatusTransition(OrderStatus currentStatus, OrderStatus newStatus) {
        if (!orderService.isValidStatusTransition(currentStatus, newStatus)) {
            throw new InvalidStatusTransitionException(
                String.format("Cannot transition from %s to %s", currentStatus, newStatus));
        }
    }

    private OrderResponseDTO convertToResponseDTO(Order order) {
        return OrderResponseDTO.builder()
            .orderId(order.getOrderId())
            .customerId(order.getCustomerId())
            .status(order.getStatus())
            .totalAmount(order.getTotalAmount())
            .subtotal(order.getSubtotal())
            .tax(order.getTax())
            .shippingCost(order.getShippingCost())
            .items(order.getItems())
            .shippingAddress(order.getShippingAddress())
            .billingAddress(order.getBillingAddress())
            .paymentMethod(order.getPaymentMethod())
            .paymentStatus(order.getPaymentStatus())
            .trackingNumber(order.getTrackingNumber())
            .createdAt(order.getCreatedAt())
            .updatedAt(order.getUpdatedAt())
            .build();
    }

    @ExceptionHandler(OrderNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleOrderNotFound(OrderNotFoundException ex) {
        logger.error("Order not found: {}", ex.getMessage());
        ErrorResponse error = new ErrorResponse(HttpStatus.NOT_FOUND.value(), ex.getMessage(), LocalDateTime.now());
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
    }

    @ExceptionHandler(ValidationException.class)
    public ResponseEntity<ErrorResponse> handleValidationException(ValidationException ex) {
        logger.error("Validation error: {}", ex.getMessage());
        ErrorResponse error = new ErrorResponse(HttpStatus.BAD_REQUEST.value(), ex.getMessage(), LocalDateTime.now());
        return ResponseEntity.badRequest().body(error);
    }

    @ExceptionHandler(OrderProcessingException.class)
    public ResponseEntity<ErrorResponse> handleOrderProcessingException(OrderProcessingException ex) {
        logger.error("Order processing error: {}", ex.getMessage());
        ErrorResponse error = new ErrorResponse(HttpStatus.INTERNAL_SERVER_ERROR.value(), ex.getMessage(), LocalDateTime.now());
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(error);
    }
}
