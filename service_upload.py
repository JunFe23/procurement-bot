"""
용역 계약 업체 내역 CSV → service_contract_raw 적재
(물품/공사와 동일 방식: 파일 단위 트랜잭션, 로그, 완료 시 completed_service 이동)

PK: (계약납품통합번호, 계약납품통합변경차수, 계약업체사업자등록번호, 업종)
- 분담이행 공동수급에서 동일 업체가 여러 업종(면허)으로 참여하는 경우
  업종별로 별도 행이 생성되므로 업종까지 포함해야 유일성이 보장됨.

Usage:
  python service_upload.py --downloads-dir ./downloads_service --completed-dir ./completed_service

Options:
  --downloads-dir      소스 폴더 (기본: ./downloads_service)
  --completed-dir     처리 완료 이동 폴더 (기본: ./completed_service)
  --dry-run            검증/정규화만, DB insert 생략
  --dedupe-in-file    파일 내 중복 행 제거
  --stop-on-fail / --no-stop-on-fail
"""

import argparse
import glob
import os
import sys
import time
import uuid
from typing import Dict, List, Optional

def _stderr(msg: str) -> None:
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


_stderr("service_upload: 스크립트 로딩 중...")
_stderr("  pandas 로딩 중...")
import numpy as np
import pandas as pd
_stderr("  pandas 로드 완료.")
_stderr("  sqlalchemy 로딩 중...")
from sqlalchemy import create_engine, text
_stderr("  sqlalchemy 로드 완료.")


def _log(msg: str) -> None:
    print(msg, flush=True)

# =========================================================
# [설정]
# =========================================================
DB_CONNECTION_STR = "mysql+pymysql://root:@localhost:3306/g2b?connect_timeout=10"
TABLE_NAME = "service_contract_raw"
LOG_TABLE_NAME = "service_ingestion_log"

ENCODING = "utf-16"
SEPARATOR = "\t"
SKIP_ROWS = 71   # 용역 리포트: 헤더가 72번째 줄
CHUNK_SIZE = 10000

