-- local redis = require "resty.redis"
-- local cjson = require "cjson"
--
-- -- Cấu hình Rate Limit
-- local window_size = 60  -- 60 giây
-- local max_requests = 10  -- Cho phép tối đa 10 requests mỗi phút
--
-- -- Hàm Rate Limit
-- local function is_rate_limited(client_id)
--     local red = redis:new()
--     red:set_timeout(1000)  -- 1 giây timeout
--
--     local ok, err = red:connect("127.0.0.1", 6379)
--     if not ok then
--         ngx.log(ngx.ERR, "Redis connection error: ", err)
--         return false
--     end
--
--     local now = ngx.now()
--     local key = "rate_limit:" .. client_id
--
--     -- Lấy danh sách timestamp của requests
--     local timestamps = red:lrange(key, 0, -1)
--
--     -- Lọc bỏ các request cũ
--     for i, ts in ipairs(timestamps) do
--         if tonumber(ts) < now - window_size then
--             red:lpop(key)  -- Xóa request cũ
--         end
--     end
--
--     -- Kiểm tra số request còn lại
--     local count = red:llen(key)
--     if count >= max_requests then
--         return true  -- Quá giới hạn
--     end
--
--     -- Thêm timestamp request mới
--     red:rpush(key, now)
--     red:expire(key, window_size)  -- Đảm bảo key tồn tại tối đa window_size giây
--
--     return false
-- end
--
-- -- Lấy IP làm client_id (hoặc dùng JWT, API Key...)
-- local client_id = ngx.var.remote_addr
-- if is_rate_limited(client_id) then
--     ngx.status = 429
--     ngx.say(cjson.encode({ error = "Rate limit exceeded" }))
--     return ngx.exit(429)
-- end
--
-- ngx.say(cjson.encode({ message = "Request allowed!" }))


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

-- Lấy IP của client
local client_ip = ngx.var.remote_addr

if is_rate_limited(client_ip) then
    ngx.status = ngx.HTTP_TOO_MANY_REQUESTS
    ngx.say("429 Too Many Requests")
    ngx.exit(ngx.HTTP_TOO_MANY_REQUESTS)
end
