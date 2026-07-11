import { useEffect, useMemo, useState } from 'react';
import { collection, doc, onSnapshot, orderBy, query } from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from './firebase.js';
import { normalize, lettersPoolFromAnswer } from './normalize.js';
import {
  THEME_PRESETS,
  THEME_ROLES,
  MOTIF_OPTIONS,
  TILE_SHAPE_OPTIONS,
  resolveThemeColors,
} from './packThemes.js';

const COUNTRIES = ['ci', 'sn', 'ml', 'cm', 'bj'];

/** `#RRGGBB` valide pour `<input type="color">` (ignore l'alpha 8-digits). */
function colorInputValue(hex) {
  if (typeof hex !== 'string') return '#000000';
  const v = hex.replace('#', '');
  return v.length >= 6 ? `#${v.slice(0, 6)}` : '#000000';
}

/** Style CSS de la forme d'une tuile-lettre (approximation du rendu app). */
function tileShapeStyle(shape) {
  switch (shape) {
    case 'rounded':
      return { borderRadius: '50%' };
    case 'hex':
      return { clipPath: 'polygon(25% 5%,75% 5%,100% 50%,75% 95%,25% 95%,0 50%)' };
    case 'diamond':
      return { clipPath: 'polygon(50% 0,100% 50%,50% 100%,0 50%)' };
    case 'sculpted':
    default:
      return { borderRadius: 8 };
  }
}

const MOTIF_LABELS = {
  none: 'aucun',
  adinkra: 'adinkra',
  kita: 'kita',
  bogolan: 'bogolan',
  kente: 'kente',
  vagues: 'vagues',
};
const SHAPE_LABELS = {
  sculpted: 'sculptée',
  rounded: 'arrondie',
  hex: 'hexagone',
  diamond: 'losange',
};

/**
 * Prévisualisation live du skin : mini-scène de jeu (fond, bulle question,
 * cellules-réponse, tuiles-lettres) rendue avec les couleurs résolues du
 * preset + overrides. Reflète en direct chaque changement du sélecteur.
 */
function ThemePreview({ themeId, packId, overrides, motif, tileShape }) {
  const { colors, motif: rMotif, tileShape: rShape } = useMemo(
    () => resolveThemeColors({ themeId, packId, overrides, motif, tileShape }),
    [themeId, packId, overrides, motif, tileShape],
  );
  const shapeCss = tileShapeStyle(rShape);
  // 4 tuiles : 3 au repos + 1 sélectionnée (dernière).
  const restTiles = ['K', 'A', 'B'];

  return (
    <div className="theme-preview-wrap">
      <div
        className="theme-preview"
        style={{
          background: `linear-gradient(160deg, ${colors.background}, ${colors.background_end})`,
        }}
      >
        {/* Bulle question */}
        <div
          className="tp-bubble"
          style={{ background: colors.bubble_background }}
        >
          <span
            className="tp-bubble-stripe"
            style={{ background: colors.bubble_accent }}
          />
          <span className="tp-bubble-text" style={{ color: colors.bubble_text }}>
            Quel fleuve traverse Abidjan ?
          </span>
        </div>

        {/* Cellules-réponse */}
        <div className="tp-cells">
          {[0, 1, 2, 3, 4].map((i) => {
            const filled = i < 2;
            return (
              <span
                key={i}
                className="tp-cell"
                style={{
                  background: filled ? colors.accent : 'transparent',
                  border: `1.5px solid ${colors.accent}`,
                  color: colors.on_accent,
                }}
              >
                {filled ? ['É', 'B'][i] : ''}
              </span>
            );
          })}
        </div>

        {/* Filet « golden path » indicatif */}
        <div className="tp-path" style={{ background: colors.path }} />

        {/* Tuiles-lettres */}
        <div className="tp-tiles">
          {restTiles.map((ch, i) => (
            <span
              key={i}
              className="tp-tile"
              style={{
                background: colors.tile,
                borderBottom: `3px solid ${colors.tile_edge}`,
                color: colors.tile_text,
                ...shapeCss,
              }}
            >
              {ch}
            </span>
          ))}
          <span
            className="tp-tile"
            style={{
              background: colors.tile_selected,
              borderBottom: `3px solid ${colors.tile_selected_edge}`,
              color: colors.tile_text,
              ...shapeCss,
            }}
          >
            J
          </span>
        </div>
      </div>
      <p className="muted small tp-caption">
        Motif : {MOTIF_LABELS[rMotif] ?? rMotif} · Tuiles : {SHAPE_LABELS[rShape] ?? rShape}
        {colors.sommets_tint && (
          <>
            {' · '}Teinte Sommets{' '}
            <span
              className="tp-swatch"
              style={{ background: colors.sommets_tint }}
            />
          </>
        )}
      </p>
    </div>
  );
}

