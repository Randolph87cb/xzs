import { post, type ApiResponse } from './request'

export interface AdminPracticeObservationRequest {
  days?: 7 | 14 | 30
  studentName?: string | null
  classId?: number | null
}

export interface AdminPracticeObservationDay {
  date: string
  questionCount: number
  correctCount: number
  weightedAccuracy?: number | null
}

export interface AdminRecentPractice {
  id: number
  paperName: string
  createTime: string
  questionCount: number
  correctCount: number
  weightedAccuracy?: number | null
}

export interface AdminPracticeObservationStudent {
  id: number
  userName: string
  name: string
  imagePath?: string | null
  classId?: number | null
  className?: string | null
  gradeLevel?: number | null
  directionLabel: string
  questionCount: number
  correctCount: number
  weightedAccuracy?: number | null
  improved?: boolean | null
  attentionText: string
  days: AdminPracticeObservationDay[]
  recentPractices: AdminRecentPractice[]
  weakPointsSupported: boolean
  weakPointsMessage: string
}

export interface AdminPracticeObservationResponse {
  periodStart: string
  periodEnd: string
  dates: string[]
  summary: {
    activeStudentCount: number
    totalQuestionCount: number
    weightedAccuracy?: number | null
    improvedStudentCount: number
  }
  students: AdminPracticeObservationStudent[]
  improvementRule: string
}

export function getAdminPracticeObservation(
  request: AdminPracticeObservationRequest
): Promise<ApiResponse<AdminPracticeObservationResponse>> {
  return post<AdminPracticeObservationResponse>('/api/admin/practiceObservation/index', request)
}