# 용역 계약 업체 내역 CSV 한글 컬럼명 → 영문
# CSV 구조 특이사항:
#   대표물품분류(코드) | (빈헤더=명칭) | 세부품명(코드) | (빈헤더=명칭) | ... | 수요기관(코드) | (빈헤더=명칭)
#   빈 헤더 컬럼은 pandas가 'Unnamed: N' 으로 명명 → _fix_unnamed_columns() 에서 처리
KOR_TO_ENG = {
    "계약납품통합번호": "contract_delivery_integrated_no",
    "계약납품통합변경차수": "contract_delivery_integrated_change_seq",
    "계약요청접수번호": "contract_request_no",
    "장기계속차수": "long_term_continuation_seq",
    "입찰공고차수": "bid_notice_seq",
    "입찰공고번호": "bid_notice_no",
    "초년도계약번호": "initial_year_contract_no",
    "대표물품분류": "representative_item_category_code",   # 코드 (e.g. '76121598')
    "대표물품분류명": "representative_item_category",       # 명칭 (빈헤더 → _fix_unnamed_columns)
    "세부품명": "detail_item_code",                        # 코드 (e.g. '7612159801')
    "세부품명명": "detail_item_name",                       # 명칭 (빈헤더 → _fix_unnamed_columns)
    "공공조달분류": "public_procurement_category",
    "대분류공공조달분류": "public_procurement_category_major",
    "중분류공공조달분류": "public_procurement_category_mid",
    "계약명": "contract_title",
    "계약기간내용": "contract_period_content",
    "공공조달구분": "public_procurement_type",
    "MAS여부": "is_mas",
    "우수제품여부": "is_quality_product",
    "최종계약납품요구여부": "is_final_contract_delivery_required",
    "최초계약납품요구여부": "is_initial_contract_delivery_required",
    "장기초년도계약여부": "is_initial_long_term_contract",
    "기준연도": "base_year",
    "기준년월": "base_year_month",
    "기준반기": "base_half_year",
    "기준분기": "base_quarter",
    "기준일자": "base_date",
    "최대납품기한일자": "max_delivery_due_date",
    "최초기준일자": "initial_base_date",
    "완수일자": "completion_date",
    "착수일자": "start_date",
    "조달업무영역": "procurement_work_area",
    "조달방식구분": "procurement_method_type",
    "계약유형": "contract_type",
    "계약방법": "contract_method",
    "계약법유형": "contract_law_type",
    "공동수급구성방식": "joint_supply_type",
    "공동수급사유": "joint_supply_reason",
    "신규장기구분": "new_long_term_type",
    "조항호": "clause_no",
    "낙찰방법": "award_method",
    "표준계약방법": "standard_contract_method",
    "현장지역": "site_region",
    "업종": "business_type",
    "분담업종": "assigned_business_type",
    "계약변경구분": "contract_change_type",
    "계약지청": "contract_branch",
    "수요기관": "demand_agency_code",                      # 코드 (e.g. '1613191')
    "수요기관명": "demand_agency",                          # 명칭 (빈헤더 → _fix_unnamed_columns)
    "수요기관지역": "demand_agency_region",
    "수요기관사업자등록번호": "demand_agency_biz_no",
    "소관구분": "department_type",
    "수요기관최상위기관": "demand_agency_top",
    "계약업체사업자등록번호": "vendor_biz_reg_no",
    "계약업체": "vendor_name",
    "계약시점 기업형태구분": "company_type_at_contract",
    "계약시점 사회적기업인증여부": "is_social_enterprise_at_contract",
    "계약시점 업체명": "vendor_name_at_contract",
    "계약시점 업체대표자명": "vendor_rep_at_contract",
    "계약시점 업체지역": "vendor_region_at_contract",
    "계약시점 여성기업인증여부": "is_women_enterprise_at_contract",
    "계약시점 장애인기업인증여부": "is_disabled_enterprise_at_contract",
    "총부기계약금액": "total_supplementary_amount",
    "최초계약금액": "first_contract_amount",
    "계약지분율": "contract_share_pct",
    "총부기계약지분금액": "total_supplementary_share_amount",
    "계약지분금액": "contract_share_amount",
    "계약지분증감금액": "contract_share_amount_delta",
    "계약납품수량": "contract_delivery_qty",
    "계약납품증감수량": "contract_delivery_qty_delta",
    "계약금액": "contract_amount",
    "계약증감금액": "contract_amount_delta",
}

REQUIRED_COLUMNS = [
    "contract_delivery_integrated_no",
    "contract_delivery_integrated_change_seq",
    "vendor_biz_reg_no",
    "business_type",
]

CSV_DTYPE = {
    "계약납품통합번호": str,
    "계약요청접수번호": str,
    "입찰공고번호": str,
    "초년도계약번호": str,
    "수요기관사업자등록번호": str,
    "계약업체사업자등록번호": str,
    # 날짜 컬럼: float 파싱 방지 ('20151229.0' 같은 변환 차단)
    "기준일자": str,
    "최초기준일자": str,
    "착수일자": str,
    "완수일자": str,
    "최대납품기한일자": str,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="용역 계약 업체 내역 CSV → service_contract_raw")
    parser.add_argument("--downloads-dir", default="./downloads_service")
    parser.add_argument("--completed-dir", default="./completed_service")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--dedupe-in-file", action="store_true")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--stop-on-fail", dest="stop_on_fail", action="store_true")
    group.add_argument("--no-stop-on-fail", dest="stop_on_fail", action="store_false")
    parser.set_defaults(stop_on_fail=True)
    return parser.parse_args()


def list_source_files(downloads_dir: str) -> List[str]:
    files = glob.glob(os.path.join(downloads_dir, "*.csv"))
    return sorted(files, key=lambda p: (os.path.getmtime(p), os.path.basename(p).lower()))


def ensure_log_table(engine) -> None:
    create_sql = f"""
        CREATE TABLE IF NOT EXISTS {LOG_TABLE_NAME} (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            file_path VARCHAR(512) NOT NULL UNIQUE,
            file_name VARCHAR(255) NOT NULL,
            file_mtime BIGINT NOT NULL,
            status VARCHAR(32) NOT NULL,
            rows_inserted BIGINT DEFAULT 0,
            started_at DATETIME NULL,
            finished_at DATETIME NULL,
            error_message TEXT NULL,
            run_id CHAR(36) NULL
        )
    """
    with engine.begin() as conn:
        conn.execute(text(create_sql))


