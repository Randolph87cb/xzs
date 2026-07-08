import { post, type ApiResponse } from './request'
import type { AdminPageResponse, AdminUserListItem } from './adminUser'
import type { AdminQuestionEditModel } from './adminQuestion'

export interface AdminMessagePageRequest {
  sendUserName?: string | null
  pageIndex: number
  pageSize: number
}

export interface AdminMessageListItem {
  id: number
  title: string
  content: string
  sendUserName?: string
  receives?: string
  readCount?: number
  receiveUserCount?: number
  createTime?: string
}

export interface AdminMessageSendRequest {
  title: string
  content: string
  receiveUserIds: number[]
}

export interface AdminUserOption {
  name: string
  value: number
}

export interface AdminAnswerPageRequest {
  subjectId?: number | null
  pageIndex: number
  pageSize: number
}

export interface AdminAnswerListItem {
  id: number
  paperName: string
  userName: string
  userScore: number
  paperScore: number
  questionCorrect: number
  questionCount: number
  doTime?: string
  createTime?: string
}

export interface AdminUserEventPageRequest {
  userId?: number | null
  userName?: string | null
  pageIndex: number
  pageSize: number
}

export interface AdminUserEventListItem {
  id: number
  userName: string
  realName?: string
  content: string
  createTime?: string
}

export interface AdminUserEditModel extends Omit<AdminUserListItem, 'id'> {
  id?: number | null
  password?: string
  role: number
  age?: number | string
  birthDay?: string | null
  userLevel?: number
}

export interface AdminSubjectEditModel {
  id?: number | null
  name: string
  level: number
  levelName?: string
}

export interface AdminExamPaperPageRequest {
  id?: number | null
  subjectId?: number | null
  level?: number | null
  paperType?: number | null
  taskExamId?: number | null
  pageIndex: number
  pageSize: number
}

export interface AdminExamPaperListItem {
  id: number
  name: string
  questionCount?: number
  score?: number
  createTime?: string
  subjectId?: number
  paperType?: number
}

export interface AdminExamPaperTitleItem {
  name: string
  questionItems: AdminQuestionEditModel[]
}

export interface AdminExamPaperEditModel {
  id?: number | null
  level: number
  subjectId: number | null
  paperType: number
  limitDateTime: string[]
  name: string
  suggestTime: number | null
  titleItems: AdminExamPaperTitleItem[]
  score?: string
}

export interface AdminTaskPageRequest {
  pageIndex: number
  pageSize: number
}

export interface AdminTaskListItem {
  id: number
  title: string
  gradeLevel?: number
  createUserName?: string
  createTime?: string
}

export interface AdminTaskEditModel {
  id?: number | null
  gradeLevel: number
  title: string
  paperItems: AdminExamPaperListItem[]
}

export interface AdminSmartTrainingRule {
  knowledgePoint: string
  minCount: number
  maxCount: number
  weight: number
  enabled: boolean
  questionCount?: number
}

export interface AdminSmartTrainingConfig {
  id?: number | null
  subjectId: number | null
  questionCount: number
  rules: AdminSmartTrainingRule[]
}

export interface AdminQuestionCorrectionPageRequest {
  reviewStatus?: string | null
  pageIndex: number
  pageSize: number
}

export interface AdminQuestionCorrectionItem {
  id: number
  user_id: number
  user_name?: string
  real_name?: string
  question_id: number
  customer_answer_id: number
  title?: string
  student_wrong_reason?: string
  student_correct_thinking?: string
  reviewed_wrong_reason?: string
  reviewed_correct_thinking?: string
  review_status?: 'SUBMITTED' | 'REVIEWED_ONCE' | 'REVIEWED_TWICE'
  reviewer_name?: string
  review_comment?: string
  submit_time?: string
  review_time?: string
  reviewRecords?: AdminQuestionCorrectionReviewRecord[]
}

export interface AdminQuestionCorrectionReviewRecord {
  id: number
  correction_id: number
  review_round: number
  after_wrong_reason?: string
  after_correct_thinking?: string
  reviewer_name?: string
  review_comment?: string
  create_time?: string
}

export interface AdminQuestionCorrectionPageResponse {
  list: AdminQuestionCorrectionItem[]
  total: number
  pageIndex: number
  pageSize: number
}

export interface AdminQuestionCorrectionReviewRequest {
  id: number
  reviewRound: number
  reviewedWrongReason: string
  reviewedCorrectThinking: string
  reviewComment?: string
}

export interface AdminUserProfileUpdate {
  realName?: string
  phone?: string
  age?: number | string
  sex?: number | null
  birthDay?: string | null
}

export function getAdminMessagePage(
  request: AdminMessagePageRequest
): Promise<ApiResponse<AdminPageResponse<AdminMessageListItem>>> {
  return post<AdminPageResponse<AdminMessageListItem>>('/api/admin/message/page', request)
}

export function sendAdminMessage(request: AdminMessageSendRequest): Promise<ApiResponse<void>> {
  return post<void>('/api/admin/message/send', request)
}

export function selectAdminUsersByName(query: string): Promise<ApiResponse<AdminUserOption[]>> {
  return post<AdminUserOption[]>('/api/admin/user/selectByUserName', query)
}

export function getAdminAnswerPage(
  request: AdminAnswerPageRequest
): Promise<ApiResponse<AdminPageResponse<AdminAnswerListItem>>> {
  return post<AdminPageResponse<AdminAnswerListItem>>('/api/admin/examPaperAnswer/page', request)
}

