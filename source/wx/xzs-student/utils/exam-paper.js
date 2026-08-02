const normalizeExamPaper = paper => {
  if (!paper) {
    return paper
  }

  return Object.assign({}, paper, {
    titleItems: (paper.titleItems || []).map(titleItem => {
      let paperItems = titleItem.paperItems
      if (!paperItems || paperItems.length === 0) {
        paperItems = (titleItem.questionItems || []).map(question => ({
          type: 'QUESTION',
          id: question.id,
          itemOrder: question.itemOrder,
          questionItems: [question]
        }))
      } else {
        paperItems = paperItems.map(paperItem => {
          const type = paperItem.type === 'QUESTION_GROUP' ? 'QUESTION_GROUP' : 'QUESTION'
          let questionItems = paperItem.questionItems || []
          if (questionItems.length === 0 && type === 'QUESTION') {
            const question = (titleItem.questionItems || []).find(item => item.id === paperItem.id)
            questionItems = question ? [question] : []
          }
          const firstQuestion = questionItems[0] || {}
          return Object.assign({}, paperItem, {
            type,
            title: paperItem.title || firstQuestion.questionGroupTitle || '',
            questionGroupType: paperItem.questionGroupType || firstQuestion.questionGroupType || null,
            questionGroupCode: paperItem.questionGroupCode || firstQuestion.questionGroupCode || '',
            groupTypeText: (paperItem.questionGroupType || firstQuestion.questionGroupType) === 2 ? '程序填空题' : '程序阅读题',
            questionItems
          })
        }).filter(paperItem => paperItem.questionItems.length > 0)
      }
      return Object.assign({}, titleItem, { paperItems })
    })
  })
}

const mapAnswerItemsByOrder = answerItems => {
  const result = []
  ;(answerItems || []).forEach(item => {
    result[item.itemOrder] = item
  })
  return result
}

module.exports = {
  normalizeExamPaper,
  mapAnswerItemsByOrder
}
