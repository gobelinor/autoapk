#!/bin/bash

set -e
APK=$1
RESULTS_DIR="results_$APK/"
APKDECOMP="$RESULTS_DIR""$APK"_decomp
DROZER_VENV="$HOME/Tools/drozer/drozervenv/bin/activate"
FRIDA_VENV="$HOME/Tools/frida-scripts/fridavenv/bin/activate"
FRIDA_SERV="$HOME/Tools/frida-server/frida-server-17.0.1-android-arm64"
FRIDA_SCRIPTS_DIR="$HOME/Tools/frida-scripts"

if [[ -z "$APK" ]]; then
    echo "Usage: $0 app.apk"
	echo "Précision : l'APK doit être dans le même dossier que ce script."
	echo "Placer les splits et le base.apk dans un dossier 'apks/' à côté de ce script."
    exit 1
fi

mkdir -p "$RESULTS_DIR" 

# DECOMP APK
if [[ -d "$APKDECOMP" ]]; then
    echo "[i] Le dossier de décompilation '$APKDECOMP' existe déjà. Skip apktool."
else
    echo "[+] Décompression APK avec apktool..."
    apktool d "$APK" -o "$APKDECOMP" > /dev/null 2>&1 || {
        echo "[!] Erreur lors de la décompression de l'APK";
        exit 1;
    }
fi

# EXTRACT PACKAGE NAME
PACKAGE=$(cat "$APKDECOMP"/AndroidManifest.xml | grep package | sed -n 's/.*package="\([^"]*\)".*/\1/p')
if [[ -z "$PACKAGE" ]]; then
	echo "[!] Impossible de trouver le package dans AndroidManifest.xml"
	exit 1
else
	echo "[+] Package trouvé : $PACKAGE"
fi

# Backup allowed ? 
BACKUP_ALLOWED=$(cat "$APKDECOMP"/AndroidManifest.xml | grep allowBackup | sed -n 's/.*allowBackup="\([^"]*\)".*/\1/p')
if [[ "$BACKUP_ALLOWED" == "false" ]]; then
	echo "[i] Le backup est désactivé dans l'APK (allowBackup=false)."
else
	if [[ "$BACKUP_ALLOWED" == "true" ]]; then
		echo "[i] Le backup est activé dans l'APK (allowBackup=true)."
	else
		echo "[i] Le backup n'est pas spécifié dans l'APK (allowBackup non défini)."
	fi
fi

# APKLEAKS
APKLEAKS_REPORT="${RESULTS_DIR}apkleaks_report.txt"
if [[ -f "$APKLEAKS_REPORT" ]]; then
    echo "[i] Le rapport ApkLeaks '$APKLEAKS_REPORT' existe déjà. Skip."
else
    echo "[+] ApkLeaks : analyse de l'APK pour les secrets..."
    apkleaks -f "$APK" -o "$APKLEAKS_REPORT" > /dev/null 2>&1 || \
        echo "[!] Erreur lors de l'analyse avec ApkLeaks."
fi

# Lance l'émulateur
echo "[+] Lancement de l'émulateur..."
if tmux has-session -t emulator 2>/dev/null; then
	echo "[i] La session tmux 'emulator' existe déjà. Skip lancement."
else
	echo "[i] Pas de session tmux détectée. Création de la session 'emulator'."
	tmux new-session -d -s emulator "emulator -avd MyAndroid35arm64-v8a -no-snapshot-load"
	echo "[✓] Émulateur lancé dans la session tmux 'emulator'."
fi
echo "[i] Tu peux y accéder avec : tmux attach-session -t emulator"

echo "[i] Attends que l'émulateur soit prêt."
read -p "[i] Appuie sur Entrée quand l'émulateur est prêt..."

# Installation de l'APK dans l'émulateur
echo "[+] Installation de l'APK (ou multiple splits)..."
# Verification que l'APK est pas déja installé
if adb shell pm list packages | grep -q "$PACKAGE"; then
	echo "[i] L'application $PACKAGE est déjà installée. Skip installation."
