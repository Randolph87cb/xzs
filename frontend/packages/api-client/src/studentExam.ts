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
  questionId: number
  content: string | null
  contentArray: string[]
  completed: boolean
  itemOrder: number
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

export function createSmartTrainingPaper(
  request: SmartTrainingCreateRequest
): Promise<ApiResponse<SmartTrainingCreateResponse | number | string>> {
  return post<SmartTrainingCreateResponse | number | string>('/api/student/exam/paper/smartTraining/create', request)
}
