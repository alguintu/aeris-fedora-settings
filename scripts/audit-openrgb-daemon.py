#!/usr/bin/env python3
"""Statically enforce Aeris's narrow OpenRGB daemon command surface."""

import argparse
import ast
from pathlib import Path


FORBIDDEN_CALLS = {
    "apply_firmware_idle",
    "clear",
    "off",
    "resize",
    "save_mode",
    "save_profile",
    "set_custom_mode",
}
FORBIDDEN_SOURCE_TOKENS = {
    "RGBCONTROLLER_SAVEMODE",
    "RGBCONTROLLER_SETCUSTOMMODE",
}
COLOR_CALLS = {"set_color", "set_colors"}


def constant_is(node, expected):
    return isinstance(node, ast.Constant) and node.value is expected


class DaemonAuditor(ast.NodeVisitor):
    def __init__(self):
        self.errors = []
        self.direct_mode_calls = 0

    def reject(self, node, message):
        self.errors.append(f"line {getattr(node, 'lineno', '?')}: {message}")

    def visit_Call(self, node):
        method = None
        if isinstance(node.func, ast.Attribute):
            method = node.func.attr
        elif isinstance(node.func, ast.Name):
            method = node.func.id

        if method in FORBIDDEN_CALLS or (method and method.lower().startswith("save")):
            self.reject(node, f"forbidden call {method}()")

        if method == "set_mode":
            self.direct_mode_calls += 1
            valid_argument = (
                len(node.args) == 1
                and isinstance(node.args[0], ast.Constant)
                and node.args[0].value == "Direct"
            )
            valid_keywords = (
                len(node.keywords) == 1
                and node.keywords[0].arg == "save"
                and constant_is(node.keywords[0].value, False)
            )
            if not valid_argument or not valid_keywords:
                self.reject(
                    node,
                    "set_mode() must be exactly set_mode(\"Direct\", save=False)",
                )

        if method in COLOR_CALLS:
            fast_keywords = [keyword for keyword in node.keywords if keyword.arg == "fast"]
            if len(fast_keywords) != 1 or not constant_is(fast_keywords[0].value, True):
                self.reject(node, f"{method}() must explicitly use fast=True")

        self.generic_visit(node)


def audit(path):
    source = path.read_text(encoding="utf-8")
    errors = []
    for token in sorted(FORBIDDEN_SOURCE_TOKENS):
        if token in source:
            errors.append(f"forbidden SDK packet token {token}")

    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        return [f"syntax error: {exc}"]

    visitor = DaemonAuditor()
    visitor.visit(tree)
    errors.extend(visitor.errors)
    if visitor.direct_mode_calls != 1:
        errors.append(
            "daemon must contain exactly one audited Direct-mode transition site; "
            f"found {visitor.direct_mode_calls}"
        )
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("daemon", type=Path)
    args = parser.parse_args()

    problems = audit(args.daemon)
    if problems:
        for problem in problems:
            print(f"UNSAFE   {args.daemon}: {problem}")
        return 1

    print(
        f"SAFE     {args.daemon}: Direct mode is explicitly volatile; "
        "color writes are fast Direct-mode updates"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
