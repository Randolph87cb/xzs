#!/usr/bin/env python3
"""Safely reset the Neon test branch from the refreshed production branch."""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import secrets
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


API_BASE_URL = "https://console.neon.tech/api/v2"
DEFAULT_FLY_BASE_URL = "https://gesp-csp-quiz.fly.dev"
TABLES = (
    "t_user",
    "t_question",
    "t_exam_paper",
    "t_exam_paper_answer",
    "t_exam_paper_question_customer_answer",
    "t_task_exam_customer_answer",
    "t_question_correction_record",
    "t_question_correction_review_record",
)
SAFE_POST_RETRY_STATUSES = {423, 503}
TERMINAL_OPERATION_FAILURES = {"cancelled", "skipped", "error"}
WAITING_OPERATION_STATUSES = {"scheduling", "running", "failed", "cancelling"}


class SafeFailure(Exception):
    """An expected failure whose short code is safe to log."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


class AmbiguousPost(SafeFailure):
    """A POST may have reached Neon and must never be blindly repeated."""


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def utc_text(value: dt.datetime | None = None) -> str:
    return (value or utc_now()).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def log(event: str, **fields: Any) -> None:
    safe_parts = [event]
    for key, value in fields.items():
        if key not in {"attempt", "count", "status", "phase"}:
            raise RuntimeError("unsafe log field")
        safe_parts.append(f"{key}={value}")
    print(" ".join(safe_parts), flush=True)


def require_text(value: Any, code: str, maximum: int = 256) -> str:
    if not isinstance(value, str) or not value or len(value) > maximum:
        raise SafeFailure(code)
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise SafeFailure(code)
    return value


def env_text(name: str, *, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if value is None:
        raise SafeFailure("config_missing")
    return require_text(value, "config_invalid")


def env_int(name: str, default: int, minimum: int, maximum: int) -> int:
    try:
        value = int(os.environ.get(name, str(default)))
    except ValueError as exc:
        raise SafeFailure("config_invalid") from exc
    if not minimum <= value <= maximum:
        raise SafeFailure("config_invalid")
    return value


def env_float(name: str, default: float, minimum: float, maximum: float) -> float:
    try:
        value = float(os.environ.get(name, str(default)))
    except ValueError as exc:
        raise SafeFailure("config_invalid") from exc
    if not minimum <= value <= maximum:
        raise SafeFailure("config_invalid")
    return value


def require_absolute_path(name: str, default: str) -> Path:
    path = Path(os.environ.get(name, default))
    if not path.is_absolute():
        raise SafeFailure("config_path_invalid")
    return path


def require_root_0600_file(path: Path) -> None:
    try:
        file_stat = path.lstat()
    except OSError as exc:
        raise SafeFailure("secret_file_invalid") from exc
    if stat.S_ISLNK(file_stat.st_mode):
        raise SafeFailure("secret_file_invalid")
    if file_stat.st_uid != 0 or stat.S_IMODE(file_stat.st_mode) != 0o600:
        raise SafeFailure("secret_file_invalid")


def parse_timestamp(value: Any, *, compact: bool = False) -> dt.datetime:
    if not isinstance(value, str):
        raise SafeFailure("upstream_state_invalid")
    try:
        if compact:
            parsed = dt.datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=dt.timezone.utc)
        else:
            parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SafeFailure("upstream_state_invalid") from exc
    if parsed.tzinfo is None:
        raise SafeFailure("upstream_state_invalid")
    return parsed.astimezone(dt.timezone.utc)


def load_json(path: Path, error_code: str) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as stream:
            data = json.load(stream)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise SafeFailure(error_code) from exc
    if not isinstance(data, dict):
        raise SafeFailure(error_code)
    return data


def atomic_write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(data, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
        os.chmod(path, 0o600)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary_name)


@dataclass(frozen=True)
class UpstreamSuccess:
    generation: str
    source_backup_time_utc: str
    source_sha256: str
    target_endpoint_id: str
    flyway_version: str
    table_rows: dict[str, int]


@dataclass(frozen=True)
class Config:
    api_key: str
    project_id: str
    source_name: str
    target_name: str
    expected_endpoint_id: str
    test_direct_url: str
    test_database: str
    test_role: str
    test_host: str
    api_base_url: str
    fly_base_url: str
    upstream_state_file: Path
    reset_state_file: Path
    lock_file: Path
    preserve_prefix: str
    max_upstream_age_seconds: int
    operation_timeout_seconds: float
    operation_poll_seconds: float
    api_timeout_seconds: float
    api_retry_attempts: int
    api_retry_delay_seconds: float
    validation_attempts: int
    validation_retry_seconds: float
    postgres_image: str

    @classmethod
    def from_environment(cls) -> "Config":
        secret_file = os.environ.get("XZS_NEON_TEST_SECRET_FILE")
        if secret_file:
            require_root_0600_file(Path(secret_file))

        api_key = env_text("NEON_API_KEY")
        project_id = env_text("NEON_PROJECT_ID")
        expected_endpoint_id = env_text("NEON_EXPECTED_TEST_ENDPOINT_ID")
        if not re.fullmatch(r"[a-z0-9-]{1,60}", project_id):
            raise SafeFailure("config_invalid")
        if not re.fullmatch(r"ep-[a-z0-9-]{1,57}", expected_endpoint_id):
            raise SafeFailure("config_invalid")

        source_name = env_text("NEON_SOURCE_BRANCH_NAME", default="production")
        target_name = env_text("NEON_TARGET_BRANCH_NAME", default="test")
        if source_name == target_name:
            raise SafeFailure("config_invalid")

        direct_url = env_text("NEON_TEST_DIRECT_URL")
        try:
            parsed_direct = urllib.parse.urlsplit(direct_url)
            direct_port = parsed_direct.port or 5432
        except (TypeError, ValueError) as exc:
            raise SafeFailure("test_url_invalid") from exc
        host = (parsed_direct.hostname or "").lower()
        database = urllib.parse.unquote(parsed_direct.path[1:]) if parsed_direct.path.startswith("/") else ""
        role = urllib.parse.unquote(parsed_direct.username or "")
        direct_query = urllib.parse.parse_qs(parsed_direct.query, keep_blank_values=True)
        if (
            parsed_direct.scheme not in {"postgres", "postgresql"}
            or not host.endswith(".neon.tech")
            or "-pooler." in host
            or not database
            or "/" in database
            or not role
            or direct_port < 1
            or direct_port > 65535
            or host.split(".", 1)[0] != expected_endpoint_id
            or direct_query.get("sslmode") != ["require"]
        ):
            raise SafeFailure("test_url_invalid")

        api_base_url = os.environ.get("XZS_NEON_API_BASE_URL", API_BASE_URL).rstrip("/")
        if api_base_url != API_BASE_URL:
            parsed_api = urllib.parse.urlsplit(api_base_url)
            if (
                os.environ.get("XZS_NEON_TEST_MODE") != "1"
                or parsed_api.scheme != "http"
                or parsed_api.hostname not in {"127.0.0.1", "localhost", "::1"}
                or parsed_api.username
                or parsed_api.password
            ):
                raise SafeFailure("api_base_url_invalid")

        fly_base_url = env_text("NEON_TEST_FLY_BASE_URL", default=DEFAULT_FLY_BASE_URL).rstrip("/")
        parsed_fly = urllib.parse.urlsplit(fly_base_url)
        if (
            parsed_fly.scheme not in {"http", "https"}
            or not parsed_fly.hostname
            or parsed_fly.username
            or parsed_fly.password
            or parsed_fly.query
            or parsed_fly.fragment
        ):
            raise SafeFailure("fly_url_invalid")

        prefix = env_text("NEON_TEST_PRESERVE_PREFIX", default="test-pre-reset-")
        if len(prefix) > 180 or not re.fullmatch(r"[A-Za-z0-9._/-]+", prefix):
            raise SafeFailure("config_invalid")

        return cls(
            api_key=api_key,
            project_id=project_id,
            source_name=source_name,
            target_name=target_name,
            expected_endpoint_id=expected_endpoint_id,
            test_direct_url=direct_url,
            test_database=database,
            test_role=role,
            test_host=host,
            api_base_url=api_base_url,
            fly_base_url=fly_base_url,
            upstream_state_file=require_absolute_path(
                "XZS_NEON_DR_STATE_FILE", "/var/lib/xzs-neon-dr-refresh/last-success.json"
            ),
            reset_state_file=require_absolute_path(
                "XZS_NEON_TEST_RESET_STATE_FILE",
                "/var/lib/xzs-neon-dr-refresh/test-reset-state.json",
            ),
            lock_file=require_absolute_path(
                "XZS_POSTGRES_OPS_LOCK_FILE", "/run/lock/xzs-postgres-ops.lock"
            ),
            preserve_prefix=prefix,
            max_upstream_age_seconds=env_int(
                "XZS_NEON_TEST_MAX_PRODUCTION_SUCCESS_AGE_SECONDS", 14400, 60, 86400
            ),
            operation_timeout_seconds=env_float(
                "XZS_NEON_TEST_OPERATION_TIMEOUT_SECONDS", 600.0, 0.1, 7200.0
            ),
            operation_poll_seconds=env_float(
                "XZS_NEON_TEST_OPERATION_POLL_SECONDS", 5.0, 0.01, 60.0
            ),
            api_timeout_seconds=env_float("XZS_NEON_API_TIMEOUT_SECONDS", 20.0, 0.1, 120.0),
            api_retry_attempts=env_int("XZS_NEON_API_RETRY_ATTEMPTS", 5, 1, 10),
            api_retry_delay_seconds=env_float(
                "XZS_NEON_API_RETRY_DELAY_SECONDS", 2.0, 0.0, 60.0
            ),
            validation_attempts=env_int("XZS_NEON_TEST_VALIDATION_ATTEMPTS", 20, 1, 100),
            validation_retry_seconds=env_float(
                "XZS_NEON_TEST_VALIDATION_RETRY_SECONDS", 3.0, 0.0, 60.0
            ),
            postgres_image=env_text("XZS_POSTGRES_IMAGE", default="postgres:18.4-bookworm"),
        )


def load_upstream_success(config: Config) -> UpstreamSuccess:
    if not config.upstream_state_file.is_file() or config.upstream_state_file.is_symlink():
        raise SafeFailure("upstream_state_missing")
    data = load_json(config.upstream_state_file, "upstream_state_invalid")
    required = {
        "schema_version",
        "completed_at_utc",
        "source_backup_time_utc",
        "source_archive",
        "source_sha256",
        "target_fingerprint",
        "target_endpoint_id",
        "flyway_version",
        "table_rows",
        "orphan_answer_rows",
        "orphan_correction_rows",
        "result",
    }
    if set(data) != required or data.get("schema_version") != 1 or data.get("result") != "passed":
        raise SafeFailure("upstream_state_invalid")
    completed_at = parse_timestamp(data.get("completed_at_utc"))
    age = (utc_now() - completed_at).total_seconds()
    if age < -300 or age > config.max_upstream_age_seconds:
        raise SafeFailure("upstream_state_stale")
    backup_time = require_text(data.get("source_backup_time_utc"), "upstream_state_invalid")
    parse_timestamp(backup_time, compact=True)
    checksum = require_text(data.get("source_sha256"), "upstream_state_invalid")
    if not re.fullmatch(r"[0-9a-f]{64}", checksum):
        raise SafeFailure("upstream_state_invalid")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", str(data.get("target_fingerprint", ""))):
        raise SafeFailure("upstream_state_invalid")
    target_endpoint_id = require_text(
        data.get("target_endpoint_id"), "upstream_state_invalid", maximum=60
    )
    if not re.fullmatch(r"ep-[a-z0-9-]{1,57}", target_endpoint_id):
        raise SafeFailure("upstream_state_invalid")
    rows = data.get("table_rows")
    if not isinstance(rows, dict) or set(rows) != set(TABLES):
        raise SafeFailure("upstream_state_invalid")
    normalized_rows: dict[str, int] = {}
    for table in TABLES:
        value = rows.get(table)
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise SafeFailure("upstream_state_invalid")
        normalized_rows[table] = value
    if data.get("orphan_answer_rows") != 0 or data.get("orphan_correction_rows") != 0:
        raise SafeFailure("upstream_state_invalid")
    generation = f"{backup_time}:{checksum}"
    return UpstreamSuccess(
        generation=generation,
        source_backup_time_utc=backup_time,
        source_sha256=checksum,
        target_endpoint_id=target_endpoint_id,
        flyway_version=require_text(data.get("flyway_version"), "upstream_state_invalid"),
        table_rows=normalized_rows,
    )


def load_reset_state(config: Config) -> dict[str, Any] | None:
    if not config.reset_state_file.exists():
        return None
    if not config.reset_state_file.is_file() or config.reset_state_file.is_symlink():
        raise SafeFailure("reset_state_invalid")
    data = load_json(config.reset_state_file, "reset_state_invalid")
    if data.get("schema_version") != 1 or data.get("status") not in {
        "success",
        "prepared",
        "ambiguous",
    }:
        raise SafeFailure("reset_state_invalid")
    return data


class NeonApi:
    def __init__(self, config: Config):
        self.config = config

    def _url(self, path: str, query: dict[str, Any] | None = None) -> str:
        url = f"{self.config.api_base_url}/{path.lstrip('/')}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        return url

    def request_json(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, Any] | None = None,
        body: dict[str, Any] | None = None,
        is_restore_post: bool = False,
    ) -> dict[str, Any]:
        payload = None if body is None else json.dumps(body, separators=(",", ":")).encode("utf-8")
        attempts = self.config.api_retry_attempts
        for attempt in range(1, attempts + 1):
            request = urllib.request.Request(
                self._url(path, query),
                data=payload,
                method=method,
                headers={
                    "Accept": "application/json",
                    "Authorization": f"Bearer {self.config.api_key}",
                    "Content-Type": "application/json",
                    "User-Agent": "xzs-neon-test-reset/1",
                },
            )
            try:
                with urllib.request.urlopen(request, timeout=self.config.api_timeout_seconds) as response:
                    raw = response.read(2 * 1024 * 1024)
                    status = response.status
                if status < 200 or status >= 300:
                    raise SafeFailure("api_status_unexpected")
                try:
                    parsed = json.loads(raw.decode("utf-8"))
                except (UnicodeError, json.JSONDecodeError) as exc:
                    if is_restore_post:
                        raise AmbiguousPost("restore_response_ambiguous") from exc
                    raise SafeFailure("api_response_invalid") from exc
                if not isinstance(parsed, dict):
                    if is_restore_post:
                        raise AmbiguousPost("restore_response_ambiguous")
                    raise SafeFailure("api_response_invalid")
                return parsed
            except urllib.error.HTTPError as exc:
                status = exc.code
                with contextlib.suppress(Exception):
                    exc.read(2 * 1024 * 1024)
                retryable = (
                    status in SAFE_POST_RETRY_STATUSES
                    if is_restore_post
                    else status == 423 or status == 429 or 500 <= status <= 599
                )
                if retryable and attempt < attempts:
                    log("api_retry", attempt=attempt, status=status)
                    self._backoff(attempt)
                    continue
                if is_restore_post and status >= 500 and status != 503:
                    raise AmbiguousPost("restore_http_ambiguous") from exc
                if retryable:
                    raise SafeFailure("api_retry_exhausted") from exc
                raise SafeFailure("api_request_rejected") from exc
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                if is_restore_post:
                    raise AmbiguousPost("restore_transport_ambiguous") from exc
                if attempt < attempts:
                    log("api_retry", attempt=attempt, status="transport")
                    self._backoff(attempt)
                    continue
                raise SafeFailure("api_transport_failed") from exc
        raise SafeFailure("api_retry_exhausted")

    def _backoff(self, attempt: int) -> None:
        delay = min(self.config.api_retry_delay_seconds * (2 ** (attempt - 1)), 60.0)
        if delay:
            time.sleep(delay)

    def list_branches(self) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        cursor: str | None = None
        seen_cursors: set[str] = set()
        while True:
            query: dict[str, Any] = {"limit": 10000, "include_deleted": "false"}
            if cursor:
                query["cursor"] = cursor
            response = self.request_json(
                "GET", f"projects/{self.config.project_id}/branches", query=query
            )
            branches = response.get("branches")
            if not isinstance(branches, list) or any(not isinstance(item, dict) for item in branches):
                raise SafeFailure("branches_response_invalid")
            result.extend(branches)
            pagination = response.get("pagination") or {}
            if not isinstance(pagination, dict):
                raise SafeFailure("branches_response_invalid")
            next_cursor = pagination.get("next")
            if next_cursor is None:
                break
            if not isinstance(next_cursor, str) or not next_cursor or next_cursor in seen_cursors:
                raise SafeFailure("branches_pagination_invalid")
            seen_cursors.add(next_cursor)
            cursor = next_cursor
        return result

    def list_endpoints(self, branch_id: str) -> list[dict[str, Any]]:
        response = self.request_json(
            "GET",
            f"projects/{self.config.project_id}/branches/{branch_id}/endpoints",
        )
        endpoints = response.get("endpoints")
        if not isinstance(endpoints, list) or any(not isinstance(item, dict) for item in endpoints):
            raise SafeFailure("endpoints_response_invalid")
        return endpoints

    def restore(
        self, target_id: str, source_id: str, preserve_name: str | None
    ) -> dict[str, Any]:
        body = {"source_branch_id": source_id}
        if preserve_name is not None:
            body["preserve_under_name"] = preserve_name
        return self.request_json(
            "POST",
            f"projects/{self.config.project_id}/branches/{target_id}/restore",
            body=body,
            is_restore_post=True,
        )

    def get_operation(self, operation_id: str) -> dict[str, Any]:
        response = self.request_json(
            "GET", f"projects/{self.config.project_id}/operations/{operation_id}"
        )
        operation = response.get("operation")
        if not isinstance(operation, dict):
            raise SafeFailure("operation_response_invalid")
        return operation


def exact_branch(branches: list[dict[str, Any]], name: str) -> dict[str, Any]:
    matches = [branch for branch in branches if branch.get("name") == name]
    if len(matches) != 1:
        raise SafeFailure("branch_name_ambiguous")
    branch = matches[0]
    if not isinstance(branch.get("id"), str):
        raise SafeFailure("branch_response_invalid")
    return branch


def validate_topology(
    config: Config, branches: list[dict[str, Any]]
) -> tuple[dict[str, Any], dict[str, Any]]:
    source = exact_branch(branches, config.source_name)
    target = exact_branch(branches, config.target_name)
    if source["id"] == target["id"]:
        raise SafeFailure("branch_identity_invalid")
    if source.get("current_state") != "ready" or target.get("current_state") != "ready":
        raise SafeFailure("branch_not_ready")
    if target.get("parent_id") != source["id"]:
        raise SafeFailure("branch_parent_invalid")
    if target.get("protected") is not False:
        raise SafeFailure("target_protected")
    if target.get("default") is not False:
        raise SafeFailure("target_default")
    restricted = target.get("restricted_actions") or []
    if not isinstance(restricted, list):
        raise SafeFailure("branch_response_invalid")
    if any(isinstance(item, dict) and item.get("name") == "restore" for item in restricted):
        raise SafeFailure("target_restore_restricted")
    if any(branch.get("parent_id") == target["id"] for branch in branches):
        raise SafeFailure("target_has_children")
    return source, target


def endpoint_fingerprint(config: Config, endpoints: list[dict[str, Any]]) -> str:
    normalized: list[tuple[str, str, str]] = []
    read_write = []
    for endpoint in endpoints:
        endpoint_id = endpoint.get("id")
        endpoint_type = endpoint.get("type")
        host = endpoint.get("host")
        if not all(
            isinstance(value, str) and value
            for value in (endpoint_id, endpoint_type, host)
        ):
            raise SafeFailure("endpoint_response_invalid")
        normalized.append((endpoint_id, endpoint_type, host.lower()))
        if endpoint_type == "read_write":
            read_write.append(endpoint)
    if len(read_write) != 1 or read_write[0].get("id") != config.expected_endpoint_id:
        raise SafeFailure("endpoint_identity_invalid")
    if str(read_write[0].get("host", "")).lower() != config.test_host:
        raise SafeFailure("endpoint_host_invalid")
    encoded = json.dumps(sorted(normalized), separators=(",", ":")).encode("utf-8")
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def source_endpoint_fingerprint(
    expected_endpoint_id: str, endpoints: list[dict[str, Any]]
) -> str:
    read_write: list[tuple[str, str]] = []
    for endpoint in endpoints:
        endpoint_id = endpoint.get("id")
        endpoint_type = endpoint.get("type")
        host = endpoint.get("host")
        if not all(isinstance(value, str) and value for value in (endpoint_id, endpoint_type, host)):
            raise SafeFailure("source_endpoint_response_invalid")
        if endpoint_type == "read_write":
            normalized_host = host.lower()
            if (
                not re.fullmatch(r"ep-[a-z0-9-]{1,57}", endpoint_id)
                or not normalized_host.endswith(".neon.tech")
                or "-pooler." in normalized_host
                or normalized_host.split(".", 1)[0] != endpoint_id
            ):
                raise SafeFailure("source_endpoint_identity_invalid")
            read_write.append((endpoint_id, normalized_host))
    if len(read_write) != 1 or read_write[0][0] != expected_endpoint_id:
        raise SafeFailure("source_endpoint_identity_invalid")
    encoded = json.dumps(read_write[0], separators=(",", ":")).encode("utf-8")
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def run_sql(config: Config, sql: str) -> str:
    command = [
        "docker",
        "run",
        "--rm",
        "--env",
        "NEON_TEST_DIRECT_URL",
        config.postgres_image,
        "sh",
        "-eu",
        "-c",
        'exec psql "$NEON_TEST_DIRECT_URL" --no-psqlrc --tuples-only --no-align '
        '--field-separator="|" --set ON_ERROR_STOP=1 --command "$1"',
        "sh",
        sql,
    ]
    environment = os.environ.copy()
    environment["NEON_TEST_DIRECT_URL"] = config.test_direct_url
    try:
        process = subprocess.run(
            command,
            env=environment,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=max(config.api_timeout_seconds, 10.0),
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise SafeFailure("sql_validation_failed") from exc
    if process.returncode != 0:
        raise SafeFailure("sql_validation_failed")
    return process.stdout.replace("\r", "").strip()


def retry_validation(config: Config, action: Any, code: str) -> None:
    for attempt in range(1, config.validation_attempts + 1):
        try:
            action()
            return
        except SafeFailure:
            if attempt == config.validation_attempts:
                raise SafeFailure(code)
            log("validation_retry", attempt=attempt)
            if config.validation_retry_seconds:
                time.sleep(config.validation_retry_seconds)


def validate_sql_identity(config: Config) -> None:
    query = "SELECT current_database(), current_user, pg_is_in_recovery();"
    output = run_sql(config, query)
    if output != f"{config.test_database}|{config.test_role}|f":
        raise SafeFailure("sql_identity_invalid")


def validate_sql_data(config: Config, upstream: UpstreamSuccess) -> None:
    query = """
      SELECT 'flyway_version', COALESCE((SELECT version FROM public.flyway_schema_history WHERE success ORDER BY installed_rank DESC LIMIT 1), 'none')
      UNION ALL SELECT 't_user', count(*)::text FROM public.t_user
      UNION ALL SELECT 't_question', count(*)::text FROM public.t_question
      UNION ALL SELECT 't_exam_paper', count(*)::text FROM public.t_exam_paper
      UNION ALL SELECT 't_exam_paper_answer', count(*)::text FROM public.t_exam_paper_answer
      UNION ALL SELECT 't_exam_paper_question_customer_answer', count(*)::text FROM public.t_exam_paper_question_customer_answer
      UNION ALL SELECT 't_task_exam_customer_answer', count(*)::text FROM public.t_task_exam_customer_answer
      UNION ALL SELECT 't_question_correction_record', count(*)::text FROM public.t_question_correction_record
      UNION ALL SELECT 't_question_correction_review_record', count(*)::text FROM public.t_question_correction_review_record
      UNION ALL SELECT 'orphan_answer_rows', count(*)::text
        FROM public.t_exam_paper_question_customer_answer a
        LEFT JOIN public.t_exam_paper_answer p ON p.id = a.exam_paper_answer_id
        WHERE a.exam_paper_answer_id IS NOT NULL AND p.id IS NULL
      UNION ALL SELECT 'orphan_correction_rows', count(*)::text
        FROM public.t_question_correction_record c
        LEFT JOIN public.t_user u ON u.id = c.user_id
        LEFT JOIN public.t_question q ON q.id = c.question_id
        LEFT JOIN public.t_exam_paper_question_customer_answer a ON a.id = c.customer_answer_id
        WHERE u.id IS NULL OR q.id IS NULL OR a.id IS NULL;
    """
    output = run_sql(config, query)
    values: dict[str, str] = {}
    for line in output.splitlines():
        parts = line.split("|")
        if len(parts) != 2 or not parts[0] or not parts[1] or parts[0] in values:
            raise SafeFailure("sql_result_invalid")
        values[parts[0]] = parts[1]
    if set(values) != {"flyway_version", *TABLES, "orphan_answer_rows", "orphan_correction_rows"}:
        raise SafeFailure("sql_result_invalid")
    if values["flyway_version"] != upstream.flyway_version:
        raise SafeFailure("sql_flyway_mismatch")
    for table in TABLES:
        if values[table] != str(upstream.table_rows[table]):
            raise SafeFailure("sql_row_count_mismatch")
    if values["orphan_answer_rows"] != "0" or values["orphan_correction_rows"] != "0":
        raise SafeFailure("sql_orphans_detected")


def fetch_public(config: Config, path: str) -> bytes:
    request = urllib.request.Request(
        config.fly_base_url + path,
        method="GET",
        headers={"Accept": "application/json,text/html", "Cache-Control": "no-cache"},
    )
    try:
        with urllib.request.urlopen(request, timeout=config.api_timeout_seconds) as response:
            if response.status != 200:
                raise SafeFailure("fly_validation_failed")
            return response.read(2 * 1024 * 1024)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as exc:
        raise SafeFailure("fly_validation_failed") from exc


def validate_fly(config: Config) -> None:
    try:
        health = json.loads(fetch_public(config, "/api/health").decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise SafeFailure("fly_validation_failed") from exc
    if (
        not isinstance(health, dict)
        or health.get("status") != "UP"
        or not isinstance(health.get("database"), dict)
        or health["database"].get("status") != "UP"
    ):
        raise SafeFailure("fly_validation_failed")
    for path in ("/student/index.html", "/admin/index.html"):
        try:
            page = fetch_public(config, path).decode("utf-8")
        except UnicodeError as exc:
            raise SafeFailure("fly_validation_failed") from exc
        if 'type="module"' not in page:
            raise SafeFailure("fly_validation_failed")


def wait_operations(config: Config, api: NeonApi, operation_ids: list[str]) -> None:
    deadline = time.monotonic() + config.operation_timeout_seconds
    while True:
        all_finished = True
        for operation_id in operation_ids:
            operation = api.get_operation(operation_id)
            if operation.get("id") != operation_id:
                raise SafeFailure("operation_identity_invalid")
            status = operation.get("status")
            if status == "finished":
                continue
            if status in TERMINAL_OPERATION_FAILURES:
                raise SafeFailure("operation_terminal_failure")
            if status not in WAITING_OPERATION_STATUSES:
                raise SafeFailure("operation_status_invalid")
            all_finished = False
        if all_finished:
            return
        if time.monotonic() >= deadline:
            raise SafeFailure("operation_timeout")
        time.sleep(config.operation_poll_seconds)


def prepared_state(
    upstream: UpstreamSuccess,
    run_id: str,
    preserve_name: str | None,
    source_id: str,
    target_id: str,
    source_endpoint_digest: str,
    endpoint_digest: str,
) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "status": "prepared",
        "run_id": run_id,
        "prepared_at_utc": utc_text(),
        "generation": upstream.generation,
        "source_backup_time_utc": upstream.source_backup_time_utc,
        "source_sha256": upstream.source_sha256,
        "source_branch_id": source_id,
        "source_endpoint_id": upstream.target_endpoint_id,
        "pre_reset_source_endpoint_fingerprint": source_endpoint_digest,
        "pre_reset_test_branch_id": target_id,
        "pre_reset_endpoint_fingerprint": endpoint_digest,
        "preserve_under_name": preserve_name,
        "restore_response_received": False,
        "candidate_test_branch_id": None,
        "operation_ids": [],
    }


def mark_ambiguous(config: Config, state: dict[str, Any], code: str) -> None:
    updated = dict(state)
    updated["status"] = "ambiguous"
    updated["ambiguous_at_utc"] = utc_text()
    updated["failure_code"] = code
    atomic_write_json(config.reset_state_file, updated)


def acquire_lock(config: Config):
    config.lock_file.parent.mkdir(parents=True, exist_ok=True)
    lock_stream = config.lock_file.open("a+")
    try:
        fcntl.flock(lock_stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as exc:
        lock_stream.close()
        raise SafeFailure("shared_lock_busy") from exc
    return lock_stream


def run(preflight: bool, preserve_current: bool) -> int:
    config = Config.from_environment()
    upstream = load_upstream_success(config)
    existing_state = load_reset_state(config)
    if existing_state and existing_state.get("status") in {"prepared", "ambiguous"}:
        raise SafeFailure("unresolved_reset_state")
    if (
        not preflight
        and existing_state
        and existing_state.get("status") == "success"
        and existing_state.get("generation") == upstream.generation
    ):
        log("reset_noop", phase="already_consumed")
        return 0

    api = NeonApi(config)
    branches = api.list_branches()
    if preserve_current and any(
        isinstance(branch.get("name"), str)
        and branch["name"].startswith(config.preserve_prefix)
        for branch in branches
    ):
        raise SafeFailure("preserve_branch_exists")
    source, target = validate_topology(config, branches)
    source_endpoints = api.list_endpoints(source["id"])
    pre_source_endpoint_digest = source_endpoint_fingerprint(
        upstream.target_endpoint_id, source_endpoints
    )
    endpoints = api.list_endpoints(target["id"])
    pre_endpoint_digest = endpoint_fingerprint(config, endpoints)

    retry_validation(config, lambda: validate_sql_identity(config), "sql_preflight_failed")
    retry_validation(config, lambda: validate_fly(config), "fly_preflight_failed")
    if preflight:
        log("preflight_passed")
        return 0

    run_id = secrets.token_hex(8)
    preserve_name = None
    if preserve_current:
        preserve_name = (
            f"{config.preserve_prefix}{utc_now().strftime('%Y%m%dT%H%M%SZ')}-{run_id[:8]}"
        )
    if preserve_name is not None and len(preserve_name) > 256:
        raise SafeFailure("preserve_name_invalid")
    state = prepared_state(
        upstream,
        run_id,
        preserve_name,
        source["id"],
        target["id"],
        pre_source_endpoint_digest,
        pre_endpoint_digest,
    )
    atomic_write_json(config.reset_state_file, state)
    log("reset_prepared")

    try:
        response = api.restore(target["id"], source["id"], preserve_name)
    except AmbiguousPost as exc:
        mark_ambiguous(config, state, exc.code)
        raise

    candidate = response.get("branch")
    operations = response.get("operations")
    if not isinstance(candidate, dict) or not isinstance(candidate.get("id"), str):
        mark_ambiguous(config, state, "restore_response_ambiguous")
        raise AmbiguousPost("restore_response_ambiguous")
    if not isinstance(operations, list) or any(not isinstance(item, dict) for item in operations):
        mark_ambiguous(config, state, "restore_response_ambiguous")
        raise AmbiguousPost("restore_response_ambiguous")
    operation_ids: list[str] = []
    for operation in operations:
        operation_id = operation.get("id")
        if not isinstance(operation_id, str) or not re.fullmatch(
            r"[0-9a-fA-F-]{16,64}", operation_id
        ):
            mark_ambiguous(config, state, "restore_response_ambiguous")
            raise AmbiguousPost("restore_response_ambiguous")
        if operation_id in operation_ids:
            mark_ambiguous(config, state, "restore_response_ambiguous")
            raise AmbiguousPost("restore_response_ambiguous")
        operation_ids.append(operation_id)
    state["restore_response_received"] = True
    state["candidate_test_branch_id"] = candidate["id"]
    state["operation_ids"] = operation_ids
    state["response_recorded_at_utc"] = utc_text()
    atomic_write_json(config.reset_state_file, state)
    log("restore_response_recorded", count=len(operation_ids))

    wait_operations(config, api, operation_ids)
    post_branches = api.list_branches()
    post_source, post_target = validate_topology(config, post_branches)
    if post_source["id"] != source["id"] or post_target["id"] != candidate["id"]:
        raise SafeFailure("post_restore_branch_identity_invalid")
    post_source_endpoints = api.list_endpoints(post_source["id"])
    post_source_endpoint_digest = source_endpoint_fingerprint(
        upstream.target_endpoint_id, post_source_endpoints
    )
    if post_source_endpoint_digest != pre_source_endpoint_digest:
        raise SafeFailure("post_restore_source_endpoint_changed")
    post_endpoints = api.list_endpoints(post_target["id"])
    post_endpoint_digest = endpoint_fingerprint(config, post_endpoints)
    if post_endpoint_digest != pre_endpoint_digest:
        raise SafeFailure("post_restore_endpoint_changed")

    retry_validation(config, lambda: validate_sql_identity(config), "sql_post_restore_failed")
    retry_validation(
        config,
        lambda: validate_sql_data(config, upstream),
        "sql_post_restore_failed",
    )
    retry_validation(config, lambda: validate_fly(config), "fly_post_restore_failed")

    success = {
        "schema_version": 1,
        "status": "success",
        "completed_at_utc": utc_text(),
        "generation": upstream.generation,
        "source_backup_time_utc": upstream.source_backup_time_utc,
        "source_sha256": upstream.source_sha256,
        "source_branch_id": post_source["id"],
        "test_branch_id": post_target["id"],
        "test_parent_id": post_target.get("parent_id"),
        "endpoint_fingerprint": post_endpoint_digest,
        "preserve_under_name": preserve_name,
        "operation_count": len(operation_ids),
        "result": "passed",
    }
    atomic_write_json(config.reset_state_file, success)
    log("reset_passed", count=len(operation_ids))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Reset Neon test from production safely.")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--preflight",
        action="store_true",
        help="Run local, GET, SQL read-only, and Fly read-only checks without POST.",
    )
    mode.add_argument(
        "--preserve-current",
        action="store_true",
        help="Preserve the current test branch under a unique name before reset.",
    )
    arguments = parser.parse_args()
    lock_stream = None
    try:
        config = Config.from_environment()
        lock_stream = acquire_lock(config)
        return run(arguments.preflight, arguments.preserve_current)
    except SafeFailure as exc:
        log("reset_failed", phase=exc.code)
        return 1
    except Exception:
        log("reset_failed", phase="unexpected_internal_error")
        return 1
    finally:
        if lock_stream is not None:
            with contextlib.suppress(OSError):
                fcntl.flock(lock_stream.fileno(), fcntl.LOCK_UN)
            lock_stream.close()


if __name__ == "__main__":
    sys.exit(main())