else
	echo "[i] L'application $PACKAGE n'est pas installée. Procédure d'installation en cours..."
	# Recherche des splits dans le dossier apks/
	if [[ -d "apks/" ]]; then
		SPLITS=$(ls apks/split_config*.apk 2>/dev/null | sort)
		BASEAPK=$(ls apks/base.apk 2>/dev/null)
		if [[ -n "$BASEAPK" && -n "$SPLITS" ]]; then
			echo "[i] Des splits ont été détectés. Utilisation de adb install-multiple..."
			adb install-multiple $BASEAPK $SPLITS || {
				echo "[!] Échec de l'installation avec adb install-multiple"
				exit 1
			}
		elif [[ -n "$BASEAPK" ]]; then
			echo "[i] Aucun split trouvé. Installation simple de base.apk"
			adb install "$BASEAPK" || echo "[!] APK déjà installée ou échec."
		else
			echo "[!] Aucun fichier base.apk trouvé dans apks/"
			exit 1
		fi
	else
		echo "[i] Aucun dossier 'apks/' trouvé. Installation de l'APK unique : $APK"
		adb install "$APK" || echo "[!] APK déjà installée ou échec."
	fi
fi

# Pidcat
echo "[+] Lancement de Pidcat pour suivre les logs de l'application..."
if [[ -n "$TMUX" ]]; then
	echo "[i] Session tmux détectée. Lancement de Pidcat dans une nouvelle fenêtre 'pidcat'."
	tmux new-window -d -n pidcat-${APK} "pidcat -c --always-display-tags $PACKAGE"
else	
	if tmux has-session -t pidcat-${APK} 2>/dev/null; then
		echo "[i] La session tmux 'pidcat' existe déjà. Skip lancement."
	else
		echo "[i] Pas de session tmux détectée. Création de la session 'pidcat'."
		tmux new-session -d -s pidcat-${APK} "pidcat -c --always-display-tags $PACKAGE"
	fi
	echo "[i] Tu peux y accéder avec : tmux attach-session -t pidcat"
fi

# Laisser l'utilisateur tester l'application dans l'émulateur pour creer de la data 
echo "[i] Tu peux maintenant tester l'application dans l'émulateur pour générer des données."
echo "[i] Utilise 'skibidi' le plus possible pour générer des données."
read -p "[i] Appuie sur Entrée quand tu as terminé..."

# Pull des données de l'application
echo "[+] Pull /data/data et /sdcard/Android/data (si root)..."
adb root > /dev/null 2>&1 || true
adb pull "/data/data/$PACKAGE" "${RESULTS_DIR}datadata_$PACKAGE" > /dev/null 2>&1 || \
    echo "[!] Impossible de pull /data/data (pas root ?)"
adb pull "/sdcard/Android/data/$PACKAGE" "${RESULTS_DIR}sdcarddata_$PACKAGE" > /dev/null 2>&1 || \
    echo "[!] Impossible de pull /sdcard/Android/data (inexistant ?)"

# Recherche Endpoints Firebase 
FIREBASE_REPORT="${RESULTS_DIR}firebase_report.txt"
if [[ -f "$FIREBASE_REPORT" ]]; then
	echo "[i] Le rapport Firebase '$FIREBASE_REPORT' existe déjà. Skip."
else
	echo "[+] Analyse des endpoints Firebase..."
	grep -rni "firebase" | grep "http" > "$FIREBASE_REPORT" || {	
		echo "[!] Erreur lors de l'analyse des endpoints Firebase."
	}
fi

# Recherche Data Sensible ? 
SENSITIVE_DATA_REPORT="${RESULTS_DIR}sensitive_data_report.txt"
if [[ -f "$SENSITIVE_DATA_REPORT" ]]; then
	echo "[i] Le rapport de données sensibles '$SENSITIVE_DATA_REPORT' existe déjà. Skip."
else
	echo "[+] Analyse des données sensibles..."
	grep -rni "skibidi" "$RESULTS_DIR" > "$SENSITIVE_DATA_REPORT" || {
		echo "[!] Erreur lors de l'analyse des données sensibles."
	}
fi

# Lancement Jadx gui
if [[ -n "$TMUX" ]]; then
	echo "[i] Session tmux détectée. Lancement de Jadx dans une nouvelle fenêtre 'jadx'."
	tmux new-window -d -n jadx-${APK} "jadx-gui $APK"
else
	if tmux has-session -t jadx-${APK} 2>/dev/null; then
		echo "[i] La session tmux 'jadx' existe déjà. Skip lancement."
	else
		echo "[i] Pas de session tmux détectée. Création de la session 'jadx'."
		tmux new-session -d -s jadx-${APK} "jadx-gui $APK"
	fi
	echo "[i] Tu peux y accéder avec : tmux attach-session -t jadx"
fi

# DROZER

# laisser l'utilisateur lancer drozer dans l'émulateur
echo "[i] Tu peux maintenant lancer Drozer dans l'émulateur"
read -p "[i] Appuie sur Entrée quand tu as terminé..."

