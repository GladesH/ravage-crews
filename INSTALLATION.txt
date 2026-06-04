========================================================
 RAVAGE-CREWS — Page de gestion de crew (NUI)
========================================================

CONTENU
  ravage-crews/            -> le resource (à mettre dans resources/)
  crew_ravage.lua          -> pont CLIENT à ajouter dans hrs_base_building
  crew_ravage_server.lua   -> pont SERVEUR (récap des stocks) à ajouter dans hrs_base_building
  INSTALLATION.txt         -> ce fichier

--------------------------------------------------------
INSTALLATION
--------------------------------------------------------
1) Copie le dossier  ravage-crews  dans tes resources.

2) Copie  crew_ravage.lua  ET  crew_ravage_server.lua  dans le dossier de hrs_base_building.
   Dans hrs_base_building/fxmanifest.lua :

        client_scripts {
            'client.lua',
            'crew_ravage.lua',          -- en dernier des client_scripts
        }

        server_scripts {
            '@oxmysql/lib/MySQL.lua',   -- (déjà présent normalement)
            'server/main.lua',          -- (ton fichier serveur existant)
            'crew_ravage_server.lua',   -- APRÈS le fichier serveur crew
        }

3) Dans server.cfg, démarre ravage-crews AVANT hrs_base_building :

        ensure ravage-crews
        ensure hrs_base_building

4) /crew ouvre la page RAVAGE.

--------------------------------------------------------
ONGLET "COFFRES" (récap des stocks)
--------------------------------------------------------
- Liste TOUS les items des coffres (type "storages") + des props "itemStock"
  présents dans le rayon du totem de claim du CHEF, possédés par le crew.
- Accréditation requise : voir la constante STOCK_PERMISSION en haut de
  crew_ravage.lua ET de crew_ravage_server.lua (les deux doivent être identiques).
  Par défaut "canInteract" -> mets une clé qui existe dans ton Config.crewPermissionsById.
  Le chef du crew y a toujours accès.
- Lecture des coffres via la table ox_inventory (variable OX_TABLE dans
  crew_ravage_server.lua si ta table a un autre nom).

--------------------------------------------------------
NOTES
--------------------------------------------------------
- Plus besoin des remplacements qb-menu / qb-input / ox_lib.
- Le serveur hrs_base_building broadcast déjà setCrewC/setInvitesC : la page
  se met à jour en direct, sans restart.

--------------------------------------------------------
ONGLET "ACCÈS" (droits par coffre)
--------------------------------------------------------
- Sélectionne un coffre -> coche/décoche chaque membre pour autoriser/bloquer
  son accès À CE COFFRE. Coffre sans réglage = ouvert à tout le crew.
- Le chef du crew et le propriétaire du coffre gardent toujours l'accès.
- L'ACL est stockée dans la metadata du prop (persistant), et appliquée via une
  surcharge de hasPermission(). IMPORTANT : crew_ravage_server.lua doit être
  chargé APRÈS server/main.lua (sinon un message d'avertissement s'affiche au
  démarrage et l'ACL n'est pas active).
- Accréditation requise : ACL_PERMISSION (par défaut "canManageMembers"),
  identique dans crew_ravage.lua et crew_ravage_server.lua.
- Bouton "Localiser" : pose un waypoint sur le coffre choisi.

--------------------------------------------------------
ACL COFFRES — BLOCAGE RÉEL (mise à jour)
--------------------------------------------------------
- L'application du blocage ne passe PLUS par hasPermission (qui n'est pas
  utilisé pour l'ouverture des coffres dans ce build hrs). Elle passe par un
  hook ox_inventory : exports.ox_inventory:registerHook('openInventory', ...).
  -> Un membre exclu d'un coffre se voit refuser l'ouverture, quelle que soit
     la façon dont hrs ouvre le stash.
- Au démarrage, la console doit afficher :
     [ravage-crews] Hook ox_inventory 'openInventory' enregistré (ACL coffres active).
  Si tu vois le message ATTENTION à la place, ton ox_inventory ne supporte pas
  registerHook (mets-le à jour) — dis-le-moi, je ferai une variante.
- Le propriétaire du coffre et le chef du crew ne sont jamais bloqués.
- ACL_PERMISSION = "canManageMembers" : le CHEF passe toujours. Pour qu'un
  simple membre puisse gérer l'accès, cette clé doit exister dans
  Config.crewPermissionsById (sinon seul le chef gère).
