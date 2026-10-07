#!/usr/bin/env python3
"""Compila um String Catalog (.xcstrings) em <idioma>.lproj/<Tabela>.strings.

Alternativa ao `xcrun xcstringstool compile` para quem só tem as Command Line
Tools (elas trazem o python3, mas não o xcstringstool, que vem com o Xcode).
Cobre o que o MAC-LIMPO usa: valores simples (stringUnit), sem variações de
plural ou de dispositivo. Os .strings saem em formato plist XML, que o
Foundation lê igual aos .strings de texto.

Uso: compile-xcstrings.py <catalogo.xcstrings> <pasta Resources>
"""
import json
import os
import plistlib
import sys

catalog_path, resources = sys.argv[1], sys.argv[2]
table = os.path.splitext(os.path.basename(catalog_path))[0]
with open(catalog_path, encoding="utf-8") as f:
    catalog = json.load(f)

tables = {}
for key, entry in catalog.get("strings", {}).items():
    for language, localization in entry.get("localizations", {}).items():
        unit = localization.get("stringUnit")
        if not unit or unit.get("state") not in ("translated", None):
            continue
        tables.setdefault(language, {})[key] = unit["value"]

for language, strings in tables.items():
    folder = os.path.join(resources, f"{language}.lproj")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, f"{table}.strings"), "wb") as f:
        plistlib.dump(strings, f, fmt=plistlib.FMT_XML, sort_keys=True)
