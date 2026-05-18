from agents.coder import run_coder_agent


def handler(event: dict, context: object) -> dict:
    try:
        task = (event.get("task") or "").strip()
        job_id = event.get("job_id") or None

        if not task:
            return {"error": "task field is required"}

        return run_coder_agent(task, job_id=job_id)

    except Exception as e:
        return {"error": str(e)}
