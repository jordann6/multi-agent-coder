import os

_EXPECTED_KEY = os.environ.get("API_KEY", "")


def handler(event: dict, context: object) -> dict:
    provided = event.get("identitySource") or ""
    return {"isAuthorized": bool(_EXPECTED_KEY and provided == _EXPECTED_KEY)}
