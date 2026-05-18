from agents.coder import run_coder_agent


def handler(event: dict, context: object) -> dict:
    try:
        task = (event.get("task") or "").strip()

        if not task:
            return {"error": "task field is required"}

        return run_coder_agent(task)

    except Exception as e:
        return {"error": str(e)}
