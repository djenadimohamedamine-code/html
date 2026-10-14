"""
SPARK V3 — Générateur de la base de données OBD-II DTC (SAE J2012)
Source des données génériques : SAE J2012 / OBDex (Domaine public CC0-1.0)
Dossiers experts enrichis pour la Chevrolet Spark 0.8L (Moteur Daewoo F8CV)
Entièrement hors connexion (local).
"""

import urllib.request
import json
import re
import os
import sys

# Dossiers d'expertise technique automobile approfondis (sécurisés et vérifiés)
EXPERT_DOSSIERS = {
    "P0105": {
        "title": "Capteur de pression d'admission (MAP) / Barométrique — Dysfonctionnement du circuit",
        "title_en": "Manifold Absolute Pressure/Barometric Pressure Circuit Malfunction",
        "cat": "Moteur / Admission d'air",
        "sev": "alerte",
        "desc": "Le calculateur (ECU) détecte une anomalie électrique générale sur le circuit du capteur MAP ou barométrique. Le signal de pression reçu ne correspond à aucune condition normale de fonctionnement moteur.",
        "causes": [
            "Connecteur du capteur MAP débranché, mal enclenché ou broches oxydées",
            "Faisceau électrique coupé, pincé ou endommagé",
            "Défaut sur l'alimentation régulée de référence 5V venant du calculateur",
            "Durite de dépression fissurée, poreuse ou déconnectée (selon montage)",
            "Défaillance interne du capteur de pression d'admission"
        ],
        "symptoms": [
            "Voyant moteur (Check Engine) allumé au tableau de bord",
            "Ralenti instable ou calage possible à froid",
            "Légers trous ou hésitations à l'accélération",
            "Surconsommation de carburant constatée",
            "Odeur d'essence imbrûlée à l'échappement"
        ],
        "checks": [
            "Contrôle accessible : inspecter visuellement le connecteur 3 broches du capteur MAP (oxydation, humidité, verrouillage).",
            "Contrôle accessible : inspecter l'état et l'étanchéité de la durite de dépression reliant le capteur au collecteur.",
            "Contrôle électrique (multimètre) : contact mis moteur arrêté, vérifier la tension d'alimentation de référence (valeur indicative nominale ~5.0V, généralement 4.8V à 5.1V selon spécification ECU).",
            "Contrôle électrique : vérifier la continuité de la ligne de masse (< 1 Ω vers la borne négative batterie, circuit hors tension).",
            "Contrôle signal : au ralenti, vérifier la chute de tension du signal (~1.0V à 1.8V selon la dépression réelle au collecteur)."
        ],
        "note": "Important : Ne remplacez pas le capteur sans contrôle préalable. Une connectique oxydée, des cosses écartées ou une durite de dépression fissurée sont des causes fréquentes."
    },
    "P0106": {
        "title": "Capteur de pression d'admission (MAP) — Problème de plage / rendement",
        "title_en": "Manifold Absolute Pressure/Barometric Pressure Circuit Range/Performance",
        "cat": "Moteur / Admission d'air",
        "sev": "alerte",
        "desc": "La pression mesurée par le capteur MAP est incohérente avec les autres paramètres moteur (régime RPM, ouverture papillon TPS, température IAT). Par exemple, pression atmosphérique lue papillon fermé.",
        "causes": [
            "Prise d'air au collecteur d'admission, joints ou boîtier papillon",
            "Durite de dépression percée, pincée ou débranchée",
            "Boîtier papillon ou conduit de prise de dépression encrassé",
            "Capteur MAP encrassé par des vapeurs d'huile (reniflard)",
            "Décalage du calage de distribution (perte de dépression moteur)",
            "Capteur MAP dérivant hors tolérances constructeur"
        ],
        "symptoms": [
            "Ralenti instable oscillant ou 'pompant'",
            "À-coups à bas régime et vitesse stabilisée",
            "Mélange air/carburant perturbé par la mauvaise estimation de charge",
            "Manque de souplesse sous charge"
        ],
        "checks": [
            "Contrôle accessible : inspection visuelle méthodique de toutes les durites de dépression, du manchon d'admission et du reniflard.",
            "Contrôle accessible : vérifier le serrage des colliers d'admission et l'état des joints du boîtier papillon.",
            "Contrôle accessible : démonter le capteur MAP pour vérifier que son orifice n'est pas obstrué par des résidus d'huile ou calamine.",
            "Contrôle télémétrie : comparer la pression MAP contact mis (~100 kPa au niveau de la mer) et moteur chaud au ralenti (~30-40 kPa).",
            "Contrôle spécialisé atelier : test d'étanchéité au générateur de fumée basse pression (smoke tester) ou mesure de dépression au manomètre mécanique."
        ],
        "note": "Rappel de sécurité : Ne jamais pulvériser de liquide inflammable sur un moteur tournant pour détecter des fuites. Privilégier une inspection visuelle ou un test à la machine à fumée."
    },
    "P0107": {
        "title": "Capteur de pression d'admission (MAP) — Signal d'entrée trop bas (Circuit Low)",
        "title_en": "Manifold Absolute Pressure/Barometric Pressure Circuit Low Input",
        "cat": "Moteur / Admission d'air",
        "sev": "critique",
        "desc": "La tension sur la ligne de signal du capteur MAP est descendue sous le seuil critique (généralement < 0.2V). Le calculateur interprète cela comme une coupure de l'alimentation 5V ou un court-circuit franc du signal vers la masse.",
        "causes": [
            "Connecteur du capteur MAP débranché, mal verrouillé ou cosse détendue",
            "Coupure de la ligne d'alimentation de référence 5V (Vref) venant du calculateur",
            "Fil de signal en court-circuit avec la masse ou le bloc moteur",
            "Anomalie sur un autre capteur partageant la ligne 5V commune (ex: capteur papillon TPS)",
            "Défaillance interne du capteur MAP"
        ],
        "symptoms": [
            "Voyant moteur CHECK ENGINE allumé en continu",
            "Le calculateur applique une valeur de pression de secours par défaut",
            "Réponse hésitante à l'accélérateur et légers trous",
            "Estimation de carburant faussée en l'absence de mesure réelle MAP",
            "Perte d'agrément de conduite à froid"
        ],
        "checks": [
            "Contrôle accessible : débrancher la prise du capteur MAP et vérifier l'état des broches métalliques (ni tordues ni corrodées).",
            "Contrôle électrique : contact mis moteur arrêté, mesurer au multimètre la tension d'alimentation entre la broche 5V et la masse du connecteur (valeur indicative nominale ~5.0V, généralement 4.8V à 5.1V). Si 0V, inspecter le faisceau et les fusibles de gestion moteur.",
            "Contrôle électrique : mesurer la résistance entre la broche de masse du connecteur et la borne négative de la batterie (doit être < 1 Ω circuit hors tension).",
            "Contrôle électrique : prise rebranchée, mesurer la tension du fil de signal par l'arrière de la prise (backprobing sécurisé, sans percer l'isolant). Contact mis moteur arrêté : ~4.0V à 4.8V (pression atmosphérique). Au ralenti stable : ~1.0V à 1.8V.",
            "Contrôle accessible : vérifier le fonctionnement du capteur de papillon TPS qui partage la référence 5V régulée."
        ],
        "note": "RÈGLE D'OR : Ne remplacez pas le capteur immédiatement ! Le code P0107 indique une anomalie de signal électrique (tension trop basse), et non la certitude d'un capteur HS. Contrôlez l'alimentation 5V et l'état mécanique du connecteur avant tout remplacement."
    },
    "P0108": {
        "title": "Capteur de pression d'admission (MAP) — Signal d'entrée trop élevé (Circuit High)",
        "title_en": "Manifold Absolute Pressure/Barometric Pressure Circuit High Input",
        "cat": "Moteur / Admission d'air",
        "sev": "critique",
        "desc": "La tension sur la ligne de signal dépasse la limite maximale autorisée (> 4.8V). Le calculateur interprète cela comme une rupture de masse du capteur ou un court-circuit du signal vers une tension d'alimentation 5V ou 12V.",
        "causes": [
            "Coupure ou mauvaise connexion du fil de masse du capteur MAP (flottement du signal à 5V)",
            "Court-circuit entre le fil de signal et le fil d'alimentation 5V ou un conducteur 12V",
            "Grosse durite de dépression déboîtée (pression réelle restant atmosphérique au ralenti)",
            "Défaillance interne du capteur MAP"
        ],
        "symptoms": [
            "Voyant moteur allumé",
            "Mélange trop riche (le calculateur injecte plus de carburant croyant le moteur en pleine charge)",
            "Fumée noire à l'échappement et forte odeur d'essence",
            "Consommation de carburant anormalement élevée"
        ],
        "checks": [
            "Contrôle accessible : vérifier le branchement de la prise et l'état physique du faisceau électrique.",
            "Contrôle accessible : vérifier que la durite de dépression est bien raccordée et aspire correctement.",
            "Contrôle électrique : contact coupé, mesurer la résistance entre la broche de masse du capteur et la masse châssis (< 1 Ω).",
            "Contrôle électrique : contact mis, vérifier l'absence de court-circuit entre le fil de signal et le 12V batterie."
        ],
        "note": "Attention : Une rupture du fil de masse provoque immédiatement la montée du signal à 5V. Réparez la connexion de masse avant d'envisager un remplacement de capteur."
    },
    "P0109": {
        "title": "Capteur de pression d'admission (MAP) — Circuit intermittent",
        "title_en": "Manifold Absolute Pressure/Barometric Pressure Circuit Intermittent",
        "cat": "Moteur / Admission d'air",
        "sev": "alerte",
        "desc": "Le signal du capteur MAP subit des micro-coupures ou des sauts de tension brusques en roulant, souvent provoqués par les vibrations moteur ou les mouvements de caisse.",
        "causes": [
            "Faux contact dans le connecteur du capteur (cosses femelles desserrées ou oxydées)",
            "Fil du faisceau électrique fragilisé ou partiellement sectionné sous sa gaine",
            "Durite de dépression craquelée qui fuit lors des basculements du bloc moteur",
            "Micro-fissure interne sur le capteur"
        ],
        "symptoms": [
            "Voyant moteur qui s'allume de façon sporadique puis s'éteint",
            "Micro-coupures ou sursauts brefs lors du passage sur des irrégularités de la route",
            "Code défaut enregistré en mémoire historique mais parfois introuvable à l'arrêt"
        ],
        "checks": [
            "Contrôle accessible : inspecter visuellement les cosses métalliques du connecteur (ni jeu anormal ni corrosion).",
            "Contrôle faisceau : moteur au ralenti, manipuler doucement le faisceau électrique du capteur pour vérifier si le régime varie ou si le voyant s'allume (wiggle test).",
            "Contrôle durite : inspecter la souplesse et l'étanchéité de la durite de dépression sur toute sa longueur."
        ],
        "note": "Conseil atelier : Les défauts intermittents résultent fréquemment d'un problème mécanique de connectique ou d'un faisceau frottant contre un élément métallique du compartiment moteur."
    },
    "P0100": {
        "title": "Débitmètre d'air massique (MAF) — Panne du circuit",
        "title_en": "Mass or Volume Air Flow Circuit Malfunction",
        "cat": "Moteur / Admission d'air",
        "sev": "critique",
        "desc": "Anomalie générale sur le circuit du débitmètre d'air. Le calculateur ne reçoit pas de signal valide pour doser le carburant.",
        "causes": ["Connecteur débranché ou oxydé", "Fil d'alimentation ou signal coupé", "Capteur MAF défectueux"],
        "symptoms": ["Voyant moteur allumé", "Perte de puissance", "Moteur tourne en mode dégradé"],
        "checks": [
            "Contrôle accessible : vérifier le connecteur et le faisceau du capteur.",
            "Contrôle électrique : mesurer les tensions d'alimentation et la masse selon schéma technique.",
            "Contrôle pro : nettoyer délicatement l'élément sensible avec un nettoyant aérosol spécifique capteur débitmètre (sans solvant agressif)."
        ],
        "note": "Note pour Chevrolet Spark 0.8 : Le moteur F8CV fonctionne généralement sans débitmètre MAF, en utilisant l'estimation Speed-Density basée sur le capteur MAP."
    },
    "P0110": {
        "title": "Sonde de température d'air d'admission (IAT) — Dysfonctionnement circuit",
        "title_en": "Intake Air Temperature Circuit Malfunction",
        "cat": "Moteur / Température",
        "sev": "info",
        "desc": "Le calculateur reçoit une valeur de température d'air incohérente ou hors plage de fonctionnement normal.",
        "causes": ["Sonde IAT débranchée", "Faisceau coupé ou broches corrodées", "Thermistance de la sonde défaillante"],
        "symptoms": ["Voyant moteur allumé", "Légère surconsommation par temps froid"],
        "checks": [
            "Contrôle accessible : vérifier la sonde située sur le conduit d'admission d'air et son connecteur.",
            "Contrôle électrique : mesurer la résistance de la thermistance débranchée au multimètre (~2 à 3 kΩ à température ambiante de 20°C selon spécification)."
        ],
        "note": "La sonde IAT permet au calculateur de corriger la densité de l'air pour affiner le temps d'injection."
    },
    "P0113": {
        "title": "Sonde de température d'air (IAT) — Signal d'entrée trop élevé",
        "title_en": "Intake Air Temperature Circuit High Input",
        "cat": "Moteur / Température",
        "sev": "alerte",
        "desc": "La tension sur la sonde IAT est au maximum (circuit ouvert ou température équivalente lue < -40°C par le calculateur).",
        "causes": ["Connecteur de la sonde débranché", "Fil de masse ou de signal coupé", "Thermistance interne coupée"],
        "symptoms": ["Voyant moteur allumé", "Enrichissement carburant appliqué par stratégie de sécurité"],
        "checks": [
            "Contrôle accessible : vérifier le verrouillage de la prise de la sonde IAT.",
            "Contrôle électrique : mesurer au multimètre la résistance de la sonde débranchée (hors tension). Une résistance infinie confirme une coupure interne."
        ],
        "note": "Précautions : Ne jamais shunter directement les broches sans résistance de protection pour éviter d'endommager l'étage d'entrée de l'ECU."
    },
    "P0115": {
        "title": "Sonde de température liquide de refroidissement (ECT) — Panne de circuit",
        "title_en": "Engine Coolant Temperature Circuit Malfunction",
        "cat": "Moteur / Refroidissement",
        "sev": "critique",
        "desc": "Anomalie sur le circuit de la sonde de température moteur. Le calculateur ne dispose plus de la mesure réelle de température d'eau.",
        "causes": ["Connecteur de sonde ECT oxydé ou débranché", "Faisceau coupé", "Sonde ECT défaillante", "Niveau de liquide de refroidissement insuffisant"],
        "symptoms": ["Ventilateur de refroidissement tournant en continu par sécurité", "Démarrage difficile à froid ou à chaud", "Consommation excessive"],
        "checks": [
            "Contrôle accessible : vérifier le niveau de liquide de refroidissement dans le vase d'expansion (moteur froid).",
            "Contrôle accessible : inspecter la connectique de la sonde ECT sur le boîtier thermostat.",
            "Contrôle électrique : mesurer la résistance de la thermistance à froid (~2-3 kΩ à 20°C) et à chaud (~200-300 Ω à 90°C)."
        ],
        "note": "Par stratégie de protection thermique, l'ECU enclenche généralement le motoventilateur en permanence lorsqu'il perd le signal de la sonde ECT."
    },
    "P0120": {
        "title": "Capteur de position du papillon (TPS) — Dysfonctionnement circuit",
        "title_en": "Throttle/Pedal Position Sensor/Switch A Circuit Malfunction",
        "cat": "Moteur / Commande des gaz",
        "sev": "critique",
        "desc": "Anomalie sur le potentiomètre mesurant l'angle d'ouverture du boîtier papillon des gaz.",
        "causes": ["Connecteur TPS encrassé ou oxydé", "Piste potentiométrique usée avec zones de coupure", "Faisceau électrique endommagé"],
        "symptoms": ["Trous ou hésitations franches à l'accélération", "Ralenti bloqué ou instable", "Difficulté à maintenir une vitesse stable"],
        "checks": [
            "Contrôle accessible : inspecter la connectique et la fixation du capteur sur le boîtier papillon.",
            "Contrôle électrique : contact mis moteur arrêté, mesurer la variation continue et sans à-coups de la tension du signal de 0.5V (fermé) à ~4.5V (pleins gaz)."
        ],
        "note": "Surveille également l'alimentation de référence 5V commune avec le capteur MAP."
    },
    "P0130": {
        "title": "Sonde lambda amont (Ligne 1, Sonde 1) — Circuit défaillant",
        "title_en": "O2 Sensor Circuit Malfunction (Bank 1 Sensor 1)",
        "cat": "Échappement / Dépollution",
        "sev": "alerte",
        "desc": "La sonde à oxygène amont (placée avant le pot catalytique) ne transmet pas de signal cohérent au calculateur.",
        "causes": ["Sonde lambda usée ou contaminée par des dépôts", "Fil de signal fondu sur l'échappement chaud ou coupé", "Connecteur contaminé par de l'eau ou de l'huile"],
        "symptoms": ["Surconsommation d'essence", "Odeur anormale à l'échappement", "Émissions polluantes non conformes au contrôle technique"],
        "checks": [
            "Contrôle accessible : inspecter le cheminement du câble de la sonde sous le collecteur d'échappement.",
            "Contrôle télémétrie : vérifier l'oscillation de la tension de la sonde amont à chaud (doit osciller rapidement entre ~0.1V et ~0.9V au ralenti)."
        ],
        "note": "Une sonde lambda présente une durée de vie typique de 100 000 à 150 000 km selon la qualité du carburant."
    },
    "P0135": {
        "title": "Chauffage de la sonde lambda amont — Panne de circuit",
        "title_en": "O2 Sensor Heater Circuit Malfunction (Bank 1 Sensor 1)",
        "cat": "Échappement / Dépollution",
        "sev": "info",
        "desc": "La résistance électrique intégrée qui chauffe la sonde lambda pour la rendre opérationnelle rapidement à froid est coupée ou non alimentée.",
        "causes": ["Résistance chauffante interne de la sonde coupée", "Fusible du circuit de réchauffage grillé", "Faisceau électrique endommagé"],
        "symptoms": ["Voyant moteur allumé", "Régulation de richesse retardée lors des premières minutes après démarrage"],
        "checks": [
            "Contrôle électrique : sonde débranchée hors tension, mesurer la résistance du réchauffeur entre les deux fils de même couleur (généralement blancs, valeur typique entre 5 et 15 Ω).",
            "Contrôle électrique : vérifier la présence de 12V après contact sur le connecteur côté faisceau."
        ],
        "note": "Si la résistance de chauffage est infinie (coupure franche), le remplacement de la sonde est nécessaire."
    },
    "P0171": {
        "title": "Dosage de carburant — Mélange trop pauvre (Ligne 1)",
        "title_en": "System Too Lean (Bank 1)",
        "cat": "Moteur / Carburation",
        "sev": "alerte",
        "desc": "Excès d'air ou manque de carburant dans le mélange air/essence. Le calculateur a atteint sa limite maximale d'enrichissement (Short/Long Term Fuel Trim).",
        "causes": [
            "Prise d'air non mesurée au collecteur, durites de dépression ou joints d'injecteurs",
            "Pression d'essence insuffisante (filtre à carburant colmaté, pompe à essence fatiguée)",
            "Injecteur partiellement bouché",
            "Sous-évaluation de la pression par un capteur MAP dérivant"
        ],
        "symptoms": ["Manque de reprise à l'accélération", "Tendance du moteur à chauffer davantage", "Légers à-coups sous charge"],
        "checks": [
            "Contrôle accessible : inspecter visuellement toutes les durites de vide, le manchon d'admission d'air et le bouchon/jauge d'huile.",
            "Contrôle accessible : remplacer le filtre à carburant si son échéance d'entretien est dépassée.",
            "Contrôle spécialisé atelier : test d'étanchéité au générateur de fumée basse pression.",
            "Contrôle spécialisé atelier : mesure de la pression d'essence sur la rampe d'injection au manomètre mécanique."
        ],
        "note": "Rappel de sécurité : Ne jamais chercher des fuites d'air avec des solvants inflammables moteur tournant. Privilégier une inspection visuelle ou un test d'étanchéité à la machine à fumée."
    },
    "P0172": {
        "title": "Dosage de carburant — Mélange trop riche (Ligne 1)",
        "title_en": "System Too Rich (Bank 1)",
        "cat": "Moteur / Carburation",
        "sev": "alerte",
        "desc": "Trop de carburant ou manque d'air dans le mélange. Le calculateur réduit au maximum l'injection mais la sonde lambda lit toujours un mélange trop riche.",
        "causes": [
            "Filtre à air très encrassé ou colmaté",
            "Régulateur de pression d'essence défaillant ou pression excessive",
            "Injecteur fuyard restant partiellement ouvert",
            "Capteur MAP surestimant la charge réelle du moteur"
        ],
        "symptoms": ["Fumée noire à l'échappement", "Odeur prononcée d'essence", "Bougies noircies par la suie", "Surconsommation"],
        "checks": [
            "Contrôle accessible : vérifier et remplacer si nécessaire le filtre à air moteur.",
            "Contrôle accessible : démonter et examiner l'état des bougies d'allumage.",
            "Contrôle télémétrie : vérifier la cohérence des valeurs de pression MAP affichées sur l'application."
        ],
        "note": "Un filtre à air obstrué restreint le débit d'air et provoque un enrichissement anormal du mélange."
    },
    "P0300": {
        "title": "Ratés d'allumage aléatoires / cylindres multiples détectés",
        "title_en": "Random/Multiple Cylinder Misfire Detected",
        "cat": "Allumage / Combustion",
        "sev": "critique",
        "desc": "Le calculateur détecte des variations anormales de vitesse angulaire du vilebrequin, causées par des combustions incomplètes sur plusieurs cylindres.",
        "causes": [
            "Bougies d'allumage usées ou écartement des électrodes incorrect",
            "Faisceau de câbles haute tension fissuré ou poreux",
            "Bobine d'allumage défaillante ou faiblesse d'étincelle",
            "Carburant de qualité dégradée ou présence d'eau dans le réservoir",
            "Pression d'essence insuffisante"
        ],
        "symptoms": [
            "Moteur qui tremble et vibre fortement au ralenti et en charge",
            "Voyant moteur qui clignote (alerte risque catalyseur)",
            "Perte sensible de puissance"
        ],
        "checks": [
            "Contrôle accessible : démonter et examiner l'usure et la couleur des bougies d'allumage.",
            "Contrôle accessible : inspecter visuellement l'état des câbles haute tension (fissures, traces d'arcs électriques).",
            "Contrôle allumage : vérifier la bobine d'allumage et son connecteur d'alimentation."
        ],
        "note": "ATTENTION : Un voyant moteur qui clignote signale des ratés sévères risquant d'endommager le pot catalytique par surchauffe d'essence imbrûlée. Réduire la charge moteur immédiatement."
    },
    "P0301": {
        "title": "Ratés d'allumage détectés sur le cylindre 1",
        "title_en": "Cylinder 1 Misfire Detected",
        "cat": "Allumage / Combustion",
        "sev": "critique",
        "desc": "Combustion manquante ou incomplète localisée spécifiquement sur le cylindre numéro 1.",
        "causes": [
            "Bougie du cylindre 1 usée, perlée ou noyée",
            "Câble haute tension du cylindre 1 défectueux",
            "Injecteur du cylindre 1 encrassé",
            "Défaut mécanique de compression sur le cylindre 1"
        ],
        "symptoms": ["Moteur tournant sur 2 cylindres (sur Spark 3 cylindres)", "Vibrations très prononcées", "Perte de puissance majeure"],
        "checks": [
            "Contrôle accessible : permuter la bougie 1 avec un autre cylindre pour vérifier si le défaut suit la bougie.",
            "Contrôle accessible : vérifier le câble d'allumage et son bon clipsage sur la bougie 1.",
            "Contrôle spécialisé : faire mesurer les compressions moteur si les organes d'allumage sont conformes."
        ],
        "note": "Sur le moteur 3 cylindres 0.8L (F8CV), la perte d'un cylindre dégrade fortement les performances et l'équilibre vibratoire."
    },
    "P0302": {
        "title": "Ratés d'allumage détectés sur le cylindre 2",
        "title_en": "Cylinder 2 Misfire Detected",
        "cat": "Allumage / Combustion",
        "sev": "critique",
        "desc": "Combustion manquante ou incomplète localisée sur le cylindre numéro 2.",
        "causes": [
            "Bougie du cylindre 2 usée",
            "Câble haute tension du cylindre 2 défectueux",
            "Injecteur du cylindre 2 encrassé"
        ],
        "symptoms": ["Vibrations importantes au ralenti", "Manque de reprise", "Odeur d'imbrûlés"],
        "checks": [
            "Contrôle accessible : inspecter la bougie 2 et le câble haute tension associé.",
            "Contrôle accessible : permuter la bougie pour localiser l'origine du défaut."
        ],
        "note": "Contrôler l'état des bougies et du faisceau d'allumage."
    },
    "P0303": {
        "title": "Ratés d'allumage détectés sur le cylindre 3",
        "title_en": "Cylinder 3 Misfire Detected",
        "cat": "Allumage / Combustion",
        "sev": "critique",
        "desc": "Combustion manquante ou incomplète sur le cylindre numéro 3 (troisième cylindre du moteur 0.8L F8CV).",
        "causes": ["Bougie du cylindre 3", "Câble haute tension du cylindre 3", "Injecteur 3", "Jeu aux soupapes"],
        "symptoms": ["Ralenti heurté", "Fortes vibrations transmises à l'habitacle", "Perte de puissance"],
        "checks": [
            "Contrôle accessible : inspecter la bougie 3 et le câble d'allumage.",
            "Contrôle spécialisé : sur moteur F8CV à culbuteurs, faire contrôler le jeu aux soupapes si l'allumage est hors de cause."
        ],
        "note": "Sur moteur Spark 0.8 F8CV, un réglage régulier du jeu aux culbuteurs est préconisé par le constructeur."
    },
    "P0335": {
        "title": "Capteur de position de vilebrequin (PMH) — Panne du circuit",
        "title_en": "Crankshaft Position Sensor A Circuit Malfunction",
        "cat": "Allumage / Synchronisation",
        "sev": "critique",
        "desc": "Le calculateur ne capte plus la rotation du volant moteur. Sans ce signal essentiel, l'allumage et l'injection ne peuvent pas être synchronisés.",
        "causes": [
            "Capteur PMH encrassé ou tête magnétique couverte de limaille",
            "Connecteur oxydé ou faisceau coupé/frotté",
            "Défaillance interne du capteur de vilebrequin",
            "Cible dentée du volant moteur endommagée"
        ],
        "symptoms": [
            "Le moteur refuse de démarrer (le démarreur entraîne le moteur sans allumage)",
            "Coupure moteur soudaine et nette en roulant",
            "Aiguille du compte-tours restant inerte au démarrage"
        ],
        "checks": [
            "Contrôle accessible : vérifier le raccordement et la propreté du connecteur du capteur PMH.",
            "Contrôle accessible : démonter le capteur pour nettoyer sa tête magnétique des limailles métalliques éventuelles.",
            "Contrôle électrique : mesurer au multimètre la résistance interne du capteur débranché (valeur indicative typique ~500 à 1000 Ω selon modèle)."
        ],
        "note": "Cause classique de non-démarrage ou de calage net sans aucun à-coup préalable."
    },
    "P0340": {
        "title": "Capteur de position d'arbre à cames (AAC) — Panne du circuit",
        "title_en": "Camshaft Position Sensor Circuit Malfunction",
        "cat": "Allumage / Distribution",
        "sev": "critique",
        "desc": "Signal de synchronisation de l'arbre à cames absent ou incohérent avec celui du vilebrequin.",
        "causes": [
            "Capteur AAC défaillant ou connecteur oxydé",
            "Faisceau électrique endommagé",
            "Courroie de distribution détendue ou décalée"
        ],
        "symptoms": ["Démarrage laborieux nécessitant plusieurs secondes d'entraînement du démarreur", "Léger manque de vivacité"],
        "checks": [
            "Contrôle accessible : vérifier le connecteur et le câblage du capteur d'arbre à cames.",
            "Contrôle spécialisé : faire vérifier le calage de la courroie de distribution si le capteur est fonctionnel."
        ],
        "note": "Contrôler impérativement le calage de distribution si le capteur électrique est conforme."
    },
    "P0420": {
        "title": "Efficacité du catalyseur inférieure au seuil (Ligne 1)",
        "title_en": "Catalyst System Efficiency Below Threshold (Bank 1)",
        "cat": "Échappement / Dépollution",
        "sev": "alerte",
        "desc": "La capacité de stockage d'oxygène du catalyseur est insuffisante. Le signal de la sonde lambda aval commence à osciller au même rythme que celui de la sonde amont.",
        "causes": [
            "Catalyseur usé, colmaté ou dégradé par d'anciens ratés d'allumage",
            "Fuite d'échappement entre le collecteur et le pot catalytique",
            "Sonde lambda aval défaillante"
        ],
        "symptoms": ["Voyant moteur allumé", "Comportement routier souvent normal ou léger bruit métallique d'échappement"],
        "checks": [
            "Contrôle accessible : vérifier l'absence de fuite ou de fissure sur la ligne d'échappement.",
            "Contrôle télémétrie : vérifier que la sonde lambda aval délivre une tension stabilisée (~0.4V à 0.7V) et n'oscille pas comme la sonde amont."
        ],
        "note": "Attention : Des ratés d'allumage prolongés provoquent l'arrivée d'essence imbrûlée dans le catalyseur, entraînant sa destruction par fusion thermique."
    },
    "P0500": {
        "title": "Capteur de vitesse du véhicule (VSS) — Panne de circuit",
        "title_en": "Vehicle Speed Sensor Malfunction",
        "cat": "Châssis / Vitesse",
        "sev": "alerte",
        "desc": "Le calculateur moteur ne reçoit plus l'information de vitesse d'avancement du véhicule.",
        "causes": [
            "Capteur de vitesse de boîte débranché ou défaillant",
            "Pignon d'entraînement plastique usé dans la boîte de vitesses",
            "Faisceau électrique coupé"
        ],
        "symptoms": [
            "Compteur de vitesse inerte ou oscillant",
            "Instabilité du ralenti lors des décélérations à l'approche d'un arrêt",
            "Kilométrage non incrémenté sur le combiné"
        ],
        "checks": [
            "Contrôle accessible : vérifier le connecteur du capteur VSS situé sur le carter de boîte de vitesses.",
            "Contrôle accessible : inspecter le cheminement du câble électrique dans le compartiment moteur."
        ],
        "note": "Sur la Chevrolet Spark 0.8 à boîte manuelle, le capteur VSS est fixé sur le dessus du carter de boîte."
    },
    "P0505": {
        "title": "Système de régulation du ralenti (Vanne IAC) — Dysfonctionnement",
        "title_en": "Idle Air Control System Malfunction",
        "cat": "Moteur / Régulation ralenti",
        "sev": "alerte",
        "desc": "Le calculateur ne parvient pas à stabiliser le régime de ralenti à la consigne nominale programmée.",
        "causes": [
            "Moteur pas-à-pas de régulation de ralenti (IAC) encrassé par les vapeurs d'huile et la suie",
            "Conduit d'air de ralenti obstrué dans le boîtier papillon",
            "Prise d'air parasite sur le collecteur d'admission"
        ],
        "symptoms": [
            "Moteur qui cale au lâcher d'accélérateur ou lors des arrêts",
            "Régime de ralenti bloqué trop haut (ex: > 1200 tr/min à chaud)",
            "Ralenti oscillant de manière irrégulière"
        ],
        "checks": [
            "Contrôle accessible : démonter le régulateur IAC et nettoyer délicatement son pointeau et son logement avec un solvant adapté pour boîtier papillon.",
            "Contrôle accessible : nettoyer l'alésage du boîtier papillon et vérifier l'absence de calamine.",
            "Contrôle accessible : vérifier l'étanchéité du joint torique du régulateur IAC."
        ],
        "note": "Un encrassement par les dépôts d'huile et de suie est une cause fréquente d'instabilité du ralenti."
    },
    "P0700": {
        "title": "Système de commande de boîte de vitesses — Demande d'allumage voyant",
        "title_en": "Transmission Control System (MIL Request)",
        "cat": "Transmission / Boîte",
        "sev": "critique",
        "desc": "Le calculateur de transmission automatique (TCM) a détecté une anomalie et ordonne au calculateur moteur d'allumer le voyant Check Engine.",
        "causes": [
            "Anomalie interne sur la boîte automatique (si le véhicule en est équipé)",
            "Capteur de vitesse d'arbre de boîte ou électrovanne défaillante",
            "Sur véhicule à boîte manuelle : faux code résultant d'une erreur de décodage de trame"
        ],
        "symptoms": ["Voyant moteur allumé", "Comportement de boîte dégradé (si boîte automatique)"],
        "checks": [
            "Sur véhicule à boîte automatique : interroger le calculateur de boîte (TCM) pour lire le code de défaut interne spécifique.",
            "Sur Chevrolet Spark 0.8 boîte manuelle : vérifier qu'il ne s'agit pas d'une confusion de décodage avec un code moteur (ex: trame MAP)."
        ],
        "note": "Sur une Spark à boîte manuelle, ce code ne correspond à aucun composant physique de transmission et résulte typiquement d'un décodage erroné."
    },
    "U0100": {
        "title": "Perte de communication avec le calculateur moteur (ECM/PCM)",
        "title_en": "Lost Communication With ECM/PCM",
        "cat": "Réseau / Communication CAN",
        "sev": "critique",
        "desc": "Les autres modules électroniques (tableau de bord, ABS, BCM) ne reçoivent plus les trames périodiques du calculateur moteur sur le bus CAN.",
        "causes": [
            "Fusible d'alimentation du calculateur moteur grillé",
            "Relais principal de gestion moteur (Main Relay) défaillant",
            "Défaut de masse moteur ou de tresse de masse châssis",
            "Lignes du bus CAN (CAN-High ou CAN-Low) coupées ou court-circuitées"
        ],
        "symptoms": [
            "Moteur refusant de démarrer",
            "Combiné d'instruments affichant des tirets ou l'ensemble des témoins allumés",
            "Impossibilité d'établir la communication avec le scanner OBD"
        ],
        "checks": [
            "Contrôle accessible : vérifier les fusibles de gestion moteur dans la boîte à fusibles compartiment moteur.",
            "Contrôle accessible : contrôler le relais principal et les bornes de la batterie.",
            "Contrôle électrique : mesurer la tension batterie au repos (> 12.4V attendu).",
            "Contrôle spécialisé : mesurer la résistance de terminaison du bus CAN (valeur nominale de 60 Ω entre les broches 6 et 14 de la prise OBD, batterie débranchée)."
        ],
        "note": "Contrôler en priorité l'état de charge de la batterie, le serrage des cosses et les fusibles d'alimentation."
    },
    "U0155": {
        "title": "Perte de communication avec le combiné d'instruments (IPC)",
        "title_en": "Lost Communication With Instrument Panel Cluster",
        "cat": "Réseau / Communication CAN",
        "sev": "info",
        "desc": "Absence de communication de données entre le combiné du tableau de bord et les autres modules du véhicule.",
        "causes": [
            "Connecteur arrière du tableau de bord desserré ou mal enclenché",
            "Fusible d'alimentation du combiné",
            "Anomalie sur la liaison réseau habitacle"
        ],
        "symptoms": ["Aiguilles du tableau de bord inertes", "Témoins d'alerte ne s'allumant pas lors du test contact"],
        "checks": [
            "Contrôle accessible : vérifier les fusibles habitacle protégeant le combiné d'instruments.",
            "Contrôle accessible : vérifier l'enfichage du connecteur à l'arrière du bloc compteur."
        ],
        "note": "Anomalie de transmission de données avec le tableau de bord."
    }
}

