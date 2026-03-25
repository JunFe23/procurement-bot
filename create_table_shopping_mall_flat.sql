-- 쇼핑몰(3자단가) 납품요구 조회용 테이블
-- 소스: procurement_specific_item_raw WHERE contract_type = '제3자단가계약'
-- PK: (delivery_contract_no, delivery_contract_change_seq, delivery_item_seq) — raw와 동일 UNIQUE KEY
-- 기간 필터 기준: ref_date (reference_date → DATE 변환, 납품요구결재일)
-- 갱신: sp_etl_shopping_mall() UPSERT + is_active 소프트 삭제 (TRUNCATE 없음)

USE g2b;

CREATE TABLE IF NOT EXISTS shopping_mall_flat (

  -- ===== PK =====
  delivery_contract_no          VARCHAR(64)   NOT NULL COMMENT '납품요구번호',
  delivery_contract_change_seq  INT           NOT NULL COMMENT '납품요구변경차수',
  delivery_item_seq             INT           NOT NULL COMMENT '납품요구물품순번',

  -- ===== 업체·계약 정보 =====
  vendor_biz_reg_no             VARCHAR(32)   DEFAULT NULL COMMENT '업체사업자등록번호',
  vendor_name                   VARCHAR(255)  DEFAULT NULL COMMENT '업체명',
  contract_title                VARCHAR(500)  DEFAULT NULL COMMENT '계약명(요청명)',
  demand_agency_name            VARCHAR(255)  DEFAULT NULL COMMENT '수요기관명',
  demand_agency_region          VARCHAR(255)  DEFAULT NULL COMMENT '수요기관지역',
  contract_method               VARCHAR(128)  DEFAULT NULL COMMENT '계약방법',
  contract_no                   VARCHAR(64)   DEFAULT NULL COMMENT '계약번호(쇼핑몰 단가계약번호)',
  delivery_place_name           VARCHAR(500)  DEFAULT NULL COMMENT '납품장소명',
  supervising_type              VARCHAR(64)   DEFAULT NULL COMMENT '소관구분',
  company_type_at_contract      VARCHAR(64)   DEFAULT NULL COMMENT '기업형태구분',

  -- ===== 물품 정보 =====
  item_category_no              VARCHAR(64)   DEFAULT NULL COMMENT '물품분류번호',
  item_category_name            VARCHAR(255)  DEFAULT NULL COMMENT '물품분류명',
  detail_item_no                VARCHAR(64)   DEFAULT NULL COMMENT '세부품명번호',
  detail_item_name              VARCHAR(255)  DEFAULT NULL COMMENT '세부품명',
  item_identifier_no            VARCHAR(64)   DEFAULT NULL COMMENT '물품식별번호',
  item_identifier_name          VARCHAR(255)  DEFAULT NULL COMMENT '물품식별명',
  unit                          VARCHAR(255)  DEFAULT NULL COMMENT '납품단위명',
  unit_price                    BIGINT        DEFAULT NULL COMMENT '계약납품단가',
  quantity                      BIGINT        DEFAULT NULL COMMENT '납품수량',
  supply_amount                 BIGINT        DEFAULT NULL COMMENT '공급금액(단가×수량)',
  quantity_delta                BIGINT        DEFAULT NULL COMMENT '납품증감수량',
  supply_amount_delta           BIGINT        DEFAULT NULL COMMENT '공급증감금액',

  -- ===== 품질·인증 =====
  is_mas                        VARCHAR(8)    DEFAULT NULL COMMENT 'MAS여부',
  is_excellent_product          VARCHAR(8)    DEFAULT NULL COMMENT '우수제품여부',
  is_direct_purchase_target     VARCHAR(8)    DEFAULT NULL COMMENT '직접구매대상여부',

  -- ===== 날짜 =====
  -- ref_date      : reference_date(VARCHAR YYYYMMDD) → DATE  (기간 필터 기준, 납품요구결재일)
  -- first_ref_date: first_reference_date(VARCHAR YYYYMMDD) → DATE
  ref_date                      DATE          DEFAULT NULL COMMENT '납품요구결재일(기간필터 기준)',
  first_ref_date                DATE          DEFAULT NULL COMMENT '최초기준일자',
  delivery_deadline_date        DATE          DEFAULT NULL COMMENT '납품기한일자',

  -- ===== ETL 관리 =====
  is_active                     CHAR(1)       NOT NULL DEFAULT 'Y' COMMENT '활성여부(N=raw에서 사라짐)',
  last_seen_date                DATE          DEFAULT NULL COMMENT 'ETL 마지막 확인일',
  etl_loaded_at                 DATETIME      DEFAULT NULL COMMENT 'ETL 적재/갱신 시각',

  PRIMARY KEY (delivery_contract_no, delivery_contract_change_seq, delivery_item_seq),
  KEY idx_ref_date               (ref_date),
  KEY idx_first_ref_date         (first_ref_date),
  KEY idx_vendor                 (vendor_biz_reg_no),
  KEY idx_demand_agency          (demand_agency_name(100)),
  KEY idx_demand_agency_region   (demand_agency_region(50)),
  KEY idx_item_category_no       (item_category_no),
  KEY idx_detail_item_no         (detail_item_no),
  KEY idx_item_identifier_no     (item_identifier_no),
  KEY idx_is_active              (is_active)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='쇼핑몰(3자단가) 납품요구 조회용. procurement_specific_item_raw WHERE contract_type=제3자단가계약. PK=(delivery_contract_no,change_seq,item_seq). 기간필터=ref_date';
