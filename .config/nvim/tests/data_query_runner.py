"""Assertions for the bounded DuckDB data-query runner."""

from __future__ import annotations

import contextlib
import importlib.metadata
import importlib.util
import io
import json
import os
import pathlib
import stat
import sys
import tempfile
import unittest
from typing import Any, cast
from unittest import mock

import pyarrow

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNNER_PATH = ROOT / "scripts" / "data-query-runner.py"
SPEC = importlib.util.spec_from_file_location("data_query_runner", RUNNER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load runner from {RUNNER_PATH}")
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)

duckdb = runner.duckdb
parquet = runner.parquet


ALLOWED_SQL = (
    "SELECT * FROM 'source.csv' ORDER BY id",
    "FROM 'source.csv' SELECT * ORDER BY id",
    "VALUES (1), (2)",
    "WITH rows AS (SELECT * FROM 'source.csv') SELECT * FROM rows",
    "DESCRIBE SELECT * FROM 'source.csv'",
    "SHOW TABLES",
    "PRAGMA version",
    "PRAGMA database_list",
    "PRAGMA table_info('duckdb_tables')",
)

REJECTED_SQL = (
    "COPY (SELECT 1) TO 'copy.parquet'",
    "CREATE TABLE changed AS SELECT 1",
    "INSERT INTO changed VALUES (1)",
    "UPDATE changed SET value = 2",
    "DELETE FROM changed",
    "ALTER TABLE changed ADD COLUMN extra INTEGER",
    "DROP TABLE changed",
    "ATTACH 'other.duckdb' AS other",
    "DETACH other",
    "INSTALL httpfs",
    "LOAD httpfs",
    "EXPORT DATABASE 'exported'",
    "SET threads = 64",
    "PRAGMA threads=2",
    "PRAGMA memory_limit='100MB'",
    "PRAGMA enable_external_access=false",
    "PRAGMA disable_progress_bar",
    "PRAGMA force_checkpoint",
    "CALL checkpoint()",
    "EXPLAIN SELECT 1",
    "EXPLAIN ANALYZE SELECT 1",
    "BEGIN TRANSACTION",
    "COMMIT",
    "ROLLBACK",
    "PREPARE hidden AS SELECT 1",
    "EXECUTE hidden",
    "SELECT 1; SELECT 2",
)


@contextlib.contextmanager
def working_directory(path: pathlib.Path):
    previous = pathlib.Path.cwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


class Fixture:
    def __init__(
        self, case: unittest.TestCase, source_name: str = "source.csv"
    ) -> None:
        self._temporary = tempfile.TemporaryDirectory(prefix="data-query-runner-")
        case.addCleanup(self._temporary.cleanup)
        self.root = pathlib.Path(self._temporary.name).resolve()
        os.chmod(self.root, 0o700)
        self.source_dir = self.root / "source"
        self.source_dir.mkdir(mode=0o700)
        self.source = self.source_dir / source_name
        self.workspace = self.root / "workspace"
        self.workspace.mkdir(mode=0o700)
        self.spill = self.workspace / "spill"
        self.spill.mkdir(mode=0o700)
        self.result = self.workspace / "result.parquet"
        self.write_csv()

    def write_csv(self, rows: str = "id,name\n2,beta\n1,alpha\n") -> None:
        self.source.write_text(rows, encoding="utf-8")
        os.chmod(self.source, 0o600)

    def argv(self) -> list[str]:
        return [
            "--source",
            str(self.source),
            "--workspace",
            str(self.workspace),
            "--result",
            str(self.result),
        ]

    def run(
        self,
        sql: str | bytes,
        *,
        argv: list[str] | None = None,
        stdout: Any | None = None,
        stderr: io.StringIO | None = None,
    ) -> tuple[int, str, str]:
        payload = sql.encode("utf-8") if isinstance(sql, str) else sql
        output = stdout if stdout is not None else io.StringIO()
        errors = stderr if stderr is not None else io.StringIO()
        with working_directory(self.source_dir):
            code = runner.main(argv or self.argv(), io.BytesIO(payload), output, errors)
        output_text = output.getvalue() if hasattr(output, "getvalue") else ""
        error_text = errors.getvalue() if hasattr(errors, "getvalue") else ""
        return code, output_text, error_text

    def success(self, sql: str) -> dict[str, object]:
        code, output, errors = self.run(sql)
        if code != 0:
            raise AssertionError(f"runner failed with {code}: {errors}")
        if errors != "":
            raise AssertionError(f"runner wrote unexpected stderr: {errors!r}")
        if output.count("\n") != 1 or not output.endswith("\n"):
            raise AssertionError(f"runner did not emit one JSON line: {output!r}")
        record = json.loads(output)
        expected_keys = {"version", "ok", "result", "rows", "truncated"}
        if set(record) != expected_keys:
            raise AssertionError(f"unexpected success schema: {record!r}")
        expected_line = json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n"
        if output != expected_line:
            raise AssertionError(f"success JSON is not compact and sorted: {output!r}")
        return record


