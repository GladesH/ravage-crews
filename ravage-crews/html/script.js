// =========================================================
//  RAVAGE - Crew Management Page (NUI logic)
//  Payload (openCrew / updateCrew):
//   { hasCrew, identifier, isOwner, canInvite, canManage, canRemove,
//     crew:{ name, ownerId, members:[{id,name,isOwner,isMe,permissions[]}] },
//     permissionDefs:[{index,label}], nearbyPlayers:[{serverId,name}],
//     invites:[{id,name}], events:{...} }
// =========================================================

const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'ravage-crews';

let crew = null;
let activeTab = 'membres';
let modalOk = null;
let expanded = new Set(); // membres dépliés (mémorisé entre refresh)

/* ---------------------------- helpers ---------------------------- */
function post(name, body) {
    fetch(`https://${RES}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body || {})
    }).catch(() => {});
}
function act(event, args) {
    if (!event) return;
    post('crewAction', { event: event, args: args || [] });
}
function initials(name) {
    return (name || '?').trim().charAt(0).toUpperCase() || '?';
}
function el(tag, cls, txt) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt !== undefined) e.textContent = txt;
    return e;
}

/* ---------------------------- open / close ---------------------------- */
function openCrew(payload) {
    crew = payload || {};
    if (activeTab === 'inviter' && !crew.canInvite) activeTab = 'membres';
    render();
    document.getElementById('crew-overlay').classList.remove('hidden');
}
function updateCrew(payload) {
    if (document.getElementById('crew-overlay').classList.contains('hidden')) return;
    crew = payload || {};
    if (activeTab === 'inviter' && !crew.canInvite) activeTab = 'membres';
    render();
}
function closeCrew() {
    document.getElementById('crew-overlay').classList.add('hidden');
    closeModal();
    post('closeCrew', {});
}

/* ---------------------------- render ---------------------------- */
function render() {
    const body = document.getElementById('crew-body');
    body.innerHTML = '';
    if (!crew) return;

    // titre de la barre du haut = nom du crew
    const topTitle = document.getElementById('crew-window-title');
    const topSub   = document.getElementById('crew-window-sub');
    if (crew.hasCrew) {
        topTitle.textContent = (crew.crew && crew.crew.name) ? crew.crew.name : 'CREW';
        topSub.textContent   = 'RAVAGE \u2014 GESTION DU CREW';
    } else {
        topTitle.textContent = 'GESTION DU CREW';
        topSub.textContent   = 'RAVAGE \u2014 SYST\u00C8ME DE CREW';
    }

    if (!crew.hasCrew) { renderNoCrew(body); return; }

    // --- side ---
    const side = el('aside'); side.id = 'crew-side';
    const owner = (crew.crew.members || []).find(m => m.isOwner);
    side.innerHTML = `
        <div class="side-block">
            <span class="side-label">Crew</span>
            <span class="side-crewname">${esc(crew.crew.name || 'CREW')}</span>
        </div>
        <div class="side-block">
            <span class="side-label">Membres</span>
            <div class="side-stat"><span class="num">${(crew.crew.members||[]).length}${crew.maxMembers ? ' / ' + crew.maxMembers : ''}</span><span class="unit">opérateurs</span></div>
        </div>
        <div class="side-block">
            <span class="side-label">Propriétaire</span>
            <span class="side-owner">${esc(owner ? owner.name : '—')}</span>
        </div>
        <div class="side-divider"></div>
    `;
    const actions = el('div', 'side-actions');

    // Itinéraire vers la base (waypoint IG)
    const wp = el('button', 'btn full');
    wp.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="vertical-align:-2px;margin-right:7px"><path d="M3 11l9-8 9 8"/><path d="M5 10v10h14V10"/></svg>Itinéraire vers la base';
    wp.onclick = () => post('crewWaypoint', {});
    actions.appendChild(wp);

    if (crew.isOwner) {
        const rn = el('button', 'btn full', 'Renommer le crew');
        rn.onclick = () => promptRename();
        const del = el('button', 'btn danger full', 'Supprimer le crew');
        del.onclick = () => confirmModal('Supprimer le crew', 'Cette action est définitive. Confirmer la suppression du crew ?', () => act(crew.events.delete, []), true);
        actions.append(rn, del);
    } else {
        const lv = el('button', 'btn danger full', 'Quitter le crew');
        lv.onclick = () => confirmModal('Quitter le crew', 'Voulez-vous vraiment quitter ce crew ?', () => act(crew.events.leave, []), true);
        actions.append(lv);
    }
    side.appendChild(actions);

    // --- main ---
    const main = el('main'); main.id = 'crew-main';
    const tabs = el('div'); tabs.id = 'crew-tabs';
    tabs.appendChild(makeTab('membres', 'Membres', (crew.crew.members||[]).length));
    if (crew.canInvite) tabs.appendChild(makeTab('inviter', 'Inviter', (crew.nearbyPlayers||[]).length));
    const content = el('div'); content.id = 'crew-content';
    main.append(tabs, content);

    body.append(side, main);

    if (activeTab === 'inviter' && crew.canInvite) renderInvite(content);
    else renderMembers(content);
}

function makeTab(key, label, count) {
    const t = el('div', 'crew-tab' + (activeTab === key ? ' active' : ''));
    t.innerHTML = `${label}<span class="tab-count">${count}</span>`;
    t.onclick = () => { activeTab = key; render(); };
    return t;
}

/* ---- members tab ---- */
function renderMembers(content) {
    const members = crew.crew.members || [];
    const manageableIds = members
        .filter(m => crew.canManage && !m.isMe && !m.isOwner)
        .map(m => m.id);

    if (manageableIds.length > 0) {
        const bar = el('div', 'members-toolbar');
        const allExpanded = manageableIds.every(id => expanded.has(id));
        const btn = el('button', 'btn', allExpanded ? 'Tout replier' : 'Tout déplier');
        btn.style.flex = 'none';
        btn.onclick = () => {
            if (manageableIds.every(id => expanded.has(id))) {
                manageableIds.forEach(id => expanded.delete(id));
            } else {
                manageableIds.forEach(id => expanded.add(id));
            }
            render();
        };
        bar.appendChild(btn);
        content.appendChild(bar);
    }

    const grid = el('div', 'member-grid');
    members.forEach((m, i) => grid.appendChild(buildMemberCard(m, i)));
    content.appendChild(grid);
}

function buildMemberCard(m, i) {
    const card = el('div', 'member-card' + (m.isOwner ? ' is-owner' : ''));
    card.style.animationDelay = (i * 0.03) + 's';
    card.dataset.mid = m.id;

    // head
    const head = el('div', 'member-head');
    head.appendChild(el('div', 'member-avatar', initials(m.name)));
    const info = el('div', 'member-info');
    info.appendChild(el('div', 'member-name', m.name));
    const badges = el('div', 'member-badges');
    if (m.isOwner) badges.appendChild(el('span', 'badge owner', 'Propriétaire'));
    if (m.isMe) badges.appendChild(el('span', 'badge me', 'Vous'));
    info.appendChild(badges);
    head.appendChild(info);
    card.appendChild(head);

    const manageable = crew.canManage && !m.isMe && !m.isOwner;

    if (!manageable) {
        let note = "Vous ne pouvez pas gérer ce membre.";
        if (m.isOwner) note = "Propriétaire du crew — non modifiable.";
        else if (m.isMe) note = "C'est vous.";
        else if (!crew.canManage) note = "Vous n'avez pas les droits de gestion.";
        card.appendChild(el('div', 'member-readonly', note));
        return card;
    }

    // --- meta (résumé + chevron) dans le head, head cliquable pour replier/déplier ---
    head.classList.add('clickable');
    const meta    = el('div', 'member-meta');
    const summary = el('div', 'perm-summary', '0 / 0');
    const chev    = el('div', 'member-chevron', '▸');
    meta.append(summary, chev);
    head.appendChild(meta);

    // corps repliable
    const bodyWrap = el('div', 'member-body');

    // permissions
    const permsWrap = el('div', 'member-perms');
    const permsHead = el('div', 'perms-head');
    permsHead.appendChild(el('div', 'perms-title', 'Accréditations'));
    const bulkWrap = el('div', 'perms-bulk');
    const btnAll  = el('button', 'mini-btn', 'Tout cocher');
    const btnNone = el('button', 'mini-btn', 'Tout décocher');
    bulkWrap.append(btnAll, btnNone);
    permsHead.appendChild(bulkWrap);
    permsWrap.appendChild(permsHead);
    const pgrid = el('div', 'perms-grid');

    let updateSummary;

    (crew.permissionDefs || []).forEach(def => {
        const on = !!(m.permissions && m.permissions[def.index - 1]);
        const t = el('div', 'perm-toggle' + (on ? ' on' : ''));
        t.dataset.index = def.index;
        const box = el('div', 'perm-box'); box.textContent = on ? '✓' : '';
        t.appendChild(box);
        t.appendChild(el('div', 'perm-label', def.label));
        t.onclick = () => {
            t.classList.toggle('on');
            box.textContent = t.classList.contains('on') ? '✓' : '';
            if (updateSummary) updateSummary();
        };
        pgrid.appendChild(t);
    });
    permsWrap.appendChild(pgrid);
    bodyWrap.appendChild(permsWrap);

    updateSummary = () => {
        const onN = pgrid.querySelectorAll('.perm-toggle.on').length;
        const tot = (crew.permissionDefs || []).length;
        summary.textContent = onN + ' / ' + tot;
    };
    updateSummary();

    const setAll = (on) => {
        pgrid.querySelectorAll('.perm-toggle').forEach(t => {
            t.classList.toggle('on', on);
            const b = t.querySelector('.perm-box');
            if (b) b.textContent = on ? '✓' : '';
        });
        updateSummary();
    };
    btnAll.onclick  = () => setAll(true);
    btnNone.onclick = () => setAll(false);
    const acts = el('div', 'member-actions');
    const save = el('button', 'btn success', 'Enregistrer');
    save.onclick = () => {
        const arr = [];
        (crew.permissionDefs || []).forEach(def => {
            const node = pgrid.querySelector(`.perm-toggle[data-index="${def.index}"]`);
            arr[def.index - 1] = node ? node.classList.contains('on') : false;
        });
        act(crew.events.savePerms, [m.id, arr]);
        toast('Accréditations enregistrées', 'ok');
    };
    acts.appendChild(save);

    if (crew.isOwner) {
        const own = el('button', 'btn', 'Donner propriété');
        own.onclick = () => confirmModal('Transférer la propriété', `Donner la propriété du crew à ${esc(m.name)} ? Vous ne serez plus propriétaire.`, () => act(crew.events.giveOwner, [m.id]), false);
        acts.appendChild(own);
    }
    if (crew.canRemove) {
        const rm = el('button', 'btn danger', 'Retirer');
        rm.onclick = () => confirmModal('Retirer du crew', `Retirer ${esc(m.name)} du crew ?`, () => act(crew.events.removeMember, [m.id]), true);
        acts.appendChild(rm);
    }
    bodyWrap.appendChild(acts);
    card.appendChild(bodyWrap);

    // état replié/déplié (mémorisé entre les refresh)
    const setState = (open) => {
        card.classList.toggle('collapsed', !open);
        chev.textContent = open ? '▾' : '▸';
        if (open) expanded.add(m.id); else expanded.delete(m.id);
    };
    setState(expanded.has(m.id));

    head.onclick = () => setState(card.classList.contains('collapsed'));

    return card;
}

/* ---- invite tab ---- */
function renderInvite(content) {
    content.appendChild(el('div', 'section-title', 'Joueurs à proximité'));
    const players = crew.nearbyPlayers || [];
    if (players.length === 0) {
        content.appendChild(emptyState('⌖', 'Aucun joueur', "Aucun joueur à portée pour le moment. Rapprochez-vous d'un joueur pour l'inviter."));
        return;
    }
    const list = el('div', 'row-list');
    players.forEach((p, i) => {
        const row = el('div', 'list-row');
        row.style.animationDelay = (i * 0.03) + 's';
        row.appendChild(el('div', 'lr-avatar', initials(p.name)));
        row.appendChild(el('div', 'lr-name', p.name));
        const b = el('button', 'btn primary', 'Inviter');
        b.onclick = () => { act(crew.events.invite, [p.serverId]); toast('Invitation envoyée', 'ok'); b.disabled = true; b.textContent = 'Envoyé'; };
        row.appendChild(b);
        list.appendChild(row);
    });
    content.appendChild(list);
}

/* ---- no crew ---- */
function renderNoCrew(body) {
    const main = el('main'); main.id = 'crew-main'; main.style.width = '100%';
    const content = el('div'); content.id = 'crew-content';

    const top = el('div');
    top.style.cssText = 'display:flex;flex-direction:column;align-items:center;gap:16px;padding:36px 20px 28px;text-align:center;';
    top.appendChild(el('div', 'empty-icon', '⚑'));
    top.appendChild(el('div', 'empty-title', 'Aucun crew'));
    top.appendChild(el('div', 'empty-text', "Vous ne faites partie d'aucun crew. Créez le vôtre ou rejoignez-en un via une invitation."));
    const create = el('button', 'btn primary', 'Créer un crew');
    create.style.cssText = 'flex:none;padding:13px 30px;';
    create.onclick = () => promptCreate();
    top.appendChild(create);
    content.appendChild(top);

    content.appendChild(el('div', 'section-title', 'Invitations reçues'));
    const invites = crew.invites || [];
    if (invites.length === 0) {
        content.appendChild(emptyState('✉', 'Aucune invitation', "Vous n'avez aucune invitation en attente."));
    } else {
        const list = el('div', 'row-list');
        invites.forEach((inv, i) => {
            const row = el('div', 'list-row');
            row.style.animationDelay = (i * 0.03) + 's';
            row.appendChild(el('div', 'lr-avatar', initials(inv.name)));
            row.appendChild(el('div', 'lr-name', inv.name));
            const b = el('button', 'btn success', 'Rejoindre');
            b.onclick = () => confirmModal('Rejoindre le crew', `Rejoindre « ${esc(inv.name)} » ?`, () => act(crew.events.acceptInvite, [inv.id]), false);
            row.appendChild(b);
            list.appendChild(row);
        });
        content.appendChild(list);
    }

    main.appendChild(content);
    body.appendChild(main);
}

function emptyState(icon, title, text) {
    const e = el('div', 'empty-state');
    e.appendChild(el('div', 'empty-icon', icon));
    e.appendChild(el('div', 'empty-title', title));
    e.appendChild(el('div', 'empty-text', text));
    return e;
}

/* ---------------------------- modal ---------------------------- */
function confirmModal(title, text, onOk, danger) {
    document.getElementById('crew-modal-title').textContent = title;
    document.getElementById('crew-modal-text').textContent = text;
    document.getElementById('crew-modal-input-wrap').classList.add('hidden');
    const ok = document.getElementById('crew-modal-ok');
    ok.textContent = 'Confirmer';
    ok.className = 'm-btn confirm' + (danger ? ' danger' : '');
    modalOk = () => { closeModal(); onOk && onOk(); };
    ok.onclick = modalOk;
    document.getElementById('crew-modal').classList.remove('hidden');
}
function promptRename() {
    document.getElementById('crew-modal-title').textContent = 'Renommer le crew';
    document.getElementById('crew-modal-text').textContent = 'Saisissez le nouveau nom du crew.';
    document.getElementById('crew-modal-input-wrap').classList.remove('hidden');
    const input = document.getElementById('crew-modal-input');
    input.value = (crew.crew && crew.crew.name) ? crew.crew.name : '';
    const ok = document.getElementById('crew-modal-ok');
    ok.textContent = 'Enregistrer';
    ok.className = 'm-btn confirm';
    modalOk = () => {
        const v = input.value.trim();
        if (!v) { input.style.borderColor = 'var(--red)'; return; }
        closeModal();
        act(crew.events.rename, [v]);
        toast('Renommage envoyé', 'ok');
    };
    ok.onclick = modalOk;
    document.getElementById('crew-modal').classList.remove('hidden');
    setTimeout(() => input.focus(), 50);
}
function promptCreate() {
    document.getElementById('crew-modal-title').textContent = 'Créer un crew';
    document.getElementById('crew-modal-text').textContent = 'Choisissez le nom de votre crew.';
    document.getElementById('crew-modal-input-wrap').classList.remove('hidden');
    const input = document.getElementById('crew-modal-input');
    input.value = '';
    const ok = document.getElementById('crew-modal-ok');
    ok.textContent = 'Créer';
    ok.className = 'm-btn confirm';
    modalOk = () => {
        const v = input.value.trim();
        if (!v) { input.style.borderColor = 'var(--red)'; return; }
        closeModal();
        act(crew.events.create, [v]);
        toast('Création envoyée', 'ok');
    };
    ok.onclick = modalOk;
    document.getElementById('crew-modal').classList.remove('hidden');
    setTimeout(() => input.focus(), 50);
}
function closeModal() {
    document.getElementById('crew-modal').classList.add('hidden');
    modalOk = null;
}

/* ---------------------------- toast ---------------------------- */
let toastTimer = null;
function toast(msg, type) {
    const t = document.getElementById('crew-toast');
    t.textContent = msg;
    t.className = (type || '');
    t.classList.remove('hidden');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.add('hidden'), 2200);
}

/* ---------------------------- utils ---------------------------- */
function esc(s) {
    return (s == null ? '' : String(s)).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

/* ---------------------------- events ---------------------------- */
window.addEventListener('message', (e) => {
    const d = e.data; if (!d) return;
    if (d.action === 'openCrew')   openCrew(d.data || {});
    if (d.action === 'updateCrew') updateCrew(d.data || {});
    if (d.action === 'closeCrew')  document.getElementById('crew-overlay').classList.add('hidden');
});

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (!document.getElementById('crew-modal').classList.contains('hidden')) closeModal();
        else if (!document.getElementById('crew-overlay').classList.contains('hidden')) closeCrew();
    }
    if (e.key === 'Enter' && !document.getElementById('crew-modal').classList.contains('hidden') && modalOk) {
        e.preventDefault(); modalOk();
    }
});