def ensure_data_table(engine) -> None:
    create_sql = """
        CREATE TABLE IF NOT EXISTS service_contract_raw (
            -- ===== PK =====
            contract_delivery_integrated_no        VARCHAR(100)  NOT NULL COMMENT '계약납품통합번호',
            contract_delivery_integrated_change_seq BIGINT        NOT NULL COMMENT '계약납품통합변경차수',
            vendor_biz_reg_no                      VARCHAR(50)   NOT NULL COMMENT '계약업체사업자등록번호',
            business_type                          VARCHAR(200)  NOT NULL DEFAULT '' COMMENT '업종(면허) — 공동수급 시 동일 업체가 복수 업종으로 참여 가능하므로 PK 구성 요소',

            -- ===== 계약 식별 =====
            contract_request_no                    VARCHAR(100)  DEFAULT NULL COMMENT '계약요청접수번호',
            long_term_continuation_seq             VARCHAR(20)   DEFAULT NULL COMMENT '장기계속차수',
            bid_notice_seq                         VARCHAR(20)   DEFAULT NULL COMMENT '입찰공고차수',
            bid_notice_no                          VARCHAR(50)   DEFAULT NULL COMMENT '입찰공고번호',
            initial_year_contract_no               VARCHAR(100)  DEFAULT NULL COMMENT '초년도계약번호 (장기계약 그룹 키)',

            -- ===== 분류 =====
            representative_item_category_code      VARCHAR(50)   DEFAULT NULL COMMENT '대표물품분류코드 (숫자코드, e.g. 76121598)',
            representative_item_category           VARCHAR(200)  DEFAULT NULL COMMENT '대표물품분류명칭 (e.g. 건설폐기물처리서비스)',
            detail_item_code                       VARCHAR(50)   DEFAULT NULL COMMENT '세부품명코드 (숫자코드, e.g. 7612159801)',
            detail_item_name                       VARCHAR(200)  DEFAULT NULL COMMENT '세부품명명칭 (e.g. 건설폐기물처리서비스)',
            public_procurement_category            VARCHAR(50)   DEFAULT NULL COMMENT '공공조달분류코드 (ETL 필터 기준)',
            public_procurement_category_major      VARCHAR(100)  DEFAULT NULL COMMENT '대분류 공공조달분류',
            public_procurement_category_mid        VARCHAR(100)  DEFAULT NULL COMMENT '중분류 공공조달분류',

            -- ===== 계약 기본 정보 =====
            contract_title                         TEXT          DEFAULT NULL COMMENT '계약명',
            contract_period_content                VARCHAR(200)  DEFAULT NULL COMMENT '계약기간내용',
            public_procurement_type                VARCHAR(50)   DEFAULT NULL COMMENT '공공조달구분',
            procurement_work_area                  VARCHAR(50)   DEFAULT NULL COMMENT '조달업무영역 (일반용역/기술용역)',
            procurement_method_type                VARCHAR(50)   DEFAULT NULL COMMENT '조달방식구분 (중앙조달 등)',
            contract_type                          VARCHAR(50)   DEFAULT NULL COMMENT '계약유형 (총액계약 등)',
            contract_method                        VARCHAR(50)   DEFAULT NULL COMMENT '계약방법 (제한경쟁 등)',
            contract_law_type                      VARCHAR(100)  DEFAULT NULL COMMENT '계약법유형 (지방계약법 등)',
            contract_change_type                   VARCHAR(50)   DEFAULT NULL COMMENT '계약변경구분 (내용변경 등)',
            contract_branch                        VARCHAR(100)  DEFAULT NULL COMMENT '계약지청',

            -- ===== 공동수급 =====
            joint_supply_type                      VARCHAR(100)  DEFAULT NULL COMMENT '공동수급구성방식 (분담이행/공동이행)',
            joint_supply_reason                    VARCHAR(200)  DEFAULT NULL COMMENT '공동수급사유',
            assigned_business_type                 VARCHAR(200)  DEFAULT NULL COMMENT '분담업종',

            -- ===== 장기계약 =====
            new_long_term_type                     VARCHAR(50)   DEFAULT NULL COMMENT '신규장기구분 (신규(장기) 등)',

            -- ===== 낙찰 =====
            clause_no                              VARCHAR(100)  DEFAULT NULL COMMENT '조항호',
            award_method                           VARCHAR(100)  DEFAULT NULL COMMENT '낙찰방법',
            standard_contract_method               VARCHAR(100)  DEFAULT NULL COMMENT '표준계약방법',
            site_region                            VARCHAR(100)  DEFAULT NULL COMMENT '현장지역',

            -- ===== 여부 플래그 =====
            is_mas                                 VARCHAR(10)   DEFAULT NULL COMMENT 'MAS여부',
            is_quality_product                     VARCHAR(10)   DEFAULT NULL COMMENT '우수제품여부',
            is_final_contract_delivery_required    VARCHAR(10)   DEFAULT NULL COMMENT '최종계약납품요구여부 (ETL flat 필터 기준)',
            is_initial_contract_delivery_required  VARCHAR(10)   DEFAULT NULL COMMENT '최초계약납품요구여부',
            is_initial_long_term_contract          VARCHAR(10)   DEFAULT NULL COMMENT '장기초년도계약여부',

            -- ===== 기준 기간 =====
            base_year                              VARCHAR(10)   DEFAULT NULL COMMENT '기준연도',
            base_year_month                        VARCHAR(10)   DEFAULT NULL COMMENT '기준년월 (YYYYMM)',
            base_half_year                         VARCHAR(10)   DEFAULT NULL COMMENT '기준반기',
            base_quarter                           VARCHAR(10)   DEFAULT NULL COMMENT '기준분기',
            base_date                              VARCHAR(20)   DEFAULT NULL COMMENT '기준일자 (YYYYMMDD, flat.contract_date 변환 원본)',
            max_delivery_due_date                  VARCHAR(20)   DEFAULT NULL COMMENT '최대납품기한일자 (YYYYMMDD)',
            initial_base_date                      VARCHAR(20)   DEFAULT NULL COMMENT '최초기준일자 (YYYYMMDD, flat.first_contract_date 변환 원본)',
            completion_date                        VARCHAR(20)   DEFAULT NULL COMMENT '완수일자 (YYYYMMDD)',
            start_date                             VARCHAR(20)   DEFAULT NULL COMMENT '착수일자 (YYYYMMDD)',

            -- ===== 수요기관 =====
            demand_agency_code                     VARCHAR(50)   DEFAULT NULL COMMENT '수요기관코드 (숫자코드, e.g. 1613191)',
            demand_agency                          TEXT          DEFAULT NULL COMMENT '수요기관명칭 (e.g. 국토교통부 원주지방국토관리청)',
            demand_agency_region                   VARCHAR(200)  DEFAULT NULL COMMENT '수요기관지역',
            demand_agency_biz_no                   VARCHAR(50)   DEFAULT NULL COMMENT '수요기관사업자등록번호',
            department_type                        VARCHAR(50)   DEFAULT NULL COMMENT '소관구분 (지방정부 등)',
            demand_agency_top                      VARCHAR(200)  DEFAULT NULL COMMENT '수요기관최상위기관',

            -- ===== 계약업체 정보 =====
            vendor_name                            TEXT          DEFAULT NULL COMMENT '계약업체명',
            company_type_at_contract               VARCHAR(50)   DEFAULT NULL COMMENT '계약시점 기업형태구분 (중소기업 등)',
            is_social_enterprise_at_contract       VARCHAR(10)   DEFAULT NULL COMMENT '계약시점 사회적기업인증여부',
            vendor_name_at_contract                VARCHAR(200)  DEFAULT NULL COMMENT '계약시점 업체명',
            vendor_rep_at_contract                 VARCHAR(100)  DEFAULT NULL COMMENT '계약시점 업체대표자명',
            vendor_region_at_contract              VARCHAR(200)  DEFAULT NULL COMMENT '계약시점 업체지역',
            is_women_enterprise_at_contract        VARCHAR(10)   DEFAULT NULL COMMENT '계약시점 여성기업인증여부',
            is_disabled_enterprise_at_contract     VARCHAR(10)   DEFAULT NULL COMMENT '계약시점 장애인기업인증여부',

            -- ===== 금액 =====
            total_supplementary_amount             BIGINT        DEFAULT NULL COMMENT '총부기계약금액',
            first_contract_amount                  BIGINT        DEFAULT NULL COMMENT '최초계약금액',
            contract_share_pct                     VARCHAR(20)   DEFAULT NULL COMMENT '계약지분율 (공동수급 지분 %)',
            total_supplementary_share_amount       BIGINT        DEFAULT NULL COMMENT '총부기계약지분금액',
            contract_share_amount                  BIGINT        DEFAULT NULL COMMENT '계약지분금액',
            contract_share_amount_delta            BIGINT        DEFAULT NULL COMMENT '계약지분증감금액',
            contract_delivery_qty                  BIGINT        DEFAULT NULL COMMENT '계약납품수량',
            contract_delivery_qty_delta            BIGINT        DEFAULT NULL COMMENT '계약납품증감수량',
            contract_amount                        BIGINT        DEFAULT NULL COMMENT '계약금액',
            contract_amount_delta                  BIGINT        DEFAULT NULL COMMENT '계약증감금액',

            PRIMARY KEY (contract_delivery_integrated_no, contract_delivery_integrated_change_seq, vendor_biz_reg_no, business_type),
            KEY idx_vendor_biz_reg_no (vendor_biz_reg_no),
            KEY idx_base_date (base_date),
            KEY idx_public_procurement_category (public_procurement_category),
            KEY idx_is_final (is_final_contract_delivery_required)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
          COMMENT='용역 계약 업체 내역 CSV 원본 적재. PK=(계약납품통합번호, 변경차수, 업체사업자번호, 업종)'
    """
    with engine.begin() as conn:
        conn.execute(text(create_sql))


