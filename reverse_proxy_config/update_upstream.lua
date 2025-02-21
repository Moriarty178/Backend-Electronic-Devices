local redis = require "resty.redis"

-- Kết nối Redis
local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000) -- Timeout 1s

    local ok, err = red:connect("127.0.0.1", 6379)
    if not ok then
        ngx.log(ngx.ERR, "Redis connection error: ", err)
        return nil
    end

    return red
end

-- Hàm lấy danh sách backend từ Redis
local function get_backends()
    local red = connect_redis()
    if not red then return {} end

    local backends, err = red:smembers("backend_servers") or {}
    if not backends then
        ngx.log(ngx.ERR, "Failed to fetch backend servers: ", err)
        return {}
    end

    return backends
end

-- Cập nhật shared memory với danh sách backend mới
local function update_upstream()
    local backends = get_backends()
    if #backends == 0 then
        ngx.log(ngx.ERR, "No backends found in Redis")
        return
    end

    local upstream_list = {}
    for _, backend in ipairs(backends) do
        table.insert(upstream_list, backend)
    end

    -- Lưu danh sách backend vào shared memory
    local dict = ngx.shared.backend_list
    dict:set("backends", table.concat(upstream_list, ","))
    ngx.log(ngx.ERR, "Updated upstream list: ", table.concat(upstream_list, ","))
end

-- -- Lắng nghe Redis Pub/Sub để cập nhật backend động
-- local function listen_for_updates()
--     while true do
--         local red = connect_redis()
--         if not red then
--             ngx.log(ngx.ERR, "Failed to connect to Redis, retrying in 5s...")
--             ngx.sleep(5) -- Đợi 5 giây trước khi thử lại
--         else
--             ngx.log(ngx.ERR, "Connected to Redis, subscribing to 'update_upstream'")
--             local res, err = red:subscribe("update_upstream")
--
--             if not res then
--                 ngx.log(ngx.ERR, "Failed to subscribe to Redis channel: ", err)
--                 ngx.sleep(5) -- Đợi 5 giây trước khi thử lại
--             else
--                 -- Lắng nghe sự kiện liên tục
--                 while true do
--                     local res, err = red:read_reply()
--                     if res then
--                         ngx.log(ngx.ERR, "Received event from Redis.")
--                         if res[3] == "refresh" then
--                             update_upstream() -- Gọi cập nhật backend khi nhận thông điệp "refresh"
--                         end
--                     elseif err then
--                         ngx.log(ngx.ERR, "Redis connection lost: ", err)
--                         break -- Thoát vòng lặp, kết nối lại Redis
--                     end
--                 end
--             end
--         end
--     end
-- end


-- ngx.thread.spawn(listen_for_updates) -- Khởi động luồng lắng nghe Redis trong init_worker
-- ngx.timer.at(0, listen_for_updates)

-- Đăng ký timer để chạy mỗi 5 giây
local function start_timer()
    local ok, err = ngx.timer.at(0, update_upstream)
    if ngx.worker.id() == 0 then
        local ok, err = ngx.timer.every(10, update_upstream)
        if not ok then
            ngx.log(ngx.ERR, "Failed to start timer: ", err)
        end
    end
end

-- update_upstream(): gọi trực tiếp sẽ LỖI do: init_worker_lua ko cho phép kết nối dến redis - việc gọi hàm update_upstream có phần connect redis -> Lỗi.
-- Nhưng gọi update_upstream gián tiếp qua timer thì ko sao vì: các API như ngx.every.timer được phép trong init_worker_lua, access_by_lua, content_by_lua, ....
start_timer()

-- Thêm phần event-driven để cập nhật update_upstream() khi có backend thêm/bớt
-- cụ thể: khi thêm/bớt thì bên backend_java ngoài mã để add/remove thì còn cần có thêm: publish sự kiện "update" đến topic "update_upstream" để lua script (subscriber) biết mà call update_upstream()
