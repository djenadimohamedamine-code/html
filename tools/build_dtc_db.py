import urllib.request
import json
import re
import os
import sys

# Expert detailed dossiers in French
EXPERT_DOSSIERS = {
    "P0105": {
        "title": "Capteur de pression d'admission (MAP) / Barométrique — Dysfonctionnement du circuit",
        "cat": "Moteur / Admission d'air",
        "sev": "alerte",
        "desc": "Le calculateur (ECU) détecte une anomalie électrique générale sur le circuit du capteur MAP ou BARO. Le signal de pression reçu ne correspond à aucune condition normale de fonctionnement moteur.",
        "causes": [
            "Connecteur du capteur MAP débranché, mal enclenché ou broches oxydées",
            "Faisceau électrique coupé, pincé ou en court-circuit",
            "Absence de l'alimentation de référence 5V venant du calculateur",
            "Durite de dépression fissurée, poreuse ou déconnectée (sur Spark 0.8)",
            "Défaillance interne du capteur de pression d'admission"
        ],
        "symptoms": [
            "Voyant moteur (Check Engine) allumé au tableau de bord",
            "Ralenti instable ou moteur qui cale à chaud/froid",
            "Légers trous ou à-coups à l'accélération",
            "Surconsommation de carburant constatée",
            "Odeur d'essence imbrûlée à l'échappement"
        ],
        "checks": [
            "1. Inspecter visuellement le connecteur 3 broches du capteur MAP (recherche d'oxydation ou d'humidité).",
            "2. Contact mis moteur arrêté : mesurer la tension entre la broche 5V (Vref) et la masse du connecteur (doit faire entre 4.8V et 5.1V).",
            "3. Vérifier la continuité de la masse (résistance < 1 Ohm vers la borne négative batterie).",
            "4. Vérifier l'état de la petite durite de dépression reliant le capteur au collecteur.",
            "5. Vérifier la tension du fil de signal au ralenti (doit chuter entre 1.0V et 1.8V)."
        ],
        "note": "Important : Ne remplacez pas le capteur sans tester. 70% des défauts P0105 proviennent d'une connectique desserrée ou d'une durite de vide fissurée."
    },
    "P0106": {
        "title": "Capteur de pression d'admission (MAP) — Problème de plage / rendement",
        "cat": "Moteur / Admission d'air",
        "sev": "alerte",
        "desc": "La pression mesurée par le capteur MAP est incohérente avec les autres paramètres moteur (régime RPM, ouverture papillon TPS, température IAT). Par exemple, pression atmosphérique lue papillon fermé.",
        "causes": [
            "Prise d'air au collecteur d'admission ou joint de boîtier papillon",
            "Durite de dépression percée ou débranchée",
            "Boîtier papillon encrassé perturbant la dépression au ralenti",
            "Capteur MAP encrassé par des vapeurs d'huile (blow-by reniflard)",
            "Décalage léger du calage de distribution (perte de dépression)",
            "Capteur MAP dérivant hors tolérances constructeur"
        ],
        "symptoms": [
            "Ralenti qui oscille ou 'pompe' de 800 à 1200 tr/min",
            "À-coups désagréables à bas régime et vitesse constante",
            "Légère fumée noire ou mélange trop riche par stratégie de sécurité",
            "Manque de vivacité sous forte charge"
        ],
        "checks": [
            "1. Moteur tournant : pulvériser un nettoyant frein sur les joints d'admission pour détecter une prise d'air.",
            "2. Démonter et nettoyer le petit conduit d'air du capteur MAP (souvent calaminé ou gras).",
            "3. Nettoyer le boîtier papillon et la vanne de ralenti (IAC).",
            "4. Comparer la pression MAP contact mis (~100 kPa) et moteur au ralenti (~30-40 kPa).",
            "5. Contrôler les compressions moteur si le ralenti reste irrégulier."
        ],
        "note": "Important : Une fuite d'air à l'admission génère exactement ce code, même si le capteur MAP est neuf. Traquez les prises d'air avant tout remplacement."
    },
    "P0107": {
        "title": "Capteur de pression d'admission (MAP) — Signal d'entrée trop bas (Circuit Low)",
        "cat": "Moteur / Admission d'air",
        "sev": "critique",
        "desc": "La tension sur la ligne de signal du capteur MAP est descendue sous le seuil critique (généralement < 0.2V). Le calculateur interprète cela comme un fil coupé sur le 5V ou un court-circuit franc du signal à la masse.",
        "causes": [
            "Connecteur du capteur MAP débranché, mal verrouillé ou cosse détendue",
            "Coupure de la ligne d'alimentation 5V (Vref) venant du calculateur",
            "Fil de signal en court-circuit avec la masse ou le bloc moteur",
            "Court-circuit sur un autre capteur partageant le 5V (ex: capteur papillon TPS)",
            "Rupture interne du pont piézoélectrique du capteur MAP"
        ],
        "symptoms": [
            "Voyant moteur CHECK ENGINE allumé en continu",
            "Le calculateur applique une valeur de pression par défaut de secours",
            "Réponse hésitante à l'accélérateur et légers trous",
            "Estimation de carburant faussée en l'absence de mesure réelle MAP",
            "Perte d'agrément de conduite à froid"
        ],
        "checks": [
            "1. Débrancher la prise du capteur MAP et mesurer la tension d'alimentation contact mis : vous DEVEZ trouver entre 4.8V et 5.1V. Si 0V, le fil 5V est coupé ou le calculateur est en sécurité.",
            "2. Mesurer la résistance entre la broche de masse du connecteur et la borne (-) de la batterie (doit être < 1 Ohm).",
            "3. Multimètre en voltmètre sur le fil de signal (prise rebranchée) : contact mis moteur arrêté, la tension doit être de 4.0V à 4.8V (pression atmosphérique). Au ralenti, elle doit chuter vers 1.0V-1.5V. Si elle reste à 0V, le fil est à la masse ou le capteur est HS.",
            "4. Vérifier si le capteur de papillon TPS fonctionne (ligne 5V partagée)."
        ],
        "note": "RÈGLE D'OR : Ne remplacez pas le capteur immédiatement ! Ce code P0107 indique une anomalie de signal électrique (tension < 0.2V), PAS forcément un capteur défaillant. Vérifiez en priorité l'alimentation 5V et le verrouillage du connecteur."
    },
    "P0108": {
        "title": "Capteur de pression d'admission (MAP) — Signal d'entrée trop élevé (Circuit High)",
        "cat": "Moteur / Admission d'air",
        "sev": "critique",
        "desc": "La tension sur la ligne de signal dépasse la limite maximale (> 4.8V). Le calculateur interprète cela comme une rupture de masse du capteur ou un court-circuit du signal vers l'alimentation 5V ou 12V.",
        "causes": [
            "Coupure du fil de masse du capteur MAP (flottement du potentiel à 5V)",
            "Court-circuit entre le fil de signal et le 5V ou le 12V batterie",
            "Grosse durite de dépression déboîtée (pression réelle restant atmosphérique au ralenti)",
            "Défaillance interne du capteur MAP en court-circuit"
        ],
        "symptoms": [
            "Voyant moteur allumé",
            "Fumée noire importante à l'échappement (le calculateur surdose l'essence)",
            "Moteur qui s'engorge, tourne très riche et risque de noyer les bougies",
            "Forte odeur d'essence et consommation qui explose"
        ],
        "checks": [
            "1. Mesurer immédiatement la ligne de masse du connecteur à l'ohmmètre.",
            "2. Vérifier qu'aucun fil du faisceau n'est dénudé ou fondu sur l'échappement chaud.",
            "3. Vérifier que la prise de dépression aspire bien le doigt au ralenti.",
            "4. Remplacer le capteur si les tensions faisceau sont conformes mais le signal reste bloqué à 5V."
        ],
        "note": "Attention : Un fil de masse coupé fait monter la tension à 5V immédiatement. Réparez la masse avant de remplacer le capteur."
    },
    "P0109": {
        "title": "Capteur de pression d'admission (MAP) — Circuit intermittent",
        "cat": "Moteur / Admission d'air",
        "sev": "alerte",
        "desc": "Le signal du capteur MAP subit des micro-coupures ou des sauts de tension brusques en roulant, typiquement sous l'effet des vibrations moteur ou des secousses de la route.",
        "causes": [
            "Faux contact dans le connecteur du capteur (cosses femelles écartées)",
            "Fil du faisceau électrique fatigué ou à moitié sectionné dans sa gaine",
            "Micro-fissure dans la soudure interne du capteur MAP",
            "Durite de dépression craquelée qui fuit lors des mouvements du moteur"
        ],
        "symptoms": [
            "Voyant moteur qui s'allume puis s'éteint sporadiquement",
            "Micro-coupures ou sursauts soudains lors du passage sur des bosses",
            "Code défaut enregistré en mémoire historique mais souvent absent au ralenti"
        ],
        "checks": [
            "1. Test de secouement ('Wiggle test') : Moteur au ralenti, remuer doucement le faisceau et la prise du capteur pour reproduire le défaut.",
            "2. Démonter la prise et resserrer délicatement les pinces femelles avec une aiguille.",
            "3. Vérifier l'ancrage du faisceau électrique sur le moteur."
        ],
        "note": "Conseil : 9 fois sur 10, un code intermittent est un problème mécanique de connectique ou de faisceau vibrant contre une pièce métallique."
    },
    "P0100": {
        "title": "Débitmètre d'air massique (MAF) — Panne du circuit",
        "cat": "Moteur / Admission d'air",
        "sev": "critique",
        "desc": "Anomalie générale sur le circuit du débitmètre d'air. Le calculateur ne reçoit pas de signal valide pour doser le carburant.",
        "causes": ["Connecteur débranché ou oxydé", "Fil d'alimentation ou signal coupé", "Capteur MAF défectueux"],
        "symptoms": ["Voyant moteur allumé", "Perte de puissance", "Moteur tourne en mode dégradé"],
        "checks": ["Vérifier le connecteur", "Mesurer l'alimentation 12V/5V", "Nettoyer l'élément chauffant du MAF"],
        "note": "Note : Sur Chevrolet Spark 0.8, le système fonctionne sans MAF (estimation par capteur MAP)."
    },
    "P0110": {
        "title": "Sonde de température d'air d'admission (IAT) — Dysfonctionnement circuit",
        "cat": "Moteur / Température",
        "sev": "info",
        "desc": "Le calculateur reçoit une valeur de température d'air incohérente ou hors plage.",
        "causes": ["Sonde IAT débranchée", "Faisceau coupé", "Sonde thermistance HS"],
        "symptoms": ["Voyant moteur allumé", "Légère surconsommation par temps froid"],
        "checks": ["Vérifier la sonde située sur le conduit d'admission", "Mesurer la résistance à 20°C (~2.5 kOhm)"],
        "note": "La sonde IAT sert à corriger la masse d'air admise pour affiner l'injection."
    },
    "P0113": {
        "title": "Sonde de température d'air (IAT) — Signal d'entrée trop élevé",
        "cat": "Moteur / Température",
        "sev": "alerte",
        "desc": "La tension sur la sonde IAT est au maximum (circuit ouvert ou température calculée < -40°C).",
        "causes": ["Connecteur débranché", "Fil de masse ou signal coupé", "Thermistance coupée"],
        "symptoms": ["Voyant moteur allumé", "Enrichissement carburant par sécurité"],
        "checks": ["Vérifier le branchement de la prise de température d'air", "Shunter les 2 broches pour voir si la valeur change"],
        "note": "Une prise IAT débranchée affiche instantanément -40°C et ce code P0113."
    },
    "P0115": {
        "title": "Sonde de température liquide de refroidissement (ECT) — Panne de circuit",
        "cat": "Moteur / Refroidissement",
        "sev": "critique",
        "desc": "Anomalie sur la sonde de température moteur. Le calculateur ne connaît plus la température réelle du liquide de refroidissement.",
        "causes": ["Connecteur de sonde ECT oxydé", "Fil coupé", "Sonde de température HS", "Niveau de liquide trop bas"],
        "symptoms": ["Ventilateur de radiateur qui tourne à fond en permanence", "Démarrage difficile", "Consommation excessive"],
        "checks": ["Vérifier le niveau de liquide", "Contrôler la prise de sonde", "Mesurer la résistance de la sonde"],
        "note": "Par sécurité, l'ECU allume souvent le motoventilateur en permanence lorsqu'il perd la sonde ECT."
    },
    "P0120": {
        "title": "Capteur de position du papillon (TPS) — Dysfonctionnement circuit",
        "cat": "Moteur / Commande des gaz",
        "sev": "critique",
        "desc": "Anomalie sur le potentiomètre mesurant l'ouverture du boîtier papillon des gaz.",
        "causes": ["Connecteur TPS encrassé", "Piste potentiométrique usée", "Faisceau électrique endommagé"],
        "symptoms": ["Trous à l'accélération", "Ralenti bloqué ou instable", "Moteur ne prend pas ses tours"],
        "checks": ["Inspecter la connectique", "Mesurer la tension variable lors de l'ouverture progressive des gaz"],
        "note": "Surveille également la ligne 5V commune avec le capteur MAP."
    },
    "P0130": {
        "title": "Sonde lambda amont (Ligne 1, Sonde 1) — Circuit défaillant",
        "cat": "Échappement / Dépollution",
        "sev": "alerte",
        "desc": "La sonde à oxygène amont située avant le pot catalytique ne transmet pas de signal cohérent.",
        "causes": ["Sonde lambda usée ou contaminée", "Fil du signal fondu ou coupé", "Connecteur plein d'huile/eau"],
        "symptoms": ["Surconsommation d'essence", "Échappement qui sent mauvais", "Contrôle technique recalé pour pollution"],
        "checks": ["Inspecter le faisceau sous le collecteur", "Vérifier la tension oscillante (doit alterner entre 0.1V et 0.9V)"],
        "note": "Une sonde lambda a une durée de vie typique de 100 000 à 150 000 km."
    },
    "P0135": {
        "title": "Chauffage de la sonde lambda amont — Panne de circuit",
        "cat": "Échappement / Dépollution",
        "sev": "info",
        "desc": "La résistance interne qui chauffe la sonde lambda pour la faire fonctionner rapidement à froid est coupée.",
        "causes": ["Résistance chauffante de la sonde grillée", "Fusible d'alimentation du chauffage grillé", "Faisceau endommagé"],
        "symptoms": ["Voyant moteur allumé", "Pollution excessive pendant les 5 premières minutes"],
        "checks": ["Mesurer la résistance entre les deux fils blancs de la sonde (doit faire environ 5 à 15 Ohms)."],
        "note": "Si la résistance est infinie (coupée), la sonde doit être remplacée."
    },
    "P0171": {
        "title": "Système de dosage carburant trop pauvre (Ligne 1)",
        "cat": "Moteur / Carburation",
        "sev": "alerte",
        "desc": "Trop d'air ou pas assez d'essence dans le mélange air/carburant. Le calculateur a atteint sa limite maximale d'enrichissement.",
        "causes": ["Prise d'air à l'admission", "Pression d'essence trop faible (pompe fatiguée, filtre bouché)", "Injecteur partiellement encrassé", "Capteur MAP sous-évaluant la pression"],
        "symptoms": ["Manque de reprise", "Moteur qui chauffe davantage", "À-coups sous charge"],
        "checks": ["Traquer les prises d'air au nettoyant frein", "Remplacer le filtre à essence", "Mesurer la pression de rampe d'injection"],
        "note": "Mimo, vérifie les prises d'air et le filtre à essence en priorité !"
    },
    "P0172": {
        "title": "Système de dosage carburant trop riche (Ligne 1)",
        "cat": "Moteur / Carburation",
        "sev": "alerte",
        "desc": "Trop d'essence ou pas assez d'air dans le mélange. Le calculateur réduit au maximum l'injection mais le mélange reste trop gras.",
        "causes": ["Filtre à air très encrassé / bouché", "Régulateur de pression d'essence défaillant", "Injecteur qui fuit ou reste ouvert", "Capteur MAP indiquant une pression trop forte"],
        "symptoms": ["Fumée noire à l'échappement", "Odeur forte d'essence", "Bougies noires calaminées", "Surconsommation"],
        "checks": ["Contrôler et remplacer le filtre à air", "Vérifier l'état des bougies", "Contrôler le capteur MAP"],
        "note": "Mimo, vérifie ton filtre à air et le capteur MAP !"
    },
    "P0300": {
        "title": "Ratés d'allumage aléatoires / cylindres multiples détectés",
        "cat": "Allumage / Combustion",
        "sev": "critique",
        "desc": "Le capteur de vilebrequin détecte des ralentissements anormaux de la rotation du moteur, provoqués par des combustions incomplètes sur plusieurs cylindres.",
        "causes": ["Bougies d'allumage usées ou écartement incorrect", "Faisceau de bougies / câbles haute tension fissurés", "Bobine d'allumage fatiguée", "Qualité de carburant médiocre ou eau dans le réservoir", "Pression d'essence insuffisante"],
        "symptoms": ["Moteur qui broute et vibre fortement", "Voyant moteur qui clignote (danger catalyseur)", "Perte importante de puissance"],
        "checks": ["Démonter et inspecter les bougies (couleur, usure)", "Tester les câbles d'allumage la nuit pour voir d'éventuelles étincelles", "Vérifier la bobine d'allumage"],
        "note": "URGENT : Un voyant moteur qui clignote indique un risque immédiat de destruction du pot catalytique par l'essence imbrûlée !"
    },
    "P0301": {
        "title": "Ratés d'allumage détectés sur le cylindre 1",
        "cat": "Allumage / Combustion",
        "sev": "critique",
        "desc": "Combustion manquante ou incomplète localisée spécifiquement sur le cylindre numéro 1.",
        "causes": ["Bougie du cylindre 1 usée ou noyée", "Câble HT du cylindre 1 coupé ou poreux", "Injecteur 1 bouché", "Compression faible sur le cylindre 1"],
        "symptoms": ["Moteur qui tourne sur 2 cylindres (sur Spark 3 cylindres)", "Bruit de tracteur", "Fortes vibrations"],
        "checks": ["Permuter la bougie 1 avec la 2 : si le défaut migre en P0302, la bougie est coupable.", "Vérifier l'étincelle à la sortie du câble 1."],
        "note": "Sur une Spark 0.8 (3 cylindres), perdre un cylindre divise la puissance par trois !"
    },
    "P0302": {
        "title": "Ratés d'allumage détectés sur le cylindre 2",
        "cat": "Allumage / Combustion",
        "sev": "critique",
        "desc": "Combustion manquante ou incomplète sur le cylindre 2.",
        "causes": ["Bougie du cylindre 2 usée", "Câble d'allumage du cylindre 2 poreux", "Injecteur 2 encrassé"],
        "symptoms": ["Moteur qui tremble au ralenti", "Manque total de reprise", "Odeur d'essence"],
        "checks": ["Contrôler la bougie 2 et le câble d'allumage."],
        "note": "Vérifier bougies et câbles haute tension."
    },
    "P0303": {
        "title": "Ratés d'allumage détectés sur le cylindre 3",
        "cat": "Allumage / Combustion",
        "sev": "critique",
        "desc": "Combustion manquante ou incomplète sur le cylindre 3 (dernier cylindre sur moteur F8CV Spark).",
        "causes": ["Bougie cylindre 3", "Câble bougie 3", "Injecteur 3", "Jeu aux soupapes"],
        "symptoms": ["Ralenti très heurté", "Vibrations fortes dans l'habitacle", "Manque de puissance"],
        "checks": ["Inspecter la bougie 3 et le câble d'allumage."],
        "note": "Sur moteur Spark 0.8 F8CV, contrôler le jeu aux culbuteurs si les bougies sont neuves."
    },
    "P0335": {
        "title": "Capteur de position de vilebrequin (PMH) — Panne du circuit",
        "cat": "Allumage / Synchronisation",
        "sev": "critique",
        "desc": "Le calculateur ne capte plus la rotation du volant moteur. Sans ce signal, l'allumage et l'injection ne peuvent pas être synchronisés.",
        "causes": ["Capteur PMH sale ou couvert de limaille métallique", "Faisceau coupé ou broche oxydée", "Capteur PMH défaillant", "Cible dentée du volant moteur endommagée"],
        "symptoms": ["Moteur refuse de démarrer (le démarreur tourne dans le vide)", "Coupure moteur soudaine en roulant", "Compte-tours à 0 tr/min"],
        "checks": ["Démonter le capteur PMH et nettoyer sa tête magnétique", "Mesurer la résistance de la bobine du capteur (~500-1000 Ohms)"],
        "note": "Panne classique de non-démarrage ou coupure nette du moteur."
    },
    "P0340": {
        "title": "Capteur de position d'arbre à cames (AAC) — Panne du circuit",
        "cat": "Allumage / Distribution",
        "sev": "critique",
        "desc": "Signal de synchronisation de l'arbre à cames absent ou incohérent avec le vilebrequin.",
        "causes": ["Capteur AAC défaillant", "Câblage abîmé", "Courroie de distribution détendue ou décalée d'une dent"],
        "symptoms": ["Démarrage long (nécessite plusieurs tours de démarreur)", "Légère perte de puissance"],
        "checks": ["Vérifier le connecteur du capteur d'arbre à cames", "Contrôler le calage de la courroie de distribution"],
        "note": "Vérifier impérativement le calage de distribution si le capteur est bon."
    },
    "P0420": {
        "title": "Efficacité du catalyseur inférieure au seuil (Ligne 1)",
        "cat": "Échappement / Dépollution",
        "sev": "alerte",
        "desc": "La capacité de stockage d'oxygène du catalyseur est trop faible. La sonde lambda aval commence à osciller au même rythme que la sonde amont.",
        "causes": ["Catalyseur usé, calaminé ou fondu par des ratés d'allumage", "Fuite à l'échappement entre collecteur et catalyseur", "Sonde lambda aval défectueuse"],
        "symptoms": ["Voyant moteur allumé", "Aucun symptôme de conduite apparent ou léger bruit métallique d'échappement"],
        "checks": ["Contrôler l'étanchéité de la ligne d'échappement", "Vérifier le bon fonctionnement des 2 sondes lambda"],
        "note": "Attention : Des ratés d'allumage non réparés finissent par détruire le catalyseur et créer ce code."
    },
    "P0500": {
        "title": "Capteur de vitesse du véhicule (VSS) — Panne de circuit",
        "cat": "Châssis / Vitesse",
        "sev": "alerte",
        "desc": "Le calculateur moteur ne reçoit pas l'information de vitesse d'avancement du véhicule.",
        "causes": ["Capteur de vitesse de boîte de vitesses débranché ou HS", "Pignon d'entraînement plastique usé dans la boîte", "Faisceau coupé"],
        "symptoms": ["Aiguille du compteur de vitesse qui ne monte pas ou saute", "Ralenti instable à la décélération lors des arrêts aux feux", "Consommation kilométrique non incrémentée"],
        "checks": ["Vérifier le capteur de vitesse situé sur la boîte de vitesses", "Contrôler le connecteur et l'état du câble"],
        "note": "Sur Spark 0.8, le capteur VSS est vissé sur le carter de boîte de vitesses."
    },
    "P0505": {
        "title": "Système de régulation du ralenti (Vanne IAC) — Dysfonctionnement",
        "cat": "Moteur / Régulation ralenti",
        "sev": "alerte",
        "desc": "Le calculateur n'arrive pas à stabiliser le régime de ralenti à la consigne voulue.",
        "causes": ["Moteur pas-à-pas de ralenti (IAC) encrassé de suie", "Conduit d'air de ralenti bouché", "Prise d'air admission"],
        "symptoms": ["Moteur cale dès qu'on lâche l'accélérateur", "Ralenti bloqué trop haut (ex: 1500 tr/min)"],
        "checks": ["Démonter la vanne IAC et la nettoyer avec un nettoyant carburateur", "Nettoyer l'alésage du boîtier papillon"],
        "note": "Un simple nettoyage de la pointe de la vanne IAC résout ce problème dans 80% des cas."
    },
    "P0700": {
        "title": "Système de commande de boîte de vitesses — Demande d'allumage voyant",
        "cat": "Transmission / Boîte",
        "sev": "critique",
        "desc": "Le calculateur de transmission (TCM) a détecté une anomalie sur la boîte de vitesses et demande au calculateur moteur d'allumer le voyant.",
        "causes": ["Défaut interne de boîte automatique (si équipé)", "Capteur de vitesse d'arbre de boîte défaillant", "Anomalie d'électrovanne de boîte"],
        "symptoms": ["Boîte en mode secours / bloquée sur un rapport", "Voyant moteur allumé"],
        "checks": ["Scanner le calculateur de boîte (TCM) pour lire le sous-code précis.", "Vérifier le niveau d'huile de boîte."],
        "note": "Sur Spark à boîte manuelle, ce code peut résulter d'un mauvais décodage d'une trame moteur."
    },
    "U0100": {
        "title": "Perte de communication avec le calculateur moteur (ECM/PCM)",
        "cat": "Réseau / Communication CAN",
        "sev": "critique",
        "desc": "Les autres calculateurs (combiné, ABS, BCM) ne reçoivent plus les trames périodiques du calculateur moteur sur le bus CAN.",
        "causes": ["Fusible d'alimentation calculateur moteur grillé", "Relais principal (Main Relay) défaillant", "Mauvaise masse moteur / châssis", "Lignes CAN-High ou CAN-Low en court-circuit ou coupées"],
        "symptoms": ["Moteur ne démarre pas", "Tableau de bord affichant des tirets ou tous les voyants allumés", "Impossible de se connecter au scanner"],
        "checks": ["Contrôler les fusibles compartiment moteur", "Vérifier le relais principal", "Mesurer la tension de batterie", "Mesurer la résistance du bus CAN (60 Ohms entre pin 6 et 14 OBD)"],
        "note": "Vérifier impérativement le relais principal et l'état des cosses de batterie."
    },
    "U0155": {
        "title": "Perte de communication avec le tableau de bord (IPC)",
        "cat": "Réseau / Communication CAN",
        "sev": "info",
        "desc": "Absence de communication entre le calculateur moteur et le bloc compteurs.",
        "causes": ["Connecteur arrière du combiné desserré", "Fusible du tableau de bord", "Problème faisceau CAN habitacle"],
        "symptoms": ["Aiguilles du tableau de bord inertes", "Voyants qui ne s'allument pas"],
        "checks": ["Vérifier le fusible du tableau de bord", "Vérifier la connectique du combiné"],
        "note": "Défaut de liaison habitacle."
    }
}

