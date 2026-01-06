#!/usr/bin/env bash
set -e 

DROZER_VENV="$HOME/Tools/drozer/venv/bin/activate"
FRIDA_VENV="$HOME/Tools/frida-scripts/venv/bin/activate"
FRIDA_SERV="$HOME/Tools/frida-server/frida-server-17.0.1-android-arm64"
FRIDA_SCRIPTS_DIR="$HOME/Tools/frida-scripts"
FIREBASE_VENV="$HOME/Tools/firebase-sniper/venv/bin/activate"
EMULATOR_IMAGE="MyAndroid35arm64-v8a"

ARG=$1
APP=$(basename "$ARG")
RESULTS_DIR="results_$APP/"
APKDECOMP="$RESULTS_DIR"decompiled_apk/
APKUNZIP="$RESULTS_DIR"unzipped_apk/

if [[ -z "$ARG" ]]; then
	echo "Usage: $0 app.apk (if only one .apk)"
	echo "or: $0 apks_appname (if multiple splits in apks/ folder)"
    exit 1
fi

mkdir -p "$RESULTS_DIR" 

if [[ -f "$ARG" ]]; then
	APK="$ARG"
elif [[ -d "$ARG" ]]; then
	APKS_DIR="$ARG"
	APK="$APKS_DIR/base.apk"
	if [[ ! -f "$APK" ]]; then
		echo "[!] Fichier APK '$APK' introuvable."
		exit 1
	fi
else
	echo "[!] Argument invalide. Fournir un fichier APK ou un dossier contenant apks/."
	exit 1
fi

# Unzip APK
if [[ -d "$APKUNZIP" ]]; then
	echo "[i] Le dossier de l'APK dézippé existe déjà. Skip unzip."
else
	echo "[+] Unzip de l'APK..."
	unzip -q "$APK" -d "$APKUNZIP" || {
		echo "[!] Erreur lors de la décompression de l'APK";
		exit 1;
	}
fi

# Detect if libflutter.so is used 
FLUTTER_USED=$(grep -rl "libflutter.so" "$APKUNZIP" || true)
if [[ -n "$FLUTTER_USED" ]]; then
	echo "[i] L'application utilise Flutter (libflutter.so détecté)."
else
	echo "[i] L'application ne semble pas utiliser Flutter."
fi

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
	echo "[+] Nom du package trouvé : $PACKAGE"
fi

SAFE_PACKAGE=$(echo "$PACKAGE" | tr '.' '_')

# Backup allowed ? 
BACKUP_ALLOWED=$(cat "$APKDECOMP"/AndroidManifest.xml | grep allowBackup | sed -n 's/.*allowBackup="\([^"]*\)".*/\1/p')
if [[ "$BACKUP_ALLOWED" == "false" ]]; then
	echo "[i] Le backup est désactivé (allowBackup=false)."
else
	if [[ "$BACKUP_ALLOWED" == "true" ]]; then
		echo "[i] Le backup est activé (allowBackup=true)."
	else
		echo "[i] Le backup n'est pas spécifié (allowBackup non défini)."
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

# Google maps key : Necessite de retravailler le script gmapsapiscanner pour eviter de stuck et devoir "press enter" et eviter d'avoir de la couleur dans l'output
GOOGLE_MAPS_KEY_REPORT="${RESULTS_DIR}google_maps_key_report.txt"
if [[ -f "$GOOGLE_MAPS_KEY_REPORT" ]]; then
	echo "[i] Le rapport Google Maps Key '$GOOGLE_MAPS_KEY_REPORT' existe déjà. Skip."
else
	echo "[+] Recherche de clés Google Maps dans l'output de apkleaks"
	GOOGLE_MAPS_KEYS=$(grep -Eo 'AIza[_0-9A-Za-z-]{35}' "$APKLEAKS_REPORT" | sort -u || true)
	if [[ -n "$GOOGLE_MAPS_KEYS" ]]; then
		echo "[i] Clés Google Maps détectées "
		source $HOME/Tools/gmapsapiscanner/gmapvenv/bin/activate
		# FOR EACH KEY
		for KEY in $GOOGLE_MAPS_KEYS; do
			echo "[i] Clé détectée : $KEY (Press Enter to process)"
			python3 $HOME/Tools/gmapsapiscanner/maps_api_scanner.py --api-key "$KEY" >> "$GOOGLE_MAPS_KEY_REPORT" 2>&1 
			echo "===========================================" >> "$GOOGLE_MAPS_KEY_REPORT"
		done
		deactivate
	    echo "[i] Resultat enregistré dans $GOOGLE_MAPS_KEY_REPORT"
	else
		echo "[i] Aucune clé Google Maps détectée."
		echo "Aucune clé Google Maps détectée." > "$GOOGLE_MAPS_KEY_REPORT"
	fi
fi


# Lance l'émulateur
echo "[+] Lancement de l'émulateur..."
if tmux has-session -t emulator 2>/dev/null; then
	echo "[i] La session tmux 'emulator' existe déjà. Skip lancement."
else
	echo "[i] Pas de session tmux détectée. Création de la session 'emulator'."
	tmux new-session -d -s emulator "emulator -avd $EMULATOR_IMAGE -no-snapshot-load"
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
	if [[ -d "$APKS_DIR" ]]; then
		SPLITS=$(ls $APKS_DIR/split_config*.apk 2>/dev/null | sort)
		BASEAPK=$(ls $APKS_DIR/base.apk 2>/dev/null)
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
echo "[+] Tu peux lancer Pidcat avec cette commande pour suivre les logs de l'application :"
echo "pidcat -c --always-display-tags $PACKAGE"