# Lexique de traduction technique automobile anglais -> français
LEXICON = [
    # Composants et capteurs principaux
    (r"\bFuel Volume Regulator\b", "Régulateur de débit de carburant"),
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
    (r"\bEvaporative Emission System\b", "Système EVAP (vapeurs carburant)"),
    (r"\bVehicle Speed Sensor\b", "Capteur de vitesse du véhicule (VSS)"),
    (r"\bIdle Air Control\b", "Régulation du ralenti (IAC)"),
    (r"\bTransmission Control Module\b", "Calculateur de boîte de vitesses (TCM)"),
    (r"\bEngine Control Module\b", "Calculateur moteur (ECM/PCM)"),
    (r"\bAnti-Lock Brake System\b", "Système antiblocage de roues (ABS)"),
    (r"\bInstrument Panel Cluster\b", "Combiné d'instruments (Tableau de bord)"),
    (r"\bBody Control Module\b", "Boîtier de servitude carrosserie (BCM)"),
    (r"\bLost Communication With\b", "Perte de communication avec"),
    (r"\bControl Module\b", "Module de commande"),
    (r"\bFuel Pressure Regulator\b", "Régulateur de pression de carburant"),
    (r"\bFuel Rail Pressure\b", "Pression de rampe d'injection"),
    (r"\bFuel Injector\b", "Injecteur de carburant"),
    (r"\bEGR\b", "Recirculation des gaz d'échappement (EGR)"),
    (r"\bExhaust Gas Recirculation\b", "Recirculation des gaz d'échappement (EGR)"),

    # Qualifications d'état et de panne électrique SAE J2012
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
    (r"\bSystem Too Lean\b", "Dosage carburant trop pauvre"),
    (r"\bSystem Too Rich\b", "Dosage carburant trop riche"),
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
    print("=== SPARK V3 — Compilation de la base de codes défaut SAE J2012 ===")
    
    final_db = {
        "_meta": {
            "source": "SAE J2012 / Open OBD (CC0-1.0 Domaine Public)",
            "license": "CC0-1.0 (Public Domain)",
            "version": "3.0.0",
            "offline": True,
            "disclaimer": "Les indications fournies sont données à titre indicatif. Se référer au manuel d'atelier pour les spécifications constructeur exactes."
        }
    }

    # 1. Chargement et parsing des familles SAE
    families = ['P0xxx', 'P2xxx', 'P3xxx', 'U0xxx', 'U3xxx', 'C0xxx', 'B0xxx']
    for fam in families:
        url = f"https://raw.githubusercontent.com/foerbsnavi/obdex/main/data/generic/{fam}_enriched.yaml"
        print(f"Extraction {fam}...")
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            raw = urllib.request.urlopen(req, timeout=30).read().decode('utf-8')
            
            pattern = re.compile(r'- code:\s*([A-Z0-9]{5})\s+category:\s*(\w+)\s+title:\s+en:\s*([^\n]+)')
            matches = pattern.findall(raw)
            print(f"  -> {len(matches)} codes traités dans {fam}")
            
            for code, cat, en_title in matches:
                clean_en = en_title.strip('"\' ')
                fr_title = translate_title(clean_en)
                sev = determine_severity(code, fr_title)
                category = determine_category(code)
                
                final_db[code] = {
                    "msg": fr_title,
                    "title": fr_title,
                    "title_en": clean_en,
                    "sev": sev,
                    "cat": category
                }
        except Exception as e:
            print(f"  Avertissement sur {fam}: {e}")

    # 2. Intégration des dossiers experts approfondis
    print(f"\nFusion des {len(EXPERT_DOSSIERS)} dossiers experts d'atelier...")
    for code, dossier in EXPERT_DOSSIERS.items():
        entry = {
            "msg": dossier["title"],
            "title": dossier["title"],
            "title_en": dossier.get("title_en", ""),
            "sev": dossier["sev"],
            "cat": dossier["cat"],
            "desc": dossier["desc"],
            "causes": dossier["causes"],
            "symptoms": dossier["symptoms"],
            "checks": dossier["checks"],
            "note": dossier.get("note", "")
        }
        final_db[code] = entry

    # 3. Écriture du fichier final JSON
    out_path = os.path.join("assets", "data", "dtc_codes.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(final_db, f, ensure_ascii=False, indent=2)

    file_size_kb = os.path.getsize(out_path) / 1024
    print(f"\n[SUCCÈS] Base DTC générée : {len(final_db) - 1} codes OBD-II.")
    print(f"Fichier : {out_path} ({file_size_kb:.1f} KB)")
    
    # Vérification des codes MAP
    for c in ["P0105", "P0106", "P0107", "P0108", "P0109"]:
        if c in final_db:
            print(f"  [OK] {c}: {final_db[c]['title']} (causes: {len(final_db[c].get('causes', []))}, vérifs: {len(final_db[c].get('checks', []))})")

if __name__ == "__main__":
    main()