class RunnerConstantsTests(unittest.TestCase):
    def test_exact_dependency_versions_and_limits(self) -> None:
        self.assertEqual(importlib.metadata.version("duckdb"), "1.5.5")
        self.assertEqual(importlib.metadata.version("pyarrow"), "25.0.0")
        self.assertEqual(runner.MAX_SQL_BYTES, 1_048_576)
        self.assertEqual(runner.MAX_ROWS, 100_000)
        self.assertEqual(runner.PROBE_ROWS, 100_001)
        self.assertEqual(runner.MAX_FILE_BYTES, 1_073_741_824)
        self.assertEqual(runner.MAX_MEMORY, "1GB")
        self.assertEqual(runner.MAX_SPILL, "1GB")
        self.assertEqual(runner.MAX_THREADS, 4)
        self.assertEqual(runner.ARROW_BATCH_ROWS, 8192)


class ParserPolicyTests(unittest.TestCase):
    def test_all_allowed_parser_classifications_succeed(self) -> None:
        for sql in ALLOWED_SQL:
            with self.subTest(sql=sql):
                statements = duckdb.extract_statements(sql)
                self.assertEqual(len(statements), 1)
                self.assertEqual(statements[0].type, duckdb.StatementType.SELECT)
                fixture = Fixture(self)
                record = fixture.success(sql)
                self.assertEqual(record["version"], 1)
                self.assertIs(record["ok"], True)
                self.assertEqual(record["result"], str(fixture.result))
                self.assertIsInstance(record["rows"], int)
                self.assertIs(record["truncated"], False)

    def test_all_rejected_statement_families_fail_before_execution(self) -> None:
        for sql in REJECTED_SQL:
            with self.subTest(sql=sql):
                fixture = Fixture(self)
                code, output, errors = fixture.run(sql)
                self.assertEqual(code, 3)
                self.assertEqual(output, "")
                self.assertNotEqual(errors, "")
                self.assertFalse(fixture.result.exists())
                if sql == "SELECT 1; SELECT 2":
                    self.assertIn("exactly one", errors.lower())
                else:
                    statements = duckdb.extract_statements(sql)
                    self.assertEqual(len(statements), 1)
                    statement_type = str(statements[0].type).split(".")[-1]
                    self.assertIn(statement_type.lower(), errors.lower())

    def test_parser_handles_comments_strings_and_semicolons_without_prefix_rules(
        self,
    ) -> None:
        allowed = (
            "-- DELETE FROM source\nSELECT 1 AS value",
            "/* COPY source */ SELECT 'INSERT; UPDATE; DROP' AS value",
            "SELECT ';' AS semicolon, 'PRAGMA version' AS text;",
            "WITH write_prefix AS (SELECT 'CREATE TABLE' AS text) SELECT * FROM write_prefix",
        )
        for sql in allowed:
            with self.subTest(sql=sql):
                fixture = Fixture(self)
                record = fixture.success(sql)
                self.assertGreaterEqual(cast(int, record["rows"]), 1)

    def test_empty_whitespace_invalid_utf8_syntax_and_oversize_inputs_fail_cleanly(
        self,
    ) -> None:
        cases = (
            (b"", 2, "empty"),
            (b" \t\r\n", 2, "empty"),
            (b"SELECT '\xff'", 2, "utf-8"),
            (b"SELECT FROM", 3, "parse"),
            (b"x" * (runner.MAX_SQL_BYTES + 1), 2, "1048576"),
        )
        for payload, expected_code, diagnostic in cases:
            with self.subTest(diagnostic=diagnostic):
                fixture = Fixture(self)
                code, output, errors = fixture.run(payload)
                self.assertEqual(code, expected_code)
                self.assertEqual(output, "")
                self.assertIn(diagnostic, errors.lower())
                self.assertFalse(fixture.result.exists())