def fetch_log_record(engine, file_path: str) -> Optional[Dict]:
    with engine.connect() as conn:
        result = conn.execute(
            text(
                f"SELECT file_path, file_mtime, status, rows_inserted FROM {LOG_TABLE_NAME} WHERE file_path = :fp"
            ),
            {"fp": file_path},
        ).mappings().first()
    return dict(result) if result else None


def upsert_log(
    engine,
    *,
    file_path: str,
    file_name: str,
    file_mtime: int,
    status: str,
    rows_inserted: int,
    run_id: str,
    error_message: Optional[object] = None,
    set_started: bool = False,
) -> None:
    msg = str(error_message).replace("\x00", "")[:2000] if error_message else None
    sql = f"""
        INSERT INTO {LOG_TABLE_NAME} (
            file_path, file_name, file_mtime, status, rows_inserted,
            started_at, finished_at, error_message, run_id
        ) VALUES (
            :file_path, :file_name, :file_mtime, :status, :rows_inserted,
            CASE WHEN :set_started = 1 THEN NOW() ELSE NULL END,
            CASE WHEN :set_started = 1 THEN NULL ELSE NOW() END,
            :error_message, :run_id
        )
        ON DUPLICATE KEY UPDATE
            file_name = VALUES(file_name),
            file_mtime = VALUES(file_mtime),
            status = VALUES(status),
            rows_inserted = VALUES(rows_inserted),
            started_at = CASE WHEN :set_started = 1 THEN NOW() ELSE started_at END,
            finished_at = CASE WHEN :set_started = 1 THEN NULL ELSE NOW() END,
            error_message = VALUES(error_message),
            run_id = VALUES(run_id)
    """
    with engine.begin() as conn:
        conn.execute(
            text(sql),
            {
                "file_path": file_path,
                "file_name": file_name,
                "file_mtime": file_mtime,
                "status": status,
                "rows_inserted": rows_inserted,
                "error_message": msg,
                "run_id": run_id,
                "set_started": 1 if set_started else 0,
            },
        )


