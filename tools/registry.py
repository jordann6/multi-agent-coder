CODER_TOOLS = [
    {
        "name": "write_code",
        "description": (
            "Generate a language-appropriate scaffold and structural hints to guide "
            "code writing for the given task."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "language": {
                    "type": "string",
                    "description": "Programming language such as python, javascript, bash, go, typescript"
                },
                "task": {
                    "type": "string",
                    "description": "Description of what the code should accomplish"
                }
            },
            "required": ["language", "task"]
        }
    },
    {
        "name": "explain_code",
        "description": (
            "Analyze a code block and return structural metadata including detected "
            "functions, classes, imports, and line count to inform a plain-language explanation."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "The code block to analyze"
                },
                "language": {
                    "type": "string",
                    "description": "The programming language of the code block"
                }
            },
            "required": ["code", "language"]
        }
    },
    {
        "name": "debug_code",
        "description": (
            "Analyze code and an error message to classify the bug type and return "
            "structured diagnostic information."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "The code that contains the bug"
                },
                "error": {
                    "type": "string",
                    "description": "The error message or description of unexpected behavior"
                },
                "language": {
                    "type": "string",
                    "description": "The programming language of the code"
                }
            },
            "required": ["code", "error", "language"]
        }
    }
]

ORCHESTRATOR_TOOLS = [
    {
        "name": "invoke_coder",
        "description": (
            "Route a coding task to the Coder specialist agent. Use for tasks "
            "involving writing, explaining, or debugging code."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "task": {
                    "type": "string",
                    "description": "The full task description to send to the Coder specialist"
                }
            },
            "required": ["task"]
        }
    }
]
