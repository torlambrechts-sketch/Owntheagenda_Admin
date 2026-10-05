'use client'

import { useState, useTransition } from 'react'
import { useTranslations } from 'next-intl'
import { testConnection, type TestResult } from './actions'

export function TestButton() {
  const t = useTranslations('status')
  const [result, setResult] = useState<TestResult>(null)
  const [pending, start] = useTransition()
  return (
    <div className="flex flex-col items-start gap-2">
      <button
        type="button"
        disabled={pending}
        onClick={() => start(async () => setResult(await testConnection()))}
        className="rounded-md border border-neutral-900 px-3 py-1.5 text-sm font-semibold focus:outline-none focus-visible:ring-2 focus-visible:ring-neutral-900 disabled:opacity-60"
      >
        {t('test')}
      </button>
      {result ? (
        <p role="status" className={`text-sm ${result.ok ? 'text-green-800' : 'text-red-700'}`}>
          {result.ok ? t('testOk', { count: result.count }) : t('testFailed', { error: result.error })}
        </p>
      ) : null}
    </div>
  )
}