MAX_CHAR_LENGTH_FOR_INSERT = 8192


def fetch_column_max_lengths(engine, table_name: str) -> Dict[str, int]:
    try:
        with engine.connect() as conn:
            rows = conn.execute(
                text(
                    """
                SELECT column_name, character_maximum_length
                FROM information_schema.columns
                WHERE table_schema = DATABASE() AND table_name = :t AND character_maximum_length IS NOT NULL
                """
                ),
                {"t": table_name},
            ).fetchall()
        return {r[0]: int(r[1]) for r in rows}
    except Exception:
        return {}


_INT64_MAX = 2**63 - 1
_INT64_MIN = -(2**63)


def _clamp_int64(x: float) -> int:
    v = int(round(x))
    return max(_INT64_MIN, min(_INT64_MAX, v))


def _float_to_int64_series(s: pd.Series) -> pd.Series:
    s = pd.to_numeric(s, errors="coerce").replace([np.inf, -np.inf], np.nan).fillna(0)
    s = s.clip(_INT64_MIN, _INT64_MAX).round()
    return s.apply(lambda x: _clamp_int64(x) if np.isfinite(x) and pd.notna(x) else 0)


def _float_to_int64_nullable_series(s: pd.Series) -> pd.Series:
    s = pd.to_numeric(s, errors="coerce").replace([np.inf, -np.inf], np.nan)
    s = s.clip(_INT64_MIN, _INT64_MAX).round()
    return s.apply(lambda x: _clamp_int64(x) if np.isfinite(x) and pd.notna(x) else None)


