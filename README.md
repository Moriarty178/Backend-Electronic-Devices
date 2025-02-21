# Selling Computer Equipment - Backend

## 📌 Overview
This project is a robust and scalable backend system for an e-commerce platform specializing in retailing computer products. It provides comprehensive features for customers, staff, and administrators, ensuring high availability, efficient request handling, and seamless scalability through advanced database replication and load balancing mechanisms.

## 🔧 Features

### 1. **Customer Features**
- User registration, login, and password recovery
- Product search and cart management
- Order placement and payment processing
- Order tracking and status updates

### 2. **Staff Features**
- Product management: add, edit, delete, and update
- Category and discount code management
- Real-time customer support via chat

### 3. **Administrator Features**
- Comprehensive management of products, categories, and discount codes
- Staff and customer account management
- Monitoring key business metrics and statistics

## 🛠️ Tech Stack
- **Backend**: Java Spring
- **Database**: PostgreSQL (Primary/Replica) with Streaming Replication
- **Connection Pooling**: Pgpool-II (config Failover, Follow Primary)
- **Load Balancer & Reverse Proxy**: Nginx
- **Rate Limiting**: Redis + Lua Script
- **Containerization**: Docker
- **Real-time Communication**: WebSocket for customer support messaging.

## 🔼 System Enhancements & Optimizations

### 1. **Nginx as Load Balancer & Reverse Proxy (OpenResty)**
- **Load Balancing:** Distributes traffic across multiple backend instances, supporting auto-scaling based on system load.
- **Rate Limiting:** Implements IP-based request rate limiting using the **Sliding Window Logs** algorithm with Redis & Lua Script.
> Reference: [Nginx Notes](reverse_proxy_config/README.md)

### 2. **Database Optimization**
- **Database Replication:** Implements a **Primary-Replica** architecture with **Streaming Replication** to ensure high availability.
- **Connection Pooling:** Utilizes **Pgpool-II** to optimize PostgreSQL connection management, with additional configurations for failover and automatic primary node detection.
> Reference: [Database Notes](pg_primary_replica/README.md)

### 3. **Concurrency Control**
- Implements **Optimistic Locking** to handle data conflicts in a multi-threaded environment efficiently.
> Reference: [How does the entity version property work when using JPA and Hibernate](
https://vladmihalcea.com/jpa-entity-version-property-hibernate/)

## 🏗️ System Architecture

![image](https://i.imgur.com/yE77xwL.png)

---

# Authors
- [@Moriarty178](https://github.com/Moriarty178)