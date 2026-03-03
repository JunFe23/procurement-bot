-- 공사 계약 ETL: summary UPSERT(Step2) → history UPSERT(Step1) → summary 정리(Step3)
-- TRUNCATE 사용 안 함. FK 때문에 summary 먼저 갱신 후 history 삽입.
-- 시설공사 필터: public_procurement_category_major = '시설공사' AND mid IN (...) AND name IN (...)

USE g2b;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_etl_construction_contracts //

CREATE PROCEDURE sp_etl_construction_contracts()
BEGIN
  DECLARE v_run_date DATE DEFAULT CURDATE();

  -- ========== Step2: raw → summary UPSERT (최종행 1건 per contract_no, 시설공사만)
  -- 최종행 선택: is_final_contract='Y' 우선 → change_seq DESC → contract_date DESC
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
    saved,
    is_active,
    last_seen_date,
    updated_at
  )
  SELECT
    r.contract_no,
    r.vendor_biz_reg_no,
    'CONST',
    r.initial_year_contract_no,
    CASE
      WHEN COALESCE(TRIM(r.long_term_continuation_seq), '') NOT IN ('', '0') OR r.is_initial_long_term_contract = 'Y' THEN 'Y'
      ELSE 'N'
    END,
    r.vendor_name,
    r.contract_title,
    r.demand_agency_name,
    r.demand_agency_region,
    r.public_procurement_category_name,
    r.bid_contract_method,
    r.bid_notice_no,
    r.first_contract_date_d,
    r.first_contract_amount,
    r.contract_date_d,
    r.contract_amount,
    r.contract_change_seq,
    COALESCE(s.saved, 'N'),
    'Y',
    v_run_date,
    NOW()
  FROM (
    SELECT
      contract_no,
      contract_change_seq,
      vendor_biz_reg_no,
      initial_year_contract_no,
      long_term_continuation_seq,
      is_initial_long_term_contract,
      vendor_name,
      contract_title,
      demand_agency_name,
      demand_agency_region,
      public_procurement_category_name,
      bid_contract_method,
      bid_notice_no,
      first_contract_amount,
      contract_amount,
      COALESCE(STR_TO_DATE(TRIM(first_contract_date), '%Y%m%d'), STR_TO_DATE(TRIM(first_contract_date), '%Y-%m-%d')) AS first_contract_date_d,
      COALESCE(STR_TO_DATE(TRIM(contract_date), '%Y%m%d'), STR_TO_DATE(TRIM(contract_date), '%Y-%m-%d')) AS contract_date_d,
      ROW_NUMBER() OVER (
        PARTITION BY contract_no
        ORDER BY
          (CASE WHEN is_final_contract = 'Y' THEN 1 ELSE 0 END) DESC,
          contract_change_seq DESC,
          COALESCE(STR_TO_DATE(TRIM(contract_date), '%Y%m%d'), STR_TO_DATE(TRIM(contract_date), '%Y-%m-%d'), '1000-01-01') DESC
      ) AS rn
    FROM construction_contract_raw
    WHERE (public_procurement_category_major = '시설공사')
      AND (public_procurement_category_mid IN ('개별법령', '시설물유지관리공사'))
      AND (TRIM(COALESCE(public_procurement_category_name, '')) IN ('전기공사', '정보통신공사', '기계설비공사', '시설물유지관리공사', '상하수도설비공사', '기타시설공사'))
  ) r
  LEFT JOIN construction_contract_summary s ON s.contract_no = r.contract_no
  WHERE r.rn = 1
  ON DUPLICATE KEY UPDATE
    vendor_biz_reg_no                  = VALUES(vendor_biz_reg_no),
    initial_year_contract_no            = VALUES(initial_year_contract_no),
    is_long_term_contract              = VALUES(is_long_term_contract),
    vendor_name                        = VALUES(vendor_name),
    contract_title                     = VALUES(contract_title),
    demand_agency_name                 = VALUES(demand_agency_name),
    demand_agency_region               = VALUES(demand_agency_region),
    public_procurement_category_name   = VALUES(public_procurement_category_name),
    bid_contract_method                = VALUES(bid_contract_method),
    bid_notice_no                      = VALUES(bid_notice_no),
    first_contract_date                = VALUES(first_contract_date),
    first_contract_amount              = VALUES(first_contract_amount),
    contract_date                      = VALUES(contract_date),
    contract_amount                    = VALUES(contract_amount),
    latest_change_seq                  = VALUES(latest_change_seq),
    is_active                          = 'Y',
    last_seen_date                     = v_run_date,
    updated_at                         = NOW();

  -- ========== Step1: raw → history UPSERT (시설공사만, FK 만족하므로 summary 이후 실행)
  INSERT INTO construction_contract_change_history (
    contract_no,
    change_seq,
    contract_date,
    contract_amount,
    contract_diff_amount,
    first_contract_amount,
    total_book_contract_amount,
    estimated_price,
    estimated_amount,
    bid_amount,
    is_first_contract,
    is_final_contract,
    is_first_long_term_contract,
    raw_contract_no,
    raw_change_seq,
    updated_at
  )
  SELECT
    r.contract_no,
    r.contract_change_seq,
    COALESCE(STR_TO_DATE(TRIM(r.contract_date), '%Y%m%d'), STR_TO_DATE(TRIM(r.contract_date), '%Y-%m-%d')),
    r.contract_amount,
    r.contract_amount_delta,
    r.first_contract_amount,
    r.total_supplementary_amount,
    r.estimated_price,
    r.estimated_amount,
    r.award_amount,
    CASE WHEN TRIM(COALESCE(r.is_first_contract, '')) = 'Y' THEN 'Y' ELSE 'N' END,
    CASE WHEN TRIM(COALESCE(r.is_final_contract, '')) = 'Y' THEN 'Y' ELSE 'N' END,
    CASE WHEN TRIM(COALESCE(r.is_initial_long_term_contract, '')) = 'Y' THEN 'Y' ELSE 'N' END,
    r.contract_no,
    r.contract_change_seq,
    NOW()
  FROM construction_contract_raw r
  WHERE (r.public_procurement_category_major = '시설공사')
    AND (r.public_procurement_category_mid IN ('개별법령', '시설물유지관리공사'))
    AND (TRIM(COALESCE(r.public_procurement_category_name, '')) IN ('전기공사', '정보통신공사', '기계설비공사', '시설물유지관리공사', '상하수도설비공사', '기타시설공사'))
  ON DUPLICATE KEY UPDATE
    contract_date                = VALUES(contract_date),
    contract_amount              = VALUES(contract_amount),
    contract_diff_amount         = VALUES(contract_diff_amount),
    first_contract_amount        = VALUES(first_contract_amount),
    total_book_contract_amount   = VALUES(total_book_contract_amount),
    estimated_price              = VALUES(estimated_price),
    estimated_amount             = VALUES(estimated_amount),
    bid_amount                   = VALUES(bid_amount),
    is_first_contract            = VALUES(is_first_contract),
    is_final_contract            = VALUES(is_final_contract),
    is_first_long_term_contract  = VALUES(is_first_long_term_contract),
    raw_contract_no              = VALUES(raw_contract_no),
    raw_change_seq               = VALUES(raw_change_seq),
    updated_at                   = NOW();

  -- ========== Step3: raw(시설공사)에 더 이상 없는 contract_no → summary is_active='N'
  UPDATE construction_contract_summary s
  SET s.is_active = 'N', s.updated_at = NOW()
  WHERE s.is_active = 'Y'
    AND NOT EXISTS (
      SELECT 1
      FROM construction_contract_raw r
      WHERE r.contract_no = s.contract_no
        AND r.public_procurement_category_major = '시설공사'
        AND r.public_procurement_category_mid IN ('개별법령', '시설물유지관리공사')
        AND TRIM(COALESCE(r.public_procurement_category_name, '')) IN ('전기공사', '정보통신공사', '기계설비공사', '시설물유지관리공사', '상하수도설비공사', '기타시설공사')
    );

END //

DELIMITER ;
