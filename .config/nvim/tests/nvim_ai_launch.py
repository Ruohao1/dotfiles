"""Security and behavior tests for the native AI Bubblewrap launcher."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
import pathlib
import shutil
import signal
import socket
import stat
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
LAUNCHER_PATH = ROOT / "scripts" / "nvim-ai-launch.py"
SPEC = importlib.util.spec_from_file_location("nvim_ai_launch", LAUNCHER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load launcher from {LAUNCHER_PATH}")
launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launcher)

VERSION = "1.18.18"
IDENTITY_KEY = "a" * 32
PROFILE_TOKEN = "b" * 32
LAUNCH_TOKEN = "c" * 32
CONTROL_TOKEN = "d" * 32
PASSWORD = "e" * 32
POLICY_JSON = (
    '{"bash":"ask","doom_loop":"ask","external_directory":"ask",'
    '"skill":"deny","task":"deny","webfetch":"ask","websearch":"ask"}'
)
CONFIG_JSON = (
    '{"$schema":"https://opencode.ai/config.json","autoupdate":false,'
    '"permission":{"bash":"ask","doom_loop":"ask",'
    '"external_directory":"ask","skill":"deny","task":"deny",'
    '"webfetch":"ask","websearch":"ask"},"agent":{'
    '"general":{"disable":true},"explore":{"disable":true},'
    '"compaction":{"permission":{"*":"deny"}},'
    '"summary":{"permission":{"*":"deny"}},'
    '"title":{"permission":{"*":"deny"}}}}'
)
BOOTSTRAP_GITIGNORE = (
    b"node_modules\npackage.json\npackage-lock.json\nbun.lock\n.gitignore"
)
BOOTSTRAP_GITIGNORE_SHA256 = (
    "663a068e76d264d0bc6740f5450b6c4193c7b41ecf5e0dc222485b8a17404d95"
)


def compact_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def fingerprint_for(root: str, config: bytes, instructions: bytes) -> str:
    components = (
        b"1",
        VERSION.encode("utf-8"),
        IDENTITY_KEY.encode("ascii"),
        root.encode("utf-8"),
        config,
        instructions,
    )
    digest = hashlib.sha256()
    for component in components:
        digest.update(len(component).to_bytes(8, "big"))
        digest.update(component)
    return digest.hexdigest()


def fixture_metadata(mode: int = 0o600, uid: int | None = None) -> dict[str, object]:
    return {
        "is_symlink": False,
        "is_regular": True,
        "mode": mode,
        "uid": os.getuid() if uid is None else uid,
        "size": 1024,
    }


def windows(values: list[str], width: int) -> list[list[str]]:
    return [
        values[index : index + width]
        for index in range(0, len(values) - width + 1)
    ]


class StatProxy:
    def __init__(self, source: os.stat_result, **changes: int) -> None:
        self._source = source
        self._changes = changes

    def __getattr__(self, name: str) -> object:
        if name in self._changes:
            return self._changes[name]
        return getattr(self._source, name)


class Fixture:
    def __init__(self, case: unittest.TestCase) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="nvim-ai-launch-")
        case.addCleanup(temporary.cleanup)
        self.base = pathlib.Path(temporary.name).resolve()
        os.chmod(self.base, 0o700)

        self.home = self.private_dir(self.base / "home")
        self.home_opencode = self.private_dir(self.home / ".opencode")
        environment = mock.patch.dict(os.environ, {"HOME": str(self.home)})
        environment.start()
        case.addCleanup(environment.stop)
        self.project = self.private_dir(self.base / "project")
        self.git_common = self.private_dir(self.base / "git")
        self.git_dir = self.private_dir(self.git_common / "worktrees" / "repo")
        self.git_entry = self.private_file(
            self.project / ".git", ("gitdir: " + str(self.git_dir) + "\n").encode()
        )
        self.runtime_root = self.private_dir(self.base / "runtime")
        self.context_dir = self.private_dir(self.runtime_root / "context")
        self.state_root = self.private_dir(self.base / "state")
        self.backends_parent = self.private_dir(self.state_root / "backends")
        self.backend_state = self.private_dir(self.backends_parent / "opencode")
        self.private_dir(self.backend_state / "xdg-cache")
        self.private_dir(self.backend_state / "xdg-data")
        self.private_dir(self.backend_state / "xdg-state")
        self.event_file = self.private_file(
            self.backend_state / "events.ndjson", b""
        )
        self.control_socket = self.runtime_root / "control.sock"
        self.control_listener = socket.socket(socket.AF_UNIX)
        self.control_listener.bind(str(self.control_socket))
        case.addCleanup(self.control_listener.close)

        self.python = pathlib.Path(os.path.realpath(shutil.which("python3") or ""))
        self.bwrap = pathlib.Path(os.path.realpath(shutil.which("bwrap") or "/bin/true"))
        self.shell = pathlib.Path(os.path.realpath("/bin/sh"))
        self.git = pathlib.Path(os.path.realpath(shutil.which("git") or "/bin/true"))
        self.profile_helper = pathlib.Path(
            os.path.realpath(ROOT / "scripts" / "nvim-ai-opencode-profile.py")
        )
        self.helper = pathlib.Path(os.path.realpath("/bin/true"))

        self.instructions = b"# Repository instructions\n\nfixture\n\n"
        self.auth = {
            "anthropic": {"type": "api", "key": "credential-canary"},
            "openai": {
                "type": "oauth",
                "refresh": "refresh-canary",
                "access": "access-canary",
                "expires": 4102444800000,
                "accountId": "acct-test",
            },
        }
        self.profile_root = self.build_profile()

    @staticmethod
    def private_dir(path: pathlib.Path) -> pathlib.Path:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(path, 0o700)
        return path

    @staticmethod
    def private_file(path: pathlib.Path, payload: bytes) -> pathlib.Path:
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        path.write_bytes(payload)
        os.chmod(path, 0o600)
        return path

    def build_profile(self) -> pathlib.Path:
        profile = self.private_dir(
            self.backend_state / "profiles" / PROFILE_TOKEN
        )
        credentials = self.private_dir(profile / "credentials")
        self.private_file(
            credentials / "auth.json",
            (compact_json(self.auth) + "\n").encode("utf-8"),
        )
        self.private_dir(profile / "empty-home-opencode")
        opencode = self.private_dir(profile / "xdg-config" / "opencode")
        self.private_file(opencode / ".gitignore", BOOTSTRAP_GITIGNORE)
        self.private_file(opencode / "AGENTS.md", self.instructions)
        config = CONFIG_JSON.encode("utf-8")
        self.private_file(opencode / "opencode.json", config)
        fingerprint = fingerprint_for(str(self.project), config, self.instructions)
        profile_manifest = {
            "schema": 1,
            "version": VERSION,
            "identity_key": IDENTITY_KEY,
            "root": str(self.project),
            "fingerprint": fingerprint,
            "config_sha256": hashlib.sha256(config).hexdigest(),
            "instructions_sha256": hashlib.sha256(self.instructions).hexdigest(),
        }
        self.private_file(
            profile / "manifest.json",
            (compact_json(profile_manifest) + "\n").encode("utf-8"),
        )
        return profile

    @property
    def fingerprint(self) -> str:
        return fingerprint_for(
            str(self.project), CONFIG_JSON.encode("utf-8"), self.instructions
        )

    def managed_profile(self) -> dict[str, object]:
        return {
            "schema": 1,
            "version": VERSION,
            "profile_root": str(self.profile_root),
            "fingerprint": self.fingerprint,
            "config_source": str(self.profile_root / "xdg-config"),
            "auth_source": str(self.profile_root / "credentials" / "auth.json"),
            "home_mask_source": str(self.profile_root / "empty-home-opencode"),
        }

    def managed_environment(self) -> dict[str, str]:
        return {
            "OPENCODE_DISABLE_AUTOUPDATE": "true",
            "OPENCODE_DISABLE_CLAUDE_CODE": "true",
            "OPENCODE_DISABLE_EXTERNAL_SKILLS": "true",
            "OPENCODE_DISABLE_LSP_DOWNLOAD": "true",
            "OPENCODE_DISABLE_PROJECT_CONFIG": "true",
            "OPENCODE_PERMISSION": POLICY_JSON,
            "OPENCODE_PURE": "true",
            "OPENCODE_SERVER_PASSWORD": PASSWORD,
            "OPENCODE_SERVER_USERNAME": "opencode",
            "XDG_CACHE_HOME": str(self.backend_state / "xdg-cache"),
            "XDG_CONFIG_HOME": str(self.backend_state / "xdg-config"),
            "XDG_DATA_HOME": str(self.backend_state / "xdg-data"),
            "XDG_STATE_HOME": str(self.backend_state / "xdg-state"),
        }

    def manifest(
        self, *, writable: bool = False, grants: list[str] | None = None
    ) -> dict[str, object]:
        return {
            "schema": 1,
            "token": LAUNCH_TOKEN,
            "identity_key": IDENTITY_KEY,
            "root": str(self.project),
            "git_dir": str(self.git_dir),
            "git_common_dir": str(self.git_common),
            "git_entry": str(self.git_entry),
            "writable": writable,
            "grants": list(grants or []),
            "review_id": "review_0123456789abcdef" if writable else None,
            "runtime_root": str(self.runtime_root),
            "state_root": str(self.state_root),
            "context_dir": str(self.context_dir),
            "backend_state_dir": str(self.backend_state),
            "control_socket": str(self.control_socket),
            "control_token": CONTROL_TOKEN,
            "control_helper": str(self.helper),
            "event_helper": str(self.helper),
            "profile_helper": str(self.profile_helper),
            "launcher": str(LAUNCHER_PATH.resolve()),
            "review_helper": str(self.helper),
            "event_file": str(self.event_file),
            "tmux_socket": None,
            "python": str(self.python),
            "bwrap": str(self.bwrap),
            "host_tools": [str(self.git)],
            "shell": str(self.shell),
            "launch": {
                "kind": "server_attach",
                "backend": "opencode",
                "argv": None,
                "server_argv": [
                    str(self.helper),
                    "--pure",
                    "serve",
                    "--hostname",
                    "127.0.0.1",
                    "--port",
                    "4096",
                ],
                "attach_argv": [
                    str(self.helper),
                    "--pure",
                    "attach",
                    "http://127.0.0.1:4096",
                    "--dir",
                    str(self.project),
                    "--session",
                    "ses_test",
                ],
                "env": self.managed_environment(),
                "session": "ses_test",
                "capabilities": {
                    "approval": True,
                    "busy": True,
                    "completion": True,
                    "exact_session": True,
                },
                "read_only_inputs": [],
                "protected_paths": [str(self.profile_root), str(self.helper)],
                "event_url": "http://127.0.0.1:4096/event",
                "event_file": str(self.event_file),
                "managed_profile": self.managed_profile(),
            },
        }

    def write_launch_manifest(self, manifest: dict[str, object]) -> pathlib.Path:
        path = self.private_file(
            self.runtime_root / (LAUNCH_TOKEN + ".json"),
            (compact_json(manifest) + "\n").encode("utf-8"),
        )
        return path

    def direct_manifest(self) -> dict[str, object]:
        manifest = self.manifest()
        launch = manifest["launch"]
        assert isinstance(launch, dict)
        launch.update(
            {
                "kind": "direct",
                "backend": "codex",
                "argv": [str(self.helper), "-C", str(self.project)],
                "server_argv": None,
                "attach_argv": None,
                "env": {"CODEX_HOME": str(self.backend_state)},
                "session": "last",
                "capabilities": {
                    "approval": False,
                    "busy": False,
                    "completion": False,
                    "exact_session": False,
                },
                "read_only_inputs": [],
                "protected_paths": [str(self.helper)],
                "event_url": None,
                "event_file": None,
                "managed_profile": None,
            }
        )
        return manifest


class ManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture(self)

    def test_exact_manifest_and_managed_profile_are_valid(self) -> None:
        manifest = self.fixture.manifest()
        self.assertIs(launcher.validate_manifest(manifest, fixture_metadata()), manifest)
        validated = launcher.validate_managed_profile(
            manifest, {"HOME": str(self.fixture.home)}
        )
        self.assertEqual(validated["fingerprint"], self.fixture.fingerprint)
        self.assertNotIn("credential-canary", compact_json(validated))

    def test_manifest_rejects_unknown_keys_and_unsafe_metadata(self) -> None:
        manifest = self.fixture.manifest()
        manifest["unknown"] = True
        with self.assertRaisesRegex(ValueError, "manifest keys"):
            launcher.validate_manifest(manifest, fixture_metadata())
        with self.assertRaisesRegex(ValueError, "0600"):
            launcher.validate_manifest(
                self.fixture.manifest(), fixture_metadata(mode=0o644)
            )
        with self.assertRaisesRegex(ValueError, "owner"):
            launcher.validate_manifest(
                self.fixture.manifest(), fixture_metadata(uid=os.getuid() + 1)
            )
        metadata = fixture_metadata()
        metadata["is_symlink"] = True
        with self.assertRaisesRegex(ValueError, "symlink"):
            launcher.validate_manifest(self.fixture.manifest(), metadata)
        metadata = fixture_metadata()
        metadata["size"] = 1024 * 1024 + 1
        with self.assertRaisesRegex(ValueError, "large"):
            launcher.validate_manifest(self.fixture.manifest(), metadata)

    def test_hostile_json_container_types_are_normalized_to_validation_errors(self) -> None:
        for field, mutation in (
            ("grants", lambda manifest: manifest.update({"grants": [{}]})),
            (
                "host tools",
                lambda manifest: manifest.update({"host_tools": [{}]}),
            ),
            (
                "protected paths",
                lambda manifest: manifest["launch"].update(
                    {"protected_paths": [{}]}
                ),
            ),
        ):
            with self.subTest(field=field):
                manifest = self.fixture.manifest()
                mutation(manifest)
                with self.assertRaises(ValueError):
                    launcher.validate_manifest(manifest, fixture_metadata())

        path = self.fixture.write_launch_manifest(self.fixture.manifest())
        with mock.patch.object(
            launcher,
            "validate_manifest",
            side_effect=TypeError("unhashable hostile shape"),
        ):
            with self.assertRaisesRegex(ValueError, "validation"):
                launcher.consume_manifest(str(path))
        self.assertTrue(path.exists())

    def test_direct_backends_reject_profiles_and_opencode_requires_one(self) -> None:
        for backend in ("codex", "claude"):
            with self.subTest(backend=backend):
                manifest = self.fixture.manifest()
                launch = manifest["launch"]
                assert isinstance(launch, dict)
                launch["kind"] = "direct"
                launch["backend"] = backend
                launch["argv"] = [str(self.fixture.helper)]
                launch["server_argv"] = None
                launch["attach_argv"] = None
                with self.assertRaisesRegex(ValueError, "managed profile"):
                    launcher.validate_manifest(manifest, fixture_metadata())

        manifest = self.fixture.manifest()
        launch = manifest["launch"]
        assert isinstance(launch, dict)
        launch["managed_profile"] = None
        with self.assertRaisesRegex(ValueError, "managed profile"):
            launcher.validate_manifest(manifest, fixture_metadata())

    def test_profile_public_shape_version_fingerprint_and_paths_are_exact(self) -> None:
        mutations = {
            "extra field": lambda value: value.update({"auth": "authenticated"}),
            "version": lambda value: value.update({"version": "1.18.19"}),
            "fingerprint": lambda value: value.update({"fingerprint": "C" * 64}),
            "root outside backend state": lambda value: value.update(
                {"profile_root": str(self.fixture.base / "outside" / PROFILE_TOKEN)}
            ),
            "config outside profile": lambda value: value.update(
                {"config_source": str(self.fixture.backend_state / "xdg-config")}
            ),
            "auth outside profile": lambda value: value.update(
                {"auth_source": str(self.fixture.backend_state / "auth.json")}
            ),
            "mask outside profile": lambda value: value.update(
                {"home_mask_source": str(self.fixture.backend_state / "empty")}
            ),
        }
        for label, mutate in mutations.items():
            with self.subTest(label=label):
                manifest = self.fixture.manifest()
                launch = manifest["launch"]
                assert isinstance(launch, dict)
                profile = launch["managed_profile"]
                assert isinstance(profile, dict)
                mutate(profile)
                with self.assertRaisesRegex(ValueError, "managed profile"):
                    launcher.validate_manifest(manifest, fixture_metadata())

    def test_writable_requires_review_and_grants_are_sorted_unique_directories(self) -> None:
        grant = self.fixture.private_dir(self.fixture.base / "grant")
        manifest = self.fixture.manifest(writable=True, grants=[str(grant)])
        launcher.validate_manifest(manifest, fixture_metadata())
        manifest["review_id"] = None
        with self.assertRaisesRegex(ValueError, "review"):
            launcher.validate_manifest(manifest, fixture_metadata())

        first = self.fixture.private_dir(self.fixture.base / "z-grant")
        second = self.fixture.private_dir(self.fixture.base / "a-grant")
        for grants in (
            [str(first), str(second)],
            [str(first), str(first)],
            ["/"],
            [str(first / "../escape")],
        ):
            with self.subTest(grants=grants):
                changed = self.fixture.manifest(writable=True, grants=grants)
                with self.assertRaisesRegex(ValueError, "grant"):
                    launcher.validate_manifest(changed, fixture_metadata())

    def test_manifest_is_descriptor_read_and_unlinked_only_after_validation(self) -> None:
        path = self.fixture.write_launch_manifest(self.fixture.manifest())
        consumed = launcher.consume_manifest(str(path))
        self.assertEqual(consumed["token"], LAUNCH_TOKEN)
        self.assertFalse(path.exists())

        bad = self.fixture.write_launch_manifest(self.fixture.manifest())
        os.chmod(bad, 0o644)
        with self.assertRaisesRegex(ValueError, "0600"):
            launcher.consume_manifest(str(bad))
        self.assertTrue(bad.exists())

    def test_consume_rolls_back_first_launch_destinations_after_profile_failure(self) -> None:
        for leaf in ("xdg-cache", "xdg-data", "xdg-state"):
            (self.fixture.backend_state / leaf).rmdir()
        auth = self.fixture.profile_root / "credentials/auth.json"
        auth.write_bytes(b"{}\n")
        os.chmod(auth, 0o600)
        path = self.fixture.write_launch_manifest(self.fixture.manifest())
        with self.assertRaisesRegex(ValueError, "authentication"):
            launcher.consume_manifest(str(path))
        self.assertTrue(path.exists())
        for leaf in ("xdg-cache", "xdg-config", "xdg-data", "xdg-state"):
            self.assertFalse((self.fixture.backend_state / leaf).exists())

    def test_consume_rolls_back_first_launch_destinations_after_unlink_failure(self) -> None:
        for leaf in ("xdg-cache", "xdg-data", "xdg-state"):
            (self.fixture.backend_state / leaf).rmdir()
        path = self.fixture.write_launch_manifest(self.fixture.manifest())
        real_unlink = launcher.os.unlink

        def fail_manifest_unlink(target, *args, **kwargs):
            if target == str(path):
                raise PermissionError("manifest unlink refused")
            return real_unlink(target, *args, **kwargs)

        with mock.patch.object(launcher.os, "unlink", side_effect=fail_manifest_unlink):
            with self.assertRaisesRegex(ValueError, "consumed"):
                launcher.consume_manifest(str(path))
        self.assertTrue(path.exists())
        for leaf in ("xdg-cache", "xdg-config", "xdg-data", "xdg-state"):
            self.assertFalse((self.fixture.backend_state / leaf).exists())


class ManagedProfileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture(self)

    def validate(self) -> dict[str, object]:
        return launcher.validate_managed_profile(
            self.fixture.manifest(), {"HOME": str(self.fixture.home)}
        )

    def test_exact_tree_modes_bootstrap_hash_config_hash_and_credentials(self) -> None:
        validated = self.validate()
        self.assertEqual(validated["fingerprint"], self.fixture.fingerprint)
        self.assertEqual(
            hashlib.sha256(BOOTSTRAP_GITIGNORE).hexdigest(),
            BOOTSTRAP_GITIGNORE_SHA256,
        )

    def test_symlink_component_wrong_mode_wrong_owner_and_extra_entry_fail(self) -> None:
        profile = self.fixture.profile_root
        real_credentials = profile / "credentials-real"
        (profile / "credentials").rename(real_credentials)
        (profile / "credentials").symlink_to(real_credentials, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "managed"):
            self.validate()

        (profile / "credentials").unlink()
        real_credentials.rename(profile / "credentials")
        os.chmod(profile / "credentials", 0o755)
        with self.assertRaisesRegex(ValueError, "managed"):
            self.validate()
        os.chmod(profile / "credentials", 0o700)

        self.fixture.private_file(profile / "extra", b"x")
        with self.assertRaisesRegex(ValueError, "profile"):
            self.validate()
        (profile / "extra").unlink()

        with mock.patch.object(launcher, "_current_uid", return_value=os.getuid() + 1):
            with self.assertRaisesRegex(ValueError, "owner"):
                self.validate()

    def test_nonempty_home_mask_and_isolated_account_state_fail(self) -> None:
        marker = self.fixture.private_file(
            self.fixture.profile_root / "empty-home-opencode" / "marker", b"x"
        )
        with self.assertRaisesRegex(ValueError, "home mask"):
            self.validate()
        marker.unlink()

        data = self.fixture.backend_state / "xdg-data" / "opencode"
        data.mkdir(mode=0o700)
        for name in ("account.json", "mcp-auth.json"):
            with self.subTest(name=name):
                path = self.fixture.private_file(data / name, b"{}\n")
                with self.assertRaisesRegex(ValueError, "isolated OpenCode state"):
                    self.validate()
                path.unlink()

    def test_changed_files_hashes_noncanonical_json_and_empty_auth_fail(self) -> None:
        profile = self.fixture.profile_root
        cases = {
            "configuration": profile / "xdg-config/opencode/opencode.json",
            "bootstrap": profile / "xdg-config/opencode/.gitignore",
            "instructions": profile / "xdg-config/opencode/AGENTS.md",
            "manifest": profile / "manifest.json",
            "auth": profile / "credentials/auth.json",
        }
        originals = {name: path.read_bytes() for name, path in cases.items()}
        mutations = {
            "configuration": CONFIG_JSON.encode("utf-8") + b" ",
            "bootstrap": BOOTSTRAP_GITIGNORE + b"\n",
            "instructions": self.fixture.instructions + b"changed",
            "manifest": originals["manifest"].replace(b'"config_sha256":"', b'"config_sha256":"0'),
            "auth": b"{}\n",
        }
        for name, path in cases.items():
            with self.subTest(name=name):
                path.write_bytes(mutations[name])
                os.chmod(path, 0o600)
                with self.assertRaises(ValueError) as caught:
                    self.validate()
                self.assertNotIn("credential-canary", str(caught.exception))
                path.write_bytes(originals[name])
                os.chmod(path, 0o600)

    def test_duplicate_auth_key_and_oversized_profile_file_fail_without_secret(self) -> None:
        path = self.fixture.profile_root / "credentials/auth.json"
        path.write_bytes(
            b'{"provider":{"type":"api","key":"secret-one"},'
            b'"provider":{"type":"api","key":"secret-two"}}\n'
        )
        os.chmod(path, 0o600)
        with self.assertRaises(ValueError) as caught:
            self.validate()
        self.assertNotIn("secret-one", str(caught.exception))
        self.assertNotIn("secret-two", str(caught.exception))

        path.write_bytes(b"x" * (1024 * 1024 + 1))
        os.chmod(path, 0o600)
        with self.assertRaisesRegex(ValueError, "large"):
            self.validate()

    def test_authentication_requires_helper_canonical_key_order_without_secret(self) -> None:
        path = self.fixture.profile_root / "credentials/auth.json"
        reversed_providers = {
            "openai": self.fixture.auth["openai"],
            "anthropic": self.fixture.auth["anthropic"],
        }
        reordered_api_record = {
            "anthropic": {"key": "credential-canary", "type": "api"},
            "openai": self.fixture.auth["openai"],
        }
        reordered_metadata = {
            "anthropic": {
                "type": "api",
                "key": "credential-canary",
                "metadata": {
                    "z-key": "metadata-secret-z",
                    "a-key": "metadata-secret-a",
                },
            },
            "openai": self.fixture.auth["openai"],
        }
        for name, value in (
            ("provider order", reversed_providers),
            ("record order", reordered_api_record),
            ("metadata order", reordered_metadata),
        ):
            with self.subTest(name=name):
                path.write_bytes((compact_json(value) + "\n").encode("utf-8"))
                os.chmod(path, 0o600)
                with self.assertRaisesRegex(ValueError, "canonical") as caught:
                    self.validate()
                diagnostic = str(caught.exception)
                self.assertNotIn("credential-canary", diagnostic)
                self.assertNotIn("metadata-secret", diagnostic)

    def test_home_must_be_canonical_owned_and_destination_not_symlink_or_file(self) -> None:
        manifest = self.fixture.manifest()
        with self.assertRaisesRegex(ValueError, "HOME"):
            launcher.validate_managed_profile(
                manifest, {"HOME": str(self.fixture.home / "../home")}
            )

        with mock.patch.object(launcher, "_current_uid", return_value=os.getuid() + 1):
            with self.assertRaisesRegex(ValueError, "HOME"):
                launcher.validate_managed_profile(
                    manifest, {"HOME": str(self.fixture.home)}
                )

        destination = self.fixture.home / ".opencode"
        target = self.fixture.private_dir(self.fixture.base / "host-opencode")
        destination.rmdir()
        destination.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "home OpenCode destination"):
            launcher.validate_managed_profile(
                manifest, {"HOME": str(self.fixture.home)}
            )
        destination.unlink()
        self.fixture.private_file(destination, b"host")
        with self.assertRaisesRegex(ValueError, "home OpenCode destination"):
            launcher.validate_managed_profile(
                manifest, {"HOME": str(self.fixture.home)}
            )

        destination.unlink()
        with self.assertRaisesRegex(ValueError, "home OpenCode destination"):
            launcher.validate_managed_profile(
                manifest, {"HOME": str(self.fixture.home)}
            )

    def test_home_destination_replacement_during_validation_is_rejected(self) -> None:
        destination = str(self.fixture.home_opencode)
        real_lstat = launcher.os.lstat
        calls = 0

        def changing_lstat(path):
            nonlocal calls
            metadata = real_lstat(path)
            if path == destination:
                calls += 1
                if calls >= 2:
                    return StatProxy(metadata, st_ino=metadata.st_ino + 1)
            return metadata

        with mock.patch.object(launcher.os, "lstat", side_effect=changing_lstat):
            with self.assertRaisesRegex(ValueError, "changed"):
                launcher._validate_home({"HOME": str(self.fixture.home)})

    def test_xdg_destination_components_reject_symlinks_modes_and_extra_account_state(self) -> None:
        data = self.fixture.backend_state / "xdg-data"
        real_data = self.fixture.backend_state / "xdg-data-real"
        data.rename(real_data)
        data.symlink_to(real_data, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "XDG|isolated"):
            self.validate()
        data.unlink()
        real_data.rename(data)

        cache = self.fixture.backend_state / "xdg-cache"
        os.chmod(cache, 0o755)
        with self.assertRaisesRegex(ValueError, "XDG|isolated"):
            self.validate()

    def test_managed_mount_preparation_creates_only_exact_private_backend_placeholders(self) -> None:
        config = self.fixture.backend_state / "xdg-config"
        data_home = self.fixture.backend_state / "xdg-data"
        opencode = data_home / "opencode"
        auth = opencode / "auth.json"
        self.assertFalse(config.exists())
        self.assertFalse(opencode.exists())
        created = launcher.prepare_mount_destinations(
            self.fixture.manifest(), {"HOME": str(self.fixture.home)}
        )
        self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(opencode.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(auth.stat().st_mode), 0o600)
        self.assertEqual(auth.read_bytes(), b"")
        self.assertTrue(self.fixture.home_opencode.is_dir())
        self.assertFalse((self.fixture.home / ".opencode/hostile").exists())
        self.assertEqual(
            [item["path"] for item in created],
            [str(config), str(opencode), str(auth)],
        )

    def test_first_launch_preparation_creates_every_private_xdg_destination(self) -> None:
        for leaf in ("xdg-cache", "xdg-data", "xdg-state"):
            (self.fixture.backend_state / leaf).rmdir()
        created = launcher.prepare_mount_destinations(
            self.fixture.manifest(), {"HOME": str(self.fixture.home)}
        )
        expected_directories = {
            self.fixture.backend_state / "xdg-cache",
            self.fixture.backend_state / "xdg-config",
            self.fixture.backend_state / "xdg-data",
            self.fixture.backend_state / "xdg-data/opencode",
            self.fixture.backend_state / "xdg-state",
        }
        for directory in expected_directories:
            self.assertTrue(directory.is_dir())
            self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
        auth = self.fixture.backend_state / "xdg-data/opencode/auth.json"
        self.assertEqual(auth.read_bytes(), b"")
        self.assertEqual(stat.S_IMODE(auth.stat().st_mode), 0o600)
        launcher.validate_managed_profile(
            self.fixture.manifest(), {"HOME": str(self.fixture.home)}
        )
        self.assertEqual(
            {item["path"] for item in created},
            {str(path) for path in expected_directories} | {str(auth)},
        )
        launcher.rollback_mount_destinations(created)
        for directory in expected_directories:
            self.assertFalse(directory.exists())

    def test_managed_mount_preparation_refuses_hostile_existing_auth_destination(self) -> None:
        opencode = self.fixture.private_dir(
            self.fixture.backend_state / "xdg-data" / "opencode"
        )
        target = self.fixture.private_file(self.fixture.base / "hostile-auth", b"x")
        (opencode / "auth.json").symlink_to(target)
        with self.assertRaisesRegex(ValueError, "destination|authentication"):
            launcher.prepare_mount_destinations(
                self.fixture.manifest(), {"HOME": str(self.fixture.home)}
            )
        self.assertTrue((opencode / "auth.json").is_symlink())
        self.assertEqual(target.read_bytes(), b"x")


class EnvironmentAndMountTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture(self)

    def test_environment_is_exact_allowlisted_and_secret_parent_is_dropped(self) -> None:
        manifest = self.fixture.manifest()
        parent = {
            "PATH": "/usr/bin",
            "HOME": str(self.fixture.home),
            "USER": "tester",
            "TERM": "xterm-256color",
            "HTTPS_PROXY": "http://proxy.invalid",
            "SECRET": "no",
        }
        environment = launcher.build_environment(manifest, parent)
        self.assertEqual(environment["PATH"], "/usr/bin")
        self.assertEqual(environment["HOME"], str(self.fixture.home))
        self.assertEqual(environment["TERM"], "xterm-256color")
        self.assertEqual(environment["OPENCODE_SERVER_PASSWORD"], PASSWORD)
        self.assertNotIn("SECRET", environment)
        self.assertNotIn("TMUX", environment)

    def test_every_managed_environment_mutation_and_unknown_opencode_key_fails(self) -> None:
        baseline = self.fixture.manifest()
        launch = baseline["launch"]
        assert isinstance(launch, dict)
        environment = launch["env"]
        assert isinstance(environment, dict)
        for name, value in list(environment.items()):
            with self.subTest(name=name):
                manifest = copy.deepcopy(baseline)
                changed_launch = manifest["launch"]
                assert isinstance(changed_launch, dict)
                changed = changed_launch["env"]
                assert isinstance(changed, dict)
                changed[name] = str(value) + "changed"
                with self.assertRaisesRegex(ValueError, "OpenCode environment"):
                    launcher.build_environment(
                        manifest, {"HOME": str(self.fixture.home)}
                    )

        manifest = self.fixture.manifest()
        changed_launch = manifest["launch"]
        assert isinstance(changed_launch, dict)
        changed = changed_launch["env"]
        assert isinstance(changed, dict)
        changed["OPENCODE_HOSTILE"] = "true"
        with self.assertRaisesRegex(ValueError, "adapter environment"):
            launcher.build_environment(manifest, {"HOME": str(self.fixture.home)})

        for inherited in (
            {"HOME": str(self.fixture.home), "OPENCODE_HOSTILE": "true"},
            {"HOME": str(self.fixture.home), "OPENCODE_PURE": "false"},
        ):
            with self.subTest(inherited=inherited):
                with self.assertRaisesRegex(ValueError, "inherited OpenCode"):
                    launcher.build_environment(self.fixture.manifest(), inherited)

    def test_control_and_size_in_parent_or_adapter_environment_fail(self) -> None:
        with self.assertRaisesRegex(ValueError, "environment"):
            launcher.build_environment(
                self.fixture.manifest(),
                {"HOME": str(self.fixture.home), "LANG": "bad\nvalue"},
            )
        manifest = self.fixture.manifest()
        launch = manifest["launch"]
        assert isinstance(launch, dict)
        environment = launch["env"]
        assert isinstance(environment, dict)
        environment["OPENCODE_SERVER_PASSWORD"] = "x" * 8193
        with self.assertRaisesRegex(ValueError, "environment"):
            launcher.build_environment(manifest, {"HOME": str(self.fixture.home)})

    def test_claude_additional_settings_must_be_a_canonical_backend_descendant(self) -> None:
        manifest = self.fixture.direct_manifest()
        launch = manifest["launch"]
        assert isinstance(launch, dict)
        launch["backend"] = "claude"
        launch["env"] = {
            "CLAUDE_CONFIG_DIR": str(self.fixture.backend_state),
            "CLAUDE_CODE_ADDITIONAL_SETTINGS": str(
                self.fixture.backend_state / ".." / "escape.json"
            ),
        }
        with self.assertRaisesRegex(ValueError, "Claude settings"):
            launcher.build_environment(manifest, {"HOME": str(self.fixture.home)})

    def test_read_only_mount_order_masks_root_git_tmux_and_managed_profile(self) -> None:
        manifest = self.fixture.manifest()
        manifest["tmux_socket"] = str(self.fixture.runtime_root / "tmux.sock")
        manifest["host_tools"] = sorted(
            [str(self.fixture.git), str(pathlib.Path(os.path.realpath(shutil.which("tmux") or "/bin/true")))]
        )
        launch = manifest["launch"]
        assert isinstance(launch, dict)
        argv = launcher.build_bwrap_argv(manifest, launch["server_argv"])
        self.assertEqual(
            argv[:5],
            [
                str(self.fixture.bwrap),
                "--new-session",
                "--unshare-pid",
                "--unshare-ipc",
                "--unshare-uts",
            ],
        )
        self.assertIn(
            ["--ro-bind", str(self.fixture.project), str(self.fixture.project)],
            windows(argv, 3),
        )
        self.assertNotIn(
            ["--bind", str(self.fixture.project), str(self.fixture.project)],
            windows(argv, 3),
        )
        self.assertIn(
            ["--ro-bind", "/dev/null", str(self.fixture.runtime_root / "tmux.sock")],
            windows(argv, 3),
        )
        self.assertIn(
            ["--ro-bind", str(self.fixture.git_dir), str(self.fixture.git_dir)],
            windows(argv, 3),
        )
        self.assertIn(
            ["--ro-bind", str(self.fixture.git_common), str(self.fixture.git_common)],
            windows(argv, 3),
        )
        mounts = windows(argv, 3)
        backend_bind = mounts.index(
            ["--bind", str(self.fixture.backend_state), str(self.fixture.backend_state)]
        )
        profiles_bind = mounts.index(
            [
                "--ro-bind",
                str(self.fixture.backend_state / "profiles"),
                str(self.fixture.backend_state / "profiles"),
            ]
        )
        profile_bind = mounts.index(
            ["--ro-bind", str(self.fixture.profile_root), str(self.fixture.profile_root)]
        )
        config_bind = mounts.index(
            [
                "--ro-bind",
                str(self.fixture.profile_root / "xdg-config"),
                str(self.fixture.backend_state / "xdg-config"),
            ]
        )
        auth_bind = mounts.index(
            [
                "--ro-bind",
                str(self.fixture.profile_root / "credentials/auth.json"),
                str(self.fixture.backend_state / "xdg-data/opencode/auth.json"),
            ]
        )
        mask_bind = mounts.index(
            [
                "--ro-bind",
                str(self.fixture.profile_root / "empty-home-opencode"),
                str(self.fixture.home / ".opencode"),
            ]
        )
        self.assertLess(backend_bind, profiles_bind)
        self.assertLess(profiles_bind, profile_bind)
        self.assertLess(profile_bind, config_bind)
        self.assertLess(config_bind, auth_bind)
        self.assertLess(auth_bind, mask_bind)
        git_mask = mounts.index(
            ["--ro-bind", str(self.fixture.git_common), str(self.fixture.git_common)]
        )
        self.assertGreater(git_mask, mask_bind)

    def test_writable_root_and_grant_are_exact_binds_before_git_masks(self) -> None:
        grant = self.fixture.private_dir(self.fixture.base / "grant")
        manifest = self.fixture.manifest(writable=True, grants=[str(grant)])
        launch = manifest["launch"]
        assert isinstance(launch, dict)
        argv = launcher.build_bwrap_argv(manifest, launch["server_argv"])
        mounts = windows(argv, 3)
        root_bind = mounts.index(
            ["--bind", str(self.fixture.project), str(self.fixture.project)]
        )
        grant_bind = mounts.index(["--bind", str(grant), str(grant)])
        git_mask = mounts.index(
            ["--ro-bind", str(self.fixture.git_common), str(self.fixture.git_common)]
        )
        self.assertLess(root_bind, git_mask)
        self.assertLess(grant_bind, git_mask)

    def test_server_and_attach_share_the_same_boundary_and_profile(self) -> None:
        manifest = self.fixture.manifest()
        launch = manifest["launch"]
        assert isinstance(launch, dict)
        server = launcher.build_bwrap_argv(manifest, launch["server_argv"])
        attach = launcher.build_bwrap_argv(manifest, launch["attach_argv"])
        server_separator = server.index("--")
        attach_separator = attach.index("--")
        self.assertEqual(server[: server_separator + 1], attach[: attach_separator + 1])
        self.assertEqual(
            launcher.build_environment(
                manifest, {"HOME": str(self.fixture.home)}
            )["OPENCODE_SERVER_PASSWORD"],
            PASSWORD,
        )


class InheritedBoundaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture(self)

    def validate(self, manifest: dict[str, object] | None = None) -> None:
        launcher.validate_manifest(
            manifest or self.fixture.manifest(), fixture_metadata()
        )

    def test_python_bwrap_and_shell_require_canonical_safe_executables(self) -> None:
        unsafe = self.fixture.private_file(
            self.fixture.base / "unsafe-tool", b"#!/bin/sh\nexit 0\n"
        )
        os.chmod(unsafe, 0o777)
        symlink = self.fixture.base / "tool-link"
        symlink.symlink_to(self.fixture.helper)
        for field in ("python", "bwrap", "shell"):
            for label, replacement in (
                ("writable", unsafe),
                ("symlink", symlink),
                ("noncanonical", self.fixture.base / "project" / ".." / "unsafe-tool"),
            ):
                with self.subTest(field=field, label=label):
                    manifest = self.fixture.manifest()
                    manifest[field] = str(replacement)
                    with self.assertRaises(ValueError):
                        self.validate(manifest)

    def test_launcher_and_every_helper_require_exact_safe_files(self) -> None:
        unsafe = self.fixture.private_file(self.fixture.base / "unsafe-helper", b"x")
        os.chmod(unsafe, 0o666)
        manifest = self.fixture.manifest()
        manifest["launcher"] = str(self.fixture.helper)
        with self.assertRaisesRegex(ValueError, "launcher"):
            self.validate(manifest)

        for field in (
            "review_helper",
            "control_helper",
            "event_helper",
            "profile_helper",
        ):
            with self.subTest(field=field):
                manifest = self.fixture.manifest()
                manifest[field] = str(unsafe)
                with self.assertRaises(ValueError):
                    self.validate(manifest)

        real_lstat = launcher.os.lstat

        def wrong_owner(path: str) -> os.stat_result | StatProxy:
            metadata = real_lstat(path)
            if path == str(self.fixture.profile_helper):
                return StatProxy(metadata, st_uid=os.getuid() + 1)
            return metadata

        with mock.patch.object(launcher.os, "lstat", side_effect=wrong_owner):
            with mock.patch.object(launcher, "_safe_nonuser_path", return_value=False):
                with self.assertRaisesRegex(ValueError, "owner"):
                    self.validate()

    def test_every_trusted_program_and_helper_rejects_a_safe_third_uid(self) -> None:
        third_uid = os.getuid() + 1000

        def executable(name: str) -> pathlib.Path:
            path = self.fixture.private_file(
                self.fixture.base / "trusted-owner" / name,
                b"#!/bin/sh\nexit 0\n",
            )
            os.chmod(path, 0o700)
            return path

        cases: list[tuple[str, dict[str, object], pathlib.Path]] = []
        for field in ("python", "bwrap", "shell"):
            manifest = self.fixture.manifest()
            path = executable(field)
            manifest[field] = str(path)
            cases.append((field, manifest, path))

        for field in (
            "review_helper",
            "control_helper",
            "event_helper",
            "profile_helper",
        ):
            manifest = self.fixture.manifest()
            path = self.fixture.private_file(
                self.fixture.base / "trusted-owner" / field,
                b"helper\n",
            )
            manifest[field] = str(path)
            cases.append((field, manifest, path))

        launcher_manifest = self.fixture.manifest()
        cases.append(("launcher", launcher_manifest, LAUNCHER_PATH.resolve()))

        host_tool_manifest = self.fixture.manifest()
        host_tool = executable("host-tools/git")
        host_tool_manifest["host_tools"] = [str(host_tool)]
        cases.append(("host tool", host_tool_manifest, host_tool))

        direct_manifest = self.fixture.direct_manifest()
        direct_launch = direct_manifest["launch"]
        assert isinstance(direct_launch, dict)
        direct_backend = executable("direct-backend")
        direct_launch["argv"][0] = str(direct_backend)
        direct_launch["protected_paths"] = [str(direct_backend)]
        cases.append(("direct backend", direct_manifest, direct_backend))

        managed_manifest = self.fixture.manifest()
        managed_launch = managed_manifest["launch"]
        assert isinstance(managed_launch, dict)
        managed_backend = executable("managed-backend")
        managed_launch["server_argv"][0] = str(managed_backend)
        managed_launch["attach_argv"][0] = str(managed_backend)
        managed_launch["protected_paths"] = sorted(
            [str(managed_backend), str(self.fixture.profile_root)]
        )
        cases.append(("managed backend", managed_manifest, managed_backend))

        real_lstat = launcher.os.lstat
        for label, manifest, target in cases:
            with self.subTest(label=label):
                def third_owner(path: str) -> os.stat_result | StatProxy:
                    metadata = real_lstat(path)
                    if os.fspath(path) == str(target):
                        return StatProxy(metadata, st_uid=third_uid)
                    return metadata

                with mock.patch.object(
                    launcher.os, "lstat", side_effect=third_owner
                ):
                    with mock.patch.object(
                        launcher, "_safe_nonuser_path", return_value=True
                    ):
                        with self.assertRaisesRegex(ValueError, "owner"):
                            self.validate(manifest)

    def test_trusted_nodes_accept_root_and_current_user_ownership(self) -> None:
        path = self.fixture.private_file(
            self.fixture.base / "trusted-owner" / "accepted",
            b"#!/bin/sh\nexit 0\n",
        )
        os.chmod(path, 0o700)
        real_lstat = launcher.os.lstat
        for owner, safe_nonuser in ((os.getuid(), False), (0, True)):
            with self.subTest(owner=owner):
                def selected_owner(candidate: str) -> os.stat_result | StatProxy:
                    metadata = real_lstat(candidate)
                    if os.fspath(candidate) == str(path):
                        return StatProxy(metadata, st_uid=owner)
                    return metadata

                with mock.patch.object(
                    launcher.os, "lstat", side_effect=selected_owner
                ):
                    with mock.patch.object(
                        launcher,
                        "_safe_nonuser_path",
                        return_value=safe_nonuser,
                    ):
                        launcher._validate_executable(str(path), "trusted executable")
                        launcher._validate_trusted_file(str(path), "trusted helper")

    def test_host_tools_are_exact_sorted_unique_and_safe(self) -> None:
        for tools in (
            [],
            [str(self.fixture.git), str(self.fixture.git)],
            [str(self.fixture.helper), str(self.fixture.git)],
        ):
            with self.subTest(tools=tools):
                manifest = self.fixture.manifest()
                manifest["host_tools"] = tools
                with self.assertRaisesRegex(ValueError, "host tools"):
                    self.validate(manifest)

        manifest = self.fixture.manifest()
        manifest["tmux_socket"] = str(self.fixture.control_socket)
        manifest["host_tools"] = [str(self.fixture.git)]
        with self.assertRaisesRegex(ValueError, "host tools"):
            self.validate(manifest)

    def test_runtime_state_backend_context_event_and_control_are_strict(self) -> None:
        mutations = {
            "runtime_root": str(self.fixture.runtime_root / ".." / "runtime"),
            "state_root": str(self.fixture.state_root / ".." / "state"),
            "context_dir": str(self.fixture.base / "outside-context"),
            "backend_state_dir": str(self.fixture.base / "outside-backend"),
            "event_file": str(self.fixture.base / "outside-events.ndjson"),
            "control_socket": str(self.fixture.event_file),
            "control_token": "D" * 32,
        }
        self.fixture.private_dir(self.fixture.base / "outside-context")
        self.fixture.private_dir(self.fixture.base / "outside-backend")
        self.fixture.private_file(self.fixture.base / "outside-events.ndjson", b"")
        for field, value in mutations.items():
            with self.subTest(field=field):
                manifest = self.fixture.manifest()
                manifest[field] = value
                with self.assertRaises(ValueError):
                    self.validate(manifest)

        os.chmod(self.fixture.runtime_root, 0o755)
        with self.assertRaisesRegex(ValueError, "runtime root"):
            self.validate()

    def test_root_git_and_tmux_paths_reject_symlinks_wrong_kinds_and_mutation(self) -> None:
        root_link = self.fixture.base / "root-link"
        root_link.symlink_to(self.fixture.project, target_is_directory=True)
        manifest = self.fixture.manifest()
        manifest["root"] = str(root_link)
        with self.assertRaisesRegex(ValueError, "project root"):
            self.validate(manifest)

        manifest = self.fixture.manifest()
        manifest["git_dir"] = str(self.fixture.git_entry)
        with self.assertRaisesRegex(ValueError, "Git directory"):
            self.validate(manifest)

        manifest = self.fixture.manifest()
        manifest["git_entry"] = str(self.fixture.base / "outside-git-entry")
        self.fixture.private_file(pathlib.Path(manifest["git_entry"]), b"gitdir: x\n")
        with self.assertRaisesRegex(ValueError, "Git entry"):
            self.validate(manifest)

        manifest = self.fixture.manifest()
        manifest["tmux_socket"] = str(self.fixture.event_file)
        tmux = pathlib.Path(os.path.realpath(shutil.which("tmux") or "/bin/true"))
        manifest["host_tools"] = sorted([str(self.fixture.git), str(tmux)])
        with self.assertRaisesRegex(ValueError, "tmux socket"):
            self.validate(manifest)

    def test_current_user_tmux_socket_accepts_group_writable_session_mode(self) -> None:
        tmux_socket = self.fixture.runtime_root / "tmux.sock"
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(str(tmux_socket))
        self.addCleanup(listener.close)
        os.chmod(tmux_socket, 0o770)
        manifest = self.fixture.manifest()
        manifest["tmux_socket"] = str(tmux_socket)
        tmux = pathlib.Path(os.path.realpath(shutil.which("tmux") or "/bin/true"))
        manifest["host_tools"] = sorted([str(self.fixture.git), str(tmux)])
        self.validate(manifest)

    def test_git_entry_accepts_standard_directory_and_linked_worktree_file(self) -> None:
        self.validate()
        self.fixture.git_entry.write_text(
            "gitdir: " + str(self.fixture.git_dir), encoding="utf-8"
        )
        os.chmod(self.fixture.git_entry, 0o600)
        self.validate()
        self.fixture.git_entry.unlink()
        self.fixture.git_entry.mkdir(mode=0o700)
        manifest = self.fixture.manifest()
        manifest["git_dir"] = str(self.fixture.git_entry)
        manifest["git_common_dir"] = str(self.fixture.git_entry)
        self.validate(manifest)

    def test_git_entry_is_exact_and_linked_file_target_matches_git_directory(self) -> None:
        decoy = self.fixture.private_file(
            self.fixture.project / "decoy-git-entry",
            ("gitdir: " + str(self.fixture.git_dir) + "\n").encode(),
        )
        manifest = self.fixture.manifest()
        manifest["git_entry"] = str(decoy)
        with self.assertRaisesRegex(ValueError, "Git entry"):
            self.validate(manifest)

        self.fixture.git_entry.write_text("gitdir: /tmp/wrong\n", encoding="utf-8")
        os.chmod(self.fixture.git_entry, 0o600)
        with self.assertRaisesRegex(ValueError, "Git entry"):
            self.validate()

        self.fixture.git_entry.write_bytes(b"x" * 4097)
        os.chmod(self.fixture.git_entry, 0o600)
        with self.assertRaisesRegex(ValueError, "Git entry"):
            self.validate()

    def test_read_only_inputs_enforce_provider_root_kind_and_destination(self) -> None:
        provider = self.fixture.private_dir(self.fixture.base / "provider")
        source = self.fixture.private_file(provider / "auth.json", b"{}\n")
        manifest = self.fixture.direct_manifest()
        launch = manifest["launch"]
        assert isinstance(launch, dict)
        launch["protected_paths"] = sorted([str(provider), str(self.fixture.helper)])
        launch["read_only_inputs"] = [
            {
                "source": str(source),
                "destination": str(self.fixture.backend_state / "auth.json"),
                "kind": "file",
            }
        ]
        self.validate(manifest)

        outside = self.fixture.private_file(self.fixture.base / "outside-auth.json", b"{}\n")
        changed = copy.deepcopy(manifest)
        changed["launch"]["read_only_inputs"][0]["source"] = str(outside)
        with self.assertRaisesRegex(ValueError, "provider root"):
            self.validate(changed)

        changed = copy.deepcopy(manifest)
        changed["launch"]["read_only_inputs"][0]["destination"] = str(
            self.fixture.base / "outside-destination"
        )
        with self.assertRaisesRegex(ValueError, "destination"):
            self.validate(changed)

        changed = copy.deepcopy(manifest)
        changed["launch"]["read_only_inputs"][0]["kind"] = "directory"
        with self.assertRaisesRegex(ValueError, "source"):
            self.validate(changed)

        destination = self.fixture.private_dir(self.fixture.backend_state / "auth.json")
        with self.assertRaisesRegex(ValueError, "destination"):
            self.validate(manifest)
        destination.rmdir()

        source_link = provider / "linked-auth.json"
        source_link.symlink_to(source)
        changed = copy.deepcopy(manifest)
        changed["launch"]["read_only_inputs"][0]["source"] = str(source_link)
        with self.assertRaisesRegex(ValueError, "source"):
            self.validate(changed)

    def test_missing_input_destination_gets_only_exact_private_persistent_placeholders(self) -> None:
        provider = self.fixture.private_dir(self.fixture.base / "provider-missing")
        source = self.fixture.private_file(provider / "auth.json", b"{}\n")
        manifest = self.fixture.direct_manifest()
        launch = manifest["launch"]
        assert isinstance(launch, dict)
        destination_parent = self.fixture.backend_state / "nested" / "provider"
        destination = destination_parent / "auth.json"
        launch["protected_paths"] = sorted([str(provider), str(self.fixture.helper)])
        launch["read_only_inputs"] = [
            {
                "source": str(source),
                "destination": str(destination),
                "kind": "file",
            }
        ]
        self.validate(manifest)
        created = launcher.prepare_mount_destinations(manifest, dict(os.environ))
        self.assertTrue(destination_parent.is_dir())
        self.assertEqual(stat.S_IMODE(destination_parent.stat().st_mode), 0o700)
        self.assertTrue(destination.is_file())
        self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)
        self.assertIn(str(destination), [item["path"] for item in created])
        argv = launcher.build_bwrap_argv(manifest, launch["argv"])
        self.assertNotIn(["--dir", str(destination_parent)], windows(argv, 2))

        hostile_parent = self.fixture.backend_state / "nested"
        launcher.rollback_mount_destinations(created)
        target = self.fixture.private_dir(self.fixture.base / "destination-escape")
        hostile_parent.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "destination"):
            self.validate(manifest)
        hostile_parent.unlink()
        self.fixture.private_file(hostile_parent, b"wrong kind")
        with self.assertRaisesRegex(ValueError, "destination"):
            self.validate(manifest)

    def test_mount_preparation_rolls_back_only_its_own_objects_on_failure(self) -> None:
        provider = self.fixture.private_dir(self.fixture.base / "provider-rollback")
        first = self.fixture.private_file(provider / "one.json", b"{}\n")
        second = self.fixture.private_file(provider / "two.json", b"{}\n")
        hostile_parent = self.fixture.private_file(
            self.fixture.backend_state / "z-hostile", b"wrong kind"
        )
        manifest = self.fixture.direct_manifest()
        launch = manifest["launch"]
        assert isinstance(launch, dict)
        launch["protected_paths"] = sorted([str(provider), str(self.fixture.helper)])
        first_destination = self.fixture.backend_state / "a-created" / "one.json"
        launch["read_only_inputs"] = [
            {
                "source": str(first),
                "destination": str(first_destination),
                "kind": "file",
            },
            {
                "source": str(second),
                "destination": str(hostile_parent / "two.json"),
                "kind": "file",
            },
        ]
        with self.assertRaisesRegex(ValueError, "destination"):
            launcher.prepare_mount_destinations(manifest, dict(os.environ))
        self.assertFalse(first_destination.exists())
        self.assertFalse(first_destination.parent.exists())
        self.assertTrue(hostile_parent.is_file())

    def test_post_create_failures_remove_the_exact_unpublished_inode(self) -> None:
        directory_destination = self.fixture.backend_state / "post-create-directory"
        with mock.patch.object(
            launcher.os, "fchmod", side_effect=OSError("injected directory failure")
        ):
            with self.assertRaisesRegex(ValueError, "created safely|creation"):
                launcher._ensure_private_mount_destination(
                    str(self.fixture.backend_state),
                    str(directory_destination),
                    "directory",
                    [],
                )
        self.assertFalse(directory_destination.exists())

        file_destination = self.fixture.backend_state / "post-create-file"
        with mock.patch.object(
            launcher.os, "fchmod", side_effect=OSError("injected file failure")
        ):
            with self.assertRaisesRegex(ValueError, "created safely|creation"):
                launcher._ensure_private_mount_destination(
                    str(self.fixture.backend_state),
                    str(file_destination),
                    "file",
                    [],
                )
        self.assertFalse(file_destination.exists())

        earliest_directory = self.fixture.backend_state / "earliest-directory"
        real_stat = launcher.os.stat
        directory_stat_failed = False

        def fail_first_stat_after_mkdir(path, *args, **kwargs):
            nonlocal directory_stat_failed
            if (
                path == earliest_directory.name
                and earliest_directory.exists()
                and not directory_stat_failed
            ):
                directory_stat_failed = True
                raise OSError("injected first directory stat failure")
            return real_stat(path, *args, **kwargs)

        with mock.patch.object(
            launcher.os, "stat", side_effect=fail_first_stat_after_mkdir
        ):
            with self.assertRaisesRegex(ValueError, "created safely|cleanup"):
                launcher._ensure_private_mount_destination(
                    str(self.fixture.backend_state),
                    str(earliest_directory),
                    "directory",
                    [],
                )
        self.assertFalse(earliest_directory.exists())

        earliest_file = self.fixture.backend_state / "earliest-file"
        real_fstat = launcher.os.fstat
        file_fstat_failed = False

        def fail_first_created_file_fstat(descriptor):
            nonlocal file_fstat_failed
            target = os.path.realpath("/proc/self/fd/" + str(descriptor))
            if target == str(earliest_file) and not file_fstat_failed:
                file_fstat_failed = True
                raise OSError("injected first file fstat failure")
            return real_fstat(descriptor)

        with mock.patch.object(
            launcher.os, "fstat", side_effect=fail_first_created_file_fstat
        ):
            with self.assertRaisesRegex(ValueError, "created safely|cleanup"):
                launcher._ensure_private_mount_destination(
                    str(self.fixture.backend_state),
                    str(earliest_file),
                    "file",
                    [],
                )
        self.assertFalse(earliest_file.exists())

    def test_rollback_refuses_replacement_and_reports_cleanup_failure(self) -> None:
        destination = self.fixture.backend_state / "rollback-replacement"
        created: list[dict[str, object]] = []
        launcher._ensure_private_mount_destination(
            str(self.fixture.backend_state), str(destination), "file", created
        )
        destination.unlink()
        destination.write_bytes(b"replacement")
        os.chmod(destination, 0o600)
        with self.assertRaisesRegex(ValueError, "cleanup|rollback"):
            launcher.rollback_mount_destinations(created)
        self.assertEqual(destination.read_bytes(), b"replacement")

    def test_rollback_reports_verified_inode_removal_failure(self) -> None:
        destination = self.fixture.backend_state / "rollback-refused"
        created: list[dict[str, object]] = []
        launcher._ensure_private_mount_destination(
            str(self.fixture.backend_state), str(destination), "file", created
        )
        with mock.patch.object(launcher.os, "unlink", side_effect=PermissionError):
            with self.assertRaisesRegex(ValueError, "cleanup|rollback"):
                launcher.rollback_mount_destinations(created)
        self.assertTrue(destination.exists())

    def test_provider_protected_paths_must_be_current_user_owned(self) -> None:
        provider = self.fixture.private_dir(self.fixture.base / "provider-owner")
        source = self.fixture.private_file(provider / "auth.json", b"{}\n")
        manifest = self.fixture.direct_manifest()
        launch = manifest["launch"]
        assert isinstance(launch, dict)
        launch["protected_paths"] = sorted([str(provider), str(self.fixture.helper)])
        launch["read_only_inputs"] = [
            {
                "source": str(source),
                "destination": str(self.fixture.backend_state / "auth-owner.json"),
                "kind": "file",
            }
        ]
        real_lstat = launcher.os.lstat

        def wrong_owner(path: str) -> os.stat_result | StatProxy:
            metadata = real_lstat(path)
            if path == str(provider):
                return StatProxy(metadata, st_uid=os.getuid() + 1)
            return metadata

        with mock.patch.object(launcher.os, "lstat", side_effect=wrong_owner):
            with mock.patch.object(launcher, "_safe_nonuser_path", return_value=True):
                with self.assertRaisesRegex(ValueError, "protected path"):
                    self.validate(manifest)

    def test_boolean_schema_values_are_rejected(self) -> None:
        for value in (True, 1.0):
            with self.subTest(value=value):
                manifest = self.fixture.manifest()
                manifest["schema"] = value
                with self.assertRaisesRegex(ValueError, "schema"):
                    self.validate(manifest)

                public = self.fixture.manifest()
                public_launch = public["launch"]
                assert isinstance(public_launch, dict)
                public_profile = public_launch["managed_profile"]
                assert isinstance(public_profile, dict)
                public_profile["schema"] = value
                with self.assertRaisesRegex(ValueError, "schema"):
                    self.validate(public)

        path = self.fixture.profile_root / "manifest.json"
        internal = json.loads(path.read_text(encoding="utf-8"))
        internal["schema"] = 1.0
        path.write_text(compact_json(internal) + "\n", encoding="utf-8")
        os.chmod(path, 0o600)
        with self.assertRaisesRegex(ValueError, "manifest"):
            launcher.validate_managed_profile(
                self.fixture.manifest(), {"HOME": str(self.fixture.home)}
            )

    def test_protected_paths_reject_missing_root_symlink_and_duplicates(self) -> None:
        linked = self.fixture.base / "protected-link"
        linked.symlink_to(self.fixture.helper)
        for paths in (
            ["/"],
            [str(self.fixture.base / "missing")],
            [str(linked)],
            [str(self.fixture.helper), str(self.fixture.helper)],
        ):
            with self.subTest(paths=paths):
                manifest = self.fixture.direct_manifest()
                launch = manifest["launch"]
                assert isinstance(launch, dict)
                launch["protected_paths"] = paths
                with self.assertRaises(ValueError):
                    self.validate(manifest)

    def test_manifest_replacement_and_unlink_failure_never_consume_ambiguously(self) -> None:
        path = self.fixture.write_launch_manifest(self.fixture.manifest())
        original = path.read_bytes()
        backup = path.with_suffix(".original")
        real_read = launcher.os.read
        replaced = False

        def racing_read(descriptor: int, maximum: int) -> bytes:
            nonlocal replaced
            payload = real_read(descriptor, maximum)
            if payload and not replaced:
                replaced = True
                path.rename(backup)
                path.write_bytes(original)
                os.chmod(path, 0o600)
            return payload

        with mock.patch.object(launcher.os, "read", side_effect=racing_read):
            with self.assertRaisesRegex(ValueError, "changed"):
                launcher.consume_manifest(str(path))
        self.assertTrue(path.exists())

        second = self.fixture.write_launch_manifest(self.fixture.manifest())
        with mock.patch.object(launcher.os, "unlink", side_effect=PermissionError):
            with self.assertRaisesRegex(ValueError, "cleanup"):
                launcher.consume_manifest(str(second))
        self.assertTrue(second.exists())

        invalid = self.fixture.manifest()
        invalid["unknown"] = True
        third = self.fixture.write_launch_manifest(invalid)
        with self.assertRaisesRegex(ValueError, "manifest keys"):
            launcher.consume_manifest(str(third))
        self.assertTrue(third.exists())


class FakeProcess:
    def __init__(self, wait_code: int = 0, running: bool = True) -> None:
        self.wait_code = wait_code
        self.running = running
        self.signals: list[int] = []
        self.terminated = False
        self.killed = False

    def poll(self) -> int | None:
        return None if self.running else self.wait_code

    def wait(self, timeout: float | None = None) -> int:
        del timeout
        self.running = False
        return self.wait_code

    def send_signal(self, number: int) -> None:
        self.signals.append(number)

    def terminate(self) -> None:
        self.terminated = True
        self.running = False

    def kill(self) -> None:
        self.killed = True
        self.running = False


class ProcessBoundaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture(self)
        launcher._ACTIVE_CHILDREN.clear()
        self.addCleanup(launcher._ACTIVE_CHILDREN.clear)

    def test_server_attach_opens_only_after_attach_starts_and_before_its_wait(self) -> None:
        manifest = self.fixture.manifest()
        environment = launcher.build_environment(manifest, dict(os.environ))
        server = FakeProcess()
        attach = FakeProcess(wait_code=0)
        order: list[str] = []

        def start_child(*_args: object, **_options: object) -> FakeProcess:
            if not order:
                order.append("server start")
                return server
            order.append("attach start")
            return attach

        def attach_wait(timeout: float | None = None) -> int:
            del timeout
            order.append("attach wait")
            attach.running = False
            return 0

        attach.wait = mock.Mock(side_effect=attach_wait)
        descriptors = [os.open(os.devnull, os.O_WRONLY), os.open(os.devnull, os.O_WRONLY)]
        with mock.patch.object(launcher, "_open_server_output", side_effect=descriptors):
            with mock.patch.object(
                launcher,
                "_wait_for_server",
                side_effect=lambda *_args: order.append("readiness"),
            ):
                with mock.patch.object(
                    launcher, "_start_child", side_effect=start_child
                ) as start:
                    with mock.patch.object(
                        launcher,
                        "append_event",
                        side_effect=lambda _manifest, state: order.append(
                            state + " event"
                        ),
                    ) as event:
                        self.assertEqual(
                            launcher.run_backend(
                                manifest,
                                environment,
                                on_start=lambda: order.append("on_start"),
                            ),
                            0,
                        )
        self.assertEqual(start.call_count, 2)
        self.assertIs(start.call_args_list[0].args[1], environment)
        self.assertIs(start.call_args_list[1].args[1], environment)
        self.assertTrue(server.terminated)
        event.assert_called_once_with(manifest, "open")
        self.assertEqual(
            order,
            [
                "server start",
                "on_start",
                "readiness",
                "attach start",
                "open event",
                "attach wait",
            ],
        )

    def test_attach_start_failure_emits_failed_but_never_open(self) -> None:
        manifest = self.fixture.manifest()
        environment = launcher.build_environment(manifest, dict(os.environ))
        server = FakeProcess()
        order: list[str] = []

        def start_child(*_args: object, **_options: object) -> FakeProcess:
            if not order:
                order.append("server start")
                return server
            order.append("attach start")
            raise OSError("attach refused")

        descriptors = [os.open(os.devnull, os.O_WRONLY), os.open(os.devnull, os.O_WRONLY)]
        with mock.patch.object(launcher, "_open_server_output", side_effect=descriptors):
            with mock.patch.object(
                launcher,
                "_wait_for_server",
                side_effect=lambda *_args: order.append("readiness"),
            ):
                with mock.patch.object(
                    launcher, "_start_child", side_effect=start_child
                ):
                    with mock.patch.object(
                        launcher,
                        "append_event",
                        side_effect=lambda _manifest, state: order.append(
                            state + " event"
                        ),
                    ) as event:
                        with self.assertRaisesRegex(
                            ValueError, "server or attach client"
                        ):
                            launcher.run_backend(
                                manifest,
                                environment,
                                on_start=lambda: order.append("on_start"),
                            )
        self.assertTrue(server.terminated)
        self.assertEqual(event.call_args_list, [mock.call(manifest, "failed")])
        self.assertEqual(
            order,
            [
                "server start",
                "on_start",
                "readiness",
                "attach start",
                "failed event",
            ],
        )

    def test_forwarded_signals_reach_each_active_child(self) -> None:
        first = FakeProcess()
        second = FakeProcess()
        launcher._ACTIVE_CHILDREN[:] = [first, second]
        launcher._forward_signal(signal.SIGTERM, None)
        self.assertEqual(first.signals, [signal.SIGTERM])
        self.assertEqual(second.signals, [signal.SIGTERM])

    def test_bwrap_start_failure_never_retries_the_raw_backend(self) -> None:
        manifest = self.fixture.direct_manifest()
        environment = launcher.build_environment(manifest, dict(os.environ))
        with mock.patch.object(
            launcher.subprocess, "Popen", side_effect=OSError("bwrap refused")
        ) as popen:
            with mock.patch.object(launcher, "append_event") as event:
                with self.assertRaisesRegex(ValueError, "managed backend"):
                    launcher.run_backend(manifest, environment)
        self.assertEqual(popen.call_count, 1)
        invoked = popen.call_args.args[0]
        self.assertEqual(invoked[0], manifest["bwrap"])
        self.assertNotEqual(invoked[0], manifest["launch"]["argv"][0])
        event.assert_called_once_with(manifest, "failed")

    def test_diagnostic_fallback_never_executes_an_unconfined_shell(self) -> None:
        manifest = self.fixture.manifest()
        environment = launcher.build_environment(manifest, dict(os.environ))
        confined = [manifest["bwrap"], "--", manifest["shell"], "-l"]
        with mock.patch("builtins.print"):
            with mock.patch.object(launcher, "build_bwrap_argv", return_value=confined):
                with mock.patch.object(launcher.os, "execve", side_effect=OSError) as execute:
                    with mock.patch.object(
                        launcher, "_fixed_wait", side_effect=RuntimeError("stop")
                    ):
                        with self.assertRaisesRegex(RuntimeError, "stop"):
                            launcher.diagnostic_fallback(
                                manifest, environment, "backend exited"
                            )
        execute.assert_called_once_with(manifest["bwrap"], confined, environment)

    def test_bounded_diagnostic_preserves_safe_text(self) -> None:
        self.assertEqual(launcher._bounded_diagnostic("backend exited"), "backend exited")
        self.assertNotIn("\n", launcher._bounded_diagnostic("bad\nmessage"))

    def test_main_rolls_back_mount_preparation_only_before_child_start(self) -> None:
        manifest = self.fixture.direct_manifest()
        environment = launcher.build_environment(manifest, dict(os.environ))
        created = [
            {
                "path": str(self.fixture.backend_state / "prepared"),
                "dev": 1,
                "ino": 2,
                "kind": "directory",
            }
        ]

        def fail_before_start(_manifest, _environment, on_start=None):
            del on_start
            raise ValueError("start failed")

        def fail_after_start(_manifest, _environment, on_start=None):
            assert on_start is not None
            on_start()
            raise ValueError("runtime failed")

        for name, runner, rollback_expected in (
            ("before start", fail_before_start, True),
            ("after start", fail_after_start, False),
        ):
            with self.subTest(name=name):
                with mock.patch.object(
                    launcher,
                    "consume_manifest",
                    return_value=(manifest, created),
                ):
                    with mock.patch.object(
                        launcher, "build_environment", return_value=environment
                    ):
                        with mock.patch.object(
                            launcher, "run_backend", side_effect=runner
                        ):
                            with mock.patch.object(
                                launcher, "rollback_mount_destinations"
                            ) as rollback:
                                with mock.patch.object(
                                    launcher,
                                    "_fixed_wait",
                                    side_effect=RuntimeError("fixed wait"),
                                ) as fixed_wait:
                                    with mock.patch.object(
                                        launcher,
                                        "diagnostic_fallback",
                                        side_effect=RuntimeError("confined fallback"),
                                    ) as fallback:
                                        with mock.patch("builtins.print"):
                                            expected = (
                                                "fixed wait"
                                                if rollback_expected
                                                else "confined fallback"
                                            )
                                            with self.assertRaisesRegex(
                                                RuntimeError, expected
                                            ):
                                                launcher.main(
                                                    ["--manifest", "/tmp/fixture.json"]
                                                )
                if rollback_expected:
                    rollback.assert_called_once_with(created)
                    fixed_wait.assert_called_once_with()
                    fallback.assert_not_called()
                else:
                    rollback.assert_not_called()
                    fixed_wait.assert_not_called()
                    fallback.assert_called_once_with(
                        manifest,
                        environment,
                        "nvim-ai-launch: managed backend failed",
                    )

    def test_main_surfaces_prestart_destination_cleanup_failure(self) -> None:
        manifest = self.fixture.direct_manifest()
        environment = launcher.build_environment(manifest, dict(os.environ))
        created = [
            {
                "path": str(self.fixture.backend_state / "prepared"),
                "dev": 1,
                "ino": 2,
                "kind": "directory",
            }
        ]
        with mock.patch.object(
            launcher, "consume_manifest", return_value=(manifest, created)
        ):
            with mock.patch.object(
                launcher, "build_environment", return_value=environment
            ):
                with mock.patch.object(
                    launcher, "run_backend", side_effect=ValueError("start failed")
                ):
                    with mock.patch.object(
                        launcher,
                        "rollback_mount_destinations",
                        side_effect=ValueError("cleanup refused"),
                    ):
                        with mock.patch.object(
                            launcher,
                            "_fixed_wait",
                            side_effect=RuntimeError("stop"),
                        ):
                            with mock.patch.object(
                                launcher, "diagnostic_fallback"
                            ) as fallback:
                                with mock.patch("builtins.print") as printed:
                                    with self.assertRaisesRegex(RuntimeError, "stop"):
                                        launcher.main(
                                            ["--manifest", "/tmp/fixture.json"]
                                        )
        fallback.assert_not_called()
        printed.assert_any_call(
            "nvim-ai-launch: destination cleanup failed",
            file=launcher.sys.stderr,
            flush=True,
        )

    def test_main_normalizes_prestart_shape_errors_without_starting_a_child(self) -> None:
        manifest = self.fixture.direct_manifest()
        with mock.patch.object(
            launcher, "consume_manifest", return_value=(manifest, [])
        ):
            with mock.patch.object(
                launcher,
                "build_environment",
                side_effect=TypeError("hostile environment shape"),
            ):
                with mock.patch.object(launcher, "run_backend") as runner:
                    with mock.patch.object(
                        launcher,
                        "_fixed_wait",
                        side_effect=RuntimeError("stop"),
                    ):
                        with mock.patch("builtins.print"):
                            with self.assertRaisesRegex(RuntimeError, "stop"):
                                launcher.main(
                                    ["--manifest", "/tmp/fixture.json"]
                                )
        runner.assert_not_called()

    def test_main_reports_unpublished_destination_cleanup_failure_distinctly(self) -> None:
        path = self.fixture.write_launch_manifest(self.fixture.manifest())
        destination = self.fixture.backend_state / "xdg-config"
        real_fstat = launcher.os.fstat

        def refuse_created_destination_metadata(descriptor):
            target = os.path.realpath("/proc/self/fd/" + str(descriptor))
            if target == str(destination):
                raise OSError("injected destination metadata failure")
            return real_fstat(descriptor)

        with mock.patch.object(
            launcher.os,
            "fstat",
            side_effect=refuse_created_destination_metadata,
        ):
            with mock.patch.object(launcher, "run_backend") as runner:
                with mock.patch.object(
                    launcher,
                    "_fixed_wait",
                    side_effect=RuntimeError("stop"),
                ):
                    with mock.patch.object(launcher, "diagnostic_fallback") as fallback:
                        with mock.patch("builtins.print") as printed:
                            with self.assertRaisesRegex(RuntimeError, "stop"):
                                launcher.main(["--manifest", str(path)])
        runner.assert_not_called()
        fallback.assert_not_called()
        printed.assert_any_call(
            "nvim-ai-launch: destination cleanup failed",
            file=launcher.sys.stderr,
            flush=True,
        )
        self.assertTrue(destination.is_dir())
        self.assertTrue(path.exists())

    def test_main_rolls_back_unexpected_destination_close_error(self) -> None:
        path = self.fixture.write_launch_manifest(self.fixture.manifest())
        destination = self.fixture.backend_state / "xdg-config"
        backend = str(self.fixture.backend_state)
        real_close = launcher.os.close
        injected = False

        def fail_one_backend_close(descriptor):
            nonlocal injected
            target = os.path.realpath("/proc/self/fd/" + str(descriptor))
            if destination.exists() and target == backend and not injected:
                injected = True
                raise OSError("injected descriptor close failure")
            return real_close(descriptor)

        with mock.patch.object(launcher.os, "close", side_effect=fail_one_backend_close):
            with mock.patch.object(launcher, "run_backend") as runner:
                with mock.patch.object(
                    launcher,
                    "_fixed_wait",
                    side_effect=RuntimeError("stop"),
                ):
                    with mock.patch.object(launcher, "diagnostic_fallback") as fallback:
                        with mock.patch("builtins.print") as printed:
                            with self.assertRaisesRegex(RuntimeError, "stop"):
                                launcher.main(["--manifest", str(path)])
        runner.assert_not_called()
        fallback.assert_not_called()
        printed.assert_any_call(
            "nvim-ai-launch: launch refused",
            file=launcher.sys.stderr,
            flush=True,
        )
        self.assertFalse(destination.exists())
        self.assertTrue(path.exists())


class RealHarnessContractTests(unittest.TestCase):
    def test_preserved_profile_and_staging_namespaces_cover_all_mutations(self) -> None:
        harness = (ROOT / "tests" / "nvim-ai-sandbox.sh").read_text(
            encoding="utf-8"
        )
        required = (
            "HARNESS_PROFILES_PRESERVED=",
            "HARNESS_PROFILES_EMPTY=",
            "HARNESS_STAGING_PRESERVED=",
            "HARNESS_STAGING_EMPTY=",
            'if mkdir "$profiles_root/hostile"',
            'if mv "$profiles_preserved"',
            'if rm "$profiles_preserved/marker"',
            'if rmdir "$profiles_empty"',
            'if mkdir "$backends_parent/.opencode-profile-hostile.tmp"',
            'if mv "$staging_preserved"',
            'if rm "$staging_preserved/marker"',
            'if rmdir "$staging_empty"',
            '$(cat "$HARNESS_PROFILES_PRESERVED/marker")" = profiles-preserved',
            '$(cat "$HARNESS_STAGING_PRESERVED/marker")" = staging-preserved',
        )
        missing = [snippet for snippet in required if snippet not in harness]
        self.assertEqual(missing, [])


class DescriptorAndEventTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture(self)

    def test_descriptor_reader_rejects_same_size_replacement(self) -> None:
        parent = os.open(self.fixture.profile_root, os.O_RDONLY | os.O_DIRECTORY)
        self.addCleanup(os.close, parent)
        real_fstat = launcher.os.fstat
        calls = 0

        def changed_fstat(descriptor: int) -> os.stat_result:
            nonlocal calls
            result = real_fstat(descriptor)
            calls += 1
            if calls >= 2:
                values = list(result)
                values[1] += 1
                return os.stat_result(values)
            return result

        with mock.patch.object(launcher.os, "fstat", side_effect=changed_fstat):
            with self.assertRaisesRegex(ValueError, "changed"):
                launcher._read_regular_at(parent, "manifest.json", 1024 * 1024)

    def test_event_records_are_bounded_normalized_and_contain_no_credentials(self) -> None:
        manifest = self.fixture.manifest()
        launcher.append_event(manifest, "open")
        line = self.fixture.event_file.read_text(encoding="utf-8")
        record = json.loads(line)
        self.assertEqual(
            record,
            {"backend": "opencode", "session": "ses_test", "state": "open"},
        )
        self.assertNotIn(PASSWORD, line)
        self.assertNotIn("credential-canary", line)
        self.assertEqual(stat.S_IMODE(self.fixture.event_file.stat().st_mode), 0o600)

    def test_failed_validation_diagnostic_never_contains_decoded_secret(self) -> None:
        auth = self.fixture.profile_root / "credentials/auth.json"
        auth.write_text(
            '{"provider":{"type":"api","key":"diagnostic-secret","extra":true}}\n',
            encoding="utf-8",
        )
        os.chmod(auth, 0o600)
        with self.assertRaises(ValueError) as caught:
            launcher.validate_managed_profile(
                self.fixture.manifest(), {"HOME": str(self.fixture.home)}
            )
        self.assertNotIn("diagnostic-secret", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
