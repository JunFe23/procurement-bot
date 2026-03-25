-- 쇼핑몰 집계 테이블 갱신 프로시저
-- 소스: shopping_mall_flat (is_active='Y')
-- 전략: TRUNCATE 후 INSERT (매일 또는 sp_etl_shopping_mall() 호출 후 연이어 실행)
-- 호출: CALL sp_refresh_shopping_mall_summary();

USE g2b;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_refresh_shopping_mall_summary //

CREATE PROCEDURE sp_refresh_shopping_mall_summary()
BEGIN

  TRUNCATE TABLE shopping_mall_summary;

  INSERT INTO shopping_mall_summary (
    vendor_biz_reg_no,
    item_category_no,
    detail_item_no,
    ref_year_month,
    vendor_name,
    demand_agency_name,
    demand_agency_region,
    item_category_name,
    detail_item_name,
    contract_method,
    first_ref_date,
    final_ref_date,
    total_supply_amount,
    total_quantity,
    delivery_count,
    is_mas,
    is_excellent_product,
    etl_loaded_at
  )
  SELECT
    COALESCE(vendor_biz_reg_no, '')          AS vendor_biz_reg_no,
    COALESCE(item_category_no, '')           AS item_category_no,
    COALESCE(detail_item_no, '')             AS detail_item_no,
    DATE_FORMAT(ref_date, '%Y-%m')           AS ref_year_month,
    MAX(vendor_name)                         AS vendor_name,
    -- 수요기관: 가장 많이 등장한 값 선택 (서브쿼리 없이 MAX로 근사)
    MAX(demand_agency_name)                  AS demand_agency_name,
    MAX(demand_agency_region)                AS demand_agency_region,
    MAX(item_category_name)                  AS item_category_name,
    MAX(detail_item_name)                    AS detail_item_name,
    MAX(contract_method)                     AS contract_method,
    MIN(ref_date)                            AS first_ref_date,
    MAX(ref_date)                            AS final_ref_date,
    SUM(IFNULL(supply_amount, 0))            AS total_supply_amount,
    SUM(IFNULL(quantity, 0))                 AS total_quantity,
    COUNT(*)                                 AS delivery_count,
    MAX(is_mas)                              AS is_mas,
    MAX(is_excellent_product)                AS is_excellent_product,
    NOW()                                    AS etl_loaded_at
  FROM shopping_mall_flat
  WHERE is_active = 'Y'
    AND ref_date IS NOT NULL
  GROUP BY
    COALESCE(vendor_biz_reg_no, ''),
    COALESCE(item_category_no, ''),
    COALESCE(detail_item_no, ''),
    DATE_FORMAT(ref_date, '%Y-%m');

END //

DELIMITER ;