class FilesystemBoundaryTests(unittest.TestCase):
    def assert_query_rejected(self, fixture: Fixture, sql: str) -> str:
        code, output, errors = fixture.run(sql)
        self.assertNotEqual(code, 0)
        self.assertEqual(output, "")
        self.assertNotEqual(errors, "")
        self.assertFalse(fixture.result.exists())
        return errors

    def test_other_absolute_parent_glob_symlink_and_remote_sources_are_inaccessible(
        self,
    ) -> None:
        fixture = Fixture(self)
        sibling = fixture.root / "sibling.csv"
        sibling.write_text("id\n99\n", encoding="utf-8")
        symlink = fixture.source_dir / "linked.csv"
        symlink.symlink_to(sibling)
        sibling_literal = str(sibling).replace("'", "''")
        attempts = (
            f"SELECT * FROM '{sibling_literal}'",
            "SELECT * FROM '../sibling.csv'",
            "SELECT * FROM '*.csv'",
            "SELECT * FROM 'linked.csv'",
            "SELECT * FROM 'https://example.invalid/data.csv'",
        )
        for sql in attempts:
            with self.subTest(sql=sql):
                self.assert_query_rejected(fixture, sql)

    def test_dynamic_query_functions_cannot_hide_unsafe_access(self) -> None:
        fixture = Fixture(self)
        attempts = (
            "SELECT * FROM query('COPY (SELECT 1) TO ''copy.parquet''')",
            "SELECT * FROM query_table('/etc/passwd')",
        )
        for sql in attempts:
            with self.subTest(sql=sql):
                self.assert_query_rejected(fixture, sql)
        self.assertFalse((fixture.source_dir / "copy.parquet").exists())

    def test_special_source_names_are_passed_as_data_not_shell_text(self) -> None:
        names = (
            "sales report.csv",
            "owner's.csv",
            "-leading.csv",
            "$(touch owned);[x].csv",
            "données-東京.csv",
        )
        for name in names:
            with self.subTest(name=name):
                fixture = Fixture(self, source_name=name)
                quoted = name.replace("'", "''")
                record = fixture.success(f"SELECT * FROM '{quoted}' ORDER BY id")
                self.assertEqual(record["rows"], 2)
                self.assertFalse((fixture.source_dir / "owned").exists())

    def test_control_character_in_source_name_is_rejected_before_connect(self) -> None:
        fixture = Fixture(self, source_name="bad\nname.csv")
        with mock.patch.object(runner.duckdb, "connect") as connect:
            code, output, errors = fixture.run("SELECT 1")
        self.assertEqual(code, 2)
        self.assertEqual(output, "")
        self.assertIn("control", errors.lower())
        connect.assert_not_called()


