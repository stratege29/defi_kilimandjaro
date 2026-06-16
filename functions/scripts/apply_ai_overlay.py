# -*- coding: utf-8 -*-
"""Applique le voile + texte de marque sur les images IA générées."""
import os
from photo_card import photo_card, ACCENTS
GOLD=(233,185,73)
_HERE=os.path.dirname(os.path.abspath(__file__))
AI=os.environ.get("AI_DIR", os.path.abspath(os.path.join(_HERE,"..","..","docs/instagram_assets/ai")))
OUT=os.path.join(AI,"cards"); os.makedirs(OUT, exist_ok=True)

# subject -> (kicker, titre, sous-titre, accent)
CARDS = {
 "abidjan":     ("Villes d'Afrique","Trop facile pour un\nAbidjanais ?","Capitale économique du 225. 7 lettres.",ACCENTS["villes"]),
 "dakar":       ("Villes d'Afrique","La porte la plus à\nl'ouest de l'Afrique.","Capitale du Sénégal. 5 lettres.",ACCENTS["villes"]),
 "lagos":       ("Villes d'Afrique","La plus grande ville\nd'Afrique ?","Mégapole du Nigeria. 5 lettres.",ACCENTS["villes"]),
 "marrakech":   ("Villes d'Afrique","« La ville rouge ».\nTu sais laquelle ?","Ville marocaine mythique. 9 lettres.",ACCENTS["villes"]),
 "yamoussoukro":("Villes d'Afrique","La plus grande basilique\ndu monde est ici.","Capitale politique du 225. 12 lettres.",ACCENTS["villes"]),
 "kilimandjaro":("Le sommet","5 895 m.\nLe toit de l'Afrique.","Le plus haut sommet du continent.",ACCENTS["foot"]),
 "baobab":      ("Sagesse","La sagesse est\ncomme un baobab.","Personne ne peut l'enlacer seul. — proverbe akan",ACCENTS["culture"]),
 "balafon":     ("Coulisses","Le son du jeu ?\n100 % maison.","Synthétisé, inspiré du balafon.",GOLD),
 "masque":      ("Culture 225","Derrière chaque masque,\nune légende.","Le patrimoine, en jeu.",ACCENTS["culture"]),
 "attieke":     ("Pack Culture 225","Vrai ivoirien =\ntu trouves en 3 secondes.","Semoule de manioc fermentée. 7 lettres.",ACCENTS["culture"]),
 "alloco":      ("Pack Culture 225","Le snack n°1\ndes maquis.","Bananes plantains frites. 6 lettres.",ACCENTS["culture"]),
 "player":      ("Défi Kilimandjaro","Toi, ce soir.","Le jeu de mots qui rend accro.",GOLD),
 "friends":     ("Le duel 1v1","Le duel qui finit\nen fou rire.","1v1 en temps réel. Tague ton adversaire.",ACCENTS["foot"]),
 "duel":        ("La signature","Le plus rapide\ngagne.","Duel 1v1 en temps réel.",ACCENTS["foot"]),
}

if __name__ == "__main__":
    done=0
    for key,(k,t,s,acc) in CARDS.items():
        src=os.path.join(AI,f"{key}.png")
        if os.path.exists(src):
            photo_card(os.path.join(OUT,f"CARD_{key}.png"), src, k, t, s, acc); done+=1
        else:
            print("manquante:", key)
    print(f"\n{done} cartes habillées dans {OUT}")
