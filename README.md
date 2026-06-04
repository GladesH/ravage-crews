

CONTENU
  ravage-crews/      -> le resource (à mettre dans resources/)
  crew_ravage.lua    -> pont à ajouter DANS hrs_base_building
  INSTALLATION.txt   -> ce fichier

--------------------------------------------------------
INSTALLATION
--------------------------------------------------------
1) Copie le dossier  ravage-crews  dans tes resources.

2) Copie  crew_ravage.lua  dans le dossier de hrs_base_building.
   Puis dans hrs_base_building/fxmanifest.lua, ajoute-le APRÈS client.lua :

        client_scripts {
            'client.lua',
            'crew_ravage.lua',   -- en dernier
        }

3) Dans server.cfg, démarre ravage-crews AVANT hrs_base_building :

        ensure ravage-crews
        ensure hrs_base_building

4) /crew ouvre la page RAVAGE.

--------------------------------------------------------
NOTES
--------------------------------------------------------
- Plus besoin des remplacements qb-menu / qb-input / ox_lib :
  crew_ravage.lua remplace tout l'ancien flux de menu.
  Les events 'hrs_base_building:crew:*' deviennent inutiles (inoffensifs).

- crew_ravage.lua n'appelle QUE les events serveur réels du base building
  (addToCrew, removeFromCrew, updateCrewOwner, updateCrewPerms,
   updateCrewName, deleteCrew, leaveCrew, createCrew, acceptCrew).
  Si tu as renommé l'un d'eux, ajuste la table CREW_EVENTS en haut du fichier.

- La page se rafraîchit en direct (membre retiré, perms, etc.) via
  setCrewC / setInvitesC.
