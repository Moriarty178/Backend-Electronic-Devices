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

    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    @Value("${server.port}")
    private String port;

    private String backendAddress;

    @Override
    public void run(String... args) throws Exception {
        //String port = System.getProperty("server.port"); // ko lấy được do --PORT=8084 ko được coi là System Property

        // Lấy IP của máy chủ
        String ip = InetAddress.getLocalHost().getHostAddress(); // "127.0.0.1"

        // Định nghĩa địa chỉ máy chủ để đăng ký/hủy - (thêm/xóa) khỏi Redis
        backendAddress = ip + ":" + port;

        //  Đăng ký - lưu máy chủ vào Redis
        redisTemplate.opsForSet().add("backend_servers", backendAddress);
        System.out.println("Registered backend in Redis: " + backendAddress);

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
            System.out.println("Deregistered backend from Redis: " + backendAddress);
        }
    }
}