class InputFormatTests(unittest.TestCase):
    def test_csv_delimiter_inference(self) -> None:
        fixture = Fixture(self)
        record = fixture.success("SELECT id, name FROM 'source.csv' ORDER BY id")
        self.assertEqual(record["rows"], 2)
        table = parquet.read_table(fixture.result)
        self.assertEqual(table.column("id").to_pylist(), [1, 2])
        self.assertEqual(table.column("name").to_pylist(), ["alpha", "beta"])

    def test_tab_delimited_tsv(self) -> None:
        fixture = Fixture(self, source_name="source.tsv")
        fixture.source.write_text("id\tname\n2\tbeta\n1\talpha\n", encoding="utf-8")
        record = fixture.success("SELECT * FROM 'source.tsv' ORDER BY id")
        self.assertEqual(record["rows"], 2)
        table = parquet.read_table(fixture.result)
        self.assertEqual(table.column("name").to_pylist(), ["alpha", "beta"])

    def test_parquet_source_uses_bundled_reader(self) -> None:
        fixture = Fixture(self, source_name="source.parquet")
        parquet.write_table(
            pyarrow.table({"id": [2, 1], "name": ["beta", "alpha"]}), fixture.source
        )
        os.chmod(fixture.source, 0o600)
        record = fixture.success("SELECT * FROM 'source.parquet' ORDER BY id")
        self.assertEqual(record["rows"], 2)
        table = parquet.read_table(fixture.result)
        self.assertEqual(table.column("id").to_pylist(), [1, 2])


class ResultMaterializationTests(unittest.TestCase):
    def test_null_list_struct_and_empty_results_remain_valid_parquet(self) -> None:
        nested = Fixture(self)
        nested_record = nested.success(
            "SELECT NULL::INTEGER AS missing, [1, 2] AS items, "
            "{'name': 'value'} AS details"
        )
        self.assertEqual(nested_record["rows"], 1)
        table = parquet.read_table(nested.result)
        self.assertEqual(table.column("missing").to_pylist(), [None])
        self.assertEqual(table.column("items").to_pylist(), [[1, 2]])
        self.assertEqual(table.column("details").to_pylist(), [{"name": "value"}])

        empty = Fixture(self)
        empty_record = empty.success("SELECT 1 AS value WHERE false")
        self.assertEqual(empty_record["rows"], 0)
        self.assertIs(empty_record["truncated"], False)
        empty_table = parquet.read_table(empty.result)
        self.assertEqual(empty_table.num_rows, 0)
        self.assertEqual(empty_table.column_names, ["value"])

    def test_exact_row_cap_and_probe_row(self) -> None:
        exact = Fixture(self)
        exact_record = exact.success("SELECT range AS id FROM range(100000)")
        self.assertEqual(exact_record["rows"], 100_000)
        self.assertIs(exact_record["truncated"], False)
        self.assertEqual(parquet.read_metadata(exact.result).num_rows, 100_000)

        overflow = Fixture(self)
        overflow_record = overflow.success("SELECT range AS id FROM range(100001)")
        self.assertEqual(overflow_record["rows"], 100_000)
        self.assertIs(overflow_record["truncated"], True)
        self.assertEqual(parquet.read_metadata(overflow.result).num_rows, 100_000)

    def test_result_is_exclusive_regular_non_symlink_mode_0600(self) -> None:
        fixture = Fixture(self)
        fixture.success("SELECT 1 AS value")
        metadata = fixture.result.lstat()
        self.assertTrue(stat.S_ISREG(metadata.st_mode))
        self.assertFalse(stat.S_ISLNK(metadata.st_mode))
        self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o600)
        self.assertLessEqual(metadata.st_size, runner.MAX_FILE_BYTES)

    def test_existing_result_and_result_symlink_are_never_overwritten(self) -> None:
        existing = Fixture(self)
        existing.result.write_bytes(b"sentinel")
        code, output, errors = existing.run("SELECT 1")
        self.assertEqual(code, 2)
        self.assertEqual(output, "")
        self.assertIn("already exists", errors.lower())
        self.assertEqual(existing.result.read_bytes(), b"sentinel")

        linked = Fixture(self)
        target = linked.root / "target.parquet"
        target.write_bytes(b"target")
        linked.result.symlink_to(target)
        code, output, errors = linked.run("SELECT 1")
        self.assertEqual(code, 2)
        self.assertEqual(output, "")
        self.assertIn("already exists", errors.lower())
        self.assertEqual(target.read_bytes(), b"target")

    def test_writer_failure_and_success_output_failure_remove_partial_result(
        self,
    ) -> None:
        fixture = Fixture(self)

        class BrokenWriter:
            def __init__(self, *_args, **_kwargs) -> None:
                raise OSError("injected writer failure")

        with mock.patch.object(runner.parquet, "ParquetWriter", BrokenWriter):
            code, output, errors = fixture.run("SELECT 1 AS value")
        self.assertEqual(code, 4)
        self.assertEqual(output, "")
        self.assertIn("writer failure", errors.lower())
        self.assertFalse(fixture.result.exists())

        status_failure = Fixture(self)

        class BrokenOutput:
            def write(self, _value: str) -> int:
                raise OSError("injected stdout failure")

            def flush(self) -> None:
                return None

        errors_stream = io.StringIO()
        code, _, errors = status_failure.run(
            "SELECT 1 AS value", stdout=BrokenOutput(), stderr=errors_stream
        )
        self.assertEqual(code, 4)
        self.assertIn("stdout", errors.lower())
        self.assertFalse(status_failure.result.exists())


