package selling_electronic_devices.back_end.Config;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

import javax.annotation.PreDestroy;
import java.net.InetAddress;

@Component
public class BackendRegistration implements CommandLineRunner {

    private static final String BACKEND_SET_KEY = "backend_servers";
    private static final String REDIS_CHANNEL = "update_upstream";

    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    @Value("${server.port}")
    private String port;

    private String backendAddress;

    @Override
    public void run(String... args) throws Exception {
        // Lấy IP của máy chủ
        String ip = InetAddress.getLocalHost().getHostAddress(); // "127.0.0.1"

        backendAddress = ip + ":" + port;

        //  Đăng ký - lưu máy chủ vào Redis
        redisTemplate.opsForSet().add("backend_servers", backendAddress);
        //redisTemplate.convertAndSend(REDIS_CHANNEL, "refresh"); // publish t bóa đến Lua Script (Subscriber) để nó update servers -> Shared Memory
        System.out.println("=========|_|========= Registered backend in Redis: " + backendAddress);

        // 💡 Đảm bảo xóa backend khi ứng dụng bị dừng
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            deregisterBackend();
        }));

//        Runtime.getRuntime().addShutdownHook(new Thread(this::deregisterBackend));
//        // 🔥 Giữ ứng dụng chạy vô thời hạn để tránh shutdown quá sớm
//        new CountDownLatch(1).await();
    }

    // Shutdown hook: xóa máy chủ khỏi danh sách backend_servers trong Redis
    @PreDestroy
    public void deregisterBackend() {
        if (backendAddress != null) {
            // xóa máy chủ
            redisTemplate.opsForSet().remove("backend_servers", backendAddress);
            //redisTemplate.convertAndSend(REDIS_CHANNEL, "refresh"); // thống báo để lua script update Shared Memory
            System.out.println("=========|_|========= Deregistered backend from Redis: " + backendAddress);
        }
    }
}
