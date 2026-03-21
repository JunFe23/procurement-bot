-- 용역 계약 ETL: raw → flat UPSERT → grouped UPSERT → flat/grouped is_active 정리
-- 대상: 탑인더스트리(1188117437), 탑정보통신(1188119624) 취급 public_procurement_category와
--       동일한 공공조달분류코드를 가진 시장 전체 계약 (두 회사 계약 포함)
-- 최종행 기준: is_final_contract_delivery_required='Y' + 최고 change_seq (공사 동일 방식)
-- TRUNCATE 사용 안 함. 펼쳐서 보기=flat, 합쳐서 보기=service_contract_grouped.
-- 계약 1건 1행: 공동수급 여부 구분 없이 contract_delivery_integrated_no당 최고 change_seq 1건.
--
-- Step0: 두 회사의 public_procurement_category 목록 임시 저장 (JOIN으로 성능 확보)
-- Step1: raw JOIN tmp_target_categories → flat UPSERT
--        contract_delivery_integrated_no당 최종 1건 (max change_seq)
-- Step2: flat(is_active='Y') → grouped UPSERT
--        group_key = COALESCE(initial_year_contract_no, contract_delivery_integrated_no)
-- Step3: raw에 더 이상 없는 contract_no → flat is_active='N'
-- Step4: flat(is_active='Y')에 더 이상 없는 group_key → grouped is_active='N'
--
-- 권장 인덱스 (없으면 실행 전 생성):
--   CREATE INDEX idx_vendor_final_svc ON service_contract_raw
--     (vendor_biz_reg_no, is_final_contract_delivery_required, public_procurement_category);
--   CREATE INDEX idx_final_type_svc ON service_contract_raw
--     (is_final_contract_delivery_required, contract_type, public_procurement_category);

USE g2b;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_etl_service_contracts //