# Translation lexicon for English OBDex titles to French
LEXICON = [
    # Systems
    (r"\bFuel Volume Regulator\b", "Régulateur de débit carburant"),
    (r"\bManifold Absolute Pressure/Barometric Pressure\b", "Capteur de pression d'admission (MAP/BARO)"),
    (r"\bManifold Absolute Pressure\b", "Capteur de pression d'admission (MAP)"),
    (r"\bMass or Volume Air Flow\b", "Débitmètre d'air (MAF)"),
    (r"\bEngine Coolant Temperature\b", "Sonde de température liquide de refroidissement (ECT)"),
    (r"\bIntake Air Temperature\b", "Sonde de température d'air d'admission (IAT)"),
    (r"\bThrottle/Pedal Position Sensor/Switch\b", "Capteur de position papillon/pédale (TPS)"),
    (r"\bThrottle Position Sensor\b", "Capteur de position papillon (TPS)"),
    (r"\bOxygen Sensor\b", "Sonde lambda (O2)"),
    (r"\bO2 Sensor\b", "Sonde lambda (O2)"),
    (r"\bCrankshaft Position\b", "Capteur de vilebrequin (PMH)"),
    (r"\bCamshaft Position\b", "Capteur d'arbre à cames (AAC)"),
    (r"\bKnock Sensor\b", "Capteur de cliquetis"),
    (r"\bCatalyst System\b", "Système catalytique"),
    (r"\bEvaporative Emission System\b", "Système EVAP (recyclage vapeurs d'essence)"),
    (r"\bVehicle Speed Sensor\b", "Capteur de vitesse du véhicule (VSS)"),
    (r"\bIdle Air Control\b", "Régulation du ralenti (IAC)"),
    (r"\bTransmission Control Module\b", "Calculateur de transmission (TCM)"),
    (r"\bEngine Control Module\b", "Calculateur moteur (ECM/PCM)"),
    (r"\bAnti-Lock Brake System\b", "Système antiblocage (ABS)"),
    (r"\bInstrument Panel Cluster\b", "Combiné d'instruments / Tableau de bord"),
    (r"\bBody Control Module\b", "Module de carrosserie (BCM)"),
    (r"\bLost Communication With\b", "Perte de communication avec"),
    (r"\bControl Module\b", "Module de commande"),
    (r"\bFuel Pressure Regulator\b", "Régulateur de pression carburant"),
    (r"\bFuel Rail Pressure\b", "Pression de rampe d'injection"),
    (r"\bFuel Injector\b", "Injecteur de carburant"),
    (r"\bEGR\b", "Recirculation des gaz (EGR)"),
    (r"\bExhaust Gas Recirculation\b", "Recirculation des gaz (EGR)"),

    # Attributes
    (r"\bCircuit Range/Performance\b", "Plage de mesure / Rendement du circuit"),
    (r"\bCircuit Low\b", "Signal d'entrée trop bas (Circuit Low)"),
    (r"\bCircuit High\b", "Signal d'entrée trop élevé (Circuit High)"),
    (r"\bCircuit Intermittent\b", "Signal intermittent"),
    (r"\bCircuit Open\b", "Circuit ouvert"),
    (r"\bCircuit Malfunction\b", "Dysfonctionnement du circuit"),
    (r"\bCircuit\b", "Circuit"),
    (r"\bEfficiency Below Threshold\b", "Efficacité sous le seuil"),
    (r"\bBank 1\b", "Ligne 1"),
    (r"\bBank 2\b", "Ligne 2"),
    (r"\bSensor 1\b", "Sonde amont (1)"),
    (r"\bSensor 2\b", "Sonde aval (2)"),
    (r"\bSensor 3\b", "Sonde 3"),
    (r"\bSlow Response\b", "Temps de réponse lent"),
    (r"\bNo Activity Detected\b", "Aucune activité détectée"),
    (r"\bRandom/Multiple Cylinder Misfire Detected\b", "Ratés d'allumage aléatoires / cylindres multiples"),
    (r"\bCylinder (\d+) Misfire Detected\b", r"Ratés d'allumage détectés sur le cylindre \1"),
    (r"\bSystem Too Lean\b", "Système trop pauvre"),
    (r"\bSystem Too Rich\b", "Système trop riche"),
    (r"\bPerformance\b", "Rendement / Performance"),
    (r"\bLow Input\b", "Signal d'entrée trop faible"),
    (r"\bHigh Input\b", "Signal d'entrée trop fort"),
    (r"\bOpen Circuit\b", "Circuit ouvert"),
    (r"\bShort to Ground\b", "Court-circuit à la masse"),
    (r"\bShort to Voltage\b", "Court-circuit au plus"),
]

