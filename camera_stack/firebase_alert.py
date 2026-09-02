"""Optional Firestore + FCM reporting for fall events."""

from pathlib import Path


class FirebaseAlert:
    def __init__(self, credential_path="secrets/firebase-service-account.json"):
        self.enabled = False
        self.db = None
        self.messaging = None
        self.credential_path = Path(credential_path)
        if not self.credential_path.exists():
            print(f"Firebase disabled: place credentials at {self.credential_path}", flush=True)
            return
        try:
            import firebase_admin
            from firebase_admin import credentials, firestore, messaging
            if not firebase_admin._apps:
                firebase_admin.initialize_app(credentials.Certificate(str(self.credential_path)))
            self.db = firestore.client()
            self.messaging = messaging
            self.enabled = True
            print("Firebase connected: fall_events / topic fall-alerts", flush=True)
        except Exception as error:
            print(f"Firebase disabled: {error}", flush=True)

    def send_fall(self, confidence, box_ratio, drop_pixels, snapshot_path,
                  camera_id="living-room"):
        if not self.enabled:
            return None
        from firebase_admin import firestore
        event = {
            "event": "fall_detected",
            "detectedAt": firestore.SERVER_TIMESTAMP,
            "confidence": float(confidence),
            "boxRatio": float(box_ratio),
            "dropPixels": float(drop_pixels),
            "cameraId": camera_id,
            "snapshotPath": str(snapshot_path),
            "acknowledged": False,
        }
        reference = self.db.collection("fall_events").document()
        reference.set(event)
        message = self.messaging.Message(
            notification=self.messaging.Notification(
                title="낙상 감지",
                body=f"{camera_id} 카메라에서 낙상이 감지되었습니다.",
            ),
            data={
                "eventId": reference.id,
                "event": "fall_detected",
                "cameraId": camera_id,
            },
            topic="fall-alerts",
        )
        message_id = self.messaging.send(message)
        print(f"Firebase event={reference.id} message={message_id}", flush=True)
        return reference.id
