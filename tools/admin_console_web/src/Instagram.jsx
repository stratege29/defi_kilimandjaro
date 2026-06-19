import { useEffect, useState } from 'react';
import {
  collection,
  onSnapshot,
  orderBy,
  query,
  addDoc,
  doc,
  setDoc,
  deleteDoc,
} from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from './firebase.js';

function todayKey() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function formatChip(type) {
  if (type === 'reel') return <span className="chip orange">🎬 Reel</span>;
  if (type === 'carousel') return <span className="chip">🖼 Carrousel</span>;
  return <span className="chip grey">Image</span>;
}
function statusChip(d) {
  if (d.posted) return <span className="chip green">Publié</span>;
  if ((d.date || '') < todayKey()) return <span className="chip red">En retard</span>;
  return <span className="chip grey">Programmé</span>;
}

function thumbOf(d) {
  if (d.type === 'carousel') return (d.urls || [])[0];
  if (d.type === 'reel') return d.cover || d.url;
  return d.url;
}

function Thumb({ d }) {
  const src = thumbOf(d);
  const wrap = {
    position: 'relative', width: 50, height: 64, borderRadius: 8,
    overflow: 'hidden', background: '#0a130f', border: '1px solid var(--hair,#2C4034)',
  };
  const badge = {
    position: 'absolute', bottom: 2, right: 2, fontSize: 11, lineHeight: 1,
    background: 'rgba(0,0,0,.55)', color: '#fff', borderRadius: 4, padding: '1px 3px',
  };
  return (
    <div style={wrap}>
      {src
        ? <img src={src} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
        : <div className="muted" style={{ display: 'grid', placeItems: 'center', height: '100%' }}>—</div>}
      {d.type === 'reel' && <span style={badge}>▶</span>}
      {d.type === 'carousel' && <span style={badge}>▣ {(d.urls || []).length}</span>}
    </div>
  );
}

export default function Instagram() {
  const [sub, setSub] = useState('sched');
  return (
    <>
      <header className="topbar">
        <h2>Instagram · @defi_kilimandjaro</h2>
        <span className="spacer" />
      </header>
      <div className="tabs">
        <button className={sub === 'stats' ? 'tab active' : 'tab'} onClick={() => setSub('stats')}>📈 Stats</button>
        <button className={sub === 'sched' ? 'tab active' : 'tab'} onClick={() => setSub('sched')}>🗓️ Calendrier</button>
        <button className={sub === 'grid' ? 'tab active' : 'tab'} onClick={() => setSub('grid')}>▦ Grille</button>
        <button className={sub === 'mosaic' ? 'tab active' : 'tab'} onClick={() => setSub('mosaic')}>🧩 Mosaïque</button>
        <button className={sub === 'stories' ? 'tab active' : 'tab'} onClick={() => setSub('stories')}>📲 Stories</button>
        <button className={sub === 'ia' ? 'tab active' : 'tab'} onClick={() => setSub('ia')}>🎨 Images IA</button>
        <button className={sub === 'play' ? 'tab active' : 'tab'} onClick={() => setSub('play')}>🚀 Playbook</button>
      </div>
      {sub === 'stats' && <Stats />}
      {sub === 'sched' && <Scheduler />}
      {sub === 'grid' && <Grid />}
      {sub === 'mosaic' && <Mosaic />}
      {sub === 'stories' && <Stories />}
      {sub === 'ia' && <AiImages />}
      {sub === 'play' && <Playbook />}
    </>
  );
}

