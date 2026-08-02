import { post, type ApiResponse } from './request'
import type { AdminPageResponse } from './adminUser'
import type { AdminQuestionEditModel } from './adminQuestion'

export type AdminQuestionGroupType = 1 | 2

export interface AdminQuestionGroupPageRequest {
  id?: number | null
  subjectId?: number | null
  groupType?: AdminQuestionGroupType | null
  knowledgePoint?: string | null
  status?: number | null
  pageIndex: number
  pageSize: number
}

export interface AdminQuestionGroupEditModel {
  id?: number | null
  groupType: AdminQuestionGroupType
  subjectId: number
  gradeLevel?: number | null
  difficult: number
  knowledgePoint: string
  title: string
  groupCode?: string | null
  importBatch?: string | null
  importSource?: string | null
  importParentOrder?: number | null
  status?: number | null
  questionItems: AdminQuestionEditModel[]
  createTime?: string
  questionCount?: number
  totalScore?: string
}

export function getAdminQuestionGroupPage(
  request: AdminQuestionGroupPageRequest
): Promise<ApiResponse<AdminPageResponse<AdminQuestionGroupEditModel>>> {
  return post<AdminPageResponse<AdminQuestionGroupEditModel>>('/api/admin/question/group/page', request)
}

export function getAdminQuestionGroup(id: number): Promise<ApiResponse<AdminQuestionGroupEditModel>> {
  return post<AdminQuestionGroupEditModel>(`/api/admin/question/group/select/${id}`)
}

export function saveAdminQuestionGroup(
  request: AdminQuestionGroupEditModel
): Promise<ApiResponse<AdminQuestionGroupEditModel>> {
  return post<AdminQuestionGroupEditModel>('/api/admin/question/group/edit', request)
}

export function deleteAdminQuestionGroup(id: number): Promise<ApiResponse<void>> {
  return post<void>(`/api/admin/question/group/delete/${id}`)
}
