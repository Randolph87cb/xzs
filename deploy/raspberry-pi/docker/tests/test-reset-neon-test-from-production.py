#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
import os
import shutil
import socket
import subprocess
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


SCRIPT = Path(__file__).resolve().parents[1] / "reset-neon-test-from-production.py"
SOURCE_ID = "br-source-fixture"
OLD_TARGET_ID = "br-target-old-fixture"
NEW_TARGET_ID = "br-target-new-fixture"
ENDPOINT_ID = "ep-test-fixture"
ENDPOINT_HOST = "ep-test-fixture.fixture.neon.tech"
PRODUCTION_ENDPOINT_ID = "ep-production-fixture"
PRODUCTION_ENDPOINT_HOST = "ep-production-fixture.fixture.neon.tech"
CHANGED_PRODUCTION_ENDPOINT_ID = "ep-production-changed-fixture"
CHANGED_PRODUCTION_ENDPOINT_HOST = "ep-production-changed-fixture.fixture.neon.tech"
OPERATION_ID = "11111111-1111-1111-1111-111111111111"
CHECKSUM = "a" * 64
TABLE_ROWS = {
    "t_user": 1,
    "t_question": 2,
    "t_exam_paper": 3,
    "t_exam_paper_answer": 4,
    "t_exam_paper_question_customer_answer": 5,
    "t_task_exam_customer_answer": 6,
    "t_question_correction_record": 7,
    "t_question_correction_review_record": 8,
}


class FakeState:
    def __init__(self) -> None:
        self.scenario = "success"
        self.restored = False
        self.calls: list[tuple[str, str, Any]] = []
        self.restore_statuses: list[Any] = [200]
        self.operation_statuses: list[str] = ["finished"]
        self.operation_calls = 0
        self.pagination_calls = 0

    def reset(self, scenario: str = "success") -> None:
        self.__init__()
        self.scenario = scenario

    def branches(self) -> list[dict[str, Any]]:
        target_id = NEW_TARGET_ID if self.restored else OLD_TARGET_ID
        source = {
            "id": SOURCE_ID,
            "name": "production",
            "current_state": "ready",
            "protected": True,
            "default": True,
            "restricted_actions": [],
        }
        target = {
            "id": target_id,
            "name": "test",
            "parent_id": SOURCE_ID,
            "current_state": "ready",
            "protected": False,
            "default": False,
            "restricted_actions": [],
        }
        if self.scenario == "parent_wrong":
            target["parent_id"] = "br-other-fixture"
        elif self.scenario == "protected":
            target["protected"] = True
        elif self.scenario == "default":
            target["default"] = True
        elif self.scenario == "restricted":
            target["restricted_actions"] = [{"name": "restore", "reason": "fixture"}]
        elif self.scenario == "not_ready":
            target["current_state"] = "resetting"
        branches = [source, target]
        if self.scenario == "child":
            branches.append(
                {
                    "id": "br-child-fixture",
                    "name": "child",
                    "parent_id": target_id,
                    "current_state": "ready",
                    "protected": False,
                    "default": False,
                }
            )
        if self.scenario == "duplicate":
            duplicate = dict(target)
            duplicate["id"] = "br-duplicate-fixture"
            branches.append(duplicate)
        if self.scenario == "partial_name":
            branches.append(
                {
                    "id": "br-partial-fixture",
                    "name": "production-copy",
                    "parent_id": SOURCE_ID,
                    "current_state": "ready",
                    "protected": False,
                    "default": False,
                }
            )
        if self.scenario == "preserve_exists":
            branches.append(
                {
                    "id": "br-preserved-fixture",
                    "name": "test-pre-reset-existing-fixture",
                    "parent_id": SOURCE_ID,
                    "current_state": "ready",
                    "protected": False,
                    "default": False,
                }
            )
        return branches


