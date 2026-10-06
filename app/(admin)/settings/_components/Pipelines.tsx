'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { Pipeline, Setting } from '@/lib/data/settings'
import type { NumberFormat } from '@/lib/format'
import { deleteStage, reorderStages, savePipeline, saveStage } from '../actions'
import { k, useRun } from './kit'
import { RuleCard } from './Rules'

type Stage = Pipeline['stages'][number]
const COLS = '[grid-template-columns:50px_minmax(0,1.5fr)_120px_140px_130px]'

/**
 * Pipelines and stages (Settings.dc.html, v.pipelines): pipeline chips, the stage table, add and delete with a
 * target; under them the register's pipeline rules in the Rules row style (V-SETTINGS-38).
 */
export function Pipelines({ pipelines, groups, canEdit, rules, nf, canEditRules }: {
  pipelines: Pipeline[] | null
  groups: { id: string; name: string }[]
  canEdit: boolean
  rules: Setting[]
  nf: NumberFormat
  canEditRules: boolean
}) {
  const t = useTranslations('settings')
  const { run, pending } = useRun()
  const [pl, setPl] = useState<string | null>(pipelines?.[0]?.id ?? null)
  const [adding, setAdding] = useState(false)
  const [name, setName] = useState('')

  const ruleCard = rules.length ? (
    <>
      {!canEditRules && canEdit ? (
        <div className="px-1 text-12 text-muted">{t('readOnly', { right: t('perms.cell', { action: t('perms.actions.configure'), scope: t('perms.scopes.global') }) })}</div>
      ) : null}
      <RuleCard title={t('rules.groups.pipelines')} items={rules} nf={nf} canEdit={canEditRules} />
    </>
  ) : null

  if (!pipelines) return (
    <>
      <div className={`${k.card} px-[18px] py-4 text-12.5 text-muted`}>{t('unavailable')}</div>
      {ruleCard}
    </>
  )
  const cur = pipelines.find((p) => p.id === pl) ?? pipelines[0] ?? null
  const vis = cur?.visibility_group_ids?.length ? cur.visibility_group_ids.map((id) => groups.find((g) => g.id === id)?.name ?? '—').join(', ') : t('pipelines.everyone')

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-[6px]">
        {pipelines.map((p) => (
          <button key={p.id} type="button" aria-pressed={cur?.id === p.id} onClick={() => setPl(p.id)} className={k.chip(cur?.id === p.id)}>
            {p.name}
          </button>
        ))}
        {canEdit && !adding ? (
          <button type="button" onClick={() => setAdding(true)} className={k.dashedChip}>
            {t('pipelines.add')}
          </button>
        ) : null}
        {adding ? (
          <form
            className="flex items-center gap-1"
            onSubmit={(e) => {
              e.preventDefault()
              const n = name.trim()
              if (!n) return
              run(() => savePipeline({ id: null, name: n }), (r) => {
                setPl(r.id)
                setAdding(false)
                setName('')
                return t('pipelines.added')
              })
            }}
          >
            <input autoFocus aria-label={t('pipelines.addName')} placeholder={t('pipelines.addName')} value={name} maxLength={80} onChange={(e) => setName(e.target.value)} className="h-[30px] rounded-999 border border-line-strong bg-canvas px-3 text-12 text-ink" />
            <button type="submit" disabled={pending || !name.trim()} className={k.dashedChip}>{t('pipelines.addSubmit')}</button>
            <button type="button" onClick={() => setAdding(false)} className="cursor-pointer border-none bg-transparent px-2 text-12 text-muted">{t('pipelines.cancel')}</button>
          </form>
        ) : null}
        <span className="flex-1" />
        {cur ? <span className="text-12 text-muted">{t('pipelines.visibleTo', { who: vis })}</span> : null}
      </div>
      {!canEdit ? <div className="px-1 text-12 text-muted">{t('readOnly', { right: t('rights.configure') })}</div> : null}
      {cur ? <StageTable key={cur.id} pipeline={cur} canEdit={canEdit} /> : <div className={`${k.card} px-[18px] py-4 text-12.5 text-muted`}>{t('pipelines.empty')}</div>}
      {ruleCard}
    </div>
  )
}

