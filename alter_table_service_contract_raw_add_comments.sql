-- service_contract_raw 컬럼 한글 COMMENT 추가
-- 데이터 변경 없이 COMMENT만 추가 (MODIFY COLUMN은 타입/기본값 동일 유지 필수)
USE g2b;

ALTER TABLE service_contract_raw
  -- ===== PK =====
  MODIFY COLUMN contract_delivery_integrated_no        VARCHAR(100)  NOT NULL                COMMENT '계약납품통합번호',
  MODIFY COLUMN contract_delivery_integrated_change_seq BIGINT        NOT NULL                COMMENT '계약납품통합변경차수',
  MODIFY COLUMN vendor_biz_reg_no                      VARCHAR(50)   NOT NULL                COMMENT '계약업체사업자등록번호',
  MODIFY COLUMN business_type                          VARCHAR(200)  NOT NULL DEFAULT ''      COMMENT '업종(면허) — 공동수급 시 동일 업체가 복수 업종으로 참여 가능하므로 PK 구성 요소',

  -- ===== 계약 식별 =====
  MODIFY COLUMN contract_request_no                    VARCHAR(100)  DEFAULT NULL             COMMENT '계약요청접수번호',
  MODIFY COLUMN long_term_continuation_seq             VARCHAR(20)   DEFAULT NULL             COMMENT '장기계속차수',
  MODIFY COLUMN bid_notice_seq                         VARCHAR(20)   DEFAULT NULL             COMMENT '입찰공고차수',
  MODIFY COLUMN bid_notice_no                          VARCHAR(50)   DEFAULT NULL             COMMENT '입찰공고번호',
  MODIFY COLUMN initial_year_contract_no               VARCHAR(100)  DEFAULT NULL             COMMENT '초년도계약번호 (장기계약 그룹 키)',

  -- ===== 분류 =====
  MODIFY COLUMN representative_item_category           VARCHAR(50)   DEFAULT NULL             COMMENT '대표물품분류',
  MODIFY COLUMN detail_item_name                       VARCHAR(200)  DEFAULT NULL             COMMENT '세부품명',
  MODIFY COLUMN public_procurement_category            VARCHAR(50)   DEFAULT NULL             COMMENT '공공조달분류코드 (ETL 필터 기준)',
  MODIFY COLUMN public_procurement_category_major      VARCHAR(100)  DEFAULT NULL             COMMENT '대분류 공공조달분류',
  MODIFY COLUMN public_procurement_category_mid        VARCHAR(100)  DEFAULT NULL             COMMENT '중분류 공공조달분류',

  -- ===== 계약 기본 정보 =====
  MODIFY COLUMN contract_title                         TEXT          DEFAULT NULL             COMMENT '계약명',
  MODIFY COLUMN contract_period_content                VARCHAR(200)  DEFAULT NULL             COMMENT '계약기간내용',
  MODIFY COLUMN public_procurement_type                VARCHAR(50)   DEFAULT NULL             COMMENT '공공조달구분',
  MODIFY COLUMN procurement_work_area                  VARCHAR(50)   DEFAULT NULL             COMMENT '조달업무영역 (일반용역/기술용역)',
  MODIFY COLUMN procurement_method_type                VARCHAR(50)   DEFAULT NULL             COMMENT '조달방식구분 (중앙조달 등)',
  MODIFY COLUMN contract_type                          VARCHAR(50)   DEFAULT NULL             COMMENT '계약유형 (총액계약 등)',
  MODIFY COLUMN contract_method                        VARCHAR(50)   DEFAULT NULL             COMMENT '계약방법 (제한경쟁 등)',
  MODIFY COLUMN contract_law_type                      VARCHAR(100)  DEFAULT NULL             COMMENT '계약법유형 (지방계약법 등)',
  MODIFY COLUMN contract_change_type                   VARCHAR(50)   DEFAULT NULL             COMMENT '계약변경구분 (내용변경 등)',
  MODIFY COLUMN contract_branch                        VARCHAR(100)  DEFAULT NULL             COMMENT '계약지청',

  -- ===== 공동수급 =====
  MODIFY COLUMN joint_supply_type                      VARCHAR(100)  DEFAULT NULL             COMMENT '공동수급구성방식 (분담이행/공동이행)',
  MODIFY COLUMN joint_supply_reason                    VARCHAR(200)  DEFAULT NULL             COMMENT '공동수급사유',
  MODIFY COLUMN assigned_business_type                 VARCHAR(200)  DEFAULT NULL             COMMENT '분담업종',

  -- ===== 장기계약 =====
  MODIFY COLUMN new_long_term_type                     VARCHAR(50)   DEFAULT NULL             COMMENT '신규장기구분 (신규(장기) 등)',

  -- ===== 낙찰 =====
  MODIFY COLUMN clause_no                              VARCHAR(100)  DEFAULT NULL             COMMENT '조항호',
  MODIFY COLUMN award_method                           VARCHAR(100)  DEFAULT NULL             COMMENT '낙찰방법',
  MODIFY COLUMN standard_contract_method               VARCHAR(100)  DEFAULT NULL             COMMENT '표준계약방법',
  MODIFY COLUMN site_region                            VARCHAR(100)  DEFAULT NULL             COMMENT '현장지역',

  -- ===== 여부 플래그 =====
  MODIFY COLUMN is_mas                                 VARCHAR(10)   DEFAULT NULL             COMMENT 'MAS여부',
  MODIFY COLUMN is_quality_product                     VARCHAR(10)   DEFAULT NULL             COMMENT '우수제품여부',
  MODIFY COLUMN is_final_contract_delivery_required    VARCHAR(10)   DEFAULT NULL             COMMENT '최종계약납품요구여부 (ETL flat 필터 기준)',
  MODIFY COLUMN is_initial_contract_delivery_required  VARCHAR(10)   DEFAULT NULL             COMMENT '최초계약납품요구여부',
  MODIFY COLUMN is_initial_long_term_contract          VARCHAR(10)   DEFAULT NULL             COMMENT '장기초년도계약여부',

  -- ===== 기준 기간 =====
  MODIFY COLUMN base_year                              VARCHAR(10)   DEFAULT NULL             COMMENT '기준연도',
  MODIFY COLUMN base_year_month                        VARCHAR(10)   DEFAULT NULL             COMMENT '기준년월 (YYYYMM)',
  MODIFY COLUMN base_half_year                         VARCHAR(10)   DEFAULT NULL             COMMENT '기준반기',
  MODIFY COLUMN base_quarter                           VARCHAR(10)   DEFAULT NULL             COMMENT '기준분기',
  MODIFY COLUMN base_date                              VARCHAR(20)   DEFAULT NULL             COMMENT '기준일자 (YYYYMMDD, flat.contract_date 변환 원본)',
  MODIFY COLUMN max_delivery_due_date                  VARCHAR(20)   DEFAULT NULL             COMMENT '최대납품기한일자 (YYYYMMDD)',
  MODIFY COLUMN initial_base_date                      VARCHAR(20)   DEFAULT NULL             COMMENT '최초기준일자 (YYYYMMDD, flat.first_contract_date 변환 원본)',
  MODIFY COLUMN completion_date                        VARCHAR(20)   DEFAULT NULL             COMMENT '완수일자 (YYYYMMDD)',
  MODIFY COLUMN start_date                             VARCHAR(20)   DEFAULT NULL             COMMENT '착수일자 (YYYYMMDD)',

  -- ===== 수요기관 =====
  MODIFY COLUMN demand_agency                          TEXT          DEFAULT NULL             COMMENT '수요기관명',
  MODIFY COLUMN demand_agency_region                   VARCHAR(200)  DEFAULT NULL             COMMENT '수요기관지역',
  MODIFY COLUMN demand_agency_biz_no                   VARCHAR(50)   DEFAULT NULL             COMMENT '수요기관사업자등록번호',
  MODIFY COLUMN department_type                        VARCHAR(50)   DEFAULT NULL             COMMENT '소관구분 (지방정부 등)',
  MODIFY COLUMN demand_agency_top                      VARCHAR(200)  DEFAULT NULL             COMMENT '수요기관최상위기관',

  -- ===== 계약업체 정보 =====
  MODIFY COLUMN vendor_name                            TEXT          DEFAULT NULL             COMMENT '계약업체명',
  MODIFY COLUMN company_type_at_contract               VARCHAR(50)   DEFAULT NULL             COMMENT '계약시점 기업형태구분 (중소기업 등)',
  MODIFY COLUMN is_social_enterprise_at_contract       VARCHAR(10)   DEFAULT NULL             COMMENT '계약시점 사회적기업인증여부',
  MODIFY COLUMN vendor_name_at_contract                VARCHAR(200)  DEFAULT NULL             COMMENT '계약시점 업체명',
  MODIFY COLUMN vendor_rep_at_contract                 VARCHAR(100)  DEFAULT NULL             COMMENT '계약시점 업체대표자명',
  MODIFY COLUMN vendor_region_at_contract              VARCHAR(200)  DEFAULT NULL             COMMENT '계약시점 업체지역',
  MODIFY COLUMN is_women_enterprise_at_contract        VARCHAR(10)   DEFAULT NULL             COMMENT '계약시점 여성기업인증여부',
  MODIFY COLUMN is_disabled_enterprise_at_contract     VARCHAR(10)   DEFAULT NULL             COMMENT '계약시점 장애인기업인증여부',

  -- ===== 금액 =====
  MODIFY COLUMN total_supplementary_amount             BIGINT        DEFAULT NULL             COMMENT '총부기계약금액',
  MODIFY COLUMN first_contract_amount                  BIGINT        DEFAULT NULL             COMMENT '최초계약금액',
  MODIFY COLUMN contract_share_pct                     VARCHAR(20)   DEFAULT NULL             COMMENT '계약지분율 (공동수급 지분 %)',
  MODIFY COLUMN total_supplementary_share_amount       BIGINT        DEFAULT NULL             COMMENT '총부기계약지분금액',
  MODIFY COLUMN contract_share_amount                  BIGINT        DEFAULT NULL             COMMENT '계약지분금액',
  MODIFY COLUMN contract_share_amount_delta            BIGINT        DEFAULT NULL             COMMENT '계약지분증감금액',
  MODIFY COLUMN contract_delivery_qty                  BIGINT        DEFAULT NULL             COMMENT '계약납품수량',
  MODIFY COLUMN contract_delivery_qty_delta            BIGINT        DEFAULT NULL             COMMENT '계약납품증감수량',
  MODIFY COLUMN contract_amount                        BIGINT        DEFAULT NULL             COMMENT '계약금액',
  MODIFY COLUMN contract_amount_delta                  BIGINT        DEFAULT NULL             COMMENT '계약증감금액';
