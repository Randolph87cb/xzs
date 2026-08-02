import type { ExamPaperDetail, ExamPaperItem, ExamPaperTitleItem, ExamQuestion } from '@xzs/api-client'

export interface NormalizedExamPaperTitleItem extends Omit<ExamPaperTitleItem, 'paperItems'> {
  paperItems: ExamPaperItem[]
}

export function normalizeExamPaperTitleItems(
  paper: ExamPaperDetail | null | undefined
): NormalizedExamPaperTitleItem[] {
  return (paper?.titleItems ?? []).map((titleItem) => ({
    ...titleItem,
    questionItems: titleItem.questionItems ?? [],
    paperItems: normalizePaperItems(titleItem)
  }))
}

export function flattenExamQuestions(titleItems: NormalizedExamPaperTitleItem[]): ExamQuestion[] {
  return titleItems.flatMap((titleItem) => titleItem.paperItems.flatMap((paperItem) => paperItem.questionItems))
}

export function limitExamPaperItems(
  titleItems: NormalizedExamPaperTitleItem[],
  visiblePaperItemCount: number
): NormalizedExamPaperTitleItem[] {
  let remaining = visiblePaperItemCount

  return titleItems.flatMap((titleItem) => {
    if (remaining <= 0) {
      return []
    }

    const paperItems = titleItem.paperItems.slice(0, remaining)
    remaining -= paperItems.length
    return paperItems.length ? [{ ...titleItem, paperItems }] : []
  })
}

export function findPaperItemNumberByQuestionOrder(
  titleItems: NormalizedExamPaperTitleItem[],
  itemOrder: number
) {
  let paperItemNumber = 0
  for (const titleItem of titleItems) {
    for (const paperItem of titleItem.paperItems) {
      paperItemNumber += 1
      if (paperItem.questionItems.some((question) => question.itemOrder === itemOrder)) {
        return paperItemNumber
      }
    }
  }
  return 0
}

function normalizePaperItems(titleItem: ExamPaperTitleItem): ExamPaperItem[] {
  if (!titleItem.paperItems?.length) {
    return (titleItem.questionItems ?? []).map((question) => ({
      type: 'QUESTION',
      id: question.id,
      itemOrder: question.itemOrder,
      questionItems: [question]
    }))
  }

  return titleItem.paperItems.flatMap((paperItem) => {
    const type = paperItem.type === 'QUESTION_GROUP' ? 'QUESTION_GROUP' : 'QUESTION'
    let questionItems = paperItem.questionItems ?? []

    if (questionItems.length === 0 && type === 'QUESTION') {
      const question = titleItem.questionItems?.find((item) => item.id === paperItem.id)
      questionItems = question ? [question] : []
    }

    if (questionItems.length === 0) {
      return []
    }

    const firstQuestion = questionItems[0]
    return [{
      ...paperItem,
      type,
      title: paperItem.title || firstQuestion?.questionGroupTitle || null,
      questionGroupType: paperItem.questionGroupType ?? firstQuestion?.questionGroupType ?? null,
      questionGroupCode: paperItem.questionGroupCode || firstQuestion?.questionGroupCode || null,
      questionItems
    }]
  })
}