class FakeHandler(BaseHTTPRequestHandler):
    server: "FakeServer"

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def send_json(self, status: int, data: dict[str, Any]) -> None:
        encoded = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path
        state = self.server.state
        state.calls.append(("GET", path, None))
        if path.endswith("/branches"):
            query = urllib.parse.parse_qs(parsed.query)
            branches = state.branches()
            if state.scenario in {"pagination", "partial_name"}:
                if "cursor" not in query:
                    state.pagination_calls += 1
                    extra = []
                    if state.scenario == "partial_name":
                        extra = [item for item in branches if item["name"] == "production-copy"]
                    self.send_json(
                        200,
                        {
                            "branches": [item for item in branches if item["name"] == "production"] + extra,
                            "pagination": {"next": "fixture-next"},
                        },
                    )
                    return
                self.send_json(
                    200,
                    {"branches": [item for item in branches if item["name"] == "test"]},
                )
                return
            self.send_json(200, {"branches": branches})
            return
        if path.endswith("/endpoints"):
            if f"/branches/{SOURCE_ID}/endpoints" in path:
                endpoint_id = PRODUCTION_ENDPOINT_ID
                host = PRODUCTION_ENDPOINT_HOST
                if state.scenario == "source_endpoint_mismatch":
                    endpoint_id = CHANGED_PRODUCTION_ENDPOINT_ID
                    host = CHANGED_PRODUCTION_ENDPOINT_HOST
                elif state.scenario == "source_endpoint_change_after" and state.restored:
                    endpoint_id = CHANGED_PRODUCTION_ENDPOINT_ID
                    host = CHANGED_PRODUCTION_ENDPOINT_HOST
            else:
                endpoint_id = ENDPOINT_ID
                host = ENDPOINT_HOST
                if state.scenario == "endpoint_change" and state.restored:
                    host = "ep-test-fixture.changed.neon.tech"
            self.send_json(
                200,
                {
                    "endpoints": [
                        {"id": endpoint_id, "type": "read_write", "host": host}
                    ]
                },
            )
            return
        if "/operations/" in path:
            index = min(state.operation_calls, len(state.operation_statuses) - 1)
            operation_status = state.operation_statuses[index]
            state.operation_calls += 1
            self.send_json(
                200,
                {"operation": {"id": OPERATION_ID, "status": operation_status}},
            )
            return
        if path == "/api/health":
            if state.scenario == "fly_fail_after" and state.restored:
                self.send_json(503, {"status": "DOWN"})
                return
            self.send_json(200, {"status": "UP", "database": {"status": "UP"}})
            return
        if path in {"/student/index.html", "/admin/index.html"}:
            encoded = b'<html><script type="module"></script></html>'
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
            return
        self.send_json(404, {"code": "not_found"})

    def do_POST(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            body = json.loads(raw.decode("utf-8"))
        except Exception:
            body = None
        state = self.server.state
        state.calls.append(("POST", path, body))
        response = state.restore_statuses.pop(0) if state.restore_statuses else 200
        if response == "disconnect":
            with contextlib_suppress(OSError):
                self.connection.shutdown(socket.SHUT_RDWR)
            self.connection.close()
            return
        if response != 200:
            self.send_json(int(response), {"code": "fixture_error", "message": "fixture"})
            return
        state.restored = True
        operations: list[dict[str, Any]] = [{"id": OPERATION_ID, "status": "running"}]
        if state.scenario == "zero_operations":
            operations = []
        self.send_json(
            200,
            {
                "branch": {"id": NEW_TARGET_ID, "name": "test", "parent_id": SOURCE_ID},
                "operations": operations,
            },
        )


class contextlib_suppress:
    def __init__(self, *exceptions: type[BaseException]):
        self.exceptions = exceptions

    def __enter__(self):
        return self

    def __exit__(self, exception_type, _exception, _traceback):
        return exception_type is not None and issubclass(exception_type, self.exceptions)


class FakeServer(ThreadingHTTPServer):
    def __init__(self, address, handler, state: FakeState):
        super().__init__(address, handler)
        self.state = state


class ResetNeonTestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="xzs-neon-test-reset-tests-"))
        self.state = FakeState()
        self.server = FakeServer(("127.0.0.1", 0), FakeHandler, self.state)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.upstream_file = self.root / "upstream.json"
        self.reset_file = self.root / "reset-state.json"
        self.lock_file = self.root / "ops.lock"
        self.write_upstream()
        self.write_fake_docker()
        self.environment = os.environ.copy()
        self.environment.update(
            {
                "PATH": f"{self.bin_dir}{os.pathsep}{self.environment.get('PATH', '')}",
                "NEON_API_KEY": "fixture-api-token-secret",
                "NEON_PROJECT_ID": "project-fixture",
                "NEON_SOURCE_BRANCH_NAME": "production",
                "NEON_TARGET_BRANCH_NAME": "test",
                "NEON_EXPECTED_TEST_ENDPOINT_ID": ENDPOINT_ID,
                "NEON_TEST_DIRECT_URL": (
                    f"postgresql://fixture_role:fixture-db-secret@{ENDPOINT_HOST}/xzs?sslmode=require"
                ),
                "NEON_TEST_FLY_BASE_URL": self.base_url,
                "XZS_NEON_API_BASE_URL": self.base_url + "/api/v2",
                "XZS_NEON_TEST_MODE": "1",
                "XZS_NEON_DR_STATE_FILE": str(self.upstream_file),
                "XZS_NEON_TEST_RESET_STATE_FILE": str(self.reset_file),
                "XZS_POSTGRES_OPS_LOCK_FILE": str(self.lock_file),
                "XZS_NEON_TEST_MAX_PRODUCTION_SUCCESS_AGE_SECONDS": "14400",
                "XZS_NEON_TEST_OPERATION_TIMEOUT_SECONDS": "0.3",
                "XZS_NEON_TEST_OPERATION_POLL_SECONDS": "0.02",
                "XZS_NEON_API_TIMEOUT_SECONDS": "1",
                "XZS_NEON_API_RETRY_ATTEMPTS": "3",
                "XZS_NEON_API_RETRY_DELAY_SECONDS": "0",
                "XZS_NEON_TEST_VALIDATION_ATTEMPTS": "1",
                "XZS_NEON_TEST_VALIDATION_RETRY_SECONDS": "0",
                "XZS_POSTGRES_IMAGE": "fixture-postgres-image",
                "FAKE_SQL_MODE": "success",
            }
        )

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        shutil.rmtree(self.root)

    def write_upstream(self, **overrides: Any) -> None:
        now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
        data: dict[str, Any] = {
            "schema_version": 1,
            "completed_at_utc": now.isoformat().replace("+00:00", "Z"),
            "source_backup_time_utc": now.strftime("%Y%m%dT%H%M%SZ"),
            "source_archive": "xzs-fixture.dump",
            "source_sha256": CHECKSUM,
            "target_fingerprint": "sha256:" + "b" * 64,
            "target_endpoint_id": PRODUCTION_ENDPOINT_ID,
            "flyway_version": "5.9.0",
            "table_rows": TABLE_ROWS,
            "orphan_answer_rows": 0,
            "orphan_correction_rows": 0,
            "result": "passed",
        }
        data.update(overrides)
        self.upstream_file.write_text(json.dumps(data), encoding="utf-8")

    def write_fake_docker(self) -> None:
        fake = self.bin_dir / "docker"
        rows_output = (
            "flyway_version|5.9.0\n"
            + "\n".join(f"{key}|{value}" for key, value in TABLE_ROWS.items())
            + "\norphan_answer_rows|0\norphan_correction_rows|0"
        )
        fake.write_text(
            f"""#!/usr/bin/env python3
import os
import sys

args = " ".join(sys.argv[1:])
mode = os.environ.get("FAKE_SQL_MODE", "success")
if "current_database()" in args:
    if mode == "identity_fail":
        sys.exit(41)
    print("xzs|fixture_role|f")
    sys.exit(0)
if "flyway_version" in args:
    if mode == "data_fail":
        print("flyway_version|wrong")
        sys.exit(0)
    print({rows_output!r})
    sys.exit(0)
sys.exit(97)
""",
            encoding="utf-8",
        )
        fake.chmod(0o755)

    def run_script(self, *arguments: str, **env_overrides: str) -> subprocess.CompletedProcess[str]:
        environment = self.environment.copy()
        environment.update(env_overrides)
        result = subprocess.run(
            [sys_executable(), str(SCRIPT), *arguments],
            env=environment,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=10,
            check=False,
        )
        self.assert_sanitized(result.stdout + result.stderr)
        return result

    def assert_sanitized(self, text: str) -> None:
        forbidden = (
            "fixture-api-token-secret",
            "fixture-db-secret",
            "postgresql://",
            SOURCE_ID,
            OLD_TARGET_ID,
            NEW_TARGET_ID,
            ENDPOINT_ID,
            ENDPOINT_HOST,
            PRODUCTION_ENDPOINT_ID,
            PRODUCTION_ENDPOINT_HOST,
            CHANGED_PRODUCTION_ENDPOINT_ID,
            CHANGED_PRODUCTION_ENDPOINT_HOST,
            OPERATION_ID,
        )
        for value in forbidden:
            self.assertNotIn(value, text)

    def post_count(self) -> int:
        return sum(1 for method, _path, _body in self.state.calls if method == "POST")

    def assert_failure_before_post(self, scenario: str) -> None:
        self.state.reset(scenario)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.post_count(), 0)
        self.assertFalse(self.reset_file.exists())

    def test_upstream_missing_invalid_and_stale_are_rejected(self) -> None:
        self.upstream_file.unlink()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.post_count(), 0)

        self.upstream_file.write_text("{}", encoding="utf-8")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.post_count(), 0)

        self.write_upstream(target_endpoint_id="production-endpoint-without-prefix")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.post_count(), 0)

        stale = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=1)
        self.write_upstream(completed_at_utc=stale.isoformat().replace("+00:00", "Z"))
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.post_count(), 0)

    def test_consumed_generation_is_noop(self) -> None:
        upstream = json.loads(self.upstream_file.read_text(encoding="utf-8"))
        generation = upstream["source_backup_time_utc"] + ":" + upstream["source_sha256"]
        self.reset_file.write_text(
            json.dumps({"schema_version": 1, "status": "success", "generation": generation}),
            encoding="utf-8",
        )
        result = self.run_script()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.state.calls, [])

    def test_pagination_and_exact_name_matching(self) -> None:
        for scenario in ("pagination", "partial_name"):
            with self.subTest(scenario=scenario):
                self.state.reset(scenario)
                if self.reset_file.exists():
                    self.reset_file.unlink()
                result = self.run_script("--preflight")
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.post_count(), 0)
                self.assertGreaterEqual(self.state.pagination_calls, 1)

    def test_topology_failure_gates(self) -> None:
        for scenario in (
            "parent_wrong",
            "protected",
            "default",
            "restricted",
            "child",
            "duplicate",
            "not_ready",
        ):
            with self.subTest(scenario=scenario):
                self.assert_failure_before_post(scenario)

    def test_preflight_never_posts_or_writes_state(self) -> None:
        result = self.run_script("--preflight")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.post_count(), 0)
        self.assertFalse(self.reset_file.exists())

    def test_preflight_and_preserve_flags_are_mutually_exclusive(self) -> None:
        result = self.run_script("--preflight", "--preserve-current")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.calls, [])
        self.assertFalse(self.reset_file.exists())

    def test_stage1_endpoint_mismatch_blocks_preflight_and_reset(self) -> None:
        for arguments in (("--preflight",), ()):
            with self.subTest(arguments=arguments):
                self.state.reset("source_endpoint_mismatch")
                if self.reset_file.exists():
                    self.reset_file.unlink()
                result = self.run_script(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.post_count(), 0)
                self.assertFalse(self.reset_file.exists())

    def test_restore_success_records_only_final_success(self) -> None:
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.post_count(), 1)
        post = next(call for call in self.state.calls if call[0] == "POST")
        self.assertEqual(set(post[2]), {"source_branch_id"})
        self.assertEqual(post[2]["source_branch_id"], SOURCE_ID)
        state = json.loads(self.reset_file.read_text(encoding="utf-8"))
        self.assertEqual(state["status"], "success")
        self.assertEqual(state["result"], "passed")
        self.assertEqual(state["test_branch_id"], NEW_TARGET_ID)
        self.assertIsNone(state["preserve_under_name"])
        self.assertEqual(os.stat(self.reset_file).st_mode & 0o777, 0o600)

    def test_explicit_preserve_flag_includes_a_unique_name(self) -> None:
        result = self.run_script("--preserve-current")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.post_count(), 1)
        post = next(call for call in self.state.calls if call[0] == "POST")
        self.assertEqual(
            set(post[2]), {"source_branch_id", "preserve_under_name"}
        )
        preserve_name = post[2]["preserve_under_name"]
        self.assertRegex(
            preserve_name,
            r"^test-pre-reset-\d{8}T\d{6}Z-[0-9a-f]{8}$",
        )
        state = json.loads(self.reset_file.read_text(encoding="utf-8"))
        self.assertEqual(state["preserve_under_name"], preserve_name)

    def test_existing_preserve_branch_blocks_manual_but_not_routine_reset(self) -> None:
        self.state.reset("preserve_exists")
        manual = self.run_script("--preserve-current")
        self.assertNotEqual(manual.returncode, 0)
        self.assertEqual(self.post_count(), 0)
        self.assertFalse(self.reset_file.exists())

        self.state.reset("preserve_exists")
        routine = self.run_script()
        self.assertEqual(routine.returncode, 0, routine.stdout)
        self.assertEqual(self.post_count(), 1)
        post = next(call for call in self.state.calls if call[0] == "POST")
        self.assertEqual(set(post[2]), {"source_branch_id"})
        state = json.loads(self.reset_file.read_text(encoding="utf-8"))
        self.assertEqual(state["status"], "success")
        self.assertIsNone(state["preserve_under_name"])

    def test_operation_failure_and_timeout_keep_prepared(self) -> None:
        cases = ((["failed", "error"], "1"), (["running"], "0.1"))
        for statuses, timeout in cases:
            with self.subTest(statuses=statuses):
                self.state.reset("success")
                self.state.operation_statuses = statuses
                if self.reset_file.exists():
                    self.reset_file.unlink()
                result = self.run_script(
                    XZS_NEON_TEST_OPERATION_TIMEOUT_SECONDS=timeout
                )
                self.assertNotEqual(result.returncode, 0)
                state = json.loads(self.reset_file.read_text(encoding="utf-8"))
                self.assertEqual(state["status"], "prepared")

    def test_transport_ambiguity_blocks_the_next_cycle(self) -> None:
        self.state.restore_statuses = ["disconnect"]
        first = self.run_script()
        self.assertNotEqual(first.returncode, 0)
        self.assertEqual(self.post_count(), 1)
        state = json.loads(self.reset_file.read_text(encoding="utf-8"))
        self.assertEqual(state["status"], "ambiguous")

        second = self.run_script()
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual(self.post_count(), 1)

    def test_safe_post_statuses_have_limited_retry(self) -> None:
        for status in (423, 503):
            with self.subTest(status=status):
                self.state.reset("success")
                self.state.restore_statuses = [status, 200]
                if self.reset_file.exists():
                    self.reset_file.unlink()
                result = self.run_script()
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.post_count(), 2)

    def test_restore_post_429_is_not_retried_or_marked_ambiguous(self) -> None:
        self.state.restore_statuses = [429, 200]
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.post_count(), 1)
        state = json.loads(self.reset_file.read_text(encoding="utf-8"))
        self.assertEqual(state["status"], "prepared")
        self.assertNotEqual(state["status"], "success")
        self.assertNotIn("ambiguous_at_utc", state)

    def test_other_client_and_server_errors_are_never_retried(self) -> None:
        for status in (400, 401, 418, 500, 502, 504):
            with self.subTest(status=status):
                self.state.reset("success")
                self.state.restore_statuses = [status, 200]
                if self.reset_file.exists():
                    self.reset_file.unlink()
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.post_count(), 1)
                state = json.loads(self.reset_file.read_text(encoding="utf-8"))
                expected = "ambiguous" if status >= 500 else "prepared"
                self.assertEqual(state["status"], expected)

    def test_changed_branch_id_is_re_resolved_but_endpoint_change_is_rejected(self) -> None:
        success = self.run_script()
        self.assertEqual(success.returncode, 0, success.stdout)
        state = json.loads(self.reset_file.read_text(encoding="utf-8"))
        self.assertEqual(state["test_branch_id"], NEW_TARGET_ID)

        self.state.reset("endpoint_change")
        self.reset_file.unlink()
        failure = self.run_script()
        self.assertNotEqual(failure.returncode, 0)
        state = json.loads(self.reset_file.read_text(encoding="utf-8"))
        self.assertEqual(state["status"], "prepared")

    def test_changed_source_endpoint_after_restore_does_not_write_success(self) -> None:
        self.state.reset("source_endpoint_change_after")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.post_count(), 1)
        state = json.loads(self.reset_file.read_text(encoding="utf-8"))
        self.assertEqual(state["status"], "prepared")

    def test_sql_and_fly_post_validation_failures_do_not_write_success(self) -> None:
        self.state.reset("success")
        sql_failure = self.run_script(FAKE_SQL_MODE="data_fail")
        self.assertNotEqual(sql_failure.returncode, 0)
        state = json.loads(self.reset_file.read_text(encoding="utf-8"))
        self.assertEqual(state["status"], "prepared")

        self.state.reset("fly_fail_after")
        self.reset_file.unlink()
        fly_failure = self.run_script()
        self.assertNotEqual(fly_failure.returncode, 0)
        state = json.loads(self.reset_file.read_text(encoding="utf-8"))
        self.assertEqual(state["status"], "prepared")

    def test_existing_prepared_or_ambiguous_state_blocks_post(self) -> None:
        for status in ("prepared", "ambiguous"):
            with self.subTest(status=status):
                self.state.reset("success")
                self.reset_file.write_text(
                    json.dumps({"schema_version": 1, "status": status}), encoding="utf-8"
                )
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.post_count(), 0)


def sys_executable() -> str:
    return os.environ.get("PYTHON", "python3")


if __name__ == "__main__":
    unittest.main(verbosity=2)