function StageTable({ pipeline, canEdit }: { pipeline: Pipeline; canEdit: boolean }) {
  const t = useTranslations('settings.pipelines')
  const { run, pending } = useRun()
  const [deleting, setDeleting] = useState<string | null>(null)
  const stages = pipeline.stages
  const move = (i: number, dir: -1 | 1) => {
    const j = i + dir
    if (j < 0 || j >= stages.length) return
    const ids = stages.map((s) => s.id)
    ;[ids[i], ids[j]] = [ids[j]!, ids[i]!]
    run(() => reorderStages({ pipeline: pipeline.id, ids }), () => t('reordered'))
  }
  const box = 'h-[22px] w-[22px] cursor-pointer rounded-6 border border-line bg-transparent p-0 text-10 text-ink disabled:cursor-default disabled:opacity-40'
  return (
    <div className={`${k.card} overflow-x-auto`}>
      <div className={`grid min-w-[620px] gap-[10px] border-b border-line px-4 py-[9px] ${k.colHead} ${COLS}`}>
        <span>{t('cols.order')}</span>
        <span>{t('cols.stage')}</span>
        <span>{t('cols.probability')}</span>
        <span>{t('cols.rotting')}</span>
        <span />
      </div>
      {stages.map((s, i) => (
        <div key={s.id}>
          <div className={`grid min-w-[620px] items-center gap-[10px] border-b border-line px-4 py-2 text-12.5 ${COLS}`}>
            <span className="flex gap-[2px]">
              <button type="button" aria-label={t('up', { name: s.name })} disabled={!canEdit || pending || i === 0} onClick={() => move(i, -1)} className={box}>▲</button>
              <button type="button" aria-label={t('down', { name: s.name })} disabled={!canEdit || pending || i === stages.length - 1} onClick={() => move(i, 1)} className={box}>▼</button>
            </span>
            <StageInputs key={`${s.id}-${s.name}-${s.probability}-${s.rot_days}`} stage={s} pipeline={pipeline.id} canEdit={canEdit} />
            <button
              type="button"
              disabled={!canEdit || pending || stages.length < 2}
              title={stages.length < 2 ? t('deleteLast') : undefined}
              onClick={() => setDeleting(deleting === s.id ? null : s.id)}
              className="h-7 cursor-pointer rounded-9 border border-coral bg-transparent text-12 font-semibold text-rust disabled:cursor-default disabled:opacity-50"
            >
              {t('delete')}
            </button>
          </div>
          {deleting === s.id ? <DeleteStage stage={s} others={stages.filter((x) => x.id !== s.id)} onDone={() => setDeleting(null)} /> : null}
        </div>
      ))}
      {canEdit ? (
        <div className="px-4 py-[10px]">
          <button
            type="button"
            disabled={pending}
            onClick={() => run(() => saveStage({ id: null, pipeline: pipeline.id, values: { name: t('newStage'), probability: 50 } }))}
            className={k.dashed}
          >
            {t('addStage')}
          </button>
        </div>
      ) : null}
    </div>
  )
}

/** Name, probability and rotting threshold: saved when the field is left, as the design's inputs change in place. */
function StageInputs({ stage, pipeline, canEdit }: { stage: Stage; pipeline: string; canEdit: boolean }) {
  const t = useTranslations('settings.pipelines')
  const { run } = useRun()
  const [name, setName] = useState(stage.name)
  const [prob, setProb] = useState(String(stage.probability))
  const [rot, setRot] = useState(stage.rot_days === null ? '' : String(stage.rot_days))
  const save = (values: { name?: string; probability?: number; rot_days?: number | null }) => run(() => saveStage({ id: stage.id, pipeline, values }), () => t('saved'))
  const inp = 'h-8 rounded-9 border border-line bg-canvas text-12.5 text-ink'
  return (
    <>
      <input
        aria-label={t('stageName')}
        value={name}
        maxLength={60}
        disabled={!canEdit}
        onChange={(e) => setName(e.target.value)}
        onBlur={() => (name.trim() && name.trim() !== stage.name ? save({ name: name.trim() }) : setName(stage.name))}
        className={`${inp} min-w-0 px-[9px] font-semibold`}
      />
      <span className="flex items-center gap-1">
        <input
          aria-label={t('probability', { name: stage.name })}
          inputMode="numeric"
          value={prob}
          disabled={!canEdit}
          onChange={(e) => setProb(e.target.value.replace(/[^0-9]/g, '').slice(0, 3))}
          onBlur={() => {
            const n = Math.max(0, Math.min(100, parseInt(prob, 10) || 0))
            setProb(String(n))
            if (n !== stage.probability) save({ probability: n })
          }}
          className={`${inp} w-14 px-2`}
        />
        %
      </span>
      <span className="flex items-center gap-1">
        <input
          aria-label={t('rotting', { name: stage.name })}
          inputMode="numeric"
          value={rot}
          disabled={!canEdit}
          onChange={(e) => setRot(e.target.value.replace(/[^0-9]/g, '').slice(0, 4))}
          onBlur={() => {
            const n = rot === '' ? null : Math.max(1, parseInt(rot, 10) || 1)
            setRot(n === null ? '' : String(n))
            if (n !== stage.rot_days) save({ rot_days: n })
          }}
          className={`${inp} w-14 px-2`}
        />
        {t('days')}
      </span>
    </>
  )
}

/** Deleting a stage asks where its deals go (PIP-02); the toast states the count the database moved. */
function DeleteStage({ stage, others, onDone }: { stage: Stage; others: Stage[]; onDone: () => void }) {
  const t = useTranslations('settings.pipelines')
  const { run, pending } = useRun()
  const [target, setTarget] = useState(others[0]?.id ?? '')
  return (
    <form
      className="flex min-w-[620px] flex-wrap items-center gap-2 border-b border-line bg-canvas px-4 py-[10px] text-12.5"
      onSubmit={(e) => {
        e.preventDefault()
        if (!target) return
        const name = others.find((o) => o.id === target)?.name ?? ''
        run(() => deleteStage({ stage: stage.id, target }), (r) => {
          onDone()
          return t('deleted', { count: r.moved, target: name })
        })
      }}
    >
      <label className="flex flex-wrap items-center gap-2">
        {t('deleteTitle', { name: stage.name, count: stage.open_deals })}
        <select value={target} onChange={(e) => setTarget(e.target.value)} className="h-[30px] rounded-8 border border-line bg-surface text-12 text-ink">
          {others.map((o) => (
            <option key={o.id} value={o.id}>{o.name}</option>
          ))}
        </select>
      </label>
      <button type="submit" disabled={pending || !target} className="h-7 cursor-pointer rounded-9 border border-coral bg-transparent px-3 text-12 font-semibold text-rust disabled:opacity-50">
        {t('deleteConfirm')}
      </button>
      <button type="button" onClick={onDone} className="cursor-pointer border-none bg-transparent px-2 text-12 text-muted">
        {t('cancel')}
      </button>
    </form>
  )
}
