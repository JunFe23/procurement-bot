-- 용역 계약 합쳐서 보기용 조회 테이블 (장기 그룹 단위)
-- 탑인더스트리(1188117437), 탑정보통신(1188119624) 취급 public_procurement_category 기준 시장 전체 대상
-- PK: group_key (계약 그룹 1건당 1행 — 공동수급 구분 없이 계약 단위, 공사 동일 방식)
--   group_key = COALESCE(initial_year_contract_no, contract_delivery_integrated_no)
-- 기간 필터 기준 컬럼: initial_contract_date (그룹 내 최초 계약일)
-- 갱신: sp_etl_service_contracts() UPSERT + is_active 소프트 삭제 (TRUNCATE 없음)
-- 소스: service_contract_flat (is_active='Y') → raw 재스캔 불필요

USE g2b;

CREATE TABLE IF NOT EXISTS service_contract_grouped (

  -- ===== PK =====
  group_key                        VARCHAR(100) NOT NULL COMMENT 'COALESCE(initial_year_contract_no, contract_delivery_integrated_no)',

  -- ===== 업체·계약 정보 (그룹 내 최초 계약 기준) =====
  vendor_biz_reg_no                VARCHAR(50)  DEFAULT NULL COMMENT '업체사업자등록번호',
  vendor_name                      TEXT         DEFAULT NULL COMMENT '대표업체명',
  contract_title                   TEXT         DEFAULT NULL COMMENT '계약명',
  demand_agency_code               VARCHAR(50)  DEFAULT NULL COMMENT '수요기관코드 (숫자코드)',
  demand_agency                    TEXT         DEFAULT NULL COMMENT '수요기관명칭',
  demand_agency_region             VARCHAR(200) DEFAULT NULL COMMENT '수요기관지역',
  contract_method                  VARCHAR(50)  DEFAULT NULL COMMENT '계약방법',
  procurement_work_area            VARCHAR(50)  DEFAULT NULL COMMENT '조달업무영역',
  detail_item_code                 VARCHAR(50)  DEFAULT NULL COMMENT '세부품명코드 (숫자코드)',
  detail_item_name                 VARCHAR(200) DEFAULT NULL COMMENT '세부품명명칭 (최초 계약 기준)',

  -- ===== 집계 =====
  initial_contract_date            DATE         DEFAULT NULL COMMENT '그룹 최초 계약일(기간 필터)',
  initial_contract_amount          BIGINT       DEFAULT NULL COMMENT '그룹 최초 계약 시점 금액',
  final_contract_date              DATE         DEFAULT NULL COMMENT '그룹 최종 계약일',
  final_contract_amount_sum        BIGINT       DEFAULT NULL COMMENT '그룹 전체 계약금액 합계',
  contract_count                   INT          DEFAULT NULL COMMENT '그룹 내 계약 건수(장기=2+, 단건=1)',
  is_long_term                     CHAR(1)      NOT NULL DEFAULT 'N' COMMENT '장기여부 Y/N',

  -- ===== ETL 관리 =====
  saved                            CHAR(1)      NOT NULL DEFAULT 'N' COMMENT '화면 저장 체크박스용',
  is_active                        CHAR(1)      NOT NULL DEFAULT 'Y' COMMENT '활성 여부(N=flat에서 사라짐)',
  last_seen_date                   DATE         DEFAULT NULL COMMENT '마지막 반영일',
  etl_loaded_at                    DATETIME     DEFAULT NULL COMMENT 'ETL 적재/갱신 시각',

  PRIMARY KEY (group_key),
  KEY idx_initial_contract_date (initial_contract_date),
  KEY idx_final_contract_date   (final_contract_date),
  KEY idx_vendor                (vendor_biz_reg_no),
  KEY idx_is_long_term          (is_long_term),
  KEY idx_saved                 (saved),
  KEY idx_is_active             (is_active)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='용역 계약 합쳐서 보기(장기 그룹 단위). PK=group_key(1건 1행). 공동수급 구분 없이 계약 단위(공사 동일). 기간필터=initial_contract_date';