def apply_column_length_limits(df: pd.DataFrame, max_lengths: Optional[Dict[str, int]]) -> pd.DataFrame:
    if not max_lengths:
        return df
    for col, max_len in max_lengths.items():
        if col in df.columns:
            effective_len = min(max_len, MAX_CHAR_LENGTH_FOR_INSERT)
            df[col] = df[col].astype("string").str.slice(0, effective_len)
    return df


def _fix_unnamed_columns(df: pd.DataFrame) -> pd.DataFrame:
    """pandas가 'Unnamed: N'으로 명명한 빈 헤더 컬럼에 직전 컬럼 기반으로 이름을 부여.

    CSV 구조:
      대표물품분류(코드) | Unnamed:8(명칭) | 세부품명(코드) | Unnamed:10(명칭)
      수요기관(코드)    | Unnamed:48(명칭)
    """
    PAIR_MAP = {
        "대표물품분류": "대표물품분류명",
        "세부품명":     "세부품명명",
        "수요기관":     "수요기관명",
    }
    cols = list(df.columns)
    for i, col in enumerate(cols):
        if col.startswith("Unnamed:") and i > 0:
            prev = cols[i - 1]
            if prev in PAIR_MAP:
                cols[i] = PAIR_MAP[prev]
    df.columns = cols
    return df


def normalize_dataframe(
    df: pd.DataFrame,
    dedupe_in_file: bool,
    max_lengths: Optional[Dict[str, int]] = None,
) -> pd.DataFrame:
    df.columns = [str(c).strip().strip('"') for c in df.columns]
    df = _fix_unnamed_columns(df)
    df = df.rename(columns=KOR_TO_ENG)
    df = df.loc[:, ~df.columns.duplicated(keep="first")]

    missing = [c for c in REQUIRED_COLUMNS if c not in df.columns]
    if missing:
        raise ValueError(f"Missing required columns: {missing}")

    df["contract_delivery_integrated_no"] = df["contract_delivery_integrated_no"].astype(str).str.strip()
    if (df["contract_delivery_integrated_no"] == "").any():
        raise ValueError("contract_delivery_integrated_no contains empty values")

    try:
        df["contract_delivery_integrated_change_seq"] = _float_to_int64_series(
            df["contract_delivery_integrated_change_seq"]
        )
    except Exception as e:
        raise RuntimeError(f"contract_delivery_integrated_change_seq 변환 실패: {e}") from e

    df["vendor_biz_reg_no"] = df["vendor_biz_reg_no"].astype(str).str.strip()
    if (df["vendor_biz_reg_no"] == "").any():
        raise ValueError("vendor_biz_reg_no contains empty values")

    # business_type은 PK 구성 요소이므로 NULL → 빈 문자열로 보정
    if "business_type" in df.columns:
        df["business_type"] = df["business_type"].fillna("").astype(str).str.strip()
    else:
        df["business_type"] = ""

    amount_cols = [
        "total_supplementary_amount", "first_contract_amount",
        "total_supplementary_share_amount", "contract_share_amount",
        "contract_share_amount_delta", "contract_delivery_qty",
        "contract_delivery_qty_delta", "contract_amount", "contract_amount_delta",
    ]
    for col in amount_cols:
        if col in df.columns:
            try:
                s = df[col].astype(str).str.replace(",", "", regex=False)
                df[col] = _float_to_int64_nullable_series(s)
            except Exception as e:
                raise RuntimeError(f"컬럼 {col!r} 변환 실패: {e}") from e

    if dedupe_in_file:
        df = df.drop_duplicates(subset=REQUIRED_COLUMNS, keep="last")

    target = [c for c in KOR_TO_ENG.values() if c in df.columns]
    target = list(dict.fromkeys(target))
    df = df[target]
    return apply_column_length_limits(df, max_lengths)


