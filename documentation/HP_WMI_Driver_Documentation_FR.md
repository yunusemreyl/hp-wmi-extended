# Documentation Technique Détaillée du Pilote HP WMI (hp-wmi.c)

Ce document contient une analyse détaillée et une référence technique pour le pilote de noyau `hp-wmi.c`, qui gère le contrôle du matériel, la gestion thermique, le contrôle des ventilateurs et les raccourcis clavier spécifiques pour les ordinateurs portables HP (en particulier les séries **OMEN** et **Victus**) dans le noyau Linux.

---

## 1. Introduction et Architecture du Pilote

`hp-wmi.c` est un pilote de noyau qui expose l'interface **WMI (Windows Management Instrumentation)** présente sur les appareils HP à la plateforme Linux. Le pilote utilise deux GUID (Globally Unique Identifiers) WMI principaux pour contrôler les fonctionnalités matérielles et intercepter les événements ACPI :

| Macro GUID | Valeur de la Chaîne GUID | Fonction / Objectif |
| :--- | :--- | :--- |
| `HPWMI_EVENT_GUID` | `"95F24279-4D7B-4334-9387-ACCDC67EF61C"` | Signale des événements tels que les raccourcis clavier, l'état du capot et la connexion du chargeur. |
| `HPWMI_BIOS_GUID` | `"5FB7F034-2C63-45E9-BE91-3D44E2C707E4"` | Lecture/écriture des vitesses des ventilateurs, des températures, des modes de carte graphique et des profils thermiques. |

Le pilote communique avec le BIOS et le **Contrôleur Embarqué (EC - Embedded Controller)** en appelant la fonction `hp_wmi_perform_query` pour lire les états du matériel (`HPWMI_READ`) ou écrire de nouveaux paramètres (`HPWMI_WRITE` / `HPWMI_GM`).

---

## 2. Décalages (Offsets) du Contrôleur Embarqué (EC)

Des registres spécifiques (décalages) dans le Contrôleur Embarqué (EC) de l'appareil sont consultés pour lire et écrire les profils thermiques. Ces décalages sont définis sous `enum hp_ec_offsets`.

### Décalages EC et Descriptions

| Nom du Décalage EC | Adresse Hex | Description et Objectif |
| :--- | :---: | :--- |
| `HP_EC_OFFSET_UNKNOWN` | `0x00` | **Disposition EC Inconnue :** La lecture du profil thermique basée sur DMI est désactivée sur les cartes avec ce décalage. Le mode équilibré (`BALANCED`) est sélectionné par défaut lors d'un démarrage à froid. |
| `HP_NO_THERMAL_PROFILE_OFFSET` | `0x01` | **Pas de Profil Thermique :** Contourne complètement les lectures de profil thermique EC. Utilisé sur certains modèles récents avec des tables ACPI corrompues pour éviter les blocages de requêtes. |
| `HP_VICTUS_S_EC_THERMAL_PROFILE_OFFSET` | `0x59` | **Adresse du Profil Thermique de la Série Victus S :** Cellule mémoire EC principale stockant l'état du profil thermique sur les cartes mères modernes Victus 16 (séries r et s) et certaines cartes Omen V1. |
| `HP_OMEN_EC_THERMAL_PROFILE_FLAGS_OFFSET` | `0x62` | **Adresse des Drapeaux de Profil Thermique Omen :** Cellule de drapeau spéciale utilisée sur les appareils Omen pour activer le mode Turbo (`0x04`) ou désactiver la minuterie EC (`0x02`). |
| `HP_OMEN_EC_THERMAL_PROFILE_TIMER_OFFSET` | `0x63` | **Adresse de la Minuterie du Profil Thermique Omen :** Cellule de minuterie EC gérée par l'Omen Gaming Hub ; lorsqu'elle atteint zéro, l'EC réinitialise le profil sur "Équilibré". |
| `HP_OMEN_EC_THERMAL_PROFILE_OFFSET` | `0x95` | **Adresse de Profil Thermique Omen Classique :** Le registre d'état du profil utilisé dans les anciens modèles Omen (V1 Legacy) et certains modèles Victus plus anciens. |

