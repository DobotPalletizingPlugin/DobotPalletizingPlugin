#!/usr/bin/env python3
import argparse
import os
import shutil
import tempfile
import zipfile
from pathlib import Path


def replace_zip_entry(zip_path: Path, entry_name: str, source_path: Path) -> None:
    zip_path = zip_path.resolve()
    source_path = source_path.resolve()
    entry_name = entry_name.replace("\\", "/")

    if not zip_path.is_file():
        raise FileNotFoundError(f"zip not found: {zip_path}")
    if not source_path.is_file():
        raise FileNotFoundError(f"source file not found: {source_path}")

    with zipfile.ZipFile(zip_path, "r") as zin:
        names = zin.namelist()
        if entry_name not in names:
            matches = [name for name in names if name.replace("\\", "/").endswith(entry_name)]
            if len(matches) == 1:
                entry_name = matches[0]
            elif len(matches) > 1:
                raise RuntimeError(f"multiple entries match {entry_name}: {matches}")
            else:
                raise RuntimeError(f"entry not found in zip: {entry_name}")

        old_info = zin.getinfo(entry_name)
        old_size = old_info.file_size
        old_crc = old_info.CRC

        fd, tmp_name = tempfile.mkstemp(prefix=zip_path.stem + ".", suffix=".zip", dir=str(zip_path.parent))
        os.close(fd)
        tmp_path = Path(tmp_name)

        try:
            with zipfile.ZipFile(tmp_path, "w") as zout:
                for item in zin.infolist():
                    if item.filename == entry_name:
                        data = source_path.read_bytes()
                        new_info = zipfile.ZipInfo(item.filename, date_time=item.date_time)
                        new_info.compress_type = item.compress_type
                        new_info.comment = item.comment
                        new_info.extra = item.extra
                        new_info.internal_attr = item.internal_attr
                        new_info.external_attr = item.external_attr
                        new_info.create_system = item.create_system
                        zout.writestr(new_info, data)
                    else:
                        zout.writestr(item, zin.read(item.filename))

            shutil.move(str(tmp_path), str(zip_path))
        finally:
            if tmp_path.exists():
                tmp_path.unlink()

    with zipfile.ZipFile(zip_path, "r") as zcheck:
        new_info = zcheck.getinfo(entry_name)
        print(f"replaced: {entry_name}")
        print(f"old size/crc: {old_size}/{old_crc}")
        print(f"new size/crc: {new_info.file_size}/{new_info.CRC}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Replace one file inside a zip archive in place.")
    parser.add_argument("zip_path")
    parser.add_argument("entry_name")
    parser.add_argument("source_path")
    args = parser.parse_args()

    replace_zip_entry(Path(args.zip_path), args.entry_name, Path(args.source_path))


if __name__ == "__main__":
    main()
