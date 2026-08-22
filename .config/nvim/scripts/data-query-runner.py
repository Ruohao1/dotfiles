"""Run one bounded read-only DuckDB query and create a private Parquet result."""

from __future__ import annotations

import argparse
import contextlib
import dataclasses
import json
import os
import pathlib
import resource
import stat
import sys
import unicodedata
from collections.abc import Callable, Sequence
from typing import Any, BinaryIO, NoReturn, TextIO

import duckdb
from pyarrow import parquet

MAX_SQL_BYTES = 1_048_576
MAX_ROWS = 100_000
PROBE_ROWS = 100_001
MAX_FILE_BYTES = 1_073_741_824
MAX_MEMORY = "1GB"
MAX_SPILL = "1GB"
MAX_THREADS = 4
ARROW_BATCH_ROWS = 8192
MAX_DIAGNOSTIC_BYTES = 4096
SUPPORTED_SUFFIXES = frozenset({".csv", ".parquet", ".tsv"})


@dataclasses.dataclass(frozen=True)
class Request:
    source: pathlib.Path
    workspace: pathlib.Path
    spill: pathlib.Path
    result: pathlib.Path


class RunnerFailure(Exception):
    """A failure with a stable command-line exit classification."""

    exit_code = 4


class InputFailure(RunnerFailure):
    exit_code = 2


class PolicyFailure(RunnerFailure):
    exit_code = 3


class ExecutionFailure(RunnerFailure):
    exit_code = 4


class _ArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        raise InputFailure(f"invalid arguments: {message}")


def _contains_control_character(value: str) -> bool:
    return any(unicodedata.category(character) in {"Cc", "Cs"} for character in value)


def _path_argument(label: str, value: str) -> pathlib.Path:
    if _contains_control_character(value):
        raise InputFailure(f"{label} path contains a control character")
    path = pathlib.Path(value)
    if not path.is_absolute():
        raise InputFailure(f"{label} path must be absolute")
    return path


def _private_directory(
    label: str,
    path: pathlib.Path,
    *,
    uid: int,
) -> pathlib.Path:
    try:
        metadata = path.lstat()
    except FileNotFoundError as exc:
        raise InputFailure(f"{label} directory does not exist") from exc
    except OSError as exc:
        raise InputFailure(f"could not inspect {label} directory: {exc}") from exc
    if stat.S_ISLNK(metadata.st_mode):
        raise InputFailure(f"{label} directory must not be a symlink")
    if not stat.S_ISDIR(metadata.st_mode):
        raise InputFailure(f"{label} must be a directory")
    if stat.S_IMODE(metadata.st_mode) != 0o700:
        raise InputFailure(f"{label} directory must have mode 0700")
    if metadata.st_uid != uid:
        raise InputFailure(f"{label} directory must be owned by uid {uid}")
    try:
        canonical = path.resolve(strict=True)
    except OSError as exc:
        raise InputFailure(f"could not resolve {label} directory: {exc}") from exc
    if canonical != path:
        raise InputFailure(
            f"{label} directory must be canonical and contain no symlink"
        )
    return canonical


def _validate_request(
    source_value: str,
    workspace_value: str,
    result_value: str,
    *,
    uid: int | None = None,
) -> Request:
    expected_uid = os.getuid() if uid is None else uid
    source_path = _path_argument("source", source_value)
    workspace_path = _path_argument("workspace", workspace_value)
    result_path = _path_argument("result", result_value)

    try:
        source_metadata = source_path.lstat()
    except FileNotFoundError as exc:
        raise InputFailure("source path does not exist") from exc
    except OSError as exc:
        raise InputFailure(f"could not inspect source path: {exc}") from exc
    if stat.S_ISLNK(source_metadata.st_mode):
        raise InputFailure("source path must not be a symlink")
    if not stat.S_ISREG(source_metadata.st_mode):
        raise InputFailure("source path must be a regular file")
    try:
        source = source_path.resolve(strict=True)
    except OSError as exc:
        raise InputFailure(f"could not resolve source path: {exc}") from exc
    if source != source_path:
        raise InputFailure("source path must be canonical and contain no symlink")
    if source.suffix.lower() not in SUPPORTED_SUFFIXES:
        raise InputFailure("source path has an unsupported extension")
    if not os.access(source, os.R_OK):
        raise InputFailure("source path is not readable")

    workspace = _private_directory("workspace", workspace_path, uid=expected_uid)
    spill_path = workspace / "spill"
    spill = _private_directory("spill", spill_path, uid=expected_uid)

    if os.path.lexists(result_path):
        raise InputFailure("result path already exists")
    if result_path.suffix != ".parquet":
        raise InputFailure("result path must end with .parquet")
    if result_path.parent != workspace:
        raise InputFailure("result path must be a direct child of the workspace")
    try:
        result_parent = result_path.parent.resolve(strict=True)
        result = result_path.resolve(strict=False)
    except OSError as exc:
        raise InputFailure(f"could not resolve result path: {exc}") from exc
    if result_parent != workspace or result != result_path:
        raise InputFailure("result path must be canonical and contain no symlink")

    identities = {str(source), str(workspace), str(spill), str(result)}
    if len(identities) != 4:
        raise InputFailure(
            "source, workspace, spill, and result paths must be distinct"
        )
    return Request(source=source, workspace=workspace, spill=spill, result=result)


