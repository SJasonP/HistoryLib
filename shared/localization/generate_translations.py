#!/usr/bin/env python3
"""Generate HistoryLib platform resources from the English source strings."""

from __future__ import annotations

import concurrent.futures
import json
import plistlib
import re
import shutil
import threading
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APPLE_CATALOG = ROOT / "platforms/apple/HistoryLib/Localizable.xcstrings"
APPLE_INFO = ROOT / "platforms/apple/HistoryLib/Info.plist"
APPLE_SETTINGS = ROOT / "platforms/apple/HistoryLib/Settings.bundle"
ANDROID_RES = ROOT / "platforms/android/app/src/main/res"
WINDOWS_RES = ROOT / "platforms/windows/Resources"
CACHE_PATH = Path("/tmp/historylib-google-translation-cache.json")

TARGETS = {"ar": "ar", "fr": "fr", "ru": "ru", "es": "es"}
APPLE_LOCALES = ("en-US", "zh-Hans", *TARGETS)
PLACEHOLDER_RE = re.compile(
    r"%(?:\d+\$)?(?:lld|ld|llu|lu|[a-zA-Z@])|\\n|\n|HH:mm:ss|yyyy-MM-dd"
)
OVERRIDES = {
    "ar": {
        "HistoryLib": "HistoryLib",
        "OK": "حسنًا",
        "Cancel": "إلغاء",
        "Delete": "حذف",
        "Manage": "إدارة",
        "Back": "رجوع",
        "Help": "مساعدة",
        "Import": "استيراد",
        "Export": "تصدير",
        "Library": "المكتبة",
        "Cache": "ذاكرة التخزين المؤقت",
        "None": "لا شيء",
        "Open link on tap": "فتح الرابط عند النقر",
        "Defaults to the full record range.": "النطاق الافتراضي هو نطاق السجلات بالكامل.",
        "Safari ZIP": "أرشيف Safari بصيغة ZIP",
        "Safari layout": "تخطيط Safari",
        "%1$s; %2$s.": "%1$s؛ %2$s.",
    },
    "fr": {
        "HistoryLib": "HistoryLib",
        "OK": "OK",
        "Back": "Retour",
        "Archive password": "Mot de passe de l’archive",
        "Reading": "Lecture",
        "Writing": "Écriture",
    },
    "ru": {
        "HistoryLib": "HistoryLib",
        "OK": "ОК",
        "Summary": "Сводка",
        "Manage": "Управление",
        "None": "Нет",
        "Writing": "Запись",
        "Working… (%1$s)": "Выполняется… (%1$s)",
        "Safari ZIP": "Архив Safari ZIP",
        "Safari layout": "Структура Safari",
    },
    "es": {
        "HistoryLib": "HistoryLib",
        "OK": "Aceptar",
        "Delete": "Eliminar",
        "Manage": "Gestionar",
        "Cache": "Caché",
        "Single file": "Archivo único",
        "Detecting": "Detección",
        "Reading": "Lectura",
        "Validating": "Validación",
        "Writing": "Escritura",
        "Merging": "Fusión",
        "Cleaning up": "Limpieza",
        "By day": "Por día",
        "Confirm password": "Confirmar contraseña",
        "No history yet. Import Safari, Chrome Takeout, or HistoryLib data from Manage.":
            "Aún no hay historial. Importe datos de Safari, Chrome Takeout o HistoryLib desde Gestionar.",
        "Safari layout": "Diseño de Safari",
    },
}
ANDROID_PLURALS = {
    "zh-rCN": {
        "manage_import_done_imported": {"other": "已导入 %1$d 条记录"},
        "manage_import_done_skipped": {"other": "跳过 %1$d 条记录"},
        "manage_export_done": {"other": "已导出 %1$d 条记录。"},
        "manage_batch_preview": {"other": "匹配记录数：%1$d"},
        "manage_delete_confirm_body": {"other": "将永久删除 %1$d 条记录，且无法撤销。"},
    },
    "ar": {
        "manage_import_done_imported": {
            "zero": "لم يتم استيراد أي سجلات",
            "one": "تم استيراد سجل واحد",
            "two": "تم استيراد سجلين",
            "few": "تم استيراد %1$d سجلات",
            "many": "تم استيراد %1$d سجلًا",
            "other": "تم استيراد %1$d سجل",
        },
        "manage_import_done_skipped": {
            "zero": "لم يتم تخطي أي سجلات",
            "one": "تم تخطي سجل واحد",
            "two": "تم تخطي سجلين",
            "few": "تم تخطي %1$d سجلات",
            "many": "تم تخطي %1$d سجلًا",
            "other": "تم تخطي %1$d سجل",
        },
        "manage_export_done": {
            "zero": "لم يتم تصدير أي سجلات.",
            "one": "تم تصدير سجل واحد.",
            "two": "تم تصدير سجلين.",
            "few": "تم تصدير %1$d سجلات.",
            "many": "تم تصدير %1$d سجلًا.",
            "other": "تم تصدير %1$d سجل.",
        },
        "manage_batch_preview": {
            "zero": "لا توجد سجلات مطابقة",
            "one": "سجل مطابق واحد",
            "two": "سجلان متطابقان",
            "few": "%1$d سجلات مطابقة",
            "many": "%1$d سجلًا مطابقًا",
            "other": "%1$d سجل مطابق",
        },
        "manage_delete_confirm_body": {
            "zero": "لن يتم حذف أي سجلات.",
            "one": "سيتم حذف سجل واحد نهائيًا ولا يمكن التراجع عن ذلك.",
            "two": "سيتم حذف سجلين نهائيًا ولا يمكن التراجع عن ذلك.",
            "few": "سيتم حذف %1$d سجلات نهائيًا ولا يمكن التراجع عن ذلك.",
            "many": "سيتم حذف %1$d سجلًا نهائيًا ولا يمكن التراجع عن ذلك.",
            "other": "سيتم حذف %1$d سجل نهائيًا ولا يمكن التراجع عن ذلك.",
        },
    },
    "fr": {
        "manage_import_done_imported": {
            "one": "%1$d enregistrement importé",
            "other": "%1$d enregistrements importés",
        },
        "manage_import_done_skipped": {
            "one": "%1$d enregistrement ignoré",
            "other": "%1$d enregistrements ignorés",
        },
        "manage_export_done": {
            "one": "%1$d enregistrement exporté.",
            "other": "%1$d enregistrements exportés.",
        },
        "manage_batch_preview": {
            "one": "Enregistrement correspondant : %1$d",
            "other": "Enregistrements correspondants : %1$d",
        },
        "manage_delete_confirm_body": {
            "one": "Cette opération supprimera définitivement %1$d enregistrement et ne pourra pas être annulée.",
            "other": "Cette opération supprimera définitivement %1$d enregistrements et ne pourra pas être annulée.",
        },
    },
    "ru": {
        "manage_import_done_imported": {
            "one": "Импортирована %1$d запись",
            "few": "Импортировано %1$d записи",
            "many": "Импортировано %1$d записей",
            "other": "Импортировано %1$d записи",
        },
        "manage_import_done_skipped": {
            "one": "пропущена %1$d запись",
            "few": "пропущено %1$d записи",
            "many": "пропущено %1$d записей",
            "other": "пропущено %1$d записи",
        },
        "manage_export_done": {
            "one": "Экспортирована %1$d запись.",
            "few": "Экспортировано %1$d записи.",
            "many": "Экспортировано %1$d записей.",
            "other": "Экспортировано %1$d записи.",
        },
        "manage_batch_preview": {
            "one": "Найдена %1$d запись",
            "few": "Найдено %1$d записи",
            "many": "Найдено %1$d записей",
            "other": "Найдено %1$d записи",
        },
        "manage_delete_confirm_body": {
            "one": "%1$d запись будет удалена без возможности восстановления.",
            "few": "%1$d записи будут удалены без возможности восстановления.",
            "many": "%1$d записей будут удалены без возможности восстановления.",
            "other": "%1$d записи будут удалены без возможности восстановления.",
        },
    },
    "es": {
        "manage_import_done_imported": {
            "one": "%1$d registro importado",
            "other": "%1$d registros importados",
        },
        "manage_import_done_skipped": {
            "one": "%1$d registro omitido",
            "other": "%1$d registros omitidos",
        },
        "manage_export_done": {
            "one": "%1$d registro exportado.",
            "other": "%1$d registros exportados.",
        },
        "manage_batch_preview": {
            "one": "Registro coincidente: %1$d",
            "other": "Registros coincidentes: %1$d",
        },
        "manage_delete_confirm_body": {
            "one": "Se eliminará permanentemente %1$d registro y no se podrá deshacer.",
            "other": "Se eliminarán permanentemente %1$d registros y no se podrá deshacer.",
        },
    },
}
APPLE_PLURALS = {
    "Delete %lld Records": {
        "en": {"one": "Delete %lld Record", "other": "Delete %lld Records"},
        "en-US": {"one": "Delete %lld Record", "other": "Delete %lld Records"},
        "fr": {"one": "Supprimer %lld enregistrement", "other": "Supprimer %lld enregistrements"},
        "es": {"one": "Eliminar %lld registro", "other": "Eliminar %lld registros"},
    },
    "Failed files: %lld": {
        "en": {"one": "Failed file: %lld", "other": "Failed files: %lld"},
        "en-US": {"one": "Failed file: %lld", "other": "Failed files: %lld"},
        "fr": {"one": "Fichier en échec : %lld", "other": "Fichiers en échec : %lld"},
        "es": {"one": "Archivo fallido: %lld", "other": "Archivos fallidos: %lld"},
    },
    "Imported records: %lld": {
        "en": {"one": "Imported record: %lld", "other": "Imported records: %lld"},
        "en-US": {"one": "Imported record: %lld", "other": "Imported records: %lld"},
        "fr": {"one": "Enregistrement importé : %lld", "other": "Enregistrements importés : %lld"},
        "es": {"one": "Registro importado: %lld", "other": "Registros importados: %lld"},
    },
    "Scanned files: %lld": {
        "en": {"one": "Scanned file: %lld", "other": "Scanned files: %lld"},
        "en-US": {"one": "Scanned file: %lld", "other": "Scanned files: %lld"},
        "fr": {"one": "Fichier analysé : %lld", "other": "Fichiers analysés : %lld"},
        "es": {"one": "Archivo analizado: %lld", "other": "Archivos analizados: %lld"},
    },
    "Skipped records: %lld": {
        "en": {"one": "Skipped record: %lld", "other": "Skipped records: %lld"},
        "en-US": {"one": "Skipped record: %lld", "other": "Skipped records: %lld"},
        "fr": {"one": "Enregistrement ignoré : %lld", "other": "Enregistrements ignorés : %lld"},
        "es": {"one": "Registro omitido: %lld", "other": "Registros omitidos: %lld"},
    },
    "Valid files: %lld": {
        "en": {"one": "Valid file: %lld", "other": "Valid files: %lld"},
        "en-US": {"one": "Valid file: %lld", "other": "Valid files: %lld"},
        "fr": {"one": "Fichier valide : %lld", "other": "Fichiers valides : %lld"},
        "es": {"one": "Archivo válido: %lld", "other": "Archivos válidos: %lld"},
    },
    "iCloud sync is on.\nRecords on this device: %lld\n%@": {
        "en": {
            "one": "iCloud sync is on.\nRecord on this device: %lld\n%@",
            "other": "iCloud sync is on.\nRecords on this device: %lld\n%@",
        },
        "en-US": {
            "one": "iCloud sync is on.\nRecord on this device: %lld\n%@",
            "other": "iCloud sync is on.\nRecords on this device: %lld\n%@",
        },
        "fr": {
            "one": "La synchronisation iCloud est activée.\nEnregistrement sur cet appareil : %lld\n%@",
            "other": "La synchronisation iCloud est activée.\nEnregistrements sur cet appareil : %lld\n%@",
        },
        "es": {
            "one": "La sincronización de iCloud está activada.\nRegistro en este dispositivo: %lld\n%@",
            "other": "La sincronización de iCloud está activada.\nRegistros en este dispositivo: %lld\n%@",
        },
    },
}
APPLE_COUNT_NEUTRAL = {
    "ar": {
        "Delete %lld Records": "حذف السجلات (%lld)",
        "Failed files: %lld": "عدد الملفات الفاشلة: %lld",
        "Imported records: %lld": "عدد السجلات المستوردة: %lld",
        "Scanned files: %lld": "عدد الملفات المفحوصة: %lld",
        "Skipped records: %lld": "عدد السجلات المتخطاة: %lld",
        "Valid files: %lld": "عدد الملفات الصالحة: %lld",
        "iCloud sync is on.\nRecords on this device: %lld\n%@":
            "مزامنة iCloud قيد التشغيل.\nعدد السجلات على هذا الجهاز: %lld\n%@",
    },
    "ru": {
        "Delete %lld Records": "Удалить записи (%lld)",
        "Failed files: %lld": "Файлов с ошибками: %lld",
        "Imported records: %lld": "Импортировано записей: %lld",
        "Scanned files: %lld": "Проверено файлов: %lld",
        "Skipped records: %lld": "Пропущено записей: %lld",
        "Valid files: %lld": "Допустимых файлов: %lld",
        "iCloud sync is on.\nRecords on this device: %lld\n%@":
            "Синхронизация iCloud включена.\nЗаписей на этом устройстве: %lld\n%@",
    },
}
for plural_locale in ("fr", "es"):
    for plural_forms in ANDROID_PLURALS[plural_locale].values():
        plural_forms["many"] = plural_forms["other"]
    for localized_forms in APPLE_PLURALS.values():
        localized_forms[plural_locale]["many"] = localized_forms[plural_locale]["other"]
