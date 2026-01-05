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

---

## tmux Sessions

Emulator:
- Session name: emulator
- Command: emulator -avd <EMULATOR_IMAGE> -no-snapshot-load

JADX:
- Session name: jadx-<package_with_underscores>
- Command: jadx-gui <APK>

Drozer:
- Session name: drozer
- Command: drozer console connect
- Requires: adb forward tcp:31415 tcp:31415

Frida (optional):
- frida-serv: frida-server running in emulator
- Command: frida-ps -U

Attach to a session:
tmux attach-session -t emulator
tmux attach-session -t drozer
tmux attach-session -t frida-serv

---

## Notes

- The script is interactive
- APK install is skipped if already installed (adb shell pm list packages)
- Pulling /data/data/<package> usually requires a rooted emulator (adb root)

---

## Google Maps API Keys

- Extracted from apkleaks_report.txt
- Regex: AIza[_0-9A-Za-z-]{35}
- Results written to google_maps_key_report.txt

---

## Drozer Quickstart

Generated file:
results_<appname>/drozer_commands.txt
Includes common commands such as:

```
run app.package.attacksurface <package>
run app.package.info -a <package>
run app.activity.info -a <package>
run app.broadcast.info -a <package>
run app.provider.info -a <package>
run scanner.provider.injection -a <package>
run scanner.provider.sqltables -a <package>
run scanner.provider.traversal -a <package>
```

---

## Frida Examples

SSL pinning bypass:
frida -U -l frida-interception-and-unpinning/config.js -l android-certificate-unpinning.js -p <PID>

Custom scripts:
frida -U -l custom/hello.js -p <PID>
frida -U -l custom/print_shared_pref_updates.js -p <PID>

---

## Disclaimer

Use this script only on applications and environments you are explicitly authorized to test.

