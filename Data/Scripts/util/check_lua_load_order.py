import os
import re
from collections import defaultdict

# === CONFIG ===
SCRIPT_DIR = "E:/SteamLibrary/steamapps/common/KingdomComeDeliverance2/Mods/sanitasintenebris/Data/Scripts"
IGNORED_MODULES = {"System", "Script", "Config", "Loaded", "EnvironmentModule", "XGenAIModule"}

# === REGEX PATTERNS ===
reload_pattern = re.compile(r'Script\.ReloadScript\("([^"]+)"\)')
define_pattern = re.compile(r'SanitasInTenebris\.([a-zA-Z0-9_]+)\s*=\s*\{')
func_define_pattern = re.compile(r'function\s+SanitasInTenebris\.([a-zA-Z0-9_]+)\s*\(')
use_pattern = re.compile(r'\b([A-Z][a-zA-Z0-9_]*)[.:]')  # matches e.g. BuffLogic:Func, Utils.Log

# === DATA STRUCTURES ===
load_order = []
definitions = {}
usages = defaultdict(set)

# === SCAN FILES ===
for root, _, files in os.walk(SCRIPT_DIR):
    for file in files:
        if not file.endswith(".lua"):
            continue

        full_path = os.path.join(root, file)
        rel_path = os.path.relpath(full_path, SCRIPT_DIR).replace("\\", "/")

        with open(full_path, encoding="utf-8") as f:
            lines = f.readlines()

        for line in lines:
            if reload_match := reload_pattern.search(line):
                load_order.append(reload_match.group(1))

            if def_match := define_pattern.search(line):
                definitions[def_match.group(1)] = rel_path

            if func_match := func_define_pattern.search(line):
                definitions[func_match.group(1)] = rel_path

            for symbol in use_pattern.findall(line):
                if symbol not in definitions and symbol not in IGNORED_MODULES:
                    usages[symbol].add(rel_path)

# === REPORT ===
print("\n=== MODULE USAGE CHECK ===\n")
any_issues = False

for module in sorted(usages.keys()):
    usage_files = sorted(usages[module])
    defined_in = definitions.get(module)

    if not defined_in:
        for f in usage_files:
            print(f"❌ Used module '{module}' in '{f}' but never defined or imported")
            any_issues = True
    else:
        for f in usage_files:
            if defined_in in load_order and f in load_order:
                if load_order.index(defined_in) > load_order.index(f):
                    print(f"❌ Module '{module}' used in '{f}' before it's loaded from '{defined_in}'")
                    any_issues = True
            elif f not in load_order:
                print(f"⚠️ Module '{module}' used in '{f}', but '{f}' is not in load_order (maybe not ReloadScript-ed?)")
                any_issues = True

if not any_issues:
    print("✅ No issues found.\n")
else:
    print("\n⚠️ Check complete with warnings or errors.\n")