---

## 3. Cartes Mères (DMI Boards) et Mappages de Décalage

Le pilote lit l'identifiant de la carte mère du système (**DMI Board Name**) pour déterminer les décalages EC et les paramètres thermiques à appliquer.

### 3.1. Tableau de Mappage des Paramètres des Cartes Mères Victus & Omen

Les cartes mères définies dans le tableau `victus_s_thermal_profile_boards`, ainsi que leurs paramètres thermiques attribués et leurs décalages EC, sont répertoriées ci-dessous :

| ID de Carte (DMI Board Name) | Modèle / Série d'Ordinateur Associé | Structure de Paramètres Thermiques | Offset de Profil EC | Valeur Performance | Valeur Balanced | Valeur Low Power | Description / Cas Particuliers |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **8A13** | OMEN by HP Laptop 16-b1xxx | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Carte mère utilisant la disposition classique Omen V1. |
| **8A4D** | Série HP Omen | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Disposition classique Omen V1. |
| **8BAB** | Série HP Omen | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Carte mère Omen utilisant le décalage moderne 0x59. |
| **8BBE** | Série HP Victus | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Disposition EC inconnue (0x00). Mise en cache logicielle des profils utilisée. |
| **8BCA** | Série HP Omen | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Décalage moderne 0x59. |
| **8BCD** | Série HP Omen | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Décalage moderne 0x59. |
| **8BD4** | Série HP Victus | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Disposition EC inconnue (0x00). |
| **8BD5** | Série HP Victus | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Disposition EC inconnue (0x00). |
| **8C76** | Série HP Omen | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Décalage moderne 0x59. |
| **8C77** | Série HP Omen | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Omen moderne utilisant le décalage classique 0x95. |
| **8C78** | Série HP Omen | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Décalage moderne 0x59. |
| **8E35** | Série HP Omen | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Décalage moderne 0x59. |
| **8C99** | Série HP Victus | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Disposition EC inconnue (0x00). |
| **8C9C** | Série HP Victus (ex: 16-s1034nf) | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Disposition EC inconnue (0x00). Nécessite un rafraîchissement PL1/PL2 lors du changement de source d'alimentation. |
| **8D41** | HP Omen Max (ex: 16-u0xxx) | `omen_v1_unknown_ec_thermal_params`| `0x00` | `0x31` | `0x30` | `0x30` | Disposition Omen V1 mais avec décalage EC inconnu. |
| **8D87** | Série HP Omen | `omen_v1_no_ec_thermal_params` | `0x01` | `0x31` | `0x30` | `0x30` | Carte mère avec lectures EC désactivées. |
| **8BA9** | Série HP Omen | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Disposition classique Omen V1. |
| **8BAC** | HP Omen 16-wf0xxx | `omen_v1_no_ec_thermal_params` | `0x01` | `0x31` | `0x30` | `0x30` | **Bogue ACPI Critique :** Les tables ACPI ont une fonction GETB défectueuse (erreur de création de champ de longueur nulle) qui abandonne les requêtes WMI. Les lectures EC sont contournées pour éviter les blocages. |
| **8BC2** | Victus by HP Gaming Laptop 16-r0xxx| `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Disposition EC inconnue (0x00). |

---

### 3.2. Autres Groupes Spécialisés de Cartes DMI

#### Cartes Omen Compatibles avec le Profil Thermique (`omen_thermal_profile_boards`)
Ces noms de cartes proviennent de la liste de capacités de l'Omen Command Center et utilisent des chemins de profil thermique spécifiques à Omen :
> `84DA`, `84DB`, `84DC`, `8572`, `8573`, `8574`, `8575`, `8600`, `8601`, `8602`, `8603`, `8604`, `8605`, `8606`, `8607`, `860A`, `8746`, `8747`, `8748`, `8749`, `874A`, `8786`, `8787`, `8788`, `878A`, `878B`, `878C`, `87B5`, `886B`, `886C`, `88C8`, `88CB`, `88D1`, `88D2`, `88F4`, `88F5`, `88F6`, `88F7`, `88FD`, `88FE`, `88FF`, `8900`, `8901`, `8902`, `8912`, `8917`, `8918`, `8949`, `894A`, `89EB`, `8A15`, `8A42`, `8BAD`, `8BAC`, `8C77`, `8D41`, `8E35`, `8E41`, `8BA9`

#### Cartes Omen Forcées au Profil Thermique V0 (`omen_thermal_profile_force_v0_boards`)
Ces cartes sont forcées de fonctionner avec la version 0 du profil thermique Omen, indépendamment des données de conception système renvoyées par le BIOS :
> `8607`, `8746`, `8747`, `8748`, `8749`, `874A`

#### Cartes Omen avec Minuteurs EC (`omen_timed_thermal_profile_boards`)
Ces appareils démarrent une minuterie EC de 120 secondes lorsque le mode performance est activé. Le pilote réinitialise continuellement cette minuterie pour maintenir actif le mode performance :
> `8A15`, `8A42`, `8BAD`

#### Cartes de la Série Victus 16-d (`victus_thermal_profile_boards`)
Modèles utilisant le schéma de contrôle de profil thermique Victus de première génération :
> `88F8`, `8A25`

---

## 4. Profils Thermiques et Mappages Hexadécimaux

L'interface `platform_profile` de Linux mappe les profils utilisateur (Performance, Balanced, etc.) aux codes hexadécimaux attendus par le BIOS/EC. Ces codes varient selon les générations et séries d'appareils.

### 4.1. Profils Classiques / Standard de HP
Définis dans `enum hp_thermal_profile` :

| Nom du Profil | Valeur Hex | Profil Linux | Description |
| :--- | :---: | :--- | :--- |
| `HP_THERMAL_PROFILE_PERFORMANCE` | `0x00` | `performance` | Budget de puissance CPU/GPU maximal et courbes de ventilation agressives. |
| `HP_THERMAL_PROFILE_DEFAULT` | `0x01` | `balanced` | Utilisation quotidienne standard, puissance et bruit équilibrés. |
| `HP_THERMAL_PROFILE_COOL` | `0x02` | `cool` | Seuils d'alimentation abaissés pour maintenir basses les températures de surface. |
| `HP_THERMAL_PROFILE_QUIET` | `0x03` | `quiet` | Bruit de ventilation minimal grâce à des limites d'énergie réduites. |

### 4.2. Profils HP Omen

#### Omen V0 (Ancienne Génération)
Définis dans `enum hp_thermal_profile_omen_v0` :

| Nom du Profil | Valeur Hex | Profil Linux |
| :--- | :---: | :--- |
| `HP_OMEN_V0_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` |
| `HP_OMEN_V0_THERMAL_PROFILE_PERFORMANCE`| `0x01` | `performance` |
| `HP_OMEN_V0_THERMAL_PROFILE_COOL` | `0x02` | `cool` |

#### Omen V1 (Génération Moderne)
Définis dans `enum hp_thermal_profile_omen_v1` :

| Nom du Profil | Valeur Hex | Profil Linux |
| :--- | :---: | :--- |
| `HP_OMEN_V1_THERMAL_PROFILE_DEFAULT` | `0x30` | `balanced` |
| `HP_OMEN_V1_THERMAL_PROFILE_PERFORMANCE`| `0x31` | `performance` |
| `HP_OMEN_V1_THERMAL_PROFILE_COOL` | `0x50` | `cool` |

### 4.3. Profils HP Victus

#### Victus Standard (Série 16-d)
Définis dans `enum hp_thermal_profile_victus` :

| Nom du Profil | Valeur Hex | Profil Linux |
| :--- | :---: | :--- |
| `HP_VICTUS_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` |
| `HP_VICTUS_THERMAL_PROFILE_PERFORMANCE` | `0x01` | `performance` |
| `HP_VICTUS_THERMAL_PROFILE_QUIET` | `0x03` | `quiet` |

#### Série Victus S (Séries 16-r et 16-s)
Définis dans `enum hp_thermal_profile_victus_s` :

| Nom du Profil | Valeur Hex | Profil Linux |
| :--- | :---: | :--- |
| `HP_VICTUS_S_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` ou `low_power` (ECO)* |
| `HP_VICTUS_S_THERMAL_PROFILE_PERFORMANCE`| `0x01` | `performance` |

> [!NOTE]
> *Sur les modèles de la série Victus S, les profils `Balanced` et `Low Power` correspondent tous deux à `0x00` dans l'EC. Le pilote fait la distinction entre eux en interrogeant les états d'alimentation du GPU (cTGP et PPAB). Si les deux sont désactivés, le mode est rapporté comme `low_power` (ECO) ; si PPAB est actif, il est rapporté comme `balanced`.

---

## 5. Contrôles Graphiques & de Limite d'Alimentation (GPU & CPU PL1/PL2)

Sur les ordinateurs portables Victus et Omen modernes, les profils thermiques régissent non seulement les courbes de ventilation, mais aussi les enveloppes de puissance du CPU et du GPU (TGP/TDP).

### 5.1. Gestion de la Puissance GPU (cTGP et PPAB)
Le pilote gère les limites de puissance GPU à l'aide de `HPWMI_SET_GPU_THERMAL_MODES_QUERY` (`0x22`). La structure `struct victus_gpu_power_modes` contrôle les paramètres suivants :

| Paramètre | Type | Fonction / Comportement |
| :--- | :--- | :--- |
| `ctgp_enable` | `u8` | **Configurable TGP :** Libère le plafond de puissance maximal de la carte graphique (ex : 120W au lieu de 80W). Fixé à `0x01` (activé) en mode `Performance`, et `0x00` sinon. |
| `ppab_enable` | `u8` | **Dynamic Boost (PPAB) :** Équilibre le partage dynamique de la puissance entre le CPU et le GPU en fonction de la charge de travail. Fixé à `0x00` (désactivé) en mode `Low Power`, et `0x01` dans les modes `Balanced` et `Performance`. |
| `dstate` | `u8` | **Priorité d'Alimentation GPU :** Définit la priorité de routage de la puissance (la valeur par défaut est `1` représentant 100 % de priorité). |
| `gpu_slowdown_temp` | `u8` | **Température de Ralentissement GPU :** Limite de limitation thermique lue depuis le BIOS et préservée lors des écritures. |

### 5.2. Limites d'Alimentation CPU (PL1 et PL2)
Sur les cartes de la série Victus S, le **PL1 (Limite d'Alimentation à Long Terme)** et le **PL2 (Limite d'Alimentation à Court Terme)** du CPU sont gérés via `HPWMI_SET_POWER_LIMITS_QUERY` (`0x29`) :
* `pl2` doit toujours être supérieur ou égal à `pl1` (`pl2 >= pl1`).
* Lors des transitions de source d'alimentation (branchement/débranchement du chargeur secteur), un notificateur (`victus_s_powersource_event`) réapplique automatiquement les limites par défaut (`HP_POWER_LIMIT_DEFAULT` -> `0x00`) pour éviter les blocages de performances sur batterie.

---

## 6. Contrôle Avancé des Ventilateurs (Cadre Hwmon)

Le pilote s'interface avec le sous-système de surveillance matérielle Linux (`hwmon`) pour exposer les lectures de vitesse de ventilateur et activer des fonctionnalités de contrôle manuel.

### 6.1. Modes de Contrôle de Ventilateur
Le contrôle manuel et automatique des ventilateurs est défini sous `enum pwm_modes` :

| Nom du Mode | Valeur | Description |
| :--- | :---: | :--- |
| `PWM_MODE_MAX` | `0` | **Ventilation Maximale :** Force les ventilateurs à fonctionner à 100 % de leur cycle d'activité. |
| `PWM_MODE_MANUAL` | `1` | **Contrôle Manuel :** Permet aux utilisateurs de définir directement les RPM cibles des ventilateurs via sysfs. |
| `PWM_MODE_AUTO` | `2` | **Contrôle EC Automatique :** Cède le contrôle aux algorithmes thermiques internes du Contrôleur Embarqué. |

### 6.2. Minuteur du Chien de Garde (Keep-Alive Watchdog)
Le Contrôleur Embarqué (EC) de HP démarre un **minuteur de sécurité de 120 secondes** lors de l'accès au mode de ventilateur manuel ou maximal. Si aucune commande WMI n'est reçue dans les 120 secondes, l'EC revient au mode automatique (`AUTO`) par sécurité.

Pour éviter cela, le pilote exécute un thread de chien de garde en arrière-plan (**Delayed Work - Keep Alive Watchdog**) :
* Le pilote effectue un rafraîchissement Keep-Alive toutes les **90 secondes** (`KEEP_ALIVE_DELAY_SECS = 90`), écrivant le mode actif et les vitesses de retour à l'EC.
* Cela réinitialise constamment le minuteur de sécurité de 120 secondes de l'EC, maintenant le contrôle manuel actif.
* Lorsque l'utilisateur repasse sur `AUTO`, le thread de chien de garde est annulé (`cancel_delayed_work_sync`) et l'EC reprend la main.

### 6.3. Structure de la Table des Ventilateurs Victus S
Sur les ordinateurs portables de la série Victus S, les limites de vitesse de ventilateur sont extraites du BIOS via `HPWMI_VICTUS_S_GET_FAN_TABLE_QUERY` (`0x2F`) :

```c
struct victus_s_fan_table_header {
    u8 unknown;
    u8 num_entries; // Nombre d'entrées d'étape dans la courbe de ventilation
} __packed;