class ConfigurationTests(unittest.TestCase):
    def test_process_limits_are_applied_exactly(self) -> None:
        calls: list[tuple[object, object]] = []
        masks: list[int] = []
        runner._apply_process_limits(
            setrlimit=lambda resource_id, limits: calls.append((resource_id, limits)),
            set_umask=lambda mask: masks.append(mask),
        )
        self.assertEqual(
            calls,
            [
                (
                    runner.resource.RLIMIT_FSIZE,
                    (runner.MAX_FILE_BYTES, runner.MAX_FILE_BYTES),
                )
            ],
        )
        self.assertEqual(masks, [0o077])

    def test_duckdb_security_and_resource_settings_are_locked_in_order(self) -> None:
        fixture = Fixture(self)
        request = runner._validate_request(
            str(fixture.source), str(fixture.workspace), str(fixture.result)
        )

        class FakeConnection:
            def __init__(self) -> None:
                self.executions: list[tuple[str, object]] = []

            def execute(self, query: str, parameters: object = None):
                self.executions.append((query, parameters))
                return self

        connection = FakeConnection()
        connect_calls: list[tuple[str, dict[str, str]]] = []

        def connect(database: str, *, config: dict[str, str]):
            connect_calls.append((database, config))
            return connection

        returned = runner._configure_connection(request, connect=connect)
        self.assertIs(returned, connection)
        self.assertEqual(
            connect_calls,
            [
                (
                    ":memory:",
                    {
                        "allow_community_extensions": "false",
                        "allow_unsigned_extensions": "false",
                        "autoload_known_extensions": "false",
                        "autoinstall_known_extensions": "false",
                    },
                )
            ],
        )
        self.assertEqual(
            connection.executions,
            [
                ("SET allowed_paths = ?", [[str(fixture.source)]]),
                ("SET allowed_directories = ?", [[str(fixture.spill)]]),
                ("SET memory_limit = ?", [runner.MAX_MEMORY]),
                ("SET threads = ?", [runner.MAX_THREADS]),
                ("SET max_temp_directory_size = ?", [runner.MAX_SPILL]),
                ("SET temp_directory = ?", [str(fixture.spill)]),
                ("SET enable_external_access = false", None),
                ("SET lock_configuration = true", None),
            ],
        )


