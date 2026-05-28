# Detaillierte technische Dokumentation für den HP-WMI-Treiber (hp-wmi.c)

Dieses Dokument enthält eine detaillierte Analyse und ein technisches Referenzhandbuch für den Kernel-Treiber `hp-wmi.c`, der die Hardwaresteuerung, das thermische Management, die Lüftersteuerung und spezielle Tastatur-Hotkeys für HP-Laptops (insbesondere die Serien **OMEN** und **Victus**) im Linux-Kernel verwaltet.

---

## 1. Einführung und Treiberarchitektur

`hp-wmi.c` ist ein Kernel-Treiber, der die **WMI-Schnittstelle (Windows Management Instrumentation)** von HP-Geräten für Linux verfügbar macht. Der Treiber verwendet zwei primäre WMI-GUIDs (Globally Unique Identifiers), um Hardwarefunktionen zu steuern und ACPI-Ereignisse abzufangen:

| GUID-Makro | GUID-Zeichenfolgewert | Funktion / Zweck |
| :--- | :--- | :--- |
| `HPWMI_EVENT_GUID` | `"95F24279-4D7B-4334-9387-ACCDC67EF61C"` | Meldet Ereignisse wie Tastatur-Hotkeys, Deckelschalter und Netzteil-Verbindungsereignisse. |
| `HPWMI_BIOS_GUID` | `"5FB7F034-2C63-45E9-BE91-3D44E2C707E4"` | Lesen/Schreiben von Lüfterdrehzahlen, Temperaturen, Grafikkartenmodi und thermischen Profilen. |

Der Treiber kommuniziert mit dem BIOS und dem **eingebetteten Controller (EC - Embedded Controller)**, indem er die Funktion `hp_wmi_perform_query` aufruft, um den Hardwarestatus zu lesen (`HPWMI_READ`) oder neue Einstellungen zu schreiben (`HPWMI_WRITE` / `HPWMI_GM`).

---

## 2. Register-Offsets des eingebetteten Controllers (EC)

Der Zugriff auf bestimmte Register (Offsets) im eingebetteten Controller (EC) des Geräts dient dazu, thermische Profile zu lesen und zu schreiben. Diese Offsets sind unter `enum hp_ec_offsets` definiert.

### EC-Offsets und Beschreibungen

| EC-Offset-Name | Hex-Adresse | Beschreibung und Zweck |
| :--- | :---: | :--- |
| `HP_EC_OFFSET_UNKNOWN` | `0x00` | **Unbekanntes EC-Layout:** Auf Hauptplatinen mit diesem Offset ist das DMI-basierte Auslesen des thermischen Profils deaktiviert. Beim Kaltstart wird standardmäßig der Modus `BALANCED` gewählt. |
| `HP_NO_THERMAL_PROFILE_OFFSET` | `0x01` | **Kein thermisches Profil:** Umgeht das Auslesen des thermischen Profils über den EC vollständig. Wird bei bestimmten neueren Modellen mit fehlerhaften ACPI-Tabellen verwendet, um Systemabstürze zu verhindern. |
| `HP_VICTUS_S_EC_THERMAL_PROFILE_OFFSET` | `0x59` | **Thermische Profiladresse der Victus S-Serie:** Die primäre EC-Speicherzelle, die den thermischen Profilstatus auf modernen Victus 16- (r- und s-Serien) und einigen Omen V1-Hauptplatinen speichert. |
| `HP_OMEN_EC_THERMAL_PROFILE_FLAGS_OFFSET` | `0x62` | **Adresse der thermischen Profilflags für Omen:** Spezielle Flag-Zelle auf Omen-Geräten, um den Turbo-Modus zu aktivieren (`0x04`) oder den EC-Timer zu deaktivieren (`0x02`). |
| `HP_OMEN_EC_THERMAL_PROFILE_TIMER_OFFSET` | `0x63` | **Adresse des thermischen Profil-Timers für Omen:** Die vom Omen Gaming Hub verwaltete EC-Timer-Zelle. Wenn sie Null erreicht, setzt der EC das Profil automatisch auf "Balanced" zurück. |
| `HP_OMEN_EC_THERMAL_PROFILE_OFFSET` | `0x95` | **Klassische thermische Profiladresse für Omen:** Das Profilstatusregister, das in älteren Omen- (V1 Legacy) und einigen älteren Victus-Modellen verwendet wird. |