def iter_file_chunks(file_path: str):
    return pd.read_csv(
        file_path,
        encoding=ENCODING,
        sep=SEPARATOR,
        skiprows=SKIP_ROWS,
        low_memory=False,
        thousands=",",
        chunksize=CHUNK_SIZE,
        dtype=CSV_DTYPE,
    )


def _log_failing_row(file_name: str, chunk_idx: int, batch_start: int, row_idx_in_batch: int, row: "pd.Series", err: Exception) -> None:
    _log("")
    _log("========== 실패 행 상세 ==========")
    _log(f"  파일: {file_name}, 청크: {chunk_idx}, 행: {row_idx_in_batch} (배치 시작: {batch_start})")
    _log(f"  contract_delivery_integrated_no: {row.get('contract_delivery_integrated_no')!r}, vendor_biz_reg_no: {row.get('vendor_biz_reg_no')!r}")
    _log(f"  오류: {err}")
    _log("==================================")
    _log("")


def process_file(
    engine,
    file_path: str,
    *,
    dedupe_in_file: bool,
    dry_run: bool,
    file_name: str,
    max_lengths: Optional[Dict[str, int]],
) -> int:
    inserted = 0
    if dry_run:
        for idx, chunk in enumerate(iter_file_chunks(file_path), start=1):
            if chunk.empty:
                continue
            norm = normalize_dataframe(chunk, dedupe_in_file, max_lengths=max_lengths)
            inserted += len(norm)
            _log(f"   ↳ [{file_name}] 청크 {idx}: {len(norm)}건 검증 (누적 {inserted}건)")
        return inserted

    from sqlalchemy.dialects.mysql import insert as mysql_insert

    def _insert_ignore(table, conn, keys, data_iter):
        """INSERT IGNORE — PK 중복 행은 조용히 건너뜀."""
        stmt = mysql_insert(table.table).values([dict(zip(keys, row)) for row in data_iter])
        conn.execute(stmt.prefix_with("IGNORE"))

    INSERT_BATCH_ROWS = 1000
    with engine.begin() as conn:
        for idx, chunk in enumerate(iter_file_chunks(file_path), start=1):
            if chunk.empty:
                continue
            norm = normalize_dataframe(chunk, dedupe_in_file, max_lengths=max_lengths)
            try:
                norm.to_sql(
                    name=TABLE_NAME, con=conn, if_exists="append",
                    index=False, method=_insert_ignore,
                    chunksize=INSERT_BATCH_ROWS,
                )
                inserted += len(norm)
            except Exception as e:
                _log(f"   ↳ [{file_name}] 청크 {idx} 실패: {e}")
                raise
            _log(f"   ↳ [{file_name}] 청크 {idx}: {len(norm)}건 insert (누적 {inserted}건)")
    return inserted


