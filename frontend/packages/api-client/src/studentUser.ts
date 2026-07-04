import { post, type ApiResponse } from './request'

export interface StudentUserInfo {
  id?: number
  userName: string
  realName?: string
  age?: number
  sex?: number
  birthDay?: string
  phone?: string
  createTime?: string
  imagePath?: string
}

export interface UserEventLog {
  id: number
  content: string
  createTime: string
}

export interface StudentMessage {
  id: number
  title: string
  content: string
  sendUserName: string
  createTime: string
  readed: boolean
}

export interface StudentMessagePageRequest {
  pageIndex: number
  pageSize: number
}

export interface StudentMessagePageResponse<T> {
  list: T[]
  total: number
  pageNum: number
  pageSize: number
}

export function getCurrentStudentUser(): Promise<ApiResponse<StudentUserInfo>> {
  return post<StudentUserInfo>('/api/student/user/current')
}

export function getStudentMessageCount(): Promise<ApiResponse<number>> {
  return post<number>('/api/student/user/message/unreadCount')
}

export function getStudentUserEvents(): Promise<ApiResponse<UserEventLog[]>> {
  return post<UserEventLog[]>('/api/student/user/log')
}

export function getStudentMessagePage(
  request: StudentMessagePageRequest
): Promise<ApiResponse<StudentMessagePageResponse<StudentMessage>>> {
  return post<StudentMessagePageResponse<StudentMessage>>('/api/student/user/message/page', request)
}

export function markStudentMessageRead(id: number): Promise<ApiResponse<void>> {
  return post<void>(`/api/student/user/message/read/${id}`)
}
