#!/usr/bin/env python3
"""Lists user-facing strings in the Swift sources and checks that every one
has a translation in each Resources/<lang>.lproj/Localizable.strings.

Usage: scripts/check-localization.py [--print-keys]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources" / "Meno"
LITERAL = r'"((?:[^"\\\n]|\\.)*)"'

# Calls whose first string literal is a LocalizedStringKey or LocalizationValue.
CALLS = [
    "String(localized:", "Text(", "Button(", "Toggle(", "Label(", "TextField(", "Menu(",
    "SettingsCard(", "SettingRow(", "ToggleRow(", "SliderRow(", "Link(", ".alert(",
    ".confirmationDialog(", "Picker(", "ColorPicker(",
]
# Labelled arguments that take a LocalizedStringKey.
LABELS = ["title", "message", "subtitle", "footnote", "label", "explanation", "detail", "text", "actionTitle", "help"]
# Helpers whose second argument is a LocalizedStringKey.
SECOND_ARGUMENT = ["tip(", "pill("]
# Keys produced outside the patterns above.
EXTRA = ["Beta", "Experimental"]
# Matches of the patterns above that are not user-facing.
IGNORE = {"%@.network", "%@.capture", "%@.commands"}

INT_HINTS = (".count", "total", "uses", "days", "percent", "min(", "entry.value")


def placeholder(expression):
    return "%lld" if any(hint in expression for hint in INT_HINTS) else "%@"


def to_key(literal):
    """Turns a Swift literal with interpolations into a localization key."""
    out = ""
    has_format = "\\(" in literal
    i = 0
    while i < len(literal):
        if literal.startswith("\\(", i):
            depth = 1
            j = i + 2
            while j < len(literal) and depth:
                if literal[j] == "(":
                    depth += 1
                elif literal[j] == ")":
                    depth -= 1
                j += 1
            out += placeholder(literal[i + 2:j - 1])
            i = j
        elif literal.startswith('\\"', i):
            out += '"'
            i += 2
        elif literal[i] == "%" and has_format:
            out += "%%"
            i += 1
        else:
            out += literal[i]
            i += 1
    return out


def extract():
    keys = {}
    for path in sorted(SOURCES.rglob("*.swift")):
        source = path.read_text()
        spots = []
        for call in CALLS:
            boundary = r"(?<![A-Za-z])" if call[0].isalpha() else ""
            pattern = boundary + re.escape(call) + r"\s*(?:(?!verbatim)[A-Za-z]+:\s*)?(?=\")"
            spots += [m.end() for m in re.finditer(pattern, source)]
        for label in LABELS:
            spots += [m.end() for m in re.finditer(r"\b" + label + r":\s*(?=\")", source)]
        for helper in SECOND_ARGUMENT:
            spots += [m.end() for m in re.finditer(re.escape(helper) + r"\s*" + LITERAL + r",\s*(?=\")", source)]
        for position in spots:
            match = re.match(LITERAL, source[position:])
            if match and match.group(1).strip():
                keys.setdefault(to_key(match.group(1)), path.relative_to(ROOT))
        # Ternaries of two literals, as in Text(flag ? "A" : "B").
        for m in re.finditer(r"(?:Text|Button)\([^()\n]*\?\s*" + LITERAL + r"\s*:\s*" + LITERAL, source):
            keys.setdefault(to_key(m.group(1)), path.relative_to(ROOT))
            keys.setdefault(to_key(m.group(2)), path.relative_to(ROOT))
        # Keys picked by a condition, as in subtitle: flag ? "A" : "B" or
        # subtitle: flag ? "A" : nil, and Picker(title ?? "A").
        for m in re.finditer(r"subtitle:[^\n]*\?\s*" + LITERAL + r"\s*:\s*(?:nil|" + LITERAL + r")", source):
            keys.setdefault(to_key(m.group(1)), path.relative_to(ROOT))
            if m.group(2) is not None:
                keys.setdefault(to_key(m.group(2)), path.relative_to(ROOT))
        for m in re.finditer(r"Picker\([^\n]*\?\?\s*" + LITERAL, source):
            keys.setdefault(to_key(m.group(1)), path.relative_to(ROOT))
    for key in EXTRA:
        keys.setdefault(key, "extra")
    def has_words(key):
        stripped = key.replace("%lld", "").replace("%@", "").replace("%%", "")
        return re.search(r"[^\W\d_]", stripped) is not None

    return {k: v for k, v in keys.items() if k not in IGNORE and has_words(k)}


def parse_strings(path):
    table = {}
    pattern = re.compile(r'^\s*' + LITERAL + r'\s*=\s*' + LITERAL + r'\s*;\s*$', re.M)
    for m in pattern.finditer(path.read_text(encoding="utf-8")):
        key = m.group(1).replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
        table[key] = m.group(2)
    return table


def main():
    keys = extract()
    if "--print-keys" in sys.argv:
        for key in sorted(keys):
            print(key)
        return 0
    status = 0
    for strings in sorted(ROOT.glob("Resources/*.lproj/Localizable.strings")):
        lang = strings.parent.name
        if lang == "en.lproj":
            continue
        table = parse_strings(strings)
        missing = sorted(k for k in keys if k not in table)
        unused = sorted(k for k in table if k not in keys)
        for key in missing:
            print(f"{lang}: missing translation for \"{key}\" ({keys[key]})")
        for key in unused:
            print(f"{lang}: unused key \"{key}\"")
        if missing:
            status = 1
        print(f"{lang}: {len(table)} translations, {len(missing)} missing, {len(unused)} unused")
    return status


if __name__ == "__main__":
    sys.exit(main())