# Forward du port pour drozer
adb forward tcp:31415 tcp:31415 > /dev/null 2>&1

# Préparation du fichier contenant les commandes utiles
DROZER_CMDS="${RESULTS_DIR}drozer_commands.txt"
cat <<EOF > "$DROZER_CMDS"
list
run app.package.attacksurface $PACKAGE
run app.package.info -a $PACKAGE
run app.activity.info -a $PACKAGE
run app.activity.start --component $PACKAGE <ACTIVITY_NAME>
run app.broadcast.info -a $PACKAGE
run app.provider.info -a $PACKAGE
run app.service.info -a $PACKAGE
run scanner.provider.finduris -a $PACKAGE 
run scanner.provider.injection -a $PACKAGE
run scanner.provider.sqltables -a $PACKAGE
run scanner.provider.traversal -a $PACKAGE
help app.provider.read
EOF

echo "[✓] Commandes Drozer enregistrées dans $DROZER_CMDS"

# Lance une nouvelle fenêtre tmux avec Drozer
if [[ -n "$TMUX" ]]; then
	echo "[i] Session tmux détectée. Lancement de Drozer dans une nouvelle fenêtre 'drozer'."
	tmux new-window -d -n drozer "source $DROZER_VENV && drozer console connect"
else
	if tmux has-session -t drozer 2>/dev/null; then
		echo "[i] La session tmux 'drozer' existe déjà. Skip lancement."
	else
		echo "[i] Pas de session tmux détectée. Création d'une nouvelle session tmux nommée 'drozer'."
		tmux new-session -d -s drozer "source $DROZER_VENV && drozer console connect"
	fi
	echo "[i] Tu peux y accéder avec : tmux attach-session -t drozer"
fi 

echo "[✓] Drozer lancé dans la fenêtre tmux 'drozer'."
echo "[i] Tu peux exécuter les commandes suivantes dans Drozer :"
echo ""
cat "$DROZER_CMDS" 
echo "[i] Tu peux aussi copier-coller les commandes depuis : $DROZER_CMDS"

# Frida bypass SSL pinning
adb push "$FRIDA_SERV" /data/local/tmp/ > /dev/null 2>&1 || {
	echo "[!] Erreur lors de la copie de frida-server dans l'émulateur."
}
adb shell chmod +x /data/local/tmp/frida-server-17.0.1-android-arm64 > /dev/null 2>&1 || {
	echo "[!] Erreur lors de la modification des permissions de frida-server."
}
if tmux has-session -t frida-serv 2>/dev/null; then
	echo "[i] La session tmux 'frida-serv' existe déjà. Skip lancement."
else
	echo "[i] Pas de session tmux détectée. Création d'une nouvelle session tmux nommée 'frida-serv'."
	tmux new-session -d -s frida-serv "adb shell ./data/local/tmp/frida-server-17.0.1-android-arm64"
fi
echo "[i] Tu peux y accéder avec : tmux attach-session -t frida-serv"
echo "[✓] Frida-server lancé dans la fenêtre tmux 'frida-serv'."

if tmux has-session -t frida-venv 2>/dev/null; then
	echo "[i] La session tmux 'frida-venv' existe déjà. Skip lancement."
else
	echo "[i] Pas de session tmux détectée. Création d'une nouvelle session tmux nommée 'frida-venv'."
	tmux new-session -d -s frida-venv "source $FRIDA_VENV && frida-ps -U"
fi
echo "[i] Tu peux y accéder avec : tmux attach-session -t frida-venv"


echo "[✓] Frida lancé dans la fenêtre tmux 'frida-venv'."
echo "[i] Tu peux exécuter des scripts Frida pour bypass SSL pinning, etc."
echo "[i] Par exemple :"
echo "frida -U -l ${FRIDA_SCRIPTS_DIR}/frida-interception-and-unpinning/config.js -l ${FRIDA_SCRIPTS_DIR}/frida-interception-and-unpinning/android/android-certificate-unpinning.js -p <PID>"
echo "frida -U -l ${FRIDA_SCRIPTS_DIR}/custom/hello.js -l ${FRIDA_SCRIPTS_DIR}/custom/print_shared_pref_updates.js -p <PID>"

echo "[✓] Analyse terminée !"
echo "[i] Rapports générés dans $RESULTS_DIR :"
ls -1 "$RESULTS_DIR" | sed 's/^/   └── /'