CREATE PROCEDURE sp_etl_service_contracts()
BEGIN
  DECLARE v_run_date DATE DEFAULT CURDATE();

  -- ========== Step0: 타깃 public_procurement_category 목록 임시 저장
  -- 탑인더스트리/탑정보통신이 is_final_contract_delivery_required='Y'로 체결한 분류 코드 기준
  DROP TEMPORARY TABLE IF EXISTS tmp_target_categories;
  CREATE TEMPORARY TABLE tmp_target_categories (
    public_procurement_category VARCHAR(50) NOT NULL,
    PRIMARY KEY (public_procurement_category)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

  INSERT IGNORE INTO tmp_target_categories (public_procurement_category)
  SELECT DISTINCT public_procurement_category
  FROM service_contract_raw
  WHERE vendor_biz_reg_no IN ('1188117437', '1188119624')
    AND is_final_contract_delivery_required = 'Y'
    AND public_procurement_category IS NOT NULL
    AND TRIM(public_procurement_category) <> '';

  -- ========== Step1: raw → flat UPSERT
  -- contract_delivery_integrated_no당 최종 1건 (max change_seq, 공사와 동일 방식)
  -- 공동수급 구분 없이 단순히 최고 change_seq 행을 사용
  -- LEFT JOIN flat → saved 값 보존 (신규는 'N', 기존은 유지)
  INSERT INTO service_contract_flat (
    contract_delivery_integrated_no,
    vendor_biz_reg_no,
    vendor_name,
    contract_title,
    demand_agency_code,
    demand_agency,
    demand_agency_region,
    contract_method,
    contract_type,
    procurement_work_area,
    bid_notice_no,
    initial_year_contract_no,
    is_long_term,
    representative_item_category_code,
    representative_item_category,
    detail_item_code,
    detail_item_name,
    public_procurement_category,
    public_procurement_category_major,
    public_procurement_category_mid,
    first_contract_date,
    contract_date,
    start_date,
    completion_date,
    first_contract_amount,
    contract_amount,
    latest_change_seq,
    saved,
    is_active,
    last_seen_date,
    etl_loaded_at
  )
  SELECT
    r.contract_delivery_integrated_no,
    r.vendor_biz_reg_no,
    r.vendor_name,
    r.contract_title,
    r.demand_agency_code,
    r.demand_agency,
    r.demand_agency_region,
    r.contract_method,
    r.contract_type,
    r.procurement_work_area,
    r.bid_notice_no,
    r.initial_year_contract_no,
    CASE
      WHEN COALESCE(TRIM(r.long_term_continuation_seq), '') NOT IN ('', '0') THEN 'Y'
      WHEN r.is_initial_long_term_contract = 'Y' THEN 'Y'
      ELSE 'N'
    END,
    r.representative_item_category_code,
    r.representative_item_category,
    r.detail_item_code,
    r.detail_item_name,
    r.public_procurement_category,
    r.public_procurement_category_major,
    r.public_procurement_category_mid,
    STR_TO_DATE(SUBSTRING_INDEX(SUBSTRING_INDEX(TRIM(r.initial_base_date), ' ', 1), '.', 1), '%Y%m%d'),
    STR_TO_DATE(SUBSTRING_INDEX(SUBSTRING_INDEX(TRIM(r.base_date),         ' ', 1), '.', 1), '%Y%m%d'),
    STR_TO_DATE(SUBSTRING_INDEX(SUBSTRING_INDEX(TRIM(r.start_date),        ' ', 1), '.', 1), '%Y%m%d'),
    STR_TO_DATE(SUBSTRING_INDEX(SUBSTRING_INDEX(TRIM(r.completion_date),   ' ', 1), '.', 1), '%Y%m%d'),
    r.first_contract_amount,
    r.contract_amount,
    r.contract_delivery_integrated_change_seq,
    COALESCE(f.saved, 'N'),
    'Y',
    v_run_date,
    NOW()
  FROM (
    -- contract_delivery_integrated_no당 최고 change_seq 1건 선택
    SELECT
      sr.contract_delivery_integrated_no,
      sr.contract_delivery_integrated_change_seq,
      sr.vendor_biz_reg_no,
      sr.vendor_name,
      sr.contract_title,
      sr.demand_agency_code,
      sr.demand_agency,
      sr.demand_agency_region,
      sr.contract_method,
      sr.contract_type,
      sr.procurement_work_area,
      sr.bid_notice_no,
      sr.initial_year_contract_no,
      sr.long_term_continuation_seq,
      sr.is_initial_long_term_contract,
      sr.representative_item_category_code,
      sr.representative_item_category,
      sr.detail_item_code,
      sr.detail_item_name,
      sr.public_procurement_category,
      sr.public_procurement_category_major,
      sr.public_procurement_category_mid,
      sr.initial_base_date,
      sr.base_date,
      sr.start_date,
      sr.completion_date,
      sr.first_contract_amount,
      sr.contract_amount,
      ROW_NUMBER() OVER (
        PARTITION BY sr.contract_delivery_integrated_no
        ORDER BY sr.contract_delivery_integrated_change_seq DESC
      ) AS rn
    FROM service_contract_raw sr
    JOIN tmp_target_categories tc
      ON tc.public_procurement_category = sr.public_procurement_category
    WHERE sr.is_final_contract_delivery_required = 'Y'
  ) r
  LEFT JOIN service_contract_flat f
    ON f.contract_delivery_integrated_no = r.contract_delivery_integrated_no
  WHERE r.rn = 1
  ON DUPLICATE KEY UPDATE
    vendor_biz_reg_no                = VALUES(vendor_biz_reg_no),
    vendor_name                      = VALUES(vendor_name),
    contract_title                   = VALUES(contract_title),
    demand_agency_code               = VALUES(demand_agency_code),
    demand_agency                    = VALUES(demand_agency),
    demand_agency_region             = VALUES(demand_agency_region),
    contract_method                  = VALUES(contract_method),
    contract_type                    = VALUES(contract_type),
    procurement_work_area            = VALUES(procurement_work_area),
    bid_notice_no                    = VALUES(bid_notice_no),
    initial_year_contract_no         = VALUES(initial_year_contract_no),
    is_long_term                     = VALUES(is_long_term),
    representative_item_category_code = VALUES(representative_item_category_code),
    representative_item_category     = VALUES(representative_item_category),
    detail_item_code                 = VALUES(detail_item_code),
    detail_item_name                 = VALUES(detail_item_name),
    public_procurement_category      = VALUES(public_procurement_category),
    public_procurement_category_major = VALUES(public_procurement_category_major),
    public_procurement_category_mid  = VALUES(public_procurement_category_mid),
    first_contract_date              = VALUES(first_contract_date),
    contract_date                    = VALUES(contract_date),
    start_date                       = VALUES(start_date),
    completion_date                  = VALUES(completion_date),
    first_contract_amount            = VALUES(first_contract_amount),
    contract_amount                  = VALUES(contract_amount),
    latest_change_seq                = VALUES(latest_change_seq),
    is_active                        = 'Y',
    last_seen_date                   = v_run_date,
    etl_loaded_at                    = NOW();

  -- ========== Step2: flat → grouped UPSERT
  -- group_key = COALESCE(initial_year_contract_no, contract_delivery_integrated_no)
  -- 공사와 동일한 초년도계약번호 기반 장기계약 그룹 패턴
  -- 문자열 컬럼: 그룹 내 최초 계약(contract_date ASC) 기준 1행
  INSERT INTO service_contract_grouped (
    group_key,
    vendor_biz_reg_no,
    vendor_name,
    contract_title,
    demand_agency_code,
    demand_agency,
    demand_agency_region,
    contract_method,
    procurement_work_area,
    detail_item_code,
    detail_item_name,
    initial_contract_date,
    initial_contract_amount,
    final_contract_date,
    final_contract_amount_sum,
    contract_count,
    is_long_term,
    saved,
    is_active,
    last_seen_date,
    etl_loaded_at
  )
  SELECT
    g.group_key,
    MAX(CASE WHEN g.rn = 1 THEN g.vendor_biz_reg_no    END),
    MAX(CASE WHEN g.rn = 1 THEN g.vendor_name          END),
    MAX(CASE WHEN g.rn = 1 THEN g.contract_title       END),
    MAX(CASE WHEN g.rn = 1 THEN g.demand_agency_code   END),
    MAX(CASE WHEN g.rn = 1 THEN g.demand_agency        END),
    MAX(CASE WHEN g.rn = 1 THEN g.demand_agency_region END),
    MAX(CASE WHEN g.rn = 1 THEN g.contract_method      END),
    MAX(CASE WHEN g.rn = 1 THEN g.procurement_work_area END),
    MAX(CASE WHEN g.rn = 1 THEN g.detail_item_code     END),
    MAX(CASE WHEN g.rn = 1 THEN g.detail_item_name     END),
    MIN(g.contract_date),
    SUM(CASE WHEN g.contract_date = g.grp_min_date THEN IFNULL(g.contract_amount, 0) ELSE 0 END),
    MAX(g.contract_date),
    SUM(IFNULL(g.contract_amount, 0)),
    COUNT(DISTINCT g.contract_delivery_integrated_no),
    CASE WHEN COUNT(DISTINCT g.contract_delivery_integrated_no) > 1 OR MAX(g.is_long_term) = 'Y' THEN 'Y' ELSE 'N' END,
    COALESCE(MAX(lg.saved), 'N'),
    'Y',
    v_run_date,
    NOW()
  FROM (
    SELECT
      f.contract_delivery_integrated_no,
      f.vendor_biz_reg_no,
      f.vendor_name,
      f.contract_title,
      f.demand_agency_code,
      f.demand_agency,
      f.demand_agency_region,
      f.contract_method,
      f.procurement_work_area,
      f.detail_item_code,
      f.detail_item_name,
      f.contract_date,
      f.contract_amount,
      f.is_long_term,
      COALESCE(NULLIF(TRIM(f.initial_year_contract_no), ''), f.contract_delivery_integrated_no) AS group_key,
      MIN(f.contract_date) OVER (
        PARTITION BY COALESCE(NULLIF(TRIM(f.initial_year_contract_no), ''), f.contract_delivery_integrated_no)
      ) AS grp_min_date,
      ROW_NUMBER() OVER (
        PARTITION BY COALESCE(NULLIF(TRIM(f.initial_year_contract_no), ''), f.contract_delivery_integrated_no)
        ORDER BY f.contract_date ASC, f.contract_delivery_integrated_no ASC
      ) AS rn
    FROM service_contract_flat f
    WHERE f.is_active = 'Y'
  ) g
  LEFT JOIN service_contract_grouped lg
    ON lg.group_key = g.group_key
  GROUP BY g.group_key
  ON DUPLICATE KEY UPDATE
    vendor_biz_reg_no         = VALUES(vendor_biz_reg_no),
    vendor_name               = VALUES(vendor_name),
    contract_title            = VALUES(contract_title),
    demand_agency_code        = VALUES(demand_agency_code),
    demand_agency             = VALUES(demand_agency),
    demand_agency_region      = VALUES(demand_agency_region),
    contract_method           = VALUES(contract_method),
    procurement_work_area     = VALUES(procurement_work_area),
    detail_item_code          = VALUES(detail_item_code),
    detail_item_name          = VALUES(detail_item_name),
    initial_contract_date     = VALUES(initial_contract_date),
    initial_contract_amount   = VALUES(initial_contract_amount),
    final_contract_date       = VALUES(final_contract_date),
    final_contract_amount_sum = VALUES(final_contract_amount_sum),
    contract_count            = VALUES(contract_count),
    is_long_term              = VALUES(is_long_term),
    is_active                 = 'Y',
    last_seen_date            = v_run_date,
    etl_loaded_at             = NOW();

  -- ========== Step3: raw(필터 조건)에 더 이상 없는 contract_no → flat is_active='N'
  UPDATE service_contract_flat f
  SET f.is_active = 'N', f.etl_loaded_at = NOW()
  WHERE f.is_active = 'Y'
    AND NOT EXISTS (
      SELECT 1
      FROM service_contract_raw sr
      JOIN tmp_target_categories tc
        ON tc.public_procurement_category = sr.public_procurement_category
      WHERE sr.contract_delivery_integrated_no = f.contract_delivery_integrated_no
        AND sr.is_final_contract_delivery_required = 'Y'
    );

  -- ========== Step4: flat(is_active='Y')에 더 이상 없는 group_key → grouped is_active='N'
  UPDATE service_contract_grouped lg
  SET lg.is_active = 'N', lg.etl_loaded_at = NOW()
  WHERE lg.is_active = 'Y'
    AND NOT EXISTS (
      SELECT 1
      FROM service_contract_flat f
      WHERE f.is_active = 'Y'
        AND COALESCE(NULLIF(TRIM(f.initial_year_contract_no), ''), f.contract_delivery_integrated_no) = lg.group_key
    );

  DROP TEMPORARY TABLE IF EXISTS tmp_target_categories;

END //

DELIMITER ;
