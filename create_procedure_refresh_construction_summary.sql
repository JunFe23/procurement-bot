-- 공사 계약 요약 갱신 프로시저: TRUNCATE 후 construction_contract_raw 에서
-- 시설공사·최종계약만 필터하고, contract_no 당 contract_change_seq 최신 1건만 INSERT
-- 이벤트 또는 수동: CALL sp_refresh_construction_contract_summary();

USE g2b;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_refresh_construction_contract_summary //

CREATE PROCEDURE sp_refresh_construction_contract_summary()
BEGIN
  TRUNCATE TABLE construction_contract_summary;

  INSERT INTO construction_contract_summary (
    contract_no,
    vendor_biz_reg_no,
    domain_type,
    initial_year_contract_no,
    is_long_term_contract,
    vendor_name,
    contract_title,
    demand_agency_name,
    demand_agency_region,
    public_procurement_category_name,
    bid_contract_method,
    bid_notice_no,
    first_contract_date,
    first_contract_amount,
    contract_date,
    contract_amount,
    latest_change_seq,
    saved
  )
  SELECT
    r.contract_no,
    r.vendor_biz_reg_no,
    'CONST' AS domain_type,
    r.initial_year_contract_no,
    CASE
      WHEN (COALESCE(TRIM(r.long_term_continuation_seq), '') NOT IN ('', '0') OR r.is_initial_long_term_contract = 'Y') THEN 'Y'
      ELSE 'N'
    END AS is_long_term_contract,
    r.vendor_name,
    r.contract_title,
    r.demand_agency_name,
    r.demand_agency_region,
    r.public_procurement_category_name,
    r.bid_contract_method,
    r.bid_notice_no,
    r.first_contract_date,
    r.first_contract_amount,
    r.contract_date,
    r.contract_amount,
    r.contract_change_seq AS latest_change_seq,
    'N' AS saved
  FROM (
    SELECT
      contract_no,
      contract_change_seq,
      contract_date,
      contract_title,
      vendor_biz_reg_no,
      vendor_name,
      demand_agency_name,
      demand_agency_region,
      public_procurement_category_name,
      bid_contract_method,
      bid_notice_no,
      first_contract_date,
      first_contract_amount,
      contract_amount,
      initial_year_contract_no,
      long_term_continuation_seq,
      is_initial_long_term_contract,
      ROW_NUMBER() OVER (PARTITION BY contract_no ORDER BY contract_change_seq DESC) AS rn
    FROM construction_contract_raw
    WHERE (public_procurement_category_major = '시설공사')
      AND (public_procurement_category_mid IN ('개별법령', '시설물유지관리공사'))
      AND (TRIM(COALESCE(public_procurement_category_name, '')) IN ('전기공사', '정보통신공사', '기계설비공사', '시설물유지관리공사', '상하수도설비공사', '기타시설공사'))
      AND (is_final_contract = 'Y')
  ) r
  WHERE r.rn = 1;

END //

DELIMITER ;
