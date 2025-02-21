# Nginx (OpenResty) Integration for Load Balancer, Rate Limit & Auto Scale Up/Down

## Table of Contents
- [A. Rate Limit](#a-rate-limit)
    - [Tổng quan](#tổng-quan)
    - [Lưu ý](#lưu-ý)
- [B. Auto Scale Up/Down](#b-auto-scale-updown)
    - [Tổng quan](#tổng-quan-1)
    - [Yêu cầu và Triển khai](#yêu-cầu-và-triển-khai)
    - [Cấu hình Dynamic Backends](#cấu-hình-dynamic-backends)
- [Test](#test)
- [Commands & Process Management](#commands--process-management)
- [Summary](#summary)

---

## A. Rate Limit

### Tổng quan
Với mỗi yêu cầu từ một IP (client), Nginx (Reverse Proxy) sẽ thực hiện các bước sau:
- **Bước 1:** Khi có yêu cầu từ một IP đến Reverse Proxy, tiến hành xóa toàn bộ số request cũ hơn khoảng `[t-60s, t]` của IP đó khỏi Redis.
- **Bước 2:** Kiểm tra số lượng request còn lại của IP đó (trong khoảng thời gian 60 giây).
    - Nếu số lượng request vượt ngưỡng cho phép, tiến hành giới hạn truy cập cho IP.
    - Nếu chưa vượt ngưỡng, thêm request mới vào key của IP trong Redis và Nginx sẽ chuyển tiếp yêu cầu đến instance backend.

### Kết quả

### Lưu ý
- **Khi thêm backend:**
    - Ứng dụng chỉ ghi vào Redis sau khi khởi tạo hoàn tất.
    - Điều này tránh trường hợp Nginx đọc từ Redis và điều phối tải đến backend chưa sẵn sàng.

- **Khi xóa backend:**
    - Cần xóa backend khỏi Redis trước khi kill process.
    - Nếu kill process trước rồi mới xóa, có thể dẫn đến việc Nginx điều phối tải đến server đã chết vì Redis chưa kịp cập nhật.

---

## B. Auto Scale Up/Down

### Tổng quan
Để thực hiện tự động scale theo tải, Nginx (OpenResty) cần quản lý được các yếu tố sau:

1. **Theo dõi tải (traffic):**
    - Sử dụng một key (ví dụ: `traffic:count`) để theo dõi số lượng request trong một đơn vị thời gian.
    - **Triển khai:** Thêm phần này ngay trong Lua script của phần Rate Limit (ví dụ: `rate_limit.lua`).
    - **Chú ý:** Chỉ tính các request không bị rate limit. Nếu tính tất cả, hệ thống có thể hiểu sai về "tải thực tế" và kích hoạt scale backend không cần thiết.

2. **Danh sách server (backends):**
    - Danh sách các backend đang chạy cần được lưu và cập nhật trong Redis hoặc theo dõi qua một Discovery Service như Consul, Zookeeper,...
    - **Triển khai:**
        - Khi một instance backend được khởi chạy, nó tự thêm mình vào Redis với key `backend_servers`.
        - Khi shutdown, nó tự xóa mình khỏi Redis.
    - **Lưu ý:** Điều này giúp tránh Nginx điều phối tải đến server chưa khởi tạo hoặc đã chết.
        - Khi thêm backend, chỉ ghi vào Redis sau khi ứng dụng khởi tạo hoàn tất.
        - Khi xóa backend, cần xóa khỏi Redis trước khi kill process.

### Cấu hình Dynamic Backends
- **Vấn đề:** Thay vì cấu hình tĩnh các backend (ví dụ: `server http://localhost:8081, 8082, 8083,...`), chúng ta cần cấu hình Nginx dựa trên danh sách `backend_servers` trong Redis.
- **Giải pháp:**
    - Sử dụng Lua script để tự động cập nhật cấu hình danh sách backend theo thời gian thực mà không cần reload Nginx, đảm bảo hệ thống luôn theo dõi đúng các server hiện tại.
    - Cách hoạt động:
        - Lua Script -> Lấy `list_servers` từ Redis ghi vào `Shared Memory` của Nginx
        - Với mỗi request, Nginx -> Lấy `list_servers` từ `Shared Memory` của nó sau đó thực hiện điều phối tải.
---


## Test

- **Test tự động gửi request:**
  ```powershell
  1..11 | ForEach-Object { Invoke-WebRequest -Uri "http://localhost:8080/customer" -UseBasicParsing }
  ```

#### Kết quả:

<table>
  <tr>
    <td align="left">
      <img src="https://i.imgur.com/8cCdh0s.png" alt="Hình 1" height= "200px" width="360px"/><br>
      <b>Hình 1:</b> Danh sách servers lúc đầu là 3
    </td>
    <td align="left">
      <img src="https://i.imgur.com/juMkJV0.png" alt="Hình 2" height= "200px" width="360px"/><br>
      <b>Hình 2:</b> Từ chối khi vượt ngưỡng MAX_THRESHOLD
    </td>
  </tr>
  <tr>
    <td align="left">
      <img src="https://i.imgur.com/x2hN2f6.png" alt="Hình 3" height= "200px" width="360px"/><br>
      <b>Hình 3:</b> Redis lưu trữ <code>rate_limit</code>, <code>traffic:count</code>, <code>backend_servers</code>
    </td>
    <td align="left">
      <img src="https://i.imgur.com/NKBOzle.png" alt="Hình 4" height= "200px" width="360px"/><br>
      <b>Hình 4:</b> Scale up với port = 8084 khi <code>traffic:count</code> > MAX_THRESHOLD
    </td>
  </tr>
</table>




- **Kiểm tra header của response (để biết server nào đã xử lý request):**
  ```powershell
  (Invoke-WebRequest -Uri "http://localhost:8080/customer").Headers
  ```
  #### Kết quả:
  <div align="left">
        <img src="https://i.imgur.com/SsAs3gg.png" alt="Hình 5" width="60%"/><br>
        <b>Hình 5:</b> Response kèm thông tin server đã xử lý.
  </div>

---

## Commands & Process Management

- **Kiểm tra PID process đang lắng nghe cổng:**
  ```cmd
  netstat -ano | findstr :<port>
  ```
- **Kill process bằng PID:**
  ```cmd
  taskkill /F /PID <PID>
  ```
- **Liệt kê các process của Nginx:**
  ```cmd
  tasklist | findstr nginx
  ```

---

## Summary

- **Rate Limit:**  
  Mỗi yêu cầu từ một IP được xử lý qua Redis để xóa các request cũ và kiểm tra ngưỡng giới hạn. Nếu vượt ngưỡng, IP sẽ bị giới hạn truy cập.

- **Auto Scale Up/Down:**
    - Theo dõi traffic qua key `traffic:count` (chỉ tính các request không bị rate limit).
    - Quản lý danh sách backend qua key `backend_servers` trong Redis (hoặc thông qua Discovery Service).
    - Cấu hình dynamic cho Nginx thông qua Lua script để tự động cập nhật danh sách backend mà không cần reload.
- Triển khai với Redis & Lua Script: [rate_limit.lua](https://github.com/Moriarty178/Backend-Electronic-Devices/blob/main/reverse_proxy_config/rate_limit.lua)

---

# Authors
- [@Moriarty178](https://github.com/Moriarty178)