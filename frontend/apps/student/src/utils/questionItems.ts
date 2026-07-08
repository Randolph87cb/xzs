import type { QuestionOption } from '@xzs/api-client'

export function dedupeQuestionItemsByPrefix(items: QuestionOption[]) {
  const seenPrefixes = new Set<string>()

  return items.filter((item) => {
    if (seenPrefixes.has(item.prefix)) {
      return false
    }

    seenPrefixes.add(item.prefix)
    return true
  })
}
