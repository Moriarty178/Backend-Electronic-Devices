package selling_electronic_devices.back_end.Repository;

import io.lettuce.core.dynamic.annotation.Param;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import selling_electronic_devices.back_end.Entity.Category;
import selling_electronic_devices.back_end.Entity.Product;

import java.util.List;

public interface ProductRepository extends JpaRepository<Product, String> {
    // get products theo danh mục (category)
//    List<Product> findByCategory(Category category);

    @Query("SELECT p FROM Product p JOIN p.category c WHERE p.name LIKE %:query% OR p.description LIKE %:query% OR c.name LIKE %:query% " +
            "ORDER BY CASE " +
            "WHEN p.name = :query THEN 0 " +
            "WHEN p.name LIKE :query% THEN 1 " +
            "WHEN p.name LIKE %:query THEN 2 " +
            "ELSE 3 END, " +
            "c.name DESC")
    Page<Product> findBySearchQuery(@Param("query") String query, Pageable pageable);

    Page<Product> findByCategory(Category category, Pageable pageable);

    @Query("SELECT COUNT(p) FROM Product p WHERE EXTRACT(YEAR FROM p.createdAt) = :year " +
            "AND (:month IS NULL OR EXTRACT(MONTH FROM p.createdAt) = :month) ") // logic vị từ: NẾU Month != NULL THÌ kiểm tra EXTRACT(MONTH FROM p.createdAt) = month (*), ta có: A => B <==> -A ^ B ===> (*) <=> Month == NULL OR EXTRACT() = month
        // hoặc suy luận thuần túy:
        // bỏ qua -> Luôn đúng (1) hoặc Ko tồn tại
        // Khi month NULL pass =>  toàn khối điều kiện = True ko xét phần còn lai
        // Khi month # NULL thì mới xét các mệnh đề sau
        // ===> Dùng or với mệnh đề ưu tiên "month == NULL"
    Long countTotalProducts(@Param("year") int year, @Param("month") Integer month);

    boolean existsByName(String name);

//    @Query("SELECT p FROM Product ORDER BY numberVote DESC")
//    List<Product> listBestSellers(int yearStats);
}