export function getAdminUserEventPage(
  request: AdminUserEventPageRequest
): Promise<ApiResponse<AdminPageResponse<AdminUserEventListItem>>> {
  return post<AdminPageResponse<AdminUserEventListItem>>('/api/admin/user/event/page/list', request)
}

export function getAdminUser(id: number): Promise<ApiResponse<AdminUserEditModel>> {
  return post<AdminUserEditModel>(`/api/admin/user/select/${id}`)
}

export function saveAdminUser(request: AdminUserEditModel): Promise<ApiResponse<void>> {
  return post<void>('/api/admin/user/edit', request)
}

export function changeAdminUserStatus(id: number): Promise<ApiResponse<number>> {
  return post<number>(`/api/admin/user/changeStatus/${id}`)
}

export function deleteAdminUser(id: number): Promise<ApiResponse<void>> {
  return post<void>(`/api/admin/user/delete/${id}`)
}

export function getAdminSubject(id: number): Promise<ApiResponse<AdminSubjectEditModel>> {
  return post<AdminSubjectEditModel>(`/api/admin/education/subject/select/${id}`)
}

export function saveAdminSubject(request: AdminSubjectEditModel): Promise<ApiResponse<void>> {
  return post<void>('/api/admin/education/subject/edit', request)
}

export function deleteAdminSubject(id: number): Promise<ApiResponse<void>> {
  return post<void>(`/api/admin/education/subject/delete/${id}`)
}

export function getAdminExamPaperPage(
  request: AdminExamPaperPageRequest
): Promise<ApiResponse<AdminPageResponse<AdminExamPaperListItem>>> {
  return post<AdminPageResponse<AdminExamPaperListItem>>('/api/admin/exam/paper/page', request)
}

export function getAdminTaskExamPaperPage(
  request: AdminExamPaperPageRequest
): Promise<ApiResponse<AdminPageResponse<AdminExamPaperListItem>>> {
  return post<AdminPageResponse<AdminExamPaperListItem>>('/api/admin/exam/paper/taskExamPage', request)
}

export function getAdminExamPaper(id: number): Promise<ApiResponse<AdminExamPaperEditModel>> {
  return post<AdminExamPaperEditModel>(`/api/admin/exam/paper/select/${id}`)
}

export function saveAdminExamPaper(request: AdminExamPaperEditModel): Promise<ApiResponse<AdminExamPaperEditModel>> {
  return post<AdminExamPaperEditModel>('/api/admin/exam/paper/edit', request)
}

export function deleteAdminExamPaper(id: number): Promise<ApiResponse<void>> {
  return post<void>(`/api/admin/exam/paper/delete/${id}`)
}

export function getAdminTaskPage(
  request: AdminTaskPageRequest
): Promise<ApiResponse<AdminPageResponse<AdminTaskListItem>>> {
  return post<AdminPageResponse<AdminTaskListItem>>('/api/admin/task/page', request)
}

export function getAdminTask(id: number): Promise<ApiResponse<AdminTaskEditModel>> {
  return post<AdminTaskEditModel>(`/api/admin/task/select/${id}`)
}

export function saveAdminTask(request: AdminTaskEditModel): Promise<ApiResponse<AdminTaskEditModel>> {
  return post<AdminTaskEditModel>('/api/admin/task/edit', request)
}

export function deleteAdminTask(id: number): Promise<ApiResponse<void>> {
  return post<void>(`/api/admin/task/delete/${id}`)
}

export function getAdminSmartTrainingConfigList(): Promise<ApiResponse<AdminSmartTrainingConfig[]>> {
  return post<AdminSmartTrainingConfig[]>('/api/admin/smartTraining/config/list', {})
}

export function getAdminSmartTrainingConfig(subjectId: number): Promise<ApiResponse<AdminSmartTrainingConfig>> {
  return post<AdminSmartTrainingConfig>(`/api/admin/smartTraining/config/select/${subjectId}`)
}

export function saveAdminSmartTrainingConfig(request: AdminSmartTrainingConfig): Promise<ApiResponse<void>> {
  return post<void>('/api/admin/smartTraining/config/edit', request)
}

export function getAdminSmartTrainingKnowledgePoints(subjectId: number): Promise<ApiResponse<string[]>> {
  return post<string[]>(`/api/admin/smartTraining/knowledgePoints/${subjectId}`)
}

export function getAdminQuestionCorrectionPage(
  request: AdminQuestionCorrectionPageRequest
): Promise<ApiResponse<AdminQuestionCorrectionPageResponse>> {
  return post<AdminQuestionCorrectionPageResponse>('/api/admin/questionCorrection/page', request)
}

export function getAdminQuestionCorrection(id: number): Promise<ApiResponse<AdminQuestionCorrectionItem>> {
  return post<AdminQuestionCorrectionItem>(`/api/admin/questionCorrection/select/${id}`)
}

export function saveAdminQuestionCorrectionReview(
  request: AdminQuestionCorrectionReviewRequest
): Promise<ApiResponse<void>> {
  return post<void>('/api/admin/questionCorrection/review/edit', request)
}

export function updateCurrentAdminUser(request: AdminUserProfileUpdate): Promise<ApiResponse<void>> {
  return post<void>('/api/admin/user/update', request)
}
