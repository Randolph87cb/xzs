import { post, type ApiResponse } from './request'

export interface PageRequest {
  pageIndex: number
  pageSize: number
}

export interface PageResponse<T> {
  list: T[]
  total: number
  pageNum: number
  pageSize: number
  pages?: number
}

export interface SubjectItem {
  id: number
  name: string
}

export interface ExamPaperListRequest extends PageRequest {
  subjectId: number
  paperType: number
}

export interface ExamPaperListItem {
  id: number
  name: string
  createTime?: string
  score?: string | number
  suggestTime?: number
  startTime?: string
  endTime?: string
}

export interface QuestionOption {
  id?: number
  prefix: string
  content: string
}

export interface ExamQuestion {
  id: number
  title: string
  questionType: number
  itemOrder: number
  score?: string | number
  difficult?: number
  analyze?: string
  correct?: string
  correctArray?: string[]
  items: QuestionOption[]
}

export interface ExamPaperTitleItem {
  name: string
  questionItems: ExamQuestion[]
}

export interface ExamPaperDetail {
  id: number
  name: string
  score: string | number
  suggestTime: number
  titleItems: ExamPaperTitleItem[]
}

export interface AnswerItem {
  id?: number
  questionId: number
  content: string | null
  contentArray: string[]
  completed: boolean
  itemOrder: number
  doRight?: boolean | null
  score?: string | number | null
  questionScore?: string | number
}

export interface ExamPaperSubmit {
  id: number
  doTime: number
  answerItems: AnswerItem[]
}

export interface ExamRecordItem {
  id: number
  paperName: string
  subjectName: string
  status: number
  createTime: string
  systemScore: string
  userScore: string
  doTime: string
  paperScore: string
  questionCorrect: number
  questionCount: number
}

export interface ExamPaperRead {
  paper: ExamPaperDetail
  answer: ExamPaperSubmit & {
    score: string | number
    answerItems: AnswerItem[]
  }
}

export interface DashboardPaperItem {
  id: number
  name: string
  startTime?: string
  endTime?: string
}

export interface DashboardIndex {
  fixedPaper: DashboardPaperItem[]
  timeLimitPaper: DashboardPaperItem[]
  pushPaper: DashboardPaperItem[]
}

export interface DashboardTaskPaperItem {
  examPaperId: number
  examPaperName: string
  examPaperAnswerId?: number
  status: number | null
}

export interface DashboardTaskItem {
  id: number
  title: string
  paperItems: DashboardTaskPaperItem[]
}

export interface QuestionAnswerListItem {
  id: number
  shortTitle: string
  questionType: number
  subjectName: string
  createTime: string
}

export interface QuestionAnswerDetail {
  questionVM: ExamQuestion
  questionAnswerVM: AnswerItem
}

export interface SmartTrainingCreateRequest {
  subjectId: number
}

export interface SmartTrainingCreateResponse {
  id?: number
  paperId?: number
  examPaperId?: number
}

export function getSubjectList(): Promise<ApiResponse<SubjectItem[]>> {
  return post<SubjectItem[]>('/api/student/education/subject/list')
}

export function getExamPaperPage(request: ExamPaperListRequest): Promise<ApiResponse<PageResponse<ExamPaperListItem>>> {
  return post<PageResponse<ExamPaperListItem>>('/api/student/exam/paper/pageList', request)
}

export function getExamPaperDetail(id: number): Promise<ApiResponse<ExamPaperDetail>> {
  return post<ExamPaperDetail>(`/api/student/exam/paper/select/${id}`)
}

export function submitExamPaperAnswer(payload: ExamPaperSubmit): Promise<ApiResponse<string>> {
  return post<string>('/api/student/exampaper/answer/answerSubmit', payload)
}

export function getExamRecordPage(request: PageRequest): Promise<ApiResponse<PageResponse<ExamRecordItem>>> {
  return post<PageResponse<ExamRecordItem>>('/api/student/exampaper/answer/pageList', request)
}

export function readExamPaperAnswer(id: number): Promise<ApiResponse<ExamPaperRead>> {
  return post<ExamPaperRead>(`/api/student/exampaper/answer/read/${id}`)
}

export function createSmartTrainingPaper(
  request: SmartTrainingCreateRequest
): Promise<ApiResponse<SmartTrainingCreateResponse | number | string>> {
  return post<SmartTrainingCreateResponse | number | string>('/api/student/exam/paper/smartTraining/create', request)
}

export function getDashboardIndex(): Promise<ApiResponse<DashboardIndex>> {
  return post<DashboardIndex>('/api/student/dashboard/index')
}

export function getDashboardTasks(): Promise<ApiResponse<DashboardTaskItem[]>> {
  return post<DashboardTaskItem[]>('/api/student/dashboard/task')
}

export function getQuestionAnswerPage(request: PageRequest): Promise<ApiResponse<PageResponse<QuestionAnswerListItem>>> {
  return post<PageResponse<QuestionAnswerListItem>>('/api/student/question/answer/page', request)
}

export function getQuestionAnswerDetail(id: number): Promise<ApiResponse<QuestionAnswerDetail>> {
  return post<QuestionAnswerDetail>(`/api/student/question/answer/select/${id}`)
}
