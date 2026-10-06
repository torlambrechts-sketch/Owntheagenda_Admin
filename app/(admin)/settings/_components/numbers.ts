/**
 * The range a setting's number may take («A number» / «Custom», V-SETTINGS-04). The screen and the server
 * action both check it; a setting not named here takes 0 … 1 000 000 000, as count limits always have.
 */
type Bounds = { min: number; max: number; int: boolean }

const BOUNDS: Record<string, Bounds> = {
  // months without engagement before a person is suggested for archiving (marketing-documents.md §8: 6–24)
  list_hygiene: { min: 6, max: 24, int: true },
  // minutes from signup to first send (analytics_activation's target_min)
  activation_target: { min: 1, max: 1_000_000_000, int: true },
  // days ahead a renewal counts (analytics_health casts it to int and adds it to now(): ten years at most)
  renewal_window: { min: 1, max: 3650, int: true },
}

export const numberBounds = (key: string): Bounds => BOUNDS[key] ?? { min: 0, max: 1_000_000_000, int: false }

export const numberOk = (key: string, n: number) => {
  const b = numberBounds(key)
  return Number.isFinite(n) && n >= b.min && n <= b.max && (!b.int || Number.isInteger(n))
}
