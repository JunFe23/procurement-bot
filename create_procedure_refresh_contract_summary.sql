-- 집계용 테이블 갱신 프로시저: TRUNCATE 후 query_long_term_contracts 로 INSERT
-- 이벤트 또는 수동 호출: CALL sp_refresh_procurement_contract_summary();

USE g2b;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_refresh_procurement_contract_summary //

CREATE PROCEDURE sp_refresh_procurement_contract_summary()
BEGIN
  TRUNCATE TABLE procurement_contract_summary;

  INSERT INTO procurement_contract_summary (
    bid_notice_no,
    vendor_biz_reg_no,
    contract_no,
    vendor_name,
    contract_title,
    demand_agency_name,
    demand_agency_region,
    detail_item_name,
    contract_method,
    first_contract_date,
    first_contract_amount,
    final_contract_date,
    final_contract_amount,
    contract_count,
    is_long_term
  )
  SELECT
    base.bid_notice_no_norm AS bid_notice_no,
    base.vendor_biz_reg_no,
    COALESCE(MAX(CASE WHEN base.bid_notice_no_norm = '' THEN base.contract_no END), '') AS contract_no,
    MAX(base.vendor_name),
    MAX(base.contract_title),
    MAX(base.demand_agency_name),
    MAX(base.demand_agency_region),
    MAX(base.detail_item_name),
    MAX(base.contract_method),
    DATE(STR_TO_DATE(CAST(MIN(base.reference_date) AS CHAR), '%Y%m%d')),
    SUM(CASE WHEN base.reference_date = base.first_contract_date THEN IFNULL(base.contract_amount, 0) ELSE 0 END),
    DATE(STR_TO_DATE(CAST(MAX(base.reference_date) AS CHAR), '%Y%m%d')),
    SUM(IFNULL(base.contract_amount, 0)),
    COUNT(DISTINCT base.contract_no),
    IF(MAX(CASE WHEN base.is_long_term_continuous = 'Y' THEN 'Y' END) = 'Y', 'Y', 'N')
  FROM (
    SELECT
      COALESCE(NULLIF(TRIM(bid_notice_no), ''), '') AS bid_notice_no_norm,
      vendor_biz_reg_no,
      contract_no,
      vendor_name,
      contract_title,
      demand_agency_name,
      demand_agency_region,
      detail_item_name,
      contract_method,
      reference_date,
      contract_amount,
      is_long_term_continuous,
      MIN(reference_date) OVER (
        PARTITION BY
          COALESCE(NULLIF(TRIM(bid_notice_no), ''), ''),
          vendor_biz_reg_no,
          CASE WHEN COALESCE(NULLIF(TRIM(bid_notice_no), ''), '') = '' THEN contract_no END
      ) AS first_contract_date
    FROM procurement_raw USE INDEX (idx_contract_type_bid_ref)
    WHERE (contract_type IS NULL OR contract_type <> '제3자단가계약')
      AND is_final_contract = 'Y'
  ) base
  GROUP BY
    base.bid_notice_no_norm,
    base.vendor_biz_reg_no,
    CASE WHEN base.bid_notice_no_norm = '' THEN base.contract_no END;

END //

DELIMITER ;