def translate_title(en_title):
    res = en_title
    for pat, rep in LEXICON:
        res = re.sub(pat, rep, res, flags=re.IGNORECASE)
    return res

def determine_category(code):
    first = code[0].upper()
    if first == 'P':
        sub = code[1:3]
        if sub in ['00', '01', '02']:
            return "Moteur / Alimentation air et carburant"
        elif sub == '03':
            return "Allumage / Combustion"
        elif sub == '04':
            return "Échappement / Contrôle des émissions"
        elif sub == '05':
            return "Vitesse / Régulation ralenti"
        elif sub == '06':
            return "Calculateur moteur (ECU/ECM)"
        elif sub in ['07', '08', '09']:
            return "Boîte de vitesses / Transmission"
        else:
            return "Groupe motopropulseur étendu"
    elif first == 'C':
        return "Châssis / Freinage ABS / Direction"
    elif first == 'B':
        return "Carrosserie / Habitacle / Airbags"
    elif first == 'U':
        return "Réseau / Communication bus CAN"
    return "Diagnostic système"

def determine_severity(code, title):
    first = code[0].upper()
    title_l = title.lower()
    if "ratés" in title_l or "misfire" in title_l or "pmh" in title_l or "vilebrequin" in title_l or "trop bas" in title_l or "circuit low" in title_l or code in ["P0107", "P0108", "P0300", "P0301", "P0302", "P0303", "P0335", "U0100"]:
        return "critique"
    if "perte de communication" in title_l or "panne" in title_l or "trop pauvre" in title_l or "trop riche" in title_l or "rendement" in title_l or "plage" in title_l:
        return "alerte"
    return "info"