# Quel mail sera utilisé pour les tests ?
read -p "[?] Quel email veux-tu utiliser pour tester l'application ? " TEST_EMAIL
if [[ -z "$TEST_EMAIL" ]]; then
	TEST_EMAIL=BUGBOUNTY$(date +%s)@yopmail.com
	echo "[i] Aucun email fourni. Utilisation de l'email par défaut : $TEST_EMAIL"
else
	echo "[i] Email de test défini : $TEST_EMAIL"
fi

# Laisser l'utilisateur tester l'application dans l'émulateur pour creer de la data 
echo "[i] Tu peux maintenant tester l'application dans l'émulateur pour générer des données."
read -p "[i] Appuie sur Entrée quand tu as terminé..."

# Pull des données de l'application
echo "[+] Pull /data/data et /sdcard/Android/data (si root)..."
adb root > /dev/null 2>&1 || true
adb pull "/data/data/$PACKAGE" "${RESULTS_DIR}datadata_$PACKAGE" > /dev/null 2>&1 || \
    echo "[!] Impossible de pull /data/data (pas root ?)"
adb pull "/sdcard/Android/data/$PACKAGE" "${RESULTS_DIR}sdcarddata_$PACKAGE" > /dev/null 2>&1 || \
    echo "[!] Impossible de pull /sdcard/Android/data (inexistant ?)"

# Firebase Analysis
FIREBASE_REPORT="${RESULTS_DIR}firebase_report.txt"
if [[ -f "$FIREBASE_REPORT" ]]; then
	echo "[i] Le rapport Firebase '$FIREBASE_REPORT' existe déjà. Skip."
else
	echo "[+] Analyse Firebase..."
	source $FIREBASE_VENV
	APK_FULLPATH=$(realpath "$APK")
	python3 $HOME/Tools/firebase-sniper/firebase-sniper.py --apk-path "$APK_FULLPATH" --output "$FIREBASE_REPORT" --user-email "$TEST_EMAIL" > /dev/null 2>&1 || {
		echo "[!] Erreur lors de l'analyse Firebase."
	}
	deactivate
fi

# Recherche Data Sensible ?  
SENSITIVE_DATA_REPORT="${RESULTS_DIR}sensitive_data_report.txt"
if [[ -f "$SENSITIVE_DATA_REPORT" ]]; then
	echo "[i] Le rapport de données sensibles '$SENSITIVE_DATA_REPORT' existe déjà. Skip."
else
	echo "[+] Analyse des données sensibles..."
	grep -rni "$TEST_EMAIL" "$RESULTS_DIR" > "$SENSITIVE_DATA_REPORT" || \
		echo "[i] Aucune donnée sensible trouvée avec l'email '$TEST_EMAIL'."
fi

# JADX
if tmux has-session -t jadx-${SAFE_PACKAGE} 2>/dev/null; then
	echo "[i] La session tmux 'jadx-${SAFE_PACKAGE}' existe déjà. Skip."
else
	echo "[i] Pas de session tmux détectée. Création de la session 'jadx-${SAFE_PACKAGE}'."
	tmux new-session -d -s jadx-${SAFE_PACKAGE} "jadx-gui $APK"
fi
echo "[i] Tu peux y accéder avec : tmux attach-session -t jadx-${SAFE_PACKAGE}"

### DROZER ###

# laisser l'utilisateur lancer drozer dans l'émulateur
echo "[i] Tu peux maintenant lancer Drozer dans l'émulateur"
read -p "[i] Appuie sur Entrée quand tu as terminé..."

# Forward du port pour drozer
adb forward tcp:31415 tcp:31415 > /dev/null 2>&1

# Préparation du fichier contenant les commandes drozer utiles
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

# Lance une nouvelle fenêtre tmux avec Drozer
if tmux has-session -t drozer 2>/dev/null; then
	echo "[i] La session tmux 'drozer' existe déjà. Skip lancement."
else
	echo "[i] Pas de session tmux détectée. Création d'une nouvelle session tmux nommée 'drozer'."
	tmux new-session -d -s drozer "source $DROZER_VENV && drozer console connect"
fi
echo "[i] Tu peux y accéder avec : tmux attach-session -t drozer"

echo "[✓] Drozer lancé dans la fenêtre tmux 'drozer'."
echo "[i] Tu peux exécuter les commandes suivantes dans Drozer :"
cat "$DROZER_CMDS" 
echo "[i] Tu peux aussi copier-coller les commandes depuis : $DROZER_CMDS"

### FRIDA ###

read -p "[?] Voulez vous mettre en place Frida ? (y/N)" USE_FRIDA
if [[ "$USE_FRIDA" == "y" ]]; then
	# Frida server est déposé dans l'émulateur, rendu executable et executé
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
	echo "[i] Tu peux maintenant utiliser les commandes Frida suivantes :"
	echo ""
	echo "source $FRIDA_VENV && frida-ps -U"
	echo "frida -U -l ${FRIDA_SCRIPTS_DIR}/frida-interception-and-unpinning/config.js -l ${FRIDA_SCRIPTS_DIR}/frida-interception-and-unpinning/android/android-certificate-unpinning.js -p <PID>"
	echo "frida -U -l ${FRIDA_SCRIPTS_DIR}/custom/hello.js -l ${FRIDA_SCRIPTS_DIR}/custom/print_shared_pref_updates.js -p <PID>"
	echo ""
fi

# Fin

echo "[✓] Analyse terminée !"
echo "[i] Rapports générés dans $RESULTS_DIR :"
ls -1 "$RESULTS_DIR" | sed 's/^/   └── /'