SETTINGS_LINE_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
cache_lock = threading.Lock()


def load_cache() -> dict[str, str]:
    if not CACHE_PATH.exists():
        return {}
    return json.loads(CACHE_PATH.read_text(encoding="utf-8"))


CACHE = load_cache()


def protect(text: str) -> tuple[str, list[str]]:
    values: list[str] = []

    def replace(match: re.Match[str]) -> str:
        values.append(match.group(0))
        return f"{{{len(values) - 1}}}"

    return PLACEHOLDER_RE.sub(replace, text), values


def restore(text: str, values: list[str]) -> str:
    for index, value in enumerate(values):
        token = f"{{{index}}}"
        if token not in text:
            raise ValueError(f"Translation lost protected token {token}: {text}")
        text = text.replace(token, value)
    return text


def google_translate(text: str, locale: str) -> str:
    if not text.strip() or not re.search(r"[A-Za-z]", text):
        return text
    cache_key = f"v2\0{locale}\0{text}"
    with cache_lock:
        if cache_key in CACHE:
            translated = OVERRIDES.get(locale, {}).get(text, CACHE[cache_key])
            return translated.replace("...", "…")

    protected, values = protect(text)
    query = urllib.parse.urlencode(
        {"client": "gtx", "sl": "en", "tl": locale, "dt": "t", "q": protected},
    )
    url = f"https://translate.googleapis.com/translate_a/single?{query}"
    for attempt in range(5):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "HistoryLib-Localization/1.0"})
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.load(response)
            translated = "".join(part[0] for part in payload[0] if part and part[0])
            translated = restore(translated, values)
            translated = OVERRIDES.get(locale, {}).get(text, translated)
            translated = translated.replace("...", "…")
            with cache_lock:
                CACHE[cache_key] = translated
            return translated
        except Exception:
            if attempt == 4:
                raise
            time.sleep(1.5 * (attempt + 1))
    raise AssertionError("unreachable")


