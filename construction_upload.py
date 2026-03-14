"""
공사 계약 내역 CSV → construction_contract_raw 적재
(물품 계약 상세/특정품목과 동일 방식: 파일 단위 트랜잭션, 로그, 완료 시 completed 이동)
조회용 테이블(flat/construction_contract_grouped) 갱신은 이 스크립트에서 하지 않음.
→ 수동/스케줄/스프링에서 CALL sp_etl_construction_contracts(); 실행.

Usage:
  python construction_upload.py --downloads-dir ./downloads_construction --completed-dir ./completed_construction

Options:
  --downloads-dir      소스 폴더 (기본: ./downloads_construction)
  --completed-dir     처리 완료 이동 폴더 (기본: ./completed_construction)
  --dry-run           검증/정규화만, DB insert 생략
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

# 실행 직후 출력 — pandas 로딩이 수 초~수십 초 걸릴 수 있음 (최초 1회 또는 venv 환경)
def _stderr(msg: str) -> None:
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


_stderr("construction_upload: 스크립트 로딩 중...")
_stderr("  pandas 로딩 중... (최초 실행 시 10~30초 걸릴 수 있음)")
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
# 비밀번호 없이 접속: root:@... (콜론 뒤 비움)
DB_CONNECTION_STR = "mysql+pymysql://root:@localhost:3306/g2b?connect_timeout=10"
TABLE_NAME = "construction_contract_raw"
LOG_TABLE_NAME = "construction_ingestion_log"

ENCODING = "utf-16"
SEPARATOR = "\t"
SKIP_ROWS = 28
CHUNK_SIZE = 10000

# 공사 계약 내역 CSV 한글 컬럼명 → 영문
KOR_TO_ENG = {
    "계약번호": "contract_no",
    "계약변경차수": "contract_change_seq",
    "계약일자": "contract_date",
    "계약명": "contract_title",
    "조달방식구분": "procurement_method_type",
    "업체사업자등록번호": "vendor_biz_reg_no",
    "업체": "vendor_name",
    "수요기관코드": "demand_agency_code",
    "수요기관명": "demand_agency_name",
    "현장지역": "site_region",
    "착수일자": "start_date",
    "완수일자": "completion_date",
    "총완수일자": "total_completion_date",
    "업종": "business_type",
    "계약요청접수번호": "contract_request_no",
    "초년도계약번호": "initial_year_contract_no",
    "장기계속차수이": "long_term_continuation_seq",
    "장기계속차수": "long_term_continuation_seq",
    "입찰공고번호": "bid_notice_no",
    "입찰공고차수": "bid_notice_seq",
    "낙찰율": "award_rate",
    "최초계약일자": "first_contract_date",
    "최초계약여부": "is_first_contract",
    "최종계약여부": "is_final_contract",
    "최초장기계속계약여부": "is_initial_long_term_contract",
    "소관구분": "department_type",
    "수요기관지역": "demand_agency_region",
    "계약시점 여성기업인증여부": "is_women_enterprise_at_contract",
    "계약시점 기업형태구분": "company_type_at_contract",
    "계약법유형": "contract_law_type",
    "표준계약방법": "standard_contract_method",
    "공동수급구성방식": "joint_supply_type",
    "계약지청": "contract_branch",
    "계약기관명": "contract_agency_name",
    "입찰계약방법": "bid_contract_method",
    "낙찰방법": "award_method",
    "대분류공공조달분류": "public_procurement_category_major",
    "중분류공공조달분류": "public_procurement_category_mid",
    "공공조달분류명": "public_procurement_category_name",
    "계약금액": "contract_amount",
    "계약증감금액": "contract_amount_delta",
    "최초계약금액": "first_contract_amount",
    "총부기계약금액": "total_supplementary_amount",
    "예정가격": "estimated_price",
    "추정금액": "estimated_amount",
    "낙찰금액": "award_amount",
}

REQUIRED_COLUMNS = ["contract_no", "contract_change_seq"]

CSV_DTYPE = {
    "계약번호": str,
    "업체사업자등록번호": str,
    "입찰공고번호": str,
    "수요기관코드": str,
    "계약요청접수번호": str,
    "초년도계약번호": str,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="공사 계약 CSV → construction_contract_raw")
    parser.add_argument("--downloads-dir", default="./downloads_construction")
    parser.add_argument("--completed-dir", default="./completed_construction")
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
    """construction_contract_raw 테이블이 없으면 생성 (물품 적재처럼 Python만 실행해도 되도록)"""
    create_sql = """
        CREATE TABLE IF NOT EXISTS construction_contract_raw (
            contract_no                      VARCHAR(100)  NOT NULL COMMENT '계약번호',
            contract_change_seq              BIGINT        NOT NULL COMMENT '계약변경차수',
            contract_date                    VARCHAR(20)   DEFAULT NULL COMMENT '계약일자',
            contract_title                   TEXT          DEFAULT NULL COMMENT '계약명',
            procurement_method_type          VARCHAR(50)   DEFAULT NULL COMMENT '조달방식구분',
            vendor_biz_reg_no                VARCHAR(50)   DEFAULT NULL COMMENT '업체사업자등록번호',
            vendor_name                      TEXT          DEFAULT NULL COMMENT '업체',
            demand_agency_code               VARCHAR(50)   DEFAULT NULL COMMENT '수요기관코드',
            demand_agency_name               TEXT          DEFAULT NULL COMMENT '수요기관명',
            site_region                      VARCHAR(100)  DEFAULT NULL COMMENT '현장지역',
            start_date                       VARCHAR(20)   DEFAULT NULL COMMENT '착수일자',
            completion_date                  VARCHAR(20)   DEFAULT NULL COMMENT '완수일자',
            total_completion_date            VARCHAR(20)   DEFAULT NULL COMMENT '총완수일자',
            business_type                    VARCHAR(100) DEFAULT NULL COMMENT '업종',
            contract_request_no              VARCHAR(100) DEFAULT NULL COMMENT '계약요청접수번호',
            initial_year_contract_no         VARCHAR(100) DEFAULT NULL COMMENT '초년도계약번호',
            long_term_continuation_seq       VARCHAR(20)  DEFAULT NULL COMMENT '장기계속차수',
            bid_notice_no                    VARCHAR(50)   DEFAULT NULL COMMENT '입찰공고번호',
            bid_notice_seq                   VARCHAR(20)  DEFAULT NULL COMMENT '입찰공고차수',
            award_rate                       VARCHAR(50)   DEFAULT NULL COMMENT '낙찰율',
            first_contract_date              VARCHAR(20)   DEFAULT NULL COMMENT '최초계약일자',
            is_first_contract                VARCHAR(10)  DEFAULT NULL COMMENT '최초계약여부',
            is_final_contract                VARCHAR(10)  DEFAULT NULL COMMENT '최종계약여부',
            is_initial_long_term_contract    VARCHAR(10)  DEFAULT NULL COMMENT '최초장기계속계약여부',
            department_type                  VARCHAR(50)  DEFAULT NULL COMMENT '소관구분',
            demand_agency_region             VARCHAR(100) DEFAULT NULL COMMENT '수요기관지역',
            is_women_enterprise_at_contract  VARCHAR(10)  DEFAULT NULL COMMENT '계약시점 여성기업인증여부',
            company_type_at_contract         VARCHAR(50)  DEFAULT NULL COMMENT '계약시점 기업형태구분',
            contract_law_type                VARCHAR(100) DEFAULT NULL COMMENT '계약법유형',
            standard_contract_method          VARCHAR(100) DEFAULT NULL COMMENT '표준계약방법',
            joint_supply_type                VARCHAR(100) DEFAULT NULL COMMENT '공동수급구성방식',
            contract_branch                  VARCHAR(100) DEFAULT NULL COMMENT '계약지청',
            contract_agency_name             TEXT          DEFAULT NULL COMMENT '계약기관명',
            bid_contract_method              VARCHAR(100) DEFAULT NULL COMMENT '입찰계약방법',
            award_method                     VARCHAR(100) DEFAULT NULL COMMENT '낙찰방법',
            public_procurement_category_major VARCHAR(50) DEFAULT NULL COMMENT '대분류공공조달분류',
            public_procurement_category_mid  VARCHAR(50)  DEFAULT NULL COMMENT '중분류공공조달분류',
            public_procurement_category_name TEXT          DEFAULT NULL COMMENT '공공조달분류명',
            contract_amount                  BIGINT        DEFAULT NULL COMMENT '계약금액',
            contract_amount_delta            BIGINT        DEFAULT NULL COMMENT '계약증감금액',
            first_contract_amount            BIGINT        DEFAULT NULL COMMENT '최초계약금액',
            total_supplementary_amount      BIGINT        DEFAULT NULL COMMENT '총부기계약금액',
            estimated_price                  BIGINT        DEFAULT NULL COMMENT '예정가격',
            estimated_amount                 BIGINT        DEFAULT NULL COMMENT '추정금액',
            award_amount                     BIGINT        DEFAULT NULL COMMENT '낙찰금액',
            PRIMARY KEY (contract_no, contract_change_seq),
            KEY idx_vendor_biz_reg_no (vendor_biz_reg_no)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
          COMMENT='공사 계약 내역 CSV 적재 (2017~2025 등)'
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
    if error_message:
        msg = str(error_message).replace("\x00", "")[:2000]
    else:
        msg = None
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


# INSERT 시 문자열 상한 (TEXT 등). 배치 실패 시 문제 행만 건너뛰고 계속 진행.
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


# int64 범위 (BIGINT). 이 범위를 벗어나면 pandas astype가 실패하므로 클리핑 후 변환
_INT64_MAX = 2**63 - 1
_INT64_MIN = -(2**63)


def _clamp_int64(x: float) -> int:
    """float→int 변환 후 BIGINT 범위로 클램프. float 정밀도로 2^63 초과가 나올 수 있음."""
    v = int(round(x))
    return max(_INT64_MIN, min(_INT64_MAX, v))


def _float_to_int64_series(s: pd.Series) -> pd.Series:
    """float 시리즈를 안전하게 int64로 변환. inf/NaN → 0, 범위 초과 클리핑."""
    s = pd.to_numeric(s, errors="coerce").replace([np.inf, -np.inf], np.nan).fillna(0)
    s = s.clip(_INT64_MIN, _INT64_MAX).round()
    return s.apply(lambda x: _clamp_int64(x) if np.isfinite(x) and pd.notna(x) else 0)


def _float_to_int64_nullable_series(s: pd.Series) -> pd.Series:
    """float 시리즈를 정수(NULL 가능)로 변환. inf/범위초과 → None. BIGINT 상한(2^63-1) 초과 시 클램프."""
    s = pd.to_numeric(s, errors="coerce").replace([np.inf, -np.inf], np.nan)
    s = s.clip(_INT64_MIN, _INT64_MAX).round()
    return s.apply(lambda x: _clamp_int64(x) if np.isfinite(x) and pd.notna(x) else None)


def apply_column_length_limits(df: pd.DataFrame, max_lengths: Optional[Dict[str, int]]) -> pd.DataFrame:
    if not max_lengths:
        return df
    for col, max_len in max_lengths.items():
        if col in df.columns:
            # TEXT(65535) 등 긴 컬럼을 그대로 쓰면 배치 패킷이 커져 9h9h → INSERT 상한 적용
            effective_len = min(max_len, MAX_CHAR_LENGTH_FOR_INSERT)
            df[col] = df[col].astype("string").str.slice(0, effective_len)
    return df


def normalize_dataframe(
    df: pd.DataFrame,
    dedupe_in_file: bool,
    max_lengths: Optional[Dict[str, int]] = None,
) -> pd.DataFrame:
    df.columns = [str(c).strip().strip('"') for c in df.columns]
    df = df.rename(columns=KOR_TO_ENG)
    # 중복 컬럼명이 있으면 df[col]이 DataFrame이 되어 .str 호출 시 에러 → 첫 번째만 유지
    df = df.loc[:, ~df.columns.duplicated(keep="first")]

    missing = [c for c in REQUIRED_COLUMNS if c not in df.columns]
    if missing:
        raise ValueError(f"Missing required columns: {missing}")

    df["contract_no"] = df["contract_no"].astype(str).str.strip()
    if (df["contract_no"] == "").any():
        raise ValueError("contract_no contains empty values")

    try:
        df["contract_change_seq"] = _float_to_int64_series(df["contract_change_seq"])
    except Exception as e:
        raise RuntimeError(f"컬럼 'contract_change_seq' 변환 실패: {e}") from e

    amount_cols = [
        "contract_amount", "contract_amount_delta", "first_contract_amount",
        "total_supplementary_amount", "estimated_price", "estimated_amount", "award_amount",
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

    # KOR_TO_ENG.values()에 같은 영문명이 있으면(예: 장기계속차수이/장기계속차수 → long_term_continuation_seq) target 중복 → df[target] 시 컬럼 중복 → .str 에러
    target = list(dict.fromkeys([c for c in KOR_TO_ENG.values() if c in df.columns]))
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
    """실패한 행 상세 로그: 원인 분석 후 코드 수정할 수 있도록."""
    _log("")
    _log("========== 실패 행 상세 (원인 분석용) ==========")
    _log(f"  파일: {file_name}, 청크: {chunk_idx}, 배치 내 행 인덱스: {row_idx_in_batch} (배치 시작: {batch_start})")
    _log(f"  contract_no: {row.get('contract_no')!r}, contract_change_seq: {row.get('contract_change_seq')!r}")
    _log(f"  오류: {err}")
    # 문자열 컬럼 길이·일부 값 (타입/길이 문제 추적용)
    for col in ["contract_title", "vendor_name", "demand_agency_name", "contract_agency_name", "public_procurement_category_name"]:
        if col in row.index:
            val = row[col]
            if pd.isna(val):
                _log(f"  {col}: (NULL)")
            else:
                s = str(val)
                _log(f"  {col}: len={len(s)}, 앞 100자: {s[:100]!r}")
    # 금액/숫자 컬럼 (타입 문제 추적용)
    for col in ["contract_amount", "estimated_price", "estimated_amount", "award_amount"]:
        if col in row.index:
            _log(f"  {col}: {row[col]!r} (type={type(row[col]).__name__})")
    _log("==================================================")
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
    """Returns inserted row count. On failure, logs failing row and re-raises."""
    inserted = 0
    if dry_run:
        for idx, chunk in enumerate(iter_file_chunks(file_path), start=1):
            if chunk.empty:
                continue
            norm = normalize_dataframe(chunk, dedupe_in_file, max_lengths=max_lengths)
            inserted += len(norm)
            _log(f"   ↳ [{file_name}] 청크 {idx}: {len(norm)}건 검증 (누적 {inserted}건)")
        return inserted

    INSERT_BATCH_ROWS = 100
    with engine.begin() as conn:
        for idx, chunk in enumerate(iter_file_chunks(file_path), start=1):
            if chunk.empty:
                continue
            norm = normalize_dataframe(chunk, dedupe_in_file, max_lengths=max_lengths)
            start_row = 0
            while start_row < len(norm):
                batch = norm.iloc[start_row : start_row + INSERT_BATCH_ROWS]
                try:
                    batch.to_sql(name=TABLE_NAME, con=conn, if_exists="append", index=False, method="multi")
                    inserted += len(batch)
                    start_row += len(batch)
                except Exception as e:
                    # 배치 실패 → 실패한 행 한 건 찾아서 상세 로그 후 재발생(건너뛰지 않음)
                    if len(batch) == 1:
                        _log_failing_row(file_name, idx, start_row, 0, batch.iloc[0], e)
                        raise
                    for i in range(len(batch)):
                        row_df = batch.iloc[i : i + 1]
                        try:
                            row_df.to_sql(name=TABLE_NAME, con=conn, if_exists="append", index=False, method="multi")
                            inserted += 1
                        except Exception as row_e:
                            _log_failing_row(file_name, idx, start_row, i, batch.iloc[i], row_e)
                            raise
            _log(f"   ↳ [{file_name}] 청크 {idx}: {len(norm)}건 insert (누적 {inserted}건)")
    return inserted


def main() -> None:
    _log("공사 계약 적재 스크립트 시작.")
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
        ensure_data_table(engine)  # 테이블 없으면 자동 생성
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