def _parse_arguments(argv: Sequence[str]) -> tuple[str, str, str]:
    parser = _ArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("--source", required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--result", required=True)
    arguments = parser.parse_args(list(argv))
    return arguments.source, arguments.workspace, arguments.result


def _read_sql(stdin: BinaryIO) -> str:
    try:
        payload = stdin.read(MAX_SQL_BYTES + 1)
    except Exception as exc:
        raise InputFailure(f"could not read SQL input: {exc}") from exc
    if not isinstance(payload, bytes):
        raise InputFailure("SQL input must be a binary UTF-8 stream")
    if len(payload) > MAX_SQL_BYTES:
        raise InputFailure(f"SQL input exceeds the {MAX_SQL_BYTES}-byte limit")
    try:
        sql = payload.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        raise InputFailure("SQL input is not valid UTF-8") from exc
    if not sql.strip():
        raise InputFailure("SQL input is empty")
    return sql


def _apply_process_limits(
    *,
    setrlimit: Callable[[int, tuple[int, int]], object] = resource.setrlimit,
    set_umask: Callable[[int], object] = os.umask,
) -> None:
    setrlimit(resource.RLIMIT_FSIZE, (MAX_FILE_BYTES, MAX_FILE_BYTES))
    set_umask(0o077)


def _configure_connection(
    request: Request,
    *,
    connect: Callable[..., Any] | None = None,
):
    connector = duckdb.connect if connect is None else connect
    connection: Any | None = None
    try:
        configured: Any = connector(
            ":memory:",
            config={
                "allow_community_extensions": "false",
                "allow_unsigned_extensions": "false",
                "autoload_known_extensions": "false",
                "autoinstall_known_extensions": "false",
            },
        )
        connection = configured
        configured.execute("SET allowed_paths = ?", [[str(request.source)]])
        configured.execute("SET allowed_directories = ?", [[str(request.spill)]])
        configured.execute("SET memory_limit = ?", [MAX_MEMORY])
        configured.execute("SET threads = ?", [MAX_THREADS])
        configured.execute("SET max_temp_directory_size = ?", [MAX_SPILL])
        configured.execute("SET temp_directory = ?", [str(request.spill)])
        configured.execute("SET enable_external_access = false")
        configured.execute("SET lock_configuration = true")
        return configured
    except Exception as exc:
        if connection is not None:
            with contextlib.suppress(Exception):
                connection.close()
        raise ExecutionFailure(f"DuckDB configuration failed: {exc}") from exc


def _statement_type_name(statement_type: object) -> str:
    name = getattr(statement_type, "name", None)
    if isinstance(name, str):
        return name
    return str(statement_type).split(".")[-1]


def _parse_statement(connection, sql: str):
    try:
        statements = connection.extract_statements(sql)
    except Exception as exc:
        raise PolicyFailure(f"SQL parse failed: {exc}") from exc
    if len(statements) != 1:
        raise PolicyFailure(
            f"SQL must contain exactly one statement; parsed {len(statements)} statements"
        )
    statement = statements[0]
    if statement.type != duckdb.StatementType.SELECT:
        statement_type = _statement_type_name(statement.type)
        raise PolicyFailure(f"DuckDB statement class {statement_type} is not permitted")
    return statement


def _close_quietly(value: object | None) -> None:
    if value is None:
        return
    close = getattr(value, "close", None)
    if callable(close):
        with contextlib.suppress(Exception):
            close()


def _unlink_result(path: pathlib.Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except OSError:
        pass


def _validate_result(request: Request) -> None:
    try:
        metadata = request.result.lstat()
    except OSError as exc:
        raise ExecutionFailure(f"could not inspect result file: {exc}") from exc
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise ExecutionFailure("result is not a non-symlink regular file")
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        raise ExecutionFailure("result file does not have mode 0600")
    if metadata.st_uid != os.getuid():
        raise ExecutionFailure("result file is not owned by the current uid")
    if metadata.st_size > MAX_FILE_BYTES:
        raise ExecutionFailure(f"result file exceeds the {MAX_FILE_BYTES}-byte limit")
    try:
        canonical = request.result.resolve(strict=True)
    except OSError as exc:
        raise ExecutionFailure(f"could not resolve result file: {exc}") from exc
    if canonical != request.result:
        raise ExecutionFailure("result file escaped its canonical workspace path")


def _materialize_result(connection, statement, request: Request) -> tuple[int, bool]:
    reader = None
    descriptor: int | None = None
    output = None
    writer = None
    try:
        relation = connection.sql(statement.query).limit(PROBE_ROWS)
        reader = relation.to_arrow_reader(batch_size=ARROW_BATCH_ROWS)
        descriptor = os.open(
            request.result,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
            0o600,
        )
        output = os.fdopen(descriptor, "wb", closefd=True)
        descriptor = None
        writer = parquet.ParquetWriter(output, reader.schema)
        rows_written = 0
        truncated = False
        for batch in reader:
            batch_rows = batch.num_rows
            remaining = MAX_ROWS - rows_written
            if remaining > 0:
                writable_rows = min(remaining, batch_rows)
                if writable_rows > 0:
                    writer.write_batch(
                        batch
                        if writable_rows == batch_rows
                        else batch.slice(0, writable_rows)
                    )
                    rows_written += writable_rows
            if batch_rows > remaining:
                truncated = True
                break

        writer.close()
        writer = None
        output.flush()
        os.fsync(output.fileno())
        output.close()
        output = None
        reader.close()
        reader = None
        _validate_result(request)
        return rows_written, truncated
    finally:
        _close_quietly(writer)
        _close_quietly(output)
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                pass
        _close_quietly(reader)


def _execute_query(request: Request, sql: str) -> dict[str, object]:
    connection = None
    record: dict[str, object] | None = None
    failure: RunnerFailure | None = None
    try:
        _apply_process_limits()
        connection = _configure_connection(request)
        statement = _parse_statement(connection, sql)
        rows, truncated = _materialize_result(connection, statement, request)
        record = {
            "version": 1,
            "ok": True,
            "result": str(request.result),
            "rows": rows,
            "truncated": truncated,
        }
    except RunnerFailure as exc:
        failure = exc
    except Exception as exc:  # noqa: BLE001 - this is the process trust boundary.
        failure = ExecutionFailure(f"DuckDB query or result creation failed: {exc}")

    if connection is not None:
        try:
            connection.close()
        except Exception as exc:  # noqa: BLE001 - DuckDB adapters vary by failure type.
            if failure is None:
                failure = ExecutionFailure(f"could not close DuckDB connection: {exc}")
    if failure is not None:
        _unlink_result(request.result)
        raise failure
    if record is None:
        _unlink_result(request.result)
        raise ExecutionFailure("DuckDB query completed without a result record")
    return record


def _safe_diagnostic_text(message: str) -> str:
    sanitized = "".join(
        character
        if character in {"\n", "\t"}
        or not unicodedata.category(character).startswith("C")
        else "?"
        for character in message
    ).rstrip("\n")
    if not sanitized:
        sanitized = "data query failed"
    encoded = sanitized.encode("utf-8", errors="replace")
    if len(encoded) >= MAX_DIAGNOSTIC_BYTES:
        encoded = encoded[: MAX_DIAGNOSTIC_BYTES - 1]
        while True:
            try:
                sanitized = encoded.decode("utf-8", errors="strict")
                break
            except UnicodeDecodeError:
                encoded = encoded[:-1]
    return sanitized


def _write_diagnostic(stderr: TextIO, message: str) -> None:
    diagnostic = _safe_diagnostic_text(message) + "\n"
    with contextlib.suppress(Exception):
        stderr.write(diagnostic)
        stderr.flush()


def _emit_success(stdout: TextIO, record: dict[str, object]) -> None:
    line = json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n"
    try:
        stdout.write(line)
        stdout.flush()
    except Exception as exc:
        raise ExecutionFailure(
            f"could not write success status to stdout: {exc}"
        ) from exc


def main(
    argv: Sequence[str],
    stdin: BinaryIO,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    request: Request | None = None
    try:
        source, workspace, result = _parse_arguments(argv)
        request = _validate_request(source, workspace, result)
        sql = _read_sql(stdin)
        record = _execute_query(request, sql)
        _emit_success(stdout, record)
        return 0
    except RunnerFailure as exc:
        if request is not None and exc.exit_code == ExecutionFailure.exit_code:
            _unlink_result(request.result)
        _write_diagnostic(stderr, str(exc))
        return exc.exit_code
    except Exception as exc:  # noqa: BLE001 - never expose a process traceback to Neovim.
        if request is not None:
            _unlink_result(request.result)
        _write_diagnostic(stderr, f"unexpected data query runner failure: {exc}")
        return ExecutionFailure.exit_code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:], sys.stdin.buffer, sys.stdout, sys.stderr))