def translate_all(strings: set[str]) -> dict[str, dict[str, str]]:
    jobs = [(locale, text) for locale in TARGETS for text in sorted(strings)]
    result: dict[str, dict[str, str]] = {locale: {} for locale in TARGETS}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        future_map = {
            executor.submit(google_translate, text, locale): (locale, text)
            for locale, text in jobs
        }
        for index, future in enumerate(concurrent.futures.as_completed(future_map), 1):
            locale, text = future_map[future]
            result[locale][text] = future.result()
            if index % 25 == 0:
                CACHE_PATH.write_text(
                    json.dumps(CACHE, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )
            if index % 100 == 0:
                print(f"Translated {index}/{len(jobs)} strings", flush=True)
    CACHE_PATH.write_text(
        json.dumps(CACHE, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return result


def android_strings(path: Path) -> dict[str, str]:
    root = ET.parse(path).getroot()
    return {item.attrib["name"]: item.text or "" for item in root.findall("string")}


def write_android(locale: str, source_path: Path, translations: dict[str, str]) -> None:
    tree = ET.parse(source_path)
    for item in tree.getroot().findall("string"):
        item.text = translations[item.text or ""].replace("'", "\\'")
    apply_android_plurals(tree.getroot(), locale)
    ET.indent(tree, space="    ")
    output = ANDROID_RES / f"values-{locale}" / "strings.xml"
    output.parent.mkdir(parents=True, exist_ok=True)
    tree.write(output, encoding="utf-8", xml_declaration=True)


def apply_android_plurals(root: ET.Element, locale: str) -> None:
    forms_by_name = ANDROID_PLURALS.get(locale)
    if not forms_by_name:
        return
    for item in root.findall("string"):
        if item.attrib["name"] in forms_by_name:
            root.remove(item)
    existing = {item.attrib["name"]: item for item in root.findall("plurals")}
    for name, forms in forms_by_name.items():
        plural = existing.get(name)
        if plural is None:
            plural = ET.SubElement(root, "plurals", {"name": name})
        plural.clear()
        plural.attrib["name"] = name
        for quantity, value in forms.items():
            item = ET.SubElement(plural, "item", {"quantity": quantity})
            item.text = value.replace("'", "\\'")


def parse_settings(path: Path) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = SETTINGS_LINE_RE.match(line)
        if match:
            rows.append((match.group(1), match.group(2)))
    return rows


def quote_strings(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def write_settings(locale: str, rows: list[tuple[str, str]], translations: dict[str, str]) -> None:
    output = APPLE_SETTINGS / f"{locale}.lproj" / "Root.strings"
    output.parent.mkdir(parents=True, exist_ok=True)
    content = "\n".join(f'"{quote_strings(key)}" = "{quote_strings(translations[value])}";' for key, value in rows)
    output.write_text(content + "\n", encoding="utf-8")


def source_android_plurals(path: Path) -> dict[str, dict[str, str]]:
    root = ET.parse(path).getroot()
    return {
        plural.attrib["name"]: {
            item.attrib["quantity"]: item.text or ""
            for item in plural.findall("item")
        }
        for plural in root.findall("plurals")
    }


def write_resw(
    locale: str,
    values: dict[str, str],
    plural_values: dict[str, dict[str, str]],
) -> None:
    root = ET.Element("root")
    headers = {
        "resmimetype": "text/microsoft-resx",
        "version": "2.0",
        "reader": "System.Resources.ResXResourceReader, System.Windows.Forms, "
        "Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089",
        "writer": "System.Resources.ResXResourceWriter, System.Windows.Forms, "
        "Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089",
    }
    for name, value in headers.items():
        header = ET.SubElement(root, "resheader", {"name": name})
        ET.SubElement(header, "value").text = value
    for name, value in values.items():
        data = ET.SubElement(
            root,
            "data",
            {
                "name": name,
                "{http://www.w3.org/XML/1998/namespace}space": "preserve",
            },
        )
        ET.SubElement(data, "value").text = value
    for name, forms in plural_values.items():
        fallback = forms["other"]
        for quantity in ("zero", "one", "two", "few", "many", "other"):
            data = ET.SubElement(
                root,
                "data",
                {
                    "name": f"{name}.{quantity.title()}",
                    "{http://www.w3.org/XML/1998/namespace}space": "preserve",
                },
            )
            ET.SubElement(data, "value").text = forms.get(quantity, fallback)
    ET.indent(root, space="  ")
    output = WINDOWS_RES / locale / "Resources.resw"
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(output, encoding="utf-8", xml_declaration=True)


def main() -> None:
    android_source_path = ANDROID_RES / "values/strings.xml"
    android_source = android_strings(android_source_path)
    android_source_plurals = source_android_plurals(android_source_path)
    settings_rows = parse_settings(APPLE_SETTINGS / "en.lproj/Root.strings")
    catalog = json.loads(APPLE_CATALOG.read_text(encoding="utf-8"))
    apple_sources = {
        key for key, value in catalog["strings"].items()
        if value.get("shouldTranslate", True) and key.strip()
    }
    sources = set(android_source.values()) | {value for _, value in settings_rows} | apple_sources
    translations = translate_all(sources)

    android_en_us = ANDROID_RES / "values-en-rUS/strings.xml"
    android_en_us.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(android_source_path, android_en_us)
    zh_tree = ET.parse(ANDROID_RES / "values-zh-rCN/strings.xml")
    for item in zh_tree.getroot().findall("string"):
        if item.attrib["name"] == "manage_import_done":
            item.text = "%1$s；%2$s。"
    apply_android_plurals(zh_tree.getroot(), "zh-rCN")
    ET.indent(zh_tree, space="    ")
    zh_tree.write(
        ANDROID_RES / "values-zh-rCN/strings.xml",
        encoding="utf-8",
        xml_declaration=True,
    )
    android_zh = android_strings(ANDROID_RES / "values-zh-rCN/strings.xml")
    for locale in TARGETS:
        write_android(locale, android_source_path, translations[locale])

    for key, entry in catalog["strings"].items():
        if not entry.get("shouldTranslate", True) or not key.strip():
            continue
        localizations = entry.setdefault("localizations", {})
        localizations["en-US"] = {
            "stringUnit": {"state": "translated", "value": key},
        }
        if not localizations.get("zh-Hans", {}).get("stringUnit", {}).get("value"):
            localizations["zh-Hans"] = {
                "stringUnit": {"state": "translated", "value": key},
            }
        for locale in TARGETS:
            localizations[locale] = {
                "stringUnit": {"state": "translated", "value": translations[locale][key]},
            }
    for key, localized_forms in APPLE_PLURALS.items():
        localizations = catalog["strings"][key].setdefault("localizations", {})
        for locale, forms in localized_forms.items():
            localizations[locale] = {
                "variations": {
                    "plural": {
                        quantity: {
                            "stringUnit": {"state": "translated", "value": value},
                        }
                        for quantity, value in forms.items()
                    },
                },
            }
        for locale, values in APPLE_COUNT_NEUTRAL.items():
            localizations[locale] = {
                "stringUnit": {"state": "translated", "value": values[key]},
            }
    APPLE_CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    write_settings("en-US", settings_rows, {value: value for _, value in settings_rows})
    for locale in TARGETS:
        write_settings(locale, settings_rows, translations[locale])

    with APPLE_INFO.open("rb") as stream:
        info = plistlib.load(stream)
    info["CFBundleLocalizations"] = ["en", *APPLE_LOCALES]
    with APPLE_INFO.open("wb") as stream:
        plistlib.dump(info, stream, sort_keys=False)

    windows_locales = {
        "en-US": (android_source, android_source_plurals),
        "zh-Hans": (android_zh, ANDROID_PLURALS["zh-rCN"]),
        **{
            locale: (
                {name: translations[locale][value] for name, value in android_source.items()},
                ANDROID_PLURALS[locale],
            )
            for locale in TARGETS
        },
    }
    for locale, (values, plural_values) in windows_locales.items():
        write_resw(locale, values, plural_values)


if __name__ == "__main__":
    main()