def main() -> None:
    _log("용역 계약 업체 내역 적재 스크립트 시작.")
    _log(f"현재 작업 디렉터리: {os.path.abspath(os.getcwd())}")
    args = parse_args()
    downloads_dir = os.path.expanduser(args.downloads_dir)
    completed_dir = os.path.expanduser(args.completed_dir)
    downloads_abs = os.path.abspath(downloads_dir)
    _log(f"소스 폴더: {downloads_abs}")
    if not os.path.isdir(downloads_dir):
        _log(f"⚠️ 폴더가 없습니다. 생성 후 CSV를 넣고 다시 실행하세요: {downloads_abs}")
        os.makedirs(downloads_dir, exist_ok=True)
        return

    files = list_source_files(downloads_dir)
    _log(f"폴더 스캔 완료: {len(files)}개 파일")

    if not files:
        _log(f"📭 '{downloads_dir}'에 CSV 파일이 없습니다.")
        return

    _log("DB 연결 및 테이블 확인 중...")
    try:
        engine = create_engine(DB_CONNECTION_STR)
        ensure_log_table(engine)
        ensure_data_table(engine)
        _log("DB 준비 완료.")
    except Exception as e:
        _log(f"❌ DB 연결/테이블 생성 실패: {e}")
        raise
    run_id = str(uuid.uuid4())
    column_max_lengths = fetch_column_max_lengths(engine, TABLE_NAME)

    success_count = 0
    failed_count = 0
    skipped_count = 0
    last_success_file = None
    failed_file = None

    _log(f"🚀 총 {len(files)}개의 파일을 발견했습니다.")
    for idx, file_path in enumerate(files):
        file_name = os.path.basename(file_path)
        file_mtime = int(os.path.getmtime(file_path))
        _log("\n==================================================")
        _log(f"[{idx + 1}/{len(files)}] 처리 시작: {file_name}")
        _log("==================================================")

        existing = fetch_log_record(engine, file_path)
        if existing and existing.get("status") == "SUCCESS" and int(existing.get("file_mtime", 0)) == file_mtime:
            skipped_count += 1
            upsert_log(engine, file_path=file_path, file_name=file_name, file_mtime=file_mtime, status="SKIPPED", rows_inserted=0, run_id=run_id, set_started=False)
            _log("⏭️  스킵: 이미 성공 처리된 파일")
            continue

        upsert_log(engine, file_path=file_path, file_name=file_name, file_mtime=file_mtime, status="RUNNING", rows_inserted=0, run_id=run_id, set_started=True)
        start_time = time.time()
        try:
            rows = process_file(engine, file_path, dedupe_in_file=args.dedupe_in_file, dry_run=args.dry_run, file_name=file_name, max_lengths=column_max_lengths)
            duration = time.time() - start_time
            if args.dry_run:
                upsert_log(engine, file_path=file_path, file_name=file_name, file_mtime=file_mtime, status="SKIPPED", rows_inserted=rows, run_id=run_id, error_message="dry-run", set_started=False)
                _log(f"🧪 DRY RUN 완료 ({duration:.1f}초, {rows}건)")
            else:
                success_count += 1
                last_success_file = file_name
                upsert_log(engine, file_path=file_path, file_name=file_name, file_mtime=file_mtime, status="SUCCESS", rows_inserted=rows, run_id=run_id, set_started=False)
                _log(f"✅ DB 적재 완료 ({duration:.1f}초, {rows}건)")
                os.makedirs(completed_dir, exist_ok=True)
                dest = os.path.join(completed_dir, file_name)
                if os.path.exists(dest):
                    os.remove(dest)
                os.replace(file_path, dest)
                _log(f"📦 파일 이동 완료: {downloads_dir} -> {completed_dir}/{file_name}")
        except Exception as exc:
            failed_count += 1
            failed_file = file_name
            upsert_log(engine, file_path=file_path, file_name=file_name, file_mtime=file_mtime, status="FAILED", rows_inserted=0, run_id=run_id, error_message=exc, set_started=False)
            _log(f"❌ 처리 실패: {exc}")
            if args.stop_on_fail:
                break

    _log("\n🎯 요약")
    _log(f"   성공: {success_count}건 / 실패: {failed_count}건 / 스킵: {skipped_count}건")
    if last_success_file:
        _log(f"   마지막 성공 파일: {last_success_file}")
    if failed_file:
        _log(f"   실패 파일: {failed_file}")


if __name__ == "__main__":
    main()