---

## 3. Hauptplatinen (DMI-Boards) und Offset-Zuordnungen

Der Treiber liest die Kennung der Systemhauptplatine (**DMI Board Name**), um zu bestimmen, welche EC-Offsets und thermischen Parameter angewendet werden müssen.

### 3.1. Zuordnungstabelle der Hauptplatinen-Parameter für Victus & Omen

Die im Array `victus_s_thermal_profile_boards` definierten Hauptplatinen sind zusammen mit ihren zugewiesenen thermischen Parametern und EC-Offsets im Folgenden aufgeführt:

| Board-ID (DMI Board Name) | Zugeordnetes Laptop-Modell / -Serie | Struktur der thermischen Parameter | EC-Profil-Offset | Performance-Wert | Balanced-Wert | Low Power-Wert | Beschreibung / Sonderfälle |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **8A13** | OMEN by HP Laptop 16-b1xxx | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Hauptplatine mit dem klassischen Omen V1-Layout. |
| **8A4D** | HP Omen Serie | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Klassisches Omen V1-Layout. |
| **8BAB** | HP Omen Serie | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Omen-Hauptplatine mit dem modernen Offset `0x59`. |
| **8BBE** | HP Victus Serie | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Unbekanntes EC-Layout (0x00). Software-Plattformprofil-Caching wird verwendet. |
| **8BCA** | HP Omen Serie | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modernes Offset `0x59`. |
| **8BCD** | HP Omen Serie | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modernes Offset `0x59`. |
| **8BD4** | HP Victus Serie | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Unbekanntes EC-Layout (0x00). |
| **8BD5** | HP Victus Serie | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Unbekanntes EC-Layout (0x00). |
| **8C76** | HP Omen Serie | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modernes Offset `0x59`. |
| **8C77** | HP Omen Serie | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Modernes Omen-Modell mit klassischem Offset `0x95`. |
| **8C78** | HP Omen Serie | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modernes Offset `0x59`. |
| **8E35** | HP Omen Serie | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modernes Offset `0x59`. |
| **8C99** | HP Victus Serie | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Unbekanntes EC-Layout (0x00). |
| **8C9C** | HP Victus Serie (z. B. 16-s1034nf) | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Unbekanntes EC-Layout (0x00). Erfordert PL1/PL2-Aktualisierung beim Wechsel der Stromquelle. |
| **8D41** | HP Omen Max (z. B. 16-u0xxx) | `omen_v1_unknown_ec_thermal_params`| `0x00` | `0x31` | `0x30` | `0x30` | Omen V1-Layout mit unbekanntem EC-Offset. |
| **8D87** | HP Omen Serie | `omen_v1_no_ec_thermal_params` | `0x01` | `0x31` | `0x30` | `0x30` | Hauptplatine mit deaktiviertem EC-Auslesen. |
| **8BA9** | HP Omen Serie | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Klassisches Omen V1-Layout. |
| **8BAC** | HP Omen 16-wf0xxx | `omen_v1_no_ec_thermal_params` | `0x01` | `0x31` | `0x30` | `0x30` | **Kritischer ACPI-Fehler:** Die ACPI-Tabellen weisen eine fehlerhafte GETB-Hilfsfunktion auf (Fehler bei der Erstellung eines Felds der Länge Null), wodurch WMI-Abfragen abgebrochen werden. Das EC-Auslesen wird umgangen, um Systemaufhänger zu vermeiden. |
| **8BC2** | Victus by HP Gaming Laptop 16-r0xxx| `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Unbekanntes EC-Layout (0x00). |

---

### 3.2. Andere spezialisierte DMI-Board-Gruppen

#### Omen-Geräte mit thermischer Profilkompatibilität (`omen_thermal_profile_boards`)
Diese Platinennamen stammen aus der Kompatibilitätsliste des Omen Command Center und verwenden Omen-spezifische thermische Profilpfade:
> `84DA`, `84DB`, `84DC`, `8572`, `8573`, `8574`, `8575`, `8600`, `8601`, `8602`, `8603`, `8604`, `8605`, `8606`, `8607`, `860A`, `8746`, `8747`, `8748`, `8749`, `874A`, `8786`, `8787`, `8788`, `878A`, `878B`, `878C`, `87B5`, `886B`, `886C`, `88C8`, `88CB`, `88D1`, `88D2`, `88F4`, `88F5`, `88F6`, `88F7`, `88FD`, `88FE`, `88FF`, `8900`, `8901`, `8902`, `8912`, `8917`, `8918`, `8949`, `894A`, `89EB`, `8A15`, `8A42`, `8BAD`, `8BAC`, `8C77`, `8D41`, `8E35`, `8E41`, `8BA9`

#### Zum thermischen Profil V0 gezwungene Omen-Platinen (`omen_thermal_profile_force_v0_boards`)
Diese Platinen werden gezwungen, das thermische Omen-Profil in Version 0 zu verwenden, unabhängig von den vom BIOS zurückgegebenen Systemdesigndaten:
> `8607`, `8746`, `8747`, `8748`, `8749`, `874A`

#### Omen-Platinen mit EC-Timern (`omen_timed_thermal_profile_boards`)
Diese Geräte starten einen 120-Sekunden-EC-Timer, wenn der Performance-Modus aktiviert ist. Der Treiber setzt diesen Timer kontinuierlich zurück, um den Performance-Modus aktiv zu halten:
> `8A15`, `8A42`, `8BAD`

#### Platinen der Victus 16-d Serie (`victus_thermal_profile_boards`)
Modelle, die das Victus-Steuerungsschema für thermische Profile der ersten Generation nutzen:
> `88F8`, `8A25`

---

## 4. Thermische Profile und Hex-Zuordnungen

Die Linux-Schnittstelle `platform_profile` ordnet Benutzerprofile (Performance, Balanced usw.) den vom BIOS/EC erwarteten Hex-Codes zu. Diese Codes variieren je nach Gerätegeneration und -serie.

### 4.1. Klassische / Standard-HP-Profile
Definiert in `enum hp_thermal_profile`:

| Profilname | Hex-Wert | Linux-Profil | Beschreibung |
| :--- | :---: | :--- | :--- |
| `HP_THERMAL_PROFILE_PERFORMANCE` | `0x00` | `performance` | Maximales CPU/GPU-Leistungsbudget und aggressive Lüfterkurven. |
| `HP_THERMAL_PROFILE_DEFAULT` | `0x01` | `balanced` | Standardmäßige tägliche Nutzung, ausgewogene Leistung und Lautstärke. |
| `HP_THERMAL_PROFILE_COOL` | `0x02` | `cool` | Niedrigere Leistungsgrenzen, um die Oberflächentemperaturen des Laptops niedrig zu halten. |
| `HP_THERMAL_PROFILE_QUIET` | `0x03` | `quiet` | Minimales Lüftergeräusch durch reduzierte Leistungsgrenzen. |

### 4.2. HP Omen Profile

#### Omen V0 (Ältere Generation)
Definiert in `enum hp_thermal_profile_omen_v0`:

| Profilname | Hex-Wert | Linux-Profil |
| :--- | :---: | :--- |
| `HP_OMEN_V0_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` |
| `HP_OMEN_V0_THERMAL_PROFILE_PERFORMANCE`| `0x01` | `performance` |
| `HP_OMEN_V0_THERMAL_PROFILE_COOL` | `0x02` | `cool` |

#### Omen V1 (Moderne Generation)
Definiert in `enum hp_thermal_profile_omen_v1`:

| Profilname | Hex-Wert | Linux-Profil |
| :--- | :---: | :--- |
| `HP_OMEN_V1_THERMAL_PROFILE_DEFAULT` | `0x30` | `balanced` |
| `HP_OMEN_V1_THERMAL_PROFILE_PERFORMANCE`| `0x31` | `performance` |
| `HP_OMEN_V1_THERMAL_PROFILE_COOL` | `0x50` | `cool` |

### 4.3. HP Victus Profile

#### Standard Victus (16-d Serie)
Definiert in `enum hp_thermal_profile_victus`:

| Profilname | Hex-Wert | Linux-Profil |
| :--- | :---: | :--- |
| `HP_VICTUS_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` |
| `HP_VICTUS_THERMAL_PROFILE_PERFORMANCE` | `0x01` | `performance` |
| `HP_VICTUS_THERMAL_PROFILE_QUIET` | `0x03` | `quiet` |

#### Victus S-Serie (16-r und 16-s Serie)
Definieren in `enum hp_thermal_profile_victus_s`:

| Profilname | Hex-Wert | Linux-Profil |
| :--- | :---: | :--- |
| `HP_VICTUS_S_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` oder `low_power` (ECO)* |
| `HP_VICTUS_S_THERMAL_PROFILE_PERFORMANCE`| `0x01` | `performance` |

> [!NOTE]
> *Bei Victus S-Modellen werden sowohl das `Balanced`- als auch das `Low Power`-Profil auf `0x00` im EC abgebildet. Der Treiber unterscheidet zwischen ihnen, indem er die GPU-Leistungszustände (cTGP und PPAB) abfragt. Wenn beide deaktiviert sind, wird der Modus als `low_power` (ECO) gemeldet; wenn PPAB aktiv ist, wird er als `balanced` gemeldet.

---

## 5. Grafikkarten- & Leistungsgrenzensteuerung (GPU & CPU PL1/PL2)

Bei modernen Victus- und Omen-Laptops regeln thermische Profile nicht nur die Lüfterkurven, sondern auch die CPU- und GPU-Leistungsbudgets (TGP/TDP).

### 5.1. GPU-Leistungsmanagement (cTGP und PPAB)
Der Treiber verwaltet GPU-Leistungsgrenzen mit `HPWMI_SET_GPU_THERMAL_MODES_QUERY` (`0x22`). Die Struktur `struct victus_gpu_power_modes` steuert die folgenden Parameter:

| Parameter | Typ | Funktion / Verhalten |
| :--- | :--- | :--- |
| `ctgp_enable` | `u8` | **Configurable TGP:** Setzt die maximale Leistungsgrenze der Grafikkarte frei (z. B. 120W statt 80W). Im `Performance`-Modus auf `0x01` (aktiviert) gesetzt, andernfalls auf `0x00`. |
| `ppab_enable` | `u8` | **Dynamic Boost (PPAB):** Gleicht die dynamische Leistungsaufteilung zwischen CPU und GPU basierend auf der Arbeitslast aus. Im `Low Power`-Modus auf `0x00` (deaktiviert) gesetzt, in `Balanced` und `Performance` auf `0x01`. |
| `dstate` | `u8` | **GPU-Leistungspriorität:** Definiert die Priorität der Leistungsverteilung (Standard ist `1`, was 100 % Priorität entspricht). |
| `gpu_slowdown_temp` | `u8` | **GPU-Drosselungstemperatur:** Die aus dem BIOS ausgelesene Grenze für die thermische Drosselung, die beim Schreiben beibehalten wird. |

### 5.2. CPU-Leistungsgrenzen (PL1 und PL2)
Bei Hauptplatinen der Victus S-Serie werden die **PL1 (Langzeit-Leistungsgrenze)** und **PL2 (Kurzzeit-Leistungsgrenze)** der CPU über `HPWMI_SET_POWER_LIMITS_QUERY` (`0x29`) verwaltet:
* `pl2` muss immer größer oder gleich `pl1` sein (`pl2 >= pl1`).
* Bei Wechseln der Stromquelle (Einstecken/Ausstecken des Netzteils) wendet ein Notifier (`victus_s_powersource_event`) automatisch die Standard-Leistungsgrenzen wieder an (`HP_POWER_LIMIT_DEFAULT` -> `0x00`), um Leistungsblockaden im Akkubetrieb zu verhindern.

---

## 6. Erweiterte Lüftersteuerung (Hwmon-Framework)

Der Treiber kommuniziert mit dem Linux-Hardwareüberwachungssubsystem (`hwmon`), um Lüfterdrehzahlwerte bereitzustellen und manuelle Steuerungen zu ermöglichen.

### 6.1. Lüftersteuerungsmodi
Die manuelle und automatische Lüftersteuerung ist unter `enum pwm_modes` definiert:

| Modusname | Wert | Beschreibung |
| :--- | :---: | :--- |
| `PWM_MODE_MAX` | `0` | **Maximaler Lüfter:** Zwingt Lüfter dazu, mit 100 % Leistung zu laufen. |
| `PWM_MODE_MANUAL` | `1` | **Manuelle Steuerung:** Ermöglicht Benutzern, Ziel-Lüfterdrehzahlen (RPM) direkt über sysfs einzustellen. |
| `PWM_MODE_AUTO` | `2` | **Automatische EC-Steuerung:** Übergibt die Steuerung wieder an die internen thermischen Algorithmen des eingebetteten Controllers. |

### 6.2. Keep-Alive-Watchdog-Timer
Der eingebettete HP-Controller (EC) startet einen **120-Sekunden-Sicherheits-Timer**, wenn er in den manuellen Lüftermodus oder den maximalen Lüftermodus wechselt. Wenn innerhalb von 120 Sekunden keine WMI-Befehle empfangen werden, kehrt der EC aus Sicherheitsgründen in den automatischen Modus (`AUTO`) zurück.

Um dies zu verhindern, führt der Treiber einen Watchdog-Thread im Hintergrund aus (**Delayed Work - Keep Alive Watchdog**):
* Der Treiber gibt alle **90 Sekunden** (`KEEP_ALIVE_DELAY_SECS = 90`) eine Keep-Alive-Aktualisierung aus und schreibt den aktiven Modus und die Drehzahlen an den EC zurück.
* Dies setzt den 120-Sekunden-Sicherheits-Timer des EC kontinuierlich zurück und hält die manuelle Steuerung aktiv.
* Wenn der Benutzer zurück auf `AUTO` wechselt, wird der Watchdog-Thread abgebrochen (`cancel_delayed_work_sync`) und der EC übernimmt wieder die Kontrolle.

### 6.3. Struktur der Victus S-Lüftertabelle
Bei Laptops der Victus S-Serie werden die Grenzen der Lüfterdrehzahlen über `HPWMI_VICTUS_S_GET_FAN_TABLE_QUERY` (`0x2F`) aus dem BIOS ausgelesen:

```c
struct victus_s_fan_table_header {
    u8 unknown;
    u8 num_entries; // Anzahl der Stufeneinträge in der Lüfterkurve
} __packed;

