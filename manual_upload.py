"""
Usage:
  python manual_upload.py --downloads-dir ./downloads --completed-dir ./completed

Options:
  --downloads-dir      Source directory (default: ./downloads)
  --completed-dir      Archive directory (default: ./completed)
  --dry-run            Validate/normalize only; skip DB insert
  --dedupe-in-file     Drop duplicate rows within a file
  --stop-on-fail       Stop at first failure (default)
  --no-stop-on-fail    Continue on failures
"""

import argparse
import glob
import os
import time
import uuid
from typing import Dict, Iterable, List, Optional

import pandas as pd
from sqlalchemy import create_engine, text

# =========================================================
# [설정]
# =========================================================
# 1. DB 접속 정보
DB_CONNECTION_STR = "mysql+pymysql://root:@localhost:3306/g2b"
TABLE_NAME = "procurement_raw"
LOG_TABLE_NAME = "procurement_ingestion_log"

# 2. 조달청 CSV 포맷 설정
ENCODING = "utf-16"
SEPARATOR = "\t"
SKIP_ROWS = 28
CHUNK_SIZE = 10000

KOR_TO_ENG = {
    "조달구분": "procurement_type",
    "계약구분": "contract_type",
    "계약번호": "contract_no",
    "계약변경차수": "contract_change_seq",
    "물품순번": "item_seq",
    "최종계약여부": "is_final_contract",
    "수요기관명": "demand_agency_name",
    "수요기관코드": "demand_agency_code",
    "수요기관구분": "demand_agency_type",
    "수요기관지역명": "demand_agency_region",
    "계약명": "contract_title",
    "계약법유형": "contract_law_type",
    "조항호명": "article_clause_name",
    "계약방법명": "contract_method",
    "물품분류번호": "item_category_no",
    "물품분류명": "item_category_name",
    "세부품명번호": "detail_item_no",
    "세부품명": "detail_item_name",
    "물품식별번호": "item_identifier_no",
    "물품식별명": "item_identifier_name",
    "MAS여부": "is_mas",
    "우수제품여부": "is_excellent_product",
    "중기간경쟁물품여부": "is_sme_competitive_item",
    "최초기준일자": "first_reference_date",
    "기준일자": "reference_date",
    "납품기한": "delivery_deadline",
    "업체명": "vendor_name",
    "업체사업자등록번호": "vendor_biz_reg_no",
    "기업구분": "company_type",
    "낙찰결정방법": "award_method",
    "공공조달분류번호": "public_procurement_category_no",
    "입찰공고번호": "bid_notice_no",
    "입찰공고차수": "bid_notice_seq",
    "장기계약차수": "long_term_contract_seq",
    "장기계속여부": "is_long_term_continuous",
    "단위": "unit",
    "단가": "unit_price",
    "수량": "quantity",
    "증감수량": "quantity_delta",
    "계약금액": "contract_amount",
    "계약증감금액": "contract_amount_delta",
}

REQUIRED_COLUMNS = ["contract_no", "contract_change_seq", "item_seq"]

