-- 용역 계약 단건(펼쳐서 보기)용 조회 테이블
-- 탑인더스트리(1188117437), 탑정보통신(1188119624) 취급 public_procurement_category 기준 시장 전체 대상
-- PK: contract_delivery_integrated_no (계약 1건당 1행 — 공동수급 구분 없이 max change_seq 1행, 공사 동일 방식)
-- 기간 필터 기준 컬럼: contract_date (base_date → DATE 변환)
-- 갱신: sp_etl_service_contracts() UPSERT + is_active 소프트 삭제 (TRUNCATE 없음)

USE g2b;

CREATE TABLE IF NOT EXISTS service_contract_flat (

  -- ===== PK =====
  contract_delivery_integrated_no  VARCHAR(100) NOT NULL COMMENT '계약납품통합번호',

  -- ===== 계약 정보 =====
  vendor_biz_reg_no                VARCHAR(50)  DEFAULT NULL COMMENT '대표업체사업자등록번호 (공동수급 시 최대지분 업체)',
  vendor_name                      TEXT         DEFAULT NULL COMMENT '대표업체명',
  contract_title                   TEXT         DEFAULT NULL COMMENT '계약명',
  demand_agency_code               VARCHAR(50)  DEFAULT NULL COMMENT '수요기관코드 (숫자코드)',
  demand_agency                    TEXT         DEFAULT NULL COMMENT '수요기관명칭',
  demand_agency_region             VARCHAR(200) DEFAULT NULL COMMENT '수요기관지역',
  contract_method                  VARCHAR(50)  DEFAULT NULL COMMENT '계약방법',
  contract_type                    VARCHAR(50)  DEFAULT NULL COMMENT '계약유형',
  procurement_work_area            VARCHAR(50)  DEFAULT NULL COMMENT '조달업무영역(일반용역/기술용역)',
  bid_notice_no                    VARCHAR(50)  DEFAULT NULL COMMENT '입찰공고번호',
  initial_year_contract_no         VARCHAR(100) DEFAULT NULL COMMENT '초년도계약번호(장기 그룹 키)',
  is_long_term                     CHAR(1)      NOT NULL DEFAULT 'N' COMMENT '장기계속여부 Y/N',

  -- ===== 분류 정보 =====
  representative_item_category_code VARCHAR(50)  DEFAULT NULL COMMENT '대표물품분류코드 (숫자코드)',
  representative_item_category      VARCHAR(200) DEFAULT NULL COMMENT '대표물품분류명칭',
  detail_item_code                  VARCHAR(50)  DEFAULT NULL COMMENT '세부품명코드 (숫자코드)',
  detail_item_name                  VARCHAR(200) DEFAULT NULL COMMENT '세부품명명칭',
  public_procurement_category      VARCHAR(50)  DEFAULT NULL COMMENT '공공조달분류코드(필터 기준)',
  public_procurement_category_major VARCHAR(100) DEFAULT NULL COMMENT '대분류공공조달분류',
  public_procurement_category_mid  VARCHAR(100) DEFAULT NULL COMMENT '중분류공공조달분류',

  -- ===== 날짜 =====
  first_contract_date              DATE         DEFAULT NULL COMMENT '최초기준일자(initial_base_date→DATE)',
  contract_date                    DATE         DEFAULT NULL COMMENT '기준일자(base_date→DATE, 기간 필터)',
  start_date                       DATE         DEFAULT NULL COMMENT '착수일자',
  completion_date                  DATE         DEFAULT NULL COMMENT '완수일자',

  -- ===== 금액 =====
  first_contract_amount            BIGINT       DEFAULT NULL COMMENT '최초계약금액',
  contract_amount                  BIGINT       DEFAULT NULL COMMENT '계약금액',

  -- ===== ETL 관리 =====
  latest_change_seq                BIGINT       DEFAULT NULL COMMENT '반영된 계약납품통합변경차수',
  saved                            CHAR(1)      NOT NULL DEFAULT 'N' COMMENT '화면 저장 체크박스용',
  is_active                        CHAR(1)      NOT NULL DEFAULT 'Y' COMMENT '활성 여부(N=raw에서 사라짐)',
  last_seen_date                   DATE         DEFAULT NULL COMMENT 'ETL에서 마지막으로 확인한 날짜',
  etl_loaded_at                    DATETIME     DEFAULT NULL COMMENT 'ETL 적재/갱신 시각',

  PRIMARY KEY (contract_delivery_integrated_no),
  KEY idx_contract_date               (contract_date),
  KEY idx_first_contract_date         (first_contract_date),
  KEY idx_vendor                      (vendor_biz_reg_no),
  KEY idx_bid_notice_no               (bid_notice_no),
  KEY idx_initial_year_contract_no    (initial_year_contract_no),
  KEY idx_public_procurement_category (public_procurement_category),
  KEY idx_is_long_term                (is_long_term),
  KEY idx_saved                       (saved),
  KEY idx_is_active                   (is_active)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='용역 계약 단건(펼쳐서 보기). PK=계약납품통합번호(1건 1행). 공동수급 구분 없이 max change_seq 1행(공사 동일). 기간필터=contract_date';
