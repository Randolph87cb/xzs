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

export interface AdminQuestionReviewPageRequest {
  subjectId?: number | null
  knowledgePoint?: string | null
  pageIndex: number
  pageSize: number
}

export interface AdminQuestionReviewListItem {
  id: number
  subject_id: number
  question_type: number
  knowledge_point?: string
  title?: string
  analyze?: string
  analysis_review_round?: number
  knowledge_review_round?: number
}

export interface AdminQuestionReviewRecord {
  id: number
  question_id: number
  review_type: 'ANALYSIS' | 'KNOWLEDGE_POINT'
  review_round: number
  before_value?: string
  after_value?: string
  reviewer_id?: number
  reviewer_name?: string
  review_comment?: string
  create_time?: string
}

export interface AdminQuestionReviewDetail extends AdminQuestionReviewListItem {
  correct?: string
  items?: string
  reviewRecords?: AdminQuestionReviewRecord[]
}

export interface AdminKnowledgePointDistributionItem {
  knowledge_point: string
  question_count: number
  reviewed_count: number
  unreviewed_count: number
}

export interface AdminQuestionReviewEditRequest {
  questionId: number
  reviewRound: number
  afterValue: string
  reviewComment?: string
}

export interface AdminQuestionReviewPageResponse {
  list: AdminQuestionReviewListItem[]
  total: number
  pageIndex: number
  pageSize: number
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

export function getAdminQuestionReviewPage(
  request: AdminQuestionReviewPageRequest
): Promise<ApiResponse<AdminQuestionReviewPageResponse>> {
  return post<AdminQuestionReviewPageResponse>('/api/admin/questionReview/page', request)
}

export function getAdminQuestionReview(id: number): Promise<ApiResponse<AdminQuestionReviewDetail>> {
  return post<AdminQuestionReviewDetail>(`/api/admin/questionReview/select/${id}`)
}

export function saveAdminQuestionAnalysisReview(request: AdminQuestionReviewEditRequest): Promise<ApiResponse<void>> {
  return post<void>('/api/admin/questionReview/analysis/edit', request)
}

export function saveAdminQuestionKnowledgeReview(request: AdminQuestionReviewEditRequest): Promise<ApiResponse<void>> {
  return post<void>('/api/admin/questionReview/knowledge/edit', request)
}

export function getAdminKnowledgePointDistribution(
  subjectId: number
): Promise<ApiResponse<AdminKnowledgePointDistributionItem[]>> {
  return post<AdminKnowledgePointDistributionItem[]>(`/api/admin/questionReview/knowledgePointDistribution/${subjectId}`)
}