struct victus_s_fan_table_entry {
    u8 cpu_rpm;     // CPU-Lüfterdrehzahl (Wert * 100 RPM)
    u8 gpu_rpm;     // GPU-Lüfterdrehzahl (Wert * 100 RPM)
    u8 unknown;
} __packed;
```
* **Mindestgrenzen:** Aus dem ersten Schritt in der Tabelle extrahiert (`entries[0].cpu_rpm`).
* **Maximalgrenzen:** Aus dem letzten Schritt extrahiert (`entries[num_entries-1]`).
* **Sicherheits-Fallback:** Wenn die Lüfterabfrage nicht unterstützt wird oder fehlerhaft ist, registriert der Treiber automatisch eine sichere **5000-RPM-Fallback-Tabelle** (`setup_fallback_fan_limits`) anstelle eines Ladefehlers.

---

## 7. WMI-Ereignisbenachrichtigungen (Event-IDs)

ACPI-Benachrichtigungen über `HPWMI_EVENT_GUID` und die Reaktion des Treibers:

| Event-ID (Hex) | Ereignisname | Auslösebedingung & Treiberverhalten |
| :---: | :--- | :--- |
| `0x01` | `HPWMI_DOCK_EVENT` | Docking/Undocking oder Wechsel in den Tablet-Modus. Gemeldet über `input_report_switch`. |
| `0x02` | `HPWMI_PARK_HDD` | Erschütterungssensor-Alarm; parkt den Lese-/Schreibkopf der Festplatte zum Datenschutz. |
| `0x03` | `HPWMI_SMART_ADAPTER` | Warnung bei inkompatiblem oder unterdimensioniertem Netzteil. |
| `0x04` | `HPWMI_BEZEL_BUTTON` | Spezielle Tastenbetätigungen am Bildschirmrand; als Tastaturereignis gemeldet. |
| `0x05` | `HPWMI_WIRELESS` | Umschalten des drahtlosen Status (Wi-Fi, Bluetooth, WWAN); aktualisiert rfkill-Zustände. |
| `0x06` | `HPWMI_CPU_BATTERY_THROTTLE` | CPU-Leistungsgrenzen aus Gründen der 3-Zellen-Batteriesicherheit reduziert. |
| `0x0A` | `HPWMI_COOLSENSE_SYSTEM_MOBILE`| HP CoolSense: Laptop befindet sich auf dem Schoß, Oberflächentemperaturen werden gesenkt. |
| `0x0B` | `HPWMI_COOLSENSE_SYSTEM_HOT` | HP CoolSense: Laptop steht auf einem Schreibtisch, volle Leistung erlaubt. |
| `0x0D` | `HPWMI_BACKLIT_KB_BRIGHTNESS` | Helligkeitsstufen der Tastaturhintergrundbeleuchtung aktualisiert. |
| `0x1A` | `HPWMI_CAMERA_TOGGLE` | **Kamera-Sichtschutzblende:** Physischer Linsenabdeckungsstatus geändert (`0xFF`: Geschlossen, `0xFE`: Offen). Meldet standardmäßiges Linux-Signal `SW_CAMERA_LENS_COVER`. |
| `0x1B` | `HPWMI_FN_P_HOTKEY` | **Kombination Fn + P:** Wechselt zyklisch durch die Plattformprofil-Optionen (`platform_profile_cycle`). |
| `0x1D` | `HPWMI_OMEN_KEY` | **Omen-Taste:** Startet den Omen Gaming Hub; gemeldet als `KEY_PROG2`. |

---

## 8. Referenz der WMI-Befehle und -Abfragen des Treibers

Nachfolgend finden Sie eine Referenz der WMI-Befehle und -Abfragetypen, die bei Abfragen (`hp_wmi_perform_query`) verwendet werden:

### 8.1. WMI-Abfragetypen (`enum hp_wmi_commandtype`)
Übergeben als erstes Argument (`query`) an `hp_wmi_perform_query`:

| Hex-Code | Abfragename (Makro) | Zweck |
| :---: | :--- | :--- |
| `0x01` | `HPWMI_DISPLAY_QUERY` | Status der Anzeige abrufen. |
| `0x02` | `HPWMI_HDDTEMP_QUERY` | HDD-Temperatursensoren abfragen. |
| `0x03` | `HPWMI_ALS_QUERY` | Steuerelemente für den Umgebungslichtsensor. |
| `0x04` | `HPWMI_HARDWARE_QUERY` | Tablet- und Docking-Zustände abfragen. |
| `0x05` | `HPWMI_WIRELESS_QUERY` | Drahtlose Switch-Zustände älterer Generationen. |
| `0x07` | `HPWMI_BATTERY_QUERY` | Batteriezustand und Metriken auslesen. |
| `0x09` | `HPWMI_BIOS_QUERY` | BIOS-Hotkey-Funktionen aktivieren (schreibt `0x6E`). |
| `0x0B` | `HPWMI_FEATURE_QUERY` | BIOS-Feature-Sets ab 2008 abfragen. |
| `0x0C` | `HPWMI_HOTKEY_QUERY` | Tastencode des gedrückten Hotkeys auslesen. |
| `0x0D` | `HPWMI_FEATURE2_QUERY` | Erweiterte BIOS-Feature-Sets ab 2009 abfragen. |
| `0x1B` | `HPWMI_WIRELESS2_QUERY` | Moderner drahtloser Multi-Device-Status-Manager (rfkill2). |
| `0x2A` | `HPWMI_POSTCODEERROR_QUERY` | BIOS POST-Fehlercodes auslesen und löschen. |
| `0x40` | `HPWMI_SYSTEM_DEVICE_MODE` | Grafikkarten-Umschalter (Mux Switch) und Erkennung des Tablet-Modus. |
| `0x4C` | `HPWMI_THERMAL_PROFILE_QUERY` | Klassische thermische Profile lesen/schreiben. |

### 8.2. Gaming- / Omen-spezifische Abfragen (`enum hp_wmi_gm_commandtype`)
Vom Gaming Hub abgeleitete Abfragen zur Verwaltung von Leistungsmerkmalen:

| Hex-Code | Abfragename (Makro) | Zweck |
| :---: | :--- | :--- |
| `0x10` | `HPWMI_FAN_COUNT_GET_QUERY` | Liest Lüfteranzahl. Löst den "benutzerdefinierten Lüftermodus" des EC aus. |
| `0x11` | `HPWMI_FAN_SPEED_GET_QUERY` | Klassische Lüfterdrehzahl auslesen. |
| `0x1A` | `HPWMI_SET_PERFORMANCE_MODE` | Thermische Omen-Profile in den EC schreiben. |
| `0x21` | `HPWMI_GET_GPU_THERMAL_MODES_QUERY`| GPU cTGP- und PPAB-Zustände auslesen. |
| `0x22` | `HPWMI_SET_GPU_THERMAL_MODES_QUERY`| GPU cTGP- und PPAB-Grenzwerte schreiben. |
| `0x26` | `HPWMI_FAN_SPEED_MAX_GET_QUERY` | Abfragen, ob der maximale Lüftermodus aktiv ist. |
| `0x27` | `HPWMI_FAN_SPEED_MAX_SET_QUERY` | Maximalen Lüftermodus umschalten (`0x01` zum Aktivieren, `0x00` zum Deaktivieren). |
| `0x28` | `HPWMI_GET_SYSTEM_DESIGN_DATA` | Systemdesign-Version abrufen (Omen V0 or V1). |
| `0x29` | `HPWMI_SET_POWER_LIMITS_QUERY` | PL1- und PL2-Grenzwerte der CPU konfigurieren. |
| `0x2D` | `HPWMI_VICTUS_S_FAN_SPEED_GET_QUERY`| Gleichzeitiges Auslesen von CPU- und GPU-Drehzahlen auf der Victus S-Serie. |
| `0x2E` | `HPWMI_VICTUS_S_FAN_SPEED_SET_QUERY`| Lüfterdrehzahlen auf der Victus S-Serie direkt überschreiben. |
| `0x2F` | `HPWMI_VICTUS_S_GET_FAN_TABLE_QUERY`| Grenzen der Lüfterkurve aus dem BIOS auslesen. |

---

## 9. Kritische Fehler und Workarounds (Fehlerbehebungen)

Im Laufe der Zeit wurden mehrere Hardware-Kompatibilitäts-Workarounds in den Treiber integriert:

### 1. NVIDIA Dynamic Boost DC GPU-Leistungsbegrenzungs-Fix (xcellsior-Patch)
* **Problem:** Auf Platinen mit unbekannten EC-Layouts (z. B. HP Omen Max 16, Board `8D41`) deaktivierte das Senden von Lüfter-WMI-Steuerungspaketen während des Ladens des Treibermoduls den NVIDIA Dynamic Boost DC-Controller, wodurch die Leistungsaufnahme der GPU (TGP) auf ihr Basisniveau begrenzt wurde (z. B. 80W statt 120W).
* **Behebung:** Der Treiber umgeht den anfänglichen WMI-Lüftermodus-Abgleich, wenn das EC-Offset `HP_EC_OFFSET_UNKNOWN` ist. Die Synchronisation des Lüftermodus wird bis zum ersten Benutzerschreiben in das sysfs-Verzeichnis `pwm_enable` aufgeschoben, wodurch die maximale GPU-Leistung erhalten bleibt.

### 2. ACPI GETB-Methodenabsturz-Verhinderung (Board 8BAC)
* **Problem:** HP Omen 16-wf0xxx (`8BAC`) Hauptplatinen enthalten einen ACPI DSDT-Fehler in ihrer `GETB`-Hilfsfunktion (Fehler bei der Erstellung eines Felds der Länge Null). Dies führte dazu, dass WMI-Methodenabfragen fehlschlugen und das ACPI-Subsystem abstürzte.
* **Behebung:** Die Platine wird explizit dem Profil `omen_v1_no_ec_thermal_params` zugeordnet. Der Treiber überspringt alle EC-basierten Auslesevorgänge für thermische Profile und verlässt sich auf zwischengespeicherte Konfigurationen, um die Systemstabilität zu gewährleisten.

### 3. Kamera-Sichtschutzblende (`camera_shutter_input_setup`)
* **Problem:** Modelle mit physischen Sichtschutzblenden erforderten eine Integration in die Benutzeroberfläche, um zu warnen, wenn die Kamera abgedeckt war.
* **Lösung:** Der Treiber registriert ein virtuelles Eingabegerät namens `HP WMI camera shutter`. Wenn das Ereignis `0x1A` ausgelöst wird, wird der Linsenabdeckungsstatus analysiert (`0xFF` für geschlossen, `0xFE` für offen) und dem Standard-Linux-Kernel-Tastencode `SW_CAMERA_LENS_COVER` zugeordnet.
