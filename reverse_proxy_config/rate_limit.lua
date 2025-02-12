local redis = require "resty.redis"

-- Kết nối Redis
local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000) -- 1 giây timeout

    local ok, err = red:connect("127.0.0.1", 6379)
    if not ok then
        ngx.log(ngx.ERR, "Redis connection error: ", err)
        return nil
    end

    return red
end

-- Thực hiện thuật toán Sliding Window Logs
local function is_rate_limited(client_ip)
    local red = connect_redis()
    if not red then
        return false -- Không kết nối được Redis thì không chặn request
    end

    local key = "rate_limit:" .. client_ip
    local now = ngx.now() * 1000 -- Timestamp tính bằng milliseconds
    local window_size = 60000  -- 60 giây
    local max_requests = 10     -- Giới hạn request

    -- Xóa các timestamp cũ hơn 60 giây
    red:zremrangebyscore(key, 0, now - window_size)

    -- Đếm số lượng request trong cửa sổ hiện tại
    local current_count = red:zcard(key)
    if current_count and current_count >= max_requests then
        return true -- Quá giới hạn request
    end

    -- Thêm timestamp mới vào danh sách
    red:zadd(key, now, now)
    red:expire(key, 60) -- Đảm bảo key tồn tại tối đa 60 giây

    return false
end

-- Cập nhật traffic vào Redis
local function update_traffic()
    local red = connect_redis()
    if not red then return end

    local key = "traffic:count"
    red:incr(key)

    --Chỉ set TTL nếu key chưa set TTL
    local current_ttl = red:ttl(key)
    if current_ttl == -1 or current_ttl == -2 then -- chưa set: -1; hết hạn: -2
        red:expire(key, 60)
    end
end

-- Kiểm tra tải và Auto Scaling backend
local function auto_scale_backend()
    local red = connect_redis()
    if not red then return end

    local traffic_count = tonumber(red:get("traffic:count")) or 0
    local min_threshold = 2  -- ngưỡng tối thiểu một server nhận được. Nếu request < 20 -> giảm instance
    local max_threshold = 3 -- ngưỡng tải tối đa mà một server chịu được. Nếu request > 100 -> thêm instance

    local backends = red:smembers("backend_servers")
    local backend_count = #backends

    if traffic_count > max_threshold * backend_count and backend_count < 9 then
        -- Thêm instance mới nếu chưa đạt giới hạn tối đa
        -- Việc scale up/down ko thể chỉ dừng ở việc thêm/xóa server trong Redis, nó phải thực sự khởi chạy hoặc dừng một "tiến trình" thực sự.
        local new_port = 8081 + backend_count
        local start_command = string.format(
            'start /b java -jar D:/electronic_devices/back-end/target/back-end-0.0.1-SNAPSHOT.jar --PORT=%d',
            new_port
        )

        os.execute(start_command)
        ngx.log(ngx.INFO, "Starting new backend on port " .. new_port)
    end

    if backend_count > 3 and traffic_count / backend_count < min_threshold then -- ????vấn đề vừa chuyến sang cửa sổ mới: count reset = 0 -> khi incr sẽ remove instace -> ko hợp lý, vì tải vẫn có thể đang lớn
--         local remove_instance = backends[#backends]
--         local remove_port = string.match(remove_instance, ":(%d+)")

        -- Loại bỏ bớt server khi tải thấp - Tìm backend có cổng lớn nhất
        local remove_instance = nil
        local max_port = 0

        for _, instance in ipairs(backends) do
            local port = tonumber(instance:match(":(%d+)$") or instance:match(":(%d+)"))
--             local cleaned_instance = instance:gsub("%s+", "") -- Xóa khoảng trắng và xuống dòng
--             local port = tonumber(cleaned_instance:match(":(%d+)$"))
            if port and port > max_port then
                max_port = port
                remove_instance = instance
            end
        end

        local remove_port = max_port

        if remove_port then
            ngx.log(ngx.WARN, "Stopping backend on MAX_PORT " .. remove_port)

            -- Xóa khỏi Redis TRƯỚC KHI kill tiến trình
            red:srem("backend_servers", remove_instance)
            ngx.log(ngx.INFO, "Removed backend from Redis: " .. remove_instance)

            -- Lấy PID của tiến trình backend dựa trên port (Windows)
            local get_pid_cmd = string.format('netstat -ano | findstr :%d', remove_port)
            local pid_file = io.popen(get_pid_cmd) -- đang là file, kiểu như csv, xlsx, ...
            local pid_output = pid_file:read("*a") -- Đọc toàn bộ output - file
            pid_file:close()

            ngx.log(ngx.INFO, "Netstat output: " .. pid_output) -- Debug xem có dữ liệu không

            local backend_pid = pid_output:match("(%d+)%s*$") -- Tìm số cuối cùng (PID)

            if backend_pid then
                ngx.log(ngx.INFO, "Found backend PID: " .. backend_pid)
                local stop_command = string.format('taskkill /F /PID %s', backend_pid)

                os.execute(stop_command)
                ngx.log(ngx.WARN, "Killed backend process with PID: " .. backend_pid)
            else
                ngx.log(ngx.ERR, "ERROR: Failed to retrieve PID for backend on port " .. remove_port)
                return  -- Không tiếp tục nếu không có PID
            end
        end
    end
end

-- Lấy IP của client
local client_ip = ngx.var.remote_addr

-- Kiểm tra Rate Limit
if is_rate_limited(client_ip) then
    ngx.status = ngx.HTTP_TOO_MANY_REQUESTS
    ngx.say("429 Too Many Requests")
    ngx.exit(ngx.HTTP_TOO_MANY_REQUESTS)
else
    -- CHỈ cập nhật traffic khi request không bị giới hạn
    update_traffic()
    auto_scale_backend()
end

-- ###Tổng quan
-- Với mỗi yêu cầu từ mỗi IP (client) ta sẽ:
-- - Khi có yêu cầu tử 1 IP đến Reverse Proxy (Nginx) thì:
--  + Xóa toàn bộ số req cũ hơn khoảng [t-60s, t] của IP (key) đó khỏi Redis
--  + Kiểm tra số lượng req còn lại của IP (key) đó (vẫn nằm trong khoảng trên).
--     ++ Nếu quá ngưỡng thì tiến hành giới hạn truy cập với IP
--     ++ Chưa quá thì thêm req đó vào key (IP) trong Redis, Nginx tiếp tục gửi yêu cầu đến instance backend

-- check PID process: netstat -ano | findstr :port (pid)
-- kill process =PID: taskkill /F /PID pid
-- tasklist | findstr nginx

-- Lưu ý:
--         +Khi thêm backend: - ứng dụng khởi tạo hoàn tất mới ghi vào Redis
--                         -> Tránh việc Nginx đọc tử Redis rồi điều phối tải cho nó trong khi nó chưa khởi tạo xong
--         +Khi xóa backend: - xóa khỏi Redis trước - nếu kill trước rồi đợi xong mới xóa
--                         -> sẽ dẫn đến th server bị xóa (kill) rồi nhưng trong Redis chưa kịp xóa -> Nginx (vốn được cấu hình động theo Redis) có thể điều phối tải đến server đã chết.
