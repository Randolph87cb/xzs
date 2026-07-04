export function formatSeconds(totalSeconds: number) {
  const safeSeconds = Math.max(0, Math.floor(totalSeconds))
  const hours = Math.floor(safeSeconds / 3600)
  const minutes = Math.floor((safeSeconds % 3600) / 60)
  const seconds = safeSeconds % 60

  return [hours, minutes, seconds].map((item) => item.toString().padStart(2, '0')).join(':')
}

export function formatExamAnswerStatus(status: number) {
  if (status === 1) {
    return '待批改'
  }

  if (status === 2) {
    return '完成'
  }

  return '未知'
}

export function formatExamAnswerStatusTag(status: number) {
  if (status === 1) {
    return 'warning'
  }

  if (status === 2) {
    return 'success'
  }

  return 'info'
}