export default function PackEditor({ packId, onBack }) {
  const [devis, setDevis] = useState(null);
  const [error, setError] = useState(null);
  const [editing, setEditing] = useState(null); // null | devinette obj | {__new:true}
  const [bulkOpen, setBulkOpen] = useState(false);
  const [metaOpen, setMetaOpen] = useState(false);
  const [catalogEntry, setCatalogEntry] = useState(null);
  const [validation, setValidation] = useState(null);
  const [validating, setValidating] = useState(false);

  useEffect(() => {
    setDevis(null);
    const q = query(
      collection(db, 'packs', packId, 'devinettes'),
      orderBy('id'),
    );
    return onSnapshot(
      q,
      (snap) => setDevis(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (e) => setError(`${e.code}: ${e.message}`),
    );
  }, [packId]);

  // Entrée catalogue (catalog/index.packs[]) pour pré-remplir les métadonnées.
  useEffect(() => {
    return onSnapshot(doc(db, 'catalog', 'index'), (snap) => {
      const list = snap.data()?.packs;
      const entry = Array.isArray(list)
        ? list.find((p) => p && p.id === packId)
        : null;
      setCatalogEntry(entry ?? null);
    });
  }, [packId]);

  async function handleDelete(d) {
    const note =
      d.status === 'published'
        ? '(déjà publiée → retirée à la prochaine publication)'
        : '(brouillon → suppression définitive)';
    if (!confirm(`Supprimer la devinette ${d.id} ?\n${note}`)) return;
    try {
      await httpsCallable(functions, 'deleteDevinette')({ packId, deviId: d.id });
    } catch (e) {
      alert(`Erreur suppression : ${e.code || e.name}: ${e.message}`);
    }
  }

  const nextId = useMemo(() => {
    let max = 0;
    for (const d of devis ?? []) {
      const m = /_(\d+)$/.exec(d.id);
      if (m) max = Math.max(max, parseInt(m[1], 10));
    }
    return `${packId}_${String(max + 1).padStart(3, '0')}`;
  }, [devis, packId]);

  async function runValidate() {
    setValidating(true);
    setValidation(null);
    try {
      const call = httpsCallable(functions, 'validatePackDraft');
      const res = await call({ packId });
      setValidation(res.data);
    } catch (e) {
      setValidation({ error: `${e.code || e.name}: ${e.message}` });
    } finally {
      setValidating(false);
    }
  }

  return (
    <>
      <header className="topbar">
        <button className="btn ghost small" onClick={onBack}>
          ← Catalogue
        </button>
        <h2>Pack : {packId}</h2>
        <span className="spacer" />
        <button className="btn ghost small" onClick={() => setMetaOpen(true)}>
          Métadonnées
        </button>
        <button className="btn ghost small" onClick={() => setBulkOpen(true)}>
          Import JSON
        </button>
        <button className="btn ghost small" onClick={runValidate} disabled={validating}>
          {validating ? 'Validation…' : 'Valider le brouillon'}
        </button>
        <button className="btn primary small" onClick={() => setEditing({ __new: true })}>
          + Devinette
        </button>
      </header>

      {error && <p className="error block">Erreur : {error}</p>}

      {validation && (
        <div className="block">
          {validation.error ? (
            <p className="error">{validation.error}</p>
          ) : (
            <div className={validation.valid ? 'success' : 'error'}>
              {validation.valid ? '✅ Brouillon valide' : '❌ Brouillon invalide'}{' '}
              ({validation.total} devinettes · {validation.errors?.length || 0} erreurs ·{' '}
              {validation.warnings?.length || 0} avertissements)
              {(validation.errors || []).slice(0, 20).map((e, i) => (
                <div key={i} className="small">• {e.deviId}: {e.code} — {e.message}</div>
              ))}
              {(validation.warnings || []).slice(0, 20).map((w, i) => (
                <div key={'w' + i} className="small muted">⚠ {w.deviId}: {w.code}</div>
              ))}
            </div>
          )}
        </div>
      )}

      {devis === null && !error && <p className="muted block">Chargement…</p>}
      {devis?.length === 0 && <p className="muted block">Aucune devinette.</p>}

      {devis?.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Réponse</th>
              <th>Énigme (fr)</th>
              <th className="num">Diff.</th>
              <th>Statut</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {devis.map((d) => (
              <tr key={d.id}>
                <td className="mono small">{d.id}</td>
                <td>{d.answer}</td>
                <td className="truncate">{d.riddle?.fr || '—'}</td>
                <td className="num">{d.difficulty}</td>
                <td>
                  <span className={'chip ' + statusClass(d.status)}>{d.status}</span>
                </td>
                <td className="row-actions">
                  <button className="btn ghost small" onClick={() => setEditing(d)}>
                    Éditer
                  </button>
                  <button className="btn danger small" onClick={() => handleDelete(d)}>
                    Supprimer
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {editing && (
        <DevinetteForm
          packId={packId}
          initial={editing.__new ? null : editing}
          newId={nextId}
          onClose={() => setEditing(null)}
        />
      )}
      {bulkOpen && (
        <BulkImport packId={packId} onClose={() => setBulkOpen(false)} />
      )}
      {metaOpen && (
        <MetaForm
          packId={packId}
          entry={catalogEntry}
          onClose={() => setMetaOpen(false)}
        />
      )}
    </>
  );
}

function MetaForm({ packId, entry, onClose }) {
  const [visible, setVisible] = useState(entry?.visible ?? true);
  const [ordering, setOrdering] = useState(entry?.ordering ?? 100);
  const [price, setPrice] = useState(entry?.unlock_cost_cauris ?? 0);
  const [color, setColor] = useState(entry?.theme_color_hex ?? '#888888');
  const [bundled, setBundled] = useState(entry?.bundled ?? false);
  const [freeChoice, setFreeChoice] = useState(entry?.free_choice_eligible ?? false);
  const [minApp, setMinApp] = useState(entry?.min_app_version ?? '0.1.0');
  const [tags, setTags] = useState((entry?.tags ?? []).join(', '));
  const [themeId, setThemeId] = useState(entry?.theme_id ?? '');
  const [motif, setMotif] = useState(entry?.theme_motif ?? '');
  const [tileShape, setTileShape] = useState(entry?.theme_tile_shape ?? '');
  const [overrides, setOverrides] = useState(entry?.theme_overrides ?? {});
  const [name, setName] = useState(entry?.name?.fr ?? '');
  const [description, setDescription] = useState(entry?.description?.fr ?? '');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState(null);

  // Met à jour un rôle d'override ; une valeur vide retire la clé (= pas
  // d'override → le client garde la couleur du preset).
  function setRole(key, value) {
    setOverrides((prev) => {
      const next = { ...prev };
      if (value && value.trim()) next[key] = value.trim();
      else delete next[key];
      return next;
    });
  }

  async function save() {
    setBusy(true);
    setErr(null);
    try {
      const patch = {
        visible,
        ordering: Number(ordering),
        unlock_cost_cauris: Number(price),
        theme_color_hex: color,
        // Skin de pack : preset + overrides couleur (appliqués au runtime
        // par le client, sans release). '' / objet vide = effacé.
        theme_id: themeId || null,
        theme_motif: motif || null,
        theme_tile_shape: tileShape || null,
        theme_overrides: Object.keys(overrides).length ? overrides : null,
        bundled,
        free_choice_eligible: freeChoice,
        min_app_version: minApp.trim(),
        tags: tags.split(',').map((t) => t.trim()).filter(Boolean),
      };
      // Libellés server-driven (catalog/index) — n'envoyer que si renseignés
      // (le schéma serveur rejette une map vide).
      if (name.trim()) patch.name = { fr: name.trim() };
      if (description.trim()) patch.description = { fr: description.trim() };
      await httpsCallable(functions, 'upsertPackMeta')({ packId, patch });
      onClose();
    } catch (e) {
      setErr(`${e.code || e.name}: ${e.message}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Métadonnées — {packId}</h3>
        {!entry && (
          <p className="muted small">
            Pack absent de catalog/index.packs[] — l'enregistrement échouera tant
            qu'il n'y est pas (publier d'abord).
          </p>
        )}
        <label>Nom du pack (FR)</label>
        <input
          value={name}
          placeholder="ex. Les Petits Génies"
          onChange={(e) => setName(e.target.value)}
        />
        <label>Description (FR)</label>
        <input
          value={description}
          placeholder="ex. Mots simples pour les enfants : animaux, fruits…"
          onChange={(e) => setDescription(e.target.value)}
        />
        <p className="muted small">
          Laisser vide = l'app retombe sur la clé i18n bundlée (pack.{packId}.name).
        </p>
        <div className="grid2">
          <label className="check">
            <input type="checkbox" checked={visible} onChange={(e) => setVisible(e.target.checked)} />
            Visible (store)
          </label>
          <label className="check">
            <input type="checkbox" checked={bundled} onChange={(e) => setBundled(e.target.checked)} />
            Bundlé
          </label>
          <label className="check">
            <input type="checkbox" checked={freeChoice} onChange={(e) => setFreeChoice(e.target.checked)} />
            Éligible choix gratuit
          </label>
        </div>
        <div className="grid2">
          <div>
            <label>Ordre</label>
            <input type="number" value={ordering} onChange={(e) => setOrdering(e.target.value)} />
          </div>
          <div>
            <label>Prix (cauris, 0 = gratuit)</label>
            <input type="number" min={0} value={price} onChange={(e) => setPrice(e.target.value)} />
          </div>
        </div>
        <div className="grid2">
          <div>
            <label>Couleur thème (#RRGGBB)</label>
            <input value={color} onChange={(e) => setColor(e.target.value)} />
          </div>
          <div>
            <label>Version min app</label>
            <input value={minApp} onChange={(e) => setMinApp(e.target.value)} />
          </div>
        </div>
        <label>Tags marketing (virgules)</label>
        <input value={tags} onChange={(e) => setTags(e.target.value)} />

        <hr className="sep" />
        <h4 style={{ margin: '8px 0 4px' }}>Skin du pack</h4>
        <p className="muted small" style={{ marginTop: 0 }}>
          Preset = structure bundlée (motif, forme des tuiles). Les overrides
          couleur s’appliquent par-dessus, au runtime, sans build.
        </p>
        <label>Preset de skin</label>
        <select value={themeId} onChange={(e) => setThemeId(e.target.value)}>
          {THEME_PRESETS.map((p) => (
            <option key={p.id} value={p.id}>{p.label}</option>
          ))}
        </select>

        <ThemePreview
          themeId={themeId}
          packId={packId}
          overrides={overrides}
          motif={motif}
          tileShape={tileShape}
        />

        <div className="grid2">
          <div>
            <label>Motif de fond</label>
            <select value={motif} onChange={(e) => setMotif(e.target.value)}>
              {MOTIF_OPTIONS.map((m) => (
                <option key={m.id} value={m.id}>{m.label}</option>
              ))}
            </select>
          </div>
          <div>
            <label>Forme des tuiles</label>
            <select
              value={tileShape}
              onChange={(e) => setTileShape(e.target.value)}
            >
              {TILE_SHAPE_OPTIONS.map((s) => (
                <option key={s.id} value={s.id}>{s.label}</option>
              ))}
            </select>
          </div>
        </div>

        <label style={{ marginTop: 8 }}>
          Overrides couleur (vide = couleur du preset)
        </label>
        <div className="grid2">
          {THEME_ROLES.map((role) => {
            const val = overrides[role.key] ?? '';
            return (
              <div className="theme-role" key={role.key}>
                <span className="muted small">{role.label}</span>
                <div className="row" style={{ gap: 6, alignItems: 'center' }}>
                  <input
                    type="color"
                    value={colorInputValue(val || '#000000')}
                    onChange={(e) => setRole(role.key, e.target.value)}
                    style={{ width: 34, height: 28, padding: 0 }}
                    title={role.key}
                  />
                  <input
                    value={val}
                    placeholder="—"
                    onChange={(e) => setRole(role.key, e.target.value)}
                    style={{ flex: 1 }}
                  />
                  {val && (
                    <button
                      type="button"
                      className="btn ghost"
                      onClick={() => setRole(role.key, '')}
                      title="Retirer l’override"
                    >
                      ×
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>

        {err && <pre className="error">{err}</pre>}
        <div className="row actions">
          <span className="muted small">Bump catalog_version → clients rafraîchissent</span>
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

function statusClass(s) {
  if (s === 'published') return 'green';
  if (s === 'draft') return 'orange';
  return 'grey';
}

function DevinetteForm({ packId, initial, newId, onClose }) {
  const isNew = !initial;
  const [id] = useState(initial?.id ?? newId);
  const [country, setCountry] = useState(initial?.country ?? 'ci');
  const [answer, setAnswer] = useState(initial?.answer ?? '');
  const [riddleFr, setRiddleFr] = useState(initial?.riddle?.fr ?? '');
  const [explFr, setExplFr] = useState(initial?.explanation?.fr ?? '');
  const [difficulty, setDifficulty] = useState(initial?.difficulty ?? 2);
  const [estTime, setEstTime] = useState(initial?.estimated_time_s ?? 30);
  const [tags, setTags] = useState((initial?.tags ?? []).join(', '));
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState(null);

  const pool = lettersPoolFromAnswer(answer);
  const normalized = normalize(answer);
  const answerLen = answer.replace(/\s/g, '').length;
  const answerOk = answerLen >= 4 && answerLen <= 12;

  async function save() {
    setBusy(true);
    setErr(null);
    try {
      const tagList = tags
        .split(',')
        .map((t) => t.trim())
        .filter(Boolean);
      const devinette = {
        id,
        pack: packId,
        country,
        answer, // le serveur upper-case + recalcule normalized/letters_pool
        riddle: { fr: riddleFr.trim() },
        explanation: explFr.trim() ? { fr: explFr.trim() } : {},
        difficulty: Number(difficulty),
        estimated_time_s: Number(estTime),
        tags: tagList,
      };
      const call = httpsCallable(functions, 'upsertDevinette');
      await call({ packId, devinette });
      onClose();
    } catch (e) {
      setErr(`${e.code || e.name}: ${e.message}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>{isNew ? 'Nouvelle devinette' : `Éditer ${id}`}</h3>
        <label>ID</label>
        <input value={id} disabled />
        <div className="grid2">
          <div>
            <label>Pays</label>
            <select value={country} onChange={(e) => setCountry(e.target.value)}>
              {COUNTRIES.map((c) => (
                <option key={c} value={c}>{c}</option>
              ))}
            </select>
          </div>
          <div>
            <label>Difficulté (1–4)</label>
            <input
              type="number" min={1} max={4}
              value={difficulty}
              onChange={(e) => setDifficulty(e.target.value)}
            />
          </div>
        </div>
        <label>Réponse {!answerOk && <span className="error small">(4–12 lettres)</span>}</label>
        <input value={answer} onChange={(e) => setAnswer(e.target.value)} />
        <p className="muted small mono">
          normalisé: {normalized || '—'} · lettres: [{pool.join(',')}]
        </p>
        <label>Énigme (fr)</label>
        <textarea rows={2} value={riddleFr} onChange={(e) => setRiddleFr(e.target.value)} />
        <label>Explication (fr)</label>
        <textarea rows={2} value={explFr} onChange={(e) => setExplFr(e.target.value)} />
        <div className="grid2">
          <div>
            <label>Temps estimé (s)</label>
            <input
              type="number" min={5} max={300}
              value={estTime}
              onChange={(e) => setEstTime(e.target.value)}
            />
          </div>
          <div>
            <label>Tags (séparés par virgule)</label>
            <input value={tags} onChange={(e) => setTags(e.target.value)} />
          </div>
        </div>
        {err && <pre className="error">{err}</pre>}
        <div className="row actions">
          <span className="muted small">Sauvegarde → statut "draft" (à publier ensuite)</span>
          <span className="spacer" />
          <button className="btn ghost" onClick={onClose}>Annuler</button>
          <button className="btn primary" disabled={busy || !answerOk || !riddleFr.trim()} onClick={save}>
            {busy ? 'Sauvegarde…' : 'Enregistrer'}
          </button>
        </div>
      </div>
    </div>
  );
}

function BulkImport({ packId, onClose }) {
  const [text, setText] = useState('');
  const [mode, setMode] = useState('append');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState(null);

  async function run() {
    setBusy(true);
    setResult(null);
    let arr;
    try {
      arr = JSON.parse(text);
      if (!Array.isArray(arr)) throw new Error('Le JSON doit être un tableau []');
    } catch (e) {
      setResult({ error: `JSON invalide : ${e.message}` });
      setBusy(false);
      return;
    }
    try {
      const call = httpsCallable(functions, 'bulkImportDevinettes');
      const res = await call({ packId, mode, devinettes: arr });
      setResult(res.data);
    } catch (e) {
      setResult({ error: `${e.code || e.name}: ${e.message}` });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Import JSON — {packId}</h3>
        <p className="muted small">
          Tableau JSON de devinettes ({'{'}id, answer, riddle, explanation, difficulty, tags…{'}'}).
          answer_normalized / letters_pool sont recalculés serveur.
        </p>
        <label>Mode</label>
        <select value={mode} onChange={(e) => setMode(e.target.value)}>
          <option value="append">append (ajouter)</option>
          <option value="replace">replace (remplace les brouillons)</option>
        </select>
        <label>JSON</label>
        <textarea rows={10} className="mono" value={text} onChange={(e) => setText(e.target.value)} />
        {result && (
          result.error ? (
            <pre className="error">{result.error}</pre>
          ) : (
            <p className="success small">
              ✅ {result.accepted} importées · {result.rejected?.length || 0} rejetées
              {result.rejected?.length > 0 && (
                <span className="error">
                  {' '}— {result.rejected.slice(0, 5).map((r) => `${r.id}: ${r.error}`).join(' | ')}
                </span>
              )}
            </p>
          )
        )}
        <div className="row actions">
          <span className="spacer" />
          <button className="btn ghost" onClick={onClose}>Fermer</button>
          <button className="btn primary" disabled={busy || !text.trim()} onClick={run}>
            {busy ? 'Import…' : 'Importer'}
          </button>
        </div>
      </div>
    </div>
  );
}
