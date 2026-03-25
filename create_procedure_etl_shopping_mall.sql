-- ETL 프로시저: procurement_specific_item_raw → shopping_mall_flat
-- 필터: contract_type = '제3자단가계약'
-- 전략: UPSERT(ON DUPLICATE KEY UPDATE) + is_active 소프트 삭제
--   Step1. 현재 raw에 없는 기존 flat 행 → is_active='N'
--   Step2. raw의 제3자단가계약 전체 → shopping_mall_flat UPSERT
-- 호출: CALL sp_etl_shopping_mall();

USE g2b;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_etl_shopping_mall //

CREATE PROCEDURE sp_etl_shopping_mall()
BEGIN

  -- -------------------------------------------------------
  -- Step 1. 소프트 삭제: raw에 더 이상 없는 행 비활성화
  -- -------------------------------------------------------
  UPDATE shopping_mall_flat f
  LEFT JOIN procurement_specific_item_raw r
    ON  r.delivery_contract_no         = f.delivery_contract_no
    AND r.delivery_contract_change_seq = f.delivery_contract_change_seq
    AND r.delivery_item_seq            = f.delivery_item_seq
    AND r.contract_type                = '제3자단가계약'
  SET
    f.is_active       = 'N',
    f.etl_loaded_at   = NOW()
  WHERE f.is_active = 'Y'
    AND r.delivery_contract_no IS NULL;

  -- -------------------------------------------------------
  -- Step 2. UPSERT: raw의 제3자단가계약 전체 → flat
  -- -------------------------------------------------------
  INSERT INTO shopping_mall_flat (
    delivery_contract_no,
    delivery_contract_change_seq,
    delivery_item_seq,
    vendor_biz_reg_no,
    vendor_name,
    contract_title,
    demand_agency_name,
    demand_agency_region,
    contract_method,
    contract_no,
    delivery_place_name,
    supervising_type,
    company_type_at_contract,
    item_category_no,
    item_category_name,
    detail_item_no,
    detail_item_name,
    item_identifier_no,
    item_identifier_name,
    unit,
    unit_price,
    quantity,
    supply_amount,
    quantity_delta,
    supply_amount_delta,
    is_mas,
    is_excellent_product,
    is_direct_purchase_target,
    ref_date,
    first_ref_date,
    delivery_deadline_date,
    is_active,
    last_seen_date,
    etl_loaded_at
  )
  SELECT
    r.delivery_contract_no,
    r.delivery_contract_change_seq,
    r.delivery_item_seq,
    r.vendor_biz_reg_no,
    r.vendor_name,
    r.contract_title,
    r.demand_agency_name,
    r.demand_agency_region,
    r.contract_method,
    r.contract_no,
    r.delivery_place_name,
    r.supervising_type,
    r.company_type_at_contract,
    r.item_category_no,
    r.item_category_name,
    r.detail_item_no,
    r.detail_item_name,
    r.item_identifier_no,
    r.item_identifier_name,
    r.delivery_unit_name,
    -- 단가/수량/금액: VARCHAR → BIGINT (콤마 제거 후 변환)
    CAST(REPLACE(IFNULL(r.delivery_unit_price,  '0'), ',', '') AS SIGNED),
    CAST(REPLACE(IFNULL(r.delivery_quantity,    '0'), ',', '') AS SIGNED),
    CAST(REPLACE(IFNULL(r.supply_amount,        '0'), ',', '') AS SIGNED),
    CAST(REPLACE(IFNULL(r.delivery_quantity_delta, '0'), ',', '') AS SIGNED),
    CAST(REPLACE(IFNULL(r.supply_amount_delta,  '0'), ',', '') AS SIGNED),
    r.is_mas,
    r.is_excellent_product,
    r.is_direct_purchase_target,
    -- 날짜: VARCHAR YYYYMMDD → DATE
    CASE WHEN r.reference_date REGEXP '^[0-9]{8}$'
         THEN STR_TO_DATE(r.reference_date, '%Y%m%d')
         ELSE NULL END,
    CASE WHEN r.first_reference_date REGEXP '^[0-9]{8}$'
         THEN STR_TO_DATE(r.first_reference_date, '%Y%m%d')
         ELSE NULL END,
    CASE WHEN r.delivery_deadline_date REGEXP '^[0-9]{8}$'
         THEN STR_TO_DATE(r.delivery_deadline_date, '%Y%m%d')
         ELSE NULL END,
    'Y',
    CURDATE(),
    NOW()
  FROM procurement_specific_item_raw r
  WHERE r.contract_type = '제3자단가계약'

  ON DUPLICATE KEY UPDATE
    vendor_biz_reg_no             = VALUES(vendor_biz_reg_no),
    vendor_name                   = VALUES(vendor_name),
    contract_title                = VALUES(contract_title),
    demand_agency_name            = VALUES(demand_agency_name),
    demand_agency_region          = VALUES(demand_agency_region),
    contract_method               = VALUES(contract_method),
    contract_no                   = VALUES(contract_no),
    delivery_place_name           = VALUES(delivery_place_name),
    supervising_type              = VALUES(supervising_type),
    company_type_at_contract      = VALUES(company_type_at_contract),
    item_category_no              = VALUES(item_category_no),
    item_category_name            = VALUES(item_category_name),
    detail_item_no                = VALUES(detail_item_no),
    detail_item_name              = VALUES(detail_item_name),
    item_identifier_no            = VALUES(item_identifier_no),
    item_identifier_name          = VALUES(item_identifier_name),
    unit                          = VALUES(unit),
    unit_price                    = VALUES(unit_price),
    quantity                      = VALUES(quantity),
    supply_amount                 = VALUES(supply_amount),
    quantity_delta                = VALUES(quantity_delta),
    supply_amount_delta           = VALUES(supply_amount_delta),
    is_mas                        = VALUES(is_mas),
    is_excellent_product          = VALUES(is_excellent_product),
    is_direct_purchase_target     = VALUES(is_direct_purchase_target),
    ref_date                      = VALUES(ref_date),
    first_ref_date                = VALUES(first_ref_date),
    delivery_deadline_date        = VALUES(delivery_deadline_date),
    is_active                     = 'Y',
    last_seen_date                = VALUES(last_seen_date),
    etl_loaded_at                 = VALUES(etl_loaded_at);

END //

DELIMITER ;
