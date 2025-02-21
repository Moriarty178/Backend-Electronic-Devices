![Logo](https://static.vecteezy.com/system/resources/previews/009/316/889/non_2x/database-icon-logo-illustration-database-storage-symbol-template-for-graphic-and-web-design-collection-free-vector.jpg)

# Cấu hình Database Replication (Primary/Replica) và Tích hợp Connection Pool (PgPool-II)

---
# 📌Overview

- [A. Cấu hình Primary/Replica](#a-cấu-hình-primaryreplica)

  - [Chuẩn bị môi trường](#1-chuẩn-bị-môi-trường)
  - [Tạo File `docker-compose.yml`](#2-tạo-file-docker-composeyml)
  - [Thiết lập Primary (Master)](#3-thiết-lập-primary-master)
  - [Thiết lập Replica (Slave)](#4-thiết-lập-replica-slave)
  - [Kiểm tra hoạt động của Replication](#5-kiểm-tra-hoạt-động-của-replication)
  - [Giám sát Replication](#6-giám-sát-replication)
  - [Quản lý hệ thống](#7-quản-lý-hệ-thống)
  - [Tối ưu hóa hệ thống](#8-tối-ưu-hóa-hệ-thống)
  - [Tổng kết](#9-tổng-kết)
- [B. Tích hợp Pgpool-II với Primary/Replica](#b-tích-hợp-pgpool-ii-với-primaryreplica)
  - [Giới thiệu](#1-giới-thiệu)
  - [Khởi tạo môi trường](#2-khởi-tạo-môi-trường)
  - [Cấu hình lại `docker-compose.yml`](#3-cấu-hình-docker-composeyml)
  - [Cấu Hình Các File Quan Trọng](#4-cấu-hình-các-file-quan-trọng)
  - [Viết Script](#5-viết-script)
  - [Chạy Và Kiểm Tra](#6-chạy-và-kiểm-tra)
  - [Xử lý lỗi](#7-xử-lý-lỗi)
  - [Tóm tắt](#tóm-tắt)
# A. Cấu hình Primary/Replica

---
## 1. Chuẩn Bị Môi Trường

### 1.1 Cài đặt Docker và Docker Compose
Trước tiên, bạn cần đảm bảo Docker và Docker Compose đã được cài đặt trên máy.

### 1.2 Tạo thư mục làm việc: 2 thư mục phụ để Mount dữ liệu từ container vào (có thể chỉnh sửa ở đây thay vì dùng nano)
```sh
mkdir postgres_replication && cd postgres_replication
mkdir master slave  # Tạo thư mục để lưu dữ liệu PostgreSQL
```

## 2. Tạo File `docker-compose.yml`
Tạo file `docker-compose.yml` với nội dung sau:
```yaml
version: '3.9'
services:
  master:
    image: postgres:15
    container_name: postgres_master
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: 1234
    ports:
      - "5432:5432"
    volumes:
      - ./master:/var/lib/postgresql/data

  slave:
    image: postgres:15
    container_name: postgres_slave
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: 1234
    depends_on:
      - master
    ports:
      - "5433:5432"
    volumes:
      - ./slave:/var/lib/postgresql/data
```

## 3. Thiết Lập Primary (Master)

### 3.1 Khởi động container
```sh
docker-compose up -d
```

### 3.2 Kết nối vào container Master
```sh
docker exec -it postgres_master bash
```

### 3.3 Cấu hình PostgreSQL (key)
**a**. Cấu hình cho các chỉ số về Replica trên Primary. Sửa file `postgresql.conf`:
```sh
nano /var/lib/postgresql/data/postgresql.conf
```
Thêm các dòng sau:
```
wal_level = replica
max_wal_senders = 10
wal_keep_size = 64MB
```

**b**. Cấu hình cho phép Replica kết nối đến Primary. Sửa file `pg_hba.conf`:
```sh
nano /var/lib/postgresql/data/pg_hba.conf
```
Thêm dòng sau:
```
host    replication    replicator2    172.18.0.3/24    trust
```
```shell
Trong đó: 172.18.0.3 là Slave_IP: có thể dùng docker inspect postgres_slave và tìm đến chỗ IPAddress
                                  hoặc dùng lệnh sau: docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' postgres_slave
          replicator2: tên user được tạo ROLE trên Master (postgres_master), tạo sau hay trước cũng được
```

Sau đó, Khởi động lại PostgreSQL trên Master
```sh
pg_ctl -D /var/lib/postgresql/data restart
Hoặc:
docker restart postgres_master
```

### 3.4 Tạo tài khoản replication (key)
```sql
CREATE ROLE replicator2 WITH REPLICATION PASSWORD '1234' LOGIN;
```

## 4. Thiết Lập Replica (Slave)

### 4.1 Kết nối vào container Slave
```sh
docker exec -it postgres_slave bash
```

### 4.2 Xóa dữ liệu cũ và sao chép dữ liệu từ Master
```sh
rm -rf /var/lib/postgresql/data/*
pg_basebackup -h postgres_master -D /var/lib/postgresql/data -U replicator2 -Fp -Xs -P -R
```
- Sau khi chạy lệnh **pg_basebackup** thì file `standby.signal` sẽ được tạo ra.
- Ý nghĩa: để cho container hiện tại biết nó là Slave (Logs hiển thị "Start streaming WAL..." thay vì ban đầu là "database system already to connect")

## 5. Kiểm Tra Hoạt Động Của Replication

### 5.1 Thêm dữ liệu vào Master
```sh
docker exec -it postgres_master psql -U admin -c "CREATE TABLE test_table (id SERIAL PRIMARY KEY, message TEXT);"
docker exec -it postgres_master psql -U admin -c "INSERT INTO test_table (message) VALUES ('Hello from Master');"
```

### 5.2 Kiểm tra dữ liệu trên Slave
```sh
docker exec -it postgres_slave psql -U admin -c "SELECT * FROM test_table;"
```
Nếu dữ liệu xuất hiện, replication đã hoạt động.

## 6. Giám Sát Replication

### 6.1 Kiểm tra trạng thái replication trên Master
```sh
docker exec -it postgres_master psql -U admin -c "SELECT * FROM pg_stat_replication;"
```

### 6.2 Theo dõi log
```sh
docker logs -f postgres_master
docker logs -f postgres_slave
```

## 7. Quản Lý Hệ Thống

### 7.1 Tắt hệ thống
```sh
docker stop postgres_slave
docker stop postgres_master
```

### 7.2 Khởi động lại hệ thống
```sh
docker start postgres_master
docker start postgres_slave
```

## 8. Tối Ưu Hóa Hệ Thống
- **Tăng kích thước WAL**: Điều chỉnh `wal_keep_size` trong `postgresql.conf` nếu cần lưu trữ nhiều WAL hơn.
- **Giảm checkpoint quá thường xuyên**: Điều chỉnh `checkpoint_timeout` và `max_wal_size`.
- **Giám sát lâu dài**: Dùng `pgAdmin`, `Prometheus` để theo dõi.

## 9. Tổng Kết
- **Master**:
    - Cấu hình replication trong `postgresql.conf` và `pg_hba.conf`.
    - Tạo user replication.
- **Slave**:
    - Xóa dữ liệu cũ.
    - Sao chép dữ liệu từ Master bằng `pg_basebackup`.
- **Kiểm tra và giám sát** để đảm bảo replication hoạt động ổn định.





# B. Tích hợp Pgpool-II với Primary/Replica

---
## 1️⃣ Giới Thiệu

Pgpool-II là một middleware giúp quản lý kết nối, cân bằng tải và thực hiện failover cho hệ thống PostgreSQL Primary/Replica.

---

## 2️⃣ Khởi Tạo Môi Trường

### 🔹 Tạo thư mục để mount dữ liệu:
```sh
mkdir -p pgpool/conf pgpool/scripts
```

### 🔹 Tạo 2 script trong `pgpool/scripts/`:
- **`init.sh`**: Tránh cơ chế ghi đè cấu hình mặc định của image `bitnami/pgpool`
- **`failover.sh`**: Xử lý quá trình **Failover**

### 🔹 Đổi port của PostgreSQL Slave:
- Mở file `postgresql.conf` trên **Slave**, đổi `port=5433` để Pgpool có thể kết nối.

---

## 3️⃣ Cấu Hình `docker-compose.yml`

Thêm **service `pgpool`** vào `docker-compose.yml`:
```yaml
pgpool:
  image: bitnami/pgpool:4
  container_name: pgpool
  environment:
    - PGPOOL_BACKEND_NODES=0:postgres_master:5432,1:postgres_slave:5433
    - PGPOOL_SR_CHECK_USER=admin
    - PGPOOL_SR_CHECK_PASSWORD=1234
    - PGPOOL_POSTGRES_USERNAME=admin
    - PGPOOL_POSTGRES_PASSWORD=1234
    - PGPOOL_ADMIN_USERNAME=pgpool_admin
    - PGPOOL_ADMIN_PASSWORD=pgpool_password
    - PGPOOL_FAILOVER_ON_BACKEND_ERROR=yes
    - PGPOOL_FAILOVER_COMMAND=/opt/bitnami/scripts/pgpool/failover.sh %d %P %H %R
  volumes:
    - ./pgpool/conf:/opt/bitnami/pgpool/conf               ### (1)
    - ./pgpool/scripts/init.sh:/opt/bitnami/scripts/init.sh ### (2)
    - ./pgpool/scripts/failover.sh:/opt/bitnami/scripts/pgpool/failover.sh ### (3)
  entrypoint: [ "/opt/bitnami/scripts/init.sh" ] ### (4) chạy scripts để đảm bảo luôn sao chéo config vào /opt/bitnami/pgpool/conf --> Tránh việc image bitnamit/pgpool kiểm tra các tệp cấu hình trong /opt/bitnami/pgpool/conf (trống hoặc thiếu) nó sẽ tạo các têệp câu hình và ghi đè lên container -> host cũng bị ghi đè do đang ánh xạ host - container.
  ports:
    - "5434:5432"
  depends_on:
    - master
    - slave # tên service trong network
```
---

## 4️⃣ Cấu Hình Các File Quan Trọng

### 🔹 `pgpool.conf`
- Cấu hình authentication, load balancing, failover, v.v...
- Điều chỉnh mật khẩu, tắt **auto_failback**:
```yaml
failover_command = '/opt/bitnami/scripts/pgpool/failover.sh %d %P %H %R'
load_balance_mode = on
auto_failback = off
```

### 🔹 `pool_hba.conf`
Thêm cấu hình cho quyền truy cập:
```conf
host    all             all             0.0.0.0/0       trust
host    replication     replicator3     0.0.0.0/0       trust
```

---

## 5️⃣ Viết Script

### 🔹 `failover.sh`
```sh
#!/bin/bash
FAILED_NODE_ID=$1
NEW_PRIMARY_NODE=$2

echo "Failover triggered. Node $FAILED_NODE_ID failed. Promoting $NEW_PRIMARY_NODE to primary."

export PGPASSWORD="1234"
if [ "$FAILED_NODE_ID" == "0" ]; then
    psql -h postgres_slave -p 5433 -U admin -c "SELECT pg_promote();"
fi
```

### 🔹 `init.sh`
```sh
#!/bin/bash

# Xóa tệp PID cũ trước khi Pgpool-II khởi động
if [ -f "/opt/bitnami/pgpool/tmp/pgpool.pid" ]; then
  echo "Xóa tệp PID cũ..."
  rm -f /opt/bitnami/pgpool/tmp/pgpool.pid
fi

cp /opt/bitnami/scripts/pgpool/conf/pgpool.conf /opt/bitnami/pgpool/conf/pgpool.conf
cp /opt/bitnami/scripts/pgpool/conf/pool_hba.conf /opt/bitnami/pgpool/conf/pool_hba.conf
cp /opt/bitnami/scripts/pgpool/conf/pool_passwd /opt/bitnami/pgpool/conf/pool_passwd

exec /opt/bitnami/scripts/pgpool/run.sh
```

---

## 6️⃣ Chạy Và Kiểm Tra

### 🔹 Chạy Docker Compose
```sh
docker compose up -d
```

### 🔹 Kiểm Tra Trạng Thái Pgpool
```sh
psql -U admin -h localhost -p 5434 -c "SHOW pool_nodes;"
```

### 🔹 Chuyển Slave Thành Primary
```sh
psql -h postgres_slave -p 5433 -U admin -c "SELECT pg_promote();"
```

---

## 7️⃣ Lỗi Gặp Phải Và Cách Xử Lý

### 🔹 Lỗi `connection to server on socket ... failed: No such file or directory`
✅ Giải pháp:
```sh
psql -h localhost -p 5434 -U admin -c "SHOW pool_nodes;"
```

### 🔹 Lỗi `pgpool: pid file found. is another pgpool(1) running?`
✅ Giải pháp:
- Thêm lệnh xóa PID vào `init.sh` trước khi Pgpool-II khởi động.

---

## Tóm Tắt

- **Bước 1:** Tạo thư mục `pgpool/scripts/`, viết 2 script `init.sh` và `failover.sh`.
- **Bước 2:** Thêm container **`pgpool`** vào `docker-compose.yml`.
- **Bước 3:** Cấu hình `pgpool.conf` và `pool_hba.conf`.
- **Bước 4:** Chạy Docker và kiểm tra kết nối.

---

# Authors
- [@Moriarty178](https://github.com/Moriarty178)