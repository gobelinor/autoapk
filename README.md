# Android APK Triage Script

A lightweight bash workflow to quickly **triage an Android app** (single APK or split APKs), generate useful reports, boot an emulator, install the app, extract app data, and optionally prepare **Drozer** and **Frida** sessions — all while keeping outputs organized in a per-app `results_*` directory.

> Designed for local security testing and bug bounty style recon on APKs you are authorized to analyze.

---

## Features

- Supports:
  - **Single APK** (`app.apk`)
  - **Split APKs folder** containing `base.apk` and `split_config*.apk`
- Creates a dedicated output directory: `results_<appname>/`
- Unzips APK 
- Checks for **Flutter** usage (`libflutter.so`)
- Decompiles APK using **apktool**
- Extracts:
  - `package` name from `AndroidManifest.xml`
  - `allowBackup` value
- Runs **ApkLeaks** and saves the report
- Detects **Google Maps API keys** from ApkLeaks output and runs `gmapsapiscanner`
- Launches an Android emulator in a **tmux** session
- Installs the APK (or split APKs via `adb install-multiple`)
- Prompts for a test email (default: `BUGBOUNTY<timestamp>@yopmail.com`)
- Pulls app data (best effort):
  - `/data/data/<package>` (requires root)
  - `/sdcard/Android/data/<package>`
- Runs **firebase-sniper** analysis and saves the report
- Searches for the test email in extracted results (basic sensitive-data check)
- Opens **jadx-gui** in a dedicated tmux session
- Prepares **Drozer** (writes a command cheat file + starts a tmux session)
- Optional **Frida** setup (push + run frida-server)

---

## Requirements

### System tools
- `bash`
- `tmux`
- `unzip`
- `grep`, `sed`, `sort`, `tr`, `realpath`
- Android tooling:
  - `adb`
  - `emulator` (Android SDK)
  - An existing AVD image (see `EMULATOR_IMAGE`)

### Security / reverse tools
- `apktool`
- `jadx-gui`
- `apkleaks`

### Python tools / venvs
This script assumes these venvs and paths exist (adjust if needed):

- Drozer venv:
  - `~/Tools/drozer/venv/bin/activate`
- Frida venv + scripts:
  - `~/Tools/frida-scripts/venv/bin/activate`
  - `~/Tools/frida-scripts/`
- Frida server binary:
  - `~/Tools/frida-server/frida-server-17.0.1-android-arm64`
- Firebase Sniper venv:
  - `~/Tools/firebase-sniper/venv/bin/activate`
- Google Maps API scanner venv:
  - `~/Tools/gmapsapiscanner/venv/bin/activate`
  - `~/Tools/gmapsapiscanner/maps_api_scanner.py`

---

## Configuration

Edit these variables at the top of the script if your setup differs:

- `EMULATOR_IMAGE="MyAndroid35arm64-v8a"`
- `DROZER_VENV=...`
- `FRIDA_VENV=...`
- `FRIDA_SERV=...`
- `FRIDA_SCRIPTS_DIR=...`
- `FIREBASE_VENV=...`

---

## Usage

### 1) Single APK

```bash
./triage.sh path/to/app.apk
```

### 2) Split APKs directory

Directory must contain `base.apk` and optional `split_config*.apk` files.

```bash
./triage.sh path/to/split_apks_folder/
```

---

## Output Structure

```
results_<appname>/
├── unzipped_apk/
├── decompiled_apk/
├── apkleaks_report.txt
├── google_maps_key_report.txt
├── firebase_report.txt
├── sensitive_data_report.txt
├── drozer_commands.txt
├── datadata_<package>/      
└── sdcarddata_<package>/    
```

---

## Disclaimer

Use this script only on applications and environments you are explicitly authorized to test.

