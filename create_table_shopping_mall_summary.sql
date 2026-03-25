-- 쇼핑몰(3자단가) 대시보드 집계 테이블
-- 소스: shopping_mall_flat (is_active='Y') 기반 집계
-- PK: (vendor_biz_reg_no, item_category_no, detail_item_no, ref_year_month)
--   → 업체 + 물품분류 + 세부품명 + 연월 단위로 집계 (대시보드 기간 필터에 대응)
-- procurement_contract_summary와 동일한 컬럼 구조로 맞춰 UNION 용이하게 설계
-- 갱신: sp_refresh_shopping_mall_summary() TRUNCATE 후 INSERT (매일 또는 ETL 후 호출)

USE g2b;

CREATE TABLE IF NOT EXISTS shopping_mall_summary (

  -- ===== PK =====
  vendor_biz_reg_no         VARCHAR(32)   NOT NULL COMMENT '업체사업자등록번호',
  item_category_no          VARCHAR(64)   NOT NULL DEFAULT '' COMMENT '물품분류번호',
  detail_item_no            VARCHAR(64)   NOT NULL DEFAULT '' COMMENT '세부품명번호',
  ref_year_month            CHAR(7)       NOT NULL COMMENT '기준연월(YYYY-MM, ref_date 기준)',

  -- ===== 업체·품목 정보 (집계 대표값) =====
  vendor_name               VARCHAR(255)  DEFAULT NULL COMMENT '업체명',
  demand_agency_name        VARCHAR(255)  DEFAULT NULL COMMENT '수요기관명(최다 빈도)',
  demand_agency_region      VARCHAR(255)  DEFAULT NULL COMMENT '수요기관지역(최다 빈도)',
  item_category_name        VARCHAR(255)  DEFAULT NULL COMMENT '물품분류명',
  detail_item_name          VARCHAR(255)  DEFAULT NULL COMMENT '세부품명',
  contract_method           VARCHAR(128)  DEFAULT NULL COMMENT '계약방법',

  -- ===== 집계 =====
  -- first_ref_date  : 그룹 내 MIN(ref_date) — procurement_contract_summary의 first_contract_date에 대응
  -- final_ref_date  : 그룹 내 MAX(ref_date) — procurement_contract_summary의 final_contract_date에 대응
  -- total_supply_amount: 그룹 내 SUM(supply_amount)
  -- delivery_count  : 납품요구 건수 (행 수)
  first_ref_date            DATE          DEFAULT NULL COMMENT '그룹 최초 납품요구결재일',
  final_ref_date            DATE          DEFAULT NULL COMMENT '그룹 최종 납품요구결재일',
  total_supply_amount       BIGINT        DEFAULT NULL COMMENT '공급금액 합계',
  total_quantity            BIGINT        DEFAULT NULL COMMENT '납품수량 합계',
  delivery_count            INT           DEFAULT NULL COMMENT '납품요구 건수',
  is_mas                    VARCHAR(8)    DEFAULT NULL COMMENT 'MAS여부',
  is_excellent_product      VARCHAR(8)    DEFAULT NULL COMMENT '우수제품여부',

  -- ===== ETL 관리 =====
  etl_loaded_at             DATETIME      DEFAULT NULL COMMENT 'ETL 적재/갱신 시각',

  PRIMARY KEY (vendor_biz_reg_no, item_category_no, detail_item_no, ref_year_month),
  KEY idx_first_ref_date        (first_ref_date),
  KEY idx_final_ref_date        (final_ref_date),
  KEY idx_vendor                (vendor_biz_reg_no),
  KEY idx_demand_agency         (demand_agency_name(100)),
  KEY idx_demand_agency_region  (demand_agency_region(50)),
  KEY idx_item_category_no      (item_category_no),
  KEY idx_detail_item_no        (detail_item_no)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='쇼핑몰(3자단가) 대시보드 집계. shopping_mall_flat 기반. PK=(vendor,item_category,detail_item,연월). 기간필터=first_ref_date/final_ref_date';