function Scheduler() {
  const [items, setItems] = useState(null);
  const [error, setError] = useState(null);
  const [editing, setEditing] = useState(undefined); // undefined=fermé, null=nouveau, obj=édition
  const [viewing, setViewing] = useState(null);

  useEffect(() => {
    const q = query(collection(db, 'instagram_queue'), orderBy('date'));
    return onSnapshot(
      q,
      (snap) => setItems(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (e) => setError(`${e.code}: ${e.message}`),
    );
  }, []);

  async function publishNow(id) {
    if (!confirm('Publier ce post maintenant sur Instagram ?')) return;
    try {
      const r = await httpsCallable(functions, 'igPublishPost')({ id });
      alert(`Publié ✅ (media ${r.data.id})`);
    } catch (e) {
      alert(`Erreur : ${e.code || e.name}: ${e.message}`);
    }
  }

  const queued = items?.filter((x) => !x.posted).length ?? 0;

  return (
    <>
      <div className="row" style={{ margin: '0 0 12px' }}>
        <span className="muted small">
          Publication auto chaque jour à 19h30 (Paris) · {queued} post(s) à venir
        </span>
        <span className="spacer" />
        <button className="btn primary small" onClick={() => setEditing(null)}>+ Nouveau post</button>
      </div>

      {error && <p className="error block">Erreur : {error}</p>}
      {!error && items === null && <p className="muted block">Chargement…</p>}

      {items?.length > 0 && (
        <table className="table">
          <thead>
            <tr><th></th><th>Date</th><th>Format</th><th>Statut</th><th>Légende</th><th></th></tr>
          </thead>
          <tbody>
            {items.map((it) => (
              <tr key={it.id} className={it.date === todayKey() ? 'today' : undefined}>
                <td style={{ cursor: 'pointer' }} onClick={() => setViewing(it)} title="Voir en grand / lire"><Thumb d={it} /></td>
                <td className="mono">{it.date}</td>
                <td>{formatChip(it.type)}</td>
                <td>{statusChip(it)}</td>
                <td className="truncate">{(it.caption || '').slice(0, 80)}</td>
                <td className="row-actions">
                  <button className="btn ghost small" onClick={() => setViewing(it)}>Voir</button>
                  <button className="btn ghost small" onClick={() => setEditing(it)}>Éditer</button>
                  {!it.posted && (
                    <button className="btn primary small" onClick={() => publishNow(it.id)}>Publier</button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {viewing && <Viewer post={viewing} onClose={() => setViewing(null)} canEdit editLabel="Éditer le post" onEdit={(p) => { setViewing(null); setEditing(p); }} />}
      {editing !== undefined && (
        <PostForm initial={editing} onClose={() => setEditing(undefined)} />
      )}
    </>
  );
}

const gridCorner = {
  position: 'absolute', top: 4, right: 5, color: '#fff', fontSize: 13, lineHeight: 1,
  textShadow: '0 1px 2px rgba(0,0,0,.7)',
};
const gridDateTag = {
  position: 'absolute', left: 4, bottom: 4, fontSize: 10, fontWeight: 600, color: '#fff',
  background: 'rgba(0,0,0,.55)', borderRadius: 4, padding: '1px 4px', lineHeight: 1.3,
};
const gridLateDot = {
  position: 'absolute', top: 6, left: 6, width: 8, height: 8, borderRadius: '50%',
  background: '#e5484d', boxShadow: '0 0 0 2px rgba(0,0,0,.45)',
};

function Grid() {
  const [items, setItems] = useState(null);
  const [error, setError] = useState(null);
  const [editing, setEditing] = useState(undefined);
  const [viewing, setViewing] = useState(null);

  useEffect(() => {
    // Ordre profil Instagram : le plus récent en premier.
    const q = query(collection(db, 'instagram_queue'), orderBy('date', 'desc'));
    return onSnapshot(
      q,
      (snap) => setItems(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (e) => setError(`${e.code}: ${e.message}`),
    );
  }, []);

  return (
    <>
      <p className="muted small block">
        Aperçu façon profil Instagram (le plus récent en haut à gauche). Vignette à pastille rouge = en retard,
        date affichée = pas encore publié. Clique une vignette pour la voir en grand / lire le reel (puis éditer).
      </p>
      {error && <p className="error block">Erreur : {error}</p>}
      {!error && items === null && <p className="muted block">Chargement…</p>}
      {items && items.length === 0 && <p className="muted block">Aucun post.</p>}
      {items && items.length > 0 && (
        <div style={{ maxWidth: 480, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 3 }}>
          {items.map((it) => {
            const src = thumbOf(it);
            const late = !it.posted && (it.date || '') < todayKey();
            return (
              <button
                key={it.id}
                onClick={() => setViewing(it)}
                title={`${it.date} · ${it.posted ? 'publié' : 'programmé'}\n${(it.caption || '').slice(0, 120)}`}
                style={{
                  position: 'relative', aspectRatio: '1 / 1', padding: 0, border: 'none',
                  cursor: 'pointer', background: '#0a130f', overflow: 'hidden', borderRadius: 2,
                  opacity: it.posted ? 1 : 0.9,
                }}
              >
                {src
                  ? <img src={src} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
                  : <span className="muted small" style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center' }}>—</span>}
                {it.type === 'reel' && <span style={gridCorner}>▶</span>}
                {it.type === 'carousel' && <span style={gridCorner}>▣</span>}
                {!it.posted && <span style={gridDateTag}>{(it.date || '').slice(5)}</span>}
                {late && <span style={gridLateDot} />}
              </button>
            );
          })}
        </div>
      )}
      {viewing && <Viewer post={viewing} onClose={() => setViewing(null)} canEdit editLabel="Éditer le post" onEdit={(p) => { setViewing(null); setEditing(p); }} />}
      {editing !== undefined && <PostForm initial={editing} onClose={() => setEditing(undefined)} />}
    </>
  );
}

function Mosaic() {
  const [items, setItems] = useState(null);
  const [error, setError] = useState(null);
  const [autopilot, setAutopilot] = useState(true);
  const [campaign, setCampaign] = useState(false);
  const [busy, setBusy] = useState(false);
  const [composing, setComposing] = useState(null);
  const [viewing, setViewing] = useState(null);

  useEffect(() => onSnapshot(collection(db, 'instagram_queue'),
    (snap) => setItems(snap.docs.map((d) => ({ id: d.id, ...d.data() })).filter((x) => x.mosaic)),
    (e) => setError(`${e.code}: ${e.message}`)), []);

  useEffect(() => onSnapshot(doc(db, 'instagram_meta', 'config'),
    (snap) => {
      const c = snap.exists() ? snap.data() : {};
      setAutopilot(c.autopilotEnabled !== false);
      setCampaign(c.mosaicAuto === true);
    },
    () => {}), []);

  // groupe -> { word, col, rows, cells: {[row]: {[col]: item}} }
  const groups = {};
  (items || []).forEach((it) => {
    const m = it.id.match(/_r(\d+)_c(\d+)$/);
    if (!m) return;
    const g = it.mosaic.group;
    const row = +m[1], col = +m[2];
    groups[g] = groups[g] || { group: g, word: it.mosaic.word, col: it.mosaic.col, rows: 0, cells: {} };
    groups[g].cells[row] = groups[g].cells[row] || {};
    groups[g].cells[row][col] = it;
    groups[g].rows = Math.max(groups[g].rows, row + 1);
  });
  const list = Object.values(groups);

  async function toggleAutopilot() {
    setBusy(true);
    try { await httpsCallable(functions, 'igSetAutopilot')({ enabled: !autopilot }); }
    catch (e) { alert(`Erreur : ${e.code || e.name}: ${e.message}`); }
    finally { setBusy(false); }
  }

  async function toggleCampaign() {
    const next = !campaign;
    if (next && !confirm('Activer le mode campagne ?\n\n• L\'autopilote normal passe en pause.\n• Une rangée mosaïque (3 posts) sera publiée automatiquement chaque jour à 19h30, du bas vers le haut.')) return;
    setBusy(true);
    try { await httpsCallable(functions, 'igSetCampaign')({ active: next }); }
    catch (e) { alert(`Erreur : ${e.code || e.name}: ${e.message}`); }
    finally { setBusy(false); }
  }

  async function publishRow(group, nextRow) {
    if (!confirm(`Publier la rangée ${nextRow + 1} (3 posts) maintenant sur Instagram ?\n\nLes posts partent ensemble pour garder la grille alignée.`)) return;
    setBusy(true);
    try {
      const r = await httpsCallable(functions, 'igPublishMosaicRow', { timeout: 540000 })({ group });
      alert(`Rangée ${(r.data.row ?? 0) + 1} publiée ✅ (${r.data.count} posts)`);
    } catch (e) {
      alert(`Erreur : ${e.code || e.name}: ${e.message}`);
    } finally { setBusy(false); }
  }

  const cellBox = (it, isLetter) => {
    const has = !!(it && (it.url || it.cover));
    const wrap = {
      position: 'relative', aspectRatio: '1 / 1', borderRadius: 4, overflow: 'hidden',
      background: '#0a130f', border: isLetter ? '2px solid var(--gold,#E9B949)' : '1px solid var(--hair,#2C4034)',
      opacity: it && it.posted ? 1 : 0.85, cursor: has ? 'pointer' : 'default',
    };
    const thumb = it ? (it.type === 'reel' ? (it.cover || it.url) : it.url) : null;
    return (
      <div style={wrap} onClick={has ? () => setViewing(it) : undefined} title={has ? (it.type === 'reel' ? 'Voir le reel' : 'Voir en grand') : ''}>
        {thumb
          ? <img src={thumb} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
          : <span className="muted" style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', fontSize: 11 }}>—</span>}
        {it && it.type === 'reel' && <span style={{ position: 'absolute', bottom: 3, right: 4, fontSize: 11 }}>🎬</span>}
        {it && it.posted && <span style={{ position: 'absolute', top: 3, right: 4, fontSize: 12 }}>✅</span>}
      </div>
    );
  };

  return (
    <>
      <div className="row" style={{ margin: '0 0 8px', alignItems: 'center' }}>
        <span className="muted small">
          Feed-mosaïque : une colonne du profil épelle un mot. Publication par <b>rangées de 3</b>, du bas vers le haut.
        </span>
        <span className="spacer" />
        <span className={campaign ? 'chip green' : 'chip grey'} style={{ marginRight: 8 }}>
          {campaign ? '🟢 Campagne active (auto 1 rangée/jour)' : 'Campagne inactive'}
        </span>
        <button className="btn primary small" disabled={busy} onClick={toggleCampaign}>
          {campaign ? 'Arrêter la campagne' : 'Démarrer la campagne'}
        </button>
      </div>
      <div className="row" style={{ margin: '0 0 12px', alignItems: 'center' }}>
        <span className="muted small">
          {campaign
            ? 'Mode campagne ON : l\'autopilote normal est en pause, une rangée part chaque jour. Tu peux aussi pousser une rangée à la main ci-dessous.'
            : `Autopilote normal : ${autopilot ? 'actif' : 'en pause'}.`}
        </span>
        <span className="spacer" />
        {!campaign && (
          <button className="btn ghost small" disabled={busy} onClick={toggleAutopilot}>
            {autopilot ? 'Mettre l’autopilote en pause' : 'Réactiver l’autopilote'}
          </button>
        )}
      </div>

      <p className="muted small block">
        Pour générer une mosaïque : <span className="mono">python functions/scripts/gen_mosaic.py MOT COLONNE</span> puis
        <span className="mono"> node functions/scripts/add_mosaic.js mosaic_&lt;slug&gt; --commit</span>.
        Pendant une campagne, garde l'autopilote <b>en pause</b> et ne publie que des rangées complètes.
      </p>

      {error && <p className="error block">Erreur : {error}</p>}
      {!error && items === null && <p className="muted block">Chargement…</p>}
      {items && list.length === 0 && <p className="muted block">Aucune mosaïque pour l'instant.</p>}

      {list.map((g) => {
        let postedRows = 0, nextRow = -1;
        for (let r = 0; r < g.rows; r += 1) {
          const row = g.cells[r] || {};
          const full = [0, 1, 2].every((c) => row[c] && row[c].posted);
          if (full) postedRows += 1;
          if (!full && (g.cells[r])) nextRow = Math.max(nextRow, r); // bas non publié
        }
        const done = postedRows >= g.rows;
        return (
          <div key={g.group} className="card block" style={{ padding: 14, marginBottom: 14 }}>
            <div className="row" style={{ alignItems: 'center', marginBottom: 10 }}>
              <div>
                <div style={{ fontWeight: 700, fontSize: 18 }}>
                  {(!g.word || g.col < 0)
                    ? <>Séparateur <span className="muted small">· rangée déco</span></>
                    : <>« {g.word} » <span className="muted small">· colonne {['gauche', 'milieu', 'droite'][g.col] || g.col}</span></>}
                </div>
                <div className="muted small">{postedRows}/{g.rows} rangée(s) publiée(s)</div>
              </div>
              <span className="spacer" />
              {done
                ? <span className="chip green">Complet 🎉</span>
                : <button className="btn primary" disabled={busy || nextRow < 0 || !(campaign || !autopilot)}
                    title={(campaign || !autopilot) ? '' : 'Démarre la campagne ou mets l’autopilote en pause'}
                    onClick={() => publishRow(g.group, nextRow)}>
                    {busy ? '…' : `Publier la rangée ${nextRow + 1} (3)`}
                  </button>}
            </div>
            {!(campaign || !autopilot) && !done && <p className="muted small" style={{ margin: '0 0 8px' }}>⏸ Démarre la campagne (ou mets l’autopilote en pause) pour publier une rangée.</p>}
            <div style={{ maxWidth: 320, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 4 }}>
              {Array.from({ length: g.rows }).flatMap((_, r) =>
                [0, 1, 2].map((c) => {
                  const it = (g.cells[r] || {})[c];
                  return <span key={`${r}-${c}`}>{cellBox(it, c === g.col)}</span>;
                }))}
            </div>
          </div>
        );
      })}
      {viewing && <Viewer post={viewing} onClose={() => setViewing(null)} onEdit={(p) => { setViewing(null); setComposing(p); }} />}
      {composing && <CardComposer doc={composing} onClose={() => setComposing(null)} />}
    </>
  );
}

function Viewer({ post, onClose, onEdit, canEdit, editLabel = 'Éditer' }) {
  const isReel = post.type === 'reel';
  const isCarousel = post.type === 'carousel';
  const media = isCarousel ? (post.urls || []) : [post.url];
  const showEdit = onEdit && (canEdit !== undefined ? canEdit : (post.type === 'image' && !post.posted));
  return (
    <div className="modal-backdrop" onClick={onClose} style={{ zIndex: 55 }}>
      <div onClick={(e) => e.stopPropagation()} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10, maxWidth: 'min(94vw, 560px)' }}>
        {isReel
          ? <video src={post.url} poster={post.cover} controls autoPlay loop playsInline style={{ width: '100%', maxHeight: '78vh', borderRadius: 12, background: '#000' }} />
          : isCarousel
            ? <div style={{ display: 'flex', gap: 6, overflowX: 'auto', maxWidth: '94vw' }}>
                {media.map((u, i) => <img key={i} src={u} alt="" style={{ height: '74vh', borderRadius: 10 }} />)}
              </div>
            : <img src={post.url} alt="" style={{ width: '100%', maxHeight: '82vh', objectFit: 'contain', borderRadius: 12 }} />}
        <div className="muted small" style={{ display: 'flex', gap: 8 }}>
          {formatChip(post.type)} {statusChip(post)} <span className="mono">{post.date}</span>
        </div>
        {post.caption && <p className="muted small" style={{ whiteSpace: 'pre-wrap', maxHeight: '16vh', overflow: 'auto', textAlign: 'center', margin: 0, maxWidth: 520 }}>{post.caption}</p>}
        <div className="row-actions">
          {showEdit && <button className="btn primary small" onClick={() => onEdit(post)}>{editLabel}</button>}
          <button className="btn ghost small" onClick={onClose}>Fermer</button>
        </div>
      </div>
    </div>
  );
}

const ACCENTS_OPT = [['culture', 'Culture (orange)'], ['nouchi', 'Nouchi (rose)'], ['villes', 'Villes (terracotta)'], ['foot', 'Foot (vert)']];
const AI_PHOTO_KEYS = ['abidjan', 'dakar', 'lagos', 'marrakech', 'yamoussoukro', 'kilimandjaro', 'baobab', 'balafon', 'masque', 'attieke', 'alloco', 'player', 'friends', 'duel'];

function CardComposer({ doc, onClose }) {
  const [tpl, setTpl] = useState(doc.cardSpec?.template || 'enigme');
  const s0 = doc.cardSpec || {};
  const [f, setF] = useState({
    categorie: s0.categorie || 'Culture 225',
    question: s0.question || '',
    answer: s0.answer || '',
    explanation: s0.explanation || '',
    texte: s0.texte || '',
    source: s0.source || 'Proverbe africain',
    accent: s0.accent || 'culture',
    photo: s0.photo || 'attieke',
    kicker: s0.kicker || 'Pack Culture 225',
    title: s0.title || '',
  });
  const [caption, setCaption] = useState(doc.caption || '');
  const [preview, setPreview] = useState(doc.type === 'image' ? doc.url : null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState(null);
  const [big, setBig] = useState(false);
  const set = (k, v) => setF((s) => ({ ...s, [k]: v }));

  function buildSpec() {
    if (tpl === 'enigme') return { template: 'enigme', categorie: f.categorie, question: f.question, answer: f.answer, accent: f.accent };
    if (tpl === 'reponse') return { template: 'reponse', categorie: f.categorie, answer: f.answer, explanation: f.explanation, accent: f.accent };
    if (tpl === 'medaillon') return { template: 'medaillon', photo: f.photo, kicker: f.kicker, title: f.title, accent: f.accent };
    return { template: 'proverbe', texte: f.texte, source: f.source };
  }

  async function run(save) {
    setBusy(true); setErr(null);
    try {
      const r = await httpsCallable(functions, 'igRenderCard', { timeout: 60000 })({ spec: buildSpec(), docId: save ? doc.id : undefined, caption: save ? caption : undefined });
      setPreview(r.data.url);
      if (save) onClose();
    } catch (e) { setErr(`${e.code || e.name}: ${e.message}`); }
    finally { setBusy(false); }
  }

  const field = (label, k, ph) => (
    <label className="block" style={{ marginBottom: 8 }}>
      <span className="muted small">{label}</span>
      <input className="input" value={f[k]} placeholder={ph} onChange={(e) => set(k, e.target.value)} style={{ width: '100%' }} />
    </label>
  );

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 840, display: 'grid', gridTemplateColumns: '1fr 380px', gap: 16 }}>
        <div>
          <h3 style={{ marginTop: 0 }}>Composer la carte <span className="muted small">· {doc.id}</span></h3>
          <div className="tabs" style={{ marginBottom: 10 }}>
            {[['enigme', 'Énigme'], ['reponse', 'Réponse'], ['proverbe', 'Proverbe'], ['medaillon', 'Médaillon']].map(([k, lab]) => (
              <button key={k} className={tpl === k ? 'tab active' : 'tab'} onClick={() => setTpl(k)}>{lab}</button>
            ))}
          </div>
          {tpl === 'enigme' && <>
            {field('Catégorie', 'categorie', 'Culture 225')}
            <label className="block" style={{ marginBottom: 8 }}><span className="muted small">Question / devinette</span>
              <textarea className="input" rows={3} value={f.question} onChange={(e) => set('question', e.target.value)} style={{ width: '100%' }} /></label>
            {field('Réponse (pour le nb de cases)', 'answer', 'ALLOCO')}
          </>}
          {tpl === 'reponse' && <>
            {field('Catégorie', 'categorie', 'Crack Nouchi')}
            {field('Réponse (en tuiles vertes)', 'answer', 'ENJAILLE')}
            <label className="block" style={{ marginBottom: 8 }}><span className="muted small">Explication</span>
              <textarea className="input" rows={3} value={f.explanation} onChange={(e) => set('explanation', e.target.value)} style={{ width: '100%' }} /></label>
          </>}
          {tpl === 'proverbe' && <>
            <label className="block" style={{ marginBottom: 8 }}><span className="muted small">Texte du proverbe</span>
              <textarea className="input" rows={3} value={f.texte} onChange={(e) => set('texte', e.target.value)} style={{ width: '100%' }} /></label>
            {field('Source', 'source', 'Proverbe akan')}
          </>}
          {tpl === 'medaillon' && <>
            <label className="block" style={{ marginBottom: 8 }}><span className="muted small">Photo (disque)</span>
              <select className="input" value={f.photo} onChange={(e) => set('photo', e.target.value)} style={{ width: '100%' }}>
                {AI_PHOTO_KEYS.map((k) => <option key={k} value={k}>{k}</option>)}
              </select></label>
            {field('Kicker (au-dessus du titre)', 'kicker', 'Pack Culture 225')}
            <label className="block" style={{ marginBottom: 8 }}><span className="muted small">Titre</span>
              <textarea className="input" rows={2} value={f.title} onChange={(e) => set('title', e.target.value)} style={{ width: '100%' }} /></label>
          </>}
          {tpl !== 'proverbe' && (
            <label className="block" style={{ marginBottom: 8 }}><span className="muted small">Accent</span>
              <select className="input" value={f.accent} onChange={(e) => set('accent', e.target.value)} style={{ width: '100%' }}>
                {ACCENTS_OPT.map(([k, lab]) => <option key={k} value={k}>{lab}</option>)}
              </select></label>
          )}
          <label className="block" style={{ marginBottom: 8 }}><span className="muted small">Légende du post</span>
            <textarea className="input" rows={2} value={caption} onChange={(e) => setCaption(e.target.value)} style={{ width: '100%' }} /></label>
          {err && <p className="error block">{err}</p>}
          <div className="row-actions" style={{ marginTop: 6 }}>
            <button className="btn ghost" disabled={busy} onClick={() => run(false)}>{busy ? '…' : 'Aperçu'}</button>
            <button className="btn primary" disabled={busy} onClick={() => run(true)}>{busy ? '…' : 'Régénérer & enregistrer'}</button>
            <button className="btn ghost" onClick={onClose}>Annuler</button>
          </div>
        </div>
        <div>
          <span className="muted small">Aperçu {preview && <span className="muted">· clic pour agrandir</span>}</span>
          <div onClick={() => preview && setBig(true)} style={{ aspectRatio: '1/1', borderRadius: 8, overflow: 'hidden', background: '#0a130f', border: '1px solid var(--hair,#2C4034)', marginTop: 4, cursor: preview ? 'zoom-in' : 'default' }}>
            {preview ? <img src={preview} alt="" style={{ width: '100%', height: '100%', objectFit: 'contain' }} />
              : <span className="muted small" style={{ display: 'grid', placeItems: 'center', height: '100%' }}>Aperçu après rendu</span>}
          </div>
        </div>
      </div>
      {big && preview && (
        <div className="modal-backdrop" onClick={() => setBig(false)} style={{ zIndex: 60 }}>
          <img src={preview} alt="" style={{ maxWidth: '92vw', maxHeight: '90vh', objectFit: 'contain', borderRadius: 12 }} />
        </div>
      )}
    </div>
  );
}

function PostForm({ initial, onClose }) {
  const isEdit = !!(initial && initial.id);
  const [date, setDate] = useState(initial?.date ?? todayKey());
  const [type, setType] = useState(initial?.type ?? 'image');
  const [url, setUrl] = useState(initial?.url ?? '');
  const [urls, setUrls] = useState((initial?.urls ?? []).join(', '));
  const [cover, setCover] = useState(initial?.cover ?? '');
  const [caption, setCaption] = useState(initial?.caption ?? '');
  const [posted, setPosted] = useState(!!initial?.posted);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState(null);

  async function save() {
    setBusy(true); setErr(null);
    try {
      const docData = { date, type, caption, posted };
      if (type === 'carousel') docData.urls = urls.split(',').map((s) => s.trim()).filter(Boolean);
      else docData.url = url.trim();
      if (type === 'reel' && cover.trim()) docData.cover = cover.trim();
      if (isEdit) await setDoc(doc(db, 'instagram_queue', initial.id), docData, { merge: true });
      else await addDoc(collection(db, 'instagram_queue'), docData);
      onClose();
    } catch (e) {
      setErr(`${e.code || e.name}: ${e.message}`);
    } finally { setBusy(false); }
  }
  async function remove() {
    if (!confirm('Supprimer ce post ?')) return;
    try { await deleteDoc(doc(db, 'instagram_queue', initial.id)); onClose(); }
    catch (e) { setErr(`${e.code || e.name}: ${e.message}`); }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>{isEdit ? `Éditer le post du ${date}` : 'Nouveau post'}</h3>
        <div className="grid2">
          <div>
            <label>Date (yyyy-MM-dd)</label>
            <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </div>
          <div>
            <label>Format</label>
            <select value={type} onChange={(e) => setType(e.target.value)}>
              <option value="image">Image</option>
              <option value="carousel">Carrousel</option>
              <option value="reel">Reel</option>
            </select>
          </div>
        </div>
        {type === 'carousel' ? (
          <>
            <label>URLs du carrousel (séparées par des virgules)</label>
            <textarea rows={2} value={urls} onChange={(e) => setUrls(e.target.value)} />
          </>
        ) : (
          <>
            <label>URL média ({type === 'reel' ? 'vidéo MP4' : 'image'})</label>
            <input value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://…" />
          </>
        )}
        {type === 'reel' && (
          <>
            <label>Cover du Reel (optionnel)</label>
            <input value={cover} onChange={(e) => setCover(e.target.value)} placeholder="https://…" />
          </>
        )}
        {(() => {
          const prev = type === 'carousel'
            ? (urls.split(',')[0] || '').trim()
            : (type === 'reel' ? (cover || url) : url).trim();
          return prev ? (
            <img src={prev} alt="" style={{ maxHeight: 170, borderRadius: 8, marginTop: 10, border: '1px solid var(--hair,#2C4034)', display: 'block' }} />
          ) : null;
        })()}
        <label>Légende</label>
        <textarea rows={5} value={caption} onChange={(e) => setCaption(e.target.value)} />
        <label className="check">
          <input type="checkbox" checked={posted} onChange={(e) => setPosted(e.target.checked)} /> Déjà publié
        </label>
        {err && <pre className="error">{err}</pre>}
        <div className="row actions">
          {isEdit && <button className="btn danger" onClick={remove}>Supprimer</button>}
          <span className="spacer" />
          <button className="btn ghost" onClick={onClose}>Annuler</button>
          <button className="btn primary" disabled={busy} onClick={save}>
            {busy ? 'Enregistrement…' : 'Enregistrer'}
          </button>
        </div>
      </div>
    </div>
  );
}

function Stats() {
  const [data, setData] = useState(null);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState('');

  async function refresh() {
    setBusy(true); setNote('Chargement…');
    try {
      const r = await httpsCallable(functions, 'igInsights')({});
      setData(r.data);
      setNote(r.data.account?.error
        ? `Stats compte indisponibles : ${r.data.account.error}`
        : `Dernière mise à jour : ${new Date(r.data.fetchedAt).toLocaleString('fr-FR')}`);
    } catch (e) {
      setNote(`Erreur : ${e.code || e.name}: ${e.message}`);
    } finally { setBusy(false); }
  }

  const a = data?.account || {};
  const media = data?.media || [];
  const eng = media.length
    ? Math.round(media.reduce((s, m) => s + (m.like_count || 0) + (m.comments_count || 0), 0) / media.length)
    : '—';
  const num = { fontSize: 32, fontWeight: 800, color: 'var(--gold, #E9B949)', lineHeight: 1 };

  return (
    <>
      <div className="row" style={{ margin: '0 0 14px' }}>
        <span className="muted small">Données live depuis l'API Instagram</span>
        <span className="spacer" />
        <button className="btn ghost small" disabled={busy} onClick={refresh}>↻ Rafraîchir</button>
      </div>
      <div className="cards">
        <div className="card"><div style={num}>{a.followers_count ?? '—'}</div><div className="muted small">Abonnés</div></div>
        <div className="card"><div style={num}>{a.media_count ?? '—'}</div><div className="muted small">Publications</div></div>
        <div className="card"><div style={num}>{eng}</div><div className="muted small">Engagement moyen / post</div></div>
      </div>
      {note && <p className="muted small block">{note}</p>}
      {media.length > 0 && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(140px,1fr))', gap: 10, marginTop: 14 }}>
          {media.map((m) => {
            const img = m.media_type === 'VIDEO' ? (m.thumbnail_url || m.media_url) : m.media_url;
            return (
              <a key={m.id} href={m.permalink} target="_blank" rel="noreferrer"
                 className="card" style={{ padding: 0, overflow: 'hidden', textDecoration: 'none' }}>
                <img src={img || ''} alt="" style={{ width: '100%', height: 140, objectFit: 'cover', display: 'block' }} />
                <div className="muted small" style={{ padding: '6px 8px' }}>❤ {m.like_count || 0} · 💬 {m.comments_count || 0}</div>
              </a>
            );
          })}
        </div>
      )}
    </>
  );
}

const AI_SUBJECTS = ['abidjan','dakar','lagos','marrakech','yamoussoukro','kilimandjaro','baobab','balafon','masque','attieke','alloco','player','friends','duel'];

function AiImages() {
  const [imgs, setImgs] = useState({});
  const [busy, setBusy] = useState(null);
  const [err, setErr] = useState(null);
  const [adding, setAdding] = useState(undefined);
  const [quality, setQuality] = useState('high');

  useEffect(() => onSnapshot(collection(db, 'ai_images'),
    (snap) => { const o = {}; snap.forEach((d) => { o[d.id] = d.data(); }); setImgs(o); },
    (e) => setErr(`${e.code}: ${e.message}`)), []);

  async function gen(key) {
    setBusy(key); setErr(null);
    try {
      // gpt-image-1 « high » prend ~1 min : on étend le délai client (défaut 70s)
      // au timeout serveur (300s), sinon l'appel échoue alors que l'image se génère.
      await httpsCallable(functions, 'igGenerateImages', { timeout: 300000 })({ keys: [key], quality });
    } catch (e) {
      // L'image arrive de toute façon via onSnapshot : un simple dépassement de délai
      // client n'est pas une vraie erreur, on ne l'affiche pas.
      const code = e.code || e.name || '';
      if (!String(code).includes('deadline-exceeded')) setErr(`${code}: ${e.message}`);
    } finally { setBusy(null); }
  }

  return (
    <>
      <p className="muted small block">
        Style signature OpenAI (illustration). Génère une image (garde le bouton « … » jusqu'au bout),
        puis « Ajouter » la met dans le calendrier.
        Nécessite le secret <span className="mono">OPENAI_API_KEY</span> + le déploiement de <span className="mono">igGenerateImages</span>.
      </p>
      <div className="block" style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <span className="muted small">Qualité :</span>
        <button className={quality === 'medium' ? 'tab active' : 'tab'} onClick={() => setQuality('medium')}>
          Medium (~30s · ~0,06 $)
        </button>
        <button className={quality === 'high' ? 'tab active' : 'tab'} onClick={() => setQuality('high')}>
          High (~1 min · ~0,16 $)
        </button>
      </div>
      {err && <p className="error block">Erreur : {err}</p>}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(150px,1fr))', gap: 12 }}>
        {AI_SUBJECTS.map((k) => {
          const im = imgs[k];
          return (
            <div key={k} className="card" style={{ padding: 8 }}>
              <div style={{ height: 170, borderRadius: 8, overflow: 'hidden', background: '#0a130f', display: 'grid', placeItems: 'center' }}>
                {im ? <img src={im.url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                    : <span className="muted small">non générée</span>}
              </div>
              <div className="mono small" style={{ margin: '6px 2px' }}>{k}</div>
              <div className="row-actions">
                <button className="btn ghost small" disabled={busy === k} onClick={() => gen(k)}>
                  {busy === k ? '…' : (im ? 'Régénérer' : 'Générer')}
                </button>
                {im && <button className="btn primary small" onClick={() => setAdding({ type: 'image', url: im.url, caption: '' })}>Ajouter</button>}
              </div>
            </div>
          );
        })}
      </div>
      {adding !== undefined && <PostForm initial={adding} onClose={() => setAdding(undefined)} />}
    </>
  );
}

function Stories() {
  const [items, setItems] = useState(null);
  const [auto, setAuto] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState(null);
  const [viewing, setViewing] = useState(null);

  useEffect(() => {
    const q = query(collection(db, 'instagram_stories'), orderBy('storyAt', 'asc'));
    return onSnapshot(q, (snap) => setItems(snap.docs.map((d) => ({ id: d.id, ...d.data() }))), (e) => setErr(`${e.code}: ${e.message}`));
  }, []);
  useEffect(() => onSnapshot(doc(db, 'instagram_meta', 'config'), (s) => setAuto(s.data()?.storiesAuto === true)), []);

  const fmt = (ts) => { const d = ts?.toDate?.(); return d ? d.toLocaleString('fr-FR', { weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—'; };
  async function call(name, data) {
    setBusy(true); setErr(null);
    try { await httpsCallable(functions, name, { timeout: 300000 })(data); }
    catch (e) { setErr(`${e.code || e.name}: ${e.message}`); } finally { setBusy(false); }
  }

  return (
    <>
      <header className="topbar"><h2>Stories</h2><span className="spacer" /></header>
      <div className="card block" style={{ padding: 14, marginBottom: 12 }}>
        <div className="row" style={{ alignItems: 'center', gap: 12 }}>
          <strong>Autopilote stories : {auto ? <span className="chip green">ON</span> : <span className="chip">OFF</span>}</strong>
          <span className="spacer" />
          <button className={auto ? 'btn ghost' : 'btn primary'} disabled={busy} onClick={() => call('igSetStoriesAuto', { enabled: !auto })}>
            {busy ? '…' : auto ? 'Mettre en pause' : 'Activer'}
          </button>
        </div>
        <p className="muted small" style={{ marginBottom: 0 }}>
          Publie automatiquement 2 stories/jour : <b>énigme à 07:30</b>, <b>réponse à 20:30</b> (heure d'Abidjan).
          Limite API Instagram : pas de sondage, sticker ou lien (à faire à la main). Génère/recharge la file avec <code>gen_stories.py</code> + <code>add_stories.js</code>.
        </p>
      </div>
      {err && <p className="error block">{err}</p>}
      {items === null && <p className="muted block">Chargement…</p>}
      {items && items.length === 0 && <p className="muted block">Aucune story en file. Lance <code>node functions/scripts/add_stories.js --commit</code>.</p>}
      {items && items.length > 0 && (
        <table className="table">
          <thead><tr><th></th><th>Quand</th><th>Type</th><th>Contenu</th><th>Statut</th><th></th></tr></thead>
          <tbody>
            {items.map((s) => (
              <tr key={s.id}>
                <td onClick={() => setViewing(s)} style={{ cursor: 'pointer' }}>
                  <div style={{ position: 'relative', width: 38, height: 67, borderRadius: 4, overflow: 'hidden', background: '#0a130f' }}>
                    {s.url && (s.mediaType === 'video'
                      ? <video src={s.url} muted playsInline preload="metadata" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                      : <img src={s.url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />)}
                    {s.mediaType === 'video' && <span style={{ position: 'absolute', bottom: 1, right: 2, fontSize: 9 }}>🎬</span>}
                  </div>
                </td>
                <td className="mono small">{fmt(s.storyAt)}</td>
                <td>{s.kind === 'enigme' ? 'Énigme' : s.kind === 'reponse' ? 'Réponse' : s.kind}</td>
                <td className="small truncate">{s.label || s.answer || ''}</td>
                <td>{s.posted ? <span className="chip green">Publiée</span> : <span className="chip">Programmée</span>}</td>
                <td className="row-actions">
                  <button className="btn ghost small" onClick={() => setViewing(s)}>Voir</button>
                  {!s.posted && <button className="btn primary small" disabled={busy} onClick={() => confirm('Publier cette story maintenant ?') && call('igPublishStoryNow', { id: s.id })}>Publier</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {viewing && <Viewer post={{ ...viewing, type: viewing.mediaType === 'video' ? 'reel' : 'image', date: fmt(viewing.storyAt), caption: viewing.label }} onClose={() => setViewing(null)} />}
    </>
  );
}

function Playbook() {
  return (
    <div className="block" style={{ maxWidth: 720 }}>
      <h3>Le ratio qui marche (2026)</h3>
      <p className="muted">Vise <b>50-60% Reels</b>, 25-30% carrousels, 15% images. Les Reels touchent les non-abonnés (≈55% de leurs vues). Rythme régulier : 4-7 posts/semaine.</p>
      <h3>Les 100 premiers abonnés</h3>
      <ul className="muted">
        <li>Commente utile/drôle sur 15-20 comptes/jour : food ivoirien, nouchi/humour 225, foot africain.</li>
        <li>Active ton réseau réel (amis, groupes WhatsApp diaspora) — les 30-50 premiers.</li>
        <li>Poste les Reels foot les jours de match du Mondial.</li>
      </ul>
      <h3>Hooks & engagement</h3>
      <ul className="muted">
        <li>1re ligne = défi identitaire / controverse chiffrée / tag-bait.</li>
        <li>Conçois pour le partage en DM (×3-5 vs likes).</li>
        <li>Carrousels "save-bait" (listes) → sauvegardes = portée durable.</li>
      </ul>
      <h3>Hashtags (3-5 ciblés)</h3>
      <div className="tags">
        {['#DéfiKilimandjaro', '#Nouchi', '#Culture225', '#CôteDIvoire', '#CoupeDuMonde2026', '#VillesDAfrique'].map((t) => (
          <span key={t} className="tag">{t}</span>
        ))}
      </div>
      <h3>Collabs à viser</h3>
      <ul className="muted">
        <li>Micro-créateurs diaspora / humour 225 (5-50k) → post Collab.</li>
        <li>Comptes food ivoirien → Reel "devine le plat" co-publié.</li>
        <li>Pages foot africain → pendant le Mondial.</li>
      </ul>
    </div>
  );
}
