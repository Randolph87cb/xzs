import { post, type ApiResponse } from './request'
import type { AdminPageResponse } from './adminUser'

export interface AdminQuestionPageRequest {
  id?: number | null
  level?: number | null
  subjectId?: number | null
  questionType?: number | null
  knowledgePoint?: string | null
  pageIndex: number
  pageSize: number
}

export interface AdminQuestionListItem {
  id: number
  questionType: number
  subjectId: number
  score: string
  difficult: number
  knowledgePoint?: string
  shortTitle?: string
  createTime?: string
}

export interface AdminQuestionEditItem {
  prefix: string
  content: string
  score?: string
  itemUuid?: string
}

export interface AdminQuestionEditModel {
  id?: number | null
  questionType: number
  subjectId: number
  title: string
  gradeLevel?: number | null
  items: AdminQuestionEditItem[]
  analyze: string
  correctArray?: string[]
  correct?: string
  score: string
  difficult: number
  knowledgePoint: string
  itemOrder?: number | null
}

export function getAdminQuestionPage(
  request: AdminQuestionPageRequest
): Promise<ApiResponse<AdminPageResponse<AdminQuestionListItem>>> {
  return post<AdminPageResponse<AdminQuestionListItem>>('/api/admin/question/page', request)
}

export function getAdminQuestion(id: number): Promise<ApiResponse<AdminQuestionEditModel>> {
  return post<AdminQuestionEditModel>(`/api/admin/question/select/${id}`)
}

export function saveAdminQuestion(request: AdminQuestionEditModel): Promise<ApiResponse<void>> {
  return post<void>('/api/admin/question/edit', request)
}

export function deleteAdminQuestion(id: number): Promise<ApiResponse<void>> {
  return post<void>(`/api/admin/question/delete/${id}`)
}