class PathContractTests(unittest.TestCase):
    def assert_input_failure(
        self,
        fixture: Fixture,
        *,
        source: pathlib.Path | None = None,
        workspace: pathlib.Path | None = None,
        result: pathlib.Path | None = None,
        diagnostic: str,
    ) -> None:
        argv = [
            "--source",
            str(source or fixture.source),
            "--workspace",
            str(workspace or fixture.workspace),
            "--result",
            str(result or fixture.result),
        ]
        code, output, errors = fixture.run("SELECT 1", argv=argv)
        self.assertEqual(code, 2)
        self.assertEqual(output, "")
        self.assertIn(diagnostic, errors.lower())

    def test_relative_and_non_file_sources_fail(self) -> None:
        relative = Fixture(self)
        self.assert_input_failure(
            relative, source=pathlib.Path("source.csv"), diagnostic="absolute"
        )

        directory = Fixture(self)
        self.assert_input_failure(
            directory, source=directory.source_dir, diagnostic="regular file"
        )

    def test_source_symlink_and_unsupported_extension_fail(self) -> None:
        linked = Fixture(self)
        target = linked.source
        source_link = linked.source_dir / "alias.csv"
        source_link.symlink_to(target)
        self.assert_input_failure(linked, source=source_link, diagnostic="symlink")

        extension = Fixture(self, source_name="source.json")
        self.assert_input_failure(extension, diagnostic="extension")

    def test_workspace_mode_owner_and_symlink_fail(self) -> None:
        unsafe = Fixture(self)
        os.chmod(unsafe.workspace, 0o755)
        self.assert_input_failure(unsafe, diagnostic="0700")

        foreign = Fixture(self)
        with self.assertRaisesRegex(runner.InputFailure, "owned"):
            runner._validate_request(
                str(foreign.source),
                str(foreign.workspace),
                str(foreign.result),
                uid=os.getuid() + 1,
            )

        linked = Fixture(self)
        real_workspace = linked.workspace
        alternate = linked.root / "real-workspace"
        real_workspace.rename(alternate)
        real_workspace.symlink_to(alternate, target_is_directory=True)
        self.assert_input_failure(linked, diagnostic="symlink")

    def test_result_must_be_absent_direct_parquet_child(self) -> None:
        outside = Fixture(self)
        self.assert_input_failure(
            outside, result=outside.root / "outside.parquet", diagnostic="direct child"
        )

        nested = Fixture(self)
        nested_dir = nested.workspace / "nested"
        nested_dir.mkdir(mode=0o700)
        self.assert_input_failure(
            nested, result=nested_dir / "result.parquet", diagnostic="direct child"
        )

        extension = Fixture(self)
        self.assert_input_failure(
            extension, result=extension.workspace / "result.csv", diagnostic=".parquet"
        )

    def test_spill_must_be_private_existing_owned_non_symlink_directory(self) -> None:
        linked = Fixture(self)
        alternate = linked.root / "spill-target"
        linked.spill.rename(alternate)
        linked.spill.symlink_to(alternate, target_is_directory=True)
        self.assert_input_failure(linked, diagnostic="spill")

        unsafe = Fixture(self)
        os.chmod(unsafe.spill, 0o755)
        self.assert_input_failure(unsafe, diagnostic="0700")

    def test_cli_shape_is_strict(self) -> None:
        fixture = Fixture(self)
        malformed = fixture.argv() + ["unexpected"]
        code, output, errors = fixture.run("SELECT 1", argv=malformed)
        self.assertEqual(code, 2)
        self.assertEqual(output, "")
        self.assertIn("arguments", errors.lower())


class DiagnosticTests(unittest.TestCase):
    def test_diagnostics_are_utf8_bounded_and_control_sanitized(self) -> None:
        stream = io.StringIO()
        runner._write_diagnostic(stream, "bad\x1b[31m\x00value\nnext\t" + ("é" * 5000))
        diagnostic = stream.getvalue()
        self.assertLessEqual(len(diagnostic.encode("utf-8")), 4096)
        self.assertTrue(diagnostic.endswith("\n"))
        self.assertNotIn("\x1b", diagnostic)
        self.assertNotIn("\x00", diagnostic)
        self.assertIn("\nnext\t", diagnostic)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    print("data query runner assertions: ok")
