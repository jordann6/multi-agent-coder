import ast
import re
from typing import Any


def write_code(language: str, task: str) -> dict[str, Any]:
    language = language.lower().strip()

    scaffolds: dict[str, dict[str, str]] = {
        "python": {
            "entry_point": "def main():",
            "error_handling": "try/except with specific exception types",
            "imports_hint": "standard library preferred; minimize third-party deps",
            "style": "PEP8, type hints encouraged",
            "template": (
                "# Task: {task}\n"
                "from typing import Any\n\n\n"
                "def main() -> Any:\n"
                "    pass\n\n\n"
                "if __name__ == '__main__':\n"
                "    main()\n"
            ),
        },
        "javascript": {
            "entry_point": "const main = () =>",
            "error_handling": "try/catch",
            "imports_hint": "ESModules preferred (import/export)",
            "style": "camelCase, const over let",
            "template": (
                "// Task: {task}\n\n"
                "const main = () => {{\n"
                "  // implementation\n"
                "}};\n\n"
                "module.exports = {{ main }};\n"
            ),
        },
        "typescript": {
            "entry_point": "const main = (): ReturnType =>",
            "error_handling": "try/catch with typed errors",
            "imports_hint": "ESModules, explicit type imports",
            "style": "strict mode, explicit return types",
            "template": (
                "// Task: {task}\n\n"
                "const main = (): void => {{\n"
                "  // implementation\n"
                "}};\n\n"
                "export {{ main }};\n"
            ),
        },
        "bash": {
            "entry_point": "#!/bin/bash",
            "error_handling": "set -euo pipefail at top of file",
            "imports_hint": "prefer built-ins; avoid external deps where possible",
            "style": "SCREAMING_SNAKE_CASE for constants, snake_case for locals",
            "template": (
                "#!/bin/bash\n"
                "# Task: {task}\n"
                "set -euo pipefail\n\n"
                "main() {{\n"
                "  echo 'implement here'\n"
                "}}\n\n"
                "main \"$@\"\n"
            ),
        },
        "go": {
            "entry_point": "func main()",
            "error_handling": "explicit error returns; no panic in library code",
            "imports_hint": "standard library first; group stdlib vs external imports",
            "style": "gofmt, exported symbols capitalized",
            "template": (
                "// Task: {task}\n"
                "package main\n\n"
                "import \"fmt\"\n\n"
                "func main() {{\n"
                "    fmt.Println(\"implement here\")\n"
                "}}\n"
            ),
        },
    }

    scaffold = scaffolds.get(
        language,
        {
            "entry_point": "language-specific entry point",
            "error_handling": "language-appropriate error handling",
            "imports_hint": "minimize dependencies",
            "style": "follow community conventions",
            "template": "// Task: {task}\n// implement here\n",
        },
    )

    return {
        "language": language,
        "task": task,
        "scaffold": scaffold["template"].format(task=task),
        "hints": {
            "entry_point": scaffold["entry_point"],
            "error_handling": scaffold["error_handling"],
            "imports": scaffold["imports_hint"],
            "style": scaffold["style"],
        },
    }


def explain_code(code: str, language: str) -> dict[str, Any]:
    language = language.lower().strip()
    result: dict[str, Any] = {
        "language": language,
        "line_count": len(code.splitlines()),
        "char_count": len(code),
        "structure": {},
    }

    if language == "python":
        try:
            tree = ast.parse(code)
            functions = [
                node.name
                for node in ast.walk(tree)
                if isinstance(node, ast.FunctionDef)
            ]
            classes = [
                node.name
                for node in ast.walk(tree)
                if isinstance(node, ast.ClassDef)
            ]
            imports: list[str] = []
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    imports.extend(alias.name for alias in node.names)
                elif isinstance(node, ast.ImportFrom):
                    imports.append(node.module or "")

            result["structure"] = {
                "functions": functions,
                "classes": classes,
                "imports": list(set(filter(None, imports))),
                "syntax_valid": True,
            }
        except SyntaxError as e:
            result["structure"] = {
                "syntax_valid": False,
                "syntax_error": str(e),
            }
    else:
        func_patterns = {
            "javascript": r"(?:function\s+(\w+)|const\s+(\w+)\s*=\s*(?:async\s*)?\()",
            "typescript": r"(?:function\s+(\w+)|const\s+(\w+)\s*=\s*(?:async\s*)?\()",
            "bash": r"^(\w+)\s*\(\)",
            "go": r"func\s+(\w+)\s*\(",
        }
        pattern = func_patterns.get(language, "")
        functions_found: list[str] = []
        if pattern:
            for match in re.finditer(pattern, code, re.MULTILINE):
                name = next((g for g in match.groups() if g), None)
                if name:
                    functions_found.append(name)
        result["structure"] = {"detected_functions": functions_found}

    return result


def debug_code(code: str, error: str, language: str) -> dict[str, Any]:
    language = language.lower().strip()

    error_patterns = [
        (
            r"NameError|ReferenceError|undefined",
            "undefined_variable",
            "A variable or function is referenced before it is defined or is out of scope.",
        ),
        (
            r"TypeError|type error|cannot read propert",
            "type_error",
            "An operation is being performed on an incompatible type.",
        ),
        (
            r"IndexError|index out of range|out of bounds",
            "index_error",
            "A sequence is being accessed at an index that does not exist.",
        ),
        (
            r"KeyError|key not found",
            "key_error",
            "A dictionary key does not exist.",
        ),
        (
            r"SyntaxError|syntax error|unexpected token|parse error",
            "syntax_error",
            "The code has a structural issue that prevents parsing.",
        ),
        (
            r"ImportError|ModuleNotFoundError|cannot find module",
            "import_error",
            "A module or package is missing or not installed.",
        ),
        (
            r"AttributeError|has no attribute|is not a function",
            "attribute_error",
            "An attribute or method does not exist on this object.",
        ),
        (
            r"ZeroDivisionError|division by zero",
            "division_error",
            "A division by zero is occurring.",
        ),
        (
            r"ConnectionError|ECONNREFUSED|timeout|ETIMEDOUT",
            "connection_error",
            "A network connection failed or timed out.",
        ),
        (
            r"PermissionError|EACCES|permission denied",
            "permission_error",
            "The process lacks permission to access a file or resource.",
        ),
    ]

    detected_type = "unknown_error"
    detected_description = "Error type could not be automatically classified."

    for pattern, error_type, description in error_patterns:
        if re.search(pattern, error, re.IGNORECASE):
            detected_type = error_type
            detected_description = description
            break

    result: dict[str, Any] = {
        "language": language,
        "error_type": detected_type,
        "error_description": detected_description,
        "raw_error": error,
        "line_count": len(code.splitlines()),
    }

    if language == "python":
        try:
            ast.parse(code)
            result["syntax_valid"] = True
        except SyntaxError as e:
            result["syntax_valid"] = False
            result["syntax_note"] = str(e)

    return result


TOOL_DISPATCH: dict[str, Any] = {
    "write_code": write_code,
    "explain_code": explain_code,
    "debug_code": debug_code,
}
