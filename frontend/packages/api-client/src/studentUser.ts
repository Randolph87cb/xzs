import { post, type ApiResponse } from './request'

export interface StudentUserInfo {
  id?: number
  userName: string
  nickName?: string
  realName?: string
  age?: number | string
  sex?: number
  birthDay?: string
  phone?: string
  classId?: number | null
  className?: string
  createTime?: string
  imagePath?: string
  userLevel?: number
}

export interface StudentUserUpdateRequest {
  nickName: string
}

export interface StudentChangePasswordRequest {
  oldPassword: string
  newPassword: string
  confirmPassword: string
}

export interface UserEventLog {
  id: number
  content: string
  createTime: string
}

export function getCurrentStudentUser(): Promise<ApiResponse<StudentUserInfo>> {
  return post<StudentUserInfo>('/api/student/user/current')
}

export function updateCurrentStudentUser(request: StudentUserUpdateRequest): Promise<ApiResponse<void>> {
  return post<void>('/api/student/user/update', request)
}

export function changeStudentPassword(request: StudentChangePasswordRequest): Promise<ApiResponse<void>> {
  return post<void>('/api/student/user/password/change', request)
}

export function getStudentUserEvents(): Promise<ApiResponse<UserEventLog[]>> {
  return post<UserEventLog[]>('/api/student/user/log')
}
