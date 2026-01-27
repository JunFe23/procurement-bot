# -*- coding: utf-8 -*-
import argparse
import os
from collections import Counter
from typing import Dict, Iterable, List

import pandas as pd

ENCODING = "utf-16"
SEPARATOR = "\t"
CHUNK_SIZE = 10000
HEADER_MATCH = "조달방식구분"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize specific-item CSV values"
    )
    parser.add_argument(
        "--file",
        required=True,
        help="CSV file path (absolute or relative)",
    )
    parser.add_argument(
        "--columns",
        default="계약방법,MAS여부,조달방식구분,계약유형,계약납품구분",
        help="Comma-separated Korean column names to summarize",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=20,
        help="Top N values to show per column",
    )
    return parser.parse_args()


def detect_header_row(file_path: str, max_lines: int = 200) -> int:
    with open(file_path, "r", encoding=ENCODING, errors="ignore") as handle:
        for idx, line in enumerate(handle):
            if HEADER_MATCH in line:
                return idx
            if idx >= max_lines:
                break
    raise ValueError(f"Header row not found in {file_path}")


def iter_chunks(file_path: str, usecols: List[str]) -> Iterable[pd.DataFrame]:
    header_row = detect_header_row(file_path)
    return pd.read_csv(
        file_path,
        encoding=ENCODING,
        sep=SEPARATOR,
        skiprows=header_row,
        low_memory=False,
        thousands=",",
        chunksize=CHUNK_SIZE,
        usecols=lambda c: c in usecols,
    )


def summarize_values(file_path: str, columns: List[str]) -> Dict[str, Counter]:
    counters: Dict[str, Counter] = {col: Counter() for col in columns}
    for chunk in iter_chunks(file_path, columns):
        if chunk.empty:
            continue
        chunk.columns = [str(c).strip().strip('"') for c in chunk.columns]
        for col in columns:
            if col not in chunk.columns:
                raise ValueError(f"Column not found: {col}")
            series = chunk[col].fillna("").astype(str).str.strip()
            counters[col].update(series)
    return counters


def main() -> None:
    args = parse_args()
    file_path = os.path.expanduser(args.file)
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File not found: {file_path}")

    columns = [c.strip() for c in args.columns.split(",") if c.strip()]
    counters = summarize_values(file_path, columns)

    for col in columns:
        print(f"\n== {col} ==")
        for value, count in counters[col].most_common(args.top):
            label = value if value else "(빈값)"
            print(f"{label}: {count}")

    if "계약방법" in columns:
        has_three_party = "3자단가" in counters["계약방법"]
        print(
            f"\n'3자단가' 포함 여부: {'있음' if has_three_party else '없음'}"
        )


if __name__ == "__main__":
    main()
