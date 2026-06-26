import { useEffect, useMemo, useState } from 'react';
import {
  collection,
  query,
  where,
  orderBy,
  onSnapshot,
} from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from './firebase.js';

const call = (name, data) =>
  httpsCallable(functions, name, { timeout: 120000 })(data).then((r) => r.data);

const STATUS_LABELS = {
  queued: 'En file',
  planning: 'Plan en cours…',
  plan_review: 'Plan à valider',
  plan_approved: 'Plan validé',
  generating: 'Génération…',
  review: 'Revue questions',
  ready: 'Prêt',
  published: 'Publié',
  failed: 'Échec',
  cancelled: 'Annulé',
};

export default function PackCreator() {
  const [jobs, setJobs] = useState(null);
  const [error, setError] = useState(null);
  const [selectedId, setSelectedId] = useState(null);
  const [showCreate, setShowCreate] = useState(false);

  useEffect(() => {
    const q = query(collection(db, 'pack_jobs'), orderBy('createdAt', 'desc'));
    return onSnapshot(
      q,
      (snap) => setJobs(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (e) => setError(`${e.code}: ${e.message}`),
    );
  }, []);

  const selected = useMemo(
    () => jobs?.find((j) => j.id === selectedId) ?? null,
    [jobs, selectedId],
  );

  return (
    <>
      <header className="topbar">
        <h2>Pack Creator</h2>
        <span className="spacer" />
        <button className="btn primary" onClick={() => setShowCreate(true)}>
          Nouveau pack
        </button>
      </header>

      {error && <p className="error block">Accès refusé / erreur : {error}</p>}
      {!error && jobs === null && <p className="muted block">Chargement…</p>}

      <div className="row" style={{ alignItems: 'flex-start', gap: 16 }}>
        <div style={{ flex: '0 0 360px' }}>
          {jobs?.length === 0 && <p className="muted block">Aucun job.</p>}
          {jobs?.map((j) => (
            <JobRow
              key={j.id}
              job={j}
              active={j.id === selectedId}
              onClick={() => setSelectedId(j.id)}
            />
          ))}
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          {selected ? (
            <JobDetail job={selected} />
          ) : (
            <p className="muted block">Sélectionne un job.</p>
          )}
        </div>
      </div>

      {showCreate && <CreateModal onClose={() => setShowCreate(false)} />}
    </>
  );
}

function JobRow({ job, active, onClick }) {
  const p = job.progress ?? {};
  const pct = p.batchesTotal ? Math.round((p.batchesDone / p.batchesTotal) * 100) : 0;
  return (
    <div
      className="card"
      style={{ cursor: 'pointer', borderColor: active ? 'var(--or)' : undefined }}
      onClick={onClick}
    >
      <div className="row">
        <span className={'chip ' + statusClass(job.status)}>
          {STATUS_LABELS[job.status] ?? job.status}
        </span>
        <span className="spacer" />
        <span className="muted small">{p.generated ?? 0}/{p.targetTotal ?? 0}</span>
      </div>
      <p className="question" style={{ marginBottom: 4 }}>{job.topic}</p>
      <div className="muted small">pack: {job.packId}</div>
      {(job.status === 'generating' || job.status === 'review') && (
        <div className="progressbar"><span style={{ width: `${pct}%` }} /></div>
      )}
    </div>
  );
}

function JobDetail({ job }) {
  const [busy, setBusy] = useState(null);

  const run = async (label, fn) => {
    setBusy(label);
    try {
      await fn();
    } catch (e) {
      alert(`${e.code || ''} ${e.message}`);
    } finally {
      setBusy(null);
    }
  };

  const p = job.progress ?? {};
  const usage = job.usage ?? {};

  return (
    <div className="card">
      <div className="row">
        <span className={'chip ' + statusClass(job.status)}>
          {STATUS_LABELS[job.status] ?? job.status}
        </span>
        <span className="spacer" />
        <span className="muted small">
          ~${(usage.estUsd ?? 0).toFixed(2)} · {usage.claudeCalls ?? 0} appels
        </span>
      </div>
      <h3 style={{ margin: '8px 0' }}>{job.topic}</h3>
      <div className="muted small">
        pack: {job.packId} · généré {p.generated ?? 0}/{p.targetTotal ?? 0} ·
        rejetés {p.rejectedAuto ?? 0} · doublons {p.duplicatesDropped ?? 0}
      </div>
      {p.lastError && <p className="error block">Dernière erreur : {p.lastError}</p>}

      <div className="row actions" style={{ marginTop: 12, flexWrap: 'wrap', gap: 8 }}>
        {job.status === 'queued' && (
          <button
            className="btn primary"
            disabled={busy}
            onClick={() => run('plan', () => call('generateResearchPlan', { jobId: job.id }))}
          >
            {busy === 'plan' ? 'Génération du plan…' : 'Générer le plan'}
          </button>
        )}
        {job.status === 'failed' && (
          <button
            className="btn"
            disabled={busy}
            onClick={() => run('retry', () => call('retryPackJob', { jobId: job.id }))}
          >
            Relancer
          </button>
        )}
        {!['published', 'cancelled', 'failed'].includes(job.status) && (
          <button
            className="btn danger"
            disabled={busy}
            onClick={() => {
              if (confirm('Annuler ce job ?')) run('cancel', () => call('cancelPackJob', { jobId: job.id }));
            }}
          >
            Annuler
          </button>
        )}
      </div>

      {(job.status === 'plan_review' || job.status === 'plan_approved') && (
        <PlanEditor job={job} />
      )}

      {['generating', 'review', 'ready', 'published'].includes(job.status) && (
        <CandidateReview job={job} />
      )}
    </div>
  );
}

function PlanEditor({ job }) {
  const [plan, setPlan] = useState(() => normalizePlan(job.plan));
  const [busy, setBusy] = useState(false);

  const total = plan.subThemes.reduce((s, t) => s + (Number(t.targetCount) || 0), 0);
  const diffTotal = ['1', '2', '3', '4'].reduce(
    (s, d) => s + (Number(plan.difficultyDistribution[d]) || 0),
    0,
  );

  const approve = async () => {
    setBusy(true);
    try {
      await call('approveResearchPlan', {
        jobId: job.id,
        plan: {
          subThemes: plan.subThemes.map((t) => ({
            name: t.name,
            targetCount: Number(t.targetCount) || 0,
            tags: t.tags,
          })),
          difficultyDistribution: {
            1: Number(plan.difficultyDistribution['1']) || 0,
            2: Number(plan.difficultyDistribution['2']) || 0,
            3: Number(plan.difficultyDistribution['3']) || 0,
            4: Number(plan.difficultyDistribution['4']) || 0,
          },
          targetTotal: total,
        },
      });
    } catch (e) {
      alert(`${e.code || ''} ${e.message}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div style={{ marginTop: 16 }}>
      <h4>Plan de recherche</h4>
      {job.plan?.rationale && <p className="muted small">{job.plan.rationale}</p>}

      <table className="table">
        <thead>
          <tr><th>Sous-thème</th><th>Cible</th><th>Tags</th></tr>
        </thead>
        <tbody>
          {plan.subThemes.map((t, i) => (
            <tr key={i}>
              <td>
                <input
                  value={t.name}
                  onChange={(e) => updateSub(i, { name: e.target.value })}
                />
              </td>
              <td style={{ width: 80 }}>
                <input
                  type="number"
                  value={t.targetCount}
                  onChange={(e) => updateSub(i, { targetCount: e.target.value })}
                />
              </td>
              <td>
                <input
                  value={t.tags.join(', ')}
                  onChange={(e) =>
                    updateSub(i, {
                      tags: e.target.value.split(',').map((s) => s.trim()).filter(Boolean),
                    })
                  }
                />
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <div className="row" style={{ gap: 8, marginTop: 8 }}>
        {['1', '2', '3', '4'].map((d) => (
          <label key={d} className="muted small">
            Niv. {d}{' '}
            <input
              type="number"
              style={{ width: 60 }}
              value={plan.difficultyDistribution[d]}
              onChange={(e) =>
                setPlan((p) => ({
                  ...p,
                  difficultyDistribution: { ...p.difficultyDistribution, [d]: e.target.value },
                }))
              }
            />
          </label>
        ))}
      </div>

      <div className="muted small" style={{ marginTop: 6 }}>
        Total sous-thèmes : {total} · total difficulté : {diffTotal}
        {total !== diffTotal && <span className="error"> (à équilibrer)</span>}
      </div>

      <button className="btn primary" style={{ marginTop: 10 }} disabled={busy} onClick={approve}>
        {busy ? 'Validation…' : 'Approuver le plan → générer'}
      </button>
    </div>
  );

  function updateSub(i, patch) {
    setPlan((p) => {
      const subThemes = [...p.subThemes];
      subThemes[i] = { ...subThemes[i], ...patch };
      return { ...p, subThemes };
    });
  }
}

function CandidateReview({ job }) {
  const [filter, setFilter] = useState('pending');
  const [cands, setCands] = useState(null);

  useEffect(() => {
    setCands(null);
    const q = query(
      collection(db, 'pack_jobs', job.id, 'candidates'),
      where('reviewStatus', '==', filter),
      orderBy('candId'),
    );
    return onSnapshot(q, (snap) =>
      setCands(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
    );
  }, [job.id, filter]);

  const counts = job.progress ?? {};

  return (
    <div style={{ marginTop: 16 }}>
      <div className="row">
        <h4 style={{ margin: 0 }}>Revue des questions</h4>
        <span className="spacer" />
        <select value={filter} onChange={(e) => setFilter(e.target.value)}>
          <option value="pending">En attente</option>
          <option value="approved">Approuvées</option>
          <option value="rejected">Rejetées</option>
        </select>
        <button
          className="btn primary"
          style={{ marginLeft: 8 }}
          onClick={() => {
            if (confirm(`Publier le pack ${job.packId} ? (valide les drafts approuvés)`))
              call('publishPack', { packId: job.packId })
                .then((r) => alert(`Publié v${r.version} (${r.count} devinettes).`))
                .catch((e) => alert(`${e.code || ''} ${e.message}`));
          }}
        >
          Publier le pack
        </button>
      </div>
      <div className="muted small">
        vérifiées OK : {counts.verified ?? 0} · généré {counts.generated ?? 0}
      </div>

      {cands === null && <p className="muted block">Chargement…</p>}
      {cands?.length === 0 && <p className="muted block">Aucun candidat ({filter}).</p>}

      <div className="cards">
        {cands?.map((c) => (
          <CandidateCard key={c.id} jobId={job.id} cand={c} />
        ))}
      </div>
    </div>
  );
}

function CandidateCard({ jobId, cand }) {
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState(cand);
  const [busy, setBusy] = useState(false);

  const act = async (name, data) => {
    setBusy(true);
    try {
      await call(name, data);
    } catch (e) {
      alert(`${e.code || ''} ${e.message}`);
    } finally {
      setBusy(false);
    }
  };

  const v = cand.verification ?? {};
  return (
    <div className="card">
      <div className="row">
        <span className={'chip ' + verdictClass(v.verdict)}>
          {v.verdict ?? '—'}{v.confidence ? ` ${Math.round(v.confidence * 100)}%` : ''}
        </span>
        <span className="muted small">diff. {cand.difficulty}/4 · {cand.subTheme}</span>
        <span className="spacer" />
        <span className="answer">{cand.answer}</span>
      </div>

      {!editing ? (
        <>
          <p className="question">{cand.riddleFr}</p>
          <p className="muted small">{cand.explanationFr}</p>
        </>
      ) : (
        <div style={{ display: 'grid', gap: 6, marginTop: 8 }}>
          <input value={form.answer} onChange={(e) => setForm({ ...form, answer: e.target.value })} placeholder="Réponse" />
          <input value={form.riddleFr} onChange={(e) => setForm({ ...form, riddleFr: e.target.value })} placeholder="Énigme" />
          <input value={form.explanationFr} onChange={(e) => setForm({ ...form, explanationFr: e.target.value })} placeholder="Explication" />
          <input type="number" min="1" max="4" value={form.difficulty} onChange={(e) => setForm({ ...form, difficulty: Number(e.target.value) })} placeholder="Difficulté" />
        </div>
      )}

      {Array.isArray(v.sources) && v.sources.length > 0 && (
        <div className="muted small" style={{ marginTop: 6 }}>
          Sources :{' '}
          {v.sources.map((s, i) => (
            <a key={i} href={s.url} target="_blank" rel="noreferrer" style={{ marginRight: 8 }}>
              {s.title || s.url}
            </a>
          ))}
        </div>
      )}
      {v.notes && <p className="muted small">Note : {v.notes}</p>}
      {cand.promotedDeviId && <p className="muted small">→ {cand.promotedDeviId}</p>}

      <div className="row actions" style={{ marginTop: 8, gap: 8 }}>
        {!editing ? (
          <button className="btn ghost" disabled={busy} onClick={() => { setForm(cand); setEditing(true); }}>
            Éditer
          </button>
        ) : (
          <>
            <button className="btn ghost" onClick={() => setEditing(false)}>Annuler</button>
            <button
              className="btn"
              disabled={busy}
              onClick={() =>
                act('updateCandidate', {
                  jobId,
                  candId: cand.candId,
                  patch: {
                    answer: form.answer.toUpperCase(),
                    riddleFr: form.riddleFr,
                    explanationFr: form.explanationFr,
                    difficulty: Number(form.difficulty),
                  },
                }).then(() => setEditing(false))
              }
            >
              Enregistrer
            </button>
          </>
        )}
        <span className="spacer" />
        {cand.reviewStatus !== 'rejected' && (
          <button
            className="btn danger"
            disabled={busy}
            onClick={() => act('rejectCandidate', { jobId, candId: cand.candId })}
          >
            Rejeter
          </button>
        )}
        {cand.reviewStatus !== 'approved' && (
          <button
            className="btn primary"
            disabled={busy}
            onClick={() => act('approveCandidate', { jobId, candId: cand.candId })}
          >
            Approuver
          </button>
        )}
      </div>
    </div>
  );
}

function CreateModal({ onClose }) {
  const [packId, setPackId] = useState('');
  const [topic, setTopic] = useState('');
  const [targetTotal, setTargetTotal] = useState(500);
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    setBusy(true);
    try {
      await call('createPackJob', { packId: packId.trim(), topic: topic.trim(), targetTotal: Number(targetTotal) });
      onClose();
    } catch (e) {
      alert(`${e.code || ''} ${e.message}`);
      setBusy(false);
    }
  };

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Nouveau pack</h3>
        <label className="muted small">Identifiant (snake_case)</label>
        <input value={packId} onChange={(e) => setPackId(e.target.value)} placeholder="ex: histoire_ci" />
        <label className="muted small">Sujet / thème</label>
        <input value={topic} onChange={(e) => setTopic(e.target.value)} placeholder="ex: Histoire de la Côte d'Ivoire" />
        <label className="muted small">Nombre de questions</label>
        <input type="number" value={targetTotal} onChange={(e) => setTargetTotal(e.target.value)} />
        <div className="row actions" style={{ marginTop: 12 }}>
          <span className="spacer" />
          <button className="btn ghost" onClick={onClose}>Annuler</button>
          <button className="btn primary" disabled={busy || !packId || !topic} onClick={submit}>
            {busy ? 'Création…' : 'Créer'}
          </button>
        </div>
      </div>
    </div>
  );
}

function normalizePlan(plan) {
  return {
    subThemes: (plan?.subThemes ?? []).map((t) => ({
      name: t.name ?? '',
      targetCount: t.targetCount ?? 0,
      tags: Array.isArray(t.tags) ? t.tags : [],
    })),
    difficultyDistribution: {
      1: plan?.difficultyDistribution?.['1'] ?? 0,
      2: plan?.difficultyDistribution?.['2'] ?? 0,
      3: plan?.difficultyDistribution?.['3'] ?? 0,
      4: plan?.difficultyDistribution?.['4'] ?? 0,
    },
  };
}

function statusClass(status) {
  if (['published', 'ready', 'plan_approved'].includes(status)) return 'green';
  if (['failed', 'cancelled'].includes(status)) return 'red';
  if (['review', 'plan_review'].includes(status)) return 'orange';
  return '';
}

function verdictClass(verdict) {
  if (verdict === 'pass') return 'green';
  if (verdict === 'fail') return 'red';
  return 'orange';
}
