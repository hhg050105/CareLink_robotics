#!/usr/bin/env python3
"""Read the requested STOP/FOLLOW mode from a Firestore document."""

import threading
import time
from pathlib import Path
from typing import Optional, Tuple


VALID_MODES = {"STOP", "FOLLOW"}


class FirebaseFollowControl(threading.Thread):
    """Poll Firestore while keeping a fail-safe local mode snapshot."""

    def __init__(self, credential_path: Path, document_path: str, poll_interval: float = 1.0):
        super().__init__(daemon=True)
        self.credential_path = credential_path
        self.document_path = document_path.strip("/")
        self.poll_interval = poll_interval
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._mode = "STOP"
        self._connected = False
        self._error: Optional[str] = None
        self._updated_at = 0.0

    def snapshot(self) -> Tuple[str, bool, Optional[str], float]:
        with self._lock:
            return self._mode, self._connected, self._error, self._updated_at

    def close(self) -> None:
        self._stop_event.set()

    def _set_state(self, mode: str, connected: bool, error: Optional[str]) -> None:
        with self._lock:
            self._mode = mode
            self._connected = connected
            self._error = error
            self._updated_at = time.monotonic()

    @staticmethod
    def mode_from_data(data: dict) -> str:
        raw_mode = data.get("mode")
        if isinstance(raw_mode, str):
            mode = raw_mode.strip().upper()
            if mode in VALID_MODES:
                return mode
        enabled = data.get("enabled")
        if isinstance(enabled, bool):
            return "FOLLOW" if enabled else "STOP"
        return "STOP"

    def run(self) -> None:
        try:
            import firebase_admin
            from firebase_admin import credentials, firestore

            if not self.credential_path.is_file():
                raise FileNotFoundError(f"Firebase credential not found: {self.credential_path}")
            if not firebase_admin._apps:
                firebase_admin.initialize_app(credentials.Certificate(str(self.credential_path)))
            document = firestore.client().document(self.document_path)
        except Exception as error:
            self._set_state("STOP", False, str(error))
            return

        while not self._stop_event.is_set():
            try:
                snapshot = document.get(timeout=5.0)
                if snapshot.exists:
                    mode = self.mode_from_data(snapshot.to_dict() or {})
                    self._set_state(mode, True, None)
                else:
                    self._set_state("STOP", True, "control document does not exist")
            except Exception as error:
                self._set_state("STOP", False, str(error))
            self._stop_event.wait(self.poll_interval)