struct victus_s_fan_table_entry {
    u8 cpu_rpm;     // Vitesse du ventilateur CPU (valeur * 100 RPM)
    u8 gpu_rpm;     // Vitesse du ventilateur GPU (valeur * 100 RPM)
    u8 unknown;
} __packed;
```
* **Limites Minimales :** Extraites de la première étape du tableau (`entries[0].cpu_rpm`).
* **Limites Maximales :** Extraites de la dernière étape du tableau (`entries[num_entries-1]`).
* **Dégradation Progressive :** Si la requête de table de ventilateur n'est pas prise en charge ou est malformée, le pilote enregistre automatiquement une **table de secours sécurisée à 5000 RPM** (`setup_fallback_fan_limits`) au lieu de faire échouer le chargement.

---

## 7. Notifications d'Événements WMI (Event IDs)

Notifications ACPI reçues via `HPWMI_EVENT_GUID` et réponses du pilote :

| ID d'Événement (Hex) | Nom de l'Événement | Condition de Déclenchement & Comportement du Pilote |
| :---: | :--- | :--- |
| `0x01` | `HPWMI_DOCK_EVENT` | Connexion/déconnexion de station d'accueil ou transition en mode tablette. Signalé via `input_report_switch`. |
| `0x02` | `HPWMI_PARK_HDD` | Alerte du capteur de chute libre ; parque la tête de lecture/écriture du disque dur pour la protection des données. |
| `0x03` | `HPWMI_SMART_ADAPTER` | Avertissement de chargeur non officiel ou sous-alimenté. |
| `0x04` | `HPWMI_BEZEL_BUTTON` | Pressions sur les boutons spéciaux du cadre d'écran ; signalé comme un événement de touche. |
| `0x05` | `HPWMI_WIRELESS` | Commutation de l'état sans fil (Wi-Fi, Bluetooth, WWAN) ; met à jour les états de rfkill. |
| `0x06` | `HPWMI_CPU_BATTERY_THROTTLE` | Limites d'alimentation du CPU réduites pour la sécurité de la batterie à 3 cellules. |
| `0x0A` | `HPWMI_COOLSENSE_SYSTEM_MOBILE`| HP CoolSense : L'ordinateur est sur les genoux, les températures de surface sont abaissées. |
| `0x0B` | `HPWMI_COOLSENSE_SYSTEM_HOT` | HP CoolSense : L'ordinateur est sur un bureau, performances maximales autorisées. |
| `0x0D` | `HPWMI_BACKLIT_KB_BRIGHTNESS` | Niveaux de luminosité du clavier rétroéclairé mis à jour. |
| `0x1A` | `HPWMI_CAMERA_TOGGLE` | **Obturateur de la Caméra :** L'état du cache physique a changé (`0xFF` : Fermé, `0xFE` : Ouvert). Signale le code Linux standard `SW_CAMERA_LENS_COVER`. |
| `0x1B` | `HPWMI_FN_P_HOTKEY` | **Combinaison Fn + P :** Fait défiler les options de profil de plateforme (`platform_profile_cycle`). |
| `0x1D` | `HPWMI_OMEN_KEY` | **Touche Omen :** Lance l'Omen Gaming Hub ; signalé comme `KEY_PROG2`. |

---

## 8. Références des Commandes & Requêtes WMI du Pilote

Ci-dessous se trouve une référence des types de commandes et requêtes WMI utilisés dans les appels (`hp_wmi_perform_query`) :

### 8.1. Types de Requêtes WMI (`enum hp_wmi_commandtype`)
Passés comme premier argument (`query`) à `hp_wmi_perform_query` :

| Code Hex | Nom de la Requête (Macro) | Objectif |
| :---: | :--- | :--- |
| `0x01` | `HPWMI_DISPLAY_QUERY` | Récupérer l'état de l'affichage. |
| `0x02` | `HPWMI_HDDTEMP_QUERY` | Interroger les capteurs de température du disque dur. |
| `0x03` | `HPWMI_ALS_QUERY` | Contrôles du capteur de lumière ambiante. |
| `0x04` | `HPWMI_HARDWARE_QUERY` | Requête sur les états de tablette et de station d'accueil. |
| `0x05` | `HPWMI_WIRELESS_QUERY` | États des commutateurs sans fil de l'ancienne génération. |
| `0x07` | `HPWMI_BATTERY_QUERY` | Lire la santé et les mesures de la batterie. |
| `0x09` | `HPWMI_BIOS_QUERY` | Activer les fonctionnalités de raccourcis du BIOS (écrit `0x6E`). |
| `0x0B` | `HPWMI_FEATURE_QUERY` | Interroger les ensembles de fonctionnalités du BIOS post-2008. |
| `0x0C` | `HPWMI_HOTKEY_QUERY` | Lire le code de touche du raccourci enfoncé. |
| `0x0D` | `HPWMI_FEATURE2_QUERY` | Interroger les ensembles de fonctionnalités avancées du BIOS post-2009. |
| `0x1B` | `HPWMI_WIRELESS2_QUERY` | Gestionnaire d'état sans fil multidispositif moderne (rfkill2). |
| `0x2A` | `HPWMI_POSTCODEERROR_QUERY` | Lire et effacer les codes d'erreur POST du BIOS. |
| `0x40` | `HPWMI_SYSTEM_DEVICE_MODE` | Commutateur de mode graphique (Mux Switch) et détection du mode tablette. |
| `0x4C` | `HPWMI_THERMAL_PROFILE_QUERY` | Lire/écrire des profils thermiques classiques. |

### 8.2. Requêtes Spécifiques Gaming / Omen (`enum hp_wmi_gm_commandtype`)
Requêtes du Gaming Command Center utilisées pour gérer les fonctionnalités de performances :

| Code Hex | Nom de la Requête (Macro) | Objectif |
| :---: | :--- | :--- |
| `0x10` | `HPWMI_FAN_COUNT_GET_QUERY` | Lit le nombre de ventilateurs. Déclenche le "mode ventilateur personnalisé" de l'EC. |
| `0x11` | `HPWMI_FAN_SPEED_GET_QUERY` | Lire la vitesse des ventilateurs classique. |
| `0x1A` | `HPWMI_SET_PERFORMANCE_MODE` | Écrire les profils thermiques Omen dans l'EC. |
| `0x21` | `HPWMI_GET_GPU_THERMAL_MODES_QUERY`| Lire les états cTGP et PPAB du GPU. |
| `0x22` | `HPWMI_SET_GPU_THERMAL_MODES_QUERY`| Écrire les limites cTGP et PPAB du GPU. |
| `0x26` | `HPWMI_FAN_SPEED_MAX_GET_QUERY` | Savoir si le mode ventilateur maximal est actif. |
| `0x27` | `HPWMI_FAN_SPEED_MAX_SET_QUERY` | Activer/désactiver le mode ventilation max (`0x01` pour activer, `0x00` pour désactiver). |
| `0x28` | `HPWMI_GET_SYSTEM_DESIGN_DATA` | Récupérer la version de conception système (Omen V0 ou V1). |
| `0x29` | `HPWMI_SET_POWER_LIMITS_QUERY` | Configurer les seuils PL1 et PL2 du CPU. |
| `0x2D` | `HPWMI_VICTUS_S_FAN_SPEED_GET_QUERY`| Lire simultanément les RPM du CPU et du GPU sur la série Victus S. |
| `0x2E` | `HPWMI_VICTUS_S_FAN_SPEED_SET_QUERY`| Remplacer directement les RPM des ventilateurs sur la série Victus S. |
| `0x2F` | `HPWMI_VICTUS_S_GET_FAN_TABLE_QUERY`| Lire les limites de courbe par étapes des ventilateurs depuis le BIOS. |

---

## 9. Bogues Critiques et Solutions de Contournement (Fixes)

Au fil du temps, plusieurs solutions de contournement de compatibilité matérielle ont été intégrées dans le pilote :

### 1. Correctif de Limitation d'Alimentation GPU par NVIDIA Dynamic Boost (correctif xcellsior)
* **Problème :** Sur les cartes dont la disposition EC n'est pas caractérisée (ex : HP Omen Max 16, carte `8D41`), l'envoi de paquets de contrôle WMI de ventilateur lors du chargement du module désactivait le contrôleur NVIDIA Dynamic Boost DC, plafonnant la cible de puissance du GPU (TGP) à son niveau de base (ex : 80W au lieu de 120W).
* **Correctif :** Le pilote contourne la réconciliation initiale du mode ventilateur WMI si le décalage EC est `HP_EC_OFFSET_UNKNOWN`. La synchronisation du mode ventilateur est différée jusqu'à la première écriture utilisateur dans sysfs `pwm_enable`, préservant la puissance GPU maximale.

### 2. Prévention du Blocage par la Méthode ACPI GETB (Carte 8BAC)
* **Problème :** Les cartes mères HP Omen 16-wf0xxx (`8BAC`) contiennent un bogue ACPI DSDT dans leur assistant `GETB`, tentant de créer un champ de longueur nulle. Cela provoquait l'échec de l'évaluation de la méthode WMI, bloquant le sous-système ACPI.
* **Correctif :** La carte est explicitement mappée sur `omen_v1_no_ec_thermal_params`. Le pilote ignore toutes les lectures de profil thermique basées sur l'EC, s'appuyant sur les configurations mises en cache pour maintenir la stabilité du système.

### 3. Obturateur de Confidentialité de l'Objectif de la Caméra (`camera_shutter_input_setup`)
* **Problème :** Les modèles équipés de commutateurs physiques de confidentialité nécessitaient une intégration avec l'interface utilisateur pour avertir lorsque l'objectif de la caméra était obturé.
* **Solution :** Le pilote enregistre un périphérique d'entrée virtuel `HP WMI camera shutter`. Lorsque l'événement `0x1A` est déclenché, l'état du cache de l'objectif est analysé (`0xFF` pour fermé, `0xFE` pour ouvert) et mappé au code de touche standard du noyau Linux `SW_CAMERA_LENS_COVER`.
