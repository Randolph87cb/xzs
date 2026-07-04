import { post, type ApiResponse } from './request'

export interface AdminDashboardIndex {
  examPaperCount: number
  questionCount: number
  doExamPaperCount: number
  doQuestionCount: number
  mothDayText: string[]
  mothDayUserActionValue: number[]
  mothDayDoExamQuestionValue: number[]
}

export function getAdminDashboardIndex(): Promise<ApiResponse<AdminDashboardIndex>> {
  return post<AdminDashboardIndex>('/api/admin/dashboard/index')
}