CSV_DTYPE = {
    "업체사업자등록번호": str,
    "입찰공고번호": str,
    "계약번호": str,
    "수요기관코드": str,
    "물품분류번호": str,
    "세부품명번호": str,
    "물품식별번호": str,
    "참조번호": str,
    "공공조달분류번호": str,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Download folder -> MySQL ingestion")
    parser.add_argument(
        "--downloads-dir",
        default="./downloads",
        help="Source directory to scan (default: ./downloads)",
    )
    parser.add_argument(
        "--completed-dir",
        default="./completed",
        help="Archive directory for processed files (default: ./completed)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate/normalize only; skip DB insert",
    )
    parser.add_argument(
        "--dedupe-in-file",
        action="store_true",
        help="Drop duplicate rows within each file",
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--stop-on-fail",
        dest="stop_on_fail",
        action="store_true",
        help="Stop at first failure (default)",
    )
    group.add_argument(
        "--no-stop-on-fail",
        dest="stop_on_fail",
        action="store_false",
        help="Continue on failures",
    )
    parser.set_defaults(stop_on_fail=True)
    return parser.parse_args()


def list_source_files(downloads_dir: str) -> List[str]:
    patterns = ["*.csv", "*.xlsx", "*.xls"]
    files: List[str] = []
    for pattern in patterns:
        files.extend(glob.glob(os.path.join(downloads_dir, pattern)))
    return sorted(
        files,
        key=lambda path: (os.path.getmtime(path), os.path.basename(path).lower()),
    )


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


def fetch_log_record(engine, file_path: str) -> Optional[Dict]:
    query = text(
        f"""
        SELECT file_path, file_mtime, status, rows_inserted
        FROM {LOG_TABLE_NAME}
        WHERE file_path = :file_path
        """
    )
    with engine.connect() as conn:
        result = conn.execute(query, {"file_path": file_path}).mappings().first()
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
        error_message = format_error_message(error_message)
    insert_sql = f"""
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
    payload = {
        "file_path": file_path,
        "file_name": file_name,
        "file_mtime": file_mtime,
        "status": status,
        "rows_inserted": rows_inserted,
        "error_message": error_message,
        "run_id": run_id,
        "set_started": 1 if set_started else 0,
    }
    with engine.begin() as conn:
        conn.execute(text(insert_sql), payload)


def format_error_message(error: object, max_len: int = 2000) -> str:
    if isinstance(error, str):
        message = error
    else:
        message = str(error)
    message = message.replace("\x00", "")
    if len(message) <= max_len:
        return message
    head = message[: max_len - 20]
    return f"{head} ... [truncated]"


def normalize_dataframe(df: pd.DataFrame, dedupe_in_file: bool) -> pd.DataFrame:
    df.columns = [str(c).strip() for c in df.columns]
    df = df.rename(columns=KOR_TO_ENG)

    missing = [col for col in REQUIRED_COLUMNS if col not in df.columns]
    if missing:
        raise ValueError(f"Missing required columns: {missing}")

    contract_no = df["contract_no"].where(df["contract_no"].notna(), "")
    df["contract_no"] = contract_no.astype(str).str.strip()
    if (df["contract_no"] == "").any():
        raise ValueError("contract_no contains empty values after normalization")

    for col in ["contract_change_seq", "item_seq"]:
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0).astype("int64")

    if dedupe_in_file:
        df = df.drop_duplicates(subset=REQUIRED_COLUMNS, keep="last")

    target_columns = [col for col in KOR_TO_ENG.values() if col in df.columns]
    return df[target_columns]


def iter_file_chunks(file_path: str) -> Iterable[pd.DataFrame]:
    ext = os.path.splitext(file_path)[1].lower()
    if ext == ".csv":
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
    if ext in [".xlsx", ".xls"]:
        try:
            return [pd.read_excel(file_path)]
        except ImportError as exc:
            raise ImportError(
                "Excel 지원을 위해 openpyxl/xlrd를 설치하세요."
            ) from exc
    raise ValueError(f"Unsupported file extension: {ext}")


def process_file(
    engine,
    file_path: str,
    *,
    dedupe_in_file: bool,
    dry_run: bool,
    file_name: str,
) -> int:
    file_rows = 0
    if dry_run:
        for idx, chunk in enumerate(iter_file_chunks(file_path), start=1):
            if chunk.empty:
                continue
            normalized = normalize_dataframe(chunk, dedupe_in_file)
            file_rows += len(normalized)
            print(
                f"   ↳ [{file_name}] 청크 {idx}: {len(normalized)}건 검증 (누적 {file_rows}건)"
            )
        return file_rows

    with engine.begin() as conn:
        for idx, chunk in enumerate(iter_file_chunks(file_path), start=1):
            if chunk.empty:
                continue
            normalized = normalize_dataframe(chunk, dedupe_in_file)
            normalized.to_sql(
                name=TABLE_NAME,
                con=conn,
                if_exists="append",
                index=False,
                method="multi",
            )
            file_rows += len(normalized)
            print(
                f"   ↳ [{file_name}] 청크 {idx}: {len(normalized)}건 insert (누적 {file_rows}건)"
            )
    return file_rows


def main() -> None:
    args = parse_args()
    downloads_dir = os.path.expanduser(args.downloads_dir)
    completed_dir = os.path.expanduser(args.completed_dir)
    files = list_source_files(downloads_dir)

    if not files:
        print(f"📭 '{downloads_dir}' 폴더에 처리할 파일이 없습니다.")
        return

    engine = create_engine(DB_CONNECTION_STR)
    ensure_log_table(engine)
    run_id = str(uuid.uuid4())

    success_count = 0
    failed_count = 0
    skipped_count = 0
    last_success_file = None
    failed_file = None

    print(f"🚀 총 {len(files)}개의 파일을 발견했습니다.")
    for idx, file_path in enumerate(files):
        file_name = os.path.basename(file_path)
        file_mtime = int(os.path.getmtime(file_path))
        print("\n==================================================")
        print(f"[{idx + 1}/{len(files)}] 처리 시작: {file_name}")
        print("==================================================")

        existing = fetch_log_record(engine, file_path)
        if (
            existing
            and existing.get("status") == "SUCCESS"
            and int(existing.get("file_mtime", 0)) == file_mtime
        ):
            skipped_count += 1
            upsert_log(
                engine,
                file_path=file_path,
                file_name=file_name,
                file_mtime=file_mtime,
                status="SKIPPED",
                rows_inserted=0,
                run_id=run_id,
                error_message=None,
                set_started=False,
            )
            print("⏭️  스킵: 이미 성공 처리된 파일")
            continue

        upsert_log(
            engine,
            file_path=file_path,
            file_name=file_name,
            file_mtime=file_mtime,
            status="RUNNING",
            rows_inserted=0,
            run_id=run_id,
            error_message=None,
            set_started=True,
        )

        start_time = time.time()
        try:
            rows = process_file(
                engine,
                file_path,
                dedupe_in_file=args.dedupe_in_file,
                dry_run=args.dry_run,
                file_name=file_name,
            )
            duration = time.time() - start_time
            if args.dry_run:
                skipped_count += 1
                upsert_log(
                    engine,
                    file_path=file_path,
                    file_name=file_name,
                    file_mtime=file_mtime,
                    status="SKIPPED",
                    rows_inserted=rows,
                    run_id=run_id,
                    error_message="dry-run",
                    set_started=False,
                )
                print(f"🧪 DRY RUN 완료 ({duration:.1f}초, {rows}건)")
            else:
                success_count += 1
                last_success_file = file_name
                upsert_log(
                    engine,
                    file_path=file_path,
                    file_name=file_name,
                    file_mtime=file_mtime,
                    status="SUCCESS",
                    rows_inserted=rows,
                    run_id=run_id,
                    error_message=None,
                    set_started=False,
                )
                print(f"✅ DB 적재 완료 ({duration:.1f}초, {rows}건)")
                if not os.path.exists(completed_dir):
                    os.makedirs(completed_dir)
                destination = os.path.join(completed_dir, file_name)
                if os.path.exists(destination):
                    os.remove(destination)
                os.replace(file_path, destination)
                print(f"📦 파일 이동 완료: {downloads_dir} -> {completed_dir}/{file_name}")
        except Exception as exc:
            failed_count += 1
            failed_file = file_name
            error_message = exc
            upsert_log(
                engine,
                file_path=file_path,
                file_name=file_name,
                file_mtime=file_mtime,
                status="FAILED",
                rows_inserted=0,
                run_id=run_id,
                error_message=error_message,
                set_started=False,
            )
            print(f"❌ 처리 실패: {error_message}")
            if args.stop_on_fail:
                break

    print("\n🎯 요약")
    print(f"   성공: {success_count}건 / 실패: {failed_count}건 / 스킵: {skipped_count}건")
    if last_success_file:
        print(f"   마지막 성공 파일: {last_success_file}")
    if failed_file:
        print(f"   실패 파일: {failed_file}")


if __name__ == "__main__":
    main()