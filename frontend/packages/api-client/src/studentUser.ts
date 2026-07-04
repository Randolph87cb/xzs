import { post, type ApiResponse } from './request'

export interface StudentUserInfo {
  id?: number
  userName: string
  realName?: string
  imagePath?: string
}

export function getCurrentStudentUser(): Promise<ApiResponse<StudentUserInfo>> {
  return post<StudentUserInfo>('/api/student/user/current')
}

export function getStudentMessageCount(): Promise<ApiResponse<number>> {
  return post<number>('/api/student/user/message/unreadCount')
}