def main():
    print("=== Construction de la base de codes défaut SPARK V3 ===")
    
    final_db = {}

    # 1. Download and parse obdex families
    families = ['P0xxx', 'P2xxx', 'P3xxx', 'U0xxx', 'U3xxx', 'C0xxx', 'B0xxx']
    for fam in families:
        url = f"https://raw.githubusercontent.com/foerbsnavi/obdex/main/data/generic/{fam}_enriched.yaml"
        print(f"Téléchargement {fam} depuis {url}...")
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            raw = urllib.request.urlopen(req, timeout=30).read().decode('utf-8')
            
            # Extract code, category, title en
            pattern = re.compile(r'- code:\s*([A-Z0-9]{5})\s+category:\s*(\w+)\s+title:\s+en:\s*([^\n]+)')
            matches = pattern.findall(raw)
            print(f"  -> {len(matches)} codes extraits dans {fam}")
            
            for code, cat, en_title in matches:
                fr_title = translate_title(en_title.strip('"\' '))
                sev = determine_severity(code, fr_title)
                category = determine_category(code)
                
                final_db[code] = {
                    "msg": fr_title,
                    "sev": sev,
                    "cat": category
                }
        except Exception as e:
            print(f"  Erreur sur {fam}: {e}")

    # 2. Merge expert dossiers (overrides / enriches)
    print(f"\nFusion des {len(EXPERT_DOSSIERS)} dossiers experts approfondis...")
    for code, dossier in EXPERT_DOSSIERS.items():
        entry = {
            "msg": dossier["title"],
            "title": dossier["title"],
            "sev": dossier["sev"],
            "cat": dossier["cat"],
            "desc": dossier["desc"],
            "causes": dossier["causes"],
            "symptoms": dossier["symptoms"],
            "checks": dossier["checks"],
            "note": dossier.get("note", "")
        }
        final_db[code] = entry

    # 3. Save to assets/data/dtc_codes.json
    out_path = os.path.join("assets", "data", "dtc_codes.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(final_db, f, ensure_ascii=False, indent=2)

    file_size_kb = os.path.getsize(out_path) / 1024
    print(f"\n[SUCCÈS] Base DTC générée : {len(final_db)} codes.")
    print(f"Fichier : {out_path} ({file_size_kb:.1f} KB)")
    
    # Check specific MAP codes
    for c in ["P0105", "P0106", "P0107", "P0108", "P0109"]:
        if c in final_db:
            print(f"  [OK] {c}: {final_db[c]['msg']} (causes: {len(final_db[c].get('causes', []))})")
        else:
            print(f"  [MANQUANT] {c} !")

if __name__ == "__main__":
    main()
